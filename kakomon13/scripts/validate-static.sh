#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  echo "error: $*" >&2
  exit 1
}

for path in kakomon13 upstream/isucon13 mise-tasks/kakomon13; do
  test -e "${path}" || fail "missing ${path}"
done

while IFS= read -r path; do
  case "${path}" in
    kakomon13/* | upstream/isucon13/* | mise-tasks/kakomon13/*) ;;
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

# Sourceとtext metadataだけをGit管理する。distはignore済みのlocal/release出力であり、
# archive・画像その他binaryをrepositoryへ追加しない。
if git ls-files -- kakomon13/artifacts kakomon13/dist upstream/isucon13/frontend/dist | grep -q .; then
  fail "generated output is tracked by Git"
fi
if {
  git ls-files -- kakomon13 upstream/isucon13
  git ls-files --others --exclude-standard -- kakomon13 upstream/isucon13
} | rg -i '\.(?:7z|a|avi|bin|bmp|bz2|db|dmg|gif|gz|ico|jar|jpeg|jpg|mov|mp3|mp4|o|pdf|png|so|sqlite3?|tar|tgz|ttf|wav|webm|webp|woff2?|xz|zip)$' >/dev/null; then
  fail "binary file is tracked under the KAKOMON13 roots"
fi
if git diff --cached --numstat | awk '$1 == "-" || $2 == "-" { found=1 } END { exit !found }'; then
  fail "staged diff contains a binary file"
fi
if rg -n 'kakomon13/artifacts|official-data-v1\.tar|frontend-v1\.tar' \
  --glob '!validate-static.sh' \
  kakomon13 upstream/isucon13/NOTICE.md mise-tasks/kakomon13; then
  fail "obsolete Git-managed artifact path remains"
fi

official_manifest="kakomon13/provisioning/official-data.manifest.sha256"
frontend_asset_manifest="kakomon13/scripts/frontend-assets.manifest.sha256"
test "$(wc -l <"${official_manifest}" | tr -d ' ')" = 205 || fail "official data manifest count changed"
test "$(wc -l <"${frontend_asset_manifest}" | tr -d ' ')" = 12 || fail "frontend asset manifest count changed"
rg -v '^[0-9a-f]{64}  [^[:space:]]+$' "${official_manifest}" "${frontend_asset_manifest}" &&
  fail "invalid SHA-256 manifest line"
official_manifest_sha256="$(shasum -a 256 "${official_manifest}" | awk '{print $1}')"
grep -qF "OfficialData = \"${official_manifest_sha256}\"" kakomon13/packer/kakomon13.pkr.hcl ||
  fail "Packer official data identity does not match the committed manifest"
if [ -d tmp/all-kakomon/isucon13/.git ]; then
  kakomon13/scripts/verify-official-source.sh >/dev/null
fi

excluded=(
  upstream/isucon13/frontend/src/assets/img
  upstream/isucon13/frontend/src/components/layout/ISUPipe_yoko_color.png
  upstream/isucon13/bench/internal/scheduler/images
  upstream/isucon13/bench/scenario/testdata/NoImage.jpg
  upstream/isucon13/webapp/img/NoImage.jpg
  upstream/isucon13/webapp/sql
  upstream/isucon13/scripts/initial-data
  upstream/isucon13/development/pdns/20_powerdns_schema.sql
)
for path in "${excluded[@]}"; do
  test ! -e "${path}" || fail "non-managed asset/data leaked into managed source: ${path}"
done

if git ls-files -- upstream/isucon13 | rg '/(?:\.git|node_modules|dist)/' >/dev/null; then
  fail "managed source tracks Git metadata or dependency/build output"
fi

if rg -n --glob '!NOTICE.md' 'u\.isucon\.dev' upstream/isucon13 >/dev/null; then
  fail "managed source still contains the owned u.isucon.dev hostname"
fi
for expected in \
  'pipe.u.isuren.internal' \
  'u.isuren.internal' \
  'DNS:*.u.isuren.internal'; do
  rg -F "${expected}" upstream/isucon13 kakomon13/provisioning >/dev/null ||
    fail "hostname contract is missing ${expected}"
done
# shellcheck disable=SC2016 # These are exact source strings, not expressions to expand here.
for expected in \
  'pdnsutil add-record "${zone}" "${zone}" A 30 "${address}"' \
  'pdnsutil add-record "${zone}" "pipe.${zone}" A 30 "${address}"' \
  'pdnsutil add-record "${zone}" "test001.${zone}" A 30 "${address}"'; do
  grep -qF "${expected}" kakomon13/provisioning/runtime/pdns-zone.sh ||
    fail "PowerDNS 5 absolute owner contract is missing: ${expected}"
done
grep -qF '"pdnsutil", "add-record", powerDNSZone, powerDNSRecordName(req.Name)' \
  upstream/isucon13/webapp/go/user_handler.go ||
  fail "dynamic PowerDNS records must use an absolute owner name"

actual_media="$(mktemp)"
expected_media="$(mktemp)"
trap 'rm -f "${actual_media}" "${expected_media}"' EXIT
rg -l --glob '!NOTICE.md' 'media\.xiii\.isucon\.dev' upstream/isucon13 | LC_ALL=C sort >"${actual_media}"
printf '%s\n' \
  upstream/isucon13/bench/internal/scheduler/livestreams_pool.go \
  upstream/isucon13/bench/internal/scheduler/reservation_pool.go \
  upstream/isucon13/bench/scenario/core_pretest_abnormal.go \
  upstream/isucon13/bench/scenario/core_pretest_calc.go \
  upstream/isucon13/bench/scenario/core_pretest_normal.go \
  upstream/isucon13/frontend/src/api/hooks.tsx | LC_ALL=C sort >"${expected_media}"
diff -u "${expected_media}" "${actual_media}"

grep -qF 'go = "1.26.6"' kakomon13/provisioning/mise.ami.toml
grep -qF 'd0507e9e9d7fe012aae570108cbd76c15de879e17130ab8cb90d4d7445cb1f2e' \
  kakomon13/provisioning/mise.ami.lock
grep -qF 'node = "24.19.0"' kakomon13/scripts/mise.toml
grep -qF 'd28c8a5bf0a808f0ed434a1dce8c54ae98f0371c0bd86ac58abc613f73e6643f' \
  kakomon13/scripts/mise.lock
grep -qF '8294b7aa9b03997481c06babf1e8b270c859358f27da57a11509afe537ac381d' \
  kakomon13/scripts/mise.lock
grep -qF '"packageManager": "yarn@3.2.2"' upstream/isucon13/frontend/package.json

if rg -n 'most_recent|= "(?:latest|lts)"|version\s*=\s*"~>' \
  kakomon13/packer/*.hcl kakomon13/provisioning/mise.ami.toml kakomon13/scripts/mise.toml; then
  fail "mutable build input found"
fi
grep -qF 'version = "= 1.8.2"' kakomon13/packer/kakomon13.pkr.hcl
rg -q 'source_ami\s*=\s*var\.source_ami' kakomon13/packer/kakomon13.pkr.hcl
rg -q 'FRONTEND_RELEASE_TAG.*exact' kakomon13/provisioning/all.sh
rg -q 'FRONTEND_RELEASE_SHA256.*exact' kakomon13/provisioning/all.sh
# shellcheck disable=SC2016 # This is the exact source text required by the contract.
grep -qF 'test "$(runuser -u "${ISUREN_USER}" -- git -C "${OFFICIAL_DIR}" rev-parse HEAD)" = "${OFFICIAL_COMMIT}"' \
  kakomon13/provisioning/50-source.sh ||
  fail "official checkout identity must be verified as its owning user"
# shellcheck disable=SC2016 # This is the exact source text required by the contract.
grep -qF '= "goss version ${GOSS_VERSION}"' kakomon13/provisioning/99-verify.sh ||
  fail "Goss version output contract is stale"
if rg -n '^[[:space:]]+contains:' kakomon13/provisioning/goss.yaml; then
  fail "deprecated literal Goss file.contains contract remains"
fi
for expected in \
  '/^official_data_manifest_sha256=[0-9a-f]{64}$/' \
  '/^frontend_release_tag=kakomon13-frontend-v[0-9]+[.][0-9]+[.][0-9]+$/' \
  '/^frontend_release_sha256=[0-9a-f]{64}$/'; do
  grep -qF "${expected}" kakomon13/provisioning/goss.yaml ||
    fail "Goss provenance regex is missing: ${expected}"
done

if rg -n --glob '*.sh' --glob '*.py' --glob '*.hcl' --glob '*.yaml' \
  'tmp/all-kakomon' kakomon13/provisioning kakomon13/cloud-init kakomon13/packer; then
  fail "clean-clone build path depends on the audit cache"
fi

line_frontend="$(grep -n 'run_step 60-frontend.sh' kakomon13/provisioning/all.sh | cut -d: -f1)"
line_bench="$(grep -n 'run_step 70-benchmark.sh' kakomon13/provisioning/all.sh | cut -d: -f1)"
line_install="$(grep -n 'run_step 75-install.sh' kakomon13/provisioning/all.sh | cut -d: -f1)"
test "${line_frontend}" -lt "${line_bench}" || fail "frontend hash must precede benchmark build"
test "${line_bench}" -lt "${line_install}" || fail "benchmark build must precede installation"

scripts=()
while IFS= read -r script; do
  scripts+=("${script}")
done < <(find kakomon13/provisioning kakomon13/scripts mise-tasks/kakomon13 -type f -perm -u+x | LC_ALL=C sort)
bash -n "${scripts[@]}"
if command -v shellcheck >/dev/null; then
  shellcheck -x -P . -P kakomon13/provisioning "${scripts[@]}"
fi

unformatted="$(gofmt -l \
  upstream/isucon13/webapp/go/main.go \
  upstream/isucon13/webapp/go/user_handler.go \
  upstream/isucon13/webapp/go/user_handler_test.go \
  upstream/isucon13/bench/cmd/bench/bench.go \
  upstream/isucon13/bench/cmd/bench/supervise.go \
  upstream/isucon13/bench/internal/attacker/dns.go \
  upstream/isucon13/bench/internal/config/benchmark.go)"
test -z "${unformatted}" || fail "gofmt needed: ${unformatted}"

python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("kakomon13/cloud-init/generate-user-data.py").read_text())'
python3 -c 'import pathlib, yaml; yaml.safe_load(pathlib.Path("kakomon13/provisioning/goss.yaml").read_text())'
packer fmt -check kakomon13/packer/kakomon13.pkr.hcl
packer validate -syntax-only kakomon13/packer/kakomon13.pkr.hcl

echo "kakomon13 static contract: ok"
