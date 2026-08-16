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

set_timezone
set_sysctl_port_range
set_limits

log "10-base.sh: done"
