# auditチェックリスト

## 1. provenanceと対象範囲

- editionとQualify/Final等のvariantを一意にする。
- official upstream URL、remote、exact commit/tag、license/noticeを確認する。
- ローカルaudit / import cacheのremote、full HEAD、clean状態を記録し、expected official identityとの一致を確認する。別sessionはclone / fetch / pullせず、不一致ならcacheを変更せず停止する。
- 参考実装の出典、revision、想定OS/architecture/providerを分離する。
- official treeを、こちらで保守するApplication・benchmark・frontend等のコードと、verified cacheから`rsync`して固定bundleへ変換する画像・静的asset・`sql/`・初期データへ分類し、target固有subpathを列挙する。
- Go版の範囲をApplication、benchmark、補助service、frontend、OS packageごとに定義する。
- upstreamのprovisioning、README、inventory、systemd、container構成から正本候補を特定する。

## 2. service、package、runtime

- Application、DB、proxy、cache、queue、DNS、TLS、補助service、benchmarkを列挙する。
- package名、設定、user/group、directory、ownership、environment、systemd依存順を集める。
- listen address、port、protocol、hostname、DNS/hosts依存、TLS終端と証明書生成責任を調べる。
- 競技用domainと全参照箇所を列挙し、元のsubdomainを保つ`isuren.internal`写像、TLS SAN、cookie/domain、benchmark target、自己署名fixtureまたは本物の秘密の境界を定義する。
- architecture固有binary、private registry/image、外部download、build-time network依存を探す。
- Ubuntu 26.04 arm64でのpackage repository、binary、systemd、kernel/library互換性を調べ、amd64・旧Ubuntu前提をRed項目にする。
- upstream指定のGo/frontend/runtimeと統合済みKAKOMON14のexactな採用値・lockを比較する。
- `latest`、floating tag、range、`most_recent`、未固定package repositoryを列挙する。

## 3. frontend

- frontend buildの要否と、benchmarkが静的file/hash manifestを検証するかを確認する。
- 「24」「26」等の数字がNode.js、OS、Go、別toolのどれかを証拠から特定する。特定できなければ`decision-required`とする。
- package manager、lockfile、workspace設定、install/build command、環境変数を確認する。
- 生成物、hash/file manifest、archive、license、配置先、配信service、cache invalidationを確認する。
- buildをAMI内、ローカル/CI、release artifactのどこで行うかと、そのexact identity/checksumを確認する。

## 4. benchmarkとresult

- benchmark source、build方法、binary/data配置、実行user、cwd、引数、target指定を確認する。
- warmup、timeout、並列性、DNS/TLS、port、host mapping、必要なfixtureを確認する。
- stdout/stderr、exit status、score、success/failure JSON等の最終result構造を確認する。
- frontend manifest等がbinaryへembedされる場合、生成順と整合性契約を確認する。
- 既存sourceと実走証拠からvalid success/failureのresult契約を調べ、将来の`verify`でfailureを再現しresultを回収する条件を定義する。audit中には再現実走しない。

## 5. topologyとlifecycle

- compact topologyについてnode数、role同居、private IP/DNS、port、benchmark経路を図または表にする。
- canonical topologyについて公式node数、role分離、data配置、benchmark経路を同様に記録する。
- compact化で変えるものと変えてはいけない競技契約を分ける。
- 初期化/resetの対象、実行command、冪等性、所要時間、失敗時状態を確認する。
- reboot後のenabled/running、identity再生成、data保持/初期化、benchmark再実行を確認する。
- failureからreset/recoveryして再度normal resultを得る検証項目を作る。

## 6. recipe gap分析

- `cloud-init`、`all.sh`、edition固有step、`goss.yaml`、`mise.toml`/lock、Packerの責任を[recipe実装契約](recipe-contract.md)へ照合する。
- 手動修正、秘密、role固有identity、builder一時file、mutable inputがimageへ残る経路を探す。
- source、runtime、frontend、base image、package、tool/pluginのpinとchecksum不足を列挙する。
- managed upstreamのbaseline/local差分、LICENSE/NOTICE、cache rsync対象のexact commit/subpath、固定bundleのmanifest/checksum、`tmp/`非依存を照合する。
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
