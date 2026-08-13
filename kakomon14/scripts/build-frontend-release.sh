#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAKOMON14_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${KAKOMON14_DIR}/.." && pwd)"
FRONTEND_DIR="${KAKOMON14_DIR}/upstream/isucon14/frontend"
BENCHRUN_DIR="${KAKOMON14_DIR}/upstream/isucon14/bench/benchrun"
DIST_DIR="${KAKOMON14_DIR}/dist"
ARTIFACT="${DIST_DIR}/kakomon14-frontend.tar.gz"
PNPM_WORKSPACE_YAML="${FRONTEND_DIR}/pnpm-workspace.yaml"

# shellcheck source=../../scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

# 後続のscripts/github-release.shが正しいコミットにタグ付けできるよう、時間のかかる
# pnpmビルドを始める前に「コミット済み」「push済み」を確認しておく(ビルド後に気づくと手戻りが大きい)。
require_clean_worktree
require_pushed_commit "$(git rev-parse HEAD)"

export MISE_CONFIG_FILE="${SCRIPT_DIR}/mise.toml"

# pnpm 10以降はesbuild/@swc/core等のpostinstallスクリプトをデフォルトでブロックする(strictDepBuilds)ため必要。
# upstream/を取り込み元の完全なコピーに保つ方針のため、ビルド後(失敗時含む)に削除する。
trap 'rm -f "${PNPM_WORKSPACE_YAML}"' EXIT
cp "${SCRIPT_DIR}/pnpm-workspace.kakomon14.yaml" "${PNPM_WORKSPACE_YAML}"

mise install
(
  cd "${FRONTEND_DIR}"
  mise exec -- pnpm install --frozen-lockfile
  mise exec -- pnpm run build
)

mkdir -p "${DIST_DIR}"
rm -f "${ARTIFACT}"
tar -C "${FRONTEND_DIR}/build/client" -czf "${ARTIFACT}" .
cp "${BENCHRUN_DIR}/frontend_hashes.json" "${DIST_DIR}/frontend_hashes.json"
cp "${BENCHRUN_DIR}/frontend_files.json" "${DIST_DIR}/frontend_files.json"

echo "built: ${ARTIFACT}"
echo "built: ${DIST_DIR}/frontend_hashes.json"
echo "built: ${DIST_DIR}/frontend_files.json"
