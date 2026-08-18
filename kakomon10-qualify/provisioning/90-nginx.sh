#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# The official source has no isucon.net/*.isucon.dev/*.isucon.local reference
# (confirmed by audit, full-text grep), so unlike other targets this recipe
# needs no isuren.internal hostname mapping; nginx serves the default vhost.
cat >/etc/nginx/sites-available/kakomon10-qualify.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    client_max_body_size 10m;

    location /api {
        proxy_pass http://127.0.0.1:1323;
    }

    location /initialize {
        proxy_pass http://127.0.0.1:1323;
    }

    location / {
        root /www/data;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/kakomon10-qualify.conf /etc/nginx/sites-enabled/kakomon10-qualify.conf
nginx -t
systemctl enable nginx
systemctl restart nginx
curl --fail --silent --output /dev/null http://127.0.0.1/
curl --fail --silent --output /dev/null http://127.0.0.1/api/chair/search/condition

log "90-nginx.sh: default vhost proxy ready"
