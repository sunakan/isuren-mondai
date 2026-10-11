#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
STAGING_DIR="${ISUREN_HOME}/.kakomon10-qualify-staging"
RELEASE_ARCHIVE="${STAGING_DIR}/kakomon10-qualify-frontend.tar.gz"
RELEASE_CHECKSUM="${RELEASE_ARCHIVE}.sha256"
RELEASE_DIR="${STAGING_DIR}/release"
FRONTEND_RELEASE_REPO_URL="https://github.com/sunakan/isuren-mondai"
FRONTEND_RELEASE_OWNER_REPO="sunakan/isuren-mondai"
RESOLVED_TAG_FILE="/tmp/kakomon10-qualify-frontend-release-tag"
RESOLVED_SHA256_FILE="/tmp/kakomon10-qualify-frontend-release-sha256"

#
# targetのRelease入力を確認
#
: "${FRONTEND_RELEASE_TAG:=latest}"
: "${FRONTEND_RELEASE_SHA256:=}"
[[ "${FRONTEND_RELEASE_TAG}" == "latest" ||
  "${FRONTEND_RELEASE_TAG}" =~ ^kakomon10-qualify-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: invalid FRONTEND_RELEASE_TAG selector" >&2
  exit 1
}
if [ -n "${FRONTEND_RELEASE_SHA256}" ]; then
  [[ "${FRONTEND_RELEASE_SHA256}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "error: invalid FRONTEND_RELEASE_SHA256" >&2
    exit 1
  }
fi
rm -f "${RESOLVED_TAG_FILE}" "${RESOLVED_SHA256_FILE}"

resolve_frontend_release_tag() {
  if [ "${FRONTEND_RELEASE_TAG}" != "latest" ]; then
    return
  fi
  local resolved
  resolved="$(curl -fsSL "https://api.github.com/repos/${FRONTEND_RELEASE_OWNER_REPO}/releases?per_page=100" |
    jq -er '[.[] | select(.draft == false and .prerelease == false and
      (.tag_name | test("^kakomon10-qualify-frontend-v[0-9]+[.][0-9]+[.][0-9]+$")))] |
      sort_by(.published_at) | last | .tag_name')"
  if [ -z "${resolved}" ]; then
    echo "error: kakomon10-qualify-frontendのReleaseが見つかりませんでした(GitHub API: ${FRONTEND_RELEASE_OWNER_REPO})" >&2
    exit 1
  fi
  FRONTEND_RELEASE_TAG="${resolved}"
  log "frontend release: latestを${FRONTEND_RELEASE_TAG}に解決"
}

persist_resolved_tag() {
  printf '%s\n' "${FRONTEND_RELEASE_TAG}" >"${RESOLVED_TAG_FILE}"
}

#
# Release archiveを取得して検証
#
# frontendと凍結した初期データを一度だけ展開し、80-frontend.shで再利用する。
download_release() {
  local base_url="${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}"
  install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${STAGING_DIR}"
  runuser -u "${ISUREN_USER}" -- curl -fsSL \
    "${base_url}/kakomon10-qualify-frontend.tar.gz" -o "${RELEASE_ARCHIVE}"
  runuser -u "${ISUREN_USER}" -- curl -fsSL \
    "${base_url}/kakomon10-qualify-frontend.tar.gz.sha256" -o "${RELEASE_CHECKSUM}"
  test "$(wc -l <"${RELEASE_CHECKSUM}" | tr -d ' ')" -eq 1
  grep -Eq '^[0-9a-f]{64} [ *]kakomon10-qualify-frontend[.]tar[.]gz$' "${RELEASE_CHECKSUM}"
  (
    cd "${STAGING_DIR}"
    sha256sum --check "$(basename "${RELEASE_CHECKSUM}")"
  )
  local resolved_sha256
  resolved_sha256="$(sha256sum "${RELEASE_ARCHIVE}" | awk '{print $1}')"
  if [ -n "${FRONTEND_RELEASE_SHA256}" ]; then
    test "${resolved_sha256}" = "${FRONTEND_RELEASE_SHA256}"
  fi
  printf '%s\n' "${resolved_sha256}" >"${RESOLVED_SHA256_FILE}"
  log "frontend release: downloaded ${FRONTEND_RELEASE_TAG} (${resolved_sha256})"
}

