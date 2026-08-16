# kakomon recipe templates

`kakomon-templ/`は、将来の`kakomonN`または`kakomonN-qualify/final` recipeへコピーして使う
初期スケルトンです。実行targetではなく、このディレクトリをPacker、cloud-init、既存recipeから
直接参照しません。

## 所有権

テンプレートからコピー・生成したファイルは、コピー先targetが所有します。コピー後のファイルは
`kakomon-templ/`へのruntime依存を持たず、target固有の監査結果に合わせて編集し、target側でGit管理します。
現時点ではgeneratorを提供しません。テンプレートとの差分を機械的に消すのではなく、差分が共通責務の
改善なのか問題固有契約なのかをレビューします。

テンプレート内の`__KAKOMON_SLUG__`は、コピー時にcanonical slugへ置換します。置換前のshellも
`bash -n`で構文検証できますが、実行時にはslug検証でfail closedします。

## 共通化の境界

共通化するのは、Ubuntu 26.04 arm64の確認、共通network/archive tool、account作成、mise runtime導入、
package/serviceの基本操作、step実行、raw telemetry、Goss runnerといった、複数targetで責務が一致した
処理形です。巨大なedition分岐をテンプレートへ追加しません。

次の契約はtarget固有のまま保ち、共通テンプレートへ吸収しません。

- official sourceのURL、exact revision、配置、license、manifest
- frontendのbuild/prebuilt区分、Release selector、asset、checksum
- benchmarkのbuild、実行、result/failure semantics
- Application、mock、DNSなどのservice、port、topology
- hostname、domain写像、TLS SAN、cookie、proxy/vhost
- DB名、account、schema、初期データ
- MySQL/nginx/DNSや、`unzip`、`jq`、`iproute2`等のtargetだけが消費するpackage
- Gossの観測内容とseal/fresh-bootの状態契約

独自処理をbase script内の`start/end`コメントへ埋め込みません。共通処理の直後に必要な処理だけを
target extensionまたは責務名を持つtarget-owned stepへ分離し、`all.sh`へ実行順を明記します。

## 利用手順

1. [provisioning/README.md](provisioning/README.md)を読み、必要な`.tmpl`だけをtargetへコピーします。
2. `.tmpl`を外し、`__KAKOMON_SLUG__`をcanonical slugへ置換します。
3. `all.sh`へ実在するtarget-owned stepだけを列挙し、optional extensionは必要な場合だけコピーします。
4. runtime version、checksum、package、source、service、Gossをtargetの証拠で固定します。
5. target側の実行方法に合わせてmodeを設定し、`bash -n`、static validation、fresh recipe gateを実施します。

このディレクトリの`.tmpl`は意図的にmode `0644`とし、直接実行しません。
