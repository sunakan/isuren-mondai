# 別セッションへのhandoff prompt契約

## 目次

1. prompt生成前の解決項目
2. promptの必須構成
3. audit mode
4. implement-through-all-sh mode
5. runtimeとfrontend
6. Git、セルフレビュー、main統合

## prompt生成前の解決項目

次を実値で埋める。不明な値は推測せず、`evidence-missing`または`decision-required`としてprompt内の停止条件にする。

| 項目 | 内容 |
|---|---|
| identity | edition、variant、canonical slug、Go版の範囲 |
| workspace | topic worktreeとmain worktreeの絶対path、branch、base full SHA、target専用の`kakomon*/**`・`upstream/**`・`mise-tasks/**`変更許可path、main統合権限 |
| audit cache | main checkoutのsource cacheとworktree-local mirrorの絶対path、remote、HEAD、dirty状態、official identityとの一致、bootstrapとimportの境界、rsync対象subpath |
| official source | URL、exact full SHA/tag、license/notice |
| references | integrated KAKOMON14、cloud-init-isucon、aws-isuconのpath、HEAD、dirty状態 |
| plan gate | current target plan ID、status、依存、競合、ユーザーの明示的な再優先順位付け、implementation readiness |
| runtime | Go、Node.js、package manager、OS、architectureの採用済み値または停止条件 |
| completion | `audit-complete`、`all-sh-slice-committed`、`ready-to-merge-main`、`merged-to-main` |

## promptの必須構成

1つのpromptへ次をこの順で書く。共通チェックリストは`$onboard-kakomon-ami-recipe`へ委譲し、target固有でない説明を繰り返さない。

1. role: 1 targetだけを担当する別Codexセッションであること。
2. cwd / Git identity: worktree絶対path、branch、base SHA。
3. Skill: `$onboard-kakomon-ami-recipe`を使い、modeを`audit`または`implement`に固定すること。
4. scope: 許可path、非変更path、外部操作禁止、他session所有物の境界。
5. evidence hierarchy: official source、audit cache、統合済みKAKOMON14、2つの参考実装を区別すること。
6. target-specific task: 調査、directory構成、file責任、受け入れ条件。
7. runtime/frontend policy: exact version、lock、checksum、build順、停止条件。
8. validation: localで安全に実施できる確認とnot-run gate。
9. Git contract: implement sessionは許可pathだけstage・commitし、条件付きでlocal mainへfast-forward統合する。pushはhuman。
10. completion report: 変更、証拠、未決、gate、次の安全な一手。

prompt冒頭でrepositoryの`AGENTS.md`を読み、1〜2行のメタ認知を行わせる。曖昧なvariant、依存未完了、所有衝突、採用済みruntimeとの不一致を見つけたら、実装へ進まず報告させる。

## audit mode

実装入口条件が不足する場合、またはユーザーが調査だけを求める場合に使う。

- ファイル作成、worktree内編集、stage、commit、push、dependency install、AWS/Orb/GitHub操作を禁止する。
- `/Users/user01/works/github.com/sunakan/aws-bastion/isuren-mondai/tmp/all-kakomon/<official-repo-name>`をread-only cacheとして調べる。
- official repositoryをclone、fetch、pullしない。cacheのremote / full HEAD / clean状態が期待値と違う場合は、cacheを変更せず`evidence-missing`として停止する。
- official sourceのURL、exact commit、license、Application、benchmark、service、frontend、topology、reset/rebootを監査する。
- `/Users/user01/works/github.com/matsuu/cloud-init-isucon`からcloud-init/provisioning上の差分候補を調べる。
- `/Users/user01/works/github.com/matsuu/aws-isucon`からPacker/provider上の差分候補を調べる。
- 参考実装の値がofficial sourceと衝突したらofficial sourceを優先し、差を報告する。
- `audit-complete`と`implementation-readiness: ready|blocked`を分ける。

read-only auditは複数targetで並行可能だが、各promptへ1 targetしか入れない。

## implement-through-all-sh mode

current planが実装可能で、専用worktreeと変更許可pathが確定している場合だけ使う。

### 変更範囲

