#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
BLACKAUTH_DIR="${ISUREN_HOME}/blackauth"

require_file "${BLACKAUTH_DIR}/isuports.pem"
# blackauth has no CGO dependency (only webapp/go does, via mattn/go-sqlite3).
# shellcheck disable=SC2016 # positional parameter expands inside the child shell
runuser -u "${ISUREN_USER}" -- env HOME="${ISUREN_HOME}" CGO_ENABLED=0 MISE_BIN="${MISE_BIN}" \
  sh -c 'cd "$1" && "${MISE_BIN}" exec -- go build -trimpath -ldflags "-s -w" -o blackauth .' \
  sh "${BLACKAUTH_DIR}"
# See 70-webapp-go.sh: go build's output mode was observed to be unreliable
# (0644) for at least one directory in this recipe on Orb Golden Base. Chmod
# defensively here too rather than assuming CGO_ENABLED=0 avoids it.
chmod 0755 "${BLACKAUTH_DIR}/blackauth"
test -x "${BLACKAUTH_DIR}/blackauth"

install -m 0644 "${SCRIPT_DIR}/systemd/blackauth.service" /etc/systemd/system/blackauth.service
systemctl daemon-reload
systemctl enable blackauth.service

log "71-blackauth-go.sh: auth server built (private key embedded) and service enabled"
