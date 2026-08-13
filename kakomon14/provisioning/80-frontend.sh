#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
WEBAPP_PUBLIC_DIR="${ISUREN_HOME}/webapp/public"
BENCHRUN_DIR="${ISUREN_HOME}/isucon14/bench/benchrun"

# frontendはAMI上でpnpm buildせず、事前にビルドしGitHub Releaseとして公開したものを取得する
# (t4g.smallでのpnpm installはOOMを起こしうる上、node/pnpmをAMIに含めずに済む。
# kakomon14/scripts/build-frontend-release.sh・scripts/github-release.sh参照)。
: "${FRONTEND_RELEASE_REPO_URL:=https://github.com/sunakan/isuren-mondai}"
: "${FRONTEND_RELEASE_TAG:=kakomon14-frontend-v1.0.0}"
FRONTEND_RELEASE_BASE_URL="${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}"
FRONTEND_RELEASE_DIR="${ISUREN_HOME}/.kakomon14-frontend-release"

# sunakan/isuren-mondaiはpublicリポジトリのため、認証なしのcurlでダウンロードできる。
download_frontend_release() {
  runuser -u "${ISUREN_USER}" -- mkdir -p "${FRONTEND_RELEASE_DIR}"
  local f
  for f in kakomon14-frontend.tar.gz frontend_hashes.json frontend_files.json; do
    runuser -u "${ISUREN_USER}" -- curl -fsSL -o "${FRONTEND_RELEASE_DIR}/${f}" "${FRONTEND_RELEASE_BASE_URL}/${f}"
  done
  log "frontend release: downloaded ${FRONTEND_RELEASE_TAG}"
}

# rsync --deleteで、前回分の古いファイル(ハッシュ付きファイル名が変わったもの等)を確実に除去する。
# isurenユーザーで実行し、所有者を揃える(chownでの後追い修正を避ける)。
deploy_public() {
  local staging="${FRONTEND_RELEASE_DIR}/public"
  runuser -u "${ISUREN_USER}" -- rm -rf "${staging}"
  runuser -u "${ISUREN_USER}" -- mkdir -p "${staging}" "${WEBAPP_PUBLIC_DIR}"
  runuser -u "${ISUREN_USER}" -- tar -xzf "${FRONTEND_RELEASE_DIR}/kakomon14-frontend.tar.gz" -C "${staging}"
  runuser -u "${ISUREN_USER}" -- rsync -a --delete "${staging}/" "${WEBAPP_PUBLIC_DIR}/"
  log "webapp/public: deployed"
}

# frontend_hashes.json/frontend_files.jsonはbenchがfrontendの整合性確認に使うファイル
# (kakomon14/upstream/isucon14/NOTICE.md「コミット対象から外したもの」参照)。
# 取り込み時点の古い内容の上に、ダウンロードした最新版を上書きする。
deploy_benchrun_manifests() {
  local f
  for f in frontend_hashes.json frontend_files.json; do
    runuser -u "${ISUREN_USER}" -- cp "${FRONTEND_RELEASE_DIR}/${f}" "${BENCHRUN_DIR}/${f}"
  done
  log "bench/benchrun manifests: deployed"
}

download_frontend_release
deploy_public
deploy_benchrun_manifests

log "80-frontend.sh: done"
