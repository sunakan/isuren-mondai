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
| workspace | topic worktreeとmain worktreeの絶対path、branch、base full SHA、変更許可path、main統合権限 |
| audit cache | main checkout配下の絶対path、remote、HEAD、dirty状態 |
| official source | URL、exact full SHA/tag、license/notice |
| references | integrated KAKOMON14、cloud-init-isucon、aws-isuconのpath、HEAD、dirty状態 |
| plan gate | plan ID、status、依存、競合、implementation readiness |
| runtime | Go、Node.js、package manager、OS、architectureの採用済み値または停止条件 |
| completion | `audit-complete`、`all-sh-slice-committed`、`ready-to-merge-main`、`merged-to-main` |

## promptの必須構成

1つのpromptへ次をこの順で書く。

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
- official sourceのURL、exact commit、license、Application、benchmark、service、frontend、topology、reset/rebootを監査する。
- `/Users/user01/works/github.com/matsuu/cloud-init-isucon`からcloud-init/provisioning上の差分候補を調べる。
- `/Users/user01/works/github.com/matsuu/aws-isucon`からPacker/provider上の差分候補を調べる。
- 参考実装の値がofficial sourceと衝突したらofficial sourceを優先し、差を報告する。
- `audit-complete`と`implementation-readiness: ready|blocked`を分ける。

read-only auditは複数targetで並行可能だが、各promptへ1 targetしか入れない。

## implement-through-all-sh mode

current planが実装可能で、専用worktreeと変更許可pathが確定している場合だけ使う。

### 変更範囲

- canonical target directoryの`provisioning/`、`cloud-init/`、`packer/`、`scripts/`を作る。
- このsliceではtarget directory配下だけを変更する。`mise-tasks/**`、`upstream/**`、repository-wide fileが必要なら実装を広げずscope expansionとして報告する。
- 他の`kakomon*/**`を変更しない。`kakomon14/**`は統合済みcommit treeを参照するだけにする。
- audit cacheと2つの参考repoを変更しない。

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
- KAKOMON14のGo 1.26.6整合とplan指定の再検証が未統合なら、依存targetの実装を開始しない。
- Node.jsは「本家に合わせる」を数字の推測で済ませない。`package.json`、`packageManager`、lockfile、CI、`.node-version`等からexact versionを特定する。
- upstreamがmajor/rangeしか指定しない場合は、互換試験候補を提示して`decision-required`にする。`node = "lts"`や`latest`を採用しない。
- frontend package managerとversionをupstreamに合わせ、KAKOMON14のpnpmを他editionへ自動移植しない。
- frontend成果物をAMI外でbuildするかAMI内でbuildするかはcurrent planに従う。生成物、license、exact tag/tree、SHA-256、配置先が欠ければ停止する。

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
