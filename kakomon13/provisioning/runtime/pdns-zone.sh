#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /etc/isuren/kakomon13/runtime.env
zone=u.isuren.internal
address="${ISUCON13_POWERDNS_SUBDOMAIN_ADDRESS}"

if pdnsutil list-all-zones | grep -qx "${zone}"; then
  pdnsutil delete-zone "${zone}"
fi
pdnsutil create-zone "${zone}"
pdnsutil add-record "${zone}" . A 30 "${address}"
pdnsutil add-record "${zone}" pipe A 30 "${address}"
pdnsutil add-record "${zone}" test001 A 30 "${address}"
