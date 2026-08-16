#!/usr/bin/env bash
set -euo pipefail

BASE_COMMIT=ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0
REPOSITORY_URL=https://github.com/isucon/isucon9-qualify.git
CANDIDATE_COMMIT="${1:-}"
if [[ ! "${CANDIDATE_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'usage: audit-upstream-update.sh <candidate-full-sha>' >&2
  exit 2
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
git init --quiet "${work_dir}/official"
git -C "${work_dir}/official" remote add origin "${REPOSITORY_URL}"
git -C "${work_dir}/official" fetch --quiet --depth 1 origin "${BASE_COMMIT}"
git -C "${work_dir}/official" fetch --quiet --depth 1 origin "${CANDIDATE_COMMIT}"

printf 'managed baseline: %s\n' "${BASE_COMMIT}"
printf 'candidate:        %s\n' "${CANDIDATE_COMMIT}"
printf 'frontend tree:    %s -> %s\n' \
  "$(git -C "${work_dir}/official" rev-parse "${BASE_COMMIT}:webapp/public")" \
  "$(git -C "${work_dir}/official" rev-parse "${CANDIDATE_COMMIT}:webapp/public")"
printf '\nmanaged Go source diff:\n'
git -C "${work_dir}/official" diff --stat "${BASE_COMMIT}" "${CANDIDATE_COMMIT}" -- \
  go.mod go.sum cmd/bench bench webapp/go
printf '\nfrontend tree diff (review only; never auto-imported):\n'
git -C "${work_dir}/official" diff --stat "${BASE_COMMIT}" "${CANDIDATE_COMMIT}" -- webapp/public

echo
echo 'This command is audit-only. Updating requires an explicit edit that records both full SHAs.'
