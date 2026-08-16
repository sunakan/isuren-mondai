# 検証gate

## gateを独立して記録する

| gate | 最小証拠 | このgateだけでは証明しないもの |
|---|---|---|
| `orb-recipe-green` | fresh Orb VMでfixed cloud-init、同一`all.sh`、Gossが手動修正なしで完走 | seal/clone、benchmark lifecycle、AWS |
| `orb-golden-green` | seal済みcandidateとfresh cloneのidentity、service、reboot | standalone result、製品経路、AWS |
| `orb-standalone-green` | Orb compact topologyのnormal result、valid failure、reset、recovery、reboot | canonical topology、Portal/`isu`、AWS |
| `orb-product-green` | Orb canonical topologyでPortal/`isu`、mTLS/SSE、result保存、restartを確認 | AWS固有境界 |
| `ami-build-green` | 同じfixed recipe digestとexact AWS入力からAMIを作成 | fresh boot、benchmark、製品経路 |
| `ami-fresh-boot-green` | fresh EC2のidentity、Goss、service、reboot、standalone benchmark、AWS固有bootを確認 | Portal/`isu`製品経路 |
| `aws-product-green` | versioned AWS profile、canonical topology、Portal/`isu`、mTLS/SSE、result/restart、AWS固有境界、cleanup | 別region/architecture/profile |

各gateへstatus（`not-run`/`blocked`/`failed`/`green`）、recipe digest、artifact ID、region、architecture/provider、topology、実行時刻、raw evidence、失敗、cleanupを記録する。AWS gateのregionは`ap-northeast-1`へ固定する。前段のGreenを後段へコピーせず、別regionのGreenも流用しない。dirty debug VMの成功をartifact昇格証拠にしない。

## verify開始前のartifact gate

外部VM/EC2へ変更を加える前に、local worktreeがcleanで、検証対象recipe commitがremote repositoryからexact SHAで取得可能であることを確認する。local HEADとremote mainの完全一致は要求しない。recipeがexternal frontendを要求する場合だけremote tag/公開Release/期待asset/published SHA-256を確認し、target-scoped `latest` selectorなら実際に解決されたtag/digestも記録する。workflowまたはReleaseがない場合は`blocked`としてpartial provisioningを始めない。

local `dist/`、別targetのRelease、過去のdownload済みarchiveを代用しない。公式source/dataやofficial prebuilt frontendをbuild instance内でexact identityから取得する契約と、こちらでfrontendをbuildしてCI/Release配布する契約を別々に守る。前者ではlocal `dist/`が存在しなくても正常とする。

## 外部操作preflight

Orb/AWS/GitHub等の外部状態を調査または操作する前に、リポジトリ指定のexternal-operation preflight Skillまたは同等の正本手順を適用し、次を確定する。read-only調査も対象に含める。

- 実施するgateと、実施しないgate
- account/provider、固定AWS region `ap-northeast-1`、architecture。暗黙のdefault regionを使わない
- 衝突しないresource namespace、所有session、対象VM/stack/image
- read-onlyかmutationか、実行command、必要権限
- 費用見積り・上限、TTL、停止時刻
- cleanup command、削除対象、担当、失敗時の回収方法、残存確認command
- 秘密をchat、argv、log、artifactへ出さない受け渡し方法
- 人間の明示承認

どれかが欠ける、またはAWS側で`ap-northeast-1`以外が選ばれている場合は外部操作を開始しない。既存resourceを名前の類似だけで再利用・削除しない。別session所有のVM、worktree、AMI、volume、stack、artifactへ触れない。AWS cleanupも作成時と同じ`ap-northeast-1`へ限定する。

AWS/SSMではaccount、instance ID、instance type、AMI ID、architecture、OS/version、private/public IP、SSM Onlineをread-onlyで照合する。credential processがhost keychainを必要としてsandbox内で失敗した場合は、secretを出力せず必要command prefixだけをscoped escalationする。

stop/start、reboot、`cloud-init clean`、既存instanceでの再provisioningをfresh stateと呼ばない。fresh recipe証拠には未provisioned base imageから作った新規VM/EC2を使い、既存instanceの再実行はidempotency/upgrade smokeとして別に記録する。

## lifecycle検証

standalone/product gateでは少なくとも次を別ケースで観測する。

1. fresh stateからnormal benchmarkが完了し、最終resultを回収できる。
2. 意図的なvalid failureでfailure result、stdout/stderr、exit semanticsを回収できる。
3. resetが定義対象だけを初期化し、service/dataを期待状態へ戻す。
4. recovery後にnormal benchmarkが再び完了する。
5. reboot後にidentity、enabled/running、DNS/TLS/port、data保持、benchmarkが契約どおりである。

provisioning完走、seal直後Goss、reboot後stateを別々に回収する。sealed Gossがclone固有`env.sh`やTLS不在を要求する場合、reboot後はfinalizerがそれらを再生成したことを別command/specで確認し、同じGoss specを無条件に再利用しない。

`curl -k`成功はserver HTTPSの証拠に限定する。browser UIはclient DNS、TCP 443、proxy/firewall、local-network permission、certificate扱いを別に確認する。benchmark timeoutはinstance resource不足でも起こるため、instance type、CPU/load、timeout、result JSONを記録し、十分なresourceで再現する前にApplication defectと断定しない。

Gossは単一hostの状態oracleに限定する。benchmark、multi-node、reset/recovery、reboot、Portal/`isu`製品E2Eの代替にしない。

## cleanup gate

外部検証はcleanup確認まで完了扱いにしない。namespace配下のVM/instance、disk/volume/snapshot、AMI、network/stack、temporary key/secret、local一時artifactを列挙し、計画した保持対象以外が残っていない証拠を取る。

cleanupに失敗した場合はgate本体が成功していても`cleanup-pending`を併記し、対象identity、費用リスク、次の安全な回収手順を報告する。
