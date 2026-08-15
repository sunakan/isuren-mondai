#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"
BENCH_DIR="${ISUREN_HOME}/isucon14/bench"
BENCHRUN_DIR="${BENCH_DIR}/benchrun"
FRONTEND_RELEASE_DIR="${ISUREN_HOME}/.kakomon14-frontend-release"
# 本家Ansibleの`bench_linux_amd64`はマルチアーキテクチャ配布のための命名で、AMI上で
# その場でビルドするisuren-mondaiには不要(matsuu/cloud-init-isucon方式と同じ理由)。
BENCH_BIN="${ISUREN_HOME}/bench"

# frontend_hashes.json/frontend_files.jsonはgo:embedでbenchバイナリに焼き込まれる
# (bench/benchrun/frontend_vaildator.go)。本家取り込み時点の古いハッシュのままだと
# isuren-mondai配布frontendの実際のハッシュと一致せず整合性チェックが失敗するため、
# go buildより前に80-frontend.shがダウンロード済みの最新版で上書きする。
update_benchrun_manifests() {
  local f
  for f in frontend_hashes.json frontend_files.json; do
    runuser -u "${ISUREN_USER}" -- cp "${FRONTEND_RELEASE_DIR}/${f}" "${BENCHRUN_DIR}/${f}"
  done
  log "bench/benchrun manifests: updated for build"
}

# matsuu/cloud-init-isucon方式(本家Ansible benchロールと同じく単一バイナリのみ配置)に倣う。
# 実行に必要なデータ(サンプルデータ・benchrunマニフェスト)はgo:embedで全てバイナリに
# 含まれるため、実行時にソース一式を残す必要が無い。
# runuser経由では.bashrcを経由せずmiseがPATHに乗らないため、mise本体はフルパスで呼ぶ
# (70-webapp-go.shと同じ対応)。
build_bench() {
  # shellcheck disable=SC2016 # env経由で渡した変数をsh -c内で展開させる
  runuser -u "${ISUREN_USER}" -- env BENCH_DIR="${BENCH_DIR}" MISE_BIN="${MISE_BIN}" BENCH_BIN="${BENCH_BIN}" \
    sh -c 'cd "${BENCH_DIR}" && "${MISE_BIN}" exec -- go build -o "${BENCH_BIN}" -ldflags "-s -w"'
  log "bench: built"
}

cleanup_bench_source() {
  rm -rf "${BENCH_DIR}"
  log "isucon14/bench: removed"
}

update_benchrun_manifests
build_bench
cleanup_bench_source

log "85-bench-build.sh: done"
