# 別セッション成果のreview契約

## 目次

1. review入力
2. severity
3. 必須確認
4. 判定と報告

## review入力

別セッションの自己申告ではなく、次を対象worktreeから直接取る。

- worktree絶対path、branch、base SHA、HEAD、status、staged/unstaged/untracked diff
- main worktree絶対path、local main HEAD、clean状態、他sessionのactive owner、main統合権限。remote mainとの比較はlocal merge入力にしない
- current planのstatus、依存、競合、変更許可path
- official URL、full SHA/tag、license/notice
- main checkoutのsource cache、worktree-local mirror、参考repoのremote、HEAD、dirty状態
- 変更fileと実行済みvalidationのraw output

別session所有の未統合worktree、VM、artifactを開いたり変更したりせず、今回の対象と明示されたworktreeだけをreviewする。

## severity

- `blocking`: provenance欠落、variant誤り、scope逸脱、秘密混入、plan依存違反、mutable build input、all.shの偽成功、他session所有物の変更。
- `major`: service/benchmark/frontend欠落、runtime identity不一致、fail-fast不備、Gossが状態変更、重要なvalidation不足。
- `minor`: 保守性、log、comment、報告の改善。正しさや再現性を壊さないもの。

好みだけの差をfindingにしない。各findingへfile/line、失敗経路、影響、最小修正方針を付ける。

## 必須確認

### scopeとGit

- canonical slug、branch、directory、variantが一貫している。
- 変更がpromptで許可されたtarget専用の`kakomon*/**`、`upstream/<official-repo-name>/**`、`mise-tasks/<canonical-slug>/**`だけに収まり、他target、参考repo、audit cacheに変更がない。
- staged/unstaged/untrackedを分け、許可pathだけがcommitされている。`git add .`や`git add -A`でscopeを広げていない。
- `tmp/all-kakomon/**`がtop-level Gitでignoreされ、stage、commit、merge payloadに含まれていない。worktree-local mirrorの存在自体や統合前に削除していないことをfindingにしない。

### provenanceとruntime

- main checkoutのsource cacheを検証後、worktree作成直後にclone全体を同名のworktree-local mirrorへ`rsync -a`し、このbootstrapだけは`.git/`を含めている。両cacheのorigin URL、full HEAD、clean状態がofficial identityと一致し、既存宛先や`--delete`を使っていない。
- bootstrap後のaudit/importはworktree-local mirrorだけから行い、main source cacheを変更・直接利用していない。別sessionがclone / fetch / pull / checkout / reset / cleanでcacheを補正していない。
- cacheをclean clone、cloud-init、AMI buildの直接build sourceにせず、保守codeだけをcommit済みmanaged sourceにしている。非commit dataは公式exact commitからbuild instance内で一時取得してcommit済みmanifestで検証するか、外部Releaseのexact tagとSHA-256へ固定している。AMI内直接取得方式ではlocal `dist/`をPacker入力にしていない。
- official URL、full SHA/tag、license/noticeを固定している。
- managed upstreamが公式baselineから取り込んだ保守対象コードとlocal変更を追跡し、`NOTICE.md`の範囲・除外・provenanceと実treeが一致する。
- 画像を含むbinary、編集しない静的asset、`sql/`、初期データをmanaged upstreamへcommitせず、worktree-local mirrorのexact commitとtarget固有subpathから一時stagingへ`rsync`している。clean clone側は公式exact commitまたは外部Release exact tag/SHA-256から再取得でき、mutable branchや由来不明archiveへfallbackしていない。
- build成果物、release archive、固定bundle、画像、音声、動画、font、database dump等のbinaryがGit管理下にない。生成物はignore済み`dist/`または一時directoryにあり、manifest、checksum、provenanceのtext metadataだけがcommitされている。
- staged diffのbinary表示、追加fileのsize/type、`git ls-files`を確認し、`artifacts/`、`dist/`、frontend build出力が追跡されていない。すでにcommit済みbinaryを独断でhistory rewrite・reset・削除していない。
- working treeやbuild先に配置された画像・binaryは、ignore対象であり、stage・commit・merge payloadに含まれていない。配置されていること自体をfindingにしない。
- binaryまたは成果物のGit管理が必要・望ましいと判断された場合、実装sessionが追加・stage・commit前に停止して人間へ相談している。相談なしにGit管理していたら`blocking`とする。
- cache由来データを保守対象codeへ実ファイルで統合せず、不要な`.git`、生成物、依存directory、重複sourceを配布物へ残していない。`rsync --delete`でmanaged sourceのlocal変更を黙って上書きしていない。
- dirty reference diffや公開AMIをsource provenanceへ昇格していない。
- ApplicationとbenchmarkがGo 1.26.6であり、Node.js、package manager、OS、architectureがcurrent adopted planと一致する。
- official contestant homeとsystemd unitを基準に、username写像後も`env.sh`、Application、benchmark、licenseの相対pathを保っている。配置差はREADME/NOTICE/Gossで意図的差分として説明され、偶発的な独自`runtime.env`やbuild-only checkout/GOPATH残留がない。
- OSとarchitectureがUbuntu 26.04 arm64、AWS regionが`ap-northeast-1`で、profile、Packer、base AMI検索、build、tag、fresh boot、product検証、cleanupのregionが一致している。暗黙のdefault regionへ依存していない。
- Packer build入力が`ap-northeast-1`のexact base image IDに固定され、別regionのAMI ID、amd64、旧Ubuntu、`most_recent`へfallbackしていない。
- URL、checksum、config、lock、Goss、provenanceのcross-versionがない。
- mise config/lockがmetadataだけでなく実際のinstallとApplication/benchmark buildに使われる。mise自体もexact URL/checksumへ固定され、`runuser`経路はfull pathとHOMEを明示し、並行する`/opt/go-*`や`/usr/local/bin/go`導入を残していない。
- `latest`、`lts`、floating tag、rangeだけのplugin/base image選択がない。
- target自身のApplication/benchmark validationを確認し、KAKOMON14のrecipe・Orb・AMI証拠をtargetの入口条件や成功証拠へ流用していない。

