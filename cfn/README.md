# CloudFormation

ベンチマーカー・競技サーバーを実際に起動するCloudFormationテンプレート置き場

以下の例は kakomon14 を対象にしています

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
