# Provisioning template skeletons

これらは、`kakomon9-qualify`、`kakomon13`、`kakomon14`で揃えた責務、コメント、ログ、
raw telemetryの形を、新しいtargetへコピーするための非実行テンプレートです。

| template | 共通責務 | コピー後にtarget側で決めるもの |
|---|---|---|
| `lib.sh.tmpl` | account default、log、root/file check、時刻・disk観測 | canonical slug |
| `all.sh.tmpl` | input検証、root-backed temp、fail-fast step、raw telemetry、完走marker | target step列と追加input |
| `10-base.sh.tmpl` | Ubuntu 26.04 arm64確認、共通network/archive tool、timezone、sysctl、limits | target固有packageとhost設定は別step |
| `20-user.sh.tmpl` | UID/GID 1100のaccount、home、sudoers、mise directory | target固有directoryは別step |
| `30-runtime.sh.tmpl` | checksum付きmise導入、config/lock、無人install | 採用versionとlockの互換性証拠 |
| `40-mysql.sh.tmpl` | package、enable/start、readiness | DB/account/schema/dataは別step |
| `41-mysql-target.sh.tmpl` | optional MySQL extensionのfail-closed骨格 | target固有daemon設定など |
| `90-nginx.sh.tmpl` | package導入、default site除去、設定前停止 | vhost/TLS/proxyはextensionまたは別step |
| `91-nginx-target.sh.tmpl` | optional nginx extensionのfail-closed骨格 | target固有設定、検査、起動、healthcheck |
| `99-verify.sh.tmpl` | checksum付きGoss runner、失敗時journal | `goss.yaml`と対象unit |

## Optional extensionの扱い

`41-mysql-target.sh.tmpl`と`91-nginx-target.sh.tmpl`は、必要な場合だけコピーします。独自処理がなければ
ファイルごと省略し、空stepやno-opを作りません。コピーした場合はfail-closed行を実装へ置き換え、
`all.sh`へ`run_step`を明示的に追加します。存在確認による自動実行は行いません。

MySQLのschema・初期データがofficial source取得後に必要なら、`41`へ詰め込まず、実行順を表す
`60-initdb.sh`や`80-database.sh`などのtarget-owned stepにします。nginx設定をservice集約stepで扱うtargetは、
`91-nginx-target.sh`を作らず、そのstepを`all.sh`へ明記します。

## コピー後の必須作業

- `10-base.sh`にはMySQL/nginx/DNSや`unzip`等を足さず、consumerが限定されるpackageはtarget-owned stepへ置く
- `all.sh`へsource、Application、frontend、benchmark、service、seal等の実在stepを順番どおり追加する
- `99-verify.sh`の`JOURNAL_UNITS`をtarget serviceへ置き換え、target-owned `goss.yaml`を用意する
- `mise.ami.toml`と`mise.ami.lock`をtarget側へ置き、version/checksumを互換性証拠とともに固定する
- package installとDB/service初期化の責務重複がないことを確認する
- templateを直接参照するcloud-init、Packer、runtime pathがないことを確認する

テンプレートはmode `0644`のまま保持します。コピー後のmodeは、targetが`bash file`で呼ぶか直接実行するかに
合わせてtarget側で決めます。
