#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon10-qualify-staging"
RELEASE_DIR="${STAGING_DIR}/release"

# 60-initdb.sh already downloaded, checksummed, and extracted the same
# frontend Release archive (it also carries the dummy-data SQL/fixtures this
# step doesn't need); this step is placement only, matching the official
# nginx config's `root /www/data;` for the static tree.
require_file "${RELEASE_DIR}/public/index.html"
rm -rf /www/data
install -d -m 0755 /www/data
rsync -a "${RELEASE_DIR}/public/" /www/data/
chown -R www-data:www-data /www/data

rm -rf "${STAGING_DIR}"

log "80-frontend.sh: frontend static export placed at /www/data"
