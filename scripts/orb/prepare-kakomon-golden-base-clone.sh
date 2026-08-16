#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

execute=false
target=""
clone_name=""
base_name=""
cloned=false

usage() {
  cat <<'EOF'
Usage:
  prepare-kakomon-golden-base-clone.sh [--execute] [--base NAME] <kakomonN> <clone-name>

Clone a stopped <kakomonN>-golden-base and regenerate clone-local hostname,
machine-id, SSH host keys, random seed, and MySQL server UUID. The source base
is never started, changed, overwritten, or deleted.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  if [[ "${cloned}" == true ]]; then
    printf 'diagnostic: clone %s was retained for inspection; it was not deleted.\n' "${clone_name}" >&2
  fi
  exit 1
}

machine_exists() {
  orb list --quiet | grep -Fxq -- "$1"
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
  --base)
    (($# >= 2)) || fail "--base requires a value"
    base_name="$2"
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
    if [[ -z "${target}" ]]; then
      target="$1"
    elif [[ -z "${clone_name}" ]]; then
      clone_name="$1"
    else
      fail "too many positional arguments"
    fi
    shift
    ;;
  esac
done

[[ "${target}" =~ ^kakomon[0-9]+(-(qualify|final))?$ ]] ||
  fail "target must be a canonical slug such as kakomon14 or kakomon9-qualify"
[[ "${clone_name}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] ||
  fail "clone name must be 1-63 lowercase alphanumeric/hyphen characters"
if [[ -z "${base_name}" ]]; then
  base_name="${target}-golden-base"
fi
[[ "${base_name}" =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]] || fail "base name is invalid"
[[ "${base_name}" =~ ^${target}-golden-base(-[a-z0-9][a-z0-9-]*)?$ ]] ||
  fail "base name must start with ${target}-golden-base"
[[ "${clone_name}" =~ ^isuren-${target}-golden(-[a-z0-9][a-z0-9-]*)?$ ]] ||
  fail "clone name must start with isuren-${target}-golden"
command -v orb >/dev/null 2>&1 || fail "required command is missing: orb"
command -v python3 >/dev/null 2>&1 || fail "required command is missing: python3"

machine_exists "${base_name}" || fail "Golden Base does not exist: ${base_name}"
machine_is_stopped "${base_name}" || fail "Golden Base must be stopped before cloning: ${base_name}"
if machine_exists "${clone_name}"; then
  fail "destination VM already exists; refusing to overwrite or delete it: ${clone_name}"
fi

printf 'Orb Golden Base clone plan\n'
printf '  target: %s\n' "${target}"
printf '  base:   %s (stopped)\n' "${base_name}"
printf '  clone:  %s\n' "${clone_name}"
if [[ "${execute}" != true ]]; then
  printf 'dry-run: no Orb VM was cloned. Add --execute after reviewing this plan.\n'
  exit 0
fi

if ! orb clone "${base_name}" "${clone_name}"; then
  if machine_exists "${clone_name}"; then
    cloned=true
  fi
  fail "orb clone failed"
fi
cloned=true
machine_is_stopped "${base_name}" || fail "source Golden Base changed state during clone"
if ! orb start "${clone_name}"; then
  fail "could not start clone"
fi

if ! orb -m "${clone_name}" -u root env \
  EXPECTED_TARGET_SLUG="${target}" \
  CLONE_NAME="${clone_name}" \
  bash -s <<'GUEST'; then
set -euo pipefail

base_marker="/etc/isuren-mondai/${EXPECTED_TARGET_SLUG}-orb-golden-base.env"
clone_marker="/etc/isuren-mondai/${EXPECTED_TARGET_SLUG}-orb-golden-base-clone.env"
[[ -f "${base_marker}" && ! -L "${base_marker}" ]]
# shellcheck disable=SC1090 # root-owned marker created by the Golden builder.
source "${base_marker}"
[[ "${KIND}" == isuren-mondai-kakomon-golden-base ]]
[[ "${SCHEMA}" == 1 ]]
[[ "${TARGET_SLUG}" == "${EXPECTED_TARGET_SLUG}" ]]
[[ "${HOST_IDENTITY_SCRUBBED}" == true ]]
[[ "${ISUREN_LAYER_ABSENT}" == true ]]
[[ -f /etc/cloud/cloud-init.disabled ]]

hostnamectl set-hostname "${CLONE_NAME}"
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup
install -d -m 0755 /var/lib/dbus
ln -sfn /etc/machine-id /var/lib/dbus/machine-id

rm -f /etc/ssh/ssh_host_*
ssh-keygen -A

systemctl unmask systemd-random-seed.service
install -d -m 0700 /var/lib/systemd
dd if=/dev/urandom of=/var/lib/systemd/random-seed bs=512 count=1 status=none
chmod 0600 /var/lib/systemd/random-seed

IFS=, read -r -a target_services <<<"${TARGET_SERVICES}"
if [[ -n "${ENABLED_SERVICES}" ]]; then
  IFS=, read -r -a enabled_services <<<"${ENABLED_SERVICES}"
  systemctl enable "${enabled_services[@]}" >/dev/null
fi
systemctl enable ssh.service >/dev/null

mysql_server_uuid=not-applicable
if printf '%s\n' "${target_services[@]}" | grep -Fxq mysql; then
  systemctl start mysql
  for _ in $(seq 1 60); do
    if [[ -s /var/lib/mysql/auto.cnf ]]; then
      mysql_server_uuid="$(sed -n 's/^[[:space:]]*server-uuid[[:space:]]*=[[:space:]]*//p' /var/lib/mysql/auto.cnf)"
      [[ "${mysql_server_uuid}" =~ ^[0-9a-fA-F-]{36}$ ]] && break
    fi
    sleep 1
  done
  [[ "${mysql_server_uuid}" =~ ^[0-9a-fA-F-]{36}$ ]]
fi

if [[ -n "${RUNNING_SERVICES}" ]]; then
  IFS=, read -r -a running_services <<<"${RUNNING_SERVICES}"
  if ! printf '%s\n' "${running_services[@]}" | grep -Fxq mysql; then
    systemctl stop mysql >/dev/null 2>&1 || true
  fi
  systemctl start "${running_services[@]}"
else
  systemctl stop "${target_services[@]}" >/dev/null 2>&1 || true
fi
systemctl start systemd-random-seed.service
systemctl start ssh.service

csv_contains() {
  local csv="$1" expected="$2"
  [[ ",${csv}," == *",${expected},"* ]]
}
for service in "${target_services[@]}"; do
  if csv_contains "${ENABLED_SERVICES}" "${service}"; then
    [[ "$(systemctl is-enabled "${service}" 2>/dev/null || true)" == enabled ]]
  else
    service_enablement="$(systemctl is-enabled "${service}" 2>/dev/null || true)"
    [[ "${service_enablement}" != enabled && "${service_enablement}" != enabled-runtime ]]
  fi
  if csv_contains "${RUNNING_SERVICES}" "${service}"; then
    systemctl is-active --quiet "${service}"
  else
    ! systemctl is-active --quiet "${service}"
  fi
done
[[ "$(systemctl is-enabled ssh.service 2>/dev/null || true)" == enabled ]]
systemctl is-active --quiet ssh.service
[[ -f /etc/cloud/cloud-init.disabled ]]
[[ ! -e /home/isuren/isuren ]]
[[ ! -e /etc/isuren/provisioning-environment-id ]]
[[ ! -e /etc/isuren/enrollment.token ]]

machine_id="$(tr -d '\n' </etc/machine-id)"
ssh_host_key_sha256="$(sha256sum /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $1}')"
base_marker_sha256="$(sha256sum "${base_marker}" | awk '{print $1}')"
[[ "${machine_id}" =~ ^[0-9a-f]{32}$ ]]
[[ "${ssh_host_key_sha256}" =~ ^[0-9a-f]{64}$ ]]
[[ "${base_marker_sha256}" =~ ^[0-9a-f]{64}$ ]]
[[ -s /var/lib/systemd/random-seed ]]
[[ "$(stat -c '%U:%G:%a' /var/lib/systemd/random-seed)" == root:root:600 ]]

{
  printf 'KIND=isuren-mondai-kakomon-golden-base-clone\n'
  printf 'SCHEMA=1\n'
  printf 'TARGET_SLUG=%s\n' "${TARGET_SLUG}"
  printf 'SOURCE_BASE_MARKER_SHA256=%s\n' "${base_marker_sha256}"
  printf 'MACHINE_ID=%s\n' "${machine_id}"
  printf 'SSH_HOST_KEY_SHA256=%s\n' "${ssh_host_key_sha256}"
  printf 'MYSQL_SERVER_UUID=%s\n' "${mysql_server_uuid}"
  printf 'CLOUD_INIT_DISABLED=true\n'
  printf 'CLONE_IDENTITY_REGENERATED=true\n'
} >"${clone_marker}"
chmod 0644 "${clone_marker}"

printf 'prepared clone: machine_id=%s ssh_host_key_sha256=%s mysql_server_uuid=%s\n' \
  "${machine_id}" "${ssh_host_key_sha256}" "${mysql_server_uuid}"
GUEST
  fail "clone identity regeneration or service restoration failed"
fi

machine_is_stopped "${base_name}" || fail "source Golden Base is no longer stopped"
cloned=false
printf 'prepared: %s source=%s state=running\n' "${clone_name}" "${base_name}"
