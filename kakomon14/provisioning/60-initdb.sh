#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
WEBAPP_SQL_DIR="${ISUREN_HOME}/webapp/sql"

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/main.yaml L28-33(initilize database)
# 本番のベンチ実行前リセット(/api/initialize)と同じ「常にDROP&CREATEしなおす」動作が正しい仕様のため、
# 他のスクリプトと違い2回目以降もchanged/alreadyの判定はせず毎回実行する。
reset_database() {
  mysql -uroot -e "DROP DATABASE IF EXISTS isuride; CREATE DATABASE IF NOT EXISTS isuride;"
  log "database: dropped and recreated"
}

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/main.yaml L34-36(initialize tables)
# init.shは/home/isucon/env.sh(固定パス)をsourceしようとするが、bastionにはisurenしかいないため
# 読み込まれない(デフォルト値がenv.shの内容と一致するため実害はないが、タスク方針通り明示exportする)。
run_init_sql() {
  runuser -u "${ISUREN_USER}" -- env \
    ISUCON_DB_HOST="127.0.0.1" \
    ISUCON_DB_PORT="3306" \
    ISUCON_DB_USER="isucon" \
    ISUCON_DB_PASSWORD="isucon" \
    ISUCON_DB_NAME="isuride" \
    bash "${WEBAPP_SQL_DIR}/init.sh"
  log "init.sh: executed"
}

reset_database
run_init_sql

log "60-initdb.sh: done"
