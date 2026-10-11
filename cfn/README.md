# CloudFormation

ベンチマーカー・競技サーバーを実際に起動するCloudFormationテンプレート置き場

以下の例は kakomon14 を対象にしています(kakomon9-qualify・kakomon10-qualify・kakomon12-qualify・kakomon13 の例は末尾を参照)

## 利用するインスタンスの料金目安

※ ボリュームや通信量などは除きます

| タイプ       | オンデマンドの時間単価 | vCPU | メモリ   |
|:----------|:------------|:-----|:------|
| c8g.large | USD 0.10006        | 2    | 4 GiB |

$1=160円で計算

| 構成                  | 時間 | USD     | 円(目安) |
|:--------------------|:---|:--------|:-|
| 2台構成(1bench + 1web) | 1  | 0.20012 | 32.0192 |
| 4台構成(1bench + 3web) | 1  | 0.40024 | 64.0384 |

## スタック作成と削除

```shell
# 作成
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --owners self \
  --filters 'Name=name,Values=isuren/kakomon14-*' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

aws cloudformation deploy \
  --stack-name kakomon14-1bench-1web \
  --template-file cfn/kakomon14-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

- `AmiId`: `mise run kakomon14:build`でビルドしたAMI_ID
- `GithubUsers`: 公開鍵を`https://github.com/<user>.keys`から取得して注入
    - スペース区切りのGitHubユーザー名(任意)
    - 公開鍵の追加は https://github.com/settings/keys で可能
    - なくてもSSM Session Manager経由でも接続可能

```shell
# 削除
aws cloudformation delete-stack --stack-name kakomon14-1bench-1web
```

## 接続(SSH版)

```shell
STACK_NAME=kakomon14-1bench-1web
WEB1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

## 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon14-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

## appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
go build -o isuride -ldflags "-s -w"
sudo systemctl restart isuride-go
```

## ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon14-1bench-1web
BENCH_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${BENCH_IP} \
  /home/isuren/bench run --target "http://10.42.1.11:80" --addr "10.42.1.11:80" \
  --payment-url "http://10.42.1.10:12345" -t 60
```

## ベンチ実行(SSM Session Manager版)

```shell
STACK_NAME=kakomon14-1bench-1web
BENCH_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
/home/isuren/bench run --target "http://10.42.1.11:80" --addr "10.42.1.11:80" \
  --payment-url "http://10.42.1.10:12345" -t 60
```

## kakomon9-qualify

`kakomon9-qualify`のベンチマーカーは`-target-url`(実際に接続するURL)と`-target-host`
(HTTPのHostヘッダ)を分けて指定できる。1bench-1web構成では`-target-url`にweb1の
プライベートIPを直接渡すことで、DNSや`/etc/hosts`の書き換えなしにnginxの`server_name`
マッチを機能させられる。payment/shipmentのmockサーバーはベンチ側が全interfaceでlistenするため、
`-payment-url`/`-shipment-url`にもbenchのプライベートIPを渡せばweb側から到達できる。

### スタック作成と削除

```shell
# 作成
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --owners self \
  --filters 'Name=name,Values=isuren/kakomon9-qualify-*' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

aws cloudformation deploy \
  --stack-name kakomon9-qualify-1bench-1web \
  --template-file cfn/kakomon9-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
# 削除
aws cloudformation delete-stack --stack-name kakomon9-qualify-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
WEB1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/isucari/webapp/go
go build -o isucari -ldflags "-s -w"
sudo systemctl restart isucari-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
BENCH_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${BENCH_IP} \
  'cd /home/isuren/isucari && ./bin/benchmarker \
    -target-url http://10.42.1.11 -target-host isucon9.isuren.internal \
    -payment-url http://10.42.1.10:5555 -shipment-url http://10.42.1.10:7001 \
    -payment-port 5555 -shipment-port 7001 \
    -data-dir initial-data -static-dir webapp/public/static'
```

### ベンチ実行(SSM Session Manager版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
BENCH_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
cd /home/isuren/isucari
./bin/benchmarker \
  -target-url http://10.42.1.11 -target-host isucon9.isuren.internal \
  -payment-url http://10.42.1.10:5555 -shipment-url http://10.42.1.10:7001 \
  -payment-port 5555 -shipment-port 7001 \
  -data-dir initial-data -static-dir webapp/public/static
```

## kakomon13

