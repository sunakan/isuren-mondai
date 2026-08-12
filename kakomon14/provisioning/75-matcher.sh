#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
SYSTEMD_UNIT="/etc/systemd/system/isuride-matcher.service"
UNIT_CHANGED=0

# 対応: isucon14/provisioning/ansible/roles/webapp/files/isuride-matcher.service
# isucon->isurenに読み替え。Go版のみに絞る方針のため、他言語(node/perl/php/python/ruby/rust)への
# Afterは削除しisuride-go.serviceのみ残す。curl先は公式のhttps://isuride.xiv.isucon.net経由(nginx/TLS依存)
# ではなくhttp://127.0.0.1:8080への直叩きに変更し、nginx/TLSを丸ごとバイパスする。
set_systemd_unit() {
  local content
  content=$(
    cat <<EOD
[Unit]
Description=isuride-matcher
After=isuride-go.service

[Service]
User=${ISUREN_USER}
Group=${ISUREN_USER}
EnvironmentFile=${ISUREN_HOME}/env.sh

ExecStart=/bin/sh -c "while true; do curl -s http://127.0.0.1:8080/api/internal/matching; sleep \$ISUCON_MATCHING_INTERVAL; done"
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
    UNIT_CHANGED=1
    log "systemd unit: changed ${SYSTEMD_UNIT}"
  else
    log "systemd unit: already up to date"
  fi
}

# ユニットファイルが変わった場合は、稼働中でも再起動して新しい内容を反映させる
# (enable --nowはすでに動作中のサービスに対しては何もしないため)。
start_service() {
  systemctl enable isuride-matcher
  if [ "${UNIT_CHANGED}" = "1" ] || ! systemctl is-active --quiet isuride-matcher; then
    systemctl restart isuride-matcher
    log "isuride-matcher service: (re)started"
  else
    log "isuride-matcher service: already running"
  fi
}

set_systemd_unit
start_service

log "75-matcher.sh: done"
