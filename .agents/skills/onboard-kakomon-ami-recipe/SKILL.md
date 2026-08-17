---
name: onboard-kakomon-ami-recipe
description: isuren-mondaiへISUCON過去問のGo版AMI recipeを追加・移植・監査するときに、official provenance、本家filesystem構成、サービス、runtime/mise、frontend Release、benchmark、topology、seal/reset/rebootを調べ、過去問固有のcloud-init・all.sh・Goss・PackerとOrb/AWSの独立gateへ段階化する。既存recipe間の共通責務について、別targetのファイルを共有せず処理形・コメント・build host/AMI観測境界を揃える作業や、kakomon-templからtarget-owned skeletonを作るときにも使う。新しいedition/Qualify/Finalのaudit、実装計画、recipe実装、fresh VM/EC2検証計画または検証開始前に使う。既定はaudit-onlyとし、既存AMIの単純なbuild・削除や一般的なAWS/Orb操作だけには使わない。
---

# 過去問AMI recipeをonboardingする

## 最初に境界を固定する

1. リポジトリの`AGENTS.md`、現在のGit/worktree状態、長期戦略の正本、統合済みKAKOMON14 recipeを読む。
2. 同時作業中のworktree・branch・VM・生成物を所有外として分離し、未統合差分を仕様や証拠にしない。
3. 依頼でモードが明示されなければ`audit`を選ぶ。モードを自動昇格させない。
4. [入力・報告契約](references/intake-and-report.md)を読み、必須入力、不明点、証拠の強さを整理する。

## モードを選ぶ

### `audit`（既定、read-only）

- ファイル変更、依存導入、VM作成、AMI build、AWS/Orb/GitHub操作をしない。
- official upstream、ローカルaudit clone、参考実装、統合済みKAKOMON14を証拠源ごとに分ける。
- official repositoryを再clone、fetch、pullしない。implement worktreeではmain checkoutのsource cacheから作成直後に複製した`tmp/all-kakomon/<official-repo-name>`をread-onlyで使い、identity不一致ならcacheを変更せず停止する。worktreeを作らないauditはmain source cacheを直接使ってよい。
- [auditチェックリスト](references/audit-checklist.md)を最後まで実施する。
- 不明点を推測で埋めず、`decision-required`または`evidence-missing`として返す。

### `plan`

- 完了したauditを入力に、edition/variant固有の作業、Red/Green、未決判断、停止条件、gate、cleanupを計画する。
- [recipe実装契約](references/recipe-contract.md)と[検証gate](references/verification-gates.md)を読む。
- 未決判断を勝手に選ばず、計画をdraftのまま止める。
- 最初の3問程度は独立recipeとし、共通化は実測差分を得た後に別判断とする。

### `implement`

- 明示的に承認されたplan、変更許可path、専用worktree、受け入れ条件が揃ってからローカル実装する。
- [実装時によくある落とし穴](references/implementation-pitfalls.md)を先に読む。Goのビルド対象、GitHub Release取得、Gossのport/file検証等、過去targetで実際に踏んだ問題を再現しない。
- target専用の`kakomon*/**`、`upstream/<official-repo-name>/**`、`mise-tasks/<canonical-slug>/**`だけを変更し、managed source、cloud-init、`all.sh`、edition固有step、Goss、mise、Packerを[recipe実装契約](references/recipe-contract.md)どおり分担させる。
- template保守が明示された場合だけ`kakomon-templ/**`・`mise-tasks/kakomon-templ/**`を変更許可pathへ加える。target実装のついでにtemplateへ逆流させず、template変更とtarget変更を別の検証・commit単位にする。
- Red/Green、関連lint/test、自己レビューを行う。未決判断や停止条件に到達したら変更を広げない。
- `implement`は外部環境操作を許可しない。外部検証は別の`verify`承認を要求する。

## copy-oriented templateを使う

新規targetのplan/implementまたは既存recipeの整形では、次の順でtemplateを使う。

1. `kakomon-templ/README.md`、`kakomon-templ/provisioning/README.md`、`mise-tasks/kakomon-templ/README.md`を読む。
2. `mise run kakomon-templ:check`を実行し、非実行mode、placeholder、shell構文、ShellCheck、shfmtがGreenなcopy sourceだけを使う。
3. targetのaudit証拠に対応する`.tmpl`だけをコピーする。不要なMySQL/nginx extensionやfrontend/AWS/upstream taskを対称性のために追加せず、ファイルごと省略する。
4. コピー先から`.tmpl`を外し、`__KAKOMON_SLUG__`・他の`__...__`・`TODO`・fail-closed guardをすべてtarget固有の根拠で置換する。mise taskには`#MISE description`を付け、独自taskなら`kakomonN独自:`と理由を明記し、実行modeとtask discoveryを確認する。
5. provisioningの`all.sh`へ実在stepだけを明示順で列挙し、optional extensionを存在確認で暗黙実行しない。target-owned source、service、domain、frontend、benchmark、Goss、seal契約を追加する。
6. コピー後のfileをtarget自身でGit管理し、cloud-init、Packer、runtimeから`kakomon-templ/**`を直接source、symlink、参照しない。
7. templateとtarget証拠が衝突したらtarget証拠を優先し、意図的な差分をREADME/NOTICE、description、検証へ残す。templateを正解としてofficial契約を上書きしない。

