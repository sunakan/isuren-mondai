# cfn

kakomon14等のAMIを使ってベンチマーカー・競技サーバーを実際に起動するための、利用者向けCloudFormationテンプレート置き場。
AMI自体の作り方(Packer/provisioning)は`kakomon14/`配下を参照。

## kakomon14-1bench-1web.yaml

kakomon14 AMIから「ベンチマーカー1台+競技サーバー1台」構成を起動する使い捨てスタック。

### 展開

```shell
aws cloudformation deploy \
  --stack-name kakomon14-1bench-1web \
  --template-file cfn/kakomon14-1bench-1web.yaml \
  --parameter-overrides AmiId=ami-xxxxxxxxxxxxxxxxx GithubUsers="your-github-id" \
  --capabilities CAPABILITY_IAM
```

- `AmiId`: `mise run kakomon14:build`でビルドしたAMIのID(必須)
- `GithubUsers`: 公開鍵を`https://github.com/<user>.keys`から取得して注入する、スペース区切りのGitHubユーザー名(任意。省略した場合はSSM Session Manager経由でのみ接続可能)

### 接続

```shell
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=kakomon14-bench,kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,InstanceId:InstanceId,PublicIp:PublicIp}" \
  --output table
```

GithubUsersを指定した場合はSSHで、指定しない場合はSSM Session Managerで接続する。

```shell
ssh isuren@<Public IP>
aws ssm start-session --target <Instance ID>
```

### 削除

```shell
aws cloudformation delete-stack --stack-name kakomon14-1bench-1web
```
