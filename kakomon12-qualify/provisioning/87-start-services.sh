#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

systemctl restart isuports-go.service
systemctl restart blackauth.service

# Neither isuports nor blackauth register an unauthenticated "/" handler
# (isuports only exposes /api/* and /initialize; blackauth only exposes
# /login/*), so a plain `curl --fail /` would report 404/400 as failure even
# once the process is healthy. Check TCP acceptance instead.
wait_for_port() {
  local port="$1" name="$2"
  for _ in $(seq 1 30); do
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
      exec 3>&- 3<&-
      log "87-start-services.sh: ${name} ready (127.0.0.1:${port})"
      return 0
    fi
    sleep 1
  done
  journalctl -u "${name}" --no-pager -n 100 >&2
  return 1
}

wait_for_port 3000 isuports-go.service
wait_for_port 3001 blackauth.service

log "87-start-services.sh: done"
