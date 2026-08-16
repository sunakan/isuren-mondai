#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

packages=(
  ca-certificates
  curl
  git
  mysql-server
  nginx
  openssl
  pdns-backend-mysql
  pdns-server
  rsync
)

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
systemctl enable --now mysql
systemctl stop nginx pdns

install -d -m 0755 /usr/local/share/isuren-mondai
dpkg-query -W -f='${Package}\t${Version}\n' "${packages[@]}" | LC_ALL=C sort \
  >/usr/local/share/isuren-mondai/kakomon13-packages.tsv

mysql -uroot <<'SQL'
CREATE USER IF NOT EXISTS 'isucon'@'localhost' IDENTIFIED BY 'isucon';
GRANT ALL PRIVILEGES ON isupipe.* TO 'isucon'@'localhost';
CREATE USER IF NOT EXISTS 'isudns'@'localhost' IDENTIFIED BY 'isudns';
GRANT ALL PRIVILEGES ON isudns.* TO 'isudns'@'localhost';
FLUSH PRIVILEGES;
SQL

log "40-packages.sh: done"
