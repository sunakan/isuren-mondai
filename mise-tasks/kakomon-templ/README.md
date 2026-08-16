# kakomon task skeletons

このディレクトリは、新しい過去問targetへコピーしてから具体化する`mise-tasks`のsource skeletonを置く。
ここからAMI buildやGitHub Releaseを直接実行するための汎用taskではない。

mise taskとして公開するのは、安全なローカル静的検査である`kakomon-templ:check`だけとする。
`*.tmpl`はmode 0644・`#MISE`なしで保持し、miseから実行対象として発見されないようにする。
このcheckはtask skeletonに加え、`kakomon-templ/provisioning/`のrecipe templateも一括検査する。

## 使い方

1. 必要な`*.tmpl`を`mise-tasks/<canonical-slug>/<task-name>`へコピーする。
2. 冒頭のtemplate guardを削除し、`#MISE description`を追加する。
3. `__KAKOMON_SLUG__`、その他の`__...__`、`TODO`をtarget固有の根拠で置き換える。
4. source AMI、Release prefix/assets、official mirrorのURL/full SHA、static contractを固定する。
5. shell syntax、target固有validation、task discoveryを確認する。

必要のないtaskはコピーしない。たとえばofficial prebuilt frontendをそのまま使い、こちらでbuild・Release
しないtargetへ`build-frontend`や`release`を形だけ追加しない。

## skeletonの責任

| file | コピー後に保つ共通の処理形 | targetごとに決めるもの |
|---|---|---|
| `build.tmpl` | clean/pushed gate、exact input検証、一時user-data、build exit保持、host-side OTel、cleanup | source AMI、Packer変数、target-scoped `latest`/exact Release identity、provenance tag |
| `diff.tmpl` | read-only mirror identity確認、差分をtask失敗にしない境界 | official URL/full SHA、managed subpath、除外根拠 |
| `validate.tmpl` | fail-fastなstatic contract入口 | source、domain、service、frontend、Packer等の検査内容 |
| `build-frontend.tmpl` | target-owned build entrypointの薄いwrapper | package manager、asset、manifest、checksum |
| `release.tmpl` | exact tag、clean/pushed gate、token隔離 | tag prefix、upload asset一覧 |
| `lock-ami-tools.tmpl` | host状態を汚さない隔離lock更新 | config path、固定したtool image、platform |
| `test-go.tmpl` | target-owned Go検査への薄い入口 | source/cache/frontend等のtest fixture |
| `verify-official-data.tmpl` | official identityとmanifestのfail-fast検証 | mirror、full SHA、file manifest |
| `audit-upstream-update.tmpl` | candidate full SHAを受け取るread-only差分監査 | official取得方法、managed path、除外根拠 |
| `prepare-artifacts.tmpl` | optional artifact準備への薄い入口 | prebuilt/download/build境界と出力先 |
| `verify-artifacts.tmpl` | prepared artifactのlocal検証入口 | manifest、digest、license、provenance |
| `refresh-upstream.tmpl` | candidateを明示したmanaged source更新骨格 | URL、full SHA、rsync対象、NOTICE除外規則 |
| `prune-ami.tmpl` | target-scoped列挙、対話確認、AMI/snapshot整理骨格 | 保持数、region、name/tag selector |
| `publish-latest-ami.tmpl` | target-scoped最新AMIの対話確認、snapshot→AMI公開順 | region、selector、公開前identity gate |

後半8つは既存targetの独自task familyを落とさないためのoptional skeletonであり、新しいtargetへ一律追加しない。
targetに不要ならファイルごとコピーせず、独自性が残る場合はコピー先の`#MISE description`へ
`(kakomonN独自: ...)`を明記する。

`kakomon-templ:check`はネットワーク、Docker、AWS、GitHubを使わず、templateの存在・mode・placeholder・
禁止されたhard-coded target・shell構文・ShellCheck・shfmtだけを検査する。
