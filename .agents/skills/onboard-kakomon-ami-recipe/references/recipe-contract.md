# recipe実装契約

## 過去問固有recipeを保つ

最初の3問程度はedition/variantごとに独立した`cloud-init`、`all.sh`、step、Goss、mise、Packer、検証taskを持たせる。統合済みKAKOMON14から借りるのはディレクトリ構成、stepの考え方、入力manifest、artifact identity、ログ形式などであり、MySQL/nginx/runtime/topologyを巨大な共通分岐へまとめない。

実体のない互換stepを作らない。`all.sh`を実行順の正本とし、step名は対象serviceの責任を表す。3問の実測差分が揃ったら共通化候補を必ずレビューするが、共通化自体は必須としない。

## file別の責任

| file | 責任 | 持たせない責任 |
|---|---|---|
| `cloud-init` | fixed recipe revisionを取得し、同一の`all.sh`を無人実行し、完走を伝える | edition構築ロジックの複製、秘密の埋め込み、成功の推測 |
| `all.sh` | edition固有stepの順序、fail-fast、構造化log、完走marker | provider分岐、未宣言の手動修正、検証失敗の握りつぶし |
| step scripts | package、user、source、DB、Application、frontend、benchmark、service等の状態作成 | 他editionの巨大条件分岐、Gossによる状態変更 |
| `goss.yaml` | file/package/user/service/port/commandとprovenance markerの観測 | 状態作成、multi-node benchmark、reset/reboot、製品E2Eの代替 |
| `mise.toml`/lock | exact runtime/tool version、architecture別URL/checksum、再現可能なinstall | `latest`、rangeだけのversion、未lock download |
| Packer | provider-native base、architecture、disk/network/build adapter、cloud-init待機、marker/Goss確認、tag、seal、cleanup | recipe本体の再実装、Orb成功の流用、製品E2E |
| `upstream/<official-repo-name>` | 公式baselineから選んだApplication、benchmark、frontend等のこちらで保守するコード、LICENSE、NOTICE | 編集しない画像・静的asset、`sql/`、初期データ、由来不明binary |
| `mise-tasks/<canonical-slug>` | target固有のimport/diff、lock、static validation、build/release adapter | 他targetの更新、保守差分の無警告上書き、承認なしの外部gate |

Packer plugin、base image、OS repository、package inventory、frontend artifact、source revision、recipe revisionを入力manifestへ束縛する。`most_recent`等で候補を探す調査段階と、artifact buildへ渡すexact IDを分ける。

## sourceとartifact identity

- `upstream/<official-repo-name>/**`を、official URLとexact baseline commit/tagから選択したこちらのmanaged source treeとする。Application、benchmark、frontend等を必要に応じてlocal更新し、公式baseline、取り込み・除外範囲、local差分を`NOTICE.md`へ記録する。
- managed sourceのbuild identityをisuren-mondaiのexact recipe commit/pathへ固定し、その起点であるofficial URL・baseline commit・license・local差分も追跡する。公式treeと同一だと偽らない。
- 編集しない画像・静的asset、`sql/`、初期データは原則managed sourceへcommitせず、frontend artifact buildまたはprovisioningが消費前に公式repositoryのexact commitからtarget固有subpathを直接取得する。取得元LICENSEを含め、managed sourceと実ファイルで統合し、取得用checkoutを削除する。
- `upstream/isucon14/NOTICE.md`と`kakomon14/provisioning/50-source.sh`を構造の参考にする。画像・dataの配置はeditionごとに異なるため、除外pathをコピーせずofficial treeから決める。
- ローカルcloneや`tmp/all-kakomon`をbuild sourceにしない。
- 参考実装からcopyする場合も、対象editionのofficial provenanceとlicenseを追跡する。
- recipe commit/digest、upstream revision、base image ID、architecture、runtime lock、frontend identity/checksumをartifact tag/manifestと証拠へ残す。
- Orb GoldenとAWS AMIを相互変換せず、同じfixed recipeからprovider-native artifactを別々に作る。

