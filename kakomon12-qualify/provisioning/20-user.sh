#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Keep the contestant account contract identical across recipes. Access keys,
# passwords, and machine identity belong to the provider/fresh-boot boundary.
create_group() {
  if ! getent group "${ISUREN_USER}" >/dev/null 2>&1; then
    groupadd -g "${ISUREN_GID}" "${ISUREN_USER}"
    log "group: created ${ISUREN_USER}(gid=${ISUREN_GID})"
  else
    log "group: already exists"
  fi
}

create_user() {
  if ! id -u "${ISUREN_USER}" >/dev/null 2>&1; then
    useradd -u "${ISUREN_UID}" -g "${ISUREN_USER}" -d "${ISUREN_HOME}" -m -s /bin/bash "${ISUREN_USER}"
    log "user: created ${ISUREN_USER}(uid=${ISUREN_UID})"
  else
    log "user: already exists"
  fi
}

chmod_home() {
  chmod 0755 "${ISUREN_HOME}"
  log "home: chmod 755 ${ISUREN_HOME}"
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

install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ISUREN_HOME}/.local" \
  "${ISUREN_HOME}/.config" \
  "${ISUREN_HOME}/.local/bin" \
  "${ISUREN_HOME}/.config/mise"
install -d -m 0755 "${PROVENANCE_DIR}"

log "20-user.sh: done"
