#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

timedatectl set-timezone UTC

install -m 0644 /dev/null /etc/sysctl.d/99-isuren.conf
echo 'net.ipv4.ip_local_port_range = 10000 65535' >/etc/sysctl.d/99-isuren.conf
sysctl --system >/dev/null

install -m 0644 /dev/null /etc/security/limits.d/99-isuren.conf
{
  echo '* - nofile 655360'
  echo '* - nproc 655360'
  echo '* soft memlock unlimited'
  echo '* hard memlock unlimited'
} >/etc/security/limits.d/99-isuren.conf

log "10-base.sh: done"
