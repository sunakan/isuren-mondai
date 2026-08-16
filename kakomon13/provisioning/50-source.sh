#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
UPSTREAM_DIR="${PROJECT_ROOT}/upstream/isucon13"
STAGING_DIR="${ISUREN_HOME}/.kakomon13-staging"
OFFICIAL_DIR="${STAGING_DIR}/official"
OFFICIAL_REPO_URL="https://github.com/isucon/isucon13.git"
OFFICIAL_COMMIT="8f6afdc3603f0c661368de4659a7240862f59623"
OFFICIAL_MANIFEST="${SCRIPT_DIR}/official-data.manifest.sha256"

rm -rf "${STAGING_DIR}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${OFFICIAL_DIR}" "${ISUREN_HOME}/webapp" "${ISUREN_HOME}/isucon13"

rsync -a "${UPSTREAM_DIR}/webapp/go/" "${ISUREN_HOME}/webapp/go/"
rsync -a "${UPSTREAM_DIR}/webapp/pdns/" "${ISUREN_HOME}/webapp/pdns/"
rsync -a "${UPSTREAM_DIR}/bench/" "${ISUREN_HOME}/isucon13/bench/"

# 画像・SQL等の非managed dataはGitへ置かず、公式exact commitからbuild時に取得する。
# commit済みmanifestで全byteを検証し、branchやlatestへfallbackしない。
runuser -u "${ISUREN_USER}" -- git init --quiet "${OFFICIAL_DIR}"
runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" remote add origin "${OFFICIAL_REPO_URL}"
runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" sparse-checkout set --cone \
  bench/internal/scheduler/images \
  bench/scenario/testdata \
  webapp/img \
  webapp/sql \
  development/pdns
runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" fetch --quiet --depth 1 \
  --filter=blob:none origin "${OFFICIAL_COMMIT}"
runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" checkout --quiet "${OFFICIAL_COMMIT}"
test "$(runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" rev-parse HEAD)" = "${OFFICIAL_COMMIT}"
(
  cd "${OFFICIAL_DIR}"
  sha256sum -c "${OFFICIAL_MANIFEST}"
)

chown -R "${ISUREN_USER}:${ISUREN_USER}" \
  "${ISUREN_HOME}/webapp" "${ISUREN_HOME}/isucon13" "${STAGING_DIR}"

log "50-source.sh: done"
