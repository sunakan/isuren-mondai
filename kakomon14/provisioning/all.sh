#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

log "start"

bash "${SCRIPT_DIR}/10-base.sh"
bash "${SCRIPT_DIR}/20-user.sh"
bash "${SCRIPT_DIR}/30-runtime.sh"
bash "${SCRIPT_DIR}/40-mysql.sh"
bash "${SCRIPT_DIR}/50-source.sh"
bash "${SCRIPT_DIR}/60-initdb.sh"
bash "${SCRIPT_DIR}/70-webapp-go.sh"
bash "${SCRIPT_DIR}/75-matcher.sh"
bash "${SCRIPT_DIR}/77-payment-mock.sh"
bash "${SCRIPT_DIR}/80-frontend.sh"
bash "${SCRIPT_DIR}/90-nginx.sh"
bash "${SCRIPT_DIR}/95-deploy-helper.sh"
bash "${SCRIPT_DIR}/99-verify.sh"

log "all.sh: done"
# cloud-initのrunecmdは、ここまでの一連のコマンドのどれかが失敗しても`cloud-init status --wait`が
# 成功扱い(status: done)を返すことがある(実機で確認済み: goss validate失敗でall.shが停止しても
# AMI作成が続行された)。empty.pkr.hclがこのファイルの存在を「provisioning完走の証拠」として
# 別途確認する(/opt/isuren-mondaiはこの後削除されるため、外側に置く)。
touch /var/lib/cloud/kakomon14-provisioned
