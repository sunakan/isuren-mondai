#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
WEBAPP_PUBLIC_DIR="${ISUREN_HOME}/webapp/public"
SITE_AVAILABLE="/etc/nginx/sites-available/isuride.conf"
SITE_ENABLED="/etc/nginx/sites-enabled/isuride.conf"
DEFAULT_ENABLED="/etc/nginx/sites-enabled/default"
TLS_DIR="/etc/nginx/tls"
TLS_CERT="${TLS_DIR}/_.xiv.isucon.net.crt"
TLS_KEY="${TLS_DIR}/_.xiv.isucon.net.key"

# 対応: isucon14/provisioning/ansible/roles/nginx/tasks/main.yaml「Install package」
# 2回目以降にネットワークへ出ないよう、未インストールのときだけapt-get updateする。
install_nginx() {
  if ! dpkg -s nginx >/dev/null 2>&1; then
    apt-get update
    apt-get install -y nginx
    log "nginx: installed"
  else
    log "nginx: already installed"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/nginx/files/etc/nginx/tls/_.xiv.isucon.net.{crt,key}
# 公式証明書は失効済み(2025年2月)のため自己署名で代用する。ベンチはTLS検証をしないため問題ない。
# 有効期限が近い(30日未満)/存在しない場合のみ再生成する冪等な作りにする。
generate_tls_cert() {
  if [ "${ENABLE_TLS}" != "true" ]; then
    return
  fi
  mkdir -p "${TLS_DIR}"
  if [ -f "${TLS_CERT}" ] && openssl x509 -checkend 2592000 -noout -in "${TLS_CERT}" >/dev/null 2>&1; then
    log "nginx tls cert: already valid"
  else
    openssl req -x509 -nodes -newkey rsa:2048 \
      -keyout "${TLS_KEY}" -out "${TLS_CERT}" \
      -days 3650 \
      -subj "/CN=*.xiv.isucon.net" \
      -addext "subjectAltName=DNS:*.xiv.isucon.net,DNS:xiv.isucon.net"
    log "nginx tls cert: generated"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/nginx/files/etc/nginx/sites-available/isuride.conf
# 公式は443のみでTLS必須の構成だが、まずTLSなしのHTTP版で静的配信+/apiプロキシの経路を通す。
# ボット避けのデフォルトvhost(公式L1-26)は本番運営向けのセキュリティ対策であり、
# このbastionでは不要なため省略し、単一のHTTP vhostのみにした。
# ENABLE_TLS=trueのときのみ、公式L28-56相当の443 vhost(xiv.isucon.net向け)を追加する。
set_site_config() {
  local content
  content=$(
    cat <<EOD
server {
  listen 80 default_server;
  server_name _;

  client_max_body_size 10m;
  root ${WEBAPP_PUBLIC_DIR};

  location / {
    try_files \$uri /index.html;
  }

  location /api/ {
    proxy_set_header Host \$host;
    proxy_pass http://localhost:8080;
  }

  location /api/internal/ {
    # localhostからのみアクセスを許可
    allow 127.0.0.1;
    deny all;
    proxy_set_header Host \$host;
    proxy_pass http://localhost:8080;
  }
}
EOD
  )
  if [ "${ENABLE_TLS}" = "true" ]; then
    content="${content}
$(cat <<EOD

server {
  listen 443 ssl;
  server_name xiv.isucon.net;
  server_name *.xiv.isucon.net;

  ssl_certificate ${TLS_CERT};
  ssl_certificate_key ${TLS_KEY};
  ssl_protocols TLSv1.3;
  ssl_prefer_server_ciphers off;

  client_max_body_size 10m;
  root ${WEBAPP_PUBLIC_DIR};

  location / {
    try_files \$uri /index.html;
  }

  location /api/ {
    proxy_set_header Host \$host;
    proxy_pass http://localhost:8080;
  }

  location /api/internal/ {
    # localhostからのみアクセスを許可
    allow 127.0.0.1;
    deny all;
    proxy_set_header Host \$host;
    proxy_pass http://localhost:8080;
  }
}
EOD
)"
  fi
  if [ ! -f "${SITE_AVAILABLE}" ] || [ "$(cat "${SITE_AVAILABLE}")" != "${content}" ]; then
    echo "${content}" >"${SITE_AVAILABLE}"
    log "nginx site config: changed ${SITE_AVAILABLE}"
  else
    log "nginx site config: already up to date"
  fi
}

enable_site() {
  if [ ! -L "${SITE_ENABLED}" ] || [ "$(readlink "${SITE_ENABLED}")" != "${SITE_AVAILABLE}" ]; then
    ln -sfn "${SITE_AVAILABLE}" "${SITE_ENABLED}"
    log "nginx site: enabled"
  else
    log "nginx site: already enabled"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/nginx/tasks/main.yaml「Delete default config」
remove_default_site() {
  if [ -e "${DEFAULT_ENABLED}" ] || [ -L "${DEFAULT_ENABLED}" ]; then
    rm -f "${DEFAULT_ENABLED}"
    log "nginx default site: removed"
  else
    log "nginx default site: already removed"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/nginx/tasks/main.yaml「check nginx config」「Start nginx」
reload_nginx() {
  nginx -t
  systemctl enable nginx
  systemctl reload-or-restart nginx
  log "nginx: reloaded"
}

install_nginx
generate_tls_cert
set_site_config
enable_site
remove_default_site
reload_nginx

log "90-nginx.sh: done"
