#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Keep the OS baseline explicit and identical across target recipes. Target
# services add their own hostname, DNS, and proxy contracts later.
set_timezone() {
  timedatectl set-timezone UTC
  log "timezone: set to UTC"
}

set_sysctl_port_range() {
  local conf=/etc/sysctl.d/99-isuren.conf
  local content='net.ipv4.ip_local_port_range = 10000 65535'
  echo "${content}" >"${conf}"
  sysctl --system >/dev/null
  log "sysctl: ${conf} set"
}

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
  echo "${content}" >"${conf}"
  log "limits: ${conf} set"
}

# KAKOMON14's matcher contract needs this local hostname. KAKOMON13 uses
# PowerDNS and its instance-init service instead, so this remains target-local.
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
