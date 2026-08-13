#!/usr/bin/env bash
set -euo pipefail

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

PREFIX="${TAG%%v*}v"
PREV_TAG="$(gh release list --limit 1000 --json tagName --jq '.[].tagName' \
  | grep "^${PREFIX}" | head -n1 || true)"

NOTES_ARGS=(--generate-notes)
if [ -n "${PREV_TAG}" ] && [ "${PREV_TAG}" != "${TAG}" ]; then
  NOTES_ARGS+=(--notes-start-tag "${PREV_TAG}")
fi

# --targetを指定しないとリモートのデフォルトブランチ最新コミットが使われ、ビルド元と
# ズレうる。ローカルHEADを明示することで、未pushなら「コミットが見つからない」エラーで
# 気づける(誤ったコミットにタグが付くより安全)。
gh release create "${TAG}" "$@" --title "${TAG}" --target "$(git rev-parse HEAD)" "${NOTES_ARGS[@]}"
