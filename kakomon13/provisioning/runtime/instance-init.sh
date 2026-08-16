#!/usr/bin/env bash
set -euo pipefail

wait_for_instance_address() {
  local remaining=120 address default_interface

  while ((remaining > 0)); do
    default_interface="$(
      ip -4 route show default |
        awk '{for (field = 1; field <= NF; field++) if ($field == "dev") { print $(field + 1); exit }}'
    )"
    address="$(
      ip -4 -o address show scope global |
        awk -v interface="${default_interface}" \
          '$2 == interface { sub(/\/.*/, "", $4); print $4; exit }'
    )"
    if [ -n "${default_interface}" ] && [ -n "${address}" ]; then
      printf '%s\n' "${address}"
      return 0
    fi

    sleep 1
    remaining=$((remaining - 1))
  done

  echo "error: timed out waiting for an IPv4 address and default route" >&2
  return 1
}

install -d -m 0755 /etc/isuren/kakomon13 /etc/nginx/tls
address="${KAKOMON13_SUBDOMAIN_ADDRESS:-}"
if [ -z "${address}" ]; then
  address="$(wait_for_instance_address)"
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
