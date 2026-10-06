# CloudFormation

ベンチマーカー・競技サーバーを実際に起動するCloudFormationテンプレート置き場

以下の共通手順は kakomon14 を対象にしています。kakomon9-qualify・kakomon12-qualify・kakomon13 のコマンドは末尾を参照してください。

操作端末にはAWS CLI v2・jqと、SSMで接続する場合はSession Manager pluginを用意してください。

4つのテンプレートは東京リージョン `ap-northeast-1` のUbuntu 26.04 arm64 AMIを対象にし、Web・Benchに同じexact AMI IDを渡します。`AmiId` は入力パラメータなので、AMIをビルドするたびにYAMLを書き換える必要はありません。

## Web・Benchの役割

| 過去問 | Webで起動するサービス | Benchで停止・無効化するサービス | Benchの配置 |
| --- | --- | --- | --- |
| kakomon9-qualify | mysql / nginx / isucari-go | Webと同じ3サービス | `/home/isuren/isucari/bin/benchmarker` |
| kakomon12-qualify | mysql / nginx / isuports-go / blackauth | Webと同じ4サービス | `/home/isuren/bench/bench` |
| kakomon13 | mysql / pdns / nginx / isupipe-go / kakomon13-pdns-zone / kakomon13-instance-init | instance-init以外の5サービス | `/home/isuren/bench` |
| kakomon14 | mysql / nginx / isuride-go / isuride-matcher / isuride-payment_mock | Webと同じ5サービス | `/home/isuren/bench` |

WebのサービスはAMI recipeで有効化されています。BenchのUserDataは公開鍵取得より先に不要なサービスを停止・無効化します。kakomon13はzoneサービスの `Requires=` がMySQL・PowerDNSを起動するため、zoneも対象に含めます。`kakomon13-instance-init` はTLS・`env.sh` 等のruntime identityを生成し、DB/DNSを起動する依存を持たないため、Benchでも有効のまま残します。

Webは `10.42.1.11`、Benchは `10.42.1.10` です。VPC内の通信を許可しているため、WebのHTTP/HTTPS、kakomon13のDNS（TCP/UDP 53）、Benchのmock（kakomon9の5555/7001・kakomon14の12345）に相互到達できます。kakomon12・13はHTTPS、kakomon9・14の以下のベンチ例はHTTPを使います。外部からはSSHと各テンプレートで指定したHTTP/HTTPSだけを許可します。

## AMIと実行環境の記録

作成例は、対象過去問・available・arm64で絞った自分のAMIから最新のIDを一度解決します。AMI一覧はJSON出力にし、全ページを取得してから最新1件を決めます（[AWS CLIの出力形式とqueryの関係](https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-filter.html#cli-usage-filter-client-side)）。続けて表示する `Name`・`Architecture`・`Tags`（recipe identity等）を確認し、意図したrecipeのAMIである場合にそのexact IDを渡してください。古いAMIの場合は対象recipeから先にビルドします。`publish-latest-ami` は公開設定を変える操作で、テンプレートへのID入力や古いAMIの削除は行いません。

検証時は、AMIのID・recipe commit・account・リージョン・stack名を記録してください。accountは次で確認できます。

```shell
aws sts get-caller-identity --region ap-northeast-1 --query Account --output text
```

`GithubUsers` は空・単一・スペース区切りの複数を指定できます。空なら公開鍵を追加せず、SSM Session Managerを使います。SSMは各インスタンスのIAM roleに `AmazonSSMManagedInstanceCore` を付与する構成です。実際に接続できるかはagentのOnline状態とネットワークを含めて確認します。

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
#
# スタックを作成
#
set -euo pipefail
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --region ap-northeast-1 --owners self \
  --filters 'Name=name,Values=isuren/kakomon14-*' 'Name=state,Values=available' 'Name=architecture,Values=arm64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output json | jq -r '. // empty')
case "$AMI_ID" in
  ami-*) ;;
  *) echo "error: 対象のavailable arm64 AMIがありません" >&2; exit 1 ;;
esac

#
# exact AMIの入力を確認
#
aws ec2 describe-images --region ap-northeast-1 --owners self --image-ids "$AMI_ID" \
  --query 'Images[0].{ImageId:ImageId,Name:Name,Architecture:Architecture,State:State,Tags:Tags}' --output json

aws cloudformation deploy --region ap-northeast-1 \
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
#
# スタックを削除
#
aws cloudformation delete-stack --region ap-northeast-1 --stack-name kakomon14-1bench-1web
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name kakomon14-1bench-1web
```

## 接続(SSH版)

```shell
STACK_NAME=kakomon14-1bench-1web
WEB1_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

## 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon14-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

## 初期起動の確認

CloudFormationの作成完了だけではUserDataの成功を確認できません。Web・Benchの両方へ接続し、次を実行してからベンチを開始してください。UserDataは初回起動で実行されるため、既存stackへのテンプレート更新だけで新しいrole設定が適用されたとは扱いません。変更したUserDataの検証には、新しいstack名でfresh instanceを作ります。

```shell
sudo cloud-init status --wait
```

