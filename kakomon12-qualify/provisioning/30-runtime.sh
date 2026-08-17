#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
MISE_VERSION="2026.8.6"
MISE_URL="https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-arm64"
MISE_SHA256="f9bd051912beb8861bf248289bfb2d8c281ff00fcdf1e44d730b8ea7e859e9a4"

# Keep the language runtime below the contestant home and use the same
# repository-wide mise layout instead of a recipe-specific /opt path.
install_mise() {
  if [ -x "${MISE_BIN}" ] &&
    [ "$("${MISE_BIN}" --version | awk '{print $1}')" = "${MISE_VERSION}" ]; then
    log "mise: already installed"
    return
  fi

  local binary
  binary="$(mktemp)"
  if ! curl -fsSL "${MISE_URL}" -o "${binary}"; then
    rm -f "${binary}"
    return 1
  fi
  if ! echo "${MISE_SHA256}  ${binary}" | sha256sum -c -; then
    rm -f "${binary}"
    return 1
  fi
  install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "$(dirname "${MISE_BIN}")"
  install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${binary}" "${MISE_BIN}"
  rm -f "${binary}"
  log "mise: installed ${MISE_VERSION}"
}

set_bashrc() {
  local bashrc="${ISUREN_HOME}/.bashrc"
  # shellcheck disable=SC2016 # Write the activation command literally.
  local line='eval "$(~/.local/bin/mise activate bash)"'
  if ! grep -qF "${line}" "${bashrc}" 2>/dev/null; then
    echo "${line}" >>"${bashrc}"
    chown "${ISUREN_USER}:${ISUREN_USER}" "${bashrc}"
    log "bashrc: added mise activate"
  else
    log "bashrc: already configured"
  fi
}

set_mise_config() {
  local conf="${ISUREN_HOME}/.config/mise/config.toml"
  install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "$(dirname "${conf}")"
  install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.toml" "${conf}"
  log "mise config: ${conf} set"
}

set_mise_lock() {
  local lock="${ISUREN_HOME}/.config/mise/mise.lock"
  install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.lock" "${lock}"
  log "mise lock: ${lock} set"
}

run_mise_install() {
  runuser -u "${ISUREN_USER}" -- env HOME="${ISUREN_HOME}" "${MISE_BIN}" install
  log "mise install: done"
}

install_mise
set_bashrc
set_mise_config
set_mise_lock
run_mise_install

log "30-runtime.sh: done"
