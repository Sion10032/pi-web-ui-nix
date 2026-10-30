#!/usr/bin/env bash
# 一键升级 pi-web 到上游最新 tag，自动迭代到构建通过并做验证。
#
# 与 dev/pi-web-ui/upgrade.sh 是姊妹脚本，但 pi-web 走 npm 路线，环节少一截：
# 上游 tag 自带 package-lock.json，仓库内不存 lock 副本，因此没有
# pnpm import 转译、没有 allowBuilds、也没有幽灵依赖（publicHoistPattern）这一说。
#
# 每一轮失败自动修复后重试：
#   1. git ls-remote 探测上游最新 semver tag，写回 package.nix 的 version
#   2. 版本变化时，先把三个 FOD hash 置为 fakeHash，再逐轮从 nix 的
#      "hash mismatch" 报错里解析 got: 写回 package.nix：
#        src      — 上游源码 tarball（fetchFromGitHub）
#        npmDeps  — fetchNpmDeps 的依赖缓存
#        notoFonts— next/font/google 的离线字体 FOD（见 package.nix 注释）
#      先置 fakeHash 是必需的：FOD 输出路径由 (name, outputHash) 决定，
#      沿用旧 hash 时本地 store 里的旧输出会被静默复用、根本不报 mismatch
#      （README「热 store 陷阱」）。
#   3. 成功后验证：nix run .#pi-web -- --version 必须等于目标版本，随后
#      nix flake check -L（除非 --no-flake-check）
#
# 自动修不了、需要人工的情况（脚本会带着构建日志末尾报错退出）：
#   - 上游改了 next/font 配置（换字体族/字重区间/子集）：package.nix 里
#     notoFontsCssUrl 与 mock 的 URL 键要一起改，报错形如
#     "Missing mocked response for URL: ..."
#   - 上游把 --ignore-scripts 跳过的东西挪到了运行期依赖，或新增了别的
#     构建期网络访问
#
# 提交与推送一律留给人工（见 AGENTS.md）。
#
# 用法：./dev/pi-web/upgrade.sh [--no-flake-check]
#   --no-flake-check  跳过 nix flake check -L（CI 的 update-pi-web.yml 用它把全量
#                     验证留给 PR 上的 ci.yml，避免重复跑 VM 测试）
#
# 环境变量：
#   UPGRADE_TARGET_VERSION  指定目标版本（可带 v 前缀），默认自动探测上游最新 stable
#                           tag；显式指定时允许降级/预发布。CI 手动触发时用它透传
#                           workflow_dispatch 的 version 输入。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UPSTREAM_URL="https://github.com/agegr/pi-web"
# 可被测试覆盖
PKG="${PKG:-$ROOT/packages/pi-web/package.nix}"

# nix 的 lib.fakeHash（写死字面量，避免脚本依赖 nix eval）
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# 收敛保护：正常升级最多 3 轮（src、npmDeps、字体 FOD），留一倍余量
MAX_ROUNDS=6
NET_RETRIES=3
TAIL_LINES=40

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/build.log"
# 失败时把构建日志另存一份，便于事后排查（$WORK 会被 trap 清掉）
KEEP_LOG="${KEEP_LOG:-${TMPDIR:-/tmp}/pi-web-upgrade-last.log}"

info() { echo "==> $*"; }
warn() { echo "警告：$*" >&2; }
die() {
  if [ -f "$LOG" ]; then
    cp "$LOG" "$KEEP_LOG" 2>/dev/null && echo "构建日志已保留：$KEEP_LOG" >&2
  fi
  echo "错误：$*" >&2
  exit 1
}

usage() {
  # 打印文件头的注释块（第 1 行 shebang 除外），遇首个非注释行即停
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

# GNU 与 BSD（macOS）sed 的 -i 语义不同，统一走临时文件；用 cat 回写以保留文件权限
sed_inplace() {
  local expr="$1" file="$2" tmp
  tmp=$(mktemp)
  sed "$expr" "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

# ---------- package.nix 读写 ----------

current_version() {
  sed -n 's/^[[:space:]]*version = "\(.*\)";.*/\1/p' "$PKG" | head -1
}

latest_version() {
  git ls-remote --tags --refs "$UPSTREAM_URL" 'v*' 2>/dev/null \
    | sed 's|.*refs/tags/v||' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -1
}

# 目标版本：UPGRADE_TARGET_VERSION 优先（CI 手动触发透传），否则探测上游最新 stable tag
resolve_target() {
  local raw="${UPGRADE_TARGET_VERSION:-}"
  if [ -n "$raw" ]; then
    raw="${raw#v}"
    printf '%s' "$raw" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
      || die "UPGRADE_TARGET_VERSION 不是合法的 semver：${UPGRADE_TARGET_VERSION}"
    printf '%s' "$raw"
    return 0
  fi
  latest_version
}

set_version() {
  sed_inplace "s|^\([[:space:]]*version = \"\)[^\"]*\(\";.*\)$|\1$1\2|" "$PKG"
  [ "$(current_version)" = "$1" ] || die "写入版本号失败：$PKG"
}

# $1 = src | npmDeps | notoFonts
hash_line_pattern() {
  case "$1" in
    src) echo '^[[:space:]]*sha256 = "' ;;
    npmDeps) echo '^[[:space:]]*npmDepsHash = "' ;;
    notoFonts) echo '^[[:space:]]*outputHash = "' ;;
    *) die "未知 hash 属性：$1" ;;
  esac
}

