#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon13-staging"
PUBLIC_DIR="${ISUREN_HOME}/webapp/public"
OFFICIAL_MANIFEST="${SCRIPT_DIR}/official-data.manifest.sha256"

install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PUBLIC_DIR}" "${ISUREN_HOME}/webapp/sql" "${ISUREN_HOME}/webapp/img"
rsync -a --delete "${STAGING_DIR}/frontend/public/" "${PUBLIC_DIR}/"
rsync -a --delete "${STAGING_DIR}/official/webapp/sql/" "${ISUREN_HOME}/webapp/sql/"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${STAGING_DIR}/official/webapp/img/NoImage.jpg" "${ISUREN_HOME}/webapp/img/NoImage.jpg"
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${STAGING_DIR}/bench-linux-arm64" "${ISUREN_HOME}/bench"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PROJECT_ROOT}/upstream/isucon13/LICENSE" "${ISUREN_HOME}/LICENSE"

official_manifest_sha256="$(sha256sum "${OFFICIAL_MANIFEST}" | awk '{print $1}')"
provenance_dir="/usr/local/share/isuren-mondai"
install -d -m 0755 "${provenance_dir}"
cat >"${provenance_dir}/kakomon13-provenance" <<EOF
official_url=https://github.com/isucon/isucon13.git
official_commit=8f6afdc3603f0c661368de4659a7240862f59623
official_data_manifest_sha256=${official_manifest_sha256}
frontend_release_tag=${FRONTEND_RELEASE_TAG}
frontend_release_sha256=${FRONTEND_RELEASE_SHA256}
go=1.26.6
node=24.19.0
yarn=3.2.2
os=ubuntu-26.04
architecture=arm64
hostname=pipe.u.isuren.internal
zone=u.isuren.internal
recipe_commit=${RECIPE_COMMIT}
EOF
sha256sum "${provenance_dir}/kakomon13-packages.tsv" \
  >"${provenance_dir}/kakomon13-packages.tsv.sha256"

log "75-install.sh: done"
