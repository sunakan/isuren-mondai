# 実装時によくある落とし穴

kakomon12-qualify onboardingのimplement/verifyで実際に踏んだ問題と対処。次のtargetでも同種の原因になりうるため、`implement`/`verify`の各stepで先回りして確認する。

## Goのビルド対象を公式Makefile/Dockerfileの`-o`引数と一致させる

対象ディレクトリ直下の`.go`が`package main`とは限らない。ライブラリ(`package <name>`)が直下にあり、実際のエントリポイントは`cmd/<name>/main.go`という配置がある(isucon12-qualifyのwebapp/goが該当)。

- `go build -o X .`を`package main`でないディレクトリに対して実行すると、実行可能ELFではなくGoパッケージのアーカイブ(ar形式、`!<arch>`マジックナンバー、`readelf`が「Go binary file」と報告する)が生成される。パーミッションも新規実行ファイルの標準(0755)ではなく0644になる。
- systemd `ExecStart=`でこれを起動すると`Exec format error`(`status=203/EXEC`)で再起動ループする。
- `chmod +x`では直らない(中身が実行可能形式でないため)。真因はビルド対象の取り違え。
- 対策: 公式`Makefile`/`Dockerfile`の`go build`行を必ず確認し、`.`ではなく実際に指定されているpackage path(`./cmd/X`等)へ揃える。ローカル検証task(`test-go`等)のビルド対象も同じpathへ揃え、AMI内で実際にビルドされるものと一致させる。

## runtime配置pathは公式README/provisioningで確認し、独自の慣習(`bin/`等)で決め打ちしない

benchmark等のビルド成果物を`/home/isuren/bin/<name>`のようなsubdirectoryへ置くか、`/home/isuren/<name>`のようにhome直下へ直接置くかは、target固有の公式配置を確認せず「他のkakomonNがこうしていたから」で決めると本家とズレる。

- isucon12-qualifyの公式README.mdには「ベンチマーカーは`/home/isucon/bench`以下にビルド済みのバイナリがあります」と明記されており、`bin/`のようなsubdirectoryは存在しない。にもかかわらずimplement時に`/home/isuren/bin/bench`という独自subdirectory配置にしてしまい、後から本家と比較して気づいた。
- 既存targetの前例も統一されていない(kakomon13は`/home/isuren/bench`をhome直下に直接、kakomon9-qualifyは本家の`isucari`プロジェクト構造ごと保持しているため`bin/`配下)。「他のtargetがこうしているから」ではなく、`recipe-contract.md`の「upstreamのfilesystem構成を保つ」原則どおり、対象targetの公式README・provisioning(mitamae/ansible等)・Dockerfileが実際に示す相対pathをそのtargetごとに確認する。
- ビルド成果物の配置pathを変更した場合、provisioning step本体だけでなく、`goss.yaml`のfile checkと、そのpathを文字列で参照している他のstep/README/NOTICEも一致するまで揃っているか確認する(片方だけ直すと矛盾が残る)。
- **訂正(`orb-standalone-green`で判明)**: 上記の「`bin/`のようなsubdirectoryは存在しない」という読みは、「`/home/isucon/bench`を単一の平坦なファイルとして置く」ことまでは意味していなかった。実際にbenchを実行すると`../public/js`をcwd相対でopenするvalidation stepがあり、これは`bench`バイナリ自身が`public/`と兄弟関係にあるdirectory(`bench/`)から起動されて初めて解決するpathだった。READMEの文言だけで配置構造を確定させず、実際にbinaryを実行してcwd相対参照が解決するかまで確認する。

## GitHub Releaseの取得はgh CLIより素のcurlを先に試す

公開リポジトリのRelease assetは`https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`という直接URLで認証不要・`gh` CLI不要で取得できる(kakomon14/13のfrontend Release取得、`provisioning/80-frontend.sh`/`60-frontend.sh`が既にこの方式)。

- `ghtkn get <profile>`由来のトークンは、`gh release list`(GraphQL経由)は成功するのに、`gh release view`/`gh release download`/`gh api repos/.../releases/tags/*`(REST)は`403 Resource not accessible by integration`または`release not found`になることがある。原因はトークンのスコープかサンドボックスのネットワーク制限か切り分けられなかったが、再現性はある。
- AMI内(`provisioning/*.sh`)で`gh` CLIへ依存を追加する前に、まず対象リポジトリが公開かどうか確認し、公開ならcurl直接ダウンロードを優先する。`gh` CLI導入(`10-base.sh`でのAPT repository追加含む)はその分の攻撃対象・依存を増やすので、不要なら入れない。
- tag名にスラッシュが含まれていても(`data/20220712_1505-...`のような形式)、URLパスにそのまま埋め込めば問題なく解決する(GitHub側がスラッシュ入りtag名をサポートしている)。

## Gossの`port:`はIPv4のみを見る(IPv6リッスンを検出できない)

Goの`http.ListenAndServe(":PORT")`/echoの`e.Start(":PORT")`のようにhostを省略すると、環境によってはIPv6(`[::]`)としてバインドされ、`/proc/net/tcp`には現れず`/proc/net/tcp6`にのみ現れる。`ss -ltn`は両方見えるので惑わされやすい。

