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

## 過去問コードの取り込み(upstream)方針

リポジトリルート直下に`upstream/`を置き、取り込み元リポジトリ名でディレクトリを分ける
(例: `upstream/isucon14/`。将来的に`upstream/isucon14-portal/`等も同様)。
過去問ごとの自作コード(`kakomon14/`等)とは別の場所に置くことで、「自分のコード」と
「取り込んだ本家コード」を分離している(node_modules等の重量物・大量のファイルが
自作コードの検索・閲覧のノイズにならないようにするため)。
GoLandがディレクトリ名`vendor`をGoのvendoring規約として誤認識し除外扱いにするため、`upstream`という
名前を採用している。

- upstream直下の名前は「isuren側の呼び名(kakomon14等)」ではなく「クローン元リポジトリ名」に揃える
- 各upstreamディレクトリには取り込み元のLICENSEをそのままコピーする。コピーライト行がリポジトリごとに
  異なる(isucon14は「2024 ISUCON14 Contributors」、isucon14-portalは「2022 ISUCON」)ため、
  1つのLICENSEファイルに統合しない
- `upstream/<取り込み元リポジトリ名>/`は公式sourceの不変mirrorではなく、Application、benchmark、frontend等の
  自分で保守するコードを置くtreeとする。対象過去問の専用worktree/sessionは、自分のtargetに対応する
  `upstream/**`と`mise-tasks/<canonical-slug>/**`を作成・更新してよい。公式の起点commit、取り込み範囲、除外範囲、
  local変更は各upstreamの`NOTICE.md`へ記録し、他過去問の同名pathへは触れない
- 自分で保守しない画像・静的assetと`sql/`・初期データは原則としてupstreamへcommitせず、過去問ごとに必要pathを
  特定して、frontend artifact buildまたはprovisioningの消費前に公式repositoryのexact commitから直接取得する。
  取得元・commit・subpathを固定し、LICENSEを伴う実ファイルとして保守対象コードへmergeする。`upstream/isucon14/NOTICE.md`と
  `kakomon14/provisioning/50-source.sh`を構造上の参考にするが、除外pathは対象upstreamを監査して個別に決める
- `packer/`・`provisioning/`・`cloud-init/`等の完全自作物にはisucon側のLICENSEを適用しない
  (このリポジトリ自体のLICENSEに従う)
- 本家から直接fetchするファイル・値(`0-init.sql`が作る`isucon`DBユーザー、`env.sh`の
  `ISUCON_DB_USER`等)は書き換えない。ISUCON商標(さくらインターネット株式会社)由来の文字列を
  避けたいのはisuren-mondai側が自作・管理するファイルに対してのみで、vendorした本家ファイルの
  中身まで書き換える実益はないと判断した(`40-mysql.sh`・`50-source.sh`参照)

## upstream取得(sparse-checkout)の実装上の注意点

kakomon14のupstream移行(`50-source.sh`)で実際にハマった点。他の過去問を追加する際にも当てはまる。
なお`50-source.sh`内では、isuren-mondai自身が保持するこの取り込み済みコードを`UPSTREAM_*`、
isucon14公式リポジトリから読み取り専用データを直接取得する側を`ISUCON14_*`と呼び分けている
(前者のディレクトリ名`upstream`と、後者が指す「本家」概念が別物であるため)。

- cone modeのsparse-checkoutは指定パスだけでなく**リポジトリルート直下のファイルも自動的に含む**。
  isuren-mondai自身を取得元にする場合、`mise.toml`(Packer/AWSタスク定義)のような
  無関係なファイルも一緒に取得されてしまう。当初は取得後に明示的に除去していたが、後述の通り
  取得用の一時ディレクトリ自体をデプロイ後に削除する方式に変えたため、この問題は自然に解消した
- gitignoreの衝突で、ファイルが`git add`時に**静かに無視される**ことがある。2パターン確認済み
    - グローバルgitignore(macOSの`Icon`ルール等)が、大文字小文字を区別しないファイルシステム上で
      正当なディレクトリ名(`icon/`等)と衝突する
    - 取り込んだディレクトリ自身の`.gitignore`(先頭`/`なしのパターン、例: `bench`)が、
      同名の無関係なディレクトリ(`services/bench/`等)を意図せず無視する
    - 取り込み時は本家ツリーと`comm -23 <(find 本家 ...) <(git ls-tree ...)`のように突き合わせて、
      欠落ファイルがないか確認する運用にする
