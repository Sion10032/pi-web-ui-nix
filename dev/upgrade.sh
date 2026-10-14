#!/usr/bin/env bash
# 一键升级 pi-web-ui 到上游最新 tag，自动迭代到构建通过并做全量验证。
#
# 覆盖 README「升级到新上游版本」的全部步骤，每一轮失败自动修复后重试：
#   1. git ls-remote 探测上游最新 semver tag，写回 package.nix 的 version
#   2. 调用 dev/update-pnpm-lock.sh 重新生成 pnpm-lock.yaml
#      （脚本自会进 nix develop，用 pin 住的 pnpm_11 生成）
#   3. 版本或 lockfile 变化时，先把两个 FOD hash 置为 fakeHash，再逐轮从
#      nix 的 "hash mismatch" 报错里解析 got: 写回 package.nix。
#      先置 fakeHash 是必需的：FOD 输出路径由 (name, outputHash) 决定，
#      沿用旧 hash 时本地 store 里的旧输出会被静默复用、根本不报 mismatch
#      （README「热 store 陷阱」）。
#   4. 解析 ERR_PNPM_IGNORED_BUILDS 的 "Ignored build scripts:" 列表
#      （pnpm ≥11 默认 strictDepBuilds=true，未批准的依赖脚本会让 install 硬失败），
#      并入 pnpm-workspace.yaml 的 allowBuilds
#   5. 解析 TS2307 "Cannot find module 'X'"：若 X 存在于 pnpm-lock.yaml，
#      说明是上游在 npm 扁平布局下测不出的幽灵依赖，把它的 scope 加进
#      pnpm-workspace.yaml 的 publicHoistPattern 后重试；同一模块再次失败即
#      中止，避免死循环
#   6. 成功后验证：nix run .# -- --version 必须等于目标版本，随后 nix flake check -L
#
# allowBuilds / publicHoistPattern 都写在仓库根的 pnpm-workspace.yaml（数据文件，
# package.nix 的 postPatch 只负责把它拷进源码树），所以升级时只改 YAML、不动 Nix
# 源码；两项都是安装期配置、不进 pnpm-lock.yaml，lockfile 仅在依赖版本变化时重新生成。
#
# 提交与推送一律留给人工（见 AGENTS.md）。
#
# 用法：./dev/upgrade.sh [--no-flake-check]
#   --no-flake-check  跳过 nix flake check -L（CI 的 update.yml 用它把全量验证留给
#                     PR 上的 ci.yml，避免重复跑 VM 测试）
#
# 环境变量：
#   UPGRADE_TARGET_VERSION  指定目标版本（可带 v 前缀），默认自动探测上游最新 stable
#                           tag；显式指定时允许降级/预发布。CI 手动触发时用它透传
#                           workflow_dispatch 的 version 输入。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
UPSTREAM_URL="https://github.com/xing-shuyin/pi-web-ui"
# 可被测试覆盖
PKG="${PKG:-$ROOT/package.nix}"
LOCK="${LOCK:-$ROOT/pnpm-lock.yaml}"
WORKSPACE_YAML="${WORKSPACE_YAML:-$ROOT/pnpm-workspace.yaml}"

# nix 的 lib.fakeHash（写死字面量，避免脚本依赖 nix eval）
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
# 收敛保护：正常升级最多 4~5 轮（src hash、deps hash、allowBuilds、幽灵 import）
MAX_ROUNDS=12
NET_RETRIES=3
TAIL_LINES=40

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LOG="$WORK/build.log"
# 失败时把构建日志另存一份，便于事后排查（$WORK 会被 trap 清掉）
KEEP_LOG="${KEEP_LOG:-${TMPDIR:-/tmp}/pi-web-ui-upgrade-last.log}"

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

# macOS 没有 sha256sum（对应 shasum -a 256）
file_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
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

# $1 = src | pnpmDeps
hash_line_pattern() {
  case "$1" in
    src) echo '^[[:space:]]*sha256 = "' ;;
    pnpmDeps) echo '^[[:space:]]*hash = "' ;;
    *) die "未知 hash 属性：$1" ;;
  esac
}

get_hash() {
  local pat
  pat=$(hash_line_pattern "$1")
  sed -n "s|$pat\([^\"]*\)\";.*|\1|p" "$PKG" | head -1
}

