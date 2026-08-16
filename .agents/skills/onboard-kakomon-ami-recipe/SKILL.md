---
name: onboard-kakomon-ami-recipe
description: isuren-mondaiへISUCON過去問のGo版AMI recipeを追加・移植・監査するときに、official provenance、本家filesystem構成、サービス、runtime/mise、frontend Release、benchmark、topology、seal/reset/rebootを調べ、過去問固有のcloud-init・all.sh・Goss・PackerとOrb/AWSの独立gateへ段階化する。新しいedition/Qualify/Finalのaudit、実装計画、recipe実装、fresh VM/EC2検証計画または検証開始前に使う。既定はaudit-onlyとし、既存AMIの単純なbuild・削除や一般的なAWS/Orb操作だけには使わない。
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
- target専用の`kakomon*/**`、`upstream/<official-repo-name>/**`、`mise-tasks/<canonical-slug>/**`だけを変更し、managed source、cloud-init、`all.sh`、edition固有step、Goss、mise、Packerを[recipe実装契約](references/recipe-contract.md)どおり分担させる。
- Red/Green、関連lint/test、自己レビューを行う。未決判断や停止条件に到達したら変更を広げない。
- `implement`は外部環境操作を許可しない。外部検証は別の`verify`承認を要求する。

### `verify`

- [検証gate](references/verification-gates.md)を読み、依頼されたgateだけを実施する。
- 一つの成功を別gateの成功へ読み替えない。gateごとにartifact identity、recipe digest、環境、証拠、cleanupを記録する。
- external frontendを使う場合は検証対象recipe commitがremoteから取得可能で、target固有Release asset/digestが存在することをread-onlyで確認し、不足時はEC2/VMへ変更を加える前に停止する。local mainとremote mainの完全一致は要求しない。
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
- mutableな`latest`、floating tag、`most_recent`、幅付きversion制約をartifact入力のまま使う。
- 未統合KAKOMON14や別worktreeの値に依存する。
- 外部操作のpreflight、承認、費用・TTL・cleanup境界が欠けている。

## 完了報告

[入力・報告契約](references/intake-and-report.md)の出力形式を使う。実施していないgateをGreenと書かず、変更path、検証、未決判断、停止条件、次に安全に進めるモードを明示する。
