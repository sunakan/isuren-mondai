# recipe実装契約

## 過去問固有recipeを保つ

最初の3問程度はedition/variantごとに独立した`cloud-init`、`all.sh`、step、Goss、mise、Packer、検証taskを持たせる。統合済みKAKOMON14から借りるのはディレクトリ構成、stepの考え方、入力manifest、artifact identity、ログ形式などであり、MySQL/nginx/runtime/topologyを巨大な共通分岐へまとめない。

実体のない互換stepを作らない。`all.sh`を実行順の正本とし、step名は対象serviceの責任を表す。3問の実測差分が揃ったら共通化候補を必ずレビューするが、共通化自体は必須としない。

## file別の責任

| file | 責任 | 持たせない責任 |
|---|---|---|
| `cloud-init` | fixed recipe revisionを取得し、同一の`all.sh`を無人実行し、完走を伝える | edition構築ロジックの複製、秘密の埋め込み、成功の推測 |
| `all.sh` | edition固有stepの順序、fail-fast、構造化log、完走marker | provider分岐、未宣言の手動修正、検証失敗の握りつぶし |
| step scripts | package、user、source、DB、Application、frontend、benchmark、service等の状態作成。official noncommit dataのAMI内取得・検証もここで行う | 他editionの巨大条件分岐、Gossによる状態変更、local cache/`dist`への実行時依存 |
| `goss.yaml` | file/package/user/service/port/commandとprovenance markerの観測 | 状態作成、multi-node benchmark、reset/reboot、製品E2Eの代替 |
| `mise.toml`/lock | exact runtime/tool version、architecture別URL/checksum、再現可能なinstall | `latest`、rangeだけのversion、未lock download |
| Packer | provider-native base、AWS region、architecture、disk/network/build adapter、cloud-init待機、marker/Goss確認、tag、seal、cleanup | recipe本体の再実装、暗黙のdefault region、Orb成功の流用、製品E2E |
| `upstream/<official-repo-name>` | 公式baselineから選んだApplication、benchmark、frontend等のこちらで保守するコード、LICENSE、NOTICE | 編集しない画像・静的asset、`sql/`、初期データ、由来不明binary |
| `mise-tasks/<canonical-slug>` | target固有のimport/diff、lock、static validation、build/release adapter | 他targetの更新、保守差分の無警告上書き、承認なしの外部gate |

Packer plugin、AWS region `ap-northeast-1`、同regionのbase image、OS repository、package inventory、frontend artifact、source revision、recipe revisionを入力manifestへ束縛する。`most_recent`等で候補を探す調査段階と、artifact buildへ渡すexact IDを分ける。

Ubuntu imageでは`/tmp`がRAM-backed tmpfsの場合がある。大きなofficial archive、Packer upload、展開処理を容量未確認の`/tmp`へ置かず、root-backed stagingを明示し、成功・失敗後のcleanupとseal時不在を検証する。archive形式はURLや思い込みで決めず、exact asset、magic/type、SHA-256と対応extractorを固定する。

localの`packer validate -syntax-only`はHCL構文の証拠に限定し、plugin install、provider接続、AMI buildのGreenへ昇格しない。通常の`packer validate`やbuildが外部plugin/network/cacheを必要とする場合は、実行したgateと未実行gateを分けて報告する。

## upstreamのfilesystem構成を保つ

official provisioningからcontestant home、Application、benchmark、environment file、runtime、license、serviceの最終配置を一覧化する。`/home/isucon`を`/home/isuren`へ読み替える場合も、相対pathとfile名を可能な限り保つ。独自の`/etc/.../runtime.env`等へ移す前に、officialの`env.sh`やsystemd `EnvironmentFile=`を正本として扱う。

official license/noticeがcontestant homeから参照される、またはpractice imageの既存契約がhome直下を採用する場合は、`/home/isuren/LICENSE`等の最終pathをREADME/provenance/Gossへ固定する。provenance directoryだけへの格納で利用者向け配置を満たしたと推測しない。

意図的な差だけをtarget README/NOTICEとGossへ明記する。少なくとも次を区別する。

- username/domain等の採用済み写像
- xbuild等をmiseへ置き換えるruntime modernization
- architecture依存名を外したbenchmark binary名
- SSM/provider finalizerへ委ねる`.ssh`、password、machine/role identity
- build後に不要なbenchmark checkout、staging、GOPATH/cache

