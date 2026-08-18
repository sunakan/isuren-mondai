#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="/home/${ISUREN_USER}/.local/bin/mise"
ISUREN_HOME="/home/${ISUREN_USER}"
# bench/cmd/bench/bench.go's default flags (--data-dir ../initial-data,
# --fixture-dir ../webapp/fixture) are cwd-relative to the built binary's
# directory, so the binary stays at the official APP_ROOT/bench/bench path
# with initial-data/ and webapp/ as siblings under APP_ROOT.
# shellcheck disable=SC2016
runuser -u "${ISUREN_USER}" -- bash -c '
  set -euo pipefail
  cd "$1"
  "$2" exec -- go build -mod=readonly -trimpath -o "$3" ./cmd/bench
' bash "${APP_ROOT}/bench" "${MISE_BIN}" "${APP_ROOT}/bench/bench"

# Both Go builds are complete. GOPATH and the build cache are build inputs,
# not part of the participant filesystem contract.
rm -rf "${ISUREN_HOME}/go" "${ISUREN_HOME}/.cache/go-build"

log "85-bench-build.sh: official-layout benchmark built; build-only Go cache removed"
