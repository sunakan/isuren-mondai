# kakomon14/provisioning

isucon14(Go)をAMI上に構築するためのプロビジョニングスクリプト群(cloud-init経由でPackerビルド時に
実行される)。各スクリプトはコマンド自体が冪等な操作を無条件実行し、意図した状態になっているかは
`99-verify.sh`(goss)で最後にまとめて検証する。`all.sh`で`10-base.sh`〜`99-verify.sh`を順に実行する。

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
