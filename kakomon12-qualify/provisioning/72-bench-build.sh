#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
BUILD_ROOT="${ISUREN_HOME}/.build/isucon12-qualify"
ARTIFACT_EXTRACT_DIR="${ARTIFACT_DIR}/extracted"
# bench/scenario.go derives the admin URL as `b.Scheme+"://admin."+b.Host`
# from whatever -target-url resolves to, and bench/models.go reads
# ./isuports.pem, ./benchmarker.json, ./benchmarker_tenant.json cwd-relative,
# and (confirmed via orb-standalone-green) a validation step also opens
# ../public/js cwd-relative. All of this only resolves correctly if bench
# runs from a bench/ directory that is a *sibling* of public/ (and of
# webapp/, blackauth/) -- i.e. the official repository root layout, not a
# single flattened binary directly under ISUREN_HOME as an earlier revision
# of this script assumed (see implementation-pitfalls.md correction).
BENCH_DIR="${ISUREN_HOME}/bench"
BENCH_BIN="${BENCH_DIR}/bench"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${BENCH_DIR}"

# bench/go.mod's `replace ../isucon12-portal`, `replace ../data`, and
# `replace ../webapp/go` directives expect these three directories as
# siblings of bench/ (50-source.sh staged that layout under BUILD_ROOT).
# shellcheck disable=SC2016 # positional parameters expand inside the child shell
runuser -u "${ISUREN_USER}" -- env HOME="${ISUREN_HOME}" CGO_ENABLED=1 MISE_BIN="${MISE_BIN}" \
  sh -c 'cd "$1" && "${MISE_BIN}" exec -- go build -trimpath -ldflags "-s -w" -o "$2" ./cmd/bench' \
  sh "${BUILD_ROOT}/bench" "${BENCH_BIN}"
# See 70-webapp-go.sh: go build's output mode was observed to be unreliable
# (0644) on Orb Golden Base. Chmod defensively here too.
chmod 0755 "${BENCH_BIN}"
test -x "${BENCH_BIN}"
chown "${ISUREN_USER}:${ISUREN_USER}" "${BENCH_BIN}"

# The official bench binary reads its own copy of the private JWT key from
# ./isuports.pem (cwd-relative os.ReadFile), unlike blackauth which embeds
# the same key at compile time via go:embed. bench/models.go's
# ./benchmarker.json / ./benchmarker_tenant.json (runtime validation
# fixtures shipped in the initial_data Release archive, not the source
# checkout -- see 05-artifacts.sh) are read the same cwd-relative way.
install -m 0600 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ISUREN_HOME}/blackauth/isuports.pem" "${BENCH_DIR}/isuports.pem"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ARTIFACT_EXTRACT_DIR}/bench/benchmarker.json" "${BENCH_DIR}/benchmarker.json"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${ARTIFACT_EXTRACT_DIR}/bench/benchmarker_tenant.json" "${BENCH_DIR}/benchmarker_tenant.json"

# bench, isucon12-portal, data, and the staged webapp/go copy are compile-time
# inputs only; the running Application already lives at
# /home/isuren/webapp/go independently of this staged tree. Remove the whole
# .build parent (not just BUILD_ROOT="${ISUREN_HOME}/.build/isucon12-qualify"),
# since `install -d` created that parent too and goss.yaml expects
# /home/isuren/.build to not exist at all.
rm -rf "${ISUREN_HOME}/.build"
rm -rf "${ISUREN_HOME}/go" "${ISUREN_HOME}/.cache/go-build"

log "72-bench-build.sh: benchmark built at /home/isuren/bench/bench; build-only source removed"
