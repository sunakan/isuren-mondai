#!/usr/bin/env bash
set -euo pipefail

: "${ISUREN_USER:=isuren}"
: "${ISUREN_UID:=1100}"
: "${ISUREN_GID:=1100}"
: "${APP_ROOT:=/home/${ISUREN_USER}/isuumo}"
: "${PROJECT_ROOT:=/opt/isuren-mondai-source}"

# These values are consumed by scripts that source this library.
# shellcheck disable=SC2034
PROVISIONING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
MANAGED_SOURCE_DIR="${PROJECT_ROOT}/upstream/isucon10-qualify"
# shellcheck disable=SC2034
PROVENANCE_DIR="/opt/isuren-mondai/kakomon10-qualify"

if [ "${APP_ROOT}" != "/home/${ISUREN_USER}/isuumo" ]; then
  printf 'unsafe APP_ROOT override rejected: %s\n' "${APP_ROOT}" >&2
  exit 1
fi

log() {
  echo "[kakomon10-qualify] $*"
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
  df -B1 / | awk 'NR == 2 {print $3}'
}

disk_total_bytes() {
  df -B1 / | awk 'NR == 2 {print $2}'
}

require_file() {
  test -f "$1" || {
    printf 'required file missing: %s\n' "$1" >&2
    exit 1
  }
}