- 当初`~/isucon14`・`~/webapp`は取得先を指すシンボリックリンクだったが、本番運用(Packerビルド時に
  1回だけプロビジョニングする)を優先し、`rsync -a`で実ファイルとしてデプロイしてから取得用の
  一時ディレクトリを削除する方式にした(`50-source.sh`のdeploy_*/cleanup_checkouts参照)。
  Why not symlink維持: systemdの`WorkingDirectory=`がシンボリックリンクを指す場合、chdir後の
  プロセスの実体パスはreadlink先になるため、プロセスからの相対パス(`../sql`等)がシンボリックリンクの
  論理的な親ではなく実体側(取得用の一時ディレクトリ)の親で解決されてしまう罠があった。実ファイル化
  によりこの罠自体が起きなくなった。ただし取得用の一時ディレクトリを毎回作り直すため、
  プロビジョニングスクリプトを開発中に何度も再実行する場合はネットワーク取得が都度走る
  (再実行速度より本番の単純さを優先した判断)
- upstream/配下のディレクトリ構成やパス(`UPSTREAM_SUBPATH`が指す場所)を変更したら、
  `UPSTREAM_COMMIT`もその変更を含むコミット以降の値に更新すること。更新を忘れると、
  古いコミット時点にはまだ存在しないパスをsparse-checkoutしようとして何も取得できず、
  `ln: No such file or directory`のような分かりにくいエラーでPackerビルドが失敗する
  (vendor→upstreamリネーム後に実際に発生。詳細はcommit 1f5ca68参照)

## mise-tasksの構成方針

タスクは全て`mise-tasks/`配下のファイルタスクで管理する(`mise.toml`への`[tasks.*]`定義はしない)。
ディレクトリを切ると`ci:shellcheck`のようにコロン区切りの名前空間になる。既存の名前空間は
`kakomon14:*`(過去問固有)・`packer:*`(Packerインフラ共通)・`ci:*`(lint類)。
新規タスクもこの分類に沿わせる。

## 新規過去問の共通platform・domain方針

- 新しくkakomon化するAMI recipeはUbuntu 26.04 arm64を採用値とし、Application、benchmark、OS package、
  補助serviceをtarget自身で検証する。非互換時にamd64や古いUbuntuへ自動fallbackせず、component別の失敗証拠を示して停止する
- Packerの調査でbase AMI候補を検索してよいが、build入力はUbuntu 26.04 arm64のexact image IDへ固定する。
  `most_recent`、architecture違い、旧OSをartifact入力へ残さない
- 本家に`isucon.net`、`*.isucon.dev`、`*.isucon.local`等の競技用domainがある場合は、元のsubdomain構造を保って
  `isuren.internal`配下へ移す。DNS/hosts、proxy、TLS SAN、cookie/domain、Application、benchmark、healthcheckを
  1つのhostname contractへ束縛し、repository全体の一括置換はしない
- 個人練習用の自己署名server certificateとprivate keyは、公開テストfixtureであることを明記し、modeを制限する場合に限り
  common Golden/AMIへ含めてよい。Public AMIでは誰でもprivate keyを取得可能なため、mTLS、Portal認証、信頼済み証明書、
  credentialを扱う通信には流用しない。これらの本物の秘密とmachine/role固有identityは従来どおりimageへ焼き込まない
- 既存の公開済みProblemVersion/manifest bytes・digestは書き換えず、新domainは別identityで扱う

## mise運用上のハマりどころ

isuren-mondai全体(kakomon14に限らない)でmiseを使う上での注意点。

