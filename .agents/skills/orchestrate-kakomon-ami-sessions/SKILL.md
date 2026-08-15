---
name: orchestrate-kakomon-ami-sessions
description: isuren-mondaiのルートセッションとして、ISUCON過去問ごとのGo版AMI recipe作業を専用worktreeと別Codexセッションへ安全に引き渡す。対象・variant・plan依存・worktree所有を監査し、別セッション用prompt、現行モデルと推論レベルの推奨、成果レビュー、別セッションによる限定stage・commit・local main統合、人間pushのgateを管理する。kakomonNまたはkakomonN-qualify/finalの新規recipeを並行調査したいとき、実装セッションを準備したいとき、all.shまでの差分やmain統合可否をレビューしたいときに使う。
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
- AWS、Orb、GitHub write、AMI build、EC2起動をprompt生成やlocal実装へ混ぜない。remote同期確認のread-only fetchだけはmain統合preflightとして許可する。それ以外の外部操作は独立した承認済みverify handoffにする。

## 現在の正本と所有を先に読む

次を毎回読み直し、過去のsession記憶や未統合worktreeを正本にしない。

1. repository rootの`AGENTS.md`、`README.md`、Git status、remote divergence、`git worktree list --porcelain`。
2. `/Users/user01/works/github.com/sunakan/isuren/docs/decisions/20260815-isuren-mondai-image-strategy.md`。
3. 対象edition/variantのcurrent planと、その`status`、`depends_on`、`conflicts_with`、変更許可path。
4. 統合済み`kakomon14/**`。activeなKAKOMON14 worktreeは所有確認だけにし、内容を参照しない。
5. `$onboard-kakomon-ami-recipe`と必要なreference。生成promptでもこのSkillを明示的に使わせる。

採用済みplanと依頼値が衝突したら、どちらかを勝手に選ばない。`decision-required`として実装promptとworktree作成を止める。特にGo、Node.js、OS、architecture、topology、hostname、frontend配布方法を再確認する。

## 対象identityを一意にする

- `N`だけでQualify/Finalが分かれる年は停止し、variantを確定する。
- 出力directory、branch、artifact、promptで同じcanonical slugを使う。例: `kakomon13`、`kakomon12-qualify`、`kakomon12-final`。
- 調査cacheはmain checkout配下の絶対pathを使う。例: `/Users/user01/works/github.com/sunakan/aws-bastion/isuren-mondai/tmp/all-kakomon/isucon13`。
- `tmp/all-kakomon/**`をread-only audit cacheとして扱い、build sourceやartifact provenanceにしない。
- official upstream URL、full commit SHAまたはexact tag、license/noticeを確定し、recipeから再取得できるようにする。
- `/Users/user01/works/github.com/matsuu/cloud-init-isucon`と`/Users/user01/works/github.com/matsuu/aws-isucon`はreference-onlyとし、毎回HEAD、remote、dirty状態を記録する。dirty差分を採用しない。

## 並行性を制御する

- read-only auditはtargetごとに並行してよい。
- local実装はcurrent planの入口条件を満たし、変更pathとworktree所有が重複しないtargetだけ許可する。
- 採用済み展開順や依存gateを「worktreeが分かれている」だけで迂回しない。
- 最初の3問は独立recipeを保ち、共通libraryを先回りして作らない。
- 他の`kakomon*/**`、特に`kakomon14/**`を変更しない。repository-wide変更が必要なら別planへ分離する。

## runtime方針を固定する

- GoはApplicationとbenchmarkの両方で`1.26.6`を第一かつ唯一の実装候補とする。
- version文字列、official archive URL、architecture別SHA-256、mise config/lock、Goss、provenanceを同じidentityへ束縛する。
- Go 1.26.6で非互換なら旧versionへ自動fallbackせず、component別の失敗証拠を示して停止する。
- KAKOMON14の1.26.6整合とcurrent planが要求する再検証が統合されるまで、依存する新規recipeをimplementへ進めない。
- Node.jsは対象upstreamの証拠からexact versionを決める。`latest`、`lts`、major/rangeだけの指定をartifact入力にしない。

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

