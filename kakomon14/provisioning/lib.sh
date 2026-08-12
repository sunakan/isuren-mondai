#!/usr/bin/env bash
set -euo pipefail

# 設定値。環境変数で上書き可能にする
: "${ISUREN_USER:=isuren}"
: "${ENABLE_TLS:=false}"

log() {
  echo "[kakomon14] $*"
}
