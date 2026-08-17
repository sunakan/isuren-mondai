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
# gh CLI is required by 05-artifacts.sh to resolve/download the initial_data
# GitHub Release asset; jq/unzip/curl/git support that fetch and its manifest
# verification.
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

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  >/etc/apt/sources.list.d/github-cli.list
apt-get update
apt-get install -y --no-install-recommends gh

timedatectl set-timezone UTC
cat >/etc/security/limits.d/99-isuren.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
cat >/etc/sysctl.d/99-isuren.conf <<'EOF'
net.ipv4.ip_local_port_range = 10000 65535
EOF
sysctl --system >/dev/null

log "10-base.sh: Ubuntu 26.04 arm64, CGO toolchain, and gh CLI ready"
