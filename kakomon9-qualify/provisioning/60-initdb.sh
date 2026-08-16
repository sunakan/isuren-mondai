#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

mysql --defaults-file=/dev/null --user=root <"${APP_ROOT}/webapp/sql/00_create_database.sql"
runuser -u "${ISUREN_USER}" -- env \
  MYSQL_HOST=127.0.0.1 \
  MYSQL_PORT=3306 \
  MYSQL_USER=isucari \
  MYSQL_PASS=isucari \
  MYSQL_DBNAME=isucari \
  bash "${APP_ROOT}/webapp/init.sh"

test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='isucari'")" -gt 0
log "60-initdb.sh: official schema and initial data loaded"
