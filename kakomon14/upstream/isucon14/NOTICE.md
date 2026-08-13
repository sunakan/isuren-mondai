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
  `bench/Dockerfile`はISUCON運営限定のプライベートECRイメージに依存しビルドできないため未使用で、
  `go run . run --target ... -t 60`のように直接実行する)

## 対象外にしたもの

- `browsercheck/`・`envcheck/` — いずれもISUCON運営側の道具で、参加者側の環境では動作しない
  (詳細はdocs/plans/kakomon14配下の調査メモ、または会話ログ参照)
- `development/` — 全言語分のDocker Compose定義で、Goのみに絞る方針とは噛み合わない

## 取り込んでいないもの

以下は「自分で手を加えない読み取り専用データ・アセット」のため、取り込まずAMI構築時に
本家(`isucon/isucon14`)から直接sparse-checkoutで取得する(`kakomon14/provisioning/50-source.sh`参照)。
js/css/ts等、将来構文が非推奨になった際に自分で保守する可能性があるコードとは取得元を分けている。

- `webapp/sql` — サンプルデータ(`3-initial-data.sql.gz`)が将来の過去問追加で肥大化しうるため
- `frontend/public` — 画像等の静的アセットで、リポジトリを重くするだけで編集対象にならないため

過去問によって画像等の置き場所は異なる(例: isucon13は`bench/internal/scheduler/images/`配下)ため、
この取り込まない対象パスは過去問ごとに個別判断する。

## コミット対象から外したもの

- `bench/benchrun/frontend_hashes.json`・`frontend_files.json` — `frontend/vite.config.ts`の
  `generateHashesFile` pluginがビルドのたびに再生成する、bench用のフロントエンド整合性確認ファイル。
  本家はコミット対象にしているが、うちは`pnpm run build`を実行するたびに必ず内容が変わるため
  (実質的にビルド成果物であり、コミットされた値を維持する意味が薄い)、`.gitignore`で対象外にしている。
  ファイル自体はディスク上に残る(取り込み時点の内容のまま)。GitHub Releaseで配布するビルド成果物には
  この2ファイルの最新版を含める(`kakomon14/scripts/build-frontend-release.sh`参照)。
