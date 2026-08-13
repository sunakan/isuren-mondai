# AGENTS.md

## このリポジトリでやろうとしていること

ISUCON過去問(isucon14等)をそれぞれGo実装だけに絞り、Packerで自分用のAMIとして焼いて保守する。
詳しい方針は`../docs/isuren-mondai-strategy.md`(aws-bastionリポジトリ側)を参照。
コマンドの使い方は`README.md`を参照。

## このリポジトリの位置づけ

`aws-bastion/isuren-mondai/`に配置されているが、aws-bastionとは別の独立したgitリポジトリ
(aws-bastion側の`.gitignore`で無視されており、aws-bastionのgit操作には一切影響しない)。
このディレクトリでの変更は、このディレクトリをカレントディレクトリにしてcommitする。

タスク管理(todo/completed)は現状aws-bastion側の`../docs/plans/kakomon14/`で行っている。
着手中/完了タスクを確認する際はそちらを見る。

## 現在地(2026-08-13時点)

bastion上での試行錯誤(`aws-bastion/scripts/kakomon14/`)によるネイティブ構築フェーズは完了済み。
まだこのリポジトリへのスクリプト移設は行っていない
(`../docs/plans/kakomon14/todo/20260813100000-migrate-scripts-to-isuren-kakomon.md`が最優先タスク)。

## 過去問コードの取り込み(upstream)方針

各過去問ディレクトリ(`kakomon14/`等)配下に`upstream/`を置き、取り込み元リポジトリ名でディレクトリを分ける
(例: `kakomon14/upstream/isucon14/`。将来的に`kakomon14/upstream/isucon14-portal/`等も同様)。
GoLandがディレクトリ名`vendor`をGoのvendoring規約として誤認識し除外扱いにするため、`upstream`という
名前を採用している。

- upstream直下の名前は「isuren側の呼び名(kakomon14等)」ではなく「クローン元リポジトリ名」に揃える
- 各upstreamディレクトリには取り込み元のLICENSEをそのままコピーする。コピーライト行がリポジトリごとに
  異なる(isucon14は「2024 ISUCON14 Contributors」、isucon14-portalは「2022 ISUCON」)ため、
  1つのLICENSEファイルに統合しない
- `packer/`・`provisioning/`・`cloud-init/`等の完全自作物にはisucon側のLICENSEを適用しない
  (このリポジトリ自体のLICENSEに従う)

## upstream取得(sparse-checkout)の実装上の注意点

kakomon14のupstream移行(`50-source.sh`)で実際にハマった点。他の過去問を追加する際にも当てはまる。
なお`50-source.sh`内では、isuren-mondai自身が保持するこの取り込み済みコードを`UPSTREAM_*`、
isucon14公式リポジトリから読み取り専用データを直接取得する側を`ISUCON14_*`と呼び分けている
(前者のディレクトリ名`upstream`と、後者が指す「本家」概念が別物であるため)。

- cone modeのsparse-checkoutは指定パスだけでなく**リポジトリルート直下のファイルも自動的に含む**。
  isuren-mondai自身を取得元にする場合、`mise.toml`(Packer/AWSタスク定義)のような
  無関係なファイルも一緒に取得されてしまう。`mise.toml`は`~/webapp/go`等でmiseを実行する際に
  ディレクトリ探索へ引っかかり「untrusted config」エラーの原因になるため、取得後に明示的に
  除去する必要がある(`50-source.sh`の`remove_upstream_root_mise_toml`参照)
- gitignoreの衝突で、ファイルが`git add`時に**静かに無視される**ことがある。2パターン確認済み
    - グローバルgitignore(macOSの`Icon`ルール等)が、大文字小文字を区別しないファイルシステム上で
      正当なディレクトリ名(`icon/`等)と衝突する
    - 取り込んだディレクトリ自身の`.gitignore`(先頭`/`なしのパターン、例: `bench`)が、
      同名の無関係なディレクトリ(`services/bench/`等)を意図せず無視する
    - 取り込み時は本家ツリーと`comm -23 <(find 本家 ...) <(git ls-tree ...)`のように突き合わせて、
      欠落ファイルがないか確認する運用にする
- symlinkの相対パス解決に注意。systemdの`WorkingDirectory=`がシンボリックリンクを指す場合、
  chdir後のプロセスの実体パスはreadlink先になるため、プロセスからの相対パス(`../sql`等)は
  シンボリックリンクの論理的な親ではなく**実体側の親ディレクトリ**で解決される。関連ファイルを
  別々の取得元からシンボリックリンクで束ねる場合、束ねる場所は実ディレクトリの内側に統一する
  (`~/webapp`配下の子要素ごとに個別symlinkを張る方式は相対パス解決を壊すため不採用。
  upstreamツリーの内側に`webapp/sql`へのsymlinkを差し込む方式にした)

