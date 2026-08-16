#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_VERSION=2026.8.5
MISE_URL=https://github.com/jdx/mise/releases/download/v2026.8.5/mise-v2026.8.5-linux-arm64
MISE_SHA256=d2bde76b1f87ab50b6f456e05332bb02de56a6bf3c5d19343cc3661e5d294681
MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"

temporary="$(mktemp)"
trap 'rm -f "${temporary}"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --output "${temporary}" "${MISE_URL}"
printf '%s  %s\n' "${MISE_SHA256}" "${temporary}" | sha256sum --check --status
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${temporary}" "${MISE_BIN}"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.toml" "/home/${ISUREN_USER}/.config/mise/config.toml"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.lock" "/home/${ISUREN_USER}/.config/mise/mise.lock"

runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" install --yes
test "$(runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" exec -- go version)" = 'go version go1.26.6 linux/arm64'

# shellcheck disable=SC2016
activate='eval "$(~/.local/bin/mise activate bash)"'
grep -Fqx "${activate}" "/home/${ISUREN_USER}/.bashrc" || printf '%s\n' "${activate}" >>"/home/${ISUREN_USER}/.bashrc"
chown "${ISUREN_USER}:${ISUREN_USER}" "/home/${ISUREN_USER}/.bashrc"

log "30-runtime.sh: mise ${MISE_VERSION} and Go 1.26.6 ready"
