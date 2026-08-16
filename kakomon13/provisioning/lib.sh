#!/usr/bin/env bash
set -euo pipefail

# Configuration values. Keep the account and optional TLS switch explicit so
# target-specific steps can use the same provisioning shell contract.
: "${ISUREN_USER:=isuren}"
: "${ENABLE_TLS:=false}"

log() {
  echo "[kakomon13] $*"
}

# These functions expose raw provisioning telemetry for the target build task
# to convert after Packer completes. The VM only writes values through log();
# it never creates spans or sends OTLP data.
now_ns() {
  date +%s%N
}

disk_used_bytes() {
  df -B1 / | awk 'NR==2{print $3}'
}

disk_total_bytes() {
  df -B1 / | awk 'NR==2{print $2}'
}
