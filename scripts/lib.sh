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
# そのまま使う(GitHub API仕様)。タグがHEAD以外のコミットを指したまま成果物だけ新しくなる
# 食い違いを事前に検知する。タグpushがCIのトリガーになる運用(GitHub Actions)では
# 「実行時点でタグがHEADを指して既に存在する」のが正常系なので、その場合は許容する。
require_tag_absent_or_at_head() {
  local tag="$1"
  local head_commit
  head_commit="$(git rev-parse HEAD)"
  # annotated tagは`refs/tags/X`がtagオブジェクトを指すため、コミットへの解決には
  # peeled ref(`refs/tags/X^{}`)が要る。lightweight tagにはpeeled refが存在しないため、
  # 両方問い合わせて存在する方(peeled優先)を使う。
  local refs
  refs="$(git ls-remote origin "refs/tags/${tag}" "refs/tags/${tag}^{}" 2>/dev/null)"
  if [ -z "${refs}" ]; then
    return 0
  fi
  local tag_commit
  tag_commit="$(printf '%s\n' "${refs}" | awk -v ref="refs/tags/${tag}^{}" '$2 == ref {print $1}')"
  if [ -z "${tag_commit}" ]; then
    tag_commit="$(printf '%s\n' "${refs}" | awk -v ref="refs/tags/${tag}" '$2 == ref {print $1}')"
  fi
  if [ "${tag_commit}" = "${head_commit}" ]; then
    return 0
  fi
  echo "エラー: タグ ${tag} は既にリモートに存在し、HEAD(${head_commit})以外を指しています。" >&2
  echo "  (gh release createは既存タグの場合--targetを無視するため、そのまま実行すると" >&2
  echo "   成果物だけ新しくなりタグは古いコミットを指したままになります)" >&2
  echo "  別のタグ名を使うか、以下でタグ自体を削除してから実行してください。" >&2
  echo "    git push origin :refs/tags/${tag}" >&2
  exit 1
}
