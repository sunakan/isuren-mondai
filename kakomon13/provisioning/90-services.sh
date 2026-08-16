#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

install -d -m 0755 /etc/isuren/kakomon13 /etc/nginx/tls /etc/systemd/system/nginx.service.d
install -m 0644 "${SCRIPT_DIR}/config/nginx.conf" /etc/nginx/sites-available/isupipe.conf
ln -sfn /etc/nginx/sites-available/isupipe.conf /etc/nginx/sites-enabled/isupipe.conf
rm -f /etc/nginx/sites-enabled/default

install -d -m 0755 /etc/powerdns/pdns.d
install -m 0644 "${SCRIPT_DIR}/config/pdns.conf" /etc/powerdns/pdns.conf
install -m 0640 -o root -g pdns "${SCRIPT_DIR}/config/gmysql-host.conf" \
  /etc/powerdns/pdns.d/gmysql-host.conf
rm -f /etc/powerdns/pdns.d/bind.conf
install -d -m 0755 /etc/systemd/resolved.conf.d
install -m 0644 "${SCRIPT_DIR}/config/resolved.conf" \
  /etc/systemd/resolved.conf.d/kakomon13.conf
ln -sfn /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl restart systemd-resolved

install -m 0755 "${SCRIPT_DIR}/runtime/instance-init.sh" /usr/local/libexec/kakomon13-instance-init
install -m 0755 "${SCRIPT_DIR}/runtime/pdns-zone.sh" /usr/local/libexec/kakomon13-pdns-zone
install -m 0755 "${SCRIPT_DIR}/runtime/reset.sh" /usr/local/libexec/kakomon13-reset
install -m 0644 "${SCRIPT_DIR}/systemd/kakomon13-instance-init.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/kakomon13-pdns-zone.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/isupipe-go.service" /etc/systemd/system/
install -m 0644 "${SCRIPT_DIR}/systemd/nginx-kakomon13.conf" \
  /etc/systemd/system/nginx.service.d/kakomon13.conf

usermod -a -G pdns "${ISUREN_USER}"
systemctl daemon-reload
systemctl enable mysql pdns nginx isupipe-go kakomon13-instance-init kakomon13-pdns-zone

# Validate the exact fresh-boot configuration, then remove the generated
# instance material in 95-seal.sh. These keys never become image input.
/usr/local/libexec/kakomon13-instance-init
nginx -t
pdns_server --config=check

log "90-services.sh: done"
