#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /home/isuren/env.sh
zone=u.isuren.internal
address="${ISUCON13_POWERDNS_SUBDOMAIN_ADDRESS}"

if pdnsutil list-all-zones | grep -qx "${zone}"; then
  pdnsutil delete-zone "${zone}"
fi

# 公式のu.isucon.dev.zone(webapp/pdns/init_zone.sh相当)由来。DefaultDNSRecord
# (bench側のservice名リスト)と全initial userぶんのAレコードを含んだ完全な
# ゾーンでないと、ベンチマーカーのdnsRecordPretestがランダムなservice名の
# 名前解決に失敗しクリティカルエラーで即停止する(pipe/test001の3レコードのみ
# のadd-recordでは不足)。
zone_file="$(mktemp)"
trap 'rm -f "${zone_file}"' EXIT
sed "s/<ISUCON_SUBDOMAIN_ADDRESS>/${address}/g" \
  /home/isuren/webapp/pdns/u.isuren.internal.zone >"${zone_file}"
pdnsutil load-zone "${zone}" "${zone_file}"
