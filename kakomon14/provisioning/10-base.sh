#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Keep only tools required by the common provisioning skeletons. Database,
# proxy, DNS, archive-format-specific, and diagnostic packages belong to the
# target step that consumes them.
COMMON_PACKAGES=(
  ca-certificates
  curl
  git
  gzip
  openssl
  procps
  rsync
  sudo
  tar
)

validate_platform() {
  # shellcheck source=/dev/null
  . /etc/os-release
  test "${ID}" = ubuntu
  test "${VERSION_ID}" = 26.04
  test "$(dpkg --print-architecture)" = arm64
  log "platform: Ubuntu 26.04 arm64"
}

install_common_packages() {
  local package
  local missing=()
  for package in "${COMMON_PACKAGES[@]}"; do
    if ! dpkg -s "${package}" >/dev/null 2>&1; then
      missing+=("${package}")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "base packages: already installed"
    return
  fi

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
  log "base packages: installed ${missing[*]}"
}

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

validate_platform
install_common_packages
set_timezone
set_sysctl_port_range
set_limits
set_hosts

log "10-base.sh: done"
