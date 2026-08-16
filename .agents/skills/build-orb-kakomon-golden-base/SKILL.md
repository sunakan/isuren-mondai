---
name: build-orb-kakomon-golden-base
description: isuren-mondaiのcanonical kakomon recipeをUbuntu 26.04 arm64 Orb VMへcloud-initで一度だけ適用し、Goss完走、入力identity、問題serviceの停止・無効化、cloud-init再実行防止、machine-id・SSH host key・random seed・MySQL UUIDの除去、停止状態を検証した問題専用Golden Baseを作る。kakomonN-golden-baseの新規作成、事前監査、失敗調査、またはbaseからisu層用cloneを準備するときに使う。AMI build、既存VMの単純な起動停止、isuren固有isu層の導入だけには使わない。
---

# Orb Kakomon Golden Base

## 目的

問題recipeだけを含むprovider-native artifact A (`<canonical-slug>-golden-base`)を作る。
isuren固有の`isu`、Portal credential、environment identityをAへ入れない。Aから安全に
cloneを準備した後、別工程でisuren層を追加してartifact B (`isuren-<slug>-golden`)を作る。

AMIのdiskを変換しない。AMIとOrbはexact recipe commit/treeとtarget-local入力を共有し、
それぞれのproviderでbuild・検証する。

## 手順

1. `AGENTS.md`と対象の`cloud-init/generate-user-data.py`、`provisioning/all.sh`、
   `provisioning/goss.yaml`、Orb adapterの`prepare-cloud-init-user-data.py`を読む。
   canonical slugとUbuntu 26.04 arm64対応を確認する。
2. `git status --short`、HEAD、push済みcommit、`orb list --format json`を確認する。
   既存の同名VMがある場合は停止する。上書き・削除・自動renameをしない。
3. まずread-only dry-runを行う。dry-runも同名Orb VM、dirty worktree、またはupstream
   tracking refに含まれないHEADをこの順で検知した時点で停止する。別端末からpushした直後なら
   `git fetch`して再実行する。

   ```bash
   mise orb:build-golden-base kakomon14
   ```

4. planのtarget、VM名、commit、recipe tree、frontend selector、service contract、
   input SHA-256を提示する。Orb VMを作る前にユーザーの明示承認を得る。
5. 承認後だけ実行する。公開repositoryのexact commit確認にGitHub tokenが必要である。

   ```bash
   GITHUB_TOKEN="$(ghtkn get sunakan/read)" mise orb:build-golden-base kakomon14 --execute
   ```

   Orb imageには`git`がない場合があり、初期cloud-init時点ではIPv4/DNSも未準備になりうる。
   Orb adapterで`set -eu`を有効化し、IPv4 routeとGitHub DNSを期限付きで待ってから、
   `apt-get update`と`ca-certificates`/`git`の無条件installを行い、その後にcanonical
   user-dataの`runcmd`を実行する。これはOrb VM内だけの処理とし、対象generatorやAMI用
   user-dataへ複製しない。途中失敗を後続cleanupの成功で隠さない。

6. 成功時は`orb-recipe-green`と`orb-golden-green`を分けて報告する。少なくとも
   cloud-init/all.sh/Goss完走、Golden marker、identity scrub、isuren層不在、停止状態を示す。
   clone/fresh-boot、standalone、product Greenは実行していなければ`not-run`と書く。

## Base cloneの準備

停止済みAをBの作業VMへcloneするときも最初はdry-runにする。

```bash
mise orb:prepare-golden-base-clone kakomon14 isuren-kakomon14-golden-next
mise orb:prepare-golden-base-clone kakomon14 isuren-kakomon14-golden-next --execute
```

この処理はsource baseを起動・変更せず、clone側でhostname、machine-id、SSH host key、
random seed、MySQL server UUIDを再生成する。問題serviceはGolden seal時に無効化し、identity
再生成後にtargetのGoss contractどおり復元する。元のuser-dataをcloneで再実行しないため、
Orb Goldenではcloud-initを無効のまま維持する。Bの追加provisioningはhost側script/Orb runで行う。
ここで完成するのはBを作るためのrunning作業VMであり、BのGolden完成を意味しない。isuren層の
検証、再seal、停止を別gateとして完了する。

## Stop rules

- worktreeがdirty、HEADが未push、frontend selectorを実体tag/digestへ解決できない、
  対象recipe/Gossに完全なservice contractがない場合はbuildしない。
- Orb bootstrapでIPv4 route、DNS、apt、`git --version`のいずれかを確認できない場合は、
  canonical recipeを開始せずcloud-initを失敗させる。
- 同名VMが存在する、baseが停止していない、canonical slugでない場合は停止する。
- build/clone失敗時は診断用VMを勝手に削除しない。名前と失敗gateを報告する。
- Aへ`isu`、Portal/mTLS credential、environment identity、実秘密を追加しない。
- sealed baseを直接起動して使わない。cloneを作りidentity再生成を完了してから使う。
