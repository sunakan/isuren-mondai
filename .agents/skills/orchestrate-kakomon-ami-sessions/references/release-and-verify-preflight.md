# Releaseと外部verifyのhandoff契約

## frontend delivery gate

current planがfrontendをAMI外のCI/Release artifactとして配布する場合、repository実装と配布を別gateにする。

1. target固有のbuild script、ignore済み出力directory、manifest、license、archive名を固定する。
2. `.github/workflows/release-<canonical-slug>-frontend.yml`をtargetの変更許可pathへ明示的に含める。build scriptだけ存在してworkflowがない状態をverify-readyにしない。
3. workflowのtag filterを`<canonical-slug>-frontend-v*`へ限定し、別targetのtagで発火させない。
4. 人間push後、remote tag、公開Release、期待asset名、asset digestをGitHub API等でread-only確認する。local `dist/`、過去のterminal出力、別targetのReleaseを代用しない。
5. provisioning/Packerへexact tagとSHA-256を渡す。ReleaseがなければEC2/VMを変更する前に`blocked`で停止する。

`all-sh-slice-committed`はrepository実装の完了、`frontend-release-published`はremote配布の完了、`verify-ready`は検証対象recipe commitがremoteから取得可能で必要なReleaseが存在する状態として分ける。local mainとremote mainの完全一致は要求しない。Release発行はGitHub writeなので、人間の承認なしに実行しない。

公式source/dataをbuild instance内で取得する方針と、frontendをCIでbuildしてRelease配布する方針を混同しない。ローカルPCへ公式assetを保持しない場合も、frontend生成物をAMI内buildへ勝手に変更しない。

official repositoryがprebuilt frontendをcommitしており、こちらで再buildしない方針を採用した場合は、CI/Release gateではなくAMI内直接取得gateを使う。official URL、exact commit、Git tree、file manifest、SHA-256、licenseを固定し、Node.js/package manager/local `dist/`を不要にする。activeな絶対domain依存が見つかった場合は生成済みassetを書き換えず停止する。

## binary tracking gate

commit前に、少なくとも次を独立に確認する。

- `git ls-files`で`artifacts/`、`dist/`、frontend build出力、画像・archive・database dumpが追跡されていない。
- `git diff --staged --numstat`の`- -`、新規fileの拡張子・size・`file`判定からbinary追加がない。
- 画像や生成物がworking treeへ存在しても、ignore対象でstage/commit/merge payloadへ含まれない。
- binaryを追跡した方がよいと判断した場合はstage前に停止し、人間へ相談する。

すでにbinaryがcommit済みなら、独断でhistory rewrite、reset、追跡解除、削除をしない。対象commit/file/sizeと回復案を示して人間へ戻す。

## AWS/Orb verify handoff

外部mutation前に次を順番どおり確認する。

1. local worktreeがcleanで、検証対象recipe commitがremote repositoryからexact SHAで取得可能である。local mainとremote mainの完全一致は要求しない。
2. external frontendなら上記delivery gateが`frontend-release-published`である。
3. account/provider、region、resource ID、owner、費用上限、TTL、停止時刻、cleanup ownerを固定する。
4. AWSは`ap-northeast-1`を全commandへ明示し、instance ID、AMI ID、instance type、architecture、OS version、SSM Onlineをread-onlyで照合する。
5. 既存instanceを使う場合も、対象以外のinstance/volume/AMI/stackへ触れない。削除・停止を依頼されていなければ行わない。
6. provisioning、sealed Goss、reboot後stateを別々に回収する。前の成功を次へコピーしない。

SSM接続を利用者へ引き渡す場合は、確認済みregionとinstance IDを使う`aws ssm start-session`のexact commandを示し、participant shellはsession内の`sudo -iu isuren`等、採用userへlogin shellとして切り替える手順を分けて示す。public IP、SSH user、暗黙regionを推測で混ぜない。

AWS credential processがhost keychain等を必要としてsandbox内で失敗した場合は、secretを表示せず、必要なread/write command prefixだけをscoped escalationする。credentialをargv、chat、log、artifactへ書かない。

## fresh stateの意味

stop/start、reboot、`cloud-init clean`、既存instance上での`all.sh`再実行はfresh provisioningの証拠ではない。導入済みpackage、旧runtime、旧設定、cacheが残るためである。

- 新しいbase imageから作った未provisioned VM/EC2だけをfresh recipe証拠にする。
- 既存instanceでの再実行はidempotency/upgrade smokeとして別ラベルにする。
- dirty debug instanceの成功をAMI fresh-boot Greenへ昇格しない。

## client、server、benchmarkを分離する

- `curl -k`成功はserver-side HTTPS応答の証拠であり、browser UIの証拠ではない。
- browserの`ERR_CONNECTION_REFUSED`はDNS解決、TCP 443、proxy/firewall、macOS local-network permission、certificate扱いをclient側で分離する。curl成功だけでbrowser問題をnginx障害と断定しない。
- browser確認を依頼されたら、public IPだけでなくnginxの`server_name`とHost header契約を読み、必要な`/etc/hosts`行とURLを報告する。IP直打ちで同じvirtual hostへ入れると推測しない。
- benchmarkのtimeoutはApplication不具合だけでなくCPU/instance size不足でも起きる。instance type、CPU/load、timeout、result JSONを記録し、十分なresourceでの再現前にcode defectと断定しない。
