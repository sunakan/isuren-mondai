#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

systemctl enable --now mysql
mysqladmin --defaults-file=/dev/null --user=root ping

log "40-mysql.sh: mysql enabled and running"
