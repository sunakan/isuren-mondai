## AMIのビルド例

```shell
mise kakomon14:build
```

## フロントエンドのリリース例(kakomon14)

```shell
# CI で動く
git tag -m "v1.0.3" kakomon14-frontend-v1.0.3 && git push origin kakomon14-frontend-v1.0.3

# ローカル版
GH_TOKEN=$(ghtkn get *****) mise run kakomon14:release kakomon14-frontend-v1.0.3
```
