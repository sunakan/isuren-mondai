#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

execute=false
target=""
vm_name=""
frontend_release_tag_override=""
distro="ubuntu:resolute"
arch="arm64"
cpus="2"
memory="4G"
disk="32G"
default_user="ubuntu"
recipe_user_data=""
user_data=""
build_log=""
created=false
build_started=false
trace_emitted=false

usage() {
  cat <<'EOF'
Usage:
  build-kakomon-golden-base.sh [options] <kakomonN>

By default this performs a read-only dry-run. Pass --execute to create and seal
the Orb machine.

Options:
  --execute                     Create the Orb Golden Base
  --name NAME                   Override the default <kakomonN>-golden-base
  --frontend-release-tag TAG    Use latest or one exact target frontend tag
  --cpus N                      Orb CPU limit (default: 2)
  --memory SIZE                 Orb memory limit (default: 4G)
  --disk SIZE                   Orb disk limit (default: 32G)
  -h, --help                    Show this help
EOF
}

fail() {
  emit_trace error
  printf 'error: %s\n' "$*" >&2
  if [[ "${created}" == true ]]; then
    printf 'diagnostic: Orb VM %s was retained for inspection; it was not deleted.\n' "${vm_name}" >&2
  fi
  exit 1
}

cleanup() {
  if [[ -n "${recipe_user_data}" ]]; then
    rm -f -- "${recipe_user_data}"
  fi
  if [[ -n "${user_data}" ]]; then
    rm -f -- "${user_data}"
  fi
  if [[ -n "${build_log}" ]]; then
    rm -f -- "${build_log}"
  fi
}
trap cleanup EXIT

emit_trace() {
  local status_code="$1"
  if [[ "${build_started}" != true || "${trace_emitted}" == true ]]; then
    return 0
  fi
  trace_emitted=true
  if ! declare -F otel_tracing_enabled >/dev/null || ! otel_tracing_enabled; then
    return 0
  fi
  local build_end_epoch
  build_end_epoch="$(date +%s)"
  otel_span \
    --service "${OTEL_SERVICE_NAME:-${target}-orb-golden-base-build}" \
    --name "orb.golden-base.build" \
    --kind server \
    --force-trace-id "${trace_id}" \
    --force-span-id "${root_span_id}" \
    --start "${build_start_epoch}" \
    --end "${build_end_epoch}" \
    --status-code "${status_code}"
  if [[ -s "${build_log}" ]]; then
    otel_emit_provisioning_spans \
      "${build_log}" "${trace_id}" "${root_span_id}" "${target}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is missing: $1"
}

machine_exists() {
  local machine_names
  if ! machine_names="$(orb list --quiet)"; then
    fail "could not list Orb VMs"
  fi
  printf '%s\n' "${machine_names}" | grep -Fxq -- "$1"
}

machine_is_stopped() {
  orb list --format json | python3 -c '
import json
import sys

rows = json.load(sys.stdin)
name = sys.argv[1]
row = next((item for item in rows if item["name"] == name), None)
raise SystemExit(0 if row and row["state"] == "stopped" else 1)
' "$1"
}

