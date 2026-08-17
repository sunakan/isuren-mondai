#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

SQL_DIR="${ISUREN_HOME}/webapp/sql"

# 01_create_mysql_database.sql creates the isuports database and the isucon
# MySQL user/grant; 10_schema.sql creates the admin tables (tenant,
# id_generator, visit_history). Both run once, as root, at provisioning time
# -- they are schema DDL, not part of the repeatable /initialize contract.
mysql --defaults-file=/dev/null --user=root <"${SQL_DIR}/admin/01_create_mysql_database.sql"
mysql --defaults-file=/dev/null --user=root <"${SQL_DIR}/admin/10_schema.sql"

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

# NOTE (decision-required, unresolved by this implement pass): whether the
# initial ~100 tenant rows referenced by init.sql's
# `DELETE FROM tenant WHERE id > 100` come from inside the initial_data
# Release archive (e.g. an admin-DB SQL dump alongside the per-tenant .db
# files) or are created by the benchmarker's own prepare phase
# (`-prepare-only` / `-skip-prepare` flags in bench/cmd/bench/main.go) could
# not be confirmed without downloading and inspecting the real archive
# (network access is out of scope for onboard-kakomon-ami-recipe's
# audit/plan/implement modes). If admin.tenant is empty after this step while
# webapp/tenant_db has *.db files, that is expected until this is resolved in
# `verify` -- do not add a fabricated seed file here.

log "60-initdb.sh: official admin schema created, tenant_db seeded from initial_data"