template更新を既存targetへ自動伝播させない。共通責務の改善を見つけた場合はtemplate単体を
`kakomon-templ:check`で検証・commitし、各targetへの反映はpaired diffとtarget gateを持つ別作業にする。

## 既存recipe間の共通処理を揃える

既存targetの比較で「問題固有差分ではないのに処理形が違う」箇所を見つけたら、次の方針で差分を減らす。

- 同じscript fileを共有せず、`kakomon13/`・`kakomon14/`等のtarget-owned fileをそれぞれ保つ。共通化するのは責務の境界、処理順、関数分割、入力検証、失敗処理、ログ形式、コメント構造とする。
- まず対応する`kakomon-templ/provisioning/*.tmpl`または`mise-tasks/kakomon-templ/*.tmpl`を比較基準にする。templateにない問題固有処理はtarget-owned step/taskへ残し、templateへedition分岐を追加して差分を隠さない。
- 統合済みKAKOMON14の`mise kakomon14:build`をbuild taskの処理形の参照にする。K13へ移す場合も、target固有のsource AMI、frontend Release、公式source、step列、service名、Goss対象は置き換えず、taskの外枠だけを揃える。
- `mise-tasks/kakomon13/**`・`mise-tasks/kakomon14/**`をtask名で対応付け、既存の`kakomonN:xxx`を一つずつ比較する。同名taskはK13/K14で`#MISE description`の文型も揃え、本文は同じ責務の順序・検証・失敗処理・コメント構造へ寄せる。片方にしかないtaskは無理に追加せず、descriptionへ`kakomonN独自:`と独自である理由を明記する。
- taskの有無は対称性ではなくfrontend/sourceの配布方式とtaskの責務で決める。official prebuilt frontendをAMI内で取得するtargetへ、実際にはbuildしない`build-frontend`やRelease upload taskを形だけ追加しない。必要ならlocal inspection用のprepare/verify taskだけを独自taskとして残し、normal buildの入力にはしない。
- `diff` taskはworktree-local official mirrorとmanaged sourceのread-only比較に限定し、exact candidate SHAをnetwork取得するupstream audit/refresh taskとは分離する。後者はexternalであることと引数のidentity契約をdescriptionへ明記し、local diffに外部fetchを混ぜない。
- 変更は一つのtask名（共通taskならK13/K14のペア）ごとに閉じ、依頼にcommitが含まれる場合はその単位で検証して小さくcommitする。stage対象はそのtaskと必要なtarget-owned fileだけに限定し、共通化のために無関係なtaskや共有scriptへ変更を広げない。
- build host側では、exact inputを検証し、cloud-init用の小さな一時`user-data`をローカル生成してPackerの`user_data_file`へ渡す。生成処理自体にGitHub/AWS取得を入れず、終了時にtrapで一時ファイルを削除する。Packerがtrackedな`user-data.yaml`や旧runnerを直接参照しないことも確認する。`packer init`、AWS API、build後のOTel送信は別のhost-side処理として記録する。
- AMI/EC2側では、User Dataから公式source・package・Release等を取得してよい。`all.sh`は`traceparent`・時刻・ディスク量・step結果などのraw telemetryだけをログへ出し、API keyやOTLP送信をAMIへ持ち込まない。Packer完了後にhost-side taskがbuild logからroot/child spanを作り、元のPacker終了コードを返す。
- `all.sh`のraw telemetry prefix/marker、PackerのGoss/span抽出範囲、host-side OTel parserは一つのlog contractとして扱う。ログ文言やtarget prefixを変更したら、抽出範囲とparserのfixture/静的検証も同じtask単位で更新する。
- コメントも共通責務の境界、実行順、失敗時の挙動、秘密・生成物の境界を同じ型で書く。ただしofficial provenance、hostname、service、frontend、benchmark等のtarget固有の根拠は、差分を減らすためだけに削除しない。
- frontend Release selectorはtarget prefix単位で解決する。KAKOMON13とKAKOMON14はそれぞれ`kakomon13-frontend-*`・`kakomon14-frontend-*`だけを候補にし、version番号やtag名を過去問間で揃える必要はない。各targetに一つ以上のtarget固有Releaseがあればよく、別targetのReleaseを代用しない。
- `latest`を採用するtargetは、AMI側でtarget prefixから具体的なtagを解決し、Releaseのasset/checksumまたはpublished digestで検証してから配置する。解決後のtag・artifact digestをprovenanceとAMI/build-hostの観測境界へ記録し、repository全体の`/releases/latest`や記録なしの可変downloadは使わない。
- taskごとに変更前後のpaired task diff、descriptionの一致、同じrelative pathの一覧、完全一致ファイル数、残したtarget固有差分、差分行数を記録する。差分が減ったことと、target固有契約を壊していないことを別々に確認する。
- Go test等のlocal validationがhost cacheの権限で失敗した場合は、コード失敗と断定せず、task専用の一時`GOCACHE`で再実行して結果を分けて記録する。

