#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Unlike kakomon13, this recipe has no per-clone identity that the TLS
# certificate or nginx config depend on (isucon12-qualify's benchmarker
# forces its own TCP destination via -target-addr and only uses the Host
# header/SNI for routing; see README.md), so the wildcard certificate can be
# generated once here at build time instead of by a fresh-boot runtime
# service. It is intentionally kept in the sealed image (95-provenance.sh
# does not remove it) and registered with the OS trust store, following the
# official ISUCON13 shared-certificate precedent already adopted by kakomon13
# for the same reason: every clone shares the same key so a standalone Bench
# node can verify Web over TLS without a separate trust-anchor distribution
# step. It is a public practice fixture for a single time-boxed competition
# over dummy data; it must never be reused for mTLS, Portal authentication,
# credentials, or trusted production traffic.
install -d -m 0755 /etc/nginx/tls
if [ ! -s /etc/nginx/tls/t.isuren.internal.key ] || [ ! -s /etc/nginx/tls/t.isuren.internal.crt ]; then
  openssl req -x509 -nodes -newkey rsa:3072 \
    -keyout /etc/nginx/tls/t.isuren.internal.key \
    -out /etc/nginx/tls/t.isuren.internal.crt \
    -days 3650 \
    -subj '/CN=t.isuren.internal' \
    -addext 'subjectAltName=DNS:t.isuren.internal,DNS:*.t.isuren.internal'
fi
chmod 0600 /etc/nginx/tls/t.isuren.internal.key
chmod 0644 /etc/nginx/tls/t.isuren.internal.crt

# server_name is a single wildcard, matching the official
# `server_name *.t.isucon.dev;` (provisioning/mitamae/cookbooks/nginx/isuports.conf):
# nginx does not need per-tenant subdomains listed individually, and neither
# does DNS -- both Web and Bench resolve `*.t.isuren.internal` to a single IP
# in this compact/standalone topology (see README.md).
cat >/etc/nginx/sites-available/isuports.conf <<'EOF'
server {
  listen 443 ssl;
  server_name *.t.isuren.internal;

  ssl_certificate     /etc/nginx/tls/t.isuren.internal.crt;
  ssl_certificate_key /etc/nginx/tls/t.isuren.internal.key;
  ssl_protocols       TLSv1.3;
  ssl_prefer_server_ciphers off;

  client_max_body_size 10m;
  root /home/isuren/webapp/public;

  location / {
    try_files $uri /index.html;
  }

  location ~ ^/(api|initialize) {
    proxy_set_header Host $host;
    proxy_read_timeout 600;
    proxy_pass http://127.0.0.1:3000;
  }

  location /auth/ {
    proxy_set_header Host $host;
    proxy_pass http://127.0.0.1:3001;
  }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/isuports.conf /etc/nginx/sites-enabled/isuports.conf
nginx -t
systemctl enable nginx
systemctl restart nginx
curl -fsSk -o /dev/null -H 'Host: admin.t.isuren.internal' https://127.0.0.1/

# Trust the fixed certificate at the OS level so a standalone Bench node can
# verify Web over TLS without a separate trust-anchor distribution step.
install -m 0644 /etc/nginx/tls/t.isuren.internal.crt \
  /usr/local/share/ca-certificates/t.isuren.internal.crt
update-ca-certificates

log "90-nginx.sh: wildcard vhost and fixed TLS certificate ready"
