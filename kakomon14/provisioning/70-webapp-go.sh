#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
WEBAPP_GO_DIR="${ISUREN_HOME}/webapp/go"
SYSTEMD_UNIT="/etc/systemd/system/isuride-go.service"

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/go.yaml L9-15
# 再ビルドのたびにサービス再起動が必要なため、changed/already判定はせず常にビルドする。
# runuser経由では.bashrcを経由せずmiseがPATHに乗らないため、mise本体はフルパスで呼ぶ。
build_isuride_go() {
  # shellcheck disable=SC2016 # env経由で渡したWEBAPP_GO_DIR/MISE_BINをsh -c内で展開させる
  runuser -u "${ISUREN_USER}" -- env WEBAPP_GO_DIR="${WEBAPP_GO_DIR}" MISE_BIN="${MISE_BIN}" \
    sh -c 'cd "${WEBAPP_GO_DIR}" && "${MISE_BIN}" exec -- go build -o "${WEBAPP_GO_DIR}/isuride" -ldflags "-s -w"'
  log "isuride-go: built"
}

# 対応: isucon14/provisioning/ansible/roles/webapp/files/isuride-go.service
# isucon->isurenに読み替え(User/Group/WorkingDirectory/EnvironmentFileのパス)。サービス名・ExecStartは据え置き。
# WorkingDirectoryは/api/initializeが相対パス../sql/init.shを呼ぶため必須。
set_systemd_unit() {
  local content
  content=$(
    cat <<EOD
[Unit]
Description=isuride-go
After=syslog.target
After=mysql.service
Requires=mysql.service

[Service]
WorkingDirectory=${WEBAPP_GO_DIR}
EnvironmentFile=${ISUREN_HOME}/env.sh

User=${ISUREN_USER}
Group=${ISUREN_USER}
ExecStart=${WEBAPP_GO_DIR}/isuride
ExecStop=/bin/kill -s QUIT \$MAINPID

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOD
  )
  if [ ! -f "${SYSTEMD_UNIT}" ] || [ "$(cat "${SYSTEMD_UNIT}")" != "${content}" ]; then
    echo "${content}" >"${SYSTEMD_UNIT}"
    systemctl daemon-reload
    log "systemd unit: changed ${SYSTEMD_UNIT}"
  else
    log "systemd unit: already up to date"
  fi
}

# 新しいバイナリを反映させるため、changed/already判定はせず常にrestartする。
restart_service() {
  systemctl enable isuride-go
  systemctl restart isuride-go
  log "isuride-go service: enabled and restarted"
}

build_isuride_go
set_systemd_unit
restart_service

log "70-webapp-go.sh: done"
