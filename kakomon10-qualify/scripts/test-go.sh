#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
stage="$(mktemp -d)"
state_dir="${KAKOMON10_QUALIFY_GO_STATE_DIR:-${stage}/go-state}"
cleanup() {
  chmod -R u+w "${stage}" 2>/dev/null || true
  rm -rf "${stage}"
}
trap cleanup EXIT

# Use a task-private GOCACHE/GOPATH instead of the host default: a failure
# here should mean a real build/test problem, not a host cache permission
# issue (see aws-bastion/CLAUDE.md's "Go test等のlocal validation" note).
export GOTOOLCHAIN=go1.26.6
export GOPATH="${state_dir}/gopath"
export GOMODCACHE="${state_dir}/gomodcache"
export GOCACHE="${state_dir}/gocache"

test "$(go version | awk '{print $3}')" = "go1.26.6"

(
  cd "${ROOT_DIR}/upstream/isucon10-qualify/webapp/go"
  go vet ./...
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o "${stage}/isuumo-linux-arm64" .
)
(
  cd "${ROOT_DIR}/upstream/isucon10-qualify/bench"
  go vet ./...
  go test ./...
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o "${stage}/bench-linux-arm64" ./cmd/bench
)

file "${stage}/isuumo-linux-arm64" "${stage}/bench-linux-arm64" 2>/dev/null || true
echo "kakomon10-qualify Go $(go version | awk '{print $3}') vet/test/build: ok"
