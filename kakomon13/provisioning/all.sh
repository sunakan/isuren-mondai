#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

: "${RECIPE_COMMIT:?RECIPE_COMMIT must be the full project commit}"
: "${FRONTEND_RELEASE_TAG:?FRONTEND_RELEASE_TAG must be an exact release tag}"
: "${FRONTEND_RELEASE_SHA256:?FRONTEND_RELEASE_SHA256 must be an exact SHA-256}"
[[ "${RECIPE_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: RECIPE_COMMIT is not a full lowercase Git SHA" >&2
  exit 1
}
[[ "${FRONTEND_RELEASE_TAG}" =~ ^kakomon13-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: FRONTEND_RELEASE_TAG is invalid" >&2
  exit 1
}
[[ "${FRONTEND_RELEASE_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "error: FRONTEND_RELEASE_SHA256 is invalid" >&2
  exit 1
}

log "start"
log "spans: begin"
log "provisioning.all: disk_total_bytes=$(disk_total_bytes)"
log "provisioning.all: start_ns=$(now_ns) disk_before=$(disk_used_bytes) traceparent=${TRACEPARENT:-<unset>}"

record_provisioning_all_end() {
  local status=$?
  log "provisioning.all: end_ns=$(now_ns) disk_after=$(disk_used_bytes) exit_status=${status}"
  log "spans: end"
}
trap record_provisioning_all_end EXIT

run_step() {
  local script="$1"
  local start_ns disk_before status=0
  start_ns="$(now_ns)"
  disk_before="$(disk_used_bytes)"
  bash "${SCRIPT_DIR}/${script}" || status=$?
  log "step: script=${script} start_ns=${start_ns} end_ns=$(now_ns) disk_before=${disk_before} disk_after=$(disk_used_bytes) exit_status=${status}"
  return "${status}"
}

run_step 10-base.sh
run_step 20-user.sh
run_step 30-runtime.sh
run_step 40-packages.sh
run_step 50-source.sh
run_step 60-frontend.sh
run_step 70-benchmark.sh
run_step 75-install.sh
run_step 80-database.sh
run_step 85-webapp-go.sh
run_step 90-services.sh
run_step 95-seal.sh
run_step 99-verify.sh

log "all.sh: done"
touch /var/lib/cloud/kakomon13-provisioned
