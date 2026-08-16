#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

systemctl stop nginx pdns mysql isupipe-go kakomon13-pdns-zone kakomon13-instance-init
# TLS証明書はここでは削除せず、90-services.shが生成したものをsealed imageへ残す。
# standalone bench nodeがWeb側の自己署名証明書を信頼するには、本来fresh boot後に
# trust anchorを別途配布する必要があるが(README.md参照)、本家isucon13自体が固定の
# ワイルドカード証明書(秘密鍵ごと)を全競技者に配布して運用していたため、それに倣う。
rm -f \
  "/home/${ISUREN_USER}/env.sh" \
  /etc/isuren/kakomon13/mysql.cnf
mysql_datadir=/var/lib/mysql
if [ -d "${mysql_datadir}" ]; then
  # The zone service recreates these records with the clone/fresh-boot address.
  # Do not retain a builder address in the common artifact.
  systemctl start mysql
  mysql -uroot isudns -e 'DELETE FROM records; DELETE FROM domains;'
  systemctl stop mysql
fi
# The installed /home/isuren/bench binary embeds its runtime assets. Keep the
# executable, but remove the benchmark source tree and other build-only files.
rm -rf \
  "/home/${ISUREN_USER}/.kakomon13-staging" \
  "/home/${ISUREN_USER}/isucon13"
rm -rf "/home/${ISUREN_USER}/.cache/go-build" "/home/${ISUREN_USER}/go"

log "95-seal.sh: done"
