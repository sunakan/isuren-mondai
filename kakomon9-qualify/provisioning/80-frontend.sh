#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_file "${ARTIFACT_DIR}/source/release/initial.zip"
rm -rf "${APP_ROOT}/webapp/public"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}/webapp/public"
rsync -a "${ARTIFACT_DIR}/frontend/public/" "${APP_ROOT}/webapp/public/"
(
  cd "${APP_ROOT}/webapp/public"
  sha256sum --check "${ARTIFACT_DIR}/frontend/MANIFEST.sha256"
)

initial_images="$(mktemp -d)"
trap 'rm -rf "${initial_images}"' EXIT
unzip -q "${ARTIFACT_DIR}/source/release/initial.zip" -d "${initial_images}"
test -d "${initial_images}/v3_initial_data"
mv "${initial_images}/v3_initial_data" "${APP_ROOT}/webapp/public/upload"
chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}/webapp/public"

install -m 0644 "${ARTIFACT_DIR}/frontend/SOURCE.txt" "${PROVENANCE_DIR}/frontend-source.txt"
install -m 0644 "${ARTIFACT_DIR}/frontend/MANIFEST.sha256" "${PROVENANCE_DIR}/frontend-MANIFEST.sha256"
log "80-frontend.sh: unchanged official prebuilt tree and initial images deployed"
