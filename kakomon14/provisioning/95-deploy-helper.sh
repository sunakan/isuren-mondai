#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
DEPLOY_SCRIPT="${ISUREN_HOME}/deploy.sh"

# チューニング作業中に、コード変更→再ビルド→再起動を1コマンドで回せるようにする。
# isurenの対話シェル(.bashrcでmise activate済み)からの実行を前提にしており、
# 70-webapp-go.shのようにmise/goをフルパス指定していない。
set_deploy_script() {
  local content
  content=$(
    cat <<'EOD'
#!/usr/bin/env bash
set -euo pipefail

cd ~/webapp/go
mise exec -- go build -o isuride -ldflags "-s -w"
sudo systemctl restart isuride-go
echo "deploy.sh: isuride-go restarted"
EOD
  )
  echo "${content}" >"${DEPLOY_SCRIPT}"
  chown "${ISUREN_USER}:${ISUREN_USER}" "${DEPLOY_SCRIPT}"
  chmod 0755 "${DEPLOY_SCRIPT}"
  log "deploy.sh: ${DEPLOY_SCRIPT} set"
}

set_deploy_script

log "95-deploy-helper.sh: done"
