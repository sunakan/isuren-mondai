---
name: orchestrate-kakomon-ami-sessions
description: isuren-mondaiのルートセッションとして、ISUCON過去問ごとのGo版AMI recipe作業を専用worktreeと別Codexセッションへ安全に引き渡す。対象・variant・plan依存・worktree所有を監査し、別セッション用prompt、現行モデルと推論レベルの推奨、成果レビュー、限定stage・commit・local main統合、人間push、frontend Release、fresh VM/EC2 verifyのhandoff gateを管理する。kakomonNまたはkakomonN-qualify/finalの新規recipeを並行調査したいとき、実装セッションを準備したいとき、all.shまでの差分・main統合・外部検証readyをレビューしたいときに使う。
---

# 過去問AMIセッションを制御する

## ルートセッションの境界を守る

- ルートセッションを制御塔に限定し、対象recipeを自分で実装しない。
- 1つのworktreeと別セッションへ1つのedition/variantだけを割り当てる。
- ユーザーがpromptだけを求めた場合はworktreeを作らない。「準備」「worktreeを立てる」まで依頼された場合だけ作る。
- ユーザーがCodex taskの新規作成まで明示しない限り、taskを作らずcopy-ready promptを返す。
- 実装開始条件を満たさない対象はaudit promptだけにし、実装worktreeを先に作らない。
- 実装promptへtarget限定の`git add`、commit、セルフレビュー、local `main`への統合権限を明記する。権限をaudit promptへ広げない。
- 実装promptのmain統合権限を、そのtargetの検証済みcommitを`--ff-only`で統合する範囲に限定する。他sessionがmainを変更中なら競合せず停止させる。
- AWS、Orb、GitHub write、AMI build、EC2起動をprompt生成やlocal実装へ混ぜない。local main統合では`main`と`origin/main`を比較せず、remote同期をmerge条件にしない。remote確認はpush済みcommitやReleaseを必要とする外部verifyのhandoffだけで行う。

## 現在の正本と所有を先に読む

次を毎回読み直し、過去のsession記憶や未統合worktreeを正本にしない。

1. repository rootの`AGENTS.md`、`README.md`、Git status、local main HEAD、`git worktree list --porcelain`。remote divergenceはlocal main統合の判定材料にしない。
2. `/Users/user01/works/github.com/sunakan/isuren/docs/decisions/20260815-isuren-mondai-image-strategy.md`。
3. 対象edition/variantのcurrent planと、その`status`、`depends_on`、`conflicts_with`、変更許可path。
4. 統合済み`kakomon14/**`。activeなKAKOMON14 worktreeは所有確認だけにし、内容を参照しない。変更pathとresourceがtargetに重ならず、current target planまたはユーザーが非依存と明示した場合は、その存在だけを実装blockerにしない。
5. `$onboard-kakomon-ami-recipe`と必要なreference。生成promptでもこのSkillを明示的に使わせる。
6. external frontend配布またはAWS/Orb verifyへ進む場合は[Releaseと外部verifyのhandoff契約](references/release-and-verify-preflight.md)。

採用済みplanと依頼値が衝突したら、どちらかを勝手に選ばない。`decision-required`として実装promptとworktree作成を止める。特にGo、Node.js、OS、architecture、AWS region、topology、hostname、frontend配布方法を再確認する。ただし、current target planまたはユーザーの最新の明示判断が古い展開順・保留理由を置き換えている場合は、その判断をpromptへ記録し、古い一般順序だけをblockerとして復活させない。

## 対象identityを一意にする