上の役割表の各サービスについて、Webは `UnitFileState=enabled`・`ActiveState=active`、Benchの停止対象は `disabled`・`inactive` を確認します。kakomon13のBenchでは `kakomon13-instance-init` が `enabled`・`active` のままであることも確認します。例:

```shell
systemctl show isupipe-go kakomon13-pdns-zone nginx pdns mysql kakomon13-instance-init \
  -p Id -p UnitFileState -p ActiveState -p SubState
```

実機のfresh起動・DNS/TLS/port・ベンチ・reboot後の同じrole状態は別々の検証です。recipeのsealed-image用Gossとfresh起動後の状態は異なるため、sealed specをそのまま起動後の合格条件にしません。reboot検証を行う場合は、両nodeの再接続後にrole状態とベンチ結果を再確認します。

## appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
/home/isuren/.local/bin/mise exec -- go build -trimpath -o isuride -ldflags "-s -w" .
sudo systemctl restart isuride-go
```

ベンチはBenchへ接続して直接実行します。kakomon14の12345番mockはベンチプロセスが起動するので、Bench上で常駐のpayment_mockを開始しません。結果ログの `結果 ... pass=true` を確認し、`--fail-on-error` の終了状態も確認します。

## ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon14-1bench-1web
BENCH_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${BENCH_IP} \
  /home/isuren/bench run --target "http://10.42.1.11:80" --addr "10.42.1.11:80" \
  --payment-url "http://10.42.1.10:12345" --fail-on-error -t 60
```

## ベンチ実行(SSM Session Manager版)

```shell
STACK_NAME=kakomon14-1bench-1web
BENCH_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon14-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
/home/isuren/bench run --target "http://10.42.1.11:80" --addr "10.42.1.11:80" \
  --payment-url "http://10.42.1.10:12345" --fail-on-error -t 60
```

## kakomon9-qualify

最終stdoutのJSONの `pass:true` を確認します。失敗でもexit 0になり得るため、終了状態だけでは判断しません。5555/7001番mockはベンチプロセスが起動します。

`kakomon9-qualify`のベンチマーカーは`-target-url`(実際に接続するURL)と`-target-host`
(HTTPのHostヘッダ)を分けて指定できる。1bench-1web構成では`-target-url`にweb1の
プライベートIPを直接渡すことで、DNSや`/etc/hosts`の書き換えなしにnginxの`server_name`
マッチを機能させられる。payment/shipmentのmockサーバーはベンチ側が全interfaceでlistenするため、
`-payment-url`/`-shipment-url`にもbenchのプライベートIPを渡せばweb側から到達できる。

### スタック作成と削除

```shell
#
# スタックを作成
#
set -euo pipefail
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --region ap-northeast-1 --owners self \
  --filters 'Name=name,Values=isuren/kakomon9-qualify-*' 'Name=state,Values=available' 'Name=architecture,Values=arm64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output json | jq -r '. // empty')
case "$AMI_ID" in
  ami-*) ;;
  *) echo "error: 対象のavailable arm64 AMIがありません" >&2; exit 1 ;;
esac

#
# exact AMIの入力を確認
#
aws ec2 describe-images --region ap-northeast-1 --owners self --image-ids "$AMI_ID" \
  --query 'Images[0].{ImageId:ImageId,Name:Name,Architecture:Architecture,State:State,Tags:Tags}' --output json

aws cloudformation deploy --region ap-northeast-1 \
  --stack-name kakomon9-qualify-1bench-1web \
  --template-file cfn/kakomon9-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
#
# スタックを削除
#
aws cloudformation delete-stack --region ap-northeast-1 --stack-name kakomon9-qualify-1bench-1web
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name kakomon9-qualify-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
WEB1_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/isucari/webapp/go
/home/isuren/.local/bin/mise exec -- go build -trimpath -o isucari -ldflags "-s -w" .
sudo systemctl restart isucari-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon9-qualify-1bench-1web
BENCH_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
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
BENCH_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon9-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$BENCH_INSTANCE_ID" \
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

`/tmp/result.json` の `pass:true` を確認します。失敗でもexit 0になり得るため、終了状態だけでは判断しません。

`kakomon13`のベンチマーカーは`--nameserver`/`--webapp`でDNSサーバー・Webアプリの接続先IPを
直接指定できるため、bench側の名前解決設定は不要。固定のワイルドカードTLS証明書がAMIに
焼き込まれ、OS trust storeにも登録済みのため、bench側で追加の証明書信頼設定も不要。

### スタック作成と削除

```shell
#
# スタックを作成
#
set -euo pipefail
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --region ap-northeast-1 --owners self \
  --filters 'Name=name,Values=isuren/kakomon13-*' 'Name=state,Values=available' 'Name=architecture,Values=arm64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output json | jq -r '. // empty')
case "$AMI_ID" in
  ami-*) ;;
  *) echo "error: 対象のavailable arm64 AMIがありません" >&2; exit 1 ;;
esac

