#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

GOSS_VERSION=0.4.10
GOSS_URL=https://github.com/goss-org/goss/releases/download/v0.4.10/goss_0.4.10_linux_arm64.tar.gz
GOSS_SHA256=90a59612b4d67d9f1a9038634c000790136bb82526a69de1e81ac075c2f6d2c6
temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 --output "${temporary}/goss.tar.gz" "${GOSS_URL}"
printf '%s  %s\n' "${GOSS_SHA256}" "${temporary}/goss.tar.gz" | sha256sum --check --status
tar -xzf "${temporary}/goss.tar.gz" -C "${temporary}"
GOSS_BIN="${temporary}/goss"
test -x "${GOSS_BIN}"

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

log "99-verify.sh: goss ${GOSS_VERSION} validate start"
if ! "${GOSS_BIN}" --gossfile "${SCRIPT_DIR}/goss.yaml" validate --format documentation --retry-timeout 30s --sleep 1s; then
  journalctl -u isucari-go.service -u nginx.service -u mysql.service --no-pager -n 150 >&2 || true
  exit 1
fi
log "99-verify.sh: goss validate end"