buildにだけ使う`~/isuconN`や`~/go`を完成artifactの仕様にしない。最終binaryへembed済みまたはfinal pathへcopy済みならsealで削除し、Gossで不在を観測する。逆にApplicationがruntime時に相対参照するsource/dataを推測で消さず、service cwdとsource codeから必要性を確認する。

benchmarkもsource packages、module entrypoint、final binary、authoritative-result wrapper、runtime assetを分ける。final binaryをhome直下へ置く等、KAKOMON13/14のpractice-image layoutへ意図的に合わせる場合はofficial pathとの差をREADME/provenance/Gossへ記録する。sourceを削除してもinitial-data、static tree、fixture、cwd等のruntime参照は残し、wrapperの既定pathと一致させる。

payment/shipment等のmockがbenchmark process内で起動するeditionでは、別のpersistent serviceを作らない。benchmark開始前に対象portが空いていることをfail-fastで確認し、wrapperがofficial引数、最終JSON、exit/failure semanticsを保持する。

official `env.sh`はkeyごとに分類する。公開されたpractice DB defaultはfile名/keyを保ち、用途と非secret性を記録してcommon imageへ含めてよい。clone固有値、credential-bearing値、machine/role identityはfresh boot finalizerで再生成し、sealed common artifactでは不在、fresh boot後は正しいowner/mode/valueで存在するという二状態を別々に検証する。sealed Goss specをそのままreboot後へ再利用して矛盾させない。

## sourceとartifact identity

- `upstream/<official-repo-name>/**`を、official URLとexact baseline commit/tagから選択したこちらのmanaged source treeとする。Application、benchmark、frontend等を必要に応じてlocal更新し、公式baseline、取り込み・除外範囲、local差分を`NOTICE.md`へ記録する。
- managed sourceのbuild identityをisuren-mondaiのexact recipe commit/pathへ固定し、その起点であるofficial URL・baseline commit・license・local差分も追跡する。公式treeと同一だと偽らない。
- implement worktree作成直後、main checkout配下のsource cacheについてorigin URL、full HEAD、clean状態を検証し、clone全体を同名のworktree-local `tmp/all-kakomon/<official-repo-name>`へ`rsync -a`する。bootstrapだけは`.git/`を含め、既存宛先と`--delete`を許可しない。複製後にも同じidentityを確認する。
- worktree-local mirrorはgitignore対象のread-only一時cacheとし、stage、commit、merge payloadに含めない。存在したままlocal mainへ統合してよく、worktree cleanup時に破棄してよい。
- 別sessionはofficial repositoryを再clone、fetch、pullせず、bootstrap後にmain source cacheを直接参照しない。不一致cacheを変更せず、人間による更新待ちとして停止する。
- 編集しない画像・静的asset、`sql/`、初期データは原則managed sourceへcommitしない。audit/import時はworktree-local mirrorから対象subpathだけを検査できるが、clean buildではofficial exact commitからbuild instance内で取得してmanifest/checksum検証するか、外部固定bundleを使う。`.git/`、`node_modules/`、`dist/`等を最終配置へ混入させず、取得元LICENSEを伴わせる。
- `upstream/isucon14/NOTICE.md`と`kakomon14/provisioning/50-source.sh`を構造の参考にする。画像・dataの配置はeditionごとに異なるため、除外pathをコピーせずofficial treeから決める。
- cacheはlocal搬入元に限り、clean clone、cloud-init、AMI buildが直接参照するbuild sourceにしない。保守codeはcommit済みmanaged sourceにする。非commit asset/dataはofficial URL・exact commit・Git treeまたはasset identity・file manifest・SHA-256を固定し、AMI内直接取得または外部固定bundleのどちらか一つで供給する。
- 参考実装からcopyする場合も、対象editionのofficial provenanceとlicenseを追跡する。
- recipe commit/digest、upstream revision、AWS region `ap-northeast-1`、同regionのbase image ID、architecture、runtime lock、frontend identity/checksumをartifact tag/manifestと証拠へ残す。
- Orb GoldenとAWS AMIを相互変換せず、同じfixed recipeからprovider-native artifactを別々に作る。

target固有のimport/refresh taskはworktree-local mirrorからの初回取り込みと公式差分監査を支援してよいが、network clone / fetchを実行せず、managed sourceのlocal変更を`rsync --delete`等で黙って上書きしない。搬入前後のofficial identity、file一覧、diffを示し、意図的な更新として扱う。

## platformとhostname

