#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

systemctl enable --now mysql
mysqladmin --defaults-file=/dev/null --user=root ping

# The official env.sh keys (MYSQL_USER=isucon, MYSQL_PASS=isucon) are the
# public practice DB default; provisioning creates the matching MySQL 8.4
# account here since the AMI's mysql-server package is not the official 5.7.
# Grant scope and credential mirror the official ansible role exactly
# (`GRANT ALL PRIVILEGES ON *.* TO isucon@localhost ... WITH GRANT OPTION`).
mysql --defaults-file=/dev/null --user=root -e \
  "CREATE USER IF NOT EXISTS isucon@localhost IDENTIFIED BY 'isucon'; GRANT ALL PRIVILEGES ON *.* TO isucon@localhost WITH GRANT OPTION; FLUSH PRIVILEGES;"

log "40-mysql.sh: mysql 8.4 enabled, running, and isucon account granted"
