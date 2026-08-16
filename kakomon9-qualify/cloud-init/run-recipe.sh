#!/usr/bin/env bash
set -euo pipefail

PROJECT_COMMIT=__PROJECT_COMMIT__
REPOSITORY_URL=https://github.com/sunakan/isuren-mondai.git
CLONE_DIR=/opt/isuren-mondai-source
ARTIFACT_DIR=/opt/isuren-artifacts/kakomon9-qualify

# Packer does not upload a dist bundle. provisioning/05-artifacts.sh fetches
# every official input at its pinned commit/URL after 10-base.sh installs the
# required network and archive tools.

if [[ ! "${PROJECT_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'cloud-init received an invalid project commit' >&2
  exit 1
fi

rm -rf "${CLONE_DIR}"
git init --quiet "${CLONE_DIR}"
git -C "${CLONE_DIR}" remote add origin "${REPOSITORY_URL}"
git -C "${CLONE_DIR}" fetch --quiet --depth 1 origin "${PROJECT_COMMIT}"
git -C "${CLONE_DIR}" checkout --quiet --detach FETCH_HEAD
test "$(git -C "${CLONE_DIR}" rev-parse HEAD)" = "${PROJECT_COMMIT}"

env \
  ARTIFACT_DIR="${ARTIFACT_DIR}" \
  PROJECT_ROOT="${CLONE_DIR}" \
  ENABLE_TEST_TLS=true \
  bash "${CLONE_DIR}/kakomon9-qualify/provisioning/all.sh"

# These are transport/build inputs, not final image contents. Durable source,
# package, binary, frontend, and TLS evidence was copied by provisioning.
rm -rf "${ARTIFACT_DIR}" "${CLONE_DIR}"
