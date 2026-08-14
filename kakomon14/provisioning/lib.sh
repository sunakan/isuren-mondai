#!/usr/bin/env bash
set -euo pipefail

# 設定値。環境変数で上書き可能にする
: "${ISUREN_USER:=isuren}"
: "${ENABLE_TLS:=false}"

log() {
  echo "[kakomon14] $*"
}

# 以下はOTel trace化(Mac側のmise-tasks/kakomon14/buildが$BUILD_LOGから事後変換)のための
# 生データ取得用。EC2側はこれらの値をlog()経由で書き出すだけで、span生成・OTLP送信は行わない。
now_ns() {
  date +%s%N
}

disk_used_bytes() {
  df -B1 / | awk 'NR==2{print $3}'
}

disk_total_bytes() {
  df -B1 / | awk 'NR==2{print $2}'
}
