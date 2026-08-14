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
