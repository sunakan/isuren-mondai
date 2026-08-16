#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Keep the contestant account contract identical across recipes. Access keys,
# passwords, and machine identity belong to the provider/fresh-boot boundary.
create_group() {
  if ! getent group "${ISUREN_USER}" >/dev/null 2>&1; then
    groupadd -g 1100 "${ISUREN_USER}"
    log "group: created ${ISUREN_USER}(gid=1100)"
  else
    log "group: already exists"
  fi
}

create_user() {
  if ! id -u "${ISUREN_USER}" >/dev/null 2>&1; then
    useradd -u 1100 -g "${ISUREN_USER}" -d "/home/${ISUREN_USER}" -m -s /bin/bash "${ISUREN_USER}"
    log "user: created ${ISUREN_USER}(uid=1100)"
  else
    log "user: already exists"
  fi
}

chmod_home() {
  local home="/home/${ISUREN_USER}"
  chmod 0755 "${home}"
  log "home: chmod 755 ${home}"
}

# The official .ssh directory, plaintext login password, and authorized keys
# are intentionally not copied into the common image. Provider access owns them.
set_sudoers() {
  local conf="/etc/sudoers.d/99-${ISUREN_USER}-user"
  local content="${ISUREN_USER}  ALL=(ALL) NOPASSWD:ALL"
  local tmp
  tmp="$(mktemp)"
  echo "${content}" >"${tmp}"
  visudo -cf "${tmp}"
  install -m 0440 -o root -g root "${tmp}" "${conf}"
  rm -f "${tmp}"
  log "sudoers: ${conf} set"
}

create_group
create_user
chmod_home
set_sudoers

# Create the home-owned mise directories before the runtime step consumes them.
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "/home/${ISUREN_USER}/.local" \
  "/home/${ISUREN_USER}/.config" \
  "/home/${ISUREN_USER}/.local/bin" \
  "/home/${ISUREN_USER}/.config/mise"

log "20-user.sh: done"
