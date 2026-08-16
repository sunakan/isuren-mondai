#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon13-staging"
FRONTEND_DIR="${STAGING_DIR}/frontend"
FRONTEND_ARCHIVE="${STAGING_DIR}/kakomon13-frontend.tar.gz"
BENCH_DATA_DIR="${ISUREN_HOME}/isucon13/bench/assets/data"
FRONTEND_RELEASE_REPO_URL="https://github.com/sunakan/isuren-mondai"

: "${FRONTEND_RELEASE_TAG:?FRONTEND_RELEASE_TAG must be an exact kakomon13 frontend release tag}"
: "${FRONTEND_RELEASE_SHA256:?FRONTEND_RELEASE_SHA256 must be the exact release archive SHA-256}"
[[ "${FRONTEND_RELEASE_TAG}" =~ ^kakomon13-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: invalid FRONTEND_RELEASE_TAG" >&2
  exit 1
}
[[ "${FRONTEND_RELEASE_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "error: invalid FRONTEND_RELEASE_SHA256" >&2
  exit 1
}

curl -fsSL \
  "${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}/kakomon13-frontend.tar.gz" \
  -o "${FRONTEND_ARCHIVE}"
echo "${FRONTEND_RELEASE_SHA256}  ${FRONTEND_ARCHIVE}" | sha256sum -c -

install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${FRONTEND_DIR}"
runuser -u "${ISUREN_USER}" -- tar -xzf "${FRONTEND_ARCHIVE}" -C "${FRONTEND_DIR}"
test -f "${FRONTEND_DIR}/LICENSE"
test -f "${FRONTEND_DIR}/frontend.manifest.sha256"
test -f "${FRONTEND_DIR}/public/index.html"
(
  cd "${FRONTEND_DIR}/public"
  sha256sum -c "../frontend.manifest.sha256"
)

install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${BENCH_DATA_DIR}"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${FRONTEND_DIR}/frontend.manifest.sha256" "${BENCH_DATA_DIR}/hash.txt"

log "60-frontend.sh: done"
