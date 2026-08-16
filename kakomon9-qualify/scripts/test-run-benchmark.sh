#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

cat >"${work_dir}/fake-bench" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_JSON:-}"
exit "${FAKE_EXIT:-0}"
EOF
chmod 0755 "${work_dir}/fake-bench"

run_case() {
  local expected="$1"
  shift
  local actual=0
  BENCH_DIR="${work_dir}" BENCH_BINARY="${work_dir}/fake-bench" "$@" \
    "${SCRIPT_DIR}/run-benchmark.sh" >/dev/null 2>/dev/null || actual=$?
  if [ "${actual}" -ne "${expected}" ]; then
    printf 'expected benchmark wrapper exit %s, got %s\n' "${expected}" "${actual}" >&2
    exit 1
  fi
}

run_case 0 env FAKE_JSON='{"pass":true,"score":1,"campaign":0,"language":"Go","messages":[]}'
run_case 2 env FAKE_JSON='{"pass":false,"score":0,"campaign":0,"language":"Go","messages":["failure"]}'
run_case 3 env FAKE_JSON='not-json'
run_case 7 env FAKE_EXIT=7 FAKE_JSON='{"pass":true,"score":1,"campaign":0,"language":"Go","messages":[]}'

echo 'benchmark wrapper semantics: pass'