- worktree作成直後、変更開始前にmain checkoutのsource cacheを検証し、worktreeの`tmp/all-kakomon/<official-repo-name>`へ`rsync -a`する。bootstrapだけは`.git/`を含め、複製先が既に存在する場合と`--delete`は禁止する。
- 複製後にworktree-local mirrorのorigin URL、full HEAD、clean状態がsource cacheおよびofficial identityと一致し、top-level Gitで`tmp/`がignoreされることを確認する。不一致ならmirrorを補正せず停止する。
- 以後のcontent audit / importはworktree-local mirrorだけをread-onlyで使い、main checkout側のsource cacheはidentity再確認以外に使わない。official repositoryのclone、fetch、pull、checkout、reset、cleanも行わない。
- `tmp/all-kakomon/**`は一時cacheであり、変更許可path、stage、commit、merge payloadに含めない。cacheがworktreeに残っていてもmain統合のblockerにせず、worktree cleanup時に破棄してよい。
- canonical target directoryの`provisioning/`、`cloud-init/`、`packer/`、`scripts/`を作る。
- 対応する`upstream/<official-repo-name>/**`と`mise-tasks/<canonical-slug>/**`を作成・更新してよい。3つのtarget専用rootをpromptへexact pathで列挙する。
- `upstream/<official-repo-name>/**`にはApplication、benchmark、frontend等のこちらで保守するコードを置く。worktree-local mirrorの対象subpathから`rsync`し、公式baseline commit、取り込み・除外範囲、local変更を`LICENSE`と`NOTICE.md`で追跡する。
- 編集しない画像・静的asset、`sql/`、初期データはupstreamへcommitせず、worktree-local mirrorのtarget固有subpathからfrontend artifact buildまたはbundle準備前に`rsync`する。このimportでは`.git/`、生成物、依存directoryを除外し、`rsync --delete`を使わない。
- cacheはlocal搬入元に限る。clean clone、cloud-init、AMI buildへ渡す非commit dataはfile manifest、official commit、SHA-256を持つ固定bundleへ変換し、`tmp/`を実行時依存にしない。
- `upstream/isucon14/NOTICE.md`、`kakomon14/provisioning/50-source.sh`、`mise-tasks/kakomon14/{refresh-upstream,diff}`は構造上の参考に限る。除外pathとlocal変更はtarget自身の監査で決め、公式更新で保守中の差分を黙って上書きしない。
- 他targetの`kakomon*/**`、`upstream/**`、`mise-tasks/**`を変更しない。repository-wide fileが必要なら実装を広げずscope expansionとして報告する。`kakomon14/**`とその対応rootは統合済みcommit treeを参照するだけにする。
- source cache、worktree-local mirror、2つの参考repoを変更しない。
- 非重複として明示されたactive worktreeは存在だけでblockerにしないが、その内容、branch、artifact、VM、resourceへ触れない。

### 実装責任

- `kakomon14`から借りるのは上位directory構成、stepの考え方、fail-fast、log、completion/provenance marker、mise/lock、Gossの責任分担だけにする。
- 対象upstreamからservice、package、user/group、directory、DB、proxy、DNS/TLS、port、Application、benchmark、frontendを再構成する。
- 実体のない互換stepを作らない。step名へMySQL/nginx等をコピーせず、対象serviceの実名を使う。
- `all.sh`をstep順序の唯一の正本にし、失敗を握りつぶさず、途中失敗でも構造化logを残す。
- `all.sh`が呼ぶ全step、`lib.sh`、`goss.yaml`、`provisioning/mise.ami.toml`と必要なlockを同じsliceで整合させる。
- `cloud-init`をfixed recipe revisionの薄い入口にし、edition構築ロジックを複製しない。
- `packer/`はdirectoryを用意して責任境界を記録できるが、このsliceでPacker完成やAMI buildを主張しない。
- secret、machine identity、role固有値、Portal/`isu`設定をcommon imageへ焼き込まない。

### 完了条件

次が揃った場合だけ実装をcommitし、`all-sh-slice-committed`とする。

- official source identityとlicense/noticeが固定されている。
- targetのmanaged upstreamとcacheからrsyncする非commit dataの境界、baseline/local差分、取得subpath、固定bundle identityが`NOTICE.md`とprovisioningで一致している。
- `all.sh`の全呼出先が存在し、空stubではなく、順序と依存が監査済みである。
- ApplicationとbenchmarkのGo build責任が明示されている。
- frontendが必要ならbuild、hash/manifest、benchmark build、配置の順序が証拠と一致する。
- exact runtimeとpackage managerがmise config/lockへ反映され、mutableな`latest`、`lts`、rangeだけの指定がない。
- Gossが状態を作らず、作成済み状態とprovenanceを観測する。
- local static validationと`git diff --check`が通るか、実行不能理由が具体的に記録されている。
- Orb、Golden、standalone、AMI、fresh boot、product gateが`not-run`と明記されている。

## runtimeとfrontend

