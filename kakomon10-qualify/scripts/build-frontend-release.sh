#!/usr/bin/env bash
set -euo pipefail

# Why this script needs a live MySQL + webapp (unlike other targets'
# frontend-only release builds): bench/scenario/verifyWithSnapshot.go replays
# recorded request/response snapshots (initial-data/result/verification_data)
# to sanity-check the Application before load starts. Those snapshots must be
# captured from a real run of the Faker-seeded dummy data against the actual
# webapp binary (see upstream/isucon10-qualify/initial-data/make_verification_data),
# so this build installs mysql-server via apt and requires sudo. It is a
# CI-only script (ubuntu-26.04-arm runner), matching the Node.js 14.9.0
# linux-arm64-only constraint already documented in NOTICE.md; it is not
# meant for interactive local runs on a development machine.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANAGED="${ROOT_DIR}/upstream/isucon10-qualify"
RELEASE_DIST="${ROOT_DIR}/kakomon10-qualify/dist"
OUTPUT="${RELEASE_DIST}/kakomon10-qualify-frontend.tar.gz"
OUTPUT_CHECKSUM="${OUTPUT}.sha256"
MISE_CONFIG="${ROOT_DIR}/kakomon10-qualify/scripts/mise.toml"
EXPECTED_NODE_VERSION="v14.9.0"
EXPECTED_GO_VERSION="go1.26.6"
OFFICIAL_REPO_URL="https://github.com/isucon/isucon10-qualify.git"
OFFICIAL_COMMIT="7e6b6cfb672cde2c57d7b594d0352dc48ce317df"
MYSQL_TEST_USER="isucon"
MYSQL_TEST_PASS="isucon"
MYSQL_TEST_DB="isuumo"
WEBAPP_PORT="1323"

work="$(mktemp -d)"
checkout=""
webapp_pid=""

cleanup() {
  if [ -n "${webapp_pid}" ] && kill -0 "${webapp_pid}" 2>/dev/null; then
    kill "${webapp_pid}" 2>/dev/null || true
    wait "${webapp_pid}" 2>/dev/null || true
  fi
  rm -rf "${work}"
  if [ -n "${checkout}" ]; then
    rm -rf "${checkout}"
  fi
}
trap cleanup EXIT

run_node() {
  MISE_CONFIG_FILE="${MISE_CONFIG}" mise exec -- "$@"
}
run_go() {
  MISE_CONFIG_FILE="${MISE_CONFIG}" mise exec -- "$@"
}

# fresh CI installs the locked toolchains; a cached local run may skip this.
MISE_CONFIG_FILE="${MISE_CONFIG}" mise install

if [ "$(run_node node --version)" != "${EXPECTED_NODE_VERSION}" ]; then
  echo "error: Node.js ${EXPECTED_NODE_VERSION} is required" >&2
  exit 1
fi
if [ "$(run_go go version | awk '{print $3}')" != "${EXPECTED_GO_VERSION}" ]; then
  echo "error: Go ${EXPECTED_GO_VERSION} is required" >&2
  exit 1
fi

# 1. Fetch the official frontend source AND the 6 official seed images
#    (initial-data/origin/{chair,estate}/*.png) at the exact official commit
#    via one blobless sparse checkout. Neither is committed under upstream/
#    isucon10-qualify (see NOTICE.md "Source and assets intentionally not
#    managed here"): binary/image assets stay out of this project's Git
#    history regardless of whether the official repository itself commits
#    them, and are instead fetched here, at build time, from the exact
#    official commit, then checksum-verified against
#    kakomon10-qualify/scripts/frontend-assets.manifest.sha256.
checkout="$(mktemp -d)"
git init --quiet "${checkout}"
git -C "${checkout}" remote add origin "${OFFICIAL_REPO_URL}"
git -C "${checkout}" sparse-checkout set --cone webapp/frontend initial-data/origin
git -C "${checkout}" fetch --quiet --depth 1 --filter=blob:none origin "${OFFICIAL_COMMIT}"
git -C "${checkout}" checkout --quiet "${OFFICIAL_COMMIT}"
test "$(git -C "${checkout}" rev-parse HEAD)" = "${OFFICIAL_COMMIT}"
frontend_src="${checkout}/webapp/frontend"
test -f "${frontend_src}/package.json"
(
  cd "${checkout}"
  shasum -a 256 -c "${ROOT_DIR}/kakomon10-qualify/scripts/frontend-assets.manifest.sha256"
)

