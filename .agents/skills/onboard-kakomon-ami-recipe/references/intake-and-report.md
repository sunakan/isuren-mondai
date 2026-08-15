# 入力・報告契約

## 必須入力

作業開始時に次を表にする。不明な値は推測せず`decision-required`または`evidence-missing`とする。

| 分類 | 必須入力 |
|---|---|
| identity | edition、Qualify/Final等のvariant、Go版など対象実装 |
| provenance | official upstream URL、exact commit/tag、license/notice |
| audit evidence | ローカルaudit cloneの絶対pathとHEAD/remote、参考実装の絶対pathとprovenance |
| artifact | architecture、provider、OS/base image方針、edition固有recipe identity |
| topology | compact topology、canonical topology、各nodeのrole/network/port |
| benchmark | 配置先、build/実行方法、target指定、result/failureの構造、必要データ |
| runtime | 統合済みKAKOMON14比較元、upstream指定、採用候補、checksum/lock方針 |
| frontend | build要否、runtimeの意味、package manager、lockfile、command、生成物、配置先 |
| operations | Orb/AWS resource namespace、費用上限、TTL、cleanup条件・担当、外部操作の承認範囲 |

ローカルaudit cloneは調査用cacheであり、build provenanceではない。`tmp/all-kakomon`を含むcacheの現在HEADを、そのままartifactの正本へ昇格しない。build sourceはofficial URLとexact commit/tagに固定し、recipeから再取得可能にする。

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
