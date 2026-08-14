#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

log "start"

# AMIスナップショット肥大化(実データ3.2GBに対し9GiB超)の原因調査用に、各ステップの前後で
# ディスク使用量を記録する。
run_step() {
  local script="$1"
  log "disk usage before ${script}: $(df -h / | awk 'NR==2{print $3}')"
  bash "${SCRIPT_DIR}/${script}"
  log "disk usage after ${script}: $(df -h / | awk 'NR==2{print $3}')"
}

run_step 10-base.sh
run_step 20-user.sh
run_step 30-runtime.sh
run_step 40-mysql.sh
run_step 50-source.sh
run_step 60-initdb.sh
run_step 70-webapp-go.sh
run_step 75-matcher.sh
run_step 77-payment-mock.sh
run_step 80-frontend.sh
run_step 90-nginx.sh
run_step 95-deploy-helper.sh
run_step 99-verify.sh

log "all.sh: done"
# cloud-initのrunecmdは、ここまでの一連のコマンドのどれかが失敗しても`cloud-init status --wait`が
# 成功扱い(status: done)を返すことがある(実機で確認済み: goss validate失敗でall.shが停止しても
# AMI作成が続行された)。empty.pkr.hclがこのファイルの存在を「provisioning完走の証拠」として
# 別途確認する(/opt/isuren-mondaiはこの後削除されるため、外側に置く)。
touch /var/lib/cloud/kakomon14-provisioned
