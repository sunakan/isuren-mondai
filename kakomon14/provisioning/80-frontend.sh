#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
WEBAPP_PUBLIC_DIR="${ISUREN_HOME}/webapp/public"

# frontendはAMI上でpnpm buildせず、事前にビルドしGitHub Releaseとして公開したものを取得する
# (t4g.smallでのpnpm installはOOMを起こしうる上、node/pnpmをAMIに含めずに済む。
# kakomon14/scripts/build-frontend-release.sh・scripts/github-release.sh参照)。
: "${FRONTEND_RELEASE_REPO_URL:=https://github.com/sunakan/isuren-mondai}"
: "${FRONTEND_RELEASE_OWNER_REPO:=sunakan/isuren-mondai}"
: "${FRONTEND_RELEASE_TAG:=latest}"
[[ "${FRONTEND_RELEASE_TAG}" == "latest" ||
  "${FRONTEND_RELEASE_TAG}" =~ ^kakomon14-frontend-v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "エラー: FRONTEND_RELEASE_TAGが不正です。" >&2
  exit 1
}
FRONTEND_RELEASE_DIR="${ISUREN_HOME}/.kakomon14-frontend-release"
FRONTEND_ARCHIVE="${FRONTEND_RELEASE_DIR}/kakomon14-frontend.tar.gz"
FRONTEND_CHECKSUM="${FRONTEND_ARCHIVE}.sha256"
# latest解決後の具体的なタグをPacker側(file provisioner)が回収し、AMIタグに記録するための
# 置き場所。FRONTEND_RELEASE_TAG=latestだとAMIのディスク中身だけでは実際に焼き込まれた
# バージョンが分からなくなるため。
RESOLVED_TAG_FILE="/tmp/kakomon14-frontend-release-tag"
RESOLVED_SHA256_FILE="/tmp/kakomon14-frontend-release-sha256"

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
  printf '%s\n' "${FRONTEND_RELEASE_TAG}" >"${RESOLVED_TAG_FILE}"
}

# sunakan/isuren-mondaiはpublicリポジトリのため、認証なしのcurlでダウンロードできる。
download_frontend_release() {
  local base_url="${FRONTEND_RELEASE_REPO_URL}/releases/download/${FRONTEND_RELEASE_TAG}"
  runuser -u "${ISUREN_USER}" -- mkdir -p "${FRONTEND_RELEASE_DIR}"
  runuser -u "${ISUREN_USER}" -- curl -fsSL -o "${FRONTEND_ARCHIVE}" "${base_url}/kakomon14-frontend.tar.gz"
  runuser -u "${ISUREN_USER}" -- curl -fsSL -o "${FRONTEND_CHECKSUM}" "${base_url}/kakomon14-frontend.tar.gz.sha256"
  (
    cd "${FRONTEND_RELEASE_DIR}"
    sha256sum --check "$(basename "${FRONTEND_CHECKSUM}")"
  )
  local f
  for f in frontend_hashes.json frontend_files.json; do
    runuser -u "${ISUREN_USER}" -- curl -fsSL -o "${FRONTEND_RELEASE_DIR}/${f}" "${base_url}/${f}"
  done
  FRONTEND_RELEASE_SHA256="$(sha256sum "${FRONTEND_ARCHIVE}" | awk '{print $1}')"
  printf '%s\n' "${FRONTEND_RELEASE_SHA256}" >"${RESOLVED_SHA256_FILE}"
  log "frontend release: downloaded ${FRONTEND_RELEASE_TAG} (${FRONTEND_RELEASE_SHA256})"
}

# rsync --deleteで、前回分の古いファイル(ハッシュ付きファイル名が変わったもの等)を確実に除去する。
# isurenユーザーで実行し、所有者を揃える(chownでの後追い修正を避ける)。
deploy_public() {
  local staging="${FRONTEND_RELEASE_DIR}/public"
  runuser -u "${ISUREN_USER}" -- rm -rf "${staging}"
  runuser -u "${ISUREN_USER}" -- mkdir -p "${staging}" "${WEBAPP_PUBLIC_DIR}"
  runuser -u "${ISUREN_USER}" -- tar -xzf "${FRONTEND_ARCHIVE}" -C "${staging}"
  # LICENSE: GitHub Release単体配布のアーティファクトとしては同梱している
  # (kakomon14/scripts/build-frontend-release.sh参照)が、nginx配信対象のwebapp/publicには不要
  # (~/isucon14/LICENSEで著作権表示は既に満たしている。50-source.sh参照)。
  runuser -u "${ISUREN_USER}" -- rm -f "${staging}/LICENSE"
  runuser -u "${ISUREN_USER}" -- rsync -a --delete "${staging}/" "${WEBAPP_PUBLIC_DIR}/"
  log "webapp/public: deployed"
}

resolve_frontend_release_tag
persist_resolved_tag
download_frontend_release
deploy_public

log "80-frontend.sh: done"
