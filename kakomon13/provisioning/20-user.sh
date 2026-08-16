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

# The official image creates an empty .ssh directory and a plaintext login
# password. This image uses SSM/provider finalizers for access, so neither
# belongs in the common artifact.

sudoers="/etc/sudoers.d/99-${ISUREN_USER}-user"
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
echo "${ISUREN_USER}  ALL=(ALL) NOPASSWD:ALL" >"${tmp}"
visudo -cf "${tmp}"
install -m 0440 -o root -g root "${tmp}" "${sudoers}"

log "20-user.sh: done"