#
# exact AMIの入力を確認
#
aws ec2 describe-images --region ap-northeast-1 --owners self --image-ids "$AMI_ID" \
  --query 'Images[0].{ImageId:ImageId,Name:Name,Architecture:Architecture,State:State,Tags:Tags}' --output json

aws cloudformation deploy --region ap-northeast-1 \
  --stack-name kakomon13-1bench-1web \
  --template-file cfn/kakomon13-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
#
# スタックを削除
#
aws cloudformation delete-stack --region ap-northeast-1 --stack-name kakomon13-1bench-1web
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name kakomon13-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon13-1bench-1web
WEB1_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon13-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
/home/isuren/.local/bin/mise exec -- go build -trimpath -o isupipe -ldflags "-s -w" .
sudo systemctl restart isupipe-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon13-1bench-1web
BENCH_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
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
BENCH_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon13-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
/home/isuren/bench run --target https://pipe.u.isuren.internal \
  --nameserver 10.42.1.11 --webapp 10.42.1.11 --dns-port 53 \
  --enable-ssl --result-path /tmp/result.json
```

## kakomon12-qualify

ベンチは `/home/isuren/bench` をcwdにして実行します。同じdirectoryの鍵・JSON fixtureと兄弟directoryの `../public/js` を読むため、このcwdを保ちます。JSON resultをstdoutに出す方式ではなく、ログの `PASSED: true` と `-exit-error-on-fail` の終了状態を確認します。

`kakomon12-qualify`のベンチマーカーは`-target-url`(HTTPのHostヘッダ/TLS SNI)と`-target-addr`
(実際に接続するTCP宛先)を分けて指定できる。1bench-1web構成では`-target-addr`にweb1の
プライベートIPを直接渡すことで、DNSや`/etc/hosts`の書き換えなしにnginxの`server_name`
マッチを機能させられる(kakomon13のPowerDNSのような仕組みは不要)。固定のワイルドカードTLS証明書が
AMIに焼き込まれ、OS trust storeにも登録済みのため、bench側で追加の証明書信頼設定も不要。

`-target-url`にはadmin hostnameではなく**base** hostname(`https://t.isuren.internal`)を渡す
(benchが自身で`admin.`prefixを組み立てるため。詳細は`kakomon12-qualify/README.md`参照)。

### スタック作成と削除

```shell
#
# スタックを作成
#
set -euo pipefail
GITHUB_USERS='<YOUR_GITHUB_USER_NAME>'
AMI_ID=$(aws ec2 describe-images --region ap-northeast-1 --owners self \
  --filters 'Name=name,Values=isuren/kakomon12-qualify-*' 'Name=state,Values=available' 'Name=architecture,Values=arm64' \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output json | jq -r '. // empty')
case "$AMI_ID" in
  ami-*) ;;
  *) echo "error: 対象のavailable arm64 AMIがありません" >&2; exit 1 ;;
esac

#
# exact AMIの入力を確認
#
aws ec2 describe-images --region ap-northeast-1 --owners self --image-ids "$AMI_ID" \
  --query 'Images[0].{ImageId:ImageId,Name:Name,Architecture:Architecture,State:State,Tags:Tags}' --output json

aws cloudformation deploy --region ap-northeast-1 \
  --stack-name kakomon12-qualify-1bench-1web \
  --template-file cfn/kakomon12-qualify-1bench-1web.yaml \
  --parameter-overrides AmiId="$AMI_ID" GithubUsers="${GITHUB_USERS}" \
  --capabilities CAPABILITY_IAM
```

```shell
#
# スタックを削除
#
aws cloudformation delete-stack --region ap-northeast-1 --stack-name kakomon12-qualify-1bench-1web
aws cloudformation wait stack-delete-complete --region ap-northeast-1 --stack-name kakomon12-qualify-1bench-1web
```

### 接続(SSH版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
WEB1_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].NetworkInterfaces[0].Association.PublicIp" --output text)
ssh isuren@${WEB1_IP}
```

### 接続(SSM Session Manager版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
WEB1_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-web1" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$WEB1_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"
```

### appのビルド(Go版)

```shell
cd /home/isuren/webapp/go
CGO_ENABLED=1 /home/isuren/.local/bin/mise exec -- go build -trimpath -o isuports -ldflags "-s -w" ./cmd/isuports
sudo systemctl restart isuports-go
```

### ベンチ実行(SSH版)

```shell
STACK_NAME=kakomon12-qualify-1bench-1web
BENCH_IP=$(aws ec2 describe-instances --region ap-northeast-1 \
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
BENCH_INSTANCE_ID=$(aws ec2 describe-instances --region ap-northeast-1 \
  --filters "Name=tag:aws:cloudformation:stack-name,Values=${STACK_NAME}" "Name=tag:Name,Values=kakomon12-qualify-bench" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" --output text)
aws ssm start-session --region ap-northeast-1 --target "$BENCH_INSTANCE_ID" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo -u isuren -i"

# セッションに入ったらベンチを実行
cd /home/isuren/bench
./bench \
  -target-url https://t.isuren.internal -target-addr 10.42.1.11:443 \
  -exit-error-on-fail -duration 60s
```
