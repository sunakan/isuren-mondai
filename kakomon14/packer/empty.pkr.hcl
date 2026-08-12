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
  name = "kakomon14-empty-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  ami_tags = {
    Name    = local.name
    Project = "isuren-kakomon"
    Kakomon = "kakomon14"
    OS      = "ubuntu-26.04-resolute-arm64"
    Packer  = "1"
  }
}

# 疎通確認用: プロビジョニング内容を持たない最小構成
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
  ami_description = "kakomon14 packer empty build (smoke test, no provisioning)"
  region          = var.region
  source_ami      = data.amazon-ami.ubuntu.id
  instance_type   = "t4g.small"
  ssh_username    = "ubuntu"
  vpc_id          = var.vpc_id
  subnet_id       = var.subnet_id

  tags          = local.ami_tags
  snapshot_tags = local.ami_tags

  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 8
  }
}

build {
  sources = ["source.amazon-ebs.kakomon14"]

  provisioner "shell" {
    inline = ["echo hello from packer"]
  }
}
