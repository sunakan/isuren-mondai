#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon13-staging"
BENCH_DIR="${ISUREN_HOME}/isucon13/bench"
BENCH_OUTPUT="${STAGING_DIR}/bench-linux-arm64"

install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${BENCH_DIR}/scenario/testdata"
rsync -a "${STAGING_DIR}/official/bench/internal/scheduler/images/" \
  "${BENCH_DIR}/internal/scheduler/images/"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${STAGING_DIR}/official/bench/scenario/testdata/NoImage.jpg" \
  "${BENCH_DIR}/scenario/testdata/NoImage.jpg"

# shellcheck disable=SC2016 # positional parameters expand inside the child shell
runuser -u "${ISUREN_USER}" -- env CGO_ENABLED=0 GOOS=linux GOARCH=arm64 \
  sh -c 'cd "$1" && /usr/local/bin/go build -trimpath -ldflags "-s -w" -o "$2" ./cmd/bench' \
  sh "${BENCH_DIR}" "${BENCH_OUTPUT}"
test -x "${BENCH_OUTPUT}"

log "70-benchmark.sh: done"
