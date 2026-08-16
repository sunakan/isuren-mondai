#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
SQL_DIR="${ISUREN_HOME}/webapp/sql"
PDNS_SCHEMA="${ISUREN_HOME}/.kakomon13-staging/official/development/pdns/20_powerdns_schema.sql"

mysql -uroot -e 'DROP DATABASE IF EXISTS isupipe; DROP DATABASE IF EXISTS isudns;'
mysql -uroot <"${SQL_DIR}/initdb.d/00_create_database.sql"
mysql -uroot <"${SQL_DIR}/initdb.d/10_schema.sql"
awk '/-- NOTE: initialize/{exit} {print}' "${PDNS_SCHEMA}" | mysql -uroot

for sql in \
  init.sql \
  initial_users.sql \
  initial_livestreams.sql \
  initial_tags.sql \
  initial_livestream_tags.sql \
  initial_reservation_slots.sql \
  initial_reactions.sql \
  initial_ngwords.sql \
  initial_livecomments.sql; do
  MYSQL_PWD=isucon mysql -uisucon isupipe <"${SQL_DIR}/${sql}"
done

log "80-database.sh: done"
