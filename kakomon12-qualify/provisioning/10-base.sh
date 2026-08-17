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
# gcc/build-essential is required to CGO-build webapp/go (mattn/go-sqlite3).
# initial_data (GitHub Release asset) and the JWT keys/sql/public tree (Git
# sparse-checkout) are both fetched from public.github.com endpoints with
# plain curl/git and need no authentication or gh CLI; see 05-artifacts.sh.
# jq/unzip support that fetch's manifest verification and archive extraction.
apt-get install -y --no-install-recommends \
  build-essential \
  ca-certificates \
  curl \
  default-mysql-client \
  git \
  gnupg \
  jq \
  mysql-server \
  nginx \
  openssl \
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

log "10-base.sh: Ubuntu 26.04 arm64 and CGO toolchain ready"
