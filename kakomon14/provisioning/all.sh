#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Build inputs are validated before any target step changes the image. This
# keeps the provisioning log and completion marker bound to the exact recipe
# commit and the target-scoped frontend Release selector.
: "${RECIPE_COMMIT:?RECIPE_COMMIT must be the full project commit}"
: "${FRONTEND_RELEASE_TAG:=latest}"
[[ "${RECIPE_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: RECIPE_COMMIT is not a full lowercase Git SHA" >&2
  exit 1
}
[[ "${FRONTEND_RELEASE_TAG}" == "latest" ||
  "${FRONTEND_RELEASE_TAG}" =~ ^kakomon14-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: FRONTEND_RELEASE_TAG is invalid" >&2
  exit 1
}

log "start"

# These raw values are converted into OTel spans by the host-side target build
# task after Packer completes. The VM does not send telemetry or receive keys.
log "spans: begin"
log "provisioning.all: disk_total_bytes=$(disk_total_bytes)"
log "provisioning.all: start_ns=$(now_ns) disk_before=$(disk_used_bytes) traceparent=${TRACEPARENT:-<unset>}"

# Keep the provisioning span complete even when set -e stops a failed step.
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
run_step 40-mysql.sh
run_step 50-source.sh
run_step 60-initdb.sh
run_step 70-webapp-go.sh
run_step 75-matcher.sh
run_step 77-payment-mock.sh
run_step 80-frontend.sh
run_step 85-bench-build.sh
run_step 90-nginx.sh
run_step 99-verify.sh

log "all.sh: done"
touch /var/lib/cloud/kakomon14-provisioned
