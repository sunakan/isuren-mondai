#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

if ! getent group "${ISUREN_USER}" >/dev/null; then
  groupadd --gid "${ISUREN_GID}" "${ISUREN_USER}"
fi
if ! id "${ISUREN_USER}" >/dev/null 2>&1; then
  useradd --uid "${ISUREN_UID}" --gid "${ISUREN_GID}" --create-home --shell /bin/bash "${ISUREN_USER}"
fi
test "$(id -u "${ISUREN_USER}")" = "${ISUREN_UID}"
test "$(id -g "${ISUREN_USER}")" = "${ISUREN_GID}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "/home/${ISUREN_USER}/.local/bin" \
  "/home/${ISUREN_USER}/.config/mise" \
  "${APP_ROOT}"
install -d -m 0755 "${PROVENANCE_DIR}"

log "20-user.sh: ${ISUREN_USER} ready"