set_hash() {
  local attr="$1" value="$2" pat n
  pat=$(hash_line_pattern "$attr")
  n=$(grep -c "$pat" "$PKG" || true)
  [ "$n" -eq 1 ] || die "package.nix 中 $attr 的 hash 行匹配到 $n 处（期望 1），拒绝改写"
  if [ "$attr" = src ]; then
    sed_inplace "s|^\([[:space:]]*sha256 = \"\)[^\"]*\(\";.*\)$|\1$value\2|" "$PKG"
  else
    sed_inplace "s|^\([[:space:]]*hash = \"\)[^\"]*\(\";.*\)$|\1$value\2|" "$PKG"
  fi
  [ "$(get_hash "$attr")" = "$value" ] || die "写入 $attr hash 失败：$PKG"
}

# 结构断言：pnpm-workspace.yaml 顶层键必须顶格、条目必须两空格缩进。
# 缩进写错会让键变成上一个映射的子键，而 YAML 仍「看起来对」。
assert_workspace_yaml_shape() {
  local bad
  bad=$(awk '
    /^[A-Za-z]/ {
      if ($0 ~ /^[A-Za-z][A-Za-z0-9_-]*:([ \t].*)?$/) next
      print NR ": " $0
      next
    }
    /^[ \t]+/ {
      if ($0 ~ /^  ("[^"]+"|[A-Za-z0-9._@\/-]+): true[ \t]*$/) next
      if ($0 ~ /^  - "[^"]+"[ \t]*$/) next
      if ($0 ~ /^  #/) next
      print NR ": " $0
    }
  ' "$WORKSPACE_YAML")
  [ -z "$bad" ] || die "pnpm-workspace.yaml 格式异常（顶层键顶格、条目两空格缩进）：$bad"
}

# YAML 键名按需加引号（@ 开头等保留字符必须引；现有文件同一规则）
quote_key() {
  if [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; then printf '%s' "$1"; else printf '"%s"' "$1"; fi
}

# 读取 allowBuilds 块中已有的键（块内注释跳过，顶格非注释行结束块）
existing_allow_builds() {
  awk '
    /^allowBuilds:[ \t]*$/ { in_block = 1; next }
    in_block && /^[^ \t#]/ { in_block = 0 }
    in_block && /^[ \t]+/ {
      line = $0
      sub(/^[ \t]+/, "", line)
      sub(/:[ \t]*true[ \t]*$/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "") print line
    }
  ' "$WORKSPACE_YAML"
}

# 读取 publicHoistPattern 块中已有的模式
existing_hoist_patterns() {
  awk '
    /^publicHoistPattern:[ \t]*$/ { in_block = 1; next }
    in_block && /^[^ \t#]/ { in_block = 0 }
    in_block && /^[ \t]*-[ \t]*/ {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      sub(/[ \t]+$/, "", line)
      gsub(/^"|"$/, "", line)
      if (line != "") print line
    }
  ' "$WORKSPACE_YAML"
}

# 把 names（每行一个）并入 allowBuilds 块，重写为排序后的映射
allow_builds_add() {
  local names_file="$1" merged body tmp
  merged=$( { existing_allow_builds; cat "$names_file"; } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u )
  body="$WORK/allow-builds.body"
  : > "$body"
  while IFS= read -r k; do
    [ -n "$k" ] && printf '  %s: true\n' "$(quote_key "$k")" >> "$body"
  done <<< "$merged"
  tmp="$WORK/pnpm-workspace.yaml.allow"
  awk -v body="$body" '
    /^allowBuilds:[ \t]*$/ {
      print
      while ((getline l < body) > 0) print l
      close(body)
      in_block = 1
      next
    }
    in_block && /^[^ \t#]/ { in_block = 0 }
    in_block && /^[ \t]*#/ { print; next }
    in_block && /^[ \t]/ { next }
    { print }
  ' "$WORKSPACE_YAML" > "$tmp" && mv "$tmp" "$WORKSPACE_YAML"
  assert_workspace_yaml_shape
}

# 把 pattern 加入 publicHoistPattern 块（去重、排序）；块不存在时追加到文件末尾
public_hoist_add() {
  local pattern="$1" merged body tmp
  merged=$( { existing_hoist_patterns; printf '%s\n' "$pattern"; } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u )
  body="$WORK/hoist.body"
  : > "$body"
  while IFS= read -r p; do
    [ -n "$p" ] && printf '  - "%s"\n' "$p" >> "$body"
  done <<< "$merged"
  tmp="$WORK/pnpm-workspace.yaml.hoist"
  awk -v body="$body" '
    /^publicHoistPattern:[ \t]*$/ {
      print
      while ((getline l < body) > 0) print l
      close(body)
      in_block = 1
      found = 1
      next
    }
    in_block && /^[^ \t#]/ { in_block = 0 }
    in_block && /^[ \t]*#/ { print; next }
    in_block && /^[ \t]/ { next }
    { print }
    END {
      if (!found) {
        print "publicHoistPattern:"
        while ((getline l < body) > 0) print l
        close(body)
      }
    }
  ' "$WORKSPACE_YAML" > "$tmp" && mv "$tmp" "$WORKSPACE_YAML"
  grep -qF -- "- \"$pattern\"" "$WORKSPACE_YAML" || die "写入 publicHoistPattern 失败：$pattern"
  assert_workspace_yaml_shape
}

# ---------- 构建与日志解析 ----------

run_build() {
  local rc=0
  ( cd "$ROOT" && nix build .#pi-web-ui -L --no-link ) >"$LOG" 2>&1 || rc=$?
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
    *pnpm-deps*) echo pnpmDeps ;;
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

# 处理 ERR_PNPM_IGNORED_BUILDS；有改动返回 0
handle_ignored_builds() {
  grep -q 'Ignored build scripts:' "$LOG" || return 1
  local names_file="$WORK/ignored-names"
  grep -o 'Ignored build scripts: .*' "$LOG" \
    | head -1 \
    | sed 's/^Ignored build scripts: //; s/\.$//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | sed '/^$/d' | LC_ALL=C sort -u > "$names_file"
  [ -s "$names_file" ] || return 1
  info "批准依赖构建脚本：$(tr '\n' ' ' < "$names_file")"
  allow_builds_add "$names_file"
  return 0
}

# 打印日志里的 TS2307 上下文，便于定位幽灵依赖类失败
show_ts2307_context() {
  [ -f "$LOG" ] || return 0
  echo "---- 构建日志中的 TS2307 ----" >&2
  grep -n 'error TS2307' "$LOG" | head -10 >&2
  echo "----------------------------" >&2
}

# 处理 TS2307 幽灵依赖；有改动返回 0
# 进度保护：同一模块第二次失败即判定为无进展（由调用方传入 seen 文件）
handle_ts2307() {
  local seen_file="$1"
  local mods pattern scope changed=1
  mods=$(grep -o "Cannot find module '[^']*'" "$LOG" | sed "s/Cannot find module '//; s/'$//" | LC_ALL=C sort -u)
  [ -n "$mods" ] || return 1
  while IFS= read -r mod; do
    [ -n "$mod" ] || continue
    if grep -qxF "$mod" "$seen_file"; then
      show_ts2307_context
      die "模块 $mod 的 TS2307 在自动修复后仍然出现，已停止（避免死循环）。请人工排查：可能是上游真的缺依赖，需要显式加进 package.json/lockfile。"
    fi
    echo "$mod" >> "$seen_file"
    # 幽灵依赖的前提：包确实在 lockfile 的依赖树里
    if ! grep -qF "'$mod@" "$LOCK"; then
      show_ts2307_context
      die "找不到模块 $mod，且它不在 pnpm-lock.yaml 的依赖树中（上游漏声明且未安装），无法靠 hoisting 修复。"
    fi
    if [[ "$mod" == @*/* ]]; then
      scope="${mod%%/*}"
      pattern="$scope/*"
    else
      pattern="$mod"
    fi
    if grep -qF "  - \"$pattern\"" "$WORKSPACE_YAML"; then
      show_ts2307_context
      die "模块 $mod 已在 publicHoistPattern（$pattern）中却仍解析失败，无法自动修复。"
    fi
    info "幽灵依赖 $mod → 加入 publicHoistPattern：$pattern"
    public_hoist_add "$pattern"
    changed=0
  done <<< "$mods"
  return $changed
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
  info "验证：nix run .# -- --version"
  out=$(cd "$ROOT" && nix run .# -- --version 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] || die "nix run .# -- --version 执行失败（exit $rc）"
  out=$(printf '%s' "$out" | tail -1 | tr -d '[:space:]')
  [ "$out" = "$target" ] || die "版本不一致：--version 输出 '$out'，期望 '$target'"
  info "版本正确：$out"

  if [ "$skip_flake" = 1 ]; then
    info "按 --no-flake-check 跳过 nix flake check -L（全量验证交给 PR 上的 ci.yml）"
    return 0
  fi

  info "验证：nix flake check -L（NixOS VM 测试 + home-manager activation，较慢）"
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
  [ -f "$LOCK" ] || die "找不到 $LOCK"
  [ -f "$WORKSPACE_YAML" ] || die "找不到 $WORKSPACE_YAML"
  # package.nix 用 cp ${./pnpm-workspace.yaml} 引入该文件，而 nix 的 flake 源只包含
  # git 跟踪的文件：未 git add 时会报含糊的 'not tracked by Git' 求值错误
  git ls-files --error-unmatch "$WORKSPACE_YAML" >/dev/null 2>&1 \
    || die "$WORKSPACE_YAML 未被 git 跟踪；请先 git add（nix 只认 git 跟踪的文件）"
  # 校验 package.nix 确实把该文件拷进了构建：否则本脚本对 YAML 的修改不会生效，
  # 幽灵依赖自动修复会静默失效（本轮迭代就会白跑）。
  grep -qE 'cp .*pnpm-workspace\.yaml' "$PKG" \
    || die "$PKG 的 postPatch 没有把 pnpm-workspace.yaml 拷进源码树（应形如 cp \${./pnpm-workspace.yaml} pnpm-workspace.yaml）；修改 YAML 不会生效，拒绝继续"

  if ! git diff --quiet -- "$PKG" "$LOCK" "$WORKSPACE_YAML"; then
    warn "$PKG / $LOCK / $WORKSPACE_YAML 有未提交改动；脚本会在其上继续修改。建议先 git stash 或提交。"
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
  else
    info "版本已一致，进入迭代/验证流程（用于修复中断的升级）"
  fi

  info "重新生成 pnpm-lock.yaml…"
  local lock_before lock_after
  lock_before=$(file_hash "$LOCK")
  ./dev/update-pnpm-lock.sh
  lock_after=$(file_hash "$LOCK")

  # 版本或 lockfile 变化 → 两个 FOD 的旧 hash 都可能被热 store 静默复用，先置 fakeHash
  if [ "$current" != "$target" ] || [ "$lock_before" != "$lock_after" ]; then
    info "重置两个 FOD hash 为 fakeHash（强制真实 fetch，避开热 store 复用）"
    set_hash src "$FAKE_HASH"
    set_hash pnpmDeps "$FAKE_HASH"
  fi

  : > "$WORK/ts2307-seen"
  local round=0 rc=0 retries=0
  while :; do
    round=$((round + 1))
    [ "$round" -le "$MAX_ROUNDS" ] || { show_tail; die "超过 $MAX_ROUNDS 轮仍未收敛，请人工排查。"; }

    info "第 $round 轮：nix build .#pi-web-ui -L"
    rc=0
    run_build || rc=$?
    if [ "$rc" -eq 0 ]; then
      info "构建通过"
      break
    fi

    if handle_hash_mismatch; then continue; fi
    if handle_ignored_builds; then continue; fi
    if handle_ts2307 "$WORK/ts2307-seen"; then continue; fi

    if is_transient && [ "$retries" -lt "$NET_RETRIES" ]; then
      retries=$((retries + 1))
      warn "网络/下载类失败，重试（$retries/$NET_RETRIES）…"
      continue
    fi

    show_tail
    die "构建失败且无法自动修复（exit $rc）。"
  done

  verify "$target" "$skip_flake"

  info "完成：pi-web-ui v$target"
  echo
  echo "本次改动："
  # 用 HEAD 而非索引作基准：pnpm-workspace.yaml 通常是已 staged 状态，
  # git diff（工作区 vs 索引）会漏报它的改动
  git diff HEAD --stat -- "$PKG" "$LOCK" "$WORKSPACE_YAML" | sed 's/^/  /'
  echo
  echo "提醒：提交/推送留给人工（AGENTS.md 禁止未经授权 push）。"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
