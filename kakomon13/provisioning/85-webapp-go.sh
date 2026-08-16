#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

WEBAPP_DIR="/home/${ISUREN_USER}/webapp/go"
# shellcheck disable=SC2016 # positional parameter expands inside the child shell
runuser -u "${ISUREN_USER}" -- sh -c 'cd "$1" && /usr/local/bin/go build -trimpath -ldflags "-s -w" -o isupipe .' sh "${WEBAPP_DIR}"
test -x "${WEBAPP_DIR}/isupipe"

log "85-webapp-go.sh: done"