- `N`だけでQualify/Finalが分かれる年は停止し、variantを確定する。
- 出力directory、branch、artifact、promptで同じcanonical slugを使う。例: `kakomon13`、`kakomon12-qualify`、`kakomon12-final`。
- main checkout配下のsource cacheを絶対pathで固定する。例: `/Users/user01/works/github.com/sunakan/aws-bastion/isuren-mondai/tmp/all-kakomon/isucon13`。
- implement worktreeを作った直後、source cacheのorigin URL、full HEAD、clean状態を検証し、worktreeの`tmp/all-kakomon/<official-repo-name>`へclone全体を`rsync -a`する。このbootstrapだけは複製先でもidentityを再検証できるよう`.git/`を含め、`--delete`を使わない。
- source cacheが期待identityと違う、複製先が既に存在する、または複製後のorigin / HEAD / clean状態が一致しない場合は停止する。clone、fetch、pull、checkout、reset、cleanで補正しない。
- worktree-local cache mirrorをread-only audit / import sourceにし、以後main checkout側のcacheはidentity再確認以外のcontent audit / importに使わない。managed sourceまたは一時build/provisioning stagingへ搬入するときは対象subpathを明示し、`.git/`、`node_modules/`、`dist/`等を除外する。
- `tmp/all-kakomon/**`はgitignore対象の一時cacheであり、変更許可path、stage、commit、merge payloadに含めない。存在したままでもlocal main統合の妨げにせず、worktree cleanupとともに破棄してよい。
- cacheは搬入元であり、clean clone、cloud-init、AMI buildが参照するprovenanceではない。保守codeだけをcommit済み`upstream/**`へ置く。非commit asset/dataは、公式exact commitからbuild instance内で一時取得してcommit済みfile manifestで検証するか、ignore済み`dist/`で生成してGitHub Release等の外部配布先へexact tagとSHA-256付きで公開する。前者ではlocal `dist/`をPacker入力や必須前処理にせず、どちらでも`tmp/` cacheへ実行時依存しない。
- official upstream URL、full commit SHAまたはexact tag、license/noticeを確定し、recipeから再取得できるようにする。
- 実装scopeはcanonical targetの`kakomon*/**`に加え、対応する`upstream/<official-repo-name>/**`と`mise-tasks/<canonical-slug>/**`を含める。別targetの同名rootやrepository-wide fileへ広げない。
- external frontendをtarget固有workflowで配布する場合は、`.github/workflows/release-<canonical-slug>-frontend.yml`も明示的な変更許可pathへ含める。workflowが必要なのに通常のtarget root外であることを理由に欠落させず、許可がなければscope expansionとして停止する。
- `upstream/<official-repo-name>/**`は公式sourceを起点にこちらが保守するcode treeとし、公式baseline、取り込み・除外範囲、local変更を`NOTICE.md`へ記録する。画像を含むbinary、編集しない静的asset、`sql/`、初期データはcommitせず、frontend buildまたはprovisioningの消費時だけ一時取得・検証する。
- build成果物、release archive、固定bundle、画像、音声、動画、font、database dump等のbinaryを、このprojectのGit管理下へ追加しない。生成物はignore済み`dist/`または一時directoryに置き、配布が必要ならGitHub Release等の外部配布先を使う。manifest、checksum、provenanceのtext metadataはGit管理してよい。
- 画像や他のbinaryがworking treeやbuild先へ配置されること自体は許可する。禁止するのはGitでの追跡であり、配置先がignore対象であることと、stage/commit/merge payloadへ入らないことを確認する。
- binaryまたは成果物をGit管理したい、あるいはその方がよいと判断した場合は、追加・stage・commitを行わず作業を停止し、対象file、理由、代替案を示して人間へ相談する。利便性やclean clone再現性を理由にこの停止条件を迂回しない。
- `/Users/user01/works/github.com/matsuu/cloud-init-isucon`と`/Users/user01/works/github.com/matsuu/aws-isucon`はreference-onlyとし、毎回HEAD、remote、dirty状態を記録する。dirty差分を採用しない。

## 並行性を制御する

- read-only auditはtargetごとに並行してよい。
- local実装はcurrent planの入口条件を満たし、変更pathとworktree所有が重複しないtargetだけ許可する。
- current target planまたはユーザーの明示的な再優先順位付けを、古い一般的な展開順より優先する。明示判断のない依存gateを「worktreeが分かれている」だけで迂回しない。
- active worktreeがあっても、targetの変更path・artifact・VM・resource namespaceと重ならなければ、それだけで停止しない。所有外worktreeの内容や生成物には触れない。
- 最初の3問は独立recipeを保ち、共通libraryを先回りして作らない。
- 他targetの`kakomon*/**`、`upstream/**`、`mise-tasks/**`、特にKAKOMON14の対応pathを変更しない。repository-wide変更が必要なら別planへ分離する。

