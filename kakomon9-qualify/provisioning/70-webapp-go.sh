#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" .
' bash "${APP_ROOT}/webapp/go" "${MISE_BIN}" "${APP_ROOT}/webapp/go/isucari"

# Remove the path used by the earlier practice-image layout when this step is
# rerun on an existing machine. The maintained image follows the official
# relative path under isucari/webapp/go.
rm -f "${APP_ROOT}/bin/isucari"

install -m 0644 "${SCRIPT_DIR}/systemd/isucari-go.service" /etc/systemd/system/isucari-go.service
systemctl daemon-reload
systemctl enable isucari-go.service

log "70-webapp-go.sh: Application built at the official relative path and service enabled"