# 写回时的 sed 表达式（与上面的 pattern 一一对应）
hash_set_expr() {
  case "$1" in
    src) echo 's|^\([[:space:]]*sha256 = "\)[^"]*\(";.*\)$|\1@V@\2|' ;;
    npmDeps) echo 's|^\([[:space:]]*npmDepsHash = "\)[^"]*\(";.*\)$|\1@V@\2|' ;;
    notoFonts) echo 's|^\([[:space:]]*outputHash = "\)[^"]*\(";.*\)$|\1@V@\2|' ;;
    *) die "未知 hash 属性：$1" ;;
  esac
}

get_hash() {
  local pat
  pat=$(hash_line_pattern "$1")
  sed -n "s|$pat\([^\"]*\)\";.*|\1|p" "$PKG" | head -1
}

set_hash() {
  local attr="$1" value="$2" pat expr n
  pat=$(hash_line_pattern "$attr")
  n=$(grep -c "$pat" "$PKG" || true)
  [ "$n" -eq 1 ] || die "package.nix 中 $attr 的 hash 行匹配到 $n 处（期望 1），拒绝改写"
  expr=$(hash_set_expr "$attr")
  sed_inplace "${expr//@V@/$value}" "$PKG"
  [ "$(get_hash "$attr")" = "$value" ] || die "写入 $attr hash 失败：$PKG"
}

# ---------- 构建与日志解析 ----------

run_build() {
  local rc=0
  ( cd "$ROOT" && nix build .#pi-web -L --no-link ) >"$LOG" 2>&1 || rc=$?
  return $rc
}

# 从日志中提取 "hash mismatch" 三元组：drv 路径 + got hash
hash_mismatches() {
  awk '
    /hash mismatch in fixed-output derivation/ {
      drv = $0
      sub(/.*derivation ./, "", drv)
      sub(/.:$/, "", drv)
      next
    }
    /^[ \t]*got: / {
      got = $0
      sub(/^[ \t]*got:[ \t]*/, "", got)
      if (drv != "" && got != "") { print drv "\t" got; drv = "" }
      next
    }
  ' "$LOG"
}

hash_attr_from_drv() {
  case "$(basename "$1")" in
    *npm-deps*) echo npmDeps ;;
    *noto-sans-mono*) echo notoFonts ;;
    *-source.drv) echo src ;;
    *) echo "" ;;
  esac
}

# 处理 hash mismatch；有改动返回 0，否则返回 1
handle_hash_mismatch() {
  local drv got attr cur changed=1
  while IFS=$'\t' read -r drv got; do
    [ -n "$drv" ] || continue
    [ -n "$got" ] || continue
    attr=$(hash_attr_from_drv "$drv")
    if [ -z "$attr" ]; then
      warn "无法归因的 hash mismatch：$drv（跳过）"
      continue
    fi
    cur=$(get_hash "$attr")
    if [ "$got" = "$cur" ]; then
      warn "$attr 的 hash 已是 $got，仍报 mismatch（可能是缓存/复用问题）"
      continue
    fi
    info "更新 $attr hash：$cur → $got"
    set_hash "$attr" "$got"
    changed=0
  done < <(hash_mismatches)
  return $changed
}

# next/font 的 mock 只认一个 URL 键：上游改了字体族/字重区间/子集时这里会失配
has_font_mock_mismatch() {
  grep -q 'Missing mocked response for URL' "$LOG"
}

is_transient() {
  grep -qE 'SSL connect error|TLS connect error|failed to download|timed out|Connection reset|502 Bad Gateway|Could not resolve host|Temporary failure in name resolution' "$LOG"
}

show_tail() {
  echo "---- 构建日志末尾（$TAIL_LINES 行）----" >&2
  tail -n "$TAIL_LINES" "$LOG" >&2
  echo "------------------------------------" >&2
}

# ---------- 验证 ----------

