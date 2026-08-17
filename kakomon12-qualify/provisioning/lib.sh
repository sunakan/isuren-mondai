#!/usr/bin/env bash
set -euo pipefail

: "${ISUREN_USER:=isuren}"
: "${ISUREN_UID:=1100}"
: "${ISUREN_GID:=1100}"
: "${APP_HOSTNAME_SUFFIX:=.t.isuren.internal}"
: "${ADMIN_HOSTNAME:=admin.t.isuren.internal}"
: "${ARTIFACT_DIR:=/opt/isuren-artifacts/kakomon12-qualify}"
: "${PROJECT_ROOT:=/opt/isuren-mondai-source}"

# These values are consumed by scripts that source this library.
# shellcheck disable=SC2034
PROVISIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
MANAGED_SOURCE_DIR="${PROJECT_ROOT}/upstream/isucon12-qualify"
# shellcheck disable=SC2034
PROVENANCE_DIR="/usr/local/share/isuren-mondai/kakomon12-qualify"
# shellcheck disable=SC2034
ISUREN_HOME="/home/${ISUREN_USER}"

log() {
  echo "[kakomon12-qualify] $*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo 'provisioning must run as root' >&2
    exit 1
  fi
}

now_ns() {
  date +%s%N
}

disk_used_bytes() {
  df -B1 / | awk 'NR==2{print $3}'
}

disk_total_bytes() {
  df -B1 / | awk 'NR==2{print $2}'
}

require_file() {
  test -f "$1" || {
    printf 'required file missing: %s\n' "$1" >&2
    exit 1
  }
}
