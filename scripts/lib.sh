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

# gh release createは--targetを指定しても、タグが既に存在する場合は無視して既存タグを
# そのまま使う(GitHub API仕様)。Releaseだけ削除してタグを消し忘れると、新しい成果物なのに
# タグは古いコミットを指したまま、という食い違いがエラーなく発生するため事前に検知する。
require_tag_not_taken() {
  local tag="$1"
  if git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
    echo "エラー: タグ ${tag} は既にリモートに存在します。" >&2
    echo "  (gh release createは既存タグの場合--targetを無視するため、そのまま実行すると" >&2
    echo "   成果物だけ新しくなりタグは古いコミットを指したままになります)" >&2
    echo "  別のタグ名を使うか、以下でタグ自体を削除してから実行してください。" >&2
    echo "    git push origin :refs/tags/${tag}" >&2
    exit 1
  fi
}
