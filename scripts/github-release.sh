#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOS'
Usage: scripts/github-release.sh <tag> <artifact-path>...

  <tag>            リリースタグ(例: kakomon14-v1.0.0)
  <artifact-path>  Releaseに添付するファイル(複数指定可)

過去問ごとに再利用できるよう、タグ以外はハードコードしていない。
リリースノートは同じ過去問(タグの"<name>-v"部分が一致するもの)の前回リリースとの
差分のみを対象にする。他の過去問(例: kakomon13)の履歴が紛れ込まないようにするため。
EOS
}

if [ "$#" -lt 2 ]; then
  usage >&2
  exit 1
fi

TAG="$1"
shift

COMMIT="$(git rev-parse HEAD)"
require_clean_worktree
require_pushed_commit "${COMMIT}"
require_tag_not_taken "${TAG}"

PREFIX="${TAG%%v*}v"
PREV_TAG="$(gh release list --limit 1000 --json tagName --jq '.[].tagName' \
  | grep "^${PREFIX}" | head -n1 || true)"

NOTES_ARGS=(--generate-notes)
if [ -n "${PREV_TAG}" ] && [ "${PREV_TAG}" != "${TAG}" ]; then
  NOTES_ARGS+=(--notes-start-tag "${PREV_TAG}")
fi

# --targetを指定しないとリモートのデフォルトブランチ最新コミットが使われ、ビルド元と
# ズレうる。ローカルHEADを明示することで、事故で誤ったコミットにタグが付くのを防ぐ。
gh release create "${TAG}" "$@" --title "${TAG}" --target "${COMMIT}" "${NOTES_ARGS[@]}"
