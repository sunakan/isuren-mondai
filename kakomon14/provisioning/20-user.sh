#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# 対応: isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L2-8
create_group() {
  if ! getent group "${ISUREN_USER}" >/dev/null 2>&1; then
    groupadd -g 1100 "${ISUREN_USER}"
    log "group: created ${ISUREN_USER}(gid=1100)"
  else
    log "group: already exists"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L10-20
# password(平文isucon)設定は未対応。bastionはSSHキー/sudo経由の運用でログインパスワード認証を使わないため。
create_user() {
  if ! id -u "${ISUREN_USER}" >/dev/null 2>&1; then
    useradd -u 1100 -g "${ISUREN_USER}" -d "/home/${ISUREN_USER}" -m -s /bin/bash "${ISUREN_USER}"
    log "user: created ${ISUREN_USER}(uid=1100)"
  else
    log "user: already exists"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L22-26
chmod_home() {
  local home="/home/${ISUREN_USER}"
  if [ "$(stat -c %a "${home}")" != "755" ]; then
    chmod 0755 "${home}"
    log "home: chmod 755 ${home}"
  else
    log "home: already 755"
  fi
}

# 未対応(意図的に除外): isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L28-41
# .sshディレクトリ作成・authorized_keys削除。bastionのユーザーアクセスモデル(ubuntu/user101経由)とは別物のため。

# 対応: isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L43-50
set_sudoers() {
  local conf="/etc/sudoers.d/99-${ISUREN_USER}-user"
  local content="${ISUREN_USER}  ALL=(ALL) NOPASSWD:ALL"
  if [ ! -f "${conf}" ] || [ "$(cat "${conf}")" != "${content}" ]; then
    local tmp
    tmp="$(mktemp)"
    echo "${content}" >"${tmp}"
    visudo -cf "${tmp}"
    install -m 0440 -o root -g root "${tmp}" "${conf}"
    rm -f "${tmp}"
    log "sudoers: changed ${conf}"
  else
    log "sudoers: already up to date"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/isucon-user/tasks/main.yml L52-59, templates/env.sh
set_env_sh() {
  local dest="/home/${ISUREN_USER}/env.sh"
  local content
  content=$(
    cat <<'EOD'
ISUCON_DB_HOST="127.0.0.1"
ISUCON_DB_PORT="3306"
ISUCON_DB_USER="isucon"
ISUCON_DB_PASSWORD="isucon"
ISUCON_DB_NAME="isuride"

# マッチング間隔（秒）
ISUCON_MATCHING_INTERVAL=0.5
EOD
  )
  if [ ! -f "${dest}" ] || [ "$(cat "${dest}")" != "${content}" ]; then
    echo "${content}" >"${dest}"
    chown "${ISUREN_USER}:${ISUREN_USER}" "${dest}"
    chmod 0755 "${dest}"
    log "env.sh: changed ${dest}"
  else
    log "env.sh: already up to date"
  fi
}

create_group
create_user
chmod_home
set_sudoers
set_env_sh

log "20-user.sh: done"
