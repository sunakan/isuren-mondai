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
# DBユーザー作成はkakomon14/provisioning/60-initdb.shが本家の0-init.sqlを実行することで行う
# (isucon-user roleが作るisuconユーザーと、本家から取得したenv.shの値を一致させるため。
# 50-source.shのlink_env_sh参照)。

install_mysql
start_mysql_service

log "40-mysql.sh: done"
