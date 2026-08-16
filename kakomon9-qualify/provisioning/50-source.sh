#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_file "${MANAGED_SOURCE_DIR}/NOTICE.md"
require_file "${MANAGED_SOURCE_DIR}/LICENSE"
require_file "${ARTIFACT_DIR}/source/release/initial-data.zip"
require_file "${ARTIFACT_DIR}/source/release/bench1.zip"
require_file "${PROVISIONING_DIR}/runtime/env.sh"

rm -rf "${APP_ROOT}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}"
rsync -a "${MANAGED_SOURCE_DIR}/" "${APP_ROOT}/"
rsync -a "${ARTIFACT_DIR}/source/webapp/" "${APP_ROOT}/webapp/"
rsync -a "${ARTIFACT_DIR}/source/initial-data/" "${APP_ROOT}/initial-data/"

unzip -q "${ARTIFACT_DIR}/source/release/initial-data.zip" -d "${APP_ROOT}/initial-data/result"
require_file "${APP_ROOT}/initial-data/result/initial.sql"
install -m 0644 "${APP_ROOT}/initial-data/result/initial.sql" "${APP_ROOT}/webapp/sql/90_initial.sql"
rm -f "${APP_ROOT}/initial-data/result/initial.sql"

bench_images="$(mktemp -d)"
trap 'rm -rf "${bench_images}"' EXIT
unzip -q "${ARTIFACT_DIR}/source/release/bench1.zip" -d "${bench_images}"
test -d "${bench_images}/v3_bench1"
mv "${bench_images}/v3_bench1" "${APP_ROOT}/initial-data/images"

install -m 0644 "${ARTIFACT_DIR}/MANIFEST.sha256" "${PROVENANCE_DIR}/artifact-MANIFEST.sha256"
install -m 0644 "${ARTIFACT_DIR}/MANIFEST.sha256.sha256" "${PROVENANCE_DIR}/artifact-MANIFEST.sha256.sha256"
install -m 0644 "${ARTIFACT_DIR}/source/SOURCE.txt" "${PROVENANCE_DIR}/source-assets.txt"
install -m 0644 "${MANAGED_SOURCE_DIR}/NOTICE.md" "${PROVENANCE_DIR}/managed-source-NOTICE.md"
install -m 0644 "${MANAGED_SOURCE_DIR}/LICENSE" "${PROVENANCE_DIR}/LICENSE"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${MANAGED_SOURCE_DIR}/LICENSE" "/home/${ISUREN_USER}/LICENSE"
# This is the exact public DB environment shipped by the official provisioning
# role. Keeping it as a shell-compatible EnvironmentFile makes the Application
# service and an interactive practice shell share one contract.
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PROVISIONING_DIR}/runtime/env.sh" "/home/${ISUREN_USER}/env.sh"

chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}"
log "50-source.sh: managed source and exact data assets deployed"
