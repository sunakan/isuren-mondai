# shellcheck shell=bash disable=SC2034
# This is the exact official public practice DB default
# (provisioning/ansible/roles/web-bootstrap/files/env.sh in the upstream
# repository). Do not change these values; they are not secrets.
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_USER=isucon
MYSQL_DBNAME=isuumo
MYSQL_PASS=isucon
