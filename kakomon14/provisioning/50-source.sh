#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# isucon14本家への直接依存をやめ、isuren-mondai自身に取り込んだ
# upstream/isucon14/ (go/frontend/payment_mock/openapi.yaml)を取得元にする
# (AGENTS.md「過去問コードの取り込み(upstream)方針」)。
: "${UPSTREAM_REPO_URL:=https://github.com/sunakan/isuren-mondai.git}"
: "${UPSTREAM_COMMIT:=d9d526895d97a3707dda96c8fa722ec15356ba44}"
UPSTREAM_SUBPATH="upstream/isucon14"

# webapp/sql(サンプルデータ)・env.shテンプレート(DB接続情報。isucon-user roleのtemplates/env.sh)は
# 自分で手を加えない読み取り専用データのため、取り込まず本家から直接sparse-checkoutで取得する
# (upstream/isucon14/NOTICE.md参照)。
# env.shはISUCON_DB_USER/ISUCON_DB_PASSWORD="isucon"を含むが、本家の値をそのまま使う
# (isucon-user roleが作るDBユーザーとの整合を保つため書き換えない。40-mysql.sh参照)。
# コミットは/Users/user01/works/github.com/isucon/isucon14のHEADに合わせて固定
# (isucon14公式リポジトリのmainブランチ、2024-12-13時点)。
: "${ISUCON14_REPO_URL:=https://github.com/isucon/isucon14.git}"
: "${ISUCON14_COMMIT:=53f8b627e040c30ebec600457c6c97da008b84b0}"
ISUCON14_SUBPATHS=("webapp/sql" "provisioning/ansible/roles/isucon-user/templates")

ISUREN_HOME="/home/${ISUREN_USER}"
# sparse-checkoutの一時的な取得先。デプロイ完了後にcleanup_checkoutsで削除する
# (本番AMIではPackerビルド時に1回きりのプロビジョニングのため、取得後も残しておく必要がない。
# 残すとディスクを圧迫する上、mise実行時のディレクトリ探索に古いmise.tomlが引っかかる懸念もある)。
UPSTREAM_CHECKOUT_DIR="${ISUREN_HOME}/.isuren-mondai-upstream"
UPSTREAM_DIR="${UPSTREAM_CHECKOUT_DIR}/${UPSTREAM_SUBPATH}"
ISUCON14_CHECKOUT_DIR="${ISUREN_HOME}/.isucon14-upstream"
ISUCON14_DIR="${ISUREN_HOME}/isucon14"
WEBAPP_DIR="${ISUREN_HOME}/webapp"
ENV_SH_DEST="${ISUREN_HOME}/env.sh"

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

# 85-bench-build.shが`~/isucon14/bench`を参照する既存の前提を変えずに済むよう、
# 取り込んだ実体を~/isucon14へ実ファイルとしてデプロイする(rsyncはroot実行でもsrcの所有者
# (isuren、sparse_checkout_fetchがrunuser -u isurenで取得したもの)を保持する)。
#
# Why not シンボリックリンク: 以前はここをシンボリックリンクにしていたが、
# systemdのWorkingDirectory=~/webapp/go がシンボリックリンクの実体側パスにchdirするため
# `../sql`のような相対パス解決が取得用の一時ディレクトリ内で完結してしまう罠があった
# (下記deploy_webapp参照)。実ファイルとしてコピーすることでこの罠自体を無くしている。
deploy_isucon14() {
  rsync -a --delete "${UPSTREAM_DIR}/" "${ISUCON14_DIR}/"
  log "isucon14: deployed"
}

# NOTICE.mdはisuren-mondaiリポジトリの取り込み範囲・除外理由を記録した開発者向けメモで、
# 実行環境(AMI)には不要なため削除する。LICENSE(本家のMIT表示)は著作権表示要件のため残す。
cleanup_isucon14_notice() {
  rm -f "${ISUCON14_DIR}/NOTICE.md"
  log "isucon14/NOTICE.md: removed"
}

# frontendはAMI上でビルドせず事前ビルド済みのGitHub Releaseを取得する(80-frontend.sh)ため、
# ~/isucon14/frontend(ソース一式)はどこからも参照されない。
cleanup_isucon14_frontend() {
  rm -rf "${ISUCON14_DIR}/frontend"
  log "isucon14/frontend: removed"
}

# webapp/sqlは本家(isucon14公式リポジトリ)から別途取得したもの。
# ~/isucon14へ実ファイルとしてマージする(deploy_isucon14の後に呼ぶこと)。
deploy_isucon14_readonly_data() {
  rsync -a --delete "${ISUCON14_CHECKOUT_DIR}/$1/" "${ISUCON14_DIR}/$1/"
  log "$1: deployed"
}

# 70-webapp-go.sh等が`~/webapp`を参照する既存の前提を変えずに済むよう、
# ~/isucon14/webapp(sql等のマージ済み)を~/webappへ実ファイルとして複製する。
# 複製後の~/isucon14/webappは使われない(bench役が~/isucon14で必要とするのは~/isucon14/bench
# のみ)ため削除する。
deploy_webapp() {
  rsync -a --delete "${ISUCON14_DIR}/webapp/" "${WEBAPP_DIR}/"
  rm -rf "${ISUCON14_DIR}/webapp"
  log "webapp: deployed"
}

# 70-webapp-go.shのsystemdユニットがEnvironmentFile=~/env.shとして参照する。
deploy_env_sh() {
  install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
    "${ISUCON14_CHECKOUT_DIR}/provisioning/ansible/roles/isucon-user/templates/env.sh" "${ENV_SH_DEST}"
  log "env.sh: deployed"
}

# 取得用の一時ディレクトリ(.git含む)は上記デプロイが終われば不要。本番AMIでは1回きりの
# プロビジョニングのため、残しておく再利用メリットよりディスク使用量・古い設定混入リスクを避ける
# ことを優先する。
cleanup_checkouts() {
  rm -rf "${UPSTREAM_CHECKOUT_DIR}" "${ISUCON14_CHECKOUT_DIR}"
  log "checkouts: removed"
}

sparse_checkout_fetch "${UPSTREAM_CHECKOUT_DIR}" "${UPSTREAM_REPO_URL}" "${UPSTREAM_COMMIT}" "${UPSTREAM_SUBPATH}"
sparse_checkout_fetch "${ISUCON14_CHECKOUT_DIR}" "${ISUCON14_REPO_URL}" "${ISUCON14_COMMIT}" "${ISUCON14_SUBPATHS[@]}"
deploy_isucon14
cleanup_isucon14_notice
cleanup_isucon14_frontend
deploy_isucon14_readonly_data "webapp/sql"
deploy_webapp
deploy_env_sh
cleanup_checkouts

log "50-source.sh: done"
