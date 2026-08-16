#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# The Go process parses webapp/public/index.html at startup, so it must start
# only after 80-frontend.sh has placed the verified official public tree.
systemctl restart isucari-go.service
for _ in $(seq 1 30); do
  if curl --fail --silent --output /dev/null http://127.0.0.1:8000/; then
    log "87-start-services.sh: Application ready on 127.0.0.1:8000"
    exit 0
  fi
  sleep 1
done
journalctl -u isucari-go.service --no-pager -n 100 >&2
exit 1