while (($# > 0)); do
  case "$1" in
  --execute)
    execute=true
    shift
    ;;
  --name)
    (($# >= 2)) || fail "--name requires a value"
    vm_name="$2"
    shift 2
    ;;
  --frontend-release-tag)
    (($# >= 2)) || fail "--frontend-release-tag requires a value"
    frontend_release_tag_override="$2"
    shift 2
    ;;
  --cpus)
    (($# >= 2)) || fail "--cpus requires a value"
    cpus="$2"
    shift 2
    ;;
  --memory)
    (($# >= 2)) || fail "--memory requires a value"
    memory="$2"
    shift 2
    ;;
  --disk)
    (($# >= 2)) || fail "--disk requires a value"
    disk="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    fail "unknown option: $1"
    ;;
  *)
    [[ -z "${target}" ]] || fail "only one kakomon target may be specified"
    target="$1"
    shift
    ;;
  esac
done

[[ "${target}" =~ ^kakomon[0-9]+(-(qualify|final))?$ ]] ||
  fail "target must be a canonical slug such as kakomon14 or kakomon9-qualify"
[[ -d "${target}" ]] || fail "target directory does not exist: ${target}"
[[ -f "${target}/cloud-init/generate-user-data.py" ]] ||
  fail "cloud-init generator is missing for ${target}"
[[ -f "${target}/provisioning/all.sh" ]] || fail "all.sh is missing for ${target}"
[[ -f "${target}/provisioning/goss.yaml" ]] || fail "goss.yaml is missing for ${target}"

if [[ -z "${vm_name}" ]]; then
  vm_name="${target}-golden-base"
fi
[[ "${vm_name}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ||
  fail "Orb VM name must be 1-63 lowercase alphanumeric/hyphen characters"
[[ "${vm_name}" =~ ^${target}-golden-base(-[a-z0-9][a-z0-9-]*)?$ ]] ||
  fail "Golden Base name must start with ${target}-golden-base"
[[ "${cpus}" =~ ^[1-9][0-9]*$ ]] || fail "--cpus must be a positive integer"
[[ "${memory}" =~ ^[1-9][0-9]*(M|G)$ ]] || fail "--memory must use M or G units"
[[ "${disk}" =~ ^[1-9][0-9]*(M|G)$ ]] || fail "--disk must use M or G units"

for command in git openssl orb python3; do
  require_command "${command}"
done

if machine_exists "${vm_name}"; then
  fail "同名のOrb VMがすでに存在します。上書き・削除はしません: ${vm_name}"
fi

project_commit="$(git rev-parse HEAD)"
[[ "${project_commit}" =~ ^[0-9a-f]{40}$ ]] || fail "HEAD is not one exact commit"
require_clean_worktree
require_commit_in_upstream_tracking_ref "${project_commit}"
recipe_tree="$(git rev-parse "${project_commit}:${target}")"
[[ "${recipe_tree}" =~ ^[0-9a-f]{40}$ ]] || fail "target recipe tree is not one exact tree"

frontend_release_tag="none"
if grep -Fq 'FRONTEND_RELEASE_TAG' "${target}/cloud-init/generate-user-data.py"; then
  inputs_file="${target}/scripts/ami-inputs.env"
  [[ -f "${inputs_file}" ]] || fail "frontend selector input is missing: ${inputs_file}"
  # shellcheck disable=SC1090 # target path is validated above and belongs to this repository.
  source "${inputs_file}"
  target_env_prefix="$(printf '%s' "${target}" | tr '[:lower:]-' '[:upper:]_')"
  selector_variable="${target_env_prefix}_FRONTEND_RELEASE_TAG"
  frontend_release_tag="${!selector_variable-}"
  if [[ -n "${frontend_release_tag_override}" ]]; then
    frontend_release_tag="${frontend_release_tag_override}"
  fi
  [[ "${frontend_release_tag}" == latest ||
    "${frontend_release_tag}" =~ ^${target}-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    fail "frontend release selector is invalid for ${target}: ${frontend_release_tag}"
  export FRONTEND_RELEASE_TAG="${frontend_release_tag}"
elif [[ -n "${frontend_release_tag_override}" ]]; then
  fail "${target} does not consume a frontend Release tag"
fi

service_contract="$({
  python3 - "${target}/provisioning/goss.yaml" <<'PY'
import sys

import yaml

document = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
services = document.get("service") or {}
for name, contract in services.items():
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@_.-"
    if not isinstance(name, str) or not name or any(ch not in allowed for ch in name):
        raise SystemExit(f"invalid service name in goss.yaml: {name!r}")
    if not isinstance(contract, dict) or not isinstance(contract.get("enabled"), bool) or not isinstance(contract.get("running"), bool):
        raise SystemExit(f"service contract must declare boolean enabled/running: {name}")
    enabled = "true" if contract.get("enabled") is True else "false"
    running = "true" if contract.get("running") is True else "false"
    print(f"{name}|{enabled}|{running}")
PY
} | LC_ALL=C sort)"
[[ -n "${service_contract}" ]] || fail "goss.yaml has no service contract for ${target}"
target_services_csv="$(printf '%s\n' "${service_contract}" | cut -d '|' -f 1 | paste -sd, -)"
enabled_services_csv="$(printf '%s\n' "${service_contract}" | awk -F '|' '$2 == "true" {print $1}' | paste -sd, -)"
running_services_csv="$(printf '%s\n' "${service_contract}" | awk -F '|' '$3 == "true" {print $1}' | paste -sd, -)"

trace_id="$(openssl rand -hex 16)"
root_span_id="$(openssl rand -hex 8)"
traceparent="00-${trace_id}-${root_span_id}-01"
operation_id="$(openssl rand -hex 16)"
export PROJECT_COMMIT="${project_commit}"
export TRACEPARENT="${traceparent}"

input_sha256="$({
  printf 'target=%s\n' "${target}"
  printf 'project_commit=%s\n' "${project_commit}"
  printf 'recipe_tree=%s\n' "${recipe_tree}"
  printf 'frontend_release_selector=%s\n' "${frontend_release_tag}"
  printf 'distro=%s\narch=%s\ncpus=%s\nmemory=%s\ndisk=%s\n' \
    "${distro}" "${arch}" "${cpus}" "${memory}" "${disk}"
  printf 'service_contract=%s\n' "${service_contract}"
} | openssl dgst -sha256 -r | awk '{print $1}')"
[[ "${input_sha256}" =~ ^[0-9a-f]{64}$ ]] || fail "could not calculate input SHA-256"

printf 'Orb Golden Base plan\n'
printf '  target:                    %s\n' "${target}"
printf '  vm_name:                   %s\n' "${vm_name}"
printf '  image:                     %s/%s\n' "${distro}" "${arch}"
printf '  resources:                 cpu=%s memory=%s disk=%s\n' "${cpus}" "${memory}" "${disk}"
printf '  project_commit:            %s\n' "${project_commit}"
printf '  recipe_tree:               %s\n' "${recipe_tree}"
printf '  frontend_release_selector: %s\n' "${frontend_release_tag}"
printf '  input_sha256:               %s\n' "${input_sha256}"
printf '  target_services:           %s\n' "${target_services_csv}"

if [[ "${execute}" != true ]]; then
  printf 'dry-run: no Orb VM was created. Add --execute after reviewing this plan.\n'
  exit 0
fi

# shellcheck source=scripts/otel.sh
source scripts/otel.sh
require_pushed_commit "${project_commit}"

# dry-run後に別processが同名VMを作る競合も、create直前の再確認で止める。
if machine_exists "${vm_name}"; then
  fail "同名のOrb VMがすでに存在します。上書き・削除はしません: ${vm_name}"
fi

recipe_user_data="$(mktemp)"
user_data="$(mktemp)"
build_log="$(mktemp)"
python3 "${target}/cloud-init/generate-user-data.py" --output "${recipe_user_data}" >/dev/null
python3 scripts/orb/prepare-cloud-init-user-data.py \
  --input "${recipe_user_data}" \
  --output "${user_data}"

printf 'create: %s\n' "${vm_name}"
build_start_epoch="$(date +%s)"
build_started=true
if ! orb create \
  --arch "${arch}" \
  --cpus "${cpus}" \
  --memory "${memory}" \
  --disk "${disk}" \
  --user "${default_user}" \
  --user-data "${user_data}" \
  "${distro}" "${vm_name}"; then
  if machine_exists "${vm_name}"; then
    created=true
  fi
  fail "orb create failed"
fi
created=true

printf 'verify: wait for cloud-init and target all.sh/Goss\n'
if ! orb -m "${vm_name}" -u root cloud-init status --wait; then
  orb -m "${vm_name}" -u root cat /var/log/cloud-init-output.log >"${build_log}" || true
  tail -n 500 "${build_log}" >&2 || true
  fail "cloud-init provisioning failed"
fi
orb -m "${vm_name}" -u root cat /var/log/cloud-init-output.log >"${build_log}"

if ! orb -m "${vm_name}" -u root env \
  TARGET_SLUG="${target}" \
  PROJECT_COMMIT="${project_commit}" \
  RECIPE_TREE="${recipe_tree}" \
  FRONTEND_RELEASE_SELECTOR="${frontend_release_tag}" \
  INPUT_SHA256="${input_sha256}" \
  BUILD_OPERATION_ID="${operation_id}" \
  TARGET_SERVICES_CSV="${target_services_csv}" \
  ENABLED_SERVICES_CSV="${enabled_services_csv}" \
  RUNNING_SERVICES_CSV="${running_services_csv}" \
  bash -s <<'GUEST'; then
set -euo pipefail

marker_dir=/etc/isuren-mondai
marker_path="${marker_dir}/${TARGET_SLUG}-orb-golden-base.env"
provisioned_marker="/var/lib/cloud/${TARGET_SLUG}-provisioned"

[[ -f "${provisioned_marker}" ]] || {
  printf 'missing provisioning marker: %s\n' "${provisioned_marker}" >&2
  exit 1
}
# shellcheck disable=SC1091 # fixed OS-owned file.
source /etc/os-release
[[ "${ID}" == ubuntu && "${VERSION_ID}" == 26.04 ]]
[[ "$(dpkg --print-architecture)" == arm64 ]]
[[ ! -e /home/isuren/isuren ]]
[[ ! -e /etc/isuren/provisioning-environment-id ]]
[[ ! -e /etc/isuren/enrollment.token ]]
[[ ! -e /etc/systemd/system/isuren-isu.service ]]
[[ ! -e /etc/systemd/system/isuren-portal.service ]]
[[ ! -e /opt/isuren-mondai ]]
test -x /usr/sbin/sshd
systemctl cat ssh.service >/dev/null

resolved_frontend_tag=none
resolved_frontend_sha256=none
if [[ "${FRONTEND_RELEASE_SELECTOR}" != none ]]; then
  resolved_tag_file="/tmp/${TARGET_SLUG}-frontend-release-tag"
  resolved_sha256_file="/tmp/${TARGET_SLUG}-frontend-release-sha256"
  [[ -s "${resolved_tag_file}" && -s "${resolved_sha256_file}" ]]
  resolved_frontend_tag="$(cat "${resolved_tag_file}")"
  resolved_frontend_sha256="$(cat "${resolved_sha256_file}")"
  [[ "${resolved_frontend_tag}" =~ ^${TARGET_SLUG}-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "${resolved_frontend_sha256}" =~ ^[0-9a-f]{64}$ ]]
fi
resolved_input_sha256="$({
  printf 'input_sha256=%s\n' "${INPUT_SHA256}"
  printf 'frontend_release_tag=%s\n' "${resolved_frontend_tag}"
  printf 'frontend_release_sha256=%s\n' "${resolved_frontend_sha256}"
} | sha256sum | awk '{print $1}')"
[[ "${resolved_input_sha256}" =~ ^[0-9a-f]{64}$ ]]

IFS=, read -r -a target_services <<<"${TARGET_SERVICES_CSV}"
for service in "${target_services[@]}" ssh.service ssh.socket; do
  systemctl disable --now "${service}" >/dev/null 2>&1 || true
done
systemctl stop systemd-random-seed.service >/dev/null 2>&1 || true
systemctl mask systemd-random-seed.service >/dev/null

# Orb clone cannot replace the source VM's user-data. Disable cloud-init after
# the one recipe run so a clone never replays the Golden build automatically.
install -d -m 0755 /etc/cloud
install -m 0644 /dev/null /etc/cloud/cloud-init.disabled
cloud-init clean --logs --seed
rm -rf /var/lib/cloud/*

rm -f /etc/ssh/ssh_host_* /var/lib/mysql/auto.cnf \
  /var/lib/dbus/machine-id /var/lib/systemd/random-seed
rm -f "/tmp/${TARGET_SLUG}-frontend-release-tag" \
  "/tmp/${TARGET_SLUG}-frontend-release-sha256"
truncate -s 0 /etc/machine-id
rm -f /root/.bash_history /home/*/.bash_history

install -d -m 0755 "${marker_dir}"
{
  printf 'KIND=isuren-mondai-kakomon-golden-base\n'
  printf 'SCHEMA=2\n'
  printf 'TARGET_SLUG=%s\n' "${TARGET_SLUG}"
  printf 'PROJECT_COMMIT=%s\n' "${PROJECT_COMMIT}"
  printf 'RECIPE_TREE=%s\n' "${RECIPE_TREE}"
  printf 'FRONTEND_RELEASE_SELECTOR=%s\n' "${FRONTEND_RELEASE_SELECTOR}"
  printf 'FRONTEND_RELEASE_TAG=%s\n' "${resolved_frontend_tag}"
  printf 'FRONTEND_RELEASE_SHA256=%s\n' "${resolved_frontend_sha256}"
  printf 'INPUT_SHA256=%s\n' "${INPUT_SHA256}"
  printf 'RESOLVED_INPUT_SHA256=%s\n' "${resolved_input_sha256}"
  printf 'BUILD_OPERATION_ID=%s\n' "${BUILD_OPERATION_ID}"
  printf 'TARGET_SERVICES=%s\n' "${TARGET_SERVICES_CSV}"
  printf 'ENABLED_SERVICES=%s\n' "${ENABLED_SERVICES_CSV}"
  printf 'RUNNING_SERVICES=%s\n' "${RUNNING_SERVICES_CSV}"
  printf 'PROVISIONING_MARKER_VERIFIED=true\n'
  printf 'SSH_SERVER_VERIFIED=true\n'
  printf 'CLOUD_INIT_DISABLED=true\n'
  printf 'HOST_IDENTITY_SCRUBBED=true\n'
  printf 'ISUREN_LAYER_ABSENT=true\n'
} >"${marker_path}"
chmod 0644 "${marker_path}"

[[ ! -s /etc/machine-id ]]
[[ ! -e /var/lib/dbus/machine-id ]]
[[ ! -e /var/lib/systemd/random-seed ]]
[[ ! -e /var/lib/mysql/auto.cnf ]]
[[ ! -e /var/lib/cloud/instances && ! -e /var/lib/cloud/data && ! -e /var/lib/cloud/seed ]]
! find /etc/ssh -maxdepth 1 -type f -name 'ssh_host_*' -print -quit | grep -q .
[[ "$(systemctl is-enabled systemd-random-seed.service 2>/dev/null || true)" == masked ]]
for service in "${target_services[@]}" ssh.service ssh.socket; do
  service_enablement="$(systemctl is-enabled "${service}" 2>/dev/null || true)"
  [[ "${service_enablement}" != enabled && "${service_enablement}" != enabled-runtime ]]
  ! systemctl is-active --quiet "${service}"
done
sync
GUEST
  fail "Golden Base sealing or verification failed"
fi

printf 'stop: %s\n' "${vm_name}"
if ! orb stop "${vm_name}"; then
  fail "could not stop Golden Base"
fi
if ! machine_is_stopped "${vm_name}"; then
  fail "Golden Base does not report the stopped state"
fi

created=false
emit_trace ok
printf 'created: %s input_sha256=%s state=stopped\n' "${vm_name}" "${input_sha256}"
