# 入力・報告契約

## 必須入力

作業開始時に次を表にする。不明な値は推測せず`decision-required`または`evidence-missing`とする。

| 分類 | 必須入力 |
|---|---|
| identity | edition、Qualify/Final等のvariant、Go版など対象実装 |
| provenance | official upstream URL、exact commit/tag、license/notice |
| audit evidence | main source cacheとworktree-local mirrorの絶対path、HEAD、remote、clean状態、expected official identityとの一致、bootstrap方法、top-level Gitのignore状態、参考実装の絶対pathとprovenance |
| managed source | `upstream/<official-repo-name>`のbaseline、cacheからrsyncするsubpath、取り込み・除外範囲、local変更、画像・静的asset・`sql/`・初期データbundleのmanifest / checksum |
| artifact | Ubuntu 26.04 arm64、AWS region `ap-northeast-1`、provider、同regionのexact base image ID方針、edition固有recipe identity、非互換時の停止証拠 |
| hostname/TLS | upstreamの競技用domain、`isuren.internal`写像、DNS/hosts・proxy・SAN・cookie・benchmark整合、自己署名fixtureまたは本物の秘密の境界 |
| topology | compact topology、canonical topology、各nodeのrole/network/port |
| benchmark | 配置先、build/実行方法、target指定、result/failureの構造、必要データ |
| runtime | 統合済みKAKOMON14比較元、upstream指定、採用候補、checksum/lock方針 |
| frontend | build要否、runtimeの意味、package manager、lockfile、command、生成物、配置先 |
| operations | Orb/AWS resource namespace、AWS region `ap-northeast-1`、費用上限、TTL、同regionでのcleanup条件・担当、外部操作の承認範囲 |

implement worktreeでは、作成直後にmain checkoutのread-only source cacheを検証し、clone全体を同名の`tmp/all-kakomon/<official-repo-name>`へ`rsync -a`する。bootstrapだけは複製先でGit identityを再検証するため`.git/`を含める。複製先はgitignore対象の一時cacheであり、stage、commit、merge payloadに含めない。存在したままのlocal main統合を許し、worktree cleanup時に破棄してよい。

以後はworktree-local mirrorをread-onlyのaudit / import cacheにする。別sessionはofficial repositoryを再clone、fetch、pullせず、main source cacheはidentity再確認以外のcontent audit / importに使わない。両cacheのorigin URL、full HEAD、clean状態がexpected official identityと一致する場合だけ対象subpathを`rsync`する。不一致ならcacheを変更せず、人間による更新待ちとして停止する。

cache自体はbuild provenanceではない。保守codeはcommit済みmanaged source、非commit asset/dataはofficial URL・exact commit・file manifest・SHA-256を持つ固定bundleへ変換する。clean clone、cloud-init、AMI buildが`tmp/all-kakomon`を直接参照してはならない。

参考実装は構成・差分発見の証拠であり、official provenanceの代替ではない。統合済みKAKOMON14は構造とruntime比較の基準に限り、未統合worktreeや一時生成物を取り込まない。

## 証拠ラベル

各結論へ次のいずれかを付ける。

- `observed`: 指定ファイル、Git metadata、実行済み検証結果から直接確認した。
- `inferred`: 複数のobserved evidenceから推論した。推論理由を添える。
- `evidence-missing`: 必要な証拠を見つけられない。
- `decision-required`: 複数案またはpolicy判断があり、人間の決定が必要である。

`observed`には可能な限り絶対pathと行番号、commit、command/resultを添える。Git revisionはofficial source、audit clone、参考実装、統合済み比較元のすべてでfull SHAを記録し、短縮SHAをartifact identityに使わない。参考実装の値と対象upstreamの値が衝突した場合は両方を示し、official upstreamを優先して差を未決判断へ送る。

auditの推奨案は`recommendation`と明記し、採用済み入力やGreen条件として扱わない。候補を一つに絞っても、互換性証拠または人間の判断が欠ける限りstatusは`decision-required`のままにする。

## モード別の成果物

### audit報告

1. scopeとread-only宣言
2. intake表
3. provenance
4. service/package/runtime/frontend matrix
5. benchmark/result/network contract
6. compact/canonical topology
7. reset、failure、recovery、reboot contract
8. recipe file別の責任分担案
9. verification gateとcleanup境界
10. `decision-required`、`evidence-missing`、停止条件
11. 次に安全に進めるモード

`audit-complete`はチェックリストの調査と報告が完了したことだけを表す。必須入力が確定し実装可能である意味には使わず、`implementation-readiness`を`ready`/`blocked`で別に報告する。

### plan報告

- edition/variant固有の変更pathと非変更path
- 依存順、Red/Green、検証回数、受け入れ条件
- 固定する入力manifestとartifact identity
- 各gateの入口条件、出口証拠、cleanup
- 人間が決める項目。未決ならdraft

### implement/verify報告

- branch、HEAD、worktree状態
- 変更ファイルと責務、許可範囲との差分
- 実行した検証と結果
- gateごとの状態。未実施は`not-run`
- cleanup結果と残存resource
- 未決判断、停止条件、次の安全な一手

`planned`、`observed`、`Green`を混同しない。実行していない検証、別provider、別architecture、別topologyを成功扱いにしない。
