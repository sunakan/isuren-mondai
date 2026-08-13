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

## コマンド実行の方針

- `packer build`・`aws cloudformation deploy`等、EC2インスタンス起動やAMI作成を伴う操作は
  課金・時間がかかるため、実行前に必ずユーザーに確認する
- `mise run down-verify-ami`はfzfでの一覧選択が前提でAIからは対話操作できない。
  aws-bastion側と同様、AIはawsコマンドで直接スタック名を指定して操作してよい
