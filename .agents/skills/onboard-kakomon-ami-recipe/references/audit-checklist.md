# auditチェックリスト

## 1. provenanceと対象範囲

- editionとQualify/Final等のvariantを一意にする。
- official upstream URL、remote、exact commit/tag、license/noticeを確認する。
- implement worktreeではmain source cacheを検証してから、作成直後にclone全体を同名のworktree-local `tmp/all-kakomon`へ`rsync -a`したことを確認する。bootstrapでは`.git/`を含め、既存宛先と`--delete`を使わない。
- main source cacheとworktree-local mirrorのremote、full HEAD、clean状態を記録し、expected official identityとの一致を確認する。local mirrorがtop-level Gitでignoreされ、stage、commit、merge payloadに含まれないことも確認する。別sessionはclone / fetch / pullせず、不一致ならcacheを変更せず停止する。
- 参考実装の出典、revision、想定OS/architecture/provider/regionを分離する。
- official treeを、こちらで保守するApplication・benchmark・frontend等のコードと、非commitの画像・静的asset・`sql/`・初期データへ分類し、target固有subpathを列挙する。非commit dataはAMI内でofficial exact commitから直接取得するか、外部固定bundleへ変換するかも分類する。
- Go版の範囲をApplication、benchmark、補助service、frontend、OS packageごとに定義する。
- upstreamのprovisioning、README、inventory、systemd、container構成から正本候補を特定する。

## 2. service、package、runtime

- Application、DB、proxy、cache、queue、DNS、TLS、補助service、benchmarkを列挙する。
- package名、設定、user/group、directory、ownership、environment、systemd依存順を集める。
- officialのcontestant home treeとsystemd unitから、`env.sh`、Application、benchmark、runtime、licenseの相対pathを一覧化する。username写像以外の配置差は意図的差分か欠落かを分類する。
- `env.sh`の各値を公開practice defaultとclone/role固有secretへ分類する。公開DB defaultはofficial file名/keyを保ってimageへ置けるが、credential-bearing値やmachine identityを同じ扱いにしない。
- benchmark source、module entrypoint、binary、任意のlocal helper/wrapper、runtime assetを分け、各fileがofficial由来かrecipe独自かを分類する。wrapperを既定で作らず、採用済みconsumer/result契約が要求する場合だけAMIへ含める。build後にsource directoryを削除する場合も、binaryが実行時に参照するinitial-data、static file、cwd、相対pathはsource codeと実走証拠から残す。official project rootがこれらのruntime assetを束ねる場合、source-only directoryと誤認してhome直下のApplication directoryへ潰さない。
- listen address、port、protocol、hostname、DNS/hosts依存、TLS終端と証明書生成責任を調べる。
- 競技用domainと全参照箇所を列挙し、元のsubdomainを保つ`isuren.internal`写像、TLS SAN、cookie/domain、benchmark target、自己署名fixtureまたは本物の秘密の境界を定義する。
- architecture固有binary、private registry/image、外部download、build-time network依存を探す。
- release assetやsource archiveの実形式をURL suffixだけで推測せず、asset名、magic/type、extractor、SHA-256を確認する。zipをtarとして扱う、またはその逆をしない。
- Ubuntu採用imageの`/tmp` mount種別と容量を確認し、大きなdownload/upload/extractがtmpfsを枯渇させないroot-backed stagingとcleanupを設計する。
- Ubuntu採用versionでservice CLI/packageのmajor versionとsyntaxを確認する。別Ubuntu/旧recipeのcommandをコピーせず、PowerDNS等のowner-name/zone semanticsを実機または公式version証拠でRed/Greenする。
- Ubuntu 26.04 arm64でのpackage repository、binary、systemd、kernel/library互換性を調べ、amd64・旧Ubuntu前提をRed項目にする。
- AWS profile、Packer、base AMI検索、build、tag、fresh boot、product検証、cleanupで`ap-northeast-1`が明示され、別regionのAMI IDや暗黙のdefault regionを使わないことを確認する。
- upstream指定のGo/frontend/runtimeと統合済みKAKOMON14のexactな採用値・lockを比較する。
- `latest`、floating tag、range、`most_recent`、未固定package repositoryを列挙する。

## 3. frontend

