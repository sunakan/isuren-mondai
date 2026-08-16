# isuren-mondai

- ISUCONの過去問を特定言語に絞り、AMIを作るためのリポジトリ
- 類似の問題もこのリポジトリで管理予定

※「ISUCON」は、さくらインターネット株式会社の商標または登録商標です。

## 対応問題

リージョンは全て ap-northeast-1(東京) です。

| 名前(対象)              | CloudFormation  | AMI  |go|java|nodejs|perl|python|ruby|rust|
|:--------------------|:----------------|:-----|:---:|:----:|:---:|:---:|:---:|:---:|:---:|
| kakomon14(ISUCON14) | [1bench-1web](https://github.com/sunakan/isuren-mondai/blob/main/cfn/kakomon14-1bench-1web.yaml) | [ami-05b13744921cbb5b7](https://ap-northeast-1.console.aws.amazon.com/ec2/home?region=ap-northeast-1#ImageDetails:imageId=ami-05b13744921cbb5b7) |✅|||||||

## Orb Golden Base

問題recipeだけを導入した停止済みVMを`<canonical-slug>-golden-base`として作る。
既定はdry-runであり、同名VMを上書き・削除しない。

```bash
mise orb:build-golden-base kakomon14
GITHUB_TOKEN="$(ghtkn get sunakan/read)" mise orb:build-golden-base kakomon14 --execute
```

isuren層を追加する作業VMはbaseを直接起動せず、clone-local identityを再生成してから使う。

```bash
mise orb:prepare-golden-base-clone kakomon14 isuren-kakomon14-golden-next
mise orb:prepare-golden-base-clone kakomon14 isuren-kakomon14-golden-next --execute
```
