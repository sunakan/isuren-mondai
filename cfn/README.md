# CloudFormation

ベンチマーカー・競技サーバーを実際に起動するCloudFormationテンプレート置き場

以下の例は kakomon14 を対象にしています(kakomon9-qualify の例は末尾を参照)

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
