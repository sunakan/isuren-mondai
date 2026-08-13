#!/usr/bin/env bash
# 複数のリリース関連スクリプト(github-release.sh、kakomon14/scripts/build-frontend-release.sh等)
# で共有するガードレール処理。

require_clean_worktree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "エラー: 未コミットの変更があります。コミットしてから実行してください。" >&2
    git status --short >&2
    exit 1
  fi
}

# gh release create --target実行時にリモートにコミットがないと422/500等の分かりにくいエラーに
# なるため、事前にgh apiで存在確認する。--silentでレスポンス本体を出力しない(認証情報混入を避ける)。
require_pushed_commit() {
  local commit="$1"
  if ! gh api "repos/{owner}/{repo}/commits/${commit}" --silent 2>/dev/null; then
    echo "エラー: コミット ${commit} がリモートに見当たりません。git pushを忘れていませんか?" >&2
    exit 1
  fi
}
