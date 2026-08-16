#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANAGED_FRONTEND="${ROOT_DIR}/upstream/isucon13/frontend"
FRONTEND_DIST="${MANAGED_FRONTEND}/dist"
RELEASE_DIST="${ROOT_DIR}/kakomon13/dist"
OUTPUT="${RELEASE_DIST}/kakomon13-frontend.tar.gz"
OUTPUT_CHECKSUM="${OUTPUT}.sha256"
FRONTEND_MANIFEST="${RELEASE_DIST}/frontend.manifest.sha256"
ASSET_MANIFEST="${ROOT_DIR}/kakomon13/scripts/frontend-assets.manifest.sha256"
EXPECTED_NODE_VERSION="v24.19.0"
OFFICIAL_REPO_URL="https://github.com/isucon/isucon13.git"
OFFICIAL_COMMIT="8f6afdc3603f0c661368de4659a7240862f59623"

checkout=""
stage="$(mktemp -d)"
asset_dir="${MANAGED_FRONTEND}/src/assets/img"
logo="${MANAGED_FRONTEND}/src/components/layout/ISUPipe_yoko_color.png"

cleanup() {
  rm -rf "${asset_dir}" "${stage}"
  rm -f "${logo}"
  if [ -n "${checkout}" ]; then
    rm -rf "${checkout}"
  fi
}
trap cleanup EXIT

test ! -e "${asset_dir}" || {
  echo "error: non-managed frontend image directory already exists: ${asset_dir}" >&2
  exit 1
}
test ! -e "${logo}" || {
  echo "error: non-managed frontend logo already exists: ${logo}" >&2
  exit 1
}

if [ -n "${KAKOMON13_OFFICIAL_SOURCE_DIR:-}" ]; then
  "${ROOT_DIR}/kakomon13/scripts/verify-official-source.sh" >/dev/null
  official_source="${KAKOMON13_OFFICIAL_SOURCE_DIR}"
else
  checkout="$(mktemp -d)"
  git init --quiet "${checkout}"
  git -C "${checkout}" remote add origin "${OFFICIAL_REPO_URL}"
  git -C "${checkout}" sparse-checkout set --cone \
    frontend/src/assets/img frontend/src/components/layout
  git -C "${checkout}" fetch --quiet --depth 1 --filter=blob:none origin "${OFFICIAL_COMMIT}"
  git -C "${checkout}" checkout --quiet "${OFFICIAL_COMMIT}"
  test "$(git -C "${checkout}" rev-parse HEAD)" = "${OFFICIAL_COMMIT}"
  (
    cd "${checkout}"
    shasum -a 256 -c "${ASSET_MANIFEST}"
  )
  official_source="${checkout}"
fi

rsync -a "${official_source}/frontend/src/assets/img/" "${asset_dir}/"
install -m 0644 \
  "${official_source}/frontend/src/components/layout/ISUPipe_yoko_color.png" "${logo}"

run_node() {
  if [ -n "${KAKOMON13_NODE_BIN_DIR:-}" ]; then
    COREPACK_HOME="${stage}/corepack" XDG_CACHE_HOME="${stage}/cache" \
      YARN_CACHE_FOLDER="${stage}/yarn-cache" \
      PATH="${KAKOMON13_NODE_BIN_DIR}:${PATH}" "$@"
  else
    COREPACK_HOME="${stage}/corepack" XDG_CACHE_HOME="${stage}/cache" \
      YARN_CACHE_FOLDER="${stage}/yarn-cache" \
      MISE_CONFIG_FILE="${ROOT_DIR}/kakomon13/scripts/mise.toml" mise exec -- "$@"
  fi
}

if [ "$(run_node node --version)" != "${EXPECTED_NODE_VERSION}" ]; then
  echo "error: Node.js ${EXPECTED_NODE_VERSION} is required" >&2
  exit 1
fi

rm -rf "${FRONTEND_DIST}"
(
  cd "${MANAGED_FRONTEND}"
  run_node corepack yarn install --immutable
  run_node corepack yarn build
)
test -f "${FRONTEND_DIST}/index.html"

mkdir -p "${RELEASE_DIST}" "${stage}/release/public"
(
  cd "${FRONTEND_DIST}"
  find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "${file}"
  done
) >"${FRONTEND_MANIFEST}"

rsync -a "${FRONTEND_DIST}/" "${stage}/release/public/"
install -m 0644 "${ROOT_DIR}/upstream/isucon13/LICENSE" "${stage}/release/LICENSE"
install -m 0644 "${FRONTEND_MANIFEST}" "${stage}/release/frontend.manifest.sha256"
rm -f "${OUTPUT}" "${OUTPUT_CHECKSUM}"
COPYFILE_DISABLE=1 tar -czf "${OUTPUT}" -C "${stage}/release" .
(
  cd "${RELEASE_DIST}"
  shasum -a 256 "$(basename "${OUTPUT}")" >"$(basename "${OUTPUT_CHECKSUM}")"
)

echo "built Vite output: ${FRONTEND_DIST}"
echo "built release output: ${RELEASE_DIST}"
