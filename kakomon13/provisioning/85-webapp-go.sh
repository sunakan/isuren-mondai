#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
WEBAPP_DIR="${ISUREN_HOME}/webapp/go"
# shellcheck disable=SC2016 # positional parameter expands inside the child shell
runuser -u "${ISUREN_USER}" -- env HOME="${ISUREN_HOME}" MISE_BIN="${MISE_BIN}" \
  sh -c 'cd "$1" && "${MISE_BIN}" exec -- go build -trimpath -ldflags "-s -w" -o isupipe .' \
  sh "${WEBAPP_DIR}"
test -x "${WEBAPP_DIR}/isupipe"

log "85-webapp-go.sh: done"
