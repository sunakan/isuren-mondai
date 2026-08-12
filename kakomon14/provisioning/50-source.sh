#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

# コミットハッシュは/Users/user01/works/github.com/isucon/isucon14(AI参照用ローカルコピー)の
# HEADに合わせて固定している。isucon14公式リポジトリのmainブランチ、2024-12-13時点。
: "${ISUCON14_REPO_URL:=https://github.com/isucon/isucon14.git}"
: "${ISUCON14_COMMIT:=53f8b627e040c30ebec600457c6c97da008b84b0}"

ISUREN_HOME="/home/${ISUREN_USER}"
ISUCON14_DIR="${ISUREN_HOME}/isucon14"
WEBAPP_LINK="${ISUREN_HOME}/webapp"

# 公式のtarball転送方式(webapp.tar.gz)ではなくgit cloneで完結させる。
# isurenユーザーでcloneするため、所有者は自然にisurenになる。
clone_isucon14() {
  if [ ! -d "${ISUCON14_DIR}/.git" ]; then
    runuser -u "${ISUREN_USER}" -- git clone "${ISUCON14_REPO_URL}" "${ISUCON14_DIR}"
    log "isucon14: cloned"
  else
    runuser -u "${ISUREN_USER}" -- git -C "${ISUCON14_DIR}" fetch --quiet
    log "isucon14: fetched"
  fi

  local current_commit
  current_commit="$(runuser -u "${ISUREN_USER}" -- git -C "${ISUCON14_DIR}" rev-parse HEAD)"
  if [ "${current_commit}" != "${ISUCON14_COMMIT}" ]; then
    runuser -u "${ISUREN_USER}" -- git -C "${ISUCON14_DIR}" checkout --quiet "${ISUCON14_COMMIT}"
    log "isucon14: checked out ${ISUCON14_COMMIT}"
  else
    log "isucon14: already at ${ISUCON14_COMMIT}"
  fi
}

# 公式のwebapp.tar.gz展開後のレイアウト(/home/isucon/webapp直下にgo/sqlが並ぶ)を再現する。
# rsyncコピーではなくシンボリックリンクにしているのは、frontend-buildタスクでwebapp/public配下に
# ビルド成果物を書き込む際、cloneしたツリーにそのまま反映されるようにするため
# (rsyncコピーだと別途同期し直す手間が発生する)。
# シンボリックリンク自体の所有者はchownしない。Linuxではシンボリックリンク自体の
# パーミッション/所有者はカーネルからほぼ無視され、実際のアクセス制御はリンク先の実体
# (isuren所有のisucon14/webapp)に対して行われるため、機能的に不要。
link_webapp() {
  if [ -L "${WEBAPP_LINK}" ] && [ "$(readlink "${WEBAPP_LINK}")" = "${ISUCON14_DIR}/webapp" ]; then
    log "webapp: symlink already up to date"
  else
    ln -sfn "${ISUCON14_DIR}/webapp" "${WEBAPP_LINK}"
    log "webapp: symlink created"
  fi
}

clone_isucon14
link_webapp

log "50-source.sh: done"
