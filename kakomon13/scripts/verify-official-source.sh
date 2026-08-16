#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OFFICIAL_SOURCE_DIR="${KAKOMON13_OFFICIAL_SOURCE_DIR:-${ROOT_DIR}/tmp/all-kakomon/isucon13}"
EXPECTED_ORIGIN="https://github.com/isucon/isucon13.git"
EXPECTED_COMMIT="8f6afdc3603f0c661368de4659a7240862f59623"

if [ ! -d "${OFFICIAL_SOURCE_DIR}/.git" ]; then
  echo "error: official source cache is missing: ${OFFICIAL_SOURCE_DIR}" >&2
  exit 1
fi
if [ "$(git -C "${OFFICIAL_SOURCE_DIR}" remote get-url origin)" != "${EXPECTED_ORIGIN}" ]; then
  echo "error: unexpected official source origin" >&2
  exit 1
fi
if [ "$(git -C "${OFFICIAL_SOURCE_DIR}" rev-parse HEAD)" != "${EXPECTED_COMMIT}" ]; then
  echo "error: unexpected official source HEAD" >&2
  exit 1
fi
if [ -n "$(git -C "${OFFICIAL_SOURCE_DIR}" status --short)" ]; then
  echo "error: official source cache is dirty" >&2
  exit 1
fi

(
  cd "${OFFICIAL_SOURCE_DIR}"
  shasum -a 256 -c "${ROOT_DIR}/kakomon13/provisioning/official-data.manifest.sha256"
  shasum -a 256 -c "${ROOT_DIR}/kakomon13/scripts/frontend-assets.manifest.sha256"
)

echo "official source identity and manifests: ok"