### `verify`

- [検証gate](references/verification-gates.md)を読み、依頼されたgateだけを実施する。
- Goss failureは即target/gate固有バグと決めつけない。[実装時によくある落とし穴](references/implementation-pitfalls.md)のGoss port/fileチェックの既知の誤検知パターンに該当しないか、`ss -ltn`等で実際の状態を確認してから対応を決める。
- 一つの成功を別gateの成功へ読み替えない。gateごとにartifact identity、recipe digest、環境、証拠、cleanupを記録する。
- external frontendを使う場合は検証対象recipe commitがremoteから取得可能で、target固有Release asset/digestが存在することをread-onlyで確認し、不足時はEC2/VMへ変更を加える前に停止する。`latest` selectorの場合はtarget prefixでの解決結果と実asset digestを確認する。local mainとremote mainの完全一致は要求しない。
- Orb/AWSなどの外部状態を調査・操作する前に、リポジトリ指定のexternal-operation preflightを適用し、人間の承認、費用上限、TTL、resource namespace、cleanup責任を確定する。AWS regionは東京`ap-northeast-1`へ固定する。
- 承認のない外部操作、対象不明なcleanup、秘密情報の表示を行わない。

## 共通停止条件

Ubuntu 26.04 arm64、AWS region `ap-northeast-1`、競技用domainが存在する場合の`isuren.internal`写像は採用済み共通入力である。古いplanに値がないだけで`decision-required`へ戻さず、互換性を`evidence-missing`として扱う。

次のいずれかなら、その場で停止し、欠けている証拠または判断を報告する。

- editionとQualify/Final等のvariantが一意でない。
- official URLとexact commit/tagが固定されていない。
- implement worktree作成直後にmain source cacheを同名のworktree-local `tmp/all-kakomon`へclone全体で`rsync -a`していない、bootstrapで`.git/`を落としている、またはlocal mirrorがtop-level Gitでignoreされていない。
- main source cacheとworktree-local mirrorのorigin URL、full HEAD、clean状態を確認せずimportしようとしている、または不一致cacheをsession自身でfetch / checkout / resetしようとしている。
- `tmp/all-kakomon`を変更許可path、stage、commit、merge payloadへ含めようとしている。worktreeに残る一時cache自体はmain統合のblockerにしない。
- clean clone、cloud-init、AMI buildが`tmp/all-kakomon`の存在を前提にしている。保守codeはcommit済みmanaged source、非commit dataは公式exact commitからAMI内で直接取得してmanifest/checksum検証するか、外部の固定bundleへ変換する。
- managed upstreamと、画像・静的asset・`sql/`・初期データ等の非commit dataの境界、subpath、license、exact commit、AMI内直接取得または外部bundle、manifest/checksumが固定されていない。
- architecture、provider、compact/canonical topologyの対応が不明である。
- Ubuntu 26.04 arm64で必要componentが成立せず、amd64・旧Ubuntuへのfallbackを人間判断なしで進めようとしている。
- profile、Packer、base AMI、build、fresh boot、product検証、cleanupのAWS regionが`ap-northeast-1`へ固定されていない、暗黙のdefault regionに依存している、または別regionへfallbackしようとしている。
- upstreamに競技用domainがあるのに`isuren.internal`へのtarget限定写像、TLS SAN、自己署名fixtureまたは本物の秘密の境界が固定されていない。
- benchmarkの実行方法、target、result/failure契約が分からない。
- frontendをこちらでbuildするのか、official prebuiltをbyte-for-byte使うのかが未分類である。buildが必要なら生成物、package manager、lockfile、build command、配置先のいずれかが不明、prebuiltならexact commit/tree/file manifest/SHA-256/licenseまたはruntime外部依存の調査が不足している。
- external frontend配布なのに、target固有workflow、remote exact tag、期待asset、published SHA-256のいずれかがなく、外部verifyを開始しようとしている。
- target prefix・resolved tag・asset digestの記録/検証がないmutableな`latest`、floating tag、`most_recent`、幅付きversion制約をartifact入力のまま使う。target-scoped `latest` selector自体は、解決後のidentityをprovenance/AMI tagへ残す場合に限り採用できる。
- 未統合KAKOMON14や別worktreeの値に依存する。
- 外部操作のpreflight、承認、費用・TTL・cleanup境界が欠けている。

## 完了報告

[入力・報告契約](references/intake-and-report.md)の出力形式を使う。実施していないgateをGreenと書かず、変更path、検証、未決判断、停止条件、次に安全に進めるモードを明示する。
