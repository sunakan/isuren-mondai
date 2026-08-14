#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"

# provisioning各スクリプトが冪等コマンドの無条件実行(if判定なし)に簡略化されたため、
# 「実際に意図通りの状態になったか」の確認はここに一本化する(goss.yaml参照)。
# gossはisurenのmise管理下にインストールされるが、mysql -uroot等root権限が必要なチェックを
# 含むため、フルパスを解決した上でroot(このスクリプト自体の実行ユーザー)として実行する
# (30-runtime.sh・70-webapp-go.shと同じ「isurenのmiseでフルパス解決し、実行ユーザーは変える」パターン)。
GOSS_BIN="$(runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" which goss)"

"${GOSS_BIN}" validate -g "${SCRIPT_DIR}/goss.yaml" --format documentation

log "99-verify.sh: done"
