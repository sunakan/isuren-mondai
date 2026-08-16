#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../scripts/artifact-inputs.env
source "${PROJECT_ROOT}/kakomon9-qualify/scripts/artifact-inputs.env"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
cat >"${PROVENANCE_DIR}/recipe.txt" <<EOF
canonical_slug=kakomon9-qualify
official_repository=https://github.com/isucon/isucon9-qualify.git
historical_original_commit=34b3e785ebdd97d5c39a1263cbf56d1ae5e3ef91
maintained_baseline_commit=ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0
frontend_tree=a427d1c0adf7e8875d7dfbdca352de5a199edd69
frontend_manifest_sha256=${OFFICIAL_FRONTEND_MANIFEST_SHA256}
dist_manifest_sha256=${DIST_MANIFEST_SHA256}
license=MIT; Copyright 2019 ISUCON9 Contributors
region=ap-northeast-1
base_ami=ami-0df1235688731e6cc
base_image=Ubuntu 26.04 LTS arm64 release serial 20260806
application=127.0.0.1:8000
public_hostname=${APP_HOST}
application_compat_hostname=${APP_COMPAT_HOST}
payment_hostname_mapping=${PAYMENT_HOSTS}; loopback-resolved but not persistent services
shipment_hostname_mapping=${SHIPMENT_HOSTS}; loopback-resolved but not persistent services
payment=localhost:5555; benchmark-owned one-shot mock
shipment=localhost:7001; benchmark-owned one-shot mock
reset=POST /initialize
restart=not implemented; exact official command/API not confirmed
frontend=official prebuilt public tree; source not managed; no rebuild
EOF

runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" exec -- go version >"${PROVENANCE_DIR}/go-version.txt"
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"${PROVENANCE_DIR}/packages.tsv"
sha256sum "${APP_ROOT}/bin/isucari" "${APP_ROOT}/bin/bench" >"${PROVENANCE_DIR}/binaries.sha256"
find "${PROVENANCE_DIR}" -type f ! -name MANIFEST.sha256 -printf '%P\0' |
  LC_ALL=C sort -z |
  xargs -0 -I{} sha256sum "${PROVENANCE_DIR}/{}" >"${PROVENANCE_DIR}/MANIFEST.sha256"

log "95-provenance.sh: durable package and source evidence recorded"
