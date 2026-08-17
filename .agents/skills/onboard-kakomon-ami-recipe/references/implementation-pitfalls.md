# 実装時によくある落とし穴

kakomon12-qualify onboardingのimplement/verifyで実際に踏んだ問題と対処。次のtargetでも同種の原因になりうるため、`implement`/`verify`の各stepで先回りして確認する。

## Goのビルド対象を公式Makefile/Dockerfileの`-o`引数と一致させる

対象ディレクトリ直下の`.go`が`package main`とは限らない。ライブラリ(`package <name>`)が直下にあり、実際のエントリポイントは`cmd/<name>/main.go`という配置がある(isucon12-qualifyのwebapp/goが該当)。

- `go build -o X .`を`package main`でないディレクトリに対して実行すると、実行可能ELFではなくGoパッケージのアーカイブ(ar形式、`!<arch>`マジックナンバー、`readelf`が「Go binary file」と報告する)が生成される。パーミッションも新規実行ファイルの標準(0755)ではなく0644になる。
- systemd `ExecStart=`でこれを起動すると`Exec format error`(`status=203/EXEC`)で再起動ループする。
- `chmod +x`では直らない(中身が実行可能形式でないため)。真因はビルド対象の取り違え。
- 対策: 公式`Makefile`/`Dockerfile`の`go build`行を必ず確認し、`.`ではなく実際に指定されているpackage path(`./cmd/X`等)へ揃える。ローカル検証task(`test-go`等)のビルド対象も同じpathへ揃え、AMI内で実際にビルドされるものと一致させる。

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