## runtime方針を固定する

- GoはApplicationとbenchmarkの両方で`1.26.6`を第一かつ唯一の実装候補とする。
- version文字列、official archive URL、architecture別SHA-256、mise config/lock、Goss、provenanceを同じidentityへ束縛する。
- Go 1.26.6で非互換なら旧versionへ自動fallbackせず、component別の失敗証拠を示して停止する。
- 統合済みKAKOMON14のruntime config/lockは構造上の比較元に限る。KAKOMON14のApplication、benchmark、Goss、Orb、AMI再検証を、独立targetのrepository-only audit/実装の入口条件にしない。
- 各targetがGo 1.26.6のofficial URL・architecture別SHA-256・config/lockを独立に固定し、Applicationとbenchmarkをtarget自身のvalidationで確認する。KAKOMON14の成功・失敗証拠を流用しない。
- Node.jsは対象upstreamの証拠からexact versionを決める。`latest`、`lts`、major/rangeだけの指定をartifact入力にしない。

## frontend配布をverify入口から逆算する

- official repositoryがprebuilt frontendをexact commit/treeで保持し、こちらでsourceを保守・再buildしないtargetでは、AMI内直接取得を独立したdelivery方式として扱う。local `dist/`、Node.js、package manager、Release workflowを要求せず、official URL、commit、tree、file manifest、SHA-256、licenseを固定してbyte-for-byte配置させる。
- prebuilt asset内の外部URLは、文字列の存在だけで変更せず、実際にHTML/bundleが登録・参照するruntime dependencyかを分ける。未登録のservice worker等に残るdormant referenceは証拠付きで維持し、activeな絶対domain依存があれば生成済みassetを書き換えず停止させる。
- frontendをCI/Release配布するtargetでは、build scriptだけでなくtarget固有workflow、tag filter、asset名、manifest/licenseをrepository sliceの受け入れ条件にする。
- `all-sh-slice-committed`、remote Release発行、外部verify readinessを別状態にする。人間push後に検証対象recipe commit、tag、Release asset、published digestをread-onlyで確認するまでEC2/VMへprovisioningを開始しない。
- Releaseが欠ける場合は既存local `dist/`や別targetのartifactで迂回せず、EC2を変更する前に停止する。
- 詳細とbinaryのstage検査は[Releaseと外部verifyのhandoff契約](references/release-and-verify-preflight.md)に従う。

## platformとhostnameを固定する

- 全targetの採用platformをUbuntu 26.04 arm64とし、Application、benchmark、OS package、DB/proxy/DNS等をtarget自身で検証する。非互換でもamd64や旧Ubuntuへ自動fallbackせず、component別証拠を示して停止する。
- AWS regionは全targetで東京`ap-northeast-1`に固定する。profile、Packer、base AMI検索、build、tag、fresh boot、product検証、cleanupを同じregionへ束縛し、AWS CLI設定や環境変数の暗黙値に依存しない。
- base AMIは`ap-northeast-1`での調査時の検索とbuild入力を分け、artifactでは同regionのUbuntu 26.04 arm64 exact image IDを固定する。`most_recent`、別regionのAMI ID、region fallbackを残さない。
- upstreamに`isucon.net`、`*.isucon.dev`、`*.isucon.local`等の競技用domainがあれば、元のsubdomain構造を保って`isuren.internal`配下へ写像する。DNS/hosts、proxy、TLS SAN、cookie/domain、Application、benchmark、healthcheckをtarget限定patchで一致させる。
- repository全体の一括置換、旧hostname alias/fallback、既存published identityの上書きを禁止する。
- 個人練習用の自己署名server key/certificateは、公開テストfixtureと明記し、権限を制限する場合だけcommon imageへ含めてよい。mTLS、Portal認証、信頼済みcertificate、credential-bearing trafficへ流用せず、本物の秘密とmachine/role固有identityは焼き込まない。
- 古いtarget planにOS、architecture、domain方針が未記載であることだけを`decision-required`にしない。この共通方針を採用済み入力とし、互換性を`evidence-missing`としてRed/Greenする。planが別の採用値を明記している場合だけ衝突として停止する。

