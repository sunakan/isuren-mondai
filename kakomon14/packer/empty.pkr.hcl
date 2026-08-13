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

locals {
  name = "kakomon14-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  ami_tags = {
    Name    = local.name
    Project = "isuren-mondai"
    Kakomon = "kakomon14"
    OS      = "ubuntu-26.04-resolute-arm64"
    Packer  = "1"
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
  instance_type   = "t4g.medium"
  ssh_username    = "ubuntu"
  vpc_id          = var.vpc_id
  subnet_id       = var.subnet_id

  # cloud-init/generate-user-data.pyが生成したgzip版。
  # EC2のUser Dataはbase64エンコード後16KBまでのため、生のuser-data.yamlではなくこちらを使う。
  user_data_file = "${path.root}/../cloud-init/user-data.yaml.gz"

  tags          = local.ami_tags
  snapshot_tags = local.ami_tags

  # bastion実測(mysqlデータ242MB+isucon14リポジトリ427MB+mise本体・モジュールキャッシュ624MB≒計1.3GB)の
  # 3倍以上の余裕を持たせる(docs/plans/kakomon14/completed/20260812182550-cloud-init-handoff-prep.md)
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 16
  }
}

build {
  sources = ["source.amazon-ebs.kakomon14"]

  # user_dataのcloud-init(write_files+runcmdでall.shを実行)が完了するまで待ってからAMI化する。
  # all.sh側がset -euo pipefailで冪等かつエラー時に非ゼロ終了するため、
  # cloud-init status --waitの終了コードでプロビジョニングの成否がそのまま判定できる。
  # 失敗時はPackerがインスタンスを即座に破棄してしまいログを見返せなくなるため、
  # 失敗を検知したらAMI化前にログをbuild出力へ吐いてから非ゼロ終了する。
  provisioner "shell" {
    inline = ["sudo cloud-init status --wait || (echo '--- cloud-init-output.log (tail) ---'; sudo tail -n 300 /var/log/cloud-init-output.log; exit 1)"]
  }
}
