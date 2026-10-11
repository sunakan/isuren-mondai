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
  validation {
    condition     = var.region == "ap-northeast-1"
    error_message = "KAKOMON10-QUALIFY builds only in ap-northeast-1."
  }
}

variable "source_ami" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{17}$", var.source_ami))
    error_message = "Source AMI must be one exact image ID."
  }
}

variable "source_ami_name" {
  type = string
}

variable "source_ami_owner" {
  type = string
}

variable "root_volume_gib" {
  type = number
  validation {
    condition     = var.root_volume_gib >= 8
    error_message = "Root volume must cover the 8 GiB base snapshot."
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

variable "project_commit" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.project_commit))
    error_message = "Project commit must be one full Git SHA."
  }
}

variable "recipe_tree" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.recipe_tree))
    error_message = "Recipe tree must be one full Git tree SHA."
  }
}

variable "managed_source_tree" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.managed_source_tree))
    error_message = "Managed source tree must be one full Git tree SHA."
  }
}

variable "frontend_release_tag" {
  type = string
  validation {
    condition     = can(regex("^kakomon10-qualify-frontend-v[0-9]+[.][0-9]+[.][0-9]+$", var.frontend_release_tag))
    error_message = "Frontend must be an exact KAKOMON10-QUALIFY Release tag."
  }
}

variable "frontend_release_sha256" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.frontend_release_sha256))
    error_message = "Frontend must have its published SHA-256."
  }
}

variable "user_data_file" {
  type = string
}

variable "manifest_file" {
  type = string
}

locals {
  build_time    = timestamp()
  name          = "isuren/kakomon10-qualify-arm64-${formatdate("YYYYMMDD'T'hhmmss", local.build_time)}Z"
  timestamp_jst = "${formatdate("YYYY-MM-DD'T'hh:mm:ss", timeadd(local.build_time, "9h"))}+09:00"
  tags = {
    Name              = local.name
    CanonicalSlug     = "kakomon10-qualify"
    Project           = "https://github.com/sunakan/isuren-mondai/commit/${var.project_commit}"
    RecipeTree        = var.recipe_tree
    ManagedSourceTree = var.managed_source_tree
    Official          = "https://github.com/isucon/isucon10-qualify/commit/7e6b6cfb672cde2c57d7b594d0352dc48ce317df"
    OS                = "ubuntu-26.04-resolute-arm64"
    Architecture      = "arm64"
    SourceAMI         = var.source_ami
    BaseName          = var.source_ami_name
    BaseOwner         = var.source_ami_owner
    RootVolumeGiB     = tostring(var.root_volume_gib)
    GoVersion         = "1.26.6"
    PackerAmazon      = "1.8.2"
    Frontend          = "https://github.com/sunakan/isuren-mondai/releases/tag/${var.frontend_release_tag}"
    FrontendSHA256    = var.frontend_release_sha256
    Timestamp         = local.timestamp_jst
  }
}

#
# ARM64の一時build instance
#
# frontendと初期データはReleaseから配置し、AMI内で再生成しない。
source "amazon-ebs" "kakomon10_qualify_arm64" {
  ami_name                    = local.name
  ami_description             = "kakomon10-qualify Go practice image for Ubuntu 26.04 arm64"
  region                      = var.region
  source_ami                  = var.source_ami
  instance_type               = "t4g.small"
  ssh_username                = "ubuntu"
  vpc_id                      = var.vpc_id
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.iam_instance_profile
  user_data_file              = var.user_data_file
  associate_public_ip_address = true
  ssh_timeout                 = "30m"
  tags                        = local.tags
  snapshot_tags               = local.tags
  encrypt_boot                = false

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_gib
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.kakomon10_qualify_arm64"]

  #
  # 完走とRelease実体を確認して検証logを回収
  #
  provisioner "shell" {
    inline = [
      "sudo cloud-init status --wait || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "test -f /var/lib/cloud/kakomon10-qualify-provisioned || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "test \"$(cat /var/lib/isuren-mondai/kakomon10-qualify/recipe-ready)\" = '${var.project_commit}'",
      "sudo grep -Fxq 'source_ami=${var.source_ami}' /opt/isuren-mondai/kakomon10-qualify/recipe.txt",
      "sudo grep -Fxq 'recipe_tree=${var.recipe_tree}' /opt/isuren-mondai/kakomon10-qualify/recipe.txt",
      "sudo grep -Fxq 'managed_source_tree=${var.managed_source_tree}' /opt/isuren-mondai/kakomon10-qualify/recipe.txt",
      "test \"$(cat /tmp/kakomon10-qualify-frontend-release-tag)\" = '${var.frontend_release_tag}'",
      "test \"$(cat /tmp/kakomon10-qualify-frontend-release-sha256)\" = '${var.frontend_release_sha256}'",
      "sudo sed -n '/\\[kakomon10-qualify\\] 99-verify.sh: goss validate start/,/\\[kakomon10-qualify\\] 99-verify.sh: goss validate end/p' /var/log/cloud-init-output.log",
      "sudo sed -n '/\\[kakomon10-qualify\\] spans: begin/,/\\[kakomon10-qualify\\] spans: end/p' /var/log/cloud-init-output.log",
      "df -B1 /",
    ]
  }

  #
  # 停止状態のidentityを検証してAMI化
  #
  provisioner "shell" {
    script          = "${path.root}/seal-image.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  post-processor "manifest" {
    output     = var.manifest_file
    strip_path = true
  }
}
