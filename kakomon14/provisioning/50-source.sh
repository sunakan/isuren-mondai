#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# isucon14本家への直接依存をやめ、isuren-mondai自身にvendorした
# kakomon14/vendor/isucon14/ (go/frontend/payment_mock/openapi.yaml)を取得元にする
# (AGENTS.md「過去問コードの取り込み(vendor)方針」)。
: "${VENDOR_REPO_URL:=https://github.com/sunakan/isuren-mondai.git}"
: "${VENDOR_COMMIT:=__VENDOR_COMMIT_PLACEHOLDER__}"
VENDOR_SUBPATH="kakomon14/vendor/isucon14"

# webapp/sql(サンプルデータ)とfrontend/public(画像等の静的アセット)は自分で手を加えない
# 読み取り専用データのため、vendorせず本家から直接sparse-checkoutで取得する
# (kakomon14/vendor/isucon14/NOTICE.md参照)。
# コミットは/Users/user01/works/github.com/isucon/isucon14のHEADに合わせて固定
# (isucon14公式リポジトリのmainブランチ、2024-12-13時点)。
: "${ISUCON14_REPO_URL:=https://github.com/isucon/isucon14.git}"
: "${ISUCON14_COMMIT:=53f8b627e040c30ebec600457c6c97da008b84b0}"
ISUCON14_UPSTREAM_SUBPATHS=("webapp/sql" "frontend/public")

ISUREN_HOME="/home/${ISUREN_USER}"
VENDOR_CHECKOUT_DIR="${ISUREN_HOME}/.isuren-mondai-vendor"
VENDOR_DIR="${VENDOR_CHECKOUT_DIR}/${VENDOR_SUBPATH}"
UPSTREAM_CHECKOUT_DIR="${ISUREN_HOME}/.isucon14-upstream"
ISUCON14_LINK="${ISUREN_HOME}/isucon14"
WEBAPP_DIR="${ISUREN_HOME}/webapp"

# Why not curl+tar: GitHubのcodeload archiveエンドポイントはリポジトリ全体のtarballしか
# 生成できず、サブパス指定で絞り込めない。過去問を追加するたびリポジトリは肥大化していく
# (特にDBサンプルデータ・画像アセットが重くなりがち)ため、必要なサブツリーだけ転送する
# sparse-checkoutを使う。
# Why not `git clone --depth 1`: cloneはデフォルトブランチの先端しか浅く取れず、
# 過去にピン留めした特定コミットを狙って取得できない。git init+remote add+特定SHAをfetchする
# 構成にすることで、shallow(--depth 1)のまま任意のコミットを指定できるようにしている。
# cone modeのsparse-checkoutはリポジトリルート直下のファイル(LICENSE等)も自動的に含むため、
# 取得先ごとにLICENSEが自然に同梱される(MITの著作権表示同梱要件を満たす)。
# 同じリポジトリ・同じコミットから複数パスを取りたい場合は、.gitを2つ持つ無駄を避けるため
# 引数でサブパスを複数渡し、1つのsparse-checkoutにまとめる。
sparse_checkout_fetch() {
  local checkout_dir="$1" repo_url="$2" commit="$3"
  shift 3
  local subpaths=("$@")

  if [ ! -d "${checkout_dir}/.git" ]; then
    runuser -u "${ISUREN_USER}" -- git init --quiet "${checkout_dir}"
    runuser -u "${ISUREN_USER}" -- git -C "${checkout_dir}" remote add origin "${repo_url}"
    runuser -u "${ISUREN_USER}" -- git -C "${checkout_dir}" sparse-checkout set --cone "${subpaths[@]}"
    log "$(basename "${checkout_dir}"): initialized"
  fi

  local current_commit
  current_commit="$(runuser -u "${ISUREN_USER}" -- git -C "${checkout_dir}" rev-parse HEAD 2>/dev/null || echo "")"
  if [ "${current_commit}" != "${commit}" ]; then
    runuser -u "${ISUREN_USER}" -- git -C "${checkout_dir}" fetch --quiet --depth 1 --filter=blob:none origin "${commit}"
    runuser -u "${ISUREN_USER}" -- git -C "${checkout_dir}" checkout --quiet "${commit}"
    log "$(basename "${checkout_dir}"): checked out ${commit}"
  else
    log "$(basename "${checkout_dir}"): already at ${commit}"
  fi
}

# 80-frontend.shが`~/isucon14/frontend`を参照する既存の前提を変えずに済むよう、
# vendorされた実体を指すシンボリックリンクを張る。
link_isucon14() {
  if [ -L "${ISUCON14_LINK}" ] && [ "$(readlink "${ISUCON14_LINK}")" = "${VENDOR_DIR}" ]; then
    log "isucon14: symlink already up to date"
  else
    ln -sfn "${VENDOR_DIR}" "${ISUCON14_LINK}"
    log "isucon14: symlink created"
  fi
}

# go/payment_mock/openapi.yamlはvendor、sqlは本家と取得元が分かれたため、
# `~/webapp`は実ディレクトリにして子要素ごとに個別のシンボリックリンクを張る。
link_webapp() {
  mkdir -p "${WEBAPP_DIR}"
  chown "${ISUREN_USER}:${ISUREN_USER}" "${WEBAPP_DIR}"
  local name target link
  for name in go payment_mock openapi.yaml; do
    target="${VENDOR_DIR}/webapp/${name}"
    link="${WEBAPP_DIR}/${name}"
    if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
      log "webapp/${name}: symlink already up to date"
    else
      ln -sfn "${target}" "${link}"
      log "webapp/${name}: symlink created"
    fi
  done
  if [ -L "${WEBAPP_DIR}/sql" ] && [ "$(readlink "${WEBAPP_DIR}/sql")" = "${UPSTREAM_CHECKOUT_DIR}/webapp/sql" ]; then
    log "webapp/sql: symlink already up to date"
  else
    ln -sfn "${UPSTREAM_CHECKOUT_DIR}/webapp/sql" "${WEBAPP_DIR}/sql"
    log "webapp/sql: symlink created"
  fi
}

# frontend/publicも本家取得のため、vendorされたfrontendツリー内にシンボリックリンクで差し込む。
link_frontend_public() {
  local target="${UPSTREAM_CHECKOUT_DIR}/frontend/public"
  local link="${VENDOR_DIR}/frontend/public"
  if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
    log "frontend/public: symlink already up to date"
  else
    ln -sfn "${target}" "${link}"
    log "frontend/public: symlink created"
  fi
}

sparse_checkout_fetch "${VENDOR_CHECKOUT_DIR}" "${VENDOR_REPO_URL}" "${VENDOR_COMMIT}" "${VENDOR_SUBPATH}"
sparse_checkout_fetch "${UPSTREAM_CHECKOUT_DIR}" "${ISUCON14_REPO_URL}" "${ISUCON14_COMMIT}" "${ISUCON14_UPSTREAM_SUBPATHS[@]}"
link_isucon14
link_webapp
link_frontend_public

log "50-source.sh: done"
