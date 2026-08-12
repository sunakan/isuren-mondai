# isuren-kakomon

ISUCON過去問をGo実装だけに絞り、Packerで自分用のAMIとして焼いて保守するリポジトリ。
詳しい方針は [aws-bastion/docs/isuren-kakomon-strategy.md](../docs/isuren-kakomon-strategy.md) を参照。

## 前提

初回のみ、このディレクトリで`mise`の設定ファイルを信頼する。

```bash
mise trust
```

## 1. Packerビルド用VPCを用意する(初回のみ)

過去問間で共有する永続VPC。一度デプロイしたら基本的に消さない。

```bash
mise up-packer-network
```

## 2. 過去問ごとにPackerビルドする

現状はkakomon14の疎通確認用(プロビジョニング内容なし)のみ。

```bash
mise build-kakomon14
```

成功すると末尾に `AMIs were created: ap-northeast-1: ami-xxxxxxxx` のようにAMI IDが出力される。

## 3. 作ったAMIから実際にEC2を起動して確認する

```bash
mise verify-ami ami-xxxxxxxx
```

SSM経由で疎通確認する場合:

```bash
INSTANCE_ID="$(aws cloudformation describe-stacks --region ap-northeast-1 \
  --stack-name verify-ami-ami-xxxxxxxx \
  --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text)"

COMMAND_ID="$(aws ssm send-command --region ap-northeast-1 \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" --parameters commands="echo pong" \
  --query "Command.CommandId" --output text)"

aws ssm get-command-invocation --region ap-northeast-1 \
  --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query "{Status:Status,StdOut:StandardOutputContent}" --output json
```

## 4. 確認用インスタンスを片付ける

```bash
mise down-verify-ami
```

fzfでの一覧選択が使えない場合(AIエージェント等)は、直接スタック名を指定して削除する。

```bash
aws cloudformation delete-stack --region ap-northeast-1 --stack-name verify-ami-ami-xxxxxxxx
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name verify-ami-ami-xxxxxxxx
```

## AMIの削除(不要になった場合)

AMIの登録解除だけではEBSスナップショットが残るので、両方削除する。

```bash
SNAPSHOT_ID="$(aws ec2 describe-images --region ap-northeast-1 --image-ids ami-xxxxxxxx \
  --query "Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=null].Ebs.SnapshotId" --output text)"

aws ec2 deregister-image --region ap-northeast-1 --image-id ami-xxxxxxxx
aws ec2 delete-snapshot --region ap-northeast-1 --snapshot-id "$SNAPSHOT_ID"
```

## Packerビルド用VPCを片付ける(基本不要)

```bash
mise down-packer-network
```