AMI IDはスタック作成時に引数で指定します。以下は東京リージョンで所有する、利用可能なarm64 AMIの最新版を選んで渡す例です。AMIをビルドするたびにYAMLを書き換える必要はありません。この作成例にはAWS CLIとjqが必要です。

`kakomon13`のベンチマーカーは`--nameserver`/`--webapp`でDNSサーバー・Webアプリの接続先IPを
直接指定できるため、bench側の名前解決設定は不要。固定のワイルドカードTLS証明書がAMIに
焼き込まれ、OS trust storeにも登録済みのため、bench側で追加の証明書信頼設定も不要。

### スタック作成と削除

```shell
#
# 最新AMIでスタックを作成
#
set -euo pipefail
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --region ap-northeast-1 --owners self \
  --filters 'Name=name,Values=isuren/kakomon13-*' 'Name=state,Values=available' 'Name=architecture,Values=arm64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output json | jq -r '. // empty')
if [ -z "$AMI_ID" ]; then
  echo '利用可能なkakomon13 AMIが見つかりません' >&2
  exit 1
fi

aws cloudformation deploy --region ap-northeast-1 \
  --stack-name kakomon13-1bench-1web \
  --template-file cfn/kakomon13-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
# 削除
aws cloudformation delete-stack --stack-name kakomon13-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon13-1bench-1web
WEB1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon13-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
go build -o isupipe -ldflags "-s -w"
sudo systemctl restart isupipe-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon13-1bench-1web
BENCH_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${BENCH_IP} \
  '/home/isuren/bench run --target https://pipe.u.isuren.internal \
    --nameserver 10.42.1.11 --webapp 10.42.1.11 --dns-port 53 \
    --enable-ssl --result-path /tmp/result.json'
```

### ベンチ実行(SSM Session Manager版)

```shell
STACK_NAME=kakomon13-1bench-1web
BENCH_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
/home/isuren/bench run --target https://pipe.u.isuren.internal \
  --nameserver 10.42.1.11 --webapp 10.42.1.11 --dns-port 53 \
  --enable-ssl --result-path /tmp/result.json
```

## kakomon12-qualify

`kakomon12-qualify`のベンチマーカーは`-target-url`(HTTPのHostヘッダ/TLS SNI)と`-target-addr`
(実際に接続するTCP宛先)を分けて指定できる。1bench-1web構成では`-target-addr`にweb1の
プライベートIPを直接渡すことで、DNSや`/etc/hosts`の書き換えなしにnginxの`server_name`
マッチを機能させられる(kakomon13のPowerDNSのような仕組みは不要)。固定のワイルドカードTLS証明書が
AMIに焼き込まれ、OS trust storeにも登録済みのため、bench側で追加の証明書信頼設定も不要。

`-target-url`にはadmin hostnameではなく**base** hostname(`https://t.isuren.internal`)を渡す
(benchが自身で`admin.`prefixを組み立てるため。詳細は`kakomon12-qualify/README.md`参照)。

### スタック作成と削除

```shell
# 作成
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --owners self \
  --filters 'Name=name,Values=isuren/kakomon12-qualify-*' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

aws cloudformation deploy \
  --stack-name kakomon12-qualify-1bench-1web \
  --template-file cfn/kakomon12-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
# 削除
aws cloudformation delete-stack --stack-name kakomon12-qualify-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
WEB1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
go build -o isuports -ldflags "-s -w"
sudo systemctl restart isuports-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
BENCH_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${BENCH_IP} \
  'cd /home/isuren/bench && ./bench \
    -target-url https://t.isuren.internal -target-addr 10.42.1.11:443 \
    -exit-error-on-fail -duration 60s'
```

### ベンチ実行(SSM Session Manager版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
BENCH_INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
cd /home/isuren/bench
./bench \
  -target-url https://t.isuren.internal -target-addr 10.42.1.11:443 \
  -exit-error-on-fail -duration 60s