- Gossの`port: tcp:PORT: listening: true`はIPv4(`/proc/net/tcp`)のみを見るため、実際にはリッスンしているのに`false`と誤検知する。
- 対策: 実際の待受を`ss -ltn`または`/proc/net/tcp6`で確認し、IPv6のみなら`port: tcp6:PORT:`を使う。アプリ側のlisten host指定を変更してまでIPv4に寄せる必要はない(公式の挙動を変えることになるため)。

## `file`コマンドは対象イメージに入っていないことがある

`file <bin> | grep 'dynamically linked'`のようなGoss `command:`チェックを書く前に、対象イメージに`file`パッケージがインストールされているか確認する。未インストールなら`ldd <bin>`(多くの環境で標準搭載、動的リンクなら依存ライブラリ一覧を出力してexit 0、静的なら非0)で代替できる。

## `install -d`が暗黙に作る親ディレクトリはcleanup対象から漏れやすい

`install -d -m 0755 "${ROOT}/sub"`は`${ROOT}`も同時に作成する。ビルド後に`rm -rf "${ROOT}/sub"`だけ削除すると、`${ROOT}`自体は空のまま残る。Gossで`${ROOT}`の`exists: false`を期待している場合、削除は`${ROOT}`ごと行う。

## provisioningの変更とgoss.yamlの期待値はセットで見直す

一時的に追加したCLIツール(`gh`等)を後で削除した際、それに依存する`package: <name>: installed: true`のようなGoss期待値の削除を忘れやすい。provisioning stepを変更したら、対応するGoss項目(file/package/command/port)が今も正しいか都度確認する。

## 成功したOrb Golden Base VMを「不要になった検証用VM」として削除しない

`orb-recipe-green`(`mise orb:build-golden-base <target> --execute`)が成功すると`<target>-golden-base`という名前のVMがstopped状態で残る。これは失敗した試行の診断用VMとは違い、`build-orb-kakomon-golden-base`スキルの後続工程(`prepare-golden-base-clone`でisuren層を追加したcloneを作る)の元になる、保持すべきprovider-native artifactである。

- mainへのマージ完了やworktree/branchのcleanupと同じタイミングで「もう使わないだろう」と一緒くたに削除しない。既存の`kakomon13-golden-base`・`kakomon14-golden-base`・`kakomon9-qualify-golden-base`も同様に保持され続けている。
- 削除してよいのは、あくまで失敗した試行の診断用VM(名前が同じでも、対応するcommitがもう存在しない・再現性のない一時状態)であり、その判断も基本的に人間の確認を経てから行う。

## Orb VM内から`systemctl reboot`すると`orb exec`が応答しなくなることがある

`orb-golden-green`のreboot検証で、cloneしたOrb VM内から`systemctl reboot`(または`nohup systemctl reboot &`)を実行すると、`orb list`上は`running`に戻るのに`orb -m <vm> ...`(exec/run/shell)がその後何度リトライしても無応答(出力なし、exit 1)になることがあった。

- `orb stop <vm>` → `orb start <vm>`(Orb側からのVM制御)に切り替えると問題なく再接続でき、identity(machine-id/SSH host key/MySQL server UUID等)・サービスのenabled/active状態も正しく検証できた。
- reboot検証は最初から`orb stop`/`orb start`で行う方が安全。VM内部からの`systemctl reboot`はOrb環境特有の接続断を起こしうる(EC2実機でも同じ問題が起きるとは限らないが、Orbでの検証手段としては避ける)。

## benchmarker自身が実行時cwd相対で読むruntime input(鍵・fixtureデータ)は、他プロセスの配置pathへ埋没しやすい

`orb-standalone-green`(benchmark実走)で初めて発覚する種類の欠落がある。Gossは「ファイルが存在するか」を個別pathでチェックするだけで、「benchmarkerが実際に実行時カレントディレクトリから見つけられるか」は検証しない。