verify() {
  local target="$1" skip_flake="${2:-0}" out rc=0
  info "验证：nix run .#pi-web -- --version"
  out=$(cd "$ROOT" && nix run .#pi-web -- --version 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] || die "nix run .#pi-web -- --version 执行失败（exit $rc）"
  out=$(printf '%s' "$out" | tail -1 | tr -d '[:space:]')
  [ "$out" = "$target" ] || die "版本不一致：--version 输出 '$out'，期望 '$target'"
  info "版本正确：$out"

  if [ "$skip_flake" = 1 ]; then
    info "按 --no-flake-check 跳过 nix flake check -L（全量验证交给 PR 上的 ci.yml）"
    return 0
  fi

  info "验证：nix flake check -L（两个 NixOS VM 测试 + 两个 home-manager activation，较慢）"
  rc=0
  ( cd "$ROOT" && nix flake check -L ) 2>&1 | tee "$WORK/flake-check.log" || rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    echo "---- flake check 日志末尾（$TAIL_LINES 行）----" >&2
    tail -n "$TAIL_LINES" "$WORK/flake-check.log" >&2
    die "nix flake check -L 失败（exit $rc）"
  fi
  info "nix flake check -L 通过"
}

# ---------- 主流程 ----------

main() {
  local skip_flake=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --no-flake-check) skip_flake=1 ;;
      *) die "未知参数：$1（脚本不接受版本号，目标版本用 UPGRADE_TARGET_VERSION 指定；见 --help）" ;;
    esac
    shift
  done

  cd "$ROOT"
  [ -f "$PKG" ] || die "找不到 $PKG"

  if ! git diff --quiet -- "$PKG"; then
    warn "$PKG 有未提交改动；脚本会在其上继续修改。建议先 git stash 或提交。"
  fi

  local target current explicit=0
  [ -n "${UPGRADE_TARGET_VERSION:-}" ] && explicit=1
  if [ "$explicit" = 1 ]; then
    info "目标版本由 UPGRADE_TARGET_VERSION 指定：v${UPGRADE_TARGET_VERSION#v}"
  else
    info "探测上游最新 tag…"
  fi
  target=$(resolve_target)
  [ -n "$target" ] || die "无法确定目标版本（网络问题？）"
  current=$(current_version)
  info "目标：v$target；package.nix 当前：v$current"

  if [ "$current" != "$target" ]; then
    if [ "$explicit" = 1 ]; then
      # 显式指定允许升/降级（回退到某个 tag、跟随预发布），只提示不阻拦
      [ "$(printf '%s\n%s\n' "$current" "$target" | sort -V | tail -1)" = "$target" ] \
        || warn "目标版本低于当前版本，将执行降级（显式指定，允许）"
    else
      [ "$(printf '%s\n%s\n' "$current" "$target" | sort -V | tail -1)" = "$target" ] \
        || die "package.nix 的版本（$current）高于上游最新（$target），请人工确认后再跑。"
    fi
    info "更新版本号：$current → $target"
    set_version "$target"

    # 版本变化 → 三个 FOD 的旧 hash 都可能被热 store 静默复用，先置 fakeHash。
    # 字体 FOD 与版本无关（同一条 Google CSS），但一起置 fake 只会多一轮
    # fetch，换来的是不依赖"它刚好没变"这个假设。
    info "重置三个 FOD hash 为 fakeHash（强制真实 fetch，避开热 store 复用）"
    set_hash src "$FAKE_HASH"
    set_hash npmDeps "$FAKE_HASH"
    set_hash notoFonts "$FAKE_HASH"
  else
    info "版本已一致，进入迭代/验证流程（用于修复中断的升级）"
  fi

  local round=0 rc=0 retries=0
  while :; do
    round=$((round + 1))
    [ "$round" -le "$MAX_ROUNDS" ] || { show_tail; die "超过 $MAX_ROUNDS 轮仍未收敛，请人工排查。"; }

    info "第 $round 轮：nix build .#pi-web -L"
    rc=0
    run_build || rc=$?
    if [ "$rc" -eq 0 ]; then
      info "构建通过"
      break
    fi

    if handle_hash_mismatch; then continue; fi

    if has_font_mock_mismatch; then
      show_tail
      die "next/font 的 URL 与 package.nix 里的 mock 键不一致：上游改了字体族/字重区间/子集。请同步更新 notoFontsCssUrl（及其版本号与 outputHash）。"
    fi

    if is_transient && [ "$retries" -lt "$NET_RETRIES" ]; then
      retries=$((retries + 1))
      warn "网络/下载类失败，重试（$retries/$NET_RETRIES）…"
      continue
    fi

    show_tail
    die "构建失败且无法自动修复（exit $rc）。"
  done

  verify "$target" "$skip_flake"

  info "完成：pi-web v$target"
  echo
  echo "本次改动："
  # 用 HEAD 而非索引作基准：package.nix 可能处于已 staged 状态，
  # git diff（工作区 vs 索引）会漏报它的改动
  git diff HEAD --stat -- "$PKG" | sed 's/^/  /'
  echo
  echo "提醒：提交/推送留给人工（AGENTS.md 禁止未经授权 push）。"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
