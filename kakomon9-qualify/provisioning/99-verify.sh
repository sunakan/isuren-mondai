#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

GOSS_VERSION="0.4.10"
GOSS_URL="https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_arm64.tar.gz"
GOSS_SHA256="90a59612b4d67d9f1a9038634c000790136bb82526a69de1e81ac075c2f6d2c6"
JOURNAL_UNITS=(isucari-go nginx mysql)
journal_args=()
for unit in "${JOURNAL_UNITS[@]}"; do
  journal_args+=(-u "${unit}")
done
archive="$(mktemp)"
staging="$(mktemp -d)"
trap 'rm -f "${archive}"; rm -rf "${staging}"' EXIT

# kakomon9-qualify独自: the optional public TLS fixture is checked before the
# common sealed-image Goss contract.
if [ "${ENABLE_TEST_TLS}" = true ]; then
  test "$(stat -c '%a' /etc/isuren-mondai/kakomon9-qualify/tls/server.key)" = 600
  openssl x509 -in /etc/isuren-mondai/kakomon9-qualify/tls/server.crt -noout -ext subjectAltName |
    grep -Fq "DNS:${APP_HOST}"
  openssl x509 -in /etc/isuren-mondai/kakomon9-qualify/tls/server.crt -noout -ext subjectAltName |
    grep -Fq "DNS:${APP_COMPAT_HOST}"
  ss -ltnH | awk '{print $4}' | grep -Eq '(^|:)443$'
  curl --fail --silent --insecure --output /dev/null \
    --resolve "${APP_HOST}:443:127.0.0.1" "https://${APP_HOST}/"
fi

# Download the verifier into a temporary directory, validate its exact
# identity, and remove it after the sealed single-host check completes.
log "99-verify.sh: goss validate start"
curl -fsSL "${GOSS_URL}" -o "${archive}"
echo "${GOSS_SHA256}  ${archive}" | sha256sum -c -
tar -xzf "${archive}" -C "${staging}"
GOSS_BIN="${staging}/goss"
test -x "${GOSS_BIN}"
test "$("${GOSS_BIN}" --version)" = "goss version ${GOSS_VERSION}"

if ! "${GOSS_BIN}" validate -g "${SCRIPT_DIR}/goss.yaml" \
  --format documentation --retry-timeout 30s --sleep 1s; then
  log "99-verify.sh: goss validate failed, dumping target journal"
  journalctl "${journal_args[@]}" --no-pager -n 150 || true
  exit 1
fi

log "99-verify.sh: goss validate end"
log "99-verify.sh: done"
