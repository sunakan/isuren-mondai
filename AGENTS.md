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

## 過去問コードの取り込み(vendor)方針

各過去問ディレクトリ(`kakomon14/`等)配下に`vendor/`を置き、取り込み元リポジトリ名でディレクトリを分ける
(例: `kakomon14/vendor/isucon14/`。将来的に`kakomon14/vendor/isucon14-portal/`等も同様)。

- vendor直下の名前は「isuren側の呼び名(kakomon14等)」ではなく「クローン元リポジトリ名」に揃える
- 各vendorディレクトリには取り込み元のLICENSEをそのままコピーする。コピーライト行がリポジトリごとに
  異なる(isucon14は「2024 ISUCON14 Contributors」、isucon14-portalは「2022 ISUCON」)ため、
  1つのLICENSEファイルに統合しない
- `packer/`・`provisioning/`・`cloud-init/`等の完全自作物にはisucon側のLICENSEを適用しない
  (このリポジトリ自体のLICENSEに従う)

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
- `runuser -u isuren -- <cmd>`は`.bashrc`を経由しないため、mise/pnpm等はフルパス
  (`/home/isuren/.local/bin/mise`)で呼ぶ必要がある。pnpmはさらにcwdからworkspace定義を探索するため、
  isurenが読めないディレクトリ(`/home/ubuntu/...`等)をcwdにしたまま実行すると`EACCES`になる。goの場合は
  `EACCES`ではなく`go.mod file not found`という別症状で現れる。回避策として、isurenのmiseインストール先
  (`/home/isuren/.local/...`は755で他ユーザーからも実行可)のバイナリをフルパス指定しつつ、実行ユーザーは
  ubuntuのままにする方法がある
  (例: `sudo -u ubuntu /home/isuren/.local/share/mise/installs/go/<version>/bin/go run . run ...`)
- pnpm 10以降はesbuild/@swc/core等のpostinstallスクリプトをデフォルトでブロックする(strictDepBuilds)。
  事前に承認内容を`pnpm-workspace.yaml`に書いておく必要がある
  (`kakomon14/provisioning/pnpm-workspace.kakomon14.yaml`で管理)
- t4g.small(メモリ1.8GiB、swap無し)は`pnpm install`のような重いビルドでOOM killerが発動しうる。
  恒久対応(swap追加等)は未着手

## コマンド実行の方針

- `packer build`・`aws cloudformation deploy`等、EC2インスタンス起動やAMI作成を伴う操作は
  課金・時間がかかるため、実行前に必ずユーザーに確認する
- `mise run down-verify-ami`はfzfでの一覧選択が前提でAIからは対話操作できない。
  aws-bastion側と同様、AIはawsコマンドで直接スタック名を指定して操作してよい