target固有のimport/refresh taskは初回取り込みと公式差分監査を支援してよいが、managed sourceのlocal変更を`rsync --delete`等で黙って上書きしない。更新前後のofficial identityとdiffを示し、意図的な更新として扱う。

## platformとhostname

- 新規targetはUbuntu 26.04 arm64を採用値とし、Application、benchmark、OS package、DB/proxy/DNS等をcomponent別にRed/Greenする。非互換時にamd64や旧Ubuntuへ自動fallbackせず、失敗証拠を残して停止する。
- base imageの検索はaudit/preflightに限定し、Packer build入力にはUbuntu 26.04 arm64のexact image IDを渡す。`most_recent`、architecture違い、旧OSをartifact identityへ残さない。
- upstreamの`isucon.net`、`*.isucon.dev`、`*.isucon.local`等を監査し、競技用domainがあれば元のsubdomain構造を保って`isuren.internal`配下へ写像する。DNS/hosts、proxy、TLS SAN、cookie/domain、Application、benchmark、healthcheckを同じhostname contractにする。
- domain変更は対象限定patchとして適用元/適用後treeとdigestを記録し、repository全体の一括置換、旧hostname alias/fallback、published ProblemVersion/manifestの同一identity上書きを禁止する。
- 個人練習用の自己署名server key/certificateは、公開テストfixtureと明記し、file mode、fingerprint、用途を固定する場合だけcommon Golden/AMIへ含めてよい。Public AMIでは秘密でない前提とし、mTLS、Portal認証、信頼済みcertificate、credential-bearing trafficへ流用しない。

## runtime決定手順

各editionのplan/implementで次を順に行う。Skill自体へ現在のversionを固定しない。

1. 統合済みKAKOMON14 recipeのexact runtime versionとlock/checksumを確認する。未統合worktreeを見ない。
2. 対象editionのofficial upstream指定との差を列挙する。
3. Application、benchmark、補助tool、frontendをbuild/test/benchmarkし、互換性とscoreへの影響を確認する計画を立てる。
4. 成功したexact versionと必要なURL、checksum、lockfileを固定する。
5. 非互換なら最小限のcompatible versionと根拠を提示し、`decision-required`としてユーザー判断を待つ。

Goとfrontend runtimeを可能な限り統合済みKAKOMON14へ揃えることは目標であり、互換性証拠や再現性より優先しない。Applicationとbenchmarkでversionを分ける場合は理由と両方のidentityを残す。

auditではupstream準拠値、KAKOMON14整合候補、最小compatible候補を比較してよいが、採用versionを確定しない。planでも互換性証拠または人間の判断が欠ける候補は未決のまま残し、implementの入力へ昇格しない。

## frontend停止条件

「24または26」等をNode.js、OS、Go、その他のversionと決め打ちしない。source、lock、CI、参考実装から意味を特定し、できなければ`decision-required`とする。

frontend buildが必要なら、次をすべて特定するまでimplementへ進まない。

- source revisionと対象directory
- package managerとexact version
- lockfile/workspace設定
- install/build commandと必要環境変数
- 生成物、hash/file manifest、license
- benchmarkとの生成順・整合性
- 配置先、配信service
- build場所とartifactのexact tag/digest/checksum

## seal境界

Golden/AMIへmachine-id、hostname、SSH host private key、本物のTLS/mTLS private key、random seed、cloud-init instance cache、credential、build log、一時checkout、Portal/`isu`/Environment/role固有設定を残さない。上記契約を満たす自己署名server key/certificateは公開テストfixtureとして残してよい。固定source、build済みApplication/benchmark/frontend、初期DB、package inventory、license/notice、artifact/recipe digestは残す。

clone/fresh boot後のidentity、秘密、role固有service、Portal接続はfinalizerの責任とし、共通recipeへ混ぜない。