- frontend buildの要否と、benchmarkが静的file/hash manifestを検証するかを確認する。
- official repositoryがprebuilt public treeをcommitしている場合、こちらでfrontend sourceを保守・再buildする必要が本当にあるかを先に判断する。再buildしないならNode.js/package manager/local `dist`/Releaseを要求せず、official exact commit/treeからAMI内で直接取得する候補を監査する。
- 「24」「26」等の数字がNode.js、OS、Go、別toolのどれかを証拠から特定する。特定できなければ`decision-required`とする。
- package manager、lockfile、workspace設定、install/build command、環境変数を確認する。
- 生成物、hash/file manifest、archive、license、配置先、配信service、cache invalidationを確認する。
- buildをAMI内、ローカル/CI、release artifactのどこで行うかと、そのexact identity/checksumを確認する。
- CI/Release配布ならtarget固有workflow、tag filter、asset名、公開Release/digestのverify入口を確認する。build scriptだけをdelivery完成としない。
- prebuilt frontendならsource URL、full commit、Git tree、file manifest、SHA-256、license、配置先を固定し、生成済みfileをbyte-for-byte扱う。HTML/bundleがservice workerを登録しているか、CDN/絶対domain参照がruntime到達可能かを区別し、dormant referenceを文字列だけで削除・置換しない。activeな絶対domain依存は再buildや一括置換で回避せず停止条件にする。

## 4. benchmarkとresult

- benchmark source、build方法、binary/data配置、実行user、cwd、引数、target指定を確認する。
- payment/shipment等のmockや補助listenerがbenchmark process所有かpersistent serviceかをsourceから確認する。benchmark process所有なら常駐serviceを捏造せず、同じportを事前占有していないことを検証する。
- warmup、timeout、並列性、DNS/TLS、port、host mapping、必要なfixtureを確認する。
- stdout/stderr、exit status、score、success/failure JSON等の最終result構造を確認する。
- frontend manifest等がbinaryへembedされる場合、生成順と整合性契約を確認する。
- 既存sourceと実走証拠からvalid success/failureのresult契約を調べ、将来の`verify`でfailureを再現しresultを回収する条件を定義する。audit中には再現実走しない。

## 5. topologyとlifecycle

- compact topologyについてnode数、role同居、private IP/DNS、port、benchmark経路を図または表にする。
- canonical topologyについて公式node数、role分離、data配置、benchmark経路を同様に記録する。
- compact化で変えるものと変えてはいけない競技契約を分ける。
- 初期化/resetの対象、実行command、冪等性、所要時間、失敗時状態を確認する。
- restart command/APIはofficial sourceまたは保存済み実走証拠がある場合だけ固定し、名称や他editionの慣例から推測実装しない。
- reboot後のenabled/running、identity再生成、data保持/初期化、benchmark再実行を確認する。
- failureからreset/recoveryして再度normal resultを得る検証項目を作る。

## 6. recipe gap分析

- `cloud-init`、`all.sh`、edition固有step、`goss.yaml`、`mise.toml`/lock、Packerの責任を[recipe実装契約](recipe-contract.md)へ照合する。
- official inputをAMI内取得する場合、network/archive tool導入がfetch stepより先であること、`all.sh`の実順とstep番号が矛盾しないこと、local `dist`やPacker file upload待ちが残らないことを確認する。
- 手動修正、秘密、role固有identity、builder一時file、mutable inputがimageへ残る経路を探す。
- miseが実際のinstall/build経路か、単なるversion metadataかを区別する。mise binary自体のpin、`runuser`時のHOME/full path、Application/benchmark両方の`mise exec`、旧`/opt`/`/usr/local` runtime残留を確認する。
- seal直後とfresh boot後のfile/service契約を分け、clone固有`env.sh`、TLS、DNS addressがsealed artifactへ残らずreboot後に再生成されることを確認する。
- source、runtime、frontend、AWS region、base image、package、tool/pluginのpinとchecksum不足を列挙する。
- managed upstreamのbaseline/local差分、LICENSE/NOTICE、非commit dataのexact commit/subpath、AMI内直接取得または外部固定bundleのmanifest/checksum、artifactのlocal cache/`dist`非依存を照合する。
- Orb recipe、Orb Golden、standalone、AMI build、fresh boot、Orb/AWS productを[検証gate](verification-gates.md)へ割り当てる。
- 各外部gateにnamespace、TTL、費用、cleanup command/owner、残存確認があるか調べる。

## audit完了判定

次がすべて報告に現れるまでaudit完了としない。

- official provenance
- service/package/runtimeとfrontend成果物
- benchmark配置・実行・result構造
- DNS/TLS/port
- compact/canonical topology
- reset、failure、recovery、reboot
- recipe file別の責任分担
- 未決判断と停止条件
- 分離されたOrb/AWS gateとcleanup