- 新規targetはUbuntu 26.04 arm64を採用値とし、Application、benchmark、OS package、DB/proxy/DNS等をcomponent別にRed/Greenする。非互換時にamd64や旧Ubuntuへ自動fallbackせず、失敗証拠を残して停止する。
- AWS regionを東京`ap-northeast-1`へ固定し、profile、Packer、base image検索、build、tag、fresh boot、product検証、cleanupへ明示する。AWS CLI設定や環境変数の暗黙値をartifact identityにしない。
- base imageの検索は`ap-northeast-1`でのaudit/preflightに限定し、Packer build入力には同regionのUbuntu 26.04 arm64 exact image IDを渡す。`most_recent`、別regionのAMI ID、architecture違い、旧OSをartifact identityへ残さない。
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

mise config/lockをchecksum metadata置き場にするだけで、別途`/opt/go-*`や`/usr/local/bin/go`を手動導入しない。mise自体もexact version、official URL、architecture、SHA-256を固定してcontestant home配下へinstallし、Applicationとbenchmarkの両buildを同じ`mise exec -- go`経路へ通す。

`runuser`は`.bashrc`を読まないため、provisioning/Gossではmise binaryのfull pathと`HOME=/home/<user>`を明示する。interactive shell用activationは補助であり、無人buildの正しさをPATHやshell初期化へ依存させない。Gossでmise version、config/lock、Go versionを観測し、旧runtime pathが残らない静的契約も置く。

auditではupstream準拠値、KAKOMON14整合候補、最小compatible候補を比較してよいが、採用versionを確定しない。planでも互換性証拠または人間の判断が欠ける候補は未決のまま残し、implementの入力へ昇格しない。

## frontend停止条件

「24または26」等をNode.js、OS、Go、その他のversionと決め打ちしない。source、lock、CI、参考実装から意味を特定し、できなければ`decision-required`とする。

まずfrontend sourceをこちらで保守してbuildする方式と、official prebuiltをbyte-for-byte使う方式を分ける。

official prebuilt方式ではNode.js、package manager、local `dist`、CI/Releaseを要求しない。official URL、exact commit、Git tree、file manifest、SHA-256、license、配置先を固定し、AMI内で直接取得・検証して配置する。Packerはlocal `dist`をuploadせず、optionalなlocal artifact taskをnormal buildの前提にしない。HTML/bundleがservice workerを登録するか、CDN/絶対domain参照がruntime到達可能かを調べ、dormant referenceは変更せず記録する。activeな絶対domain依存があれば生成済みassetを一括置換・再minifyせず停止する。

frontend buildが必要なら、次をすべて特定するまでimplementへ進まない。

- source revisionと対象directory
- package managerとexact version
- lockfile/workspace設定
- install/build commandと必要環境変数
- 生成物、hash/file manifest、license
- benchmarkとの生成順・整合性
- 配置先、配信service
- build場所とartifactのexact tag/digest/checksum

AMI外のCI/Release buildを採用する場合、target固有GitHub Actions workflow、target限定tag filter、asset名、manifest/licenseまでrepository実装へ含める。build scriptやignore済み`dist/`だけで配布可能とみなさない。外部verify前にremote tag、公開Release、asset digestをread-onlyで確認し、未発行ならlocal artifactや別target Releaseで迂回せず停止する。

official inputをAMI内で直接取得する場合は、curl/git/unzip等のnetwork/archive toolを先に導入し、`all.sh`の実行順とstep番号を一致させる。取得stepは一時directoryへdownload/extractし、全manifest/checksum/禁止domain検査がGreenになってから最終pathへ置換する。途中失敗で古いartifactを再利用せず、completion markerを作らない。

## seal境界

Golden/AMIへmachine-id、hostname、SSH host private key、本物のTLS/mTLS private key、random seed、cloud-init instance cache、credential、build log、一時checkout、Portal/`isu`/Environment/role固有設定を残さない。上記契約を満たす自己署名server key/certificateは公開テストfixtureとして残してよい。固定source、build済みApplication/benchmark/frontend、初期DB、package inventory、license/notice、artifact/recipe digestは残す。

clone/fresh boot後のidentity、秘密、role固有service、Portal接続はfinalizerの責任とし、共通recipeへ混ぜない。

seal直後とfresh boot後を別stateとして定義する。seal/Gossではservice停止、clone固有env/TLS/identity不在、一時checkout/cache不在を確認する。reboot後はfinalizer完走、env/TLS再生成、enabled/running、DNS/port/HTTP、data保持を確認する。片方のspecで両状態を同時に要求しない。
