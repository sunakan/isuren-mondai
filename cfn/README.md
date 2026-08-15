# CloudFormation

ベンチマーカー・競技サーバーを実際に起動するCloudFormationテンプレート置き場

## kakomon14-1bench-1web.yaml

### デプロイ例

```shell
# 例: GITHUB_USERS="sunakan"
GITHUB_USERS=''
AMI_ID=$(aws ec2 describe-images --owners self \
  --filters 'Name=name,Values=isuren/kakomon14-*' 'Name=state,Values=available' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)

aws cloudformation deploy \
  --stack-name kakomon14-1bench-1web \
  --template-file cfn/kakomon14-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

- `AmiId`: `mise run kakomon14:build`でビルドした最新のAMIのID(必須。上記の`describe-images`で自動解決)
- `GithubUsers`: 公開鍵を`https://github.com/<user>.keys`から取得して注入する、スペース区切りのGitHubユーザー名(任意)
    - なくてもSSM Session Manager経由でも接続可能

### ベンチ例

```shell
STACK_NAME=kakomon14-1bench-1web
WEB1_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
BENCH_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
echo "web1: ${WEB1_IP} / bench: ${BENCH_IP}"
```

`web1`・`bench`どちらも空や`None`でないことを確認する(スタック名・タグの絞り込みが正しく効いているかのチェックを兼ねる)。

GithubUsersを指定した場合はSSHで、指定しない場合はSSM Session Managerで接続する。

```shell
ssh isuren@${WEB1_IP}
ssh isuren@${BENCH_IP}
aws ssm start-session --target <Instance ID>
```

### 削除

```shell
aws cloudformation delete-stack --stack-name kakomon14-1bench-1web
```
