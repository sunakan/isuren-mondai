#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

OFFICIAL_DIR="${ARTIFACT_DIR}/official"
require_file "${MANAGED_SOURCE_DIR}/NOTICE.md"
require_file "${MANAGED_SOURCE_DIR}/LICENSE"
require_file "${OFFICIAL_DIR}/webapp/public.pem"
require_file "${OFFICIAL_DIR}/blackauth/isuports.pem"

# webapp/go: managed source (this repository) + the official public JWT key
# (fetched in 05-artifacts.sh, not committed here; see NOTICE.md).
rm -rf "${ISUREN_HOME}/webapp"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ISUREN_HOME}/webapp/go" "${ISUREN_HOME}/webapp/tenant_db"
rsync -a "${MANAGED_SOURCE_DIR}/webapp/go/" "${ISUREN_HOME}/webapp/go/"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${OFFICIAL_DIR}/webapp/public.pem" "${ISUREN_HOME}/webapp/public.pem"
rsync -a "${OFFICIAL_DIR}/webapp/sql/" "${ISUREN_HOME}/webapp/sql/"
chmod 0755 "${ISUREN_HOME}/webapp/sql/init.sh"
# 90_data.sql is gitignored upstream (only shipped via the initial_data
# Release archive, not the source checkout above); see 05-artifacts.sh.
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ARTIFACT_DIR}/extracted/webapp/sql/admin/90_data.sql" "${ISUREN_HOME}/webapp/sql/admin/90_data.sql"

# public/ (prebuilt frontend, nginx-served) is deployed as a top-level
# sibling of webapp/, blackauth/, and bench/ -- matching the official
# repository root layout, not nested under webapp/. bench/scenario.go's
# validation step opens ../public/js cwd-relative from bench/, which only
# resolves if public/ is bench/'s sibling (confirmed via
# orb-standalone-green; see 72-bench-build.sh and 90-nginx.sh).
rm -rf "${ISUREN_HOME}/public"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${ISUREN_HOME}/public"
rsync -a "${OFFICIAL_DIR}/public/" "${ISUREN_HOME}/public/"
chown -R "${ISUREN_USER}:${ISUREN_USER}" "${ISUREN_HOME}/public"

# blackauth: managed source + the official private JWT key. The key must be
# present before 71-blackauth-go.sh builds, because main.go embeds it via
# `//go:embed isuports.pem` at compile time (not loaded at runtime).
rm -rf "${ISUREN_HOME}/blackauth"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${ISUREN_HOME}/blackauth"
rsync -a "${MANAGED_SOURCE_DIR}/blackauth/" "${ISUREN_HOME}/blackauth/"
install -m 0600 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${OFFICIAL_DIR}/blackauth/isuports.pem" "${ISUREN_HOME}/blackauth/isuports.pem"

# initial_data/*.db is not a build-only input: webapp/sql/init.sh re-reads it
# on every /initialize call (`cp -r ../../initial_data/*.db ../tenant_db/`),
# so it must remain present in the sealed image, not just during provisioning.
rm -rf "${ISUREN_HOME}/initial_data"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${ISUREN_HOME}/initial_data"
rsync -a "${ARTIFACT_DIR}/extracted/initial_data/" "${ISUREN_HOME}/initial_data/"

# bench (+ its isucon12-portal/data module dependencies) is staged as a
# sibling of webapp/go under a build-only directory, mirroring the official
# repository root layout that bench/go.mod's `replace ../isucon12-portal`,
# `replace ../data`, and `replace ../webapp/go` directives expect. This whole
# directory is removed by 72-bench-build.sh once the bench binary is built;
# only the final binary at /home/isuren/bench/bench is a runtime asset.
BUILD_ROOT="${ISUREN_HOME}/.build/isucon12-qualify"
rm -rf "${BUILD_ROOT}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${BUILD_ROOT}"
rsync -a "${MANAGED_SOURCE_DIR}/bench/" "${BUILD_ROOT}/bench/"
rsync -a "${MANAGED_SOURCE_DIR}/isucon12-portal/" "${BUILD_ROOT}/isucon12-portal/"
rsync -a "${MANAGED_SOURCE_DIR}/data/" "${BUILD_ROOT}/data/"
install -d -m 0755 "${BUILD_ROOT}/webapp"
rsync -a "${ISUREN_HOME}/webapp/go/" "${BUILD_ROOT}/webapp/go/"

install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${MANAGED_SOURCE_DIR}/LICENSE" "${ISUREN_HOME}/LICENSE"

# Public practice defaults, matching the official docker-compose-go.yml
# environment block. Only the hostnames differ from the official
# `.t.isucon.dev` / `admin.t.isucon.dev` values (see kakomon12-qualify/README.md).
cat >"${ISUREN_HOME}/env.sh" <<EOF
ISUCON_DB_HOST=127.0.0.1
ISUCON_DB_PORT=3306
ISUCON_DB_USER=isucon
ISUCON_DB_PASSWORD=isucon
ISUCON_DB_NAME=isuports
ISUCON_TENANT_DB_DIR=${ISUREN_HOME}/webapp/tenant_db
ISUCON_JWT_KEY_FILE=${ISUREN_HOME}/webapp/public.pem
ISUCON_BASE_HOSTNAME=.t.isuren.internal
ISUCON_ADMIN_HOSTNAME=admin.t.isuren.internal
SERVER_APP_PORT=3000
EOF
chown "${ISUREN_USER}:${ISUREN_USER}" "${ISUREN_HOME}/env.sh"
chmod 0644 "${ISUREN_HOME}/env.sh"

chown -R "${ISUREN_USER}:${ISUREN_USER}" \
  "${ISUREN_HOME}/webapp" "${ISUREN_HOME}/blackauth" "${ISUREN_HOME}/initial_data" "${BUILD_ROOT}"
log "50-source.sh: managed source and official non-code inputs deployed"
