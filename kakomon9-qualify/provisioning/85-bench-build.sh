#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
ISUREN_HOME="/home/${ISUREN_USER}"
BENCH_BIN="${APP_ROOT}/bin/benchmarker"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}/bin"
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" ./cmd/bench
' bash "${APP_ROOT}" "${MISE_BIN}" "${BENCH_BIN}"

# Remove the earlier practice-image paths when provisioning is rerun. There is
# intentionally no wrapper: callers run the official benchmarker and inspect
# its final JSON object as the authoritative result.
rm -f "${ISUREN_HOME}/bench" "${ISUREN_HOME}/run-benchmark"

# The binary needs initial-data/ and webapp/public/static at runtime, but the
# bench Go packages and their module entrypoint are compile-time inputs only.
# Keep the participant Application source and delete just the benchmark source.
rm -rf "${APP_ROOT}/bench" "${APP_ROOT}/cmd/bench"
rmdir "${APP_ROOT}/cmd"
rm -f "${APP_ROOT}/go.mod" "${APP_ROOT}/go.sum"
test ! -e "${APP_ROOT}/bench"
test ! -e "${APP_ROOT}/cmd"

# Both Go builds are complete. GOPATH and the build cache are build inputs, not
# part of the participant filesystem contract.
rm -rf "${ISUREN_HOME}/go" "${ISUREN_HOME}/.cache/go-build"

# Payment and shipment are owned by each benchmark process. Persistent mock
# services would collide with ports 5555 and 7001 and are intentionally absent.
if ss -ltn | grep -Eq ':(5555|7001)[[:space:]]'; then
  echo 'payment or shipment mock unexpectedly persists before benchmark' >&2
  exit 1
fi

chown "${ISUREN_USER}:${ISUREN_USER}" "${BENCH_BIN}"
log "85-bench-build.sh: official-layout benchmark built and build-only source/cache removed; mocks remain one-shot responsibilities"
