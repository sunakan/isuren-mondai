packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

# packer-network.yamlのPackerInstanceProfile(AmazonSSMManagedInstanceCore付き)。
# ビルド中の一時インスタンスへSSM Session Manager経由で接続し、cloud-initの進行状況を
# 直接デバッグできるようにするため(mise-tasks/kakomon14/buildがCloudFormation Outputsから渡す)。
variable "iam_instance_profile" {
  type = string
}

# isuren-mondai自身のビルド元コミットへのGitHub URL(mise-tasks/kakomon14/buildが
# git rev-parse HEADから組み立てて渡す)。cloud-initのgit clone対象と同じコミットを指す。
variable "project_url" {
  type = string
}

# 取り込み元(本家isucon/isucon14)のコミットへのGitHub URL(mise-tasks/kakomon14/buildが
# 50-source.shのISUCON14_COMMITから組み立てて渡す)。
variable "base_url" {
  type = string
}

locals {
  # timestamp()は呼び出すたびに評価され値が変わりうる(公式ドキュメントに明記)ため、
  # Name/Timestampタグで別々に呼ぶと評価タイミングのズレで秒単位の不一致が起こりうる。
  # 1回だけ呼んでlocalに固定し、両方から共有する。
  build_time = timestamp()
  # AMI Nameは文字種制限(+・:が使えない)があるため、ISO8601のUTC基本形式(Z表記)にする。
  name = "isuren/kakomon14-${formatdate("YYYYMMDD'T'hhmmss", local.build_time)}Z"
  # NameとことなりタグのValueには文字種制限が無いため、こちらはISO8601拡張形式でJSTの
  # 正しいオフセット表記(+09:00)にする。timeaddでUTC瞬間を+9hずらしてからformatdateしているのは
  # HCLにタイムゾーン変換関数が無いため(実際にタイムゾーン変換しているわけではなく、
  # 表示上のJST値を作るための数値加算。付与する+09:00はこの値に対応する文字列)。
  timestamp_jst = "${formatdate("YYYY-MM-DD'T'hh:mm:ss", timeadd(local.build_time, "9h"))}+09:00"
  ami_tags = {
    Name      = local.name
    Project   = var.project_url
    Base      = var.base_url
    OS        = "ubuntu-26.04-resolute-arm64"
    Timestamp = local.timestamp_jst
  }
}

data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-arm64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"] # Canonical
  region      = var.region
}

source "amazon-ebs" "kakomon14" {
  ami_name        = local.name
  ami_description = "kakomon14 isucon14(Go) provisioned by cloud-init"
  region          = var.region
  source_ami      = data.amazon-ami.ubuntu.id
  # ISUCON14公式の競技者VM(c5.large: 2vCPU/4GiB)とメモリ量を揃える。
  # t4g.small(2GiB)ではフロントエンドビルド等でOOMのリスクがあるため避ける。
  instance_type        = "t4g.medium"
  ssh_username         = "ubuntu"
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  iam_instance_profile = var.iam_instance_profile

  # cloud-init/generate-user-data.pyが生成したもの。git cloneで実体を取得する構成のため
  # 内容はごく小さく、EC2 User Dataの16KB制限(base64後)を気にする必要がない。
  user_data_file = "${path.root}/../cloud-init/user-data.yaml"

  tags          = local.ami_tags
  snapshot_tags = local.ami_tags

  # AWS管理キー(aws/ebs)での暗号化は追加課金なし(https://aws.amazon.com/kms/pricing/)。
  # kms_key_idを指定しない場合はaws/ebsが使われる。
  encrypt_boot = true

  # 実機のAMI検証(verify-ami)でdu -x /を実測したところ実データは3.2GBだった。EBSスナップショットは
  # 使用済みブロックを差分記録する仕組みのため、削除済みファイルの残骸ブロック(TRIM/discard未対応の
  # ため解放されない)を含めても収まる見込みで16から8に縮小し、AMIサイズの縮小を狙う。
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 8
    # デフォルトfalseのため明示しないと、一時ビルドインスタンス終了後もルートボリュームが
    # 削除されずビルドのたびに蓄積する(Packer公式ドキュメントに明記された既知の注意点。
    # 実際に本プロジェクトでも過去のビルドで複数の未アタッチボリュームが蓄積していたことを確認した)。
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.kakomon14"]

  # user_dataのcloud-init(write_files+runcmdでall.shを実行)が完了するまで待ってからAMI化する。
  # 失敗時はPackerがインスタンスを即座に破棄してしまいログを見返せなくなるため、
  # 失敗を検知したらAMI化前にログをbuild出力へ吐いてから非ゼロ終了する。
  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait || (echo '--- cloud-init-output.log (tail) ---'; sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      # runecmd内のコマンド(bash all.sh)が非ゼロ終了しても、cloud-init status --waitはstatus: doneを
      # 返すことがある(実機で確認済み: goss validate失敗でall.shが停止してもここまで来てしまった)。
      # all.shが最後まで完走した証拠としてマーカーファイルの存在を別途確認する。
      "test -f /var/lib/cloud/kakomon14-provisioned || (echo '--- provisioning failed (marker file not found): cloud-init-output.log (tail) ---'; sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      # 成功時はcloud-init-output.log全体をtailしないため、goss validateの結果だけが
      # ビルドログから一切見えなくなる(99-verify.shが仕込むマーカー行で範囲を抜き出す)。
      "echo '--- goss validate output ---'",
      "sudo sed -n '/\\[kakomon14\\] 99-verify.sh: goss validate start/,/\\[kakomon14\\] 99-verify.sh: goss validate end/p' /var/log/cloud-init-output.log",
    ]
  }

  # 80-frontend.sh(FRONTEND_RELEASE_TAG=latest時)が解決した具体的なタグを取得する。
  # AMIタグ(Frontend)への焼き込みはmise-tasks/kakomon14/buildタスク側で行う
  # (この時点ではAMI IDがまだ存在しないため、tagsブロックに直接は書けない)。
  provisioner "file" {
    source      = "/tmp/kakomon14-frontend-release-tag"
    destination = "${path.root}/frontend-release-tag.txt"
    direction   = "download"
  }
}
