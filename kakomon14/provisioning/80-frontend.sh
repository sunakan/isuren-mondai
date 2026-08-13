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
: "${FRONTEND_RELEASE_OWNER_REPO:=sunakan/isuren-mondai}"
# デフォルトはlatest(起動のたびに最新のkakomon14-frontend-*releaseを解決)。
# タグを明示指定すればそのバージョンにピン留めできる(例: kakomon14-frontend-v1.0.1)。
: "${FRONTEND_RELEASE_TAG:=latest}"
FRONTEND_RELEASE_DIR="${ISUREN_HOME}/.kakomon14-frontend-release"
# latest解決後の具体的なタグをPacker側(file provisioner)が回収し、AMIタグに記録するための
# 置き場所。FRONTEND_RELEASE_TAG=latestだとAMIのディスク中身だけでは実際に焼き込まれた
# バージョンが分からなくなるため。
RESOLVED_TAG_FILE="/tmp/kakomon14-frontend-release-tag"

# 1つのリポジトリで複数過去問(kakomon13等)のReleaseを扱うため、GitHubの/releases/latest
# (タグprefixを問わずリポジトリ全体で最新のものを返す)は使えない。releases一覧(作成日時降順)から
# kakomon14-frontend-プレフィックスの先頭を拾う。
resolve_frontend_release_tag() {
  if [ "${FRONTEND_RELEASE_TAG}" != "latest" ]; then
    return
  fi
  local resolved
  resolved="$(curl -fsSL "https://api.github.com/repos/${FRONTEND_RELEASE_OWNER_REPO}/releases" |
    grep -o '"tag_name": *"kakomon14-frontend-[^"]*"' | head -n1 |
    sed -E 's/.*"(kakomon14-frontend-[^"]*)"$/\1/')"
  if [ -z "${resolved}" ]; then
    echo "エラー: kakomon14-frontendのReleaseが見つかりませんでした(GitHub API: ${FRONTEND_RELEASE_OWNER_REPO})" >&2
    exit 1
  fi
  FRONTEND_RELEASE_TAG="${resolved}"
  log "frontend release: latestを${FRONTEND_RELEASE_TAG}に解決"
}

# root(cloud-init runcmd)実行のためデフォルトumaskで644になり、ssh_username(ubuntu)からの
# file provisioner(download)で読める。
persist_resolved_tag() {
  echo "${FRONTEND_RELEASE_TAG}" >"${RESOLVED_TAG_FILE}"
}

# sunakan/isuren-mondaiはpublicリポジトリのため、認証なしのcurlでダウンロードできる。
download_frontend_release() {
  local base_url="${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}"
  runuser -u "${ISUREN_USER}" -- mkdir -p "${FRONTEND_RELEASE_DIR}"
  local f
  for f in kakomon14-frontend.tar.gz frontend_hashes.json frontend_files.json; do
    runuser -u "${ISUREN_USER}" -- curl -fsSL -o "${FRONTEND_RELEASE_DIR}/${f}" "${base_url}/${f}"
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

resolve_frontend_release_tag
persist_resolved_tag
download_frontend_release
deploy_public
deploy_benchrun_manifests

log "80-frontend.sh: done"
