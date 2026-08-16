#!/usr/bin/env bash
set -euo pipefail

: "${BENCH_DIR:=/home/isuren/isucari}"
: "${BENCH_BINARY:=/home/isuren/bench}"
: "${TARGET_URL:=http://isucon9.isuren.internal}"
: "${TARGET_HOST:=isucon9.isuren.internal}"

stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
trap 'rm -f "${stdout_file}" "${stderr_file}"' EXIT

runner_status=0
(
  cd "${BENCH_DIR}"
  "${BENCH_BINARY}" \
    -target-url "${TARGET_URL}" \
    -target-host "${TARGET_HOST}" \
    -payment-url http://localhost:5555 \
    -shipment-url http://localhost:7001 \
    -payment-port 5555 \
    -shipment-port 7001 \
    -data-dir initial-data \
    -static-dir webapp/public/static
) >"${stdout_file}" 2>"${stderr_file}" || runner_status=$?

cat "${stderr_file}" >&2
cat "${stdout_file}"
if [ "${runner_status}" -ne 0 ]; then
  printf 'benchmark process failed before an authoritative success result (exit=%s)\n' "${runner_status}" >&2
  exit "${runner_status}"
fi

# The official benchmark returns exit 0 for both declared pass and declared
# failure. Only its final JSON object is authoritative.
python3 - "${stdout_file}" <<'PY'
import json
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
objects = []
for line in lines:
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict):
        objects.append(value)
if not objects:
    print("benchmark emitted no final JSON object", file=sys.stderr)
    raise SystemExit(3)
result = objects[-1]
required = {"pass", "score", "campaign", "language", "messages"}
if set(result) != required or not isinstance(result["pass"], bool):
    print("benchmark final JSON does not match the expected contract", file=sys.stderr)
    raise SystemExit(3)
if not result["pass"]:
    raise SystemExit(2)
PY
