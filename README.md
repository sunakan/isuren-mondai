# isuren-mondai

- ISUCONの過去問を特定言語に絞り、AMIを作るためのリポジトリ
- 類似の問題もこのリポジトリで管理予定

※「ISUCON」は、さくらインターネット株式会社の商標または登録商標です。

## 対応問題

||go|java|nodejs|perl|python|ruby|rust|
|:---|:---:|:----:|:---:|:---:|:---:|:---:|:---:|
|ISUCON14|✅|||||||

## AMIのビルド例

## フロントエンドのリリース例(kakomon14)

```shell
# CI で動く
git tag kakomon14-frontend-v1.0.1
git push origin kakomon14-frontend-v1.0.1

# ローカル版
GH_TOKEN=$(ghtkn get *****) mise run kakomon14:release kakomon14-frontend-v1.0.1
```
