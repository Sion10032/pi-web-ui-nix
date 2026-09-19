#!/usr/bin/env bash
# 依据 package.nix 中的 version，从上游 GitHub tag 重新生成 pnpm-lock.yaml。
#
# 流程：下载该 tag 的 package.json + package-lock.json → pnpm import 转译
#（版本忠实保留，缺失的 integrity 由 registry 元数据补齐）→ 覆盖仓库的
# pnpm-lock.yaml。之后还需迭代 package.nix 里的 src / pnpmDeps 两个 hash，
# 见 README「Upgrading to a new upstream version」。
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# 从 package.nix 提取 version（单一来源：let version = "…";）
VERSION=$(sed -n 's/^[[:space:]]*version = "\(.*\)";.*/\1/p' "$ROOT/package.nix" | head -1)
if [ -z "${VERSION:-}" ]; then
  echo "错误：无法从 $ROOT/package.nix 提取 version" >&2
  exit 1
fi

# pnpm 不在 PATH 时，用仓库 devShell（内含 pin 住的 pnpm_12）重跑本脚本
if ! command -v pnpm >/dev/null 2>&1; then
  if [ -n "${IN_DEV_SHELL:-}" ]; then
    echo "错误：devShell 中也没有 pnpm" >&2
    exit 1
  fi
  echo "pnpm 不在 PATH，切换到 nix devShell 重新执行…" >&2
  exec nix develop "$ROOT" -c env IN_DEV_SHELL=1 bash "$0" "$@"
fi

BASE="https://raw.githubusercontent.com/xing-shuyin/pi-web-ui/v${VERSION}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "==> pi-web-ui v${VERSION}（pnpm $(pnpm --version)）"
echo "==> 下载上游 package.json / package-lock.json"
curl -fsSL -o "$TMP/package.json" "$BASE/package.json"
curl -fsSL -o "$TMP/package-lock.json" "$BASE/package-lock.json"

echo "==> pnpm import"
(cd "$TMP" && pnpm import)

cp "$TMP/pnpm-lock.yaml" "$ROOT/pnpm-lock.yaml"
echo "==> 已更新 $ROOT/pnpm-lock.yaml"

# 若在 git 仓库内，展示变化概览
git -C "$ROOT" diff --stat -- pnpm-lock.yaml 2>/dev/null || true
