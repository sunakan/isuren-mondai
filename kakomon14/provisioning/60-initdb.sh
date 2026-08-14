#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
WEBAPP_SQL_DIR="${ISUREN_HOME}/webapp/sql"

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/main.yaml L28-33(initilize database)
# 本番のベンチ実行前リセット(/api/initialize、webapp/go/main.goのpostInitialize)は実際にはinit.sh
# (1/2/3のSQL)しか呼んでおらずDB自体はDROPしない。ここでのDROPはAMIビルド時(再プロビジョニング時)に
# 確実にクリーンな状態から作り直すためのもので、本番の/api/initializeの模倣ではない。
# 他のスクリプトと違い2回目以降もchanged/alreadyの判定はせず毎回実行する。
#
# DB作成自体は0-init.sql(charset/collationの指定を含む、公式の定義)に委ねる。0-init.sqlが作る
# isucon@'%'ユーザーは、本家から取得したenv.sh(50-source.shのlink_env_sh参照)の値と一致する
# ため、isuren-mondai側で別途DBユーザーを作る必要はない。
reset_database() {
  mysql -uroot -e "DROP DATABASE IF EXISTS isuride;"
  mysql -uroot <"${WEBAPP_SQL_DIR}/0-init.sql"
  log "database: dropped and recreated via 0-init.sql"
}

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/main.yaml L34-36(initialize tables)
# init.shは/home/isucon/env.sh(固定パス)をsourceしようとするが、bastionにはisurenしかいないため
# 読み込まれない。ただしinit.sh自体のデフォルト値(ISUCON_DB_USER=isucon等)が0-init.sqlで作る
# ユーザー・~/env.shの値と一致するため、明示exportしなくても実害はない。
run_init_sql() {
  runuser -u "${ISUREN_USER}" -- bash "${WEBAPP_SQL_DIR}/init.sh"
  log "init.sh: executed"
}

reset_database
run_init_sql

log "60-initdb.sh: done"
