#!/usr/bin/env bash
set -euo pipefail

PROJECT_COMMIT=__PROJECT_COMMIT__
REPOSITORY_URL=https://github.com/sunakan/isuren-mondai.git
CLONE_DIR=/opt/isuren-mondai-source
ARTIFACT_DIR=/opt/isuren-artifacts/kakomon9-qualify
READY_FILE=/opt/isuren-artifacts/kakomon9-qualify.ready

if [[ ! "${PROJECT_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'cloud-init received an invalid project commit' >&2
  exit 1
fi

for _ in $(seq 1 3600); do
  if [ -f "${READY_FILE}" ]; then
    break
  fi
  sleep 1
done
test -f "${READY_FILE}"
test -d "${ARTIFACT_DIR}"

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
rm -f "${READY_FILE}"
