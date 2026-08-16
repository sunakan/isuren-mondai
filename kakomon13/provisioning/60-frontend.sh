#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon13-staging"
FRONTEND_DIR="${STAGING_DIR}/frontend"
FRONTEND_ARCHIVE="${STAGING_DIR}/kakomon13-frontend.tar.gz"
FRONTEND_CHECKSUM="${FRONTEND_ARCHIVE}.sha256"
BENCH_DATA_DIR="${ISUREN_HOME}/isucon13/bench/assets/data"
FRONTEND_RELEASE_REPO_URL="https://github.com/sunakan/isuren-mondai"
FRONTEND_RELEASE_OWNER_REPO="sunakan/isuren-mondai"
RESOLVED_TAG_FILE="/tmp/kakomon13-frontend-release-tag"
RESOLVED_SHA256_FILE="/tmp/kakomon13-frontend-release-sha256"

: "${FRONTEND_RELEASE_TAG:=latest}"
[[ "${FRONTEND_RELEASE_TAG}" == "latest" ||
  "${FRONTEND_RELEASE_TAG}" =~ ^kakomon13-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: invalid FRONTEND_RELEASE_TAG selector" >&2
  exit 1
}

resolve_frontend_release_tag() {
  if [ "${FRONTEND_RELEASE_TAG}" != "latest" ]; then
    return
  fi
  local resolved
  resolved="$(curl -fsSL "https://api.github.com/repos/${FRONTEND_RELEASE_OWNER_REPO}/releases" |
    grep -o '"tag_name": *"kakomon13-frontend-[^"]*"' | head -n1 |
    sed -E 's/.*"(kakomon13-frontend-[^"]*)"$/\1/')"
  if [ -z "${resolved}" ]; then
    echo "error: kakomon13-frontendのReleaseが見つかりませんでした(GitHub API: ${FRONTEND_RELEASE_OWNER_REPO})" >&2
    exit 1
  fi
  FRONTEND_RELEASE_TAG="${resolved}"
  log "frontend release: latestを${FRONTEND_RELEASE_TAG}に解決"
}

persist_resolved_tag() {
  printf '%s\n' "${FRONTEND_RELEASE_TAG}" >"${RESOLVED_TAG_FILE}"
}

download_frontend_release() {
  local base_url="${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}"
  runuser -u "${ISUREN_USER}" -- mkdir -p "${STAGING_DIR}"
  runuser -u "${ISUREN_USER}" -- curl -fsSL \
    "${base_url}/kakomon13-frontend.tar.gz" -o "${FRONTEND_ARCHIVE}"
  runuser -u "${ISUREN_USER}" -- curl -fsSL \
    "${base_url}/kakomon13-frontend.tar.gz.sha256" -o "${FRONTEND_CHECKSUM}"
  (
    cd "${STAGING_DIR}"
    sha256sum --check "$(basename "${FRONTEND_CHECKSUM}")"
  )
  FRONTEND_RELEASE_SHA256="$(sha256sum "${FRONTEND_ARCHIVE}" | awk '{print $1}')"
  printf '%s\n' "${FRONTEND_RELEASE_SHA256}" >"${RESOLVED_SHA256_FILE}"
  log "frontend release: downloaded ${FRONTEND_RELEASE_TAG} (${FRONTEND_RELEASE_SHA256})"
}

resolve_frontend_release_tag
persist_resolved_tag
download_frontend_release

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