- miseの設定探索は2方向ある。**上方向**(cwdからルートまで遡って全ての`mise.toml`をマージする。
  常時有効で無効化不可)と**下方向**(`monorepo_root = true`時のサブプロジェクト自動探索。
  `[monorepo].config_roots`で無効化可能)。isuren-mondaiはaws-bastion配下にあるため上方向で
  aws-bastion側のタスクが混入する問題があり、`.miserc.toml`の`ceiling_paths`で上方向の探索範囲を
  aws-bastionより上に行かないよう絞って対処した。`ceiling_paths`はearly-init設定のため
  `mise.toml`に書いても効かず、`.miserc.toml`か環境変数で指定する必要がある
- `.miserc.toml`の`ignored_config_paths`で特定configファイルを丸ごと無視できるが、`[tasks]`だけでなく
  `[tools]`も無視される。グローバル設定(`~/.config/mise/config.toml`)に対して使うと、そこで
  定義したツール(nvim等)がPATH解決できなくなる副作用がある(実際に一度nvimが壊れた)。
  特定タスクだけを隠したい場合は不向き
- `MISE_CONFIG_FILE`は`mise config ls`・`mise install`・`mise exec`には効くが、
  `mise lock`はディレクトリ探索で「現在のconfig root」を決めるため`MISE_CONFIG_FILE`を無視する。
  非標準の場所・名前で`mise.*.toml`を運用する場合、lock生成時は`MISE_ENV=<ENV名>`
  (ファイル名を`mise.<ENV名>.toml`にする)か、そのディレクトリに`cd`して素の`mise.toml`
  という名前にする必要がある(`kakomon14/scripts/mise.toml`参照)
- miseはaqua registryのスナップショットをバイナリに焼き込んでおり、"latest"指定の解決は
  そのスナップショット次第になる。`mise cache clear`やmise本体のアップグレードをしても
  古いバージョンに解決され続けることがある(pnpmで実際に確認: 本当は最新v11系が存在するのに
  9.15.4に解決された)。ツールバージョンは明示指定を徹底し、"latest"に頼らない

## frontendのビルド・配布方針

frontendはローカル/CIでビルドしGitHub Releaseで配布する(AMI上ではビルドしない)。
詳細は`kakomon14/scripts/build-frontend-release.sh`・
`.github/workflows/release-kakomon14-frontend.yml`・`upstream/isucon14/NOTICE.md`参照。

- タグ命名は過去問+役割を接頭辞にする(例: `kakomon14-frontend-v1.0.0`)。1つのリポジトリで
  複数過去問のリリースを扱うため、`scripts/github-release.sh`(過去問間で共有する汎用スクリプト)の
  前回リリース差分検出がタグの接頭辞一致で他過去問の履歴と混ざらないようにしている

## 見逃しがちな注意点(isucon14版)

aws-bastion上での試行錯誤・今回のセッションで見つかった、ハマりどころ・Why not集。
個別スクリプトのコメントに書いてあるものは重複させず、ここには「特定のファイルを読むだけでは
気づけないもの」「ツール自体の一般的な罠」を残す。

- `bench/Dockerfile`はISUCON運営限定のプライベートECRイメージ(supervisor)に依存しており一般環境では
  ビルドできない。benchはホストで直接`go run`する
- `development/compose-go.yml`は`frontend/build/client`をマウントするだけでfrontend自体はビルドしない。
  事前に`pnpm run build`しておく必要がある。同じくこのコンテナ(特にnginxの8080番ポート)が
  起動したままだと、ネイティブの`isuride-go`等とポートが競合し再起動ループになる。ネイティブ構築を
  進める前に`docker ps`で止まっていることを確認する
- ベンチ実行時の`context deadline exceeded`多発は、インスタンスのリソース不足(CPU)が原因のことがある。
  アプリのバグかリソース不足かの切り分けが必要
- AMIのベースOS(Ubuntu 26.04 arm64)の`chown`はGNU coreutilsではなくuutils coreutils(Rust実装)で、
  `-h`/`--no-dereference`がexit 0を返すのに実際にはlchownしないバグがある。シンボリックリンクの
  所有者変更が必要な場面は要注意(通常ファイルへの`chown`は正常動作)