```

## kakomon10-qualify

Ubuntu 26.04 ARM64のGo版を、`c8g.large` 2台(1bench + 1web、各30 GiB gp3)で起動します。
東京リージョン固定で、webは`10.42.1.11`のHTTP `:80`、benchは`10.42.1.10`です。
bench側のApplication/nginx/MySQLは停止し、webへHTTPで接続します。

2026-10-11にrecipe commit `936016b8c7cf6c16c0027059ce73ea90a93578b5`から作った
`ami-0006f9a470d2fb6ee`で、fresh起動・ベンチ・reset/recovery・両台reboot・ブラウザー操作を
検証済みです。AMIはprivateのまま保持し、旧失敗AMI/snapshotは削除済みです。
詳細は[10qのAWS検証記録](../kakomon10-qualify/README.md#aws-verification-2026-10-11)を参照してください。

AMI所有アカウントで使う場合、public公開(publish)は不要です。別アカウントから起動する場合は、
スタック作成の前に、そのアカウントへの[AMI共有](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-explicit.html)か
[AMIのpublic公開](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-intro.html)を行います。
このAMIからの起動には、参照するEBS snapshotを単独でpublic公開する必要はありません。
AMIは東京リージョンで利用してください。

### スタック作成と削除

`AmiId`は必須引数で、YAMLにdefaultはありません。利用する検証済みARM64 AMIのexact IDを
指定します。以下は所有アカウントで検証したprivate AMIを使う例です。
`GithubUsers`は任意です。空欄ならSSM Session Managerで接続でき、SSHを使う場合は
スペース区切りのGitHubユーザー名を指定して`https://github.com/<user>.keys`の公開鍵を配置します。
手元の端末ではAWS CLIを、SSM接続ではSession Manager pluginも使用します。

```shell
#
# 検証済みAMIでスタックを作成
#
set -euo pipefail
STACK_NAME=kakomon10-qualify-1bench-1web
AMI_ID='ami-0006f9a470d2fb6ee'
GITHUB_USERS=''

aws cloudformation deploy --region ap-northeast-1 \
  --stack-name "$STACK_NAME" \
  --template-file cfn/kakomon10-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="$GITHUB_USERS" \
  --capabilities CAPABILITY_IAM
```

練習終了後は、作成したスタックだけを削除し、完了を待ちます。AMIと共有Packerネットワークは保持します。

```shell
#
# 練習スタックを削除
#
STACK_NAME=kakomon10-qualify-1bench-1web
aws cloudformation delete-stack --region ap-northeast-1 --stack-name "$STACK_NAME"
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name "$STACK_NAME"
```

### Webへ接続(SSM Session Manager)

手元の端末でスタックのOutputsからWebのinstance IDを取得します。

```shell
#
# Webのisurenセッションへ接続
#
STACK_NAME=kakomon10-qualify-1bench-1web
WEB_INSTANCE_ID=$(aws cloudformation describe-stacks --region ap-northeast-1 \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='WebInstanceId'].OutputValue | [0]" --output text)
aws ssm start-session --region ap-northeast-1 --target "$WEB_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

Webのセッション内でUser Dataの完走と役割を確認します。

```shell
#
# Webの初期化を確認
#
sudo cloud-init status --wait
sudo /usr/local/libexec/kakomon10-qualify-check-image-state web
```

### appの再ビルド(Go版)

Webの`isuren`セッション内で、配置済みGo runtimeを使ってビルドし、Applicationを再起動します。

```shell
#
# Go版を再ビルド
#
set -euo pipefail
cd /home/isuren/isuumo/webapp/go
/home/isuren/.local/bin/mise exec -- go build -mod=readonly -trimpath -o isuumo .
sudo systemctl restart isuumo-go
```

### ベンチ実行(SSM Session Manager)

手元の端末でbenchのセッションへ接続します。

```shell
#
# Benchのisurenセッションへ接続
#
STACK_NAME=kakomon10-qualify-1bench-1web
BENCH_INSTANCE_ID=$(aws cloudformation describe-stacks --region ap-northeast-1 \
  --stack-name "$STACK_NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='BenchInstanceId'].OutputValue | [0]" --output text)
aws ssm start-session --region ap-northeast-1 --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

benchの`isuren`セッション内で実行します。`bench/`をcwdにすることで、相対pathの
`../initial-data`と`../webapp/fixture`を解決できます。benchは失敗時にもexit 0を返すため、
stdout末尾のJSONの`pass == true`を合否に使います。stdout/stderrは別々に保存します。

```shell
#
# Benchの役割を確認して実行
#
set -euo pipefail
sudo cloud-init status --wait
sudo /usr/local/libexec/kakomon10-qualify-check-image-state bench
cd /home/isuren/isuumo/bench
./bench --target-url http://10.42.1.11 >bench.stdout.jsonl 2>bench.stderr.log
tail -n 1 bench.stdout.jsonl | jq -e '.pass == true'
```
