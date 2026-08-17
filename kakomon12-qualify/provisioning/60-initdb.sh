#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

SQL_DIR="${ISUREN_HOME}/webapp/sql"

# 01_create_mysql_database.sql creates the isuports database and the isucon
# MySQL user/grant; 10_schema.sql creates the admin tables (tenant,
# id_generator, visit_history). 90_data.sql (from the initial_data Release
# archive, not the source checkout -- see 05-artifacts.sh/50-source.sh) seeds
# the ~100 baseline tenant rows init.sql's `DELETE FROM tenant WHERE id > 100`
# assumes already exist. All three run once, as root, at provisioning time --
# they are schema/baseline-data DDL, not part of the repeatable /initialize
# contract (which only re-applies init.sql itself, via sql/init.sh).
mysql --defaults-file=/dev/null --user=root <"${SQL_DIR}/admin/01_create_mysql_database.sql"
mysql --defaults-file=/dev/null --user=root <"${SQL_DIR}/admin/10_schema.sql"
mysql --defaults-file=/dev/null --user=root isuports <"${SQL_DIR}/admin/90_data.sql"

# sql/init.sh is the same script the running Application execs on every
# POST /initialize (webapp/go's `initializeScript = "../sql/init.sh"`); run
# it once here so a freshly booted clone already has tenant_db populated
# before any benchmark run touches it. It re-applies init.sql (a reset, not a
# schema statement) and copies initial_data/*.db into tenant_db/.
runuser -u "${ISUREN_USER}" -- env \
  ISUCON_DB_HOST=127.0.0.1 \
  ISUCON_DB_PORT=3306 \
  ISUCON_DB_USER=isucon \
  ISUCON_DB_PASSWORD=isucon \
  ISUCON_DB_NAME=isuports \
  bash "${SQL_DIR}/init.sh"

test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='isuports'")" -gt 0
test -n "$(find "${ISUREN_HOME}/webapp/tenant_db" -maxdepth 1 -name '*.db')"
test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e "SELECT COUNT(*) FROM isuports.tenant")" -eq 100

log "60-initdb.sh: official admin schema created, tenant_db seeded from initial_data"
