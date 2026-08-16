#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}/bin"
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" .
' bash "${APP_ROOT}/webapp/go" "${MISE_BIN}" "${APP_ROOT}/bin/isucari"

install -m 0644 "${SCRIPT_DIR}/systemd/isucari-go.service" /etc/systemd/system/isucari-go.service
systemctl daemon-reload
systemctl enable isucari-go.service

log "70-webapp-go.sh: Application built and service enabled"
