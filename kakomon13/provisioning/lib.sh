#!/usr/bin/env bash
set -euo pipefail

: "${ISUREN_USER:=isuren}"

log() {
  echo "[kakomon13] $*"
}

now_ns() {
  date +%s%N
}

disk_used_bytes() {
  df -B1 / | awk 'NR == 2 { print $3 }'
}

disk_total_bytes() {
  df -B1 / | awk 'NR == 2 { print $2 }'
}
