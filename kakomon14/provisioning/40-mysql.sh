#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# 対応: isucon14/provisioning/ansible/roles/mysql/tasks/main.yml L1-5
# 2回目以降にネットワークへ出ないよう、未インストールのときだけapt-get updateする。
install_mysql() {
  if ! dpkg -s mysql-server >/dev/null 2>&1; then
    apt-get update
    apt-get install -y mysql-server
    log "mysql-server: installed"
  else
    log "mysql-server: already installed"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/mysql/tasks/main.yml L7-11
start_mysql_service() {
  if systemctl is-active --quiet mysql && systemctl is-enabled --quiet mysql; then
    log "mysql service: already enabled and running"
  else
    systemctl enable --now mysql
    log "mysql service: enabled and started"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/mysql/tasks/main.yml L13-20
# 元のCREATE USER IF NOT EXISTSだけだと、ユーザーが既に存在する場合パスワードは更新されない。
# ALTER USERを足すことでパスワードのドリフトも解消されるようにした。
# CREATE/ALTER/GRANTはMySQL側で既に冪等なため、changed/already の判定は自前で行わずMySQLに委ねる。
set_isucon_db_user() {
  mysql -uroot -e "
    CREATE USER IF NOT EXISTS 'isucon'@'%' IDENTIFIED BY 'isucon';
    ALTER USER 'isucon'@'%' IDENTIFIED BY 'isucon';
    GRANT ALL PRIVILEGES ON *.* TO 'isucon'@'%' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
  "
  log "isucon db user: granted"
}

install_mysql
start_mysql_service
set_isucon_db_user

log "40-mysql.sh: done"
