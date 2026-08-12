#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# 対応: isucon14/provisioning/ansible/roles/base/tasks/main.yml L1-4
set_timezone() {
  if [ "$(timedatectl show -p Timezone --value)" != "UTC" ]; then
    timedatectl set-timezone UTC
    log "timezone: changed to UTC"
  else
    log "timezone: already UTC"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/base/tasks/main.yml L13-20
set_sysctl_port_range() {
  local conf=/etc/sysctl.d/99-isuren.conf
  local content='net.ipv4.ip_local_port_range = 10000 65535'
  if [ ! -f "${conf}" ] || [ "$(cat "${conf}")" != "${content}" ]; then
    echo "${content}" >"${conf}"
    sysctl --system >/dev/null
    log "sysctl: changed ${conf}"
  else
    log "sysctl: already up to date"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/base/tasks/main.yml L22-33
set_limits() {
  local conf=/etc/security/limits.d/99-isuren.conf
  local content
  content=$(
    cat <<'EOD'
* - nofile 655360
* - nproc 655360
* soft memlock unlimited
* hard memlock unlimited
EOD
  )
  if [ ! -f "${conf}" ] || [ "$(cat "${conf}")" != "${content}" ]; then
    echo "${content}" >"${conf}"
    log "limits: changed ${conf}"
  else
    log "limits: already up to date"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/base/tasks/main.yml L35-43
# ホスト名はxiv.isucon.netではなくxiv.isuren.internalを使う。
# .internalはICANNが私設ネットワーク専用に予約したTLD(.localと違いmDNSの特殊扱いを受けない)で、
# webapp/go・frontendにisucon.net依存箇所がないため置き換えても実害がないことを確認済み。
set_hosts() {
  local marker='127.0.0.1 isuride.xiv.isuren.internal'
  if ! grep -qF "${marker}" /etc/hosts; then
    {
      echo ""
      echo "# ISURIDE IP for matching requests"
      echo "${marker}"
    } >>/etc/hosts
    log "hosts: added ${marker}"
  else
    log "hosts: already present"
  fi
}

# 未対応(意図的に除外): isucon14/provisioning/ansible/roles/base/tasks/main.yml L6-11
# /etc/ssh/sshd_config.d/pubkey.conf に PubkeyAcceptedAlgorithms=+ssh-rsa を配置するタスク。
# 旧クライアント互換のための設定で、bastionからの接続は最新クライアント前提のため除外。

set_timezone
set_sysctl_port_range
set_limits
set_hosts

log "10-base.sh: done"