#
# manifestと必要な初期データを確認
#
extract_release() {
  install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${RELEASE_DIR}"
  runuser -u "${ISUREN_USER}" -- tar -xzf "${RELEASE_ARCHIVE}" -C "${RELEASE_DIR}"
  require_file "${RELEASE_DIR}/LICENSE"
  require_file "${RELEASE_DIR}/MANIFEST.sha256"
  require_file "${RELEASE_DIR}/mysql/1_DummyEstateData.sql"
  require_file "${RELEASE_DIR}/mysql/2_DummyChairData.sql"
  require_file "${RELEASE_DIR}/fixture/chair_condition.json"
  require_file "${RELEASE_DIR}/fixture/estate_condition.json"
  require_file "${RELEASE_DIR}/public/index.html"
  (
    cd "${RELEASE_DIR}"
    sha256sum --check MANIFEST.sha256
  )
}

resolve_frontend_release_tag
persist_resolved_tag
download_release
extract_release

#
# resetが読む本家pathへ凍結SQLを配置
#
# POST /initializeがcwd相対でSQLを読むので、DB投入後もfileを保持する。
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${RELEASE_DIR}/mysql/1_DummyEstateData.sql" "${APP_ROOT}/webapp/mysql/db/1_DummyEstateData.sql"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${RELEASE_DIR}/mysql/2_DummyChairData.sql" "${APP_ROOT}/webapp/mysql/db/2_DummyChairData.sql"

#
# schemaから順にDBを初期化
#
# 0_Schema.sqlがDBを作るため、接続時にDB名を指定しない。
cat "${APP_ROOT}/webapp/mysql/db/0_Schema.sql" \
  "${APP_ROOT}/webapp/mysql/db/1_DummyEstateData.sql" \
  "${APP_ROOT}/webapp/mysql/db/2_DummyChairData.sql" |
  mysql --defaults-file=/dev/null -h 127.0.0.1 -P 3306 -u isucon -pisucon
test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e "SELECT COUNT(*) FROM isuumo.chair")" -gt 0
test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e "SELECT COUNT(*) FROM isuumo.estate")" -gt 0

#
# Applicationとbenchのfixtureを配置
#
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}/webapp/fixture"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${RELEASE_DIR}/fixture/chair_condition.json" "${APP_ROOT}/webapp/fixture/chair_condition.json"
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${RELEASE_DIR}/fixture/estate_condition.json" "${APP_ROOT}/webapp/fixture/estate_condition.json"

# benchはcwd相対の../initial-dataを読む。Release時に生成したsnapshotを保持する。
require_file "${RELEASE_DIR}/initial-data-result/chair_json.txt"
require_file "${RELEASE_DIR}/initial-data-result/estate_json.txt"
test -d "${RELEASE_DIR}/initial-data-result/draft_data"
test -d "${RELEASE_DIR}/initial-data-result/verification_data"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}/initial-data/result"
rsync -a "${RELEASE_DIR}/initial-data-result/" "${APP_ROOT}/initial-data/result/"
chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}/initial-data/result"

#
# 配置したRelease identityを記録
#
install -m 0644 "${RELEASE_DIR}/LICENSE" "${PROVENANCE_DIR}/frontend-LICENSE"
install -m 0644 "${RELEASE_DIR}/MANIFEST.sha256" "${PROVENANCE_DIR}/frontend-MANIFEST.sha256"
cat >>"${PROVENANCE_DIR}/recipe.txt" <<EOF
frontend_release_tag=${FRONTEND_RELEASE_TAG}
frontend_release_sha256=$(cat "${RESOLVED_SHA256_FILE}")
EOF

log "60-initdb.sh: official schema + frozen dummy data loaded, bench/fixture data staged"
