#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OFFICIAL_SOURCE_DIR="${KAKOMON13_OFFICIAL_SOURCE_DIR:-${ROOT_DIR}/tmp/all-kakomon/isucon13}"
FRONTEND_MANIFEST="${KAKOMON13_FRONTEND_MANIFEST:-${ROOT_DIR}/kakomon13/dist/frontend.manifest.sha256}"
stage="$(mktemp -d)"
state_dir="${KAKOMON13_GO_STATE_DIR:-${stage}/go-state}"
trap 'rm -rf "${stage}"' EXIT

export GOTOOLCHAIN=go1.26.6
export GOPATH="${state_dir}/gopath"
export GOMODCACHE="${state_dir}/gomodcache"
export GOCACHE="${state_dir}/gocache"

test "$(go version)" = "go version go1.26.6 darwin/arm64"
KAKOMON13_OFFICIAL_SOURCE_DIR="${OFFICIAL_SOURCE_DIR}" \
  "${ROOT_DIR}/kakomon13/scripts/verify-official-source.sh" >/dev/null
test -f "${FRONTEND_MANIFEST}" || {
  echo "error: build frontend first; missing ${FRONTEND_MANIFEST}" >&2
  exit 1
}

mkdir -p "${stage}/webapp" "${stage}/bench/assets/data"
rsync -a "${ROOT_DIR}/upstream/isucon13/webapp/go/" "${stage}/webapp/"
rsync -a "${ROOT_DIR}/upstream/isucon13/bench/" "${stage}/bench/"
mkdir -p "${stage}/bench/scenario/testdata"
rsync -a "${OFFICIAL_SOURCE_DIR}/bench/internal/scheduler/images/" \
  "${stage}/bench/internal/scheduler/images/"
install -m 0644 "${OFFICIAL_SOURCE_DIR}/bench/scenario/testdata/NoImage.jpg" \
  "${stage}/bench/scenario/testdata/NoImage.jpg"
install -m 0644 "${FRONTEND_MANIFEST}" "${stage}/bench/assets/data/hash.txt"

(
  cd "${stage}/webapp"
  go test ./...
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o "${stage}/isupipe-linux-arm64" .
)
(
  cd "${stage}/bench"
  packages=()
  while IFS= read -r package; do
    if [ "${package}" != "github.com/isucon/isucon13/bench/isupipe" ]; then
      packages+=("${package}")
    fi
  done < <(go list ./...)
  go test "${packages[@]}"
  go test -c -o "${stage}/bench-isupipe-tests" ./isupipe
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -o "${stage}/bench-linux-arm64" ./cmd/bench
)

file "${stage}/isupipe-linux-arm64" "${stage}/bench-linux-arm64"
echo "kakomon13 Go 1.26.6 test/build: ok"
echo "bench/isupipe: compile-only; runtime DNS suite belongs to the standalone gate"
