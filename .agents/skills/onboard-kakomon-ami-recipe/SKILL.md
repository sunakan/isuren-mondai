---
name: onboard-kakomon-ami-recipe
description: isuren-mondaiへISUCON過去問のGo版AMI recipeを追加・移植・監査するときに、official provenance、サービス、runtime、frontend、benchmark、topology、reset/rebootを調べ、過去問固有のcloud-init・all.sh・Goss・mise・PackerとOrb/AWSの独立gateへ段階化する。新しいedition/Qualify/Finalのaudit、実装計画、recipe実装、検証計画または検証開始前に使う。既定はaudit-onlyとし、既存AMIの単純なbuild・削除や一般的なAWS/Orb操作だけには使わない。
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
- Orb/AWSなどの外部状態を調査・操作する前に、リポジトリ指定のexternal-operation preflightを適用し、人間の承認、費用上限、TTL、resource namespace、cleanup責任を確定する。
- 承認のない外部操作、対象不明なcleanup、秘密情報の表示を行わない。

## 共通停止条件

Ubuntu 26.04 arm64と、競技用domainが存在する場合の`isuren.internal`写像は採用済み共通入力である。古いplanに値がないだけで`decision-required`へ戻さず、互換性を`evidence-missing`として扱う。

次のいずれかなら、その場で停止し、欠けている証拠または判断を報告する。

- editionとQualify/Final等のvariantが一意でない。
- official URLとexact commit/tagが固定されていない。
- `tmp/all-kakomon`等のcacheをbuild sourceとして使おうとしている。
- managed upstreamと、公式から直接取得する画像・静的asset・`sql/`・初期データの境界、subpath、license、exact commitが固定されていない。
- architecture、provider、compact/canonical topologyの対応が不明である。
- Ubuntu 26.04 arm64で必要componentが成立せず、amd64・旧Ubuntuへのfallbackを人間判断なしで進めようとしている。
- upstreamに競技用domainがあるのに`isuren.internal`へのtarget限定写像、TLS SAN、自己署名fixtureまたは本物の秘密の境界が固定されていない。
- benchmarkの実行方法、target、result/failure契約が分からない。
- frontend buildが必要なのに、生成物、package manager、lockfile、build command、配置先のいずれかが不明である。
- mutableな`latest`、floating tag、`most_recent`、幅付きversion制約をartifact入力のまま使う。
- 未統合KAKOMON14や別worktreeの値に依存する。
- 外部操作のpreflight、承認、費用・TTL・cleanup境界が欠けている。

## 完了報告

[入力・報告契約](references/intake-and-report.md)の出力形式を使う。実施していないgateをGreenと書かず、変更path、検証、未決判断、停止条件、次に安全に進めるモードを明示する。
