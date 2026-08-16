#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../scripts/artifact-inputs.env
source "${PROJECT_ROOT}/kakomon9-qualify/scripts/artifact-inputs.env"

if [ "${OUTPUT_DIR:-}" != "${ARTIFACT_DIR}" ]; then
  OUTPUT_DIR="${ARTIFACT_DIR}"
  export OUTPUT_DIR
fi
bash "${PROJECT_ROOT}/kakomon9-qualify/scripts/prepare-artifacts.sh"

require_file "${ARTIFACT_DIR}/MANIFEST.sha256"
require_file "${ARTIFACT_DIR}/MANIFEST.sha256.sha256"
(
  cd "${ARTIFACT_DIR}"
  sha256sum --check MANIFEST.sha256.sha256
  sha256sum --check MANIFEST.sha256
  cd frontend/public
  sha256sum --check ../MANIFEST.sha256
)

grep -Fxq 'commit=ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0' "${ARTIFACT_DIR}/frontend/SOURCE.txt"
grep -Fxq 'tree=a427d1c0adf7e8875d7dfbdca352de5a199edd69' "${ARTIFACT_DIR}/frontend/SOURCE.txt"
grep -Fxq "initial_sha256=${INITIAL_SHA256}" "${ARTIFACT_DIR}/source/SOURCE.txt"
grep -Fxq "bench1_sha256=${BENCH1_SHA256}" "${ARTIFACT_DIR}/source/SOURCE.txt"
grep -Fxq "initial_data_sha256=${INITIAL_DATA_SHA256}" "${ARTIFACT_DIR}/source/SOURCE.txt"
test "$(sha256sum "${ARTIFACT_DIR}/frontend/MANIFEST.sha256" | awk '{print $1}')" = "${OFFICIAL_FRONTEND_MANIFEST_SHA256}"
test "$(sha256sum "${ARTIFACT_DIR}/source/release/initial.zip" | awk '{print $1}')" = "${INITIAL_SHA256}"
test "$(sha256sum "${ARTIFACT_DIR}/source/release/bench1.zip" | awk '{print $1}')" = "${BENCH1_SHA256}"
test "$(sha256sum "${ARTIFACT_DIR}/source/release/initial-data.zip" | awk '{print $1}')" = "${INITIAL_DATA_SHA256}"
test "$(sha256sum "${ARTIFACT_DIR}/MANIFEST.sha256" | awk '{print $1}')" = "${DIST_MANIFEST_SHA256}"
test "$(grep -Fxc 'importScripts("https://storage.googleapis.com/workbox-cdn/releases/4.3.1/workbox-sw.js");' "${ARTIFACT_DIR}/frontend/public/service-worker.js")" -eq 1
test "$(grep -R -a -F -l 'https://storage.googleapis.com/workbox-cdn/releases/4.3.1/workbox-sw.js' "${ARTIFACT_DIR}/frontend/public" | wc -l)" -eq 1
if grep -R -a -F -q 'navigator.serviceWorker' "${ARTIFACT_DIR}/frontend/public"; then
  echo 'frontend service worker registration appeared' >&2
  exit 1
fi

log "05-artifacts.sh: official inputs fetched and verified in AMI"