- `runuser -u isuren -- <cmd>`は`.bashrc`を経由しないため、mise等はフルパスで呼ぶ必要がある。
  さらにisurenが読めないディレクトリ(`/home/ubuntu/...`等)をcwdにしたまま実行すると
  `go.mod file not found`という分かりにくい症状になる(`EACCES`にはならない)。回避策として、
  isurenのmiseインストール先(`/home/isuren/.local/...`は755で他ユーザーからも実行可)のバイナリを
  フルパス指定しつつ、実行ユーザーはubuntuのままにする方法がある
  (例: `sudo -u ubuntu /home/isuren/.local/share/mise/installs/go/<version>/bin/go run . run ...`)
- Packerの`launch_block_device_mappings`は`delete_on_termination`のデフォルトが**false**
  (公式ドキュメントに明記)。明示的にtrueにしないと、一時ビルドインスタンス終了後もルート
  ボリュームが削除されずビルドのたびに蓄積する。実際に17個・240GBの未アタッチボリュームが
  蓄積していたのを発見し削除した経緯がある
- Packerの`timestamp()`は呼び出すたびに評価され値が変わりうる(公式ドキュメントに明記)。
  同じビルド内で複数箇所から時刻を使いたい場合は、1箇所(local)にまとめて共有すること。
  別々に呼ぶと評価タイミングのズレで秒単位の不一致が起こりうる
- AWSのAMIは**登録後に名前を変更できない**(リネーム不可)。「特定の固定名を使い回して
  最新版を指す」運用はできないので、バージョン管理をしたい場合はタグ(Stage等)で状態を表現する
  必要がある
- `cloud-init status --wait`は失敗時のみログをtailする設計にしているため、goss(`99-verify.sh`)の
  検証詳細はビルド成功時にはPackerのビルドログに一切出ない。成功/失敗の二値以上の情報が
  ビルドログからは得られない

## 過去問リポジトリの参照(tmp/all-kakomon/)

`tmp/all-kakomon/`(gitignore対象)に、ISUCON過去問全件を本家からclone済み
(`isucon`・`isucon2`〜`isucon14`・各`-qualify`/`-final`/`-portal`等)。
`kakomon14:refresh-upstream`のような取得スクリプトの動作確認や、他過去問の構造調査に使う。

- 各過去問は本家(`github.com/isucon/<name>`。`celestial-observability/isucon-kakomon`の
  `.gitmodules`で実際のURLを確認できる)から直接`git clone`したもの。
  `celestial-observability/isucon-kakomon`自体からファイルをcp/rsyncするだけだと、`.git`が
  33バイトのsubmoduleポインタファイル(`gitdir: ../.git/modules/<name>`)になり実体を持たないため、
  コミットIDが辿れない(`git rev-parse HEAD`が失敗する)。必ず本家URLへ`git clone`し直すこと
- `mise-tasks/ci/shellcheck`・`shfmt`は`tmp/`配下を検査対象から除外している。除外し忘れると
  無関係な過去問リポジトリの指摘がノイズとして大量に出る

## コマンド実行の方針

- `packer build`・`aws cloudformation deploy`等、EC2インスタンス起動やAMI作成を伴う操作は
  課金・時間がかかるため、実行前に必ずユーザーに確認する
- `mise run down-verify-ami`はfzfでの一覧選択が前提でAIからは対話操作できない。
  aws-bastion側と同様、AIはawsコマンドで直接スタック名を指定して操作してよい
- `mise install`・`mise lock`等、miseのキャッシュ/状態ディレクトリ(`~/.local/state/mise`・
  `~/Library/Caches/mise`)への書き込みを伴う操作は、AIのサンドボックス(`~/.config/cage/presets.yaml`
  の許可リスト外)からは実行できない。ユーザーに`!`コマンドでの実行を依頼する
- `git checkout --`・`git rm --cached`等、未コミット変更を破棄・追跡解除する操作はAIの権限設定で
  拒否される。ユーザーに実行を依頼する
- `git -C <dir> ...`はAIの権限設定で拒否される(`git add`等のステージング操作とまとめてブロック
  されている模様)。`cd <dir> && git ...`のように`cd`してから実行する
- `mise run ci:shfmt`はこのリポジトリ全体(2スペースインデント)に対して常にタブへの変換を
  提案してくる(shfmtのデフォルトインデントがタブのため)。新規の指摘でなければ無視してよい
  既知の事象で、対応不要
