#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
# The official binary/gitignore name is "isuumo" (webapp/go/.gitignore, and
# the module path github.com/isucon/isucon10-qualify/isuumo); keep it so the
# systemd unit's ExecStart matches the official relative layout.
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" .
' bash "${APP_ROOT}/webapp/go" "${MISE_BIN}" "${APP_ROOT}/webapp/go/isuumo"

install -m 0644 "${SCRIPT_DIR}/systemd/isuumo-go.service" /etc/systemd/system/isuumo-go.service
systemctl daemon-reload
systemctl enable --now isuumo-go.service

# The frontend static tree (80-frontend.sh) and benchmark binary
# (85-bench-build.sh) come later, but the Application itself only needs the
# DB (already loaded by 60-initdb.sh) to answer requests, so verify
# readiness here rather than deferring it to the nginx/Goss steps.
for _ in $(seq 1 30); do
  if curl --fail --silent --output /dev/null http://127.0.0.1:1323/api/chair/search/condition; then
    log "70-webapp-go.sh: Application ready on 127.0.0.1:1323"
    exit 0
  fi
  sleep 1
done
journalctl -u isuumo-go.service --no-pager -n 100 >&2
exit 1
