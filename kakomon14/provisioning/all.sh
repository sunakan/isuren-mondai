#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

log "start"

# Mac側がPacker build完了後に$BUILD_LOGからこのマーカーで囲まれた範囲を抜き出し、各stepの
# 開始/終了時刻・ディスク使用量・exit statusからspanを事後生成する(99-verify.shのgoss出力
# 抽出と同じパターン)。empty.pkr.hclはprovisioning成功時(マーカーファイル検出時)のみこの範囲を
# sed抽出してビルドログに出すため、"spans: end"は必ずtrap側(下記)で出す必要がある
# (成功時にscript本体の最後にログ出力しても、$BUILD_LOGにはこの範囲外の行が一切載らないため)。
log "spans: begin"
log "provisioning.all: disk_total_bytes=$(disk_total_bytes)"
# Mac側(mise-tasks/kakomon14/build)がPacker build前に生成したTRACEPARENTが、cloud-init経由で
# 本当にここまで伝播したかをログから検証できるようにする(Mac側は生成した値を無条件に信じず、
# このログ行から抽出した値と突き合わせる)。disk_beforeは全step実行前(=provisioning全体としての
# 開始時点)のディスク使用量で、各stepのdisk_before/disk_afterとは別に全体の増分を見るためのもの。
log "provisioning.all: start_ns=$(now_ns) disk_before=$(disk_used_bytes) traceparent=${TRACEPARENT:-<unset>}"

# provisioning.all span(全stepをまとめてEC2側全体を表すspan)の終了記録・"spans: end"は、
# 途中のstepが失敗してset -eによりall.shが中断されても確実に出力されるよう、EXIT trapで保証する。
# $?を最初の行で捕まえてから使う(traps内でも通常の関数同様、localの前に他のコマンドを挟むと
# $?が上書きされる)。
record_provisioning_all_end() {
  local status=$?
  log "provisioning.all: end_ns=$(now_ns) disk_after=$(disk_used_bytes) exit_status=${status}"
  log "spans: end"
}
trap record_provisioning_all_end EXIT

run_step() {
  local script="$1"
  local start_ns
  start_ns="$(now_ns)"
  local disk_before
  disk_before="$(disk_used_bytes)"
  # bash "${SCRIPT_DIR}/${script}"を裸のトップレベルコマンドのまま置くと、失敗時にset -eが
  # ここで即座にall.shを打ち切ってしまい、以降のlog行(end_ns/disk_after/exit_status)に
  # 到達できない。||で失敗を捕まえてから使うことで最後まで到達させる。
  local status=0
  bash "${SCRIPT_DIR}/${script}" || status=$?
  log "step: script=${script} start_ns=${start_ns} end_ns=$(now_ns) disk_before=${disk_before} disk_after=$(disk_used_bytes) exit_status=${status}"
  return "$status"
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
run_step 85-bench-build.sh
run_step 90-nginx.sh
run_step 99-verify.sh

log "all.sh: done"
# cloud-initのrunecmdは、ここまでの一連のコマンドのどれかが失敗しても`cloud-init status --wait`が
# 成功扱い(status: done)を返すことがある(実機で確認済み: goss validate失敗でall.shが停止しても
# AMI作成が続行された)。empty.pkr.hclがこのファイルの存在を「provisioning完走の証拠」として
# 別途確認する(/opt/isuren-mondaiはこの後削除されるため、外側に置く)。
touch /var/lib/cloud/kakomon14-provisioned
