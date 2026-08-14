#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
# gossはビルド時の検証にしか使わず、goと違い本番稼働中(チューニング中の再ビルド等)には一切
# 使わないため、mise.ami.tomlには加えず、ここで一時的に取得し確認後に削除する
# (goss.yaml自体は/opt/isuren-mondaiごと削除される。generate-user-data.py参照)。
GOSS_VERSION="0.4.10"

# provisioning各スクリプトが冪等コマンドの無条件実行(if判定なし)に簡略化されたため、
# 「実際に意図通りの状態になったか」の確認はここに一本化する(goss.yaml参照)。
# mysql -uroot等root権限が必要なチェックを含むため、isurenのmiseでフルパス解決した上で
# root(このスクリプト自体の実行ユーザー)として実行する(30-runtime.sh・70-webapp-go.shと同じパターン)。
runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" install "goss@${GOSS_VERSION}"
GOSS_BIN="$(runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" where "goss@${GOSS_VERSION}")/bin/goss"

# ビルド成功時、Packer側(empty.pkr.hcl)がこの開始/終了ログをマーカーにcloud-init-output.logから
# goss validateの出力だけを抜き出してビルドログに出す。cloud-init status --waitは失敗時しか
# ログをtailしないため、成功時に「本当に全項目を検証できたか」を確認する手段がここ以外に無い。
log "99-verify.sh: goss validate start"
"${GOSS_BIN}" validate -g "${SCRIPT_DIR}/goss.yaml" --format documentation
log "99-verify.sh: goss validate end"

runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" uninstall "goss@${GOSS_VERSION}"

log "99-verify.sh: done"