## モデルと推論レベルを提案する

モデル名は時間依存として、利用可能なmodel一覧またはcurrent official OpenAI documentationを確認してから提案する。2026-08-16時点のbaselineは次とするが、取得できないmodelを断定しない。

| session | baseline | 理由 |
|---|---|---|
| rootのprompt準備・worktree preflight | `gpt-5.6-sol` / `high` | plan、所有、prompt契約の照合 |
| edition audit | `gpt-5.6-sol` / `xhigh` | official sourceと複数referenceの横断監査 |
| `all.sh` slice実装 | `gpt-5.6-sol` / `xhigh` | 長時間の調査、実装、自己レビュー |
| 独立レビュー | `gpt-5.6-sol` / `xhigh` | provenance、scope、failure契約の厳密な確認 |
| 指摘済みの局所修正 | `gpt-5.6-terra` / `high` | boundedな修正の費用と品質の両立 |

`max`を既定にしない。複数の証拠が衝突する、同じ難所で再失敗する、またはquality-firstの独立再監査が必要な場合だけ`gpt-5.6-sol` / `max`を提案する。モデル確認を省略した場合は、baselineの日付と未確認であることを明記する。

## worktreeを準備する

実装準備を依頼され、plan入口条件がGreenの場合だけ次を行う。

1. base branch、full SHA、clean状態を記録する。local worktree準備では`main`と`origin/main`を比較しない。remote更新が別目的で必要なら勝手にpull/rebaseしない。
2. existing worktree、branch、同名path、active ownerとの衝突を確認する。
3. branchを`codex/<canonical-slug>-ami-recipe`、worktreeを`/private/tmp/isuren-mondai-<canonical-slug>-ami-recipe`の形で提案する。衝突時は名前を推測で再利用せず停止する。
4. exact base SHAからworktreeを作る。
5. main checkoutのsource cacheについてorigin URL、full HEAD、clean状態を確認する。
6. worktree作成直後に`tmp/all-kakomon/`を作り、対象cloneを同名pathへ`rsync -a`する。bootstrapでは`.git/`を含め、既存または非emptyの複製先、`--delete`、network取得を許可しない。
7. worktree-local mirrorのorigin URL、full HEAD、clean状態と、top-level Gitで`tmp/`がignoreされていることを確認する。
8. 以後のaudit/importにはworktree-local mirrorだけを使わせる。mirrorはstage・commit・merge対象外であり、統合前の削除を要求しない。

branch名へ必ずcanonical slugを含める。すでに別sessionが所有するworktree、branch、VM、artifactへ触れない。

## handoff promptを作る

[handoff prompt契約](references/handoff-prompt-contract.md)を完全に読み、placeholderを可能な限り実値へ解決して1つのcopy-ready promptにする。promptの前に次を短く示す。

- 推奨model / reasoning effortと選定理由
- mode（`audit`または`implement-through-all-sh`）
- worktreeの絶対path、branch、base SHA。prompt-onlyなら`not-created`
- implementation readinessとblocker

共通のaudit/recipe/reviewチェックリストをprompt本文へ複製せず、`$onboard-kakomon-ami-recipe`とreferenceへ委譲する。prompt本文にはtarget固有のidentity、解決済み値、証拠snapshot、変更境界、例外判断、停止条件、Git権限だけを簡潔に書く。

入口条件が不足する場合も、調査を進められるならaudit promptを返す。`all.sh` sliceの完成はAMI完成ではないため、完了ラベルを`all-sh-slice-committed`、`ready-to-merge-main`、`merged-to-main`のいずれかに限定する。

## 成果をレビューする

[review契約](references/review-contract.md)を完全に読み、対象worktreeの差分とraw evidenceを独立に確認する。別sessionの完了報告だけを証拠にしない。

