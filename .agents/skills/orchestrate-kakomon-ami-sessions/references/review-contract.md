# 別セッション成果のreview契約

## 目次

1. review入力
2. severity
3. 必須確認
4. 判定と報告

## review入力

別セッションの自己申告ではなく、次を対象worktreeから直接取る。

- worktree絶対path、branch、base SHA、HEAD、status、staged/unstaged/untracked diff
- main worktree絶対path、main HEAD、`origin/main`とのahead/behind、clean状態、他sessionのactive owner、main統合権限
- current planのstatus、依存、競合、変更許可path
- official URL、full SHA/tag、license/notice
- audit cacheと参考repoのremote、HEAD、dirty状態
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
- target directory外、他の`kakomon*/**`、参考repo、audit cacheに変更がない。
- staged/unstaged/untrackedを分け、許可pathだけがcommitされている。`git add .`や`git add -A`でscopeを広げていない。

### provenanceとruntime

- audit cacheをbuild sourceにしていない。
- official URL、full SHA/tag、license/noticeを固定している。
- dirty reference diffや公開AMIをsource provenanceへ昇格していない。
- ApplicationとbenchmarkがGo 1.26.6であり、Node.js、package manager、OS、architectureがcurrent adopted planと一致する。
- URL、checksum、config、lock、Goss、provenanceのcross-versionがない。
- `latest`、`lts`、floating tag、rangeだけのplugin/base image選択がない。
- target自身のApplication/benchmark validationを確認し、KAKOMON14のrecipe・Orb・AMI証拠をtargetの入口条件や成功証拠へ流用していない。

### recipe

- `all.sh`が唯一の実行順の正本で、全stepが存在し、空互換stepがない。
- failureが非zeroで伝播し、completion markerを失敗時に作らない。
- user/group、ownership、directory、package、service依存順、port、DB/proxy/DNS/TLSが対象upstreamから導かれている。
- Applicationとbenchmarkのbuild、配置、実行user/cwd、result/failure契約が分離されている。
- frontend build、hash/manifest更新、benchmark build、配置順がofficial契約と一致する。
- cloud-initはfixed recipeを起動する薄いadapterである。
- Gossは観測だけを行い、reset/reboot/multi-node/product E2Eの代替になっていない。
- machine-id、SSH/TLS private key、credential、role固有値をartifactへ残さない方針がある。

### validationとgate

- 実行済みlocal validationをraw resultで確認する。
- 実行不能な検証は理由と後続gateがある。
- `all.sh` slice、Orb recipe、Orb Golden、standalone、AMI build、fresh boot、product gateを混同していない。
- AWS/Orb/GitHub mutationを人間承認なしに行っていない。

### main統合

- read-only fetch後のmainと`origin/main`が同期している。
- topicがcurrent mainを含むか、main取込み後にvalidationとセルフレビューを再実施している。
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

セルフレビューGreenだけでmainへ進まず、main worktreeのclean/ownership、remote同期、fast-forward可能性を独立に確認する。local main統合後もpushは人間所有とする。