## frontendのビルド・配布方針

frontendはAMI上ではビルドしない。t4g.small(メモリ1.8GiB、swap無し)では`pnpm install`のような
重いビルドでOOM killerが発動しうる上、node/pnpmをAMIに含めずに済む(対象言語をGoのみに絞る方針にも合う)。

- `kakomon14/scripts/build-frontend-release.sh`でローカル/CIビルドし、`kakomon14/dist/`に
  成果物(`kakomon14-frontend.tar.gz`・`frontend_hashes.json`・`frontend_files.json`)を出力する
- `scripts/github-release.sh`(過去問ごとに使い回せる汎用スクリプト)でGitHub Releaseへ公開する。
  タグは`kakomon14-frontend-v1.0.0`のように過去問+役割を接頭辞にする(1つのリポジトリで複数過去問の
  リリースを扱うため)
- AMI側(`80-frontend.sh`)は`FRONTEND_RELEASE_TAG`で固定したタグ(他の`*_COMMIT`系変数と同じ
  ピン留め方式)からダウンロードするだけ。`sunakan/isuren-mondai`はpublicリポジトリなので認証不要
- `frontend_hashes.json`・`frontend_files.json`はbenchがfrontendの整合性確認に使うファイルで、
  ビルドのたびに内容が変わるためgit管理していない(`kakomon14/upstream/isucon14/NOTICE.md`参照)。
  ダウンロードした最新版を`bench/benchrun/`に上書き配置する

## 見逃しがちな注意点(isucon14版)

aws-bastion上での試行錯誤で見つかった、ハマりどころ・Why not集。aws-bastion側の
`docs/plans/kakomon14/completed/`が将来失われても実装に困らないよう、ここに複製している。

- `bench/Dockerfile`はISUCON運営限定のプライベートECRイメージ(supervisor)に依存しており一般環境では
  ビルドできない。benchはホストで直接`go run`する
- `development/compose-go.yml`はfrontendの事前ビルド(`pnpm run build`)が前提。nginxが
  `frontend/build/client`をマウントするだけでビルドはしない
- ベンチ実行時の`context deadline exceeded`多発は、インスタンスのリソース不足(CPU)が原因のことがある。
  アプリのバグかリソース不足かの切り分けが必要
- `development/compose-go.yml`のコンテナ(特にnginxの8080番ポートマッピング)が起動したままだと、
  ネイティブの`isuride-go`等とポートが競合し再起動ループになる。ネイティブ構築を進める前に`docker ps`で
  止まっていることを確認する
- AMIのベースOS(Ubuntu 26.04 arm64)の`chown`はGNU coreutilsではなくuutils coreutils(Rust実装)で、
  `-h`/`--no-dereference`がexit 0を返すのに実際にはlchownしないバグがある。シンボリックリンクの
  所有者変更が必要な場面は要注意(通常ファイルへの`chown`は正常動作)
- `runuser -u isuren -- <cmd>`は`.bashrc`を経由しないため、mise等はフルパス
  (`/home/isuren/.local/bin/mise`)で呼ぶ必要がある(goのビルドで確認。AMI上ではpnpmは使わなくなった。
  下記「frontendのビルド・配布方針」参照)。isurenが読めないディレクトリ(`/home/ubuntu/...`等)を
  cwdにしたまま実行すると`go.mod file not found`になる。回避策として、isurenのmiseインストール先
  (`/home/isuren/.local/...`は755で他ユーザーからも実行可)のバイナリをフルパス指定しつつ、実行ユーザーは
  ubuntuのままにする方法がある
  (例: `sudo -u ubuntu /home/isuren/.local/share/mise/installs/go/<version>/bin/go run . run ...`)
- pnpm 10以降はesbuild/@swc/core等のpostinstallスクリプトをデフォルトでブロックする(strictDepBuilds)。
  事前に承認内容を`pnpm-workspace.yaml`に書いておく必要がある
  (`kakomon14/scripts/pnpm-workspace.kakomon14.yaml`で管理。frontendビルドはローカル/CI側でのみ発生する)

## コマンド実行の方針

- `packer build`・`aws cloudformation deploy`等、EC2インスタンス起動やAMI作成を伴う操作は
  課金・時間がかかるため、実行前に必ずユーザーに確認する
- `mise run down-verify-ami`はfzfでの一覧選択が前提でAIからは対話操作できない。
  aws-bastion側と同様、AIはawsコマンドで直接スタック名を指定して操作してよい
