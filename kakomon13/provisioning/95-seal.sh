#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

systemctl stop nginx pdns mysql isupipe-go kakomon13-pdns-zone kakomon13-instance-init
rm -f \
  /etc/nginx/tls/pipe.u.isuren.internal.crt \
  /etc/nginx/tls/pipe.u.isuren.internal.key \
  /etc/isuren/kakomon13/runtime.env \
  /etc/isuren/kakomon13/mysql.cnf
mysql_datadir=/var/lib/mysql
if [ -d "${mysql_datadir}" ]; then
  # The zone service recreates these records with the clone/fresh-boot address.
  # Do not retain a builder address in the common artifact.
  systemctl start mysql
  mysql -uroot isudns -e 'DELETE FROM records; DELETE FROM domains;'
  systemctl stop mysql
fi
rm -rf "/home/${ISUREN_USER}/.kakomon13-staging"
rm -rf "/home/${ISUREN_USER}/.cache/go-build" "/home/${ISUREN_USER}/go/pkg/mod/cache"

log "95-seal.sh: done"
