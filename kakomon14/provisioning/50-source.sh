#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# isucon14本家への直接依存をやめ、isuren-mondai自身に取り込んだ
# upstream/isucon14/ (go/frontend/payment_mock/openapi.yaml)を取得元にする
# (AGENTS.md「過去問コードの取り込み(upstream)方針」)。
: "${UPSTREAM_REPO_URL:=https://github.com/sunakan/isuren-mondai.git}"
: "${UPSTREAM_COMMIT:=b75fd72480ab39a83c1a14461b6e1451107c55f4}"
UPSTREAM_SUBPATH="upstream/isucon14"

# webapp/sql(サンプルデータ)とfrontend/public(画像等の静的アセット)は自分で手を加えない
# 読み取り専用データのため、取り込まず本家から直接sparse-checkoutで取得する
# (upstream/isucon14/NOTICE.md参照)。
# コミットは/Users/user01/works/github.com/isucon/isucon14のHEADに合わせて固定
# (isucon14公式リポジトリのmainブランチ、2024-12-13時点)。
: "${ISUCON14_REPO_URL:=https://github.com/isucon/isucon14.git}"
: "${ISUCON14_COMMIT:=53f8b627e040c30ebec600457c6c97da008b84b0}"
ISUCON14_SUBPATHS=("webapp/sql" "frontend/public")

ISUREN_HOME="/home/${ISUREN_USER}"
UPSTREAM_CHECKOUT_DIR="${ISUREN_HOME}/.isuren-mondai-upstream"
UPSTREAM_DIR="${UPSTREAM_CHECKOUT_DIR}/${UPSTREAM_SUBPATH}"
ISUCON14_CHECKOUT_DIR="${ISUREN_HOME}/.isucon14-upstream"
ISUCON14_LINK="${ISUREN_HOME}/isucon14"
WEBAPP_LINK="${ISUREN_HOME}/webapp"

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
# 取り込んだ実体を指すシンボリックリンクを張る。
link_isucon14() {
  if [ -L "${ISUCON14_LINK}" ] && [ "$(readlink "${ISUCON14_LINK}")" = "${UPSTREAM_DIR}" ]; then
    log "isucon14: symlink already up to date"
  else
    ln -sfn "${UPSTREAM_DIR}" "${ISUCON14_LINK}"
    log "isucon14: symlink created"
  fi
}

# 70-webapp-go.sh等が`~/webapp`を参照する既存の前提を変えずに済むよう、
# 取り込んだ実体を指すシンボリックリンクを張る。
#
# Why not `~/webapp`を実ディレクトリにして子要素ごとに個別リンクする方式:
# 一度その方式で実装したが、systemdのWorkingDirectory=~/webapp/go はシンボリックリンクの
# 実体側パスにchdirするため、webapp/goプロセスから見た`../sql`は`~/webapp/sql`ではなく
# upstreamツリー内の(存在しない)webapp/sqlに解決されてしまい、/api/initializeが
# `fork/exec ../sql/init.sh: no such file or directory`で失敗した。
# sqlのシンボリックリンクをupstreamツリーの中(webapp/go と同じ実ディレクトリ)に置けば、
# `..`の解決先がupstreamツリー内で完結するため、`~/webapp`自体は単一リンクで問題ない。
link_webapp() {
  if [ -L "${WEBAPP_LINK}" ] && [ "$(readlink "${WEBAPP_LINK}")" = "${UPSTREAM_DIR}/webapp" ]; then
    log "webapp: symlink already up to date"
  else
    ln -sfn "${UPSTREAM_DIR}/webapp" "${WEBAPP_LINK}"
    log "webapp: symlink created"
  fi
}

# webapp/sqlとfrontend/publicは本家(isucon14公式リポジトリ)取得のため、upstreamツリーの内側に
# シンボリックリンクで差し込む(理由はlink_webapp内のコメント参照)。
link_isucon14_into_upstream() {
  local target="${ISUCON14_CHECKOUT_DIR}/$1"
  local link="${UPSTREAM_DIR}/$1"
  if [ -L "${link}" ] && [ "$(readlink "${link}")" = "${target}" ]; then
    log "$1: symlink already up to date"
  else
    ln -sfn "${target}" "${link}"
    log "$1: symlink created"
  fi
}

# cone modeはリポジトリルート直下のファイルも自動的に含むため、isuren-mondai自身の
# mise.toml(Packer/AWSタスク定義。kakomon14のgo/nodeとは無関係)も一緒に取得されてしまう。
# これが~/webapp/go等でmiseを実行する際にディレクトリ探索へ引っかかり、
# 「untrusted config」としてmiseがエラー終了する原因になるため取り除く。
remove_upstream_root_mise_toml() {
  local f="${UPSTREAM_CHECKOUT_DIR}/mise.toml"
  if [ -f "${f}" ]; then
    rm -f "${f}"
    log "upstream: removed stray ${f}"
  fi
}

sparse_checkout_fetch "${UPSTREAM_CHECKOUT_DIR}" "${UPSTREAM_REPO_URL}" "${UPSTREAM_COMMIT}" "${UPSTREAM_SUBPATH}"
sparse_checkout_fetch "${ISUCON14_CHECKOUT_DIR}" "${ISUCON14_REPO_URL}" "${ISUCON14_COMMIT}" "${ISUCON14_SUBPATHS[@]}"
remove_upstream_root_mise_toml
link_isucon14
link_webapp
link_isucon14_into_upstream "webapp/sql"
link_isucon14_into_upstream "frontend/public"

log "50-source.sh: done"
