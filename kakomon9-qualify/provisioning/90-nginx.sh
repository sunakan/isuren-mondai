#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

TLS_DIR=/etc/isuren-mondai/kakomon9-qualify/tls
TLS_LISTEN=''
TLS_DIRECTIVES=''
if [ "${ENABLE_TEST_TLS}" = true ]; then
  install -d -m 0700 "${TLS_DIR}"
  cat >"${TLS_DIR}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no
[dn]
CN = ${APP_HOST}
[extensions]
subjectAltName = DNS:${APP_HOST},DNS:${APP_COMPAT_HOST}
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
    -config "${TLS_DIR}/openssl.cnf" \
    -keyout "${TLS_DIR}/server.key" \
    -out "${TLS_DIR}/server.crt"
  chmod 0600 "${TLS_DIR}/server.key"
  chmod 0644 "${TLS_DIR}/server.crt"
  TLS_LISTEN='listen 443 ssl;'
  TLS_DIRECTIVES="ssl_certificate ${TLS_DIR}/server.crt;"$'\n'"    ssl_certificate_key ${TLS_DIR}/server.key;"
  openssl x509 -in "${TLS_DIR}/server.crt" -noout -fingerprint -sha256 >"${PROVENANCE_DIR}/test-tls-fingerprint.txt"
  cat >"${PROVENANCE_DIR}/test-tls-policy.txt" <<EOF
usage=public self-signed practice fixture only
hostname=${APP_HOST}
compat_hostname=${APP_COMPAT_HOST}
private_key_mode=0600
prohibited=mTLS, Portal authentication, credentials, trusted production traffic
EOF
fi

cat >/etc/nginx/sites-available/kakomon9-qualify.conf <<EOF
server {
    listen 80;
    ${TLS_LISTEN}
    server_name ${APP_HOST} ${APP_COMPAT_HOST};
    ${TLS_DIRECTIVES}

    client_max_body_size 10m;
    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/kakomon9-qualify.conf /etc/nginx/sites-enabled/kakomon9-qualify.conf
nginx -t
systemctl enable nginx
systemctl restart nginx
curl --fail --silent --output /dev/null --header "Host: ${APP_HOST}" http://127.0.0.1/

log "90-nginx.sh: ${APP_HOST} proxy ready; test_tls=${ENABLE_TEST_TLS}"
