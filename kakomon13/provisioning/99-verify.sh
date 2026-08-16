#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

GOSS_VERSION="0.4.10"
GOSS_URL="https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_arm64.tar.gz"
GOSS_SHA256="90a59612b4d67d9f1a9038634c000790136bb82526a69de1e81ac075c2f6d2c6"
archive="$(mktemp)"
staging="$(mktemp -d)"
trap 'rm -f "${archive}"; rm -rf "${staging}"' EXIT

log "99-verify.sh: goss validate start"
curl -fsSL "${GOSS_URL}" -o "${archive}"
echo "${GOSS_SHA256}  ${archive}" | sha256sum -c -
tar -xzf "${archive}" -C "${staging}"
test "$("${staging}/goss" --version)" = "goss version v${GOSS_VERSION}"
"${staging}/goss" validate -g "${SCRIPT_DIR}/goss.yaml" --format documentation
log "99-verify.sh: goss validate end"
log "99-verify.sh: done"
