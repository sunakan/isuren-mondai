#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# shellcheck source=/dev/null
. /etc/os-release
test "${ID}" = ubuntu
test "${VERSION_ID}" = 26.04
test "$(dpkg --print-architecture)" = arm64

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  iproute2 \
  jq \
  mysql-server \
  nginx \
  procps \
  rsync \
  unzip

timedatectl set-timezone UTC
cat >/etc/security/limits.d/99-isuren.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
cat >/etc/sysctl.d/99-isuren.conf <<'EOF'
net.ipv4.ip_local_port_range = 10000 65535
EOF
sysctl --system >/dev/null

log "10-base.sh: Ubuntu 26.04 arm64 and base packages ready"
