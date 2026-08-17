#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=../scripts/artifact-inputs.env
source "$(cd "${SCRIPT_DIR}/.." && pwd)/scripts/artifact-inputs.env"

[[ "${OFFICIAL_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "error: OFFICIAL_COMMIT is not a full lowercase Git SHA" >&2
  exit 1
}

# --- non-code official inputs, fetched from the exact official commit -----
# webapp/sql (schema/seed SQL), the JWT key pair, and the prebuilt frontend
# tree are intentionally not committed to upstream/isucon12-qualify (see
# NOTICE.md): sql/ and public/ are non-code data, and the key pair is
# key material. All three are fetched here and verified against the pinned
# commit rather than trusted from a floating branch/tag.
FETCH_DIR="${ARTIFACT_DIR}/official"
rm -rf "${ARTIFACT_DIR}"
install -d -m 0755 "${FETCH_DIR}"

git init --quiet "${FETCH_DIR}"
git -C "${FETCH_DIR}" remote add origin "${OFFICIAL_REPOSITORY_URL}"
git -C "${FETCH_DIR}" sparse-checkout init --no-cone
git -C "${FETCH_DIR}" sparse-checkout set \
  webapp/sql \
  webapp/go/public.pem \
  blackauth/isuports.pem \
  public
git -C "${FETCH_DIR}" fetch --quiet --depth 1 --filter=blob:none origin "${OFFICIAL_COMMIT}"
git -C "${FETCH_DIR}" checkout --quiet "${OFFICIAL_COMMIT}"
test "$(git -C "${FETCH_DIR}" rev-parse HEAD)" = "${OFFICIAL_COMMIT}"

require_file "${FETCH_DIR}/webapp/sql/init.sh"
require_file "${FETCH_DIR}/webapp/sql/admin/01_create_mysql_database.sql"
require_file "${FETCH_DIR}/webapp/sql/admin/10_schema.sql"
require_file "${FETCH_DIR}/webapp/go/public.pem"
require_file "${FETCH_DIR}/blackauth/isuports.pem"
require_file "${FETCH_DIR}/public/index.html"

# The private key is embedded verbatim into blackauth (both copies must be
# byte-identical, matching the official README's "one shared key pair" claim)
# and the public key is loaded by webapp/go at runtime; record their exact
# byte identity for provenance rather than trusting the filenames alone.
webapp_key_sha256="$(sha256sum "${FETCH_DIR}/webapp/go/public.pem" | awk '{print $1}')"
blackauth_key_sha256="$(sha256sum "${FETCH_DIR}/blackauth/isuports.pem" | awk '{print $1}')"
{
  printf 'official_commit=%s\n' "${OFFICIAL_COMMIT}"
  printf 'webapp_public_key_sha256=%s\n' "${webapp_key_sha256}"
  printf 'blackauth_private_key_sha256=%s\n' "${blackauth_key_sha256}"
} >"${ARTIFACT_DIR}/key-identity.txt"

# --- initial_data (per-tenant SQLite seed), GitHub Release only -----------
# bench/Makefile fetches this via `gh release list | ... | gh release
# download`, i.e. a floating "latest" selector with no committed Git blob.
# This recipe pins the exact tag/asset/digest instead of trusting "latest" at
# AMI-build time (recipe-contract.md ban on unpinned artifact identity).
# Resolving that pin requires network access to the official repository's
# Releases, which onboard-kakomon-ami-recipe's audit/plan/implement modes do
# not perform (external operations belong to `verify`). Until a human fills
# in scripts/artifact-inputs.env, fail closed here with a clear message
# instead of silently downloading whatever GitHub currently calls "latest".
if [ "${INITIAL_DATA_RELEASE_TAG}" = "REQUIRES_VERIFY_PHASE_RESOLUTION" ] ||
  [ "${INITIAL_DATA_ASSET_NAME}" = "REQUIRES_VERIFY_PHASE_RESOLUTION" ] ||
  [ "${INITIAL_DATA_SHA256}" = "REQUIRES_VERIFY_PHASE_RESOLUTION" ]; then
  cat >&2 <<'EOF'
error: kakomon12-qualify/scripts/artifact-inputs.env still carries the
initial_data placeholder (INITIAL_DATA_RELEASE_TAG / INITIAL_DATA_ASSET_NAME /
INITIAL_DATA_SHA256). Resolve the exact GitHub Release tag, asset name, and
SHA-256 for https://github.com/isucon/isucon12-qualify/releases (read-only,
during the verify-mode external-operation preflight) and pin them before
building this AMI. See kakomon12-qualify/README.md.
EOF
  exit 1
fi
[[ "${INITIAL_DATA_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
  echo "error: INITIAL_DATA_SHA256 is not a resolved SHA-256" >&2
  exit 1
}

RELEASE_DIR="${ARTIFACT_DIR}/release"
install -d -m 0755 "${RELEASE_DIR}"
gh release download "${INITIAL_DATA_RELEASE_TAG}" \
  --repo "isucon/isucon12-qualify" \
  --pattern "${INITIAL_DATA_ASSET_NAME}" \
  --dir "${RELEASE_DIR}" \
  --clobber
require_file "${RELEASE_DIR}/${INITIAL_DATA_ASSET_NAME}"
echo "${INITIAL_DATA_SHA256}  ${RELEASE_DIR}/${INITIAL_DATA_ASSET_NAME}" | sha256sum -c -

# The official Makefile extracts this archive at the repository root
# (`tar xzf ../initial_data.tar.gz -C ..` run from bench/), so the tar's
# internal paths are root-relative. Extract the same way and require the two
# paths that webapp/sql/init.sh and bench/Makefile's own targets depend on;
# fail closed with the archive listing if either is absent instead of
# guessing at undocumented internal layout.
EXTRACT_DIR="${ARTIFACT_DIR}/extracted"
install -d -m 0755 "${EXTRACT_DIR}"
tar -xzf "${RELEASE_DIR}/${INITIAL_DATA_ASSET_NAME}" -C "${EXTRACT_DIR}"
if [ ! -d "${EXTRACT_DIR}/initial_data" ] || [ -z "$(find "${EXTRACT_DIR}/initial_data" -maxdepth 1 -name '*.db')" ]; then
  echo "error: extracted archive has no initial_data/*.db; archive contents:" >&2
  find "${EXTRACT_DIR}" -maxdepth 3 >&2
  exit 1
fi

log "05-artifacts.sh: official non-code inputs and initial_data fetched and verified"
