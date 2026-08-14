#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
PAYMENT_MOCK_DIR="${ISUREN_HOME}/webapp/payment_mock"
SYSTEMD_UNIT="/etc/systemd/system/isuride-payment_mock.service"

# 対応: isucon14/provisioning/ansible/roles/webapp/tasks/payment_mock.yaml
# webappと同じ考え方(70-webapp-go.sh)でrunuser経由でもmiseがPATHに乗るようフルパスで呼ぶ。
build_payment_mock() {
  # shellcheck disable=SC2016 # env経由で渡したPAYMENT_MOCK_DIR/MISE_BINをsh -c内で展開させる
  runuser -u "${ISUREN_USER}" -- env PAYMENT_MOCK_DIR="${PAYMENT_MOCK_DIR}" MISE_BIN="${MISE_BIN}" \
    sh -c 'cd "${PAYMENT_MOCK_DIR}" && "${MISE_BIN}" exec -- go build -o "${PAYMENT_MOCK_DIR}/payment_mock" -ldflags "-s -w"'
  log "payment_mock: built"
}

# 対応: isucon14/provisioning/ansible/roles/webapp/files/isuride-payment_mock.service
# isucon->isurenに読み替え。payment_mock(main.go)はDBを一切使わない(決済履歴はプロセス内メモリのmapで
# 保持するのみ)ため、本家unitにあるAfter=mysql.service/Requires=mysql.serviceは含めない。
# 本家はwebapp配置候補の全サーバーにこれを常駐させ:12345固定で待ち受けさせる方式
# (docs/ISURIDE.md「決済マイクロサービスのモックについて」)。分離サーバー構成を見据え、
# 単一AMI構成の現状でもwebappと同様に常駐させておく。
# ISUREN_USERは実際にはisuren固定でしか使われない(上書きされている箇所がリポジトリ内に無い)ため、
# 展開済みの静的ファイルとして持つ(systemd/参照。原本のisuride-payment_mock.serviceも静的ファイル)。
set_systemd_unit() {
  install -m 0644 "${SCRIPT_DIR}/systemd/isuride-payment_mock.service" "${SYSTEMD_UNIT}"
  systemctl daemon-reload
  log "systemd unit: ${SYSTEMD_UNIT} set"
}

# 新しいバイナリを反映させるため、changed/already判定はせず常にrestartする(70-webapp-go.shと同じ方針)。
restart_service() {
  systemctl enable isuride-payment_mock
  systemctl restart isuride-payment_mock
  log "isuride-payment_mock service: enabled and restarted"
}

build_payment_mock
set_systemd_unit
restart_service

log "77-payment-mock.sh: done"
