# isucon14 upstream NOTICE

- 取り込み元: https://github.com/isucon/isucon14
- 取り込み時点のcommit: `53f8b627e040c30ebec600457c6c97da008b84b0`
- ライセンス: MIT (`LICENSE`参照。Copyright (c) 2024 ISUCON14 Contributors)

## 持ち込んだ範囲

- `webapp/go`(対象言語をGoのみに絞る方針のため、他言語(nodejs/perl/php/python/ruby/rust)は持ち込んでいない)
- `webapp/payment_mock`
- `webapp/openapi.yaml`
- `frontend`
- `bench`(ベンチマーカー本体。Goのみで完結し自分で保守しうるコードのため持ち込んだ。
  `go run . run --target ... -t 60`のように直接実行する)

## 対象外にしたもの

- `browsercheck/`・`envcheck/` — いずれもISUCON運営側の道具で、参加者側の環境では動作しない
  (詳細はdocs/plans/kakomon14配下の調査メモ、または会話ログ参照)
- `development/` — 全言語分のDocker Compose定義で、Goのみに絞る方針とは噛み合わない
- `bench/Dockerfile`・`bench/entrypoint.sh`・`bench/aqua.yaml` — ISUCON運営限定のプライベート
  ECRイメージ(`supervisor`)・AWS ECSのタスクメタデータAPIに依存しており一般環境では使えない。
  benchは`go run`で直接実行するためコンテナ化自体が不要
- `webapp/payment_mock/Dockerfile` — payment_mockはAMI上ではsystemdユニットからmise経由の
  `go build`成果物を直接起動する運用のため、コンテナ化自体が不要
- `bench/Taskfile.yml` — 本家の開発用ショートカット集。`gen-frontend`は
  `kakomon14/scripts/build-frontend-release.sh`で代替済み、`build-image`は上記Dockerfile依存、
  他のタスクも単なる`go run`/`go build`のラッパーで保守する価値が薄い

## 取り込んでいないもの

以下は「自分で手を加えない読み取り専用データ・アセット」のため、取り込まずAMI構築時に
本家(`isucon/isucon14`)から直接sparse-checkoutで取得する(`kakomon14/provisioning/50-source.sh`参照)。
js/css/ts等、将来構文が非推奨になった際に自分で保守する可能性があるコードとは取得元を分けている。

- `frontend/public` — 画像等の静的アセットで、リポジトリを重くするだけで編集対象にならないため

過去問によって画像等の置き場所は異なる(例: isucon13は`bench/internal/scheduler/images/`配下)ため、
この取り込まない対象パスは過去問ごとに個別判断する。

## コミット対象から外したもの

- `webapp/sql` — ローカルでのDBスキーマ確認用に`mise run kakomon14:refresh-upstream`で取り込むが、
  サンプルデータ(`3-initial-data.sql.gz`)が将来の過去問追加で肥大化しうるため`.gitignore`で
  コミット対象外にしている。AMI構築時は従来通り本家から直接sparse-checkoutで取得する
  (`kakomon14/provisioning/50-source.sh`のISUCON14_*参照)ため、この経路は変更していない
- `bench/benchrun/frontend_hashes.json`・`frontend_files.json` — `frontend/vite.config.ts`の
  `generateHashesFile` pluginがビルドのたびに再生成する、bench用のフロントエンド整合性確認ファイル。
  本家はコミット対象にしているが、うちは`pnpm run build`を実行するたびに必ず内容が変わるため
  (実質的にビルド成果物であり、コミットされた値を維持する意味が薄い)、`.gitignore`で対象外にしている。
  ファイル自体はディスク上に残る(取り込み時点の内容のまま)。GitHub Releaseで配布するビルド成果物には
  この2ファイルの最新版を含める(`kakomon14/scripts/build-frontend-release.sh`参照)。

## upstream/isucon14の更新方法

`mise run kakomon14:refresh-upstream`で`tmp/all-kakomon/isucon14`(なければclone、あれば`git pull`)を
最新化し、このディレクトリへ`rsync`で反映する。除外対象は上記「対象外にしたもの」の一覧をそのまま
rsyncの`--exclude`に反映しているため、除外方針を変える場合はこのNOTICE.mdとタスクの両方を更新すること。
