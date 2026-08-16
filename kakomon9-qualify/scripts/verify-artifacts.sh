#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${1:-${TARGET_DIR}/dist}"
# shellcheck source=./artifact-inputs.env
source "${SCRIPT_DIR}/artifact-inputs.env"

sha256_check() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check "$1"
  else
    shasum -a 256 --check "$1"
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

test -f "${DIST_DIR}/MANIFEST.sha256"
test -f "${DIST_DIR}/MANIFEST.sha256.sha256"
(
  cd "${DIST_DIR}"
  sha256_check MANIFEST.sha256.sha256
  sha256_check MANIFEST.sha256
  cd frontend/public
  sha256_check ../MANIFEST.sha256
)

grep -Fxq "commit=${OFFICIAL_MAINTAINED_COMMIT}" "${DIST_DIR}/frontend/SOURCE.txt"
grep -Fxq "tree=${OFFICIAL_FRONTEND_TREE}" "${DIST_DIR}/frontend/SOURCE.txt"
grep -Fxq "workbox_url=${WORKBOX_IMPORT_URL}" "${DIST_DIR}/frontend/SOURCE.txt"
grep -Fxq "initial_sha256=${INITIAL_SHA256}" "${DIST_DIR}/source/SOURCE.txt"
grep -Fxq "bench1_sha256=${BENCH1_SHA256}" "${DIST_DIR}/source/SOURCE.txt"
grep -Fxq "initial_data_sha256=${INITIAL_DATA_SHA256}" "${DIST_DIR}/source/SOURCE.txt"
test "$(sha256_file "${DIST_DIR}/frontend/MANIFEST.sha256")" = "${OFFICIAL_FRONTEND_MANIFEST_SHA256}"
test "$(sha256_file "${DIST_DIR}/source/release/initial.zip")" = "${INITIAL_SHA256}"
test "$(sha256_file "${DIST_DIR}/source/release/bench1.zip")" = "${BENCH1_SHA256}"
test "$(sha256_file "${DIST_DIR}/source/release/initial-data.zip")" = "${INITIAL_DATA_SHA256}"
test "$(sha256_file "${DIST_DIR}/MANIFEST.sha256")" = "${DIST_MANIFEST_SHA256}"
expected_import="importScripts(\"${WORKBOX_IMPORT_URL}\");"
test "$(grep -Fxc "${expected_import}" "${DIST_DIR}/frontend/public/service-worker.js")" -eq 1
test "$(grep -R -a -F -l "${WORKBOX_IMPORT_URL}" "${DIST_DIR}/frontend/public" | wc -l | tr -d ' ')" -eq 1
if grep -R -a -F -q 'navigator.serviceWorker' "${DIST_DIR}/frontend/public"; then
  echo 'frontend service worker registration appeared' >&2
  exit 1
fi
if grep -R -a -E -q '(catatsuy\.org|isucon\.pw|isuren\.internal)' "${DIST_DIR}/frontend/public"; then
  echo 'frontend contains an absolute competition/private domain' >&2
  exit 1
fi

printf '[kakomon9-qualify:verify-artifacts] verified %s\n' "${DIST_DIR}"
