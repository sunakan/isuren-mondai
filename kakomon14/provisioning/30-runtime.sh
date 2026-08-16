#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

ISUREN_HOME="/home/${ISUREN_USER}"
MISE_BIN="${ISUREN_HOME}/.local/bin/mise"

# 対応: isucon14/provisioning/ansible/roles/xbuild/tasks/main.yml L1-9(git/xbuild導入部分)の代替。
# xbuildはバージョン固定インストールをするだけのツールなのでmiseに置き換える。
install_mise() {
  if [ ! -x "${MISE_BIN}" ]; then
    runuser -u "${ISUREN_USER}" -- sh -c 'curl -fsSL https://mise.run | sh'
    log "mise: installed"
  else
    log "mise: already installed"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/xbuild/tasks/main.yml L37-45(.profileへのPATH追加)相当
set_bashrc() {
  local bashrc="${ISUREN_HOME}/.bashrc"
  # shellcheck disable=SC2016 # .bashrcに文字通り書き込むため展開させない
  local line='eval "$(~/.local/bin/mise activate bash)"'
  if ! grep -qF "${line}" "${bashrc}" 2>/dev/null; then
    echo "${line}" >>"${bashrc}"
    chown "${ISUREN_USER}:${ISUREN_USER}" "${bashrc}"
    log "bashrc: added mise activate"
  else
    log "bashrc: already configured"
  fi
}

# 対応: isucon14/provisioning/ansible/roles/xbuild/tasks/main.yml L27-30(go-install 1.23.2)の代替。
# バージョンはpreflight-checkの決定(go 1.26.6)に固定。frontendはAMI上でビルドしなくなったため
# node/pnpmは不要(kakomon14/scripts/mise.toml側で管理。80-frontend.sh参照)。
# aws-bastionリポジトリのパスを直接参照せず実体をisurenのホームにコピーするのは、
# /home/ubuntu配下へのisurenからのアクセス権限に依存させないため、および将来cloud-init化した際に
# aws-bastionリポジトリ自体が存在しない前提でも動くようにするため。
set_mise_config() {
  local conf="${ISUREN_HOME}/.config/mise/config.toml"
  install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "$(dirname "${conf}")"
  install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.toml" "${conf}"
  log "mise config: ${conf} set"
}

# チェックサムを固定してサプライチェーン改ざん検知・再現性を担保する。
# linux-arm64のみを対象にしているのはこのAMIがarm64(Graviton)専用のため。
# `mise lock -g -p linux-arm64`で生成したものをgit管理し、そのまま配置する。
set_mise_lock() {
  local lock="${ISUREN_HOME}/.config/mise/mise.lock"
  install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${SCRIPT_DIR}/mise.ami.lock" "${lock}"
  log "mise lock: ${lock} set"
}

# mise install自体が内部で冪等(既にインストール済みのバージョンは再取得しない)なため、
# ここでは changed/already の判定を自前で行わずmiseに委ねる。
run_mise_install() {
  runuser -u "${ISUREN_USER}" -- "${MISE_BIN}" install
  log "mise install: done"
}

install_mise
set_bashrc
set_mise_config
set_mise_lock
run_mise_install

log "30-runtime.sh: done"