- まずblocking finding、次にmajor/minor finding、最後に良い点と安全な次の一手を示す。
- findingがなければ明言し、残る未検証gateを列挙する。
- `all.sh`が存在するだけで完成にしない。呼び出すすべてのstep、mise identity、source provenance、Goss、frontend/benchmark順、fail-fastを確認する。
- external frontendの場合はtarget固有release workflowの存在とtag/asset契約を確認し、未発行Releaseをverify-readyと報告しない。
- 実施していないOrb、Golden、standalone、AMI、fresh boot、product gateを`not-run`のまま保つ。

## Git統合と外部検証を分ける

- 別セッションへtargetの変更許可pathだけを明示し、検証後の`git add -- <exact paths>`と`git commit`を追加の人間確認なしで許可する。`git add .`、`git add -A`、許可path外のstageを禁止する。
- commit前にstatus、staged stat、staged full diff、`git diff --staged --check`を確認させる。無関係な既存差分をcommitへ含めない。
- commit前に[Releaseと外部verifyのhandoff契約](references/release-and-verify-preflight.md)のbinary tracking gateも実施する。画像・archive・build出力の配置とGit追跡を混同しない。
- commit後に[review契約](references/review-contract.md)でセルフレビューし、blocking/major findingが残らず、必要validationがGreenの場合だけ`ready-to-merge-main`とする。
- main統合直前にlocal main HEAD、main worktreeのclean状態、他sessionのactive owner、resource guard、topicとの差分を再確認する。`origin/main`のfetch、ahead/behind、一致は確認せず、merge条件にしない。mainまたはtopicに所有不明の差分があれば停止する。
- topicがcurrent mainを含まない場合は、ユーザー指定に従ってtopic worktreeでmainをmergeまたはrebaseする。競合を推測で解決しない。成功後はcommit identityを取り直し、同じvalidationとセルフレビューを再実施する。rebase前の外部証拠は新commitの証拠へ自動昇格せず、許可pathのtreeが同一ならslice同一性だけを別途記録する。
- main worktreeでは`git merge --ff-only <topic-branch>`だけを許可する。fast-forwardできなければ停止し、merge commitをmain上で作らない。
- 統合後にtopic HEADがmainのancestorであること、mainのstatus、HEAD、変更範囲を確認して`merged-to-main`と報告する。worktreeやbranchを自動削除しない。
- worktree/branch削除はユーザーが明示した場合だけ行う。mainがtopic HEADを含むこと、main/topicのclean、対象worktreeの絶対pathとbranchを再確認し、対象worktreeだけをremoveしてから、そのexact branchだけを削除する。他targetのactive worktreeやbranchへ触れない。
- AIはpushしない。人間がpushし、remoteにexact main commitが存在することを確認する。
- EC2内で`git clone`して試すverify promptはpush後にだけ作る。local-only commitをclone可能と扱わない。
- external frontendなら、検証対象recipe commitがremoteから取得可能で、targetのRelease assetとpublished digestが存在するまでverify promptを実行可能扱いにしない。local mainとremote mainの完全一致は要求しない。
- `aws-bastion`のcurrent task定義を再読し、namespace入力が実際にtaskへ届くことをread-onlyで確認する。現状の`up-bastion`は`STACK_NAME`を入力として読まず、`mise.toml`の固定`BASTION_STACK_NAME`はshell側の同名変数を上書きするため、専用prefixを指定可能と扱わない。
- namespace入力を受け取れない場合は外部検証を止め、`BASTION_STACK_NAME = { default = "aws-bastion" }`またはtask argument等へ変更する別scopeを提案する。`mise.local.toml`を黙って作らない。
- EC2起動やAMI build前に、account、固定region `ap-northeast-1`、namespace、費用上限、TTL、exact stack、cleanup ownerとcommand、秘密の受け渡し、人間承認を確定する。別regionが観測されたら操作を開始しない。
- AIが対話式cleanupを使えない場合はexact stack nameを指定する手順を別途提示する。cleanup確認まで外部gateを完了扱いにしない。
