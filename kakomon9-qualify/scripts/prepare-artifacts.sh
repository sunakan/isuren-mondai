#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${TARGET_DIR}/dist"
# shellcheck source=./artifact-inputs.env
source "${SCRIPT_DIR}/artifact-inputs.env"

log() {
  printf '[kakomon9-qualify:prepare] %s\n' "$*"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_manifest() {
  local output="$1"
  shift
  find "$@" -type f -print0 |
    LC_ALL=C sort -z |
    while IFS= read -r -d '' path; do
      printf '%s  %s\n' "$(sha256_file "${path}")" "${path}"
    done >"${output}"
}

require_full_sha256() {
  local name="$1"
  local value="$2"
  if [[ ! "${value}" =~ ^[0-9a-f]{64}$ ]]; then
    printf 'invalid or unresolved SHA-256 for %s: %s\n' "${name}" "${value}" >&2
    exit 1
  fi
}

download_exact() {
  local name="$1"
  local url="$2"
  local expected="$3"
  local destination="$4"
  require_full_sha256 "${name}" "${expected}"
  if [ -n "${KAKOMON9_ARTIFACT_CACHE_DIR:-}" ]; then
    local cached="${KAKOMON9_ARTIFACT_CACHE_DIR}/${name}"
    if [ -f "${cached}" ] && [ "$(sha256_file "${cached}")" = "${expected}" ]; then
      cp "${cached}" "${destination}"
      return
    fi
  fi
  if [ ! -f "${destination}" ] || [ "$(sha256_file "${destination}")" != "${expected}" ]; then
    local temporary="${destination}.partial"
    rm -f "${temporary}"
    curl --fail --location --proto '=https' --tlsv1.2 --output "${temporary}" "${url}"
    if [ "$(sha256_file "${temporary}")" != "${expected}" ]; then
      printf 'SHA-256 mismatch for %s\n' "${name}" >&2
      rm -f "${temporary}"
      exit 1
    fi
    mv "${temporary}" "${destination}"
  fi
}

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
checkout_dir="${work_dir}/official"
new_dist="${work_dir}/dist"
mkdir -p \
  "${new_dist}/frontend/public" \
  "${new_dist}/source/initial-data/result" \
  "${new_dist}/source/release" \
  "${new_dist}/source/webapp/sql"

log "fetch official commit ${OFFICIAL_MAINTAINED_COMMIT}"
git init --quiet "${checkout_dir}"
git -C "${checkout_dir}" remote add origin "${OFFICIAL_REPOSITORY_URL}"
git -C "${checkout_dir}" fetch --quiet --depth 1 origin "${OFFICIAL_MAINTAINED_COMMIT}"
git -C "${checkout_dir}" checkout --quiet --detach FETCH_HEAD
test "$(git -C "${checkout_dir}" rev-parse HEAD)" = "${OFFICIAL_MAINTAINED_COMMIT}"
test "$(git -C "${checkout_dir}" rev-parse HEAD:webapp/public)" = "${OFFICIAL_FRONTEND_TREE}"

git -C "${checkout_dir}" archive "${OFFICIAL_MAINTAINED_COMMIT}:webapp/public" |
  tar -x -C "${new_dist}/frontend/public"
for path in init.sh sql/00_create_database.sql sql/01_schema.sql sql/02_categories.sql; do
  install -m 0644 "${checkout_dir}/webapp/${path}" "${new_dist}/source/webapp/${path}"
done
for path in image_files_md5_json.txt keywords.tsv result/category_json.txt; do
  install -m 0644 "${checkout_dir}/initial-data/${path}" "${new_dist}/source/initial-data/${path}"
done
chmod 0755 "${new_dist}/source/webapp/init.sh"
install -m 0644 "${checkout_dir}/LICENSE" "${new_dist}/source/LICENSE"

expected_import="importScripts(\"${WORKBOX_IMPORT_URL}\");"
test "$(grep -Fxc "${expected_import}" "${new_dist}/frontend/public/service-worker.js")" -eq 1
test "$(grep -R -a -F -l "${WORKBOX_IMPORT_URL}" "${new_dist}/frontend/public" | wc -l | tr -d ' ')" -eq 1
if grep -R -a -F -q 'navigator.serviceWorker' "${new_dist}/frontend/public"; then
  echo 'official frontend unexpectedly registers a service worker; refusing unchanged deployment' >&2
  exit 1
fi
if grep -R -a -E -q '(catatsuy\.org|isucon\.pw|isuren\.internal)' "${new_dist}/frontend/public"; then
  echo 'official frontend contains an absolute competition/private domain; refusing a rewrite' >&2
  exit 1
fi

download_exact initial.zip "${INITIAL_URL}" "${INITIAL_SHA256}" "${new_dist}/source/release/initial.zip"
download_exact bench1.zip "${BENCH1_URL}" "${BENCH1_SHA256}" "${new_dist}/source/release/bench1.zip"
download_exact initial-data.zip "${INITIAL_DATA_URL}" "${INITIAL_DATA_SHA256}" "${new_dist}/source/release/initial-data.zip"

test "$(unzip -Z1 "${new_dist}/source/release/initial.zip" | wc -l | tr -d ' ')" -eq 20001
if unzip -Z1 "${new_dist}/source/release/initial.zip" |
  grep -Ev '^v3_initial_data(/|/[0-9a-f]{32}\.jpg)$' >/dev/null; then
  echo 'unexpected path in initial.zip' >&2
  exit 1
fi
test "$(unzip -Z1 "${new_dist}/source/release/bench1.zip" | wc -l | tr -d ' ')" -eq 20001
if unzip -Z1 "${new_dist}/source/release/bench1.zip" |
  grep -Ev '^v3_bench1(/|/[0-9a-f]{32}\.jpg)$' >/dev/null; then
  echo 'unexpected path in bench1.zip' >&2
  exit 1
fi
expected_initial_data=$'active_sellers_json.txt\ninitial.sql\nitems_json.txt\nshippings_json.txt\ntransaction_evidences_json.txt\nusers_json.txt'
test "$(unzip -Z1 "${new_dist}/source/release/initial-data.zip" | LC_ALL=C sort)" = "${expected_initial_data}"

(
  cd "${new_dist}/frontend/public"
  write_manifest ../MANIFEST.sha256 .
)
test "$(sha256_file "${new_dist}/frontend/MANIFEST.sha256")" = "${OFFICIAL_FRONTEND_MANIFEST_SHA256}"
cat >"${new_dist}/frontend/SOURCE.txt" <<EOF
repository=${OFFICIAL_REPOSITORY_URL}
commit=${OFFICIAL_MAINTAINED_COMMIT}
tree=${OFFICIAL_FRONTEND_TREE}
license=${OFFICIAL_LICENSE}
copyright=${OFFICIAL_COPYRIGHT}
policy=official prebuilt public tree used directly; frontend source is not managed or rebuilt
workbox_url=${WORKBOX_IMPORT_URL}
workbox_policy=official bytes unchanged; URL only occurs in service-worker.js; no registration call exists
EOF

cat >"${new_dist}/source/SOURCE.txt" <<EOF
repository=${OFFICIAL_REPOSITORY_URL}
commit=${OFFICIAL_MAINTAINED_COMMIT}
release_tag=${RELEASE_TAG}
license=${OFFICIAL_LICENSE}
initial_url=${INITIAL_URL}
initial_sha256=${INITIAL_SHA256}
bench1_url=${BENCH1_URL}
bench1_sha256=${BENCH1_SHA256}
initial_data_url=${INITIAL_DATA_URL}
initial_data_sha256=${INITIAL_DATA_SHA256}
EOF

(
  cd "${new_dist}"
  find . -type f ! -path './MANIFEST.sha256' ! -path './MANIFEST.sha256.sha256' -print0 |
    LC_ALL=C sort -z |
    while IFS= read -r -d '' path; do
      printf '%s  %s\n' "$(sha256_file "${path}")" "${path}"
    done >MANIFEST.sha256
  printf '%s  MANIFEST.sha256\n' "$(sha256_file MANIFEST.sha256)" >MANIFEST.sha256.sha256
)
test "$(sha256_file "${new_dist}/MANIFEST.sha256")" = "${DIST_MANIFEST_SHA256}"

rm -rf "${DIST_DIR}"
mv "${new_dist}" "${DIST_DIR}"
log "prepared ${DIST_DIR}"
log "manifest SHA-256 $(sha256_file "${DIST_DIR}/MANIFEST.sha256")"
