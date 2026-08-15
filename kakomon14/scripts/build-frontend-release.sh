#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAKOMON14_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${KAKOMON14_DIR}/.." && pwd)"
FRONTEND_DIR="${REPO_ROOT}/upstream/isucon14/frontend"
BENCHRUN_DIR="${REPO_ROOT}/upstream/isucon14/bench/benchrun"
DIST_DIR="${KAKOMON14_DIR}/dist"
ARTIFACT="${DIST_DIR}/kakomon14-frontend.tar.gz"
PNPM_WORKSPACE_YAML="${FRONTEND_DIR}/pnpm-workspace.yaml"
FRONTEND_PUBLIC_DIR="${FRONTEND_DIR}/public"
# provisioning/50-source.shのISUCON14_REPO_URL/ISUCON14_COMMITと同じ値を使う。
ISUCON14_REPO_URL="https://github.com/isucon/isucon14.git"
ISUCON14_COMMIT="53f8b627e040c30ebec600457c6c97da008b84b0"

# shellcheck source=../../scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

# 後続のscripts/github-release.shが正しいコミットにタグ付けできるよう、時間のかかる
# pnpmビルドを始める前に「コミット済み」「push済み」を確認しておく(ビルド後に気づくと手戻りが大きい)。
require_clean_worktree
require_pushed_commit "$(git rev-parse HEAD)"

export MISE_CONFIG_FILE="${SCRIPT_DIR}/mise.toml"

PUBLIC_CHECKOUT_DIR="$(mktemp -d)"
# pnpm-workspace.yaml: pnpm 10以降はesbuild/@swc/core等のpostinstallスクリプトをデフォルトで
# ブロックする(strictDepBuilds)ため必要。
# public: frontend/publicは画像等の静的アセットで、リポジトリを重くするだけで編集対象にならない
# ためupstream/isucon14に取り込んでいない(upstream/isucon14/NOTICE.md参照)。Vite/Remixのビルドは
# public配下をそのままbuild/clientにコピーするだけの仕組みのため、ビルド成果物に含めるには
# ビルド前に配置しておく必要がある。
# upstream/を取り込み元の完全なコピーに保つ方針のため、いずれもビルド後(失敗時含む)に削除する。
trap 'rm -f "${PNPM_WORKSPACE_YAML}"; rm -rf "${FRONTEND_PUBLIC_DIR}" "${PUBLIC_CHECKOUT_DIR}"' EXIT
cp "${SCRIPT_DIR}/pnpm-workspace.kakomon14.yaml" "${PNPM_WORKSPACE_YAML}"

git init --quiet "${PUBLIC_CHECKOUT_DIR}"
git -C "${PUBLIC_CHECKOUT_DIR}" remote add origin "${ISUCON14_REPO_URL}"
git -C "${PUBLIC_CHECKOUT_DIR}" sparse-checkout set --cone frontend/public
git -C "${PUBLIC_CHECKOUT_DIR}" fetch --quiet --depth 1 --filter=blob:none origin "${ISUCON14_COMMIT}"
git -C "${PUBLIC_CHECKOUT_DIR}" checkout --quiet "${ISUCON14_COMMIT}"
cp -R "${PUBLIC_CHECKOUT_DIR}/frontend/public" "${FRONTEND_PUBLIC_DIR}"

mise install
(
  cd "${FRONTEND_DIR}"
  mise exec -- pnpm install --frozen-lockfile
  mise exec -- pnpm run build
)

mkdir -p "${DIST_DIR}"
rm -f "${ARTIFACT}"
# COPYFILE_DISABLE=1: macOSのtarはデフォルトで拡張属性/リソースフォークを`._*`という
# AppleDoubleファイルとして同梱してしまう(Linux上のtarでは不要だが無害なので常に設定する)。
COPYFILE_DISABLE=1 tar -C "${FRONTEND_DIR}/build/client" -czf "${ARTIFACT}" .
cp "${BENCHRUN_DIR}/frontend_hashes.json" "${DIST_DIR}/frontend_hashes.json"
cp "${BENCHRUN_DIR}/frontend_files.json" "${DIST_DIR}/frontend_files.json"

echo "built: ${ARTIFACT}"
echo "built: ${DIST_DIR}/frontend_hashes.json"
echo "built: ${DIST_DIR}/frontend_files.json"
