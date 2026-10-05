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

# 无条件在仓库 devShell 内运行：pnpm import（lockfile 生产者）必须与
# package.nix FOD 钉住的 pnpm_11 同版本，避免 PATH 上的其他 pnpm 生成该
# 版本读不了的 lockfile。本仓库升级流程本就依赖 nix（迭代 hash 等），
# 故不提供绕过 devShell 的路径。
if [ -z "${IN_DEV_SHELL:-}" ]; then
  echo "切换到 nix devShell（pin 住的 pnpm_11）内重新执行…" >&2
  exec nix develop "$ROOT" -c env IN_DEV_SHELL=1 bash "$0" "$@"
fi
command -v pnpm >/dev/null 2>&1 || { echo "错误：devShell 中没有 pnpm" >&2; exit 1; }

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
