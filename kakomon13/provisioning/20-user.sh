#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if ! getent group "${ISUREN_USER}" >/dev/null; then
  groupadd -g 1100 "${ISUREN_USER}"
fi
if ! id -u "${ISUREN_USER}" >/dev/null 2>&1; then
  useradd -u 1100 -g "${ISUREN_USER}" -d "/home/${ISUREN_USER}" -m -s /bin/bash "${ISUREN_USER}"
fi
chmod 0755 "/home/${ISUREN_USER}"

log "20-user.sh: done"
