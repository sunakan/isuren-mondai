#!/usr/bin/env bash
set -euo pipefail

install -d -m 0755 /etc/isuren/kakomon13 /etc/nginx/tls
address="${KAKOMON13_SUBDOMAIN_ADDRESS:-}"
if [ -z "${address}" ]; then
  address="$(hostname -I | awk '{print $1}')"
fi
if [ -z "${address}" ]; then
  echo "error: could not determine the instance address" >&2
  exit 1
fi

umask 077
if [ ! -s /etc/nginx/tls/pipe.u.isuren.internal.key ] ||
  [ ! -s /etc/nginx/tls/pipe.u.isuren.internal.crt ]; then
  openssl req -x509 -nodes -newkey rsa:3072 \
    -keyout /etc/nginx/tls/pipe.u.isuren.internal.key \
    -out /etc/nginx/tls/pipe.u.isuren.internal.crt \
    -days 3650 \
    -subj '/CN=pipe.u.isuren.internal' \
    -addext 'subjectAltName=DNS:pipe.u.isuren.internal,DNS:u.isuren.internal,DNS:*.u.isuren.internal'
fi
chmod 0600 /etc/nginx/tls/pipe.u.isuren.internal.key
chmod 0644 /etc/nginx/tls/pipe.u.isuren.internal.crt

cat >/home/isuren/env.sh <<EOF
ISUCON13_MYSQL_DIALCONFIG_NET="tcp"
ISUCON13_MYSQL_DIALCONFIG_ADDRESS="127.0.0.1"
ISUCON13_MYSQL_DIALCONFIG_PORT="3306"
ISUCON13_MYSQL_DIALCONFIG_USER="isucon"
ISUCON13_MYSQL_DIALCONFIG_DATABASE="isupipe"
ISUCON13_MYSQL_DIALCONFIG_PARSETIME="true"
ISUCON13_POWERDNS_SUBDOMAIN_ADDRESS="${address}"
ISUCON13_POWERDNS_DISABLED="false"
EOF
chown isuren:isuren /home/isuren/env.sh
chmod 0755 /home/isuren/env.sh

cat >/etc/isuren/kakomon13/mysql.cnf <<'EOF'
[client]
user=isucon
password=isucon
host=127.0.0.1
port=3306
database=isupipe
EOF
chown root:isuren /etc/isuren/kakomon13/mysql.cnf
chmod 0640 /etc/isuren/kakomon13/mysql.cnf
