#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root

# Ubuntu mounts /tmp as a RAM-backed tmpfs. The official release bundles are
# larger than the available tmpfs on the practice instances, so keep all
# mktemp/unzip/package temporary files on the root-backed volume instead.
RECIPE_TMPDIR=/var/tmp/isuren-mondai-kakomon9-qualify
rm -rf "${RECIPE_TMPDIR}"
install -d -m 1777 "${RECIPE_TMPDIR}"
export TMPDIR="${RECIPE_TMPDIR}"

log "all.sh: start"
log "provisioning.all: temp_dir=${TMPDIR}"
log "spans: begin"
log "provisioning.all: disk_total_bytes=$(disk_total_bytes)"
log "provisioning.all: start_ns=$(now_ns) disk_before=$(disk_used_bytes)"

record_end() {
  local status=$?
  log "provisioning.all: end_ns=$(now_ns) disk_after=$(disk_used_bytes) exit_status=${status}"
  log "spans: end"
}
trap record_end EXIT

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
# The official inputs are fetched by the AMI after the base tools are present.
run_step 05-artifacts.sh
run_step 20-user.sh
run_step 30-runtime.sh
run_step 40-mysql.sh
run_step 50-source.sh
run_step 60-initdb.sh
run_step 70-webapp-go.sh
run_step 80-frontend.sh
run_step 85-bench-build.sh
run_step 87-start-services.sh
run_step 90-nginx.sh
run_step 95-provenance.sh
run_step 99-verify.sh

rm -rf "${RECIPE_TMPDIR}"
touch /var/lib/cloud/kakomon9-qualify-provisioned
log "all.sh: done"
