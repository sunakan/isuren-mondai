packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.2"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "source_ami" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{17}$", var.source_ami))
    error_message = "Source AMI must be one exact AMI ID. Image discovery belongs outside the build."
  }
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
}

variable "user_data_file" {
  type = string
}

variable "project_url" {
  type = string
}

variable "recipe_tree" {
  type = string
}

variable "frontend_release_tag" {
  type = string
  validation {
    condition     = can(regex("^kakomon13-frontend-v[0-9]+\\.[0-9]+\\.[0-9]+$", var.frontend_release_tag))
    error_message = "Frontend release tag must be one exact kakomon13 semantic-version tag."
  }
}

variable "frontend_release_sha256" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.frontend_release_sha256))
    error_message = "Frontend release SHA-256 must be one exact lowercase digest."
  }
}

locals {
  build_time    = timestamp()
  name          = "isuren/kakomon13-${formatdate("YYYYMMDD'T'hhmmss", local.build_time)}Z"
  timestamp_jst = "${formatdate("YYYY-MM-DD'T'hh:mm:ss", timeadd(local.build_time, "9h"))}+09:00"
  ami_tags = {
    Name         = local.name
    Project      = var.project_url
    RecipeTree   = var.recipe_tree
    Official     = "https://github.com/isucon/isucon13/commit/8f6afdc3603f0c661368de4659a7240862f59623"
    SourceAMI    = var.source_ami
    OS           = "ubuntu-26.04-resolute-arm64"
    Architecture = "arm64"
    FrontendTag  = var.frontend_release_tag
    FrontendSHA  = var.frontend_release_sha256
    OfficialData = "5c2ffa78c28cfc4600a8f4bb38a5d0980ed770da7260b6a0c2f89c1f3e2fe043"
    Timestamp    = local.timestamp_jst
  }
}

source "amazon-ebs" "kakomon13" {
  ami_name             = local.name
  ami_description      = "kakomon13 Go practice environment provisioned by cloud-init"
  region               = var.region
  source_ami           = var.source_ami
  instance_type        = "t4g.medium"
  ssh_username         = "ubuntu"
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  iam_instance_profile = var.iam_instance_profile
  user_data_file       = var.user_data_file

  tags          = local.ami_tags
  snapshot_tags = local.ami_tags
  encrypt_boot  = false

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 8
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.kakomon13"]

  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "test -f /var/lib/cloud/kakomon13-provisioned || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "echo '--- goss validate output ---'",
      "sudo sed -n '/\\[kakomon13\\] 99-verify.sh: goss validate start/,/\\[kakomon13\\] 99-verify.sh: goss validate end/p' /var/log/cloud-init-output.log",
      "echo '--- span data ---'",
      "sudo sed -n '/\\[kakomon13\\] spans: begin/,/\\[kakomon13\\] spans: end/p' /var/log/cloud-init-output.log",
    ]
  }

  provisioner "shell" {
    inline = [
      "test ! -e /etc/nginx/tls/pipe.u.isuren.internal.key",
      "test ! -e /home/isuren/env.sh",
      "sudo truncate -s 0 /home/ubuntu/.ssh/authorized_keys",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo systemctl stop systemd-random-seed.service",
      "sudo rm -f /var/lib/systemd/random-seed",
      "sudo cloud-init clean --logs",
    ]
  }
}