# 2. Generate the Faker-seeded dummy data (SQL + fixture JSON + chair/estate
#    detail JSON + draft files) and the 1,000 recolored PNGs per kind. The
#    generators write relative to initial-data/ and into
#    ../webapp/frontend/public/images, so stage initial-data and the fetched
#    frontend as siblings, matching the official tree.
stage_root="${work}/stage"
install -d -m 0755 "${stage_root}/initial-data/result/draft_data/chair" \
  "${stage_root}/initial-data/result/draft_data/estate" \
  "${stage_root}/webapp/frontend"
rsync -a "${MANAGED}/initial-data/" "${stage_root}/initial-data/"
rsync -a "${checkout}/initial-data/origin/" "${stage_root}/initial-data/origin/"
rsync -a "${frontend_src}/" "${stage_root}/webapp/frontend/"

venv="${work}/venv"
python3 -m venv "${venv}"
"${venv}/bin/pip" install --quiet --upgrade pip
"${venv}/bin/pip" install --quiet -r "${stage_root}/initial-data/requirements.txt"
(
  cd "${stage_root}/initial-data"
  "${venv}/bin/python3" make_chair_data.py
  "${venv}/bin/python3" make_estate_data.py
)
for f in result/2_DummyChairData.sql result/chair_condition.json result/chair_json.txt \
  result/1_DummyEstateData.sql result/estate_condition.json result/estate_json.txt; do
  test -f "${stage_root}/initial-data/${f}"
done
test "$(find "${stage_root}/webapp/frontend/public/images/chair" -type f | wc -l)" -eq 1003
test "$(find "${stage_root}/webapp/frontend/public/images/estate" -type f | wc -l)" -eq 1003

# 3. Build and run the migrated webapp against the generated data, then
#    generate the benchmark verification snapshot the same way the official
#    initial-data/Makefile's verification_data target does (against a live
#    webapp), but pointed at our own throwaway MySQL instead of docker-compose.
# GitHub Actions ubuntu-26.04-arm runners observed 2026-08-18: a plain
# `apt-get install mysql-server` did not leave root on auth_socket (`sudo
# mysqladmin --user=root ping` failed with "Access denied ... using
# password: NO"), unlike a from-scratch install on bastion EC2, which does.
# Purge any pre-existing mysql packages/data first so the postinstall script
# always runs fresh and sets up root the same way 40-mysql.sh assumes.
sudo systemctl stop mysql 2>/dev/null || true
sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq mysql-server mysql-server-core mysql-client mysql-client-core mysql-common 2>/dev/null || true
sudo rm -rf /var/lib/mysql /etc/mysql
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server
sudo systemctl enable --now mysql
sudo mysqladmin --defaults-file=/dev/null --user=root ping
sudo mysql --defaults-file=/dev/null --user=root -e \
  "CREATE USER IF NOT EXISTS ${MYSQL_TEST_USER}@localhost IDENTIFIED BY '${MYSQL_TEST_PASS}'; GRANT ALL PRIVILEGES ON *.* TO ${MYSQL_TEST_USER}@localhost WITH GRANT OPTION; FLUSH PRIVILEGES;"
cat "${MANAGED}/webapp/mysql/db/0_Schema.sql" \
  "${stage_root}/initial-data/result/1_DummyEstateData.sql" \
  "${stage_root}/initial-data/result/2_DummyChairData.sql" |
  mysql --defaults-file=/dev/null -h 127.0.0.1 -P 3306 -u "${MYSQL_TEST_USER}" -p"${MYSQL_TEST_PASS}" "${MYSQL_TEST_DB}"

webapp_dir="${stage_root}/webapp/go"
install -d -m 0755 "${webapp_dir}" "${stage_root}/webapp/fixture" "${stage_root}/webapp/mysql/db"
rsync -a "${MANAGED}/webapp/go/" "${webapp_dir}/"
install -m 0644 "${stage_root}/initial-data/result/chair_condition.json" "${stage_root}/webapp/fixture/chair_condition.json"
install -m 0644 "${stage_root}/initial-data/result/estate_condition.json" "${stage_root}/webapp/fixture/estate_condition.json"
install -m 0644 "${MANAGED}/webapp/mysql/db/0_Schema.sql" "${stage_root}/webapp/mysql/db/0_Schema.sql"
install -m 0644 "${stage_root}/initial-data/result/1_DummyEstateData.sql" "${stage_root}/webapp/mysql/db/1_DummyEstateData.sql"
install -m 0644 "${stage_root}/initial-data/result/2_DummyChairData.sql" "${stage_root}/webapp/mysql/db/2_DummyChairData.sql"