### recipe

- `all.sh`が唯一の実行順の正本で、全stepが存在し、空互換stepがない。
- failureが非zeroで伝播し、completion markerを失敗時に作らない。
- user/group、ownership、directory、package、service依存順、port、DB/proxy/DNS/TLSが対象upstreamから導かれている。
- upstreamに競技用domainがある場合、元のsubdomainを保つ`isuren.internal`写像がDNS/hosts、proxy、TLS SAN、cookie/domain、Application、benchmark、healthcheckで一致し、一括置換・alias・published identity上書きがない。
- Applicationとbenchmarkのbuild、配置、実行user/cwd、result/failure契約が分離されている。
- frontendをこちらでbuildする方式とofficial prebuiltをbyte-for-byte配置する方式が分離されている。前者はbuild/hash/manifest/benchmark build/配置順、後者はexact commit/tree/file manifest/SHA-256/licenseとAMI内取得順がofficial契約に一致する。
- prebuilt assetの外部URLを文字列だけで一括置換していない。未登録service worker等のdormant referenceはruntime到達性の証拠とともに維持し、activeな絶対domain依存は生成済みassetを変更せず停止している。
- external frontend配布ならtarget固有workflow、target限定tag filter、asset名、manifest/licenseが揃う。repository slice完了とremote Release発行を分け、Release未発行の状態を外部verify-readyにしていない。
- cloud-initはfixed recipeを起動する薄いadapterである。
- Gossは観測だけを行い、reset/reboot/multi-node/product E2Eの代替になっていない。
- seal直後とfresh boot後を別stateとして検証し、clone固有env/TLS/identityはseal時不在・boot後再生成になっている。同じGoss specへ矛盾する二状態を要求していない。
- machine-id、SSH host key、credential、role固有値、本物のTLS/mTLS private keyをartifactへ残していない。自己署名server keyを含める場合は公開テストfixtureとしてmode・fingerprint・用途が固定され、認証やcredential-bearing trafficへ流用されない。

### validationとgate

- 実行済みlocal validationをraw resultで確認する。
- 実行不能な検証は理由と後続gateがある。
- `all.sh` slice、Orb recipe、Orb Golden、standalone、AMI build、fresh boot、product gateを混同していない。
- AWS/Orb/GitHub mutationを人間承認なしに行っていない。AWS操作を実施した場合はregionが`ap-northeast-1`で、cleanupも同regionに限定されている。
- 外部verify開始前に検証対象recipe commitがremoteから取得可能であること、必要なRelease asset/digest、account、resource ID、AMI ID、instance type、architecture、OS、SSM Onlineを確認している。local mainとremote mainの完全一致は要求せず、入力不足時にpartial provisioningでinstanceを汚していない。

### main統合

- topicがcurrent mainを含むか、main取込み後にvalidationとセルフレビューを再実施している。
- main取込みにrebaseを使った場合、new HEADを記録し、rebase後のvalidation/セルフレビューを取り直し、rebase前のcommit証拠をnew commitへ自動流用していない。
- topic/mainの両worktreeがcleanで、所有不明の差分やactive guardがない。
- main統合は`git merge --ff-only <topic-branch>`であり、main上に未検証merge commitを作っていない。
- 統合後にtopic HEADがmainのancestorであることを確認している。

## 判定と報告

結論を次のいずれかにする。

- `ready-to-merge-main`: blocking/major findingがなく、all.sh sliceの完了条件、clean commit、local validation、main統合条件を満たす。
- `merged-to-main`: `ready-to-merge-main`の条件を満たし、topic HEADがlocal mainへfast-forward統合済みである。
- `changes-requested`: 修正可能なblocking/major findingがある。
- `blocked`: plan依存、identity、provenance、所有、未決policyが不足し、同じscopeで安全に進めない。

報告順は次とする。

1. 結論。
2. severity順のfindings。なければ「blocking/major findingなし」と明記する。
3. 良い点。
4. 実行済みvalidationと`not-run` gate。
5. topic/mainのcommit identity、統合可否、または次の安全な修正prompt。

セルフレビューGreenだけでmainへ進まず、local main worktreeのclean/ownership、fast-forward可能性を独立に確認する。local mainとremote mainの比較・同期はlocal merge条件にせず、local main統合後のpushは人間所有とする。
