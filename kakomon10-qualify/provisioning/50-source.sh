#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_file "${MANAGED_SOURCE_DIR}/NOTICE.md"
require_file "${MANAGED_SOURCE_DIR}/LICENSE"
require_file "${MANAGED_SOURCE_DIR}/webapp/go/main.go"
require_file "${MANAGED_SOURCE_DIR}/webapp/mysql/db/0_Schema.sql"
require_file "${PROVISIONING_DIR}/runtime/env.sh"

# Keep the official relative layout (webapp/go, webapp/mysql, bench,
# initial-data as siblings under one project root) so cwd-relative reads in
# main.go (`../fixture/...`, `../mysql/db/...`) and bench (`../initial-data`,
# `../webapp/fixture`) resolve without recipe-specific path rewrites.
rm -rf "${APP_ROOT}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}"
rsync -a "${MANAGED_SOURCE_DIR}/webapp/" "${APP_ROOT}/webapp/"
rsync -a "${MANAGED_SOURCE_DIR}/bench/" "${APP_ROOT}/bench/"
rsync -a "${MANAGED_SOURCE_DIR}/initial-data/" "${APP_ROOT}/initial-data/"

install -m 0644 "${MANAGED_SOURCE_DIR}/LICENSE" "${PROVENANCE_DIR}/LICENSE"
install -m 0644 "${MANAGED_SOURCE_DIR}/NOTICE.md" "${PROVENANCE_DIR}/managed-source-NOTICE.md"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${MANAGED_SOURCE_DIR}/LICENSE" "/home/${ISUREN_USER}/LICENSE"
# This is the exact public DB environment shipped by the official provisioning
# role. Keeping it as a shell-compatible EnvironmentFile makes the Application
# service and an interactive practice shell share one contract.
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PROVISIONING_DIR}/runtime/env.sh" "/home/${ISUREN_USER}/env.sh"

cat >"${PROVENANCE_DIR}/recipe.txt" <<EOF
canonical_slug=kakomon10-qualify
official_repository=https://github.com/isucon/isucon10-qualify.git
official_commit=7e6b6cfb672cde2c57d7b594d0352dc48ce317df
license=MIT; Copyright (c) 2020 isucon10-qualify
region=ap-northeast-1
application=127.0.0.1:1323
application_environment=/home/${ISUREN_USER}/env.sh
benchmark=${APP_ROOT}/bench/bench
reset=POST /initialize
frontend=CI/Release static export (Next.js, unmodified official version); see /www/data
EOF

chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}"
log "50-source.sh: managed source deployed to ${APP_ROOT}"
