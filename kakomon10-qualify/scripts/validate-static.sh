#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  echo "error: $*" >&2
  exit 1
}

for path in kakomon10-qualify upstream/isucon10-qualify mise-tasks/kakomon10-qualify; do
  test -e "${path}" || fail "missing ${path}"
done

while IFS= read -r path; do
  case "${path}" in
    kakomon10-qualify/* | upstream/isucon10-qualify/* | mise-tasks/kakomon10-qualify/*) ;;
    .github/workflows/release-kakomon10-qualify-frontend.yml) ;;
    .agents/skills/onboard-kakomon-ami-recipe/*) ;;
    .agents/skills/orchestrate-kakomon-ami-sessions/*) ;;
    *) fail "changed path is outside the approved roots: ${path}" ;;
  esac
done < <(
  {
    git diff --name-only
    git diff --cached --name-only
    git ls-files --others --exclude-standard
  } | LC_ALL=C sort -u
)

# Source and text metadata only; dist/ is ignored local/Release output.
# No archive/binary of any kind (including small official seed images) may be
# tracked under the KAKOMON10-QUALIFY roots, regardless of upstream
# provenance or size (orchestrate-kakomon-ami-sessions/SKILL.md). The 6
# official seed images are fetched at build time instead; guard against them
# ever reappearing on disk under the managed source tree.
test ! -e upstream/isucon10-qualify/initial-data/origin ||
  fail "official seed images must not be committed; fetch them in scripts/build-frontend-release.sh instead"
test -f kakomon10-qualify/scripts/frontend-assets.manifest.sha256 ||
  fail "missing frontend-assets.manifest.sha256 for the fetched seed images"
if git ls-files -- kakomon10-qualify/dist | grep -q .; then
  fail "generated output is tracked by Git"
fi
if {
  git ls-files -- kakomon10-qualify upstream/isucon10-qualify
  git ls-files --others --exclude-standard -- kakomon10-qualify upstream/isucon10-qualify
} | grep -Ei '\.(7z|a|avi|bin|bmp|bz2|db|dmg|gif|gz|ico|jar|jpeg|jpg|mov|mp3|mp4|o|pdf|png|so|sqlite3?|tar|tgz|ttf|wav|webm|webp|woff2?|xz|zip)$' >/dev/null; then
  fail "unexpected binary file tracked under the KAKOMON10-QUALIFY roots"
fi

test -f kakomon10-qualify/scripts/artifact-inputs.env || fail "missing frontend Release tag input"
# shellcheck source=kakomon10-qualify/scripts/artifact-inputs.env
source kakomon10-qualify/scripts/artifact-inputs.env
[[ "${KAKOMON10_QUALIFY_FRONTEND_RELEASE_TAG}" == "latest" ||
  "${KAKOMON10_QUALIFY_FRONTEND_RELEASE_TAG}" =~ ^kakomon10-qualify-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "invalid frontend Release tag input"

grep -qF 'go = "1.26.6"' kakomon10-qualify/provisioning/mise.ami.toml
grep -qF 'd0507e9e9d7fe012aae570108cbd76c15de879e17130ab8cb90d4d7445cb1f2e' \
  kakomon10-qualify/provisioning/mise.ami.lock
grep -qF 'node = "14.9.0"' kakomon10-qualify/scripts/mise.toml
grep -qF '6619a69ffe95c602105484bdecbdccb319e1c0db861203bffb9b6aedfae2c2df' \
  kakomon10-qualify/scripts/mise.lock
# shellcheck disable=SC2016 # Literal source contracts, not expressions to expand.
grep -qF 'MISE_BIN="${ISUREN_HOME}/.local/bin/mise"' kakomon10-qualify/provisioning/30-runtime.sh
grep -qF 'MISE_VERSION="2026.8.6"' kakomon10-qualify/provisioning/30-runtime.sh
if grep -qrn 'most_recent\|mise[.]run\|curl[^|]*[|][[:space:]]*\(ba\)\?sh' \
  kakomon10-qualify/provisioning/*.sh kakomon10-qualify/provisioning/mise.ami.toml \
  kakomon10-qualify/scripts/mise.toml; then
  fail "mutable/unverified install pattern found"
fi

for build_script in kakomon10-qualify/provisioning/70-webapp-go.sh kakomon10-qualify/provisioning/85-bench-build.sh; do
  # shellcheck disable=SC2016 # Literal source contract ($2 is the MISE_BIN
  # positional arg passed into the runuser bash -c wrapper).
  grep -qF '"$2" exec -- go build' "${build_script}" ||
    fail "Go build must run through mise: ${build_script}"
done

grep -qF 'EnvironmentFile=/home/isuren/env.sh' \
  kakomon10-qualify/provisioning/systemd/isuumo-go.service ||
  fail "systemd unit must load the official env.sh"

release_workflow=".github/workflows/release-kakomon10-qualify-frontend.yml"
test -f "${release_workflow}" || fail "missing frontend release workflow"
grep -qF 'name: release-kakomon10-qualify-frontend' "${release_workflow}"
grep -qF '"kakomon10-qualify-frontend-v*"' "${release_workflow}"
if grep -qn 'kakomon9\|kakomon12\|kakomon13\|kakomon14' "${release_workflow}"; then
  fail "release workflow references another target"
fi

if grep -qrn 'tmp/all-kakomon' \
  kakomon10-qualify/provisioning kakomon10-qualify/cloud-init kakomon10-qualify/packer; then
  fail "clean-clone build path depends on the audit cache"
fi

line_source="$(grep -n 'run_step 50-source.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_initdb="$(grep -n 'run_step 60-initdb.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_webapp="$(grep -n 'run_step 70-webapp-go.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_frontend="$(grep -n 'run_step 80-frontend.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_bench="$(grep -n 'run_step 85-bench-build.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_nginx="$(grep -n 'run_step 90-nginx.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
line_verify="$(grep -n 'run_step 99-verify.sh' kakomon10-qualify/provisioning/all.sh | cut -d: -f1)"
test "${line_source}" -lt "${line_initdb}" || fail "source deploy must precede DB init"
test "${line_initdb}" -lt "${line_webapp}" || fail "DB init must precede Application build/start"
test "${line_webapp}" -lt "${line_frontend}" || fail "Application build must precede frontend placement"
test "${line_frontend}" -lt "${line_bench}" || fail "frontend placement must precede benchmark build"
test "${line_bench}" -lt "${line_nginx}" || fail "benchmark build must precede nginx"
test "${line_nginx}" -lt "${line_verify}" || fail "nginx must precede Goss verification"

scripts=()
while IFS= read -r script; do
  scripts+=("${script}")
done < <(find kakomon10-qualify/provisioning kakomon10-qualify/scripts mise-tasks/kakomon10-qualify \
  -type f -perm -u+x | LC_ALL=C sort)
bash -n "${scripts[@]}"
if command -v shellcheck >/dev/null; then
  shellcheck -x -P . -P kakomon10-qualify/provisioning "${scripts[@]}"
fi

unformatted="$(gofmt -l \
  upstream/isucon10-qualify/webapp/go/main.go \
  upstream/isucon10-qualify/bench/asset/*.go \
  upstream/isucon10-qualify/bench/client/*.go \
  upstream/isucon10-qualify/bench/cmd/bench/bench.go \
  upstream/isucon10-qualify/bench/fails/*.go \
  upstream/isucon10-qualify/bench/parameter/*.go \
  upstream/isucon10-qualify/bench/reporter/*.go \
  upstream/isucon10-qualify/bench/scenario/*.go \
  upstream/isucon10-qualify/bench/score/*.go \
  upstream/isucon10-qualify/initial-data/make_verification_data/*.go)"
test -z "${unformatted}" || fail "gofmt needed: ${unformatted}"

python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("kakomon10-qualify/cloud-init/generate-user-data.py").read_text())'
if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
  python3 -c 'import pathlib, yaml; yaml.safe_load(pathlib.Path("kakomon10-qualify/provisioning/goss.yaml").read_text())'
fi

echo "kakomon10-qualify static contract: ok"