- ApplicationとbenchmarkのGoを`1.26.6`へ固定する。非互換なら旧versionへfallbackせず、component別の失敗証拠を出して停止する。
- version文字列だけでなく、architecture別URL、checksum、mise config/lock、Goss/provenanceを同じidentityへ束縛する。
- KAKOMON14のApplication、benchmark、Goss、Orb、AMI再検証を独立targetのrepository-only実装の入口条件にしない。target自身でGo 1.26.6の入力identityとApplication/benchmarkを検証し、KAKOMON14の証拠を流用しない。
- Node.jsは「本家に合わせる」を数字の推測で済ませない。`package.json`、`packageManager`、lockfile、CI、`.node-version`等からexact versionを特定する。
- upstreamがmajor/rangeしか指定しない場合は、互換試験候補を提示して`decision-required`にする。`node = "lts"`や`latest`を採用しない。
- frontend package managerとversionをupstreamに合わせ、KAKOMON14のpnpmを他editionへ自動移植しない。
- frontend成果物をAMI外でbuildするかAMI内でbuildするかはcurrent planに従う。生成物、license、exact tag/tree、SHA-256、配置先が欠ければ停止する。

## OS、architecture、domain

- Ubuntu 26.04 arm64を採用値にし、Application、benchmark、package、DB/proxy/DNS等をtarget自身で検証する。非互換時はamd64・旧Ubuntuへfallbackせず、失敗componentと証拠を報告して停止する。
- Packerのbase image探索結果をbuild入力へ直接流さず、Ubuntu 26.04 arm64のexact image IDを固定する。`most_recent`、architecture違い、旧OSを許可しない。
- upstreamの競技用domainを列挙し、該当する場合は元のsubdomainを保って`isuren.internal`へ写像する。DNS/hosts、proxy、TLS SAN、cookie/domain、Application、benchmark、healthcheckを単一contractにする。
- target限定patchだけを使い、一括置換、alias、fallback、published identityの上書きをしない。
- 個人練習用の自己署名server key/certificateをcommon imageへ含める場合は、公開テストfixtureとしてmode、fingerprint、用途を記録する。mTLS、Portal認証、信頼済みcertificate、credential-bearing trafficに使わず、本物の秘密やmachine/role固有identityを含めない。
- old planでOS、architecture、domainが未決・未記載でも、この共通方針を採用済み入力としてpromptへ記録する。互換性不足は`decision-required`ではなく`evidence-missing`とし、Red/Green失敗時に停止する。

## Git、セルフレビュー、main統合

### stageとcommit

- 実装sessionへtargetの変更許可pathだけを`git add -- <exact paths>`でstageし、`git commit`することを追加の人間確認なしで許可する。
- `git add .`、`git add -A`、許可path外、別sessionの差分をstageしない。
- commit前に`git status --short`、`git diff --staged --stat`、full staged diff、`git diff --staged --check`を確認する。
- staged diffが許可scopeだけで、local validationがGreenならtarget固有のcommitを作る。
- `git push`を実行しない。

### セルフレビュー

- commit後の`main...HEAD`を[review契約](review-contract.md)に沿ってセルフレビューする。
- scope、provenance、runtime、all.sh、failure propagation、Goss、frontend/benchmark順、validation、secret/identity境界を確認する。
- findingがあればtarget branch内で修正、限定stage、commit、validation、セルフレビューを再実施し、未解決findingを残したままmainへ進まない。
- blocking/major findingなし、必要validation Green、worktree cleanを満たした場合だけ`ready-to-merge-main`とする。

### local mainへの統合

次をすべて満たす場合だけlocal `main`へ統合する。

1. topic branchがcleanで、全変更がcommit済みである。
2. current planの入口・完了条件を満たし、未決policyやstop conditionがない。
3. main worktreeがcleanで、他sessionのactive owner、resource guard、所有不明の差分がない。このpromptがtarget限定のmain統合権限を持つ。
4. read-only fetch後のlocal mainと`origin/main`が同期し、remote divergenceを確認済みである。fetchできなければ停止する。
5. topicの差分が変更許可pathだけで、セルフレビューにblocking/major findingがなく、必要validationがGreenである。

topicがcurrent mainを含まない場合はtopic worktreeでmainをmergeする。競合なしならvalidationとセルフレビューを再実施し、競合したら自動解決せず停止する。その後main worktreeで直前のHEADとclean状態を再確認し、`git merge --ff-only <topic-branch>`を実行する。fast-forwardできなければ別sessionがmainを進めた可能性を報告して停止し、main上でmerge commitを作らない。

統合後はtopic HEADがmainのancestorであること、main HEAD、status、変更pathを確認して`merged-to-main`と報告する。worktreeとbranchを削除せず、pushは人間へ戻す。

報告へbranch、topic commit、main統合前後のHEAD、worktree status、変更file、検証結果、セルフレビュー結果、未決、not-run gateを含める。`merged-to-main`をAMI完成、Orb Green、AWS Greenと表現しない。
