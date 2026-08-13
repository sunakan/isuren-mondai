#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KAKOMON14_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FRONTEND_DIR="${KAKOMON14_DIR}/upstream/isucon14/frontend"
BENCHRUN_DIR="${KAKOMON14_DIR}/upstream/isucon14/bench/benchrun"
DIST_DIR="${KAKOMON14_DIR}/dist"
ARTIFACT="${DIST_DIR}/kakomon14-frontend.tar.gz"
PNPM_WORKSPACE_YAML="${FRONTEND_DIR}/pnpm-workspace.yaml"

export MISE_CONFIG_FILE="${SCRIPT_DIR}/mise.toml"

# provisioning/80-frontend.shと同じ理由(pnpm 10以降のstrictDepBuilds対策)で必要。
# 二重管理を避けるため、AMI側と同じファイルをそのまま参照する。
# upstream/を取り込み元の完全なコピーに保つ方針のため、ビルド後(失敗時含む)に削除する。
trap 'rm -f "${PNPM_WORKSPACE_YAML}"' EXIT
cp "${KAKOMON14_DIR}/provisioning/pnpm-workspace.kakomon14.yaml" "${PNPM_WORKSPACE_YAML}"

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
