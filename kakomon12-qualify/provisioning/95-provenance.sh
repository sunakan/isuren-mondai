#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../scripts/artifact-inputs.env
source "$(cd "${SCRIPT_DIR}/.." && pwd)/scripts/artifact-inputs.env"

MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
cat >"${PROVENANCE_DIR}/recipe.txt" <<EOF
canonical_slug=kakomon12-qualify
official_repository=${OFFICIAL_REPOSITORY_URL}
official_commit=${OFFICIAL_COMMIT}
license=${OFFICIAL_LICENSE}; ${OFFICIAL_COPYRIGHT}
region=ap-northeast-1
base_ami=${BASE_AMI_ID}
base_image=Ubuntu 26.04 LTS arm64 release serial ${BASE_IMAGE_SERIAL}
application=127.0.0.1:3000 (isuports-go.service)
auth=127.0.0.1:3001 (blackauth.service)
application_environment=/home/isuren/env.sh
benchmark=/home/isuren/bin/bench
benchmark_wrapper=none; invoke the official benchmarker directly and read its final "pass"/"score" text log plus exit status (-exit-error-on-fail)
public_hostname_wildcard=*.t.isuren.internal
admin_hostname=admin.t.isuren.internal
tls=fixed self-signed wildcard cert generated once at build time and retained in the sealed image plus the OS trust store (see 90-nginx.sh)
frontend=official prebuilt public/ tree; source not managed; no rebuild
reset=POST /initialize (webapp/sql/init.sh); admin DB DDL applied once at provisioning, initial_data/*.db retained as a runtime asset
initial_data_release_tag=${INITIAL_DATA_RELEASE_TAG}
initial_data_asset=${INITIAL_DATA_ASSET_NAME}
initial_data_sha256=${INITIAL_DATA_SHA256}
EOF

runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" exec -- go version >"${PROVENANCE_DIR}/go-version.txt"
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"${PROVENANCE_DIR}/packages.tsv"
sha256sum "${ISUREN_HOME}/webapp/go/isuports" "${ISUREN_HOME}/blackauth/blackauth" "${ISUREN_HOME}/bin/bench" \
  >"${PROVENANCE_DIR}/binaries.sha256"
install -m 0644 "${ARTIFACT_DIR}/key-identity.txt" "${PROVENANCE_DIR}/key-identity.txt"

# ARTIFACT_DIR held a raw copy of the JWT private key (fetched for staging in
# 05-artifacts.sh); its only deployed copy should be /home/isuren/blackauth's,
# which 71-blackauth-go.sh already built from. Remove the staging copy now
# that provenance has recorded its checksum.
rm -rf "${ARTIFACT_DIR}"

log "95-provenance.sh: durable package and source evidence recorded"