- isucon12-qualifyのbenchは`blackauth`と違い秘密鍵をgo:embedせず、実行時に`./isuports.pem`をcwd相対で`os.ReadFile`する(`bench/models.go`は`./benchmarker.json`/`./benchmarker_tenant.json`も同様)。provisioningは秘密鍵を`blackauth/`側にしか配置しておらず、bench起動時に`open ./isuports.pem: no such file or directory`で即失敗した。Gossは`blackauth/isuports.pem`の存在だけを見ていたため素通りしていた。
- さらに`bench/scenario.go`のvalidation stepは`../public/js`もcwd相対でopenする。これはbenchバイナリが`public/`と兄弟のdirectory(`bench/`)から起動されることを前提にしており、「`ISUREN_HOME`直下にbenchを平坦配置する」という当初の判断(上の「runtime配置path」項の訂正参照)とは両立しなかった。最終的にこのrecipeは`bench`を`/home/isuren/bench/bench`へ、鍵・fixtureをその同じ`bench/`directoryへ、`public/`を兄弟の`/home/isuren/public/`へ置く構成(公式repository rootの構造そのもの)に落ち着いた。
- 対策: 公式sourceで`os.ReadFile("./X")`・`os.Open("./X")`・`os.Open("../X")`のようなcwd相対読み込みをしている箇所を洗い出し、それぞれが要求する相対関係(同じdirectory内か、兄弟directoryか)を全て満たすように配置を決める。1箇所のcwd相対読み込みだけ見て「flattenして正しかった」と早期に結論を出さない。「配置したかどうか」ではなく「そのプロセスの実行時cwdから見えるか」で検証する。
- 同じセッションでinitial_data Release archiveの内部layoutも実際にdownloadして初めて判明した: `bench/benchmarker.json`・`bench/benchmarker_tenant.json`(bench runtime fixture)、`webapp/sql/admin/90_data.sql`(gitignore対象、`docker-entrypoint-initdb.d`規約で`01_`/`10_`の後に自動適用される admin tenant seed)が`initial_data/*.db`以外にも同梱されていた。`initial_data/*.db`の存在だけを確認して「archiveの中身を把握した」と扱わず、公式`Makefile`・`docker-compose.yml`のmount定義等、archiveを実際に消費している箇所を全て洗い出してから必須ファイルを確定する。
- benchmarkerのCLIオプション(例: `-target-url`)がどのhostname階層を期待するかも、READMEの例だけで決め打ちせず`option.go`のデフォルト値・`scenario.go`の実際の組み立てロジックを読む。isucon12-qualifyのbenchは`-target-url`に**base** hostnameを渡す前提で、`admin.`prefixを自分で付加する(`b.Scheme+"://admin."+b.Host`)。admin hostnameを直接渡すと`admin.admin.<host>`という二重prefixになり、Host header不一致で401になる。
- webapp/goがCGOで`mattn/go-sqlite3`をリンクしていても、`sqlite3` CLIコマンド自体は別途OSパッケージとして必要な場合がある(`createTenantDB`が`sqlite3 <path> < schema.sql`をshell out)。「Goのsqlite3ドライバをCGOでビルドできた」ことと「sqlite3 CLIが入っている」ことは別の確認事項であり、実際にテナント作成APIを叩くまで欠落に気づけなかった。

## 手動でcloud-init runcmdをEC2上に再現するときは、cwdを変えないgit呼び出しを使う

AMI build前にfresh EC2でprovisioningを手動先行検証する場合、SSM経由で`git clone`相当をcloud-initの`runcmd`と同じ手順で再現する。この際`cd <dir> && git remote add ...`のように`cd`でchainingすると、SSMの1コマンド内でcwdが後続コマンドへ持ち越され、`all.sh`内の`mise`呼び出しがcwd配下の無関係な`mise.toml`(例: isuren-mondaiリポジトリ自身のroot mise.toml)を検出して`mise trust`エラーを出すことがある。

- 実際のcloud-init `runcmd`は各項目が独立した`git -C <dir> ...`呼び出しでcwdを一切変えないため、この問題は起きない。`cd`によるchainingは手動再現側だけの副作用であり、recipe自体のバグではない。
- 対策: 手動再現でも`git -C <dir> ...`または`git --git-dir=<dir>/.git --work-tree=<dir> ...`のようなcwd非依存の呼び出しに揃え、`cd`でcwdを変更しない。エラーが出た場合、それが本物のrecipeバグか手動再現方法のアーティファクトかを、実際のcloud-init手順との差分に立ち返って切り分ける。

## EC2初回起動直後はbackground処理がapt lockを保持していることがある(Orbでは起きない差分)

fresh EC2起動直後に`apt-get install`を含むprovisioningを走らせると、`E: Could not get lock /var/lib/dpkg/lock-frontend`で即失敗することがある。cloud-init自身のパッケージ更新処理やunattended-upgradesがバックグラウンドでdpkg lockを保持しているため。Orb VMではこの起動直後のタイミング差が発生しなかった(Orbの起動シーケンスとの違いと推測)。

- 対策: `cloud-init status --wait`または一定時間の待機後に再試行する。Packerの`amazon-ebs` provisionerは`cloud-init status --wait`を挟んでいるためこの問題を自然に回避しているが、手動でSSM経由に先行検証する場合は明示的に待つ必要がある。

## AMI root volumeは他targetの値を転用せず、実測usageとbase AMIスナップショット下限から決める

先行するtargetが`volume_size = 16`(またはそれ以上)を使っていても、そのまま新targetへ転用しない。

- base AMI(Ubuntu公式cloud image)自体のsnapshotサイズがvolume_sizeの実質的な下限になる(それ未満は指定できない)。`aws ec2 describe-images`で確認できる。
- 実際にfresh EC2上で`provisioning/all.sh`を走らせ、完了直後のdisk使用量(`df`等)を実測してから、base AMIのsnapshotサイズと比較して十分な余裕があるか判断する。
- 練習用の1bench-1web/bastion等、AMIから起動する側のスタックがAMIより大きいroot volumeを指定していれば、Ubuntu公式cloud imageのcloud-init `growpart`/`resizefs`が起動時にfilesystemを自動拡張するため、AMI自体を大きく作り込む必要はない。
