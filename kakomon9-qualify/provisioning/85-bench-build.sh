#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" ./cmd/bench
' bash "${APP_ROOT}" "${MISE_BIN}" "${APP_ROOT}/bin/bench"
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PROJECT_ROOT}/kakomon9-qualify/scripts/run-benchmark.sh" \
  "${APP_ROOT}/bin/run-benchmark"

# Payment and shipment are owned by each benchmark process. Persistent mock
# services would collide with ports 5555 and 7001 and are intentionally absent.
if ss -ltn | grep -Eq ':(5555|7001)[[:space:]]'; then
  echo 'payment or shipment mock unexpectedly persists before benchmark' >&2
  exit 1
fi

chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}/bin"
log "85-bench-build.sh: benchmark built; mocks remain one-shot responsibilities"
