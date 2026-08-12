# scripts/kakomon14

isucon14をbastion上でネイティブ構築するための冪等なプロビジョニングスクリプト群。
`all.sh`で`10-base.sh`〜`95-deploy-helper.sh`を順に実行する。

## チューニング中の再デプロイ

`95-deploy-helper.sh`が`isuren`のホームに`deploy.sh`を配置する。
`isuren`でログインし、`webapp/go`のコードを変更した後は以下の1コマンドで再ビルド・再起動できる。

```bash
~/deploy.sh
```

## ログの確認方法

```bash
# isuride-go(webapp本体)
journalctl -u isuride-go -f

# isuride-matcher(マッチング)
journalctl -u isuride-matcher -f

# nginx
journalctl -u nginx -f
tail -f /var/log/nginx/error.log
```