(
  cd "${webapp_dir}"
  run_go go build -mod=readonly -trimpath -o "${work}/isuumo" .
)
MYSQL_HOST=127.0.0.1 MYSQL_PORT=3306 MYSQL_USER="${MYSQL_TEST_USER}" MYSQL_PASS="${MYSQL_TEST_PASS}" \
  MYSQL_DBNAME="${MYSQL_TEST_DB}" SERVER_PORT="${WEBAPP_PORT}" \
  "${work}/isuumo" >"${work}/isuumo.log" 2>&1 &
webapp_pid=$!
ready=false
for _ in $(seq 1 30); do
  if curl --fail --silent --output /dev/null "http://127.0.0.1:${WEBAPP_PORT}/api/chair/search/condition"; then
    ready=true
    break
  fi
  sleep 1
done
if [ "${ready}" != true ]; then
  echo "error: throwaway webapp did not become ready" >&2
  cat "${work}/isuumo.log" >&2
  exit 1
fi

verify_gen_dir="${stage_root}/initial-data/make_verification_data"
(
  cd "${verify_gen_dir}"
  run_go go mod init makeverificationdata >/dev/null 2>&1 || true
  run_go go build -o "${work}/make_verification_data" .
)
"${work}/make_verification_data" \
  -target-url "http://127.0.0.1:${WEBAPP_PORT}" \
  -fixture-dir "${stage_root}/webapp/fixture" \
  -dest-dir "${stage_root}/initial-data/result/verification_data"
test -d "${stage_root}/initial-data/result/verification_data/chair_detail"

kill "${webapp_pid}"
wait "${webapp_pid}" 2>/dev/null || true
webapp_pid=""

# 4. Build the frontend (images from step 2 are already under public/images).
rm -rf "${stage_root}/webapp/frontend/.next" "${stage_root}/webapp/frontend/out"
(
  cd "${stage_root}/webapp/frontend"
  run_node npm ci
  run_node npm run build
  run_node npm run export
)
test -f "${stage_root}/webapp/frontend/out/index.html"

# 5. Assemble the release archive: frontend static export, the two frozen
#    dummy-data SQL files, the fixture JSON, and the bench-input result tree
#    (chair/estate JSON, draft files, verification snapshots).
install -d -m 0755 "${RELEASE_DIST}"
release="${work}/release"
install -d -m 0755 "${release}/public" "${release}/mysql" "${release}/fixture" "${release}/initial-data-result"
rsync -a "${stage_root}/webapp/frontend/out/" "${release}/public/"
install -m 0644 "${stage_root}/initial-data/result/1_DummyEstateData.sql" "${release}/mysql/1_DummyEstateData.sql"
install -m 0644 "${stage_root}/initial-data/result/2_DummyChairData.sql" "${release}/mysql/2_DummyChairData.sql"
install -m 0644 "${stage_root}/initial-data/result/chair_condition.json" "${release}/fixture/chair_condition.json"
install -m 0644 "${stage_root}/initial-data/result/estate_condition.json" "${release}/fixture/estate_condition.json"
install -m 0644 "${stage_root}/initial-data/result/chair_json.txt" "${release}/initial-data-result/chair_json.txt"
install -m 0644 "${stage_root}/initial-data/result/estate_json.txt" "${release}/initial-data-result/estate_json.txt"
rsync -a "${stage_root}/initial-data/result/draft_data/" "${release}/initial-data-result/draft_data/"
rsync -a "${stage_root}/initial-data/result/verification_data/" "${release}/initial-data-result/verification_data/"
install -m 0644 "${MANAGED}/LICENSE" "${release}/LICENSE"

(
  cd "${release}"
  find . -type f ! -name MANIFEST.sha256 -print | LC_ALL=C sort | sed 's#^\./##' | xargs sha256sum
) >"${release}/MANIFEST.sha256"

rm -f "${OUTPUT}" "${OUTPUT_CHECKSUM}"
COPYFILE_DISABLE=1 tar -czf "${OUTPUT}" -C "${release}" .
(
  cd "${RELEASE_DIST}"
  sha256sum "$(basename "${OUTPUT}")" >"$(basename "${OUTPUT_CHECKSUM}")"
)

echo "built frontend export: ${stage_root}/webapp/frontend/out"
echo "built release archive: ${OUTPUT}"