1. base branch、full SHA、clean状態、upstreamとのahead/behindを記録する。remote更新が必要なら勝手にpull/rebaseしない。
2. existing worktree、branch、同名path、active ownerとの衝突を確認する。
3. branchを`codex/<canonical-slug>-ami-recipe`、worktreeを`/private/tmp/isuren-mondai-<canonical-slug>-ami-recipe`の形で提案する。衝突時は名前を推測で再利用せず停止する。
4. exact base SHAからworktreeを作る。
5. main checkoutにだけ存在するignored audit cacheの絶対pathをpromptへ渡し、worktree側へcopyしない。

branch名へ必ずcanonical slugを含める。すでに別sessionが所有するworktree、branch、VM、artifactへ触れない。

## handoff promptを作る

[handoff prompt契約](references/handoff-prompt-contract.md)を完全に読み、placeholderを可能な限り実値へ解決して1つのcopy-ready promptにする。promptの前に次を短く示す。

- 推奨model / reasoning effortと選定理由
- mode（`audit`または`implement-through-all-sh`）
- worktreeの絶対path、branch、base SHA。prompt-onlyなら`not-created`
- implementation readinessとblocker

入口条件が不足する場合も、調査を進められるならaudit promptを返す。`all.sh` sliceの完成はAMI完成ではないため、完了ラベルを`all-sh-slice-committed`、`ready-to-merge-main`、`merged-to-main`のいずれかに限定する。

## 成果をレビューする

[review契約](references/review-contract.md)を完全に読み、対象worktreeの差分とraw evidenceを独立に確認する。別sessionの完了報告だけを証拠にしない。

- まずblocking finding、次にmajor/minor finding、最後に良い点と安全な次の一手を示す。
- findingがなければ明言し、残る未検証gateを列挙する。
- `all.sh`が存在するだけで完成にしない。呼び出すすべてのstep、mise identity、source provenance、Goss、frontend/benchmark順、fail-fastを確認する。
- 実施していないOrb、Golden、standalone、AMI、fresh boot、product gateを`not-run`のまま保つ。

## Git統合と外部検証を分ける

- 別セッションへtargetの変更許可pathだけを明示し、検証後の`git add -- <exact paths>`と`git commit`を追加の人間確認なしで許可する。`git add .`、`git add -A`、許可path外のstageを禁止する。
- commit前にstatus、staged stat、staged full diff、`git diff --staged --check`を確認させる。無関係な既存差分をcommitへ含めない。
- commit後に[review契約](references/review-contract.md)でセルフレビューし、blocking/major findingが残らず、必要validationがGreenの場合だけ`ready-to-merge-main`とする。
- main統合直前にremoteをread-onlyで更新し、main worktreeのclean状態、ahead/behind、他sessionのactive owner、resource guard、topicとの差分を再確認する。mainまたはtopicに所有不明の差分があれば停止する。
- topicがcurrent mainを含まない場合はtopic worktreeでmainをmergeし、競合なしの場合だけ同じvalidationとセルフレビューを再実施する。競合を推測で解決しない。
- main worktreeでは`git merge --ff-only <topic-branch>`だけを許可する。fast-forwardできなければ停止し、merge commitをmain上で作らない。
- 統合後にtopic HEADがmainのancestorであること、mainのstatus、HEAD、変更範囲を確認して`merged-to-main`と報告する。worktreeやbranchを自動削除しない。
- AIはpushしない。人間がpushし、remoteにexact main commitが存在することを確認する。
- EC2内で`git clone`して試すverify promptはpush後にだけ作る。local-only commitをclone可能と扱わない。
- `aws-bastion`のcurrent task定義を再読し、namespace入力が実際にtaskへ届くことをread-onlyで確認する。現状の`up-bastion`は`STACK_NAME`を入力として読まず、`mise.toml`の固定`BASTION_STACK_NAME`はshell側の同名変数を上書きするため、専用prefixを指定可能と扱わない。
- namespace入力を受け取れない場合は外部検証を止め、`BASTION_STACK_NAME = { default = "aws-bastion" }`またはtask argument等へ変更する別scopeを提案する。`mise.local.toml`を黙って作らない。
- EC2起動やAMI build前に、account、region、namespace、費用上限、TTL、exact stack、cleanup ownerとcommand、秘密の受け渡し、人間承認を確定する。
- AIが対話式cleanupを使えない場合はexact stack nameを指定する手順を別途提示する。cleanup確認まで外部gateを完了扱いにしない。
