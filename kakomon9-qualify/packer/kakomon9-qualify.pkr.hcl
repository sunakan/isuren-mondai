packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.2"
    }
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

variable "project_url" {
  type = string
}

locals {
  region          = "ap-northeast-1"
  source_ami      = "ami-0df1235688731e6cc"
  source_serial   = "20260806"
  source_owner    = "099720109477"
  build_time      = timestamp()
  name            = "isuren/kakomon9-qualify-${formatdate("YYYYMMDD'T'hhmmss", local.build_time)}Z"
  timestamp_jst   = "${formatdate("YYYY-MM-DD'T'hh:mm:ss", timeadd(local.build_time, "9h"))}+09:00"
  official_commit = "ab4aba2b41b5f32d33c90f6b65b4bc8664e80af0"
  frontend_tree   = "a427d1c0adf7e8875d7dfbdca352de5a199edd69"
  tags = {
    Name            = local.name
    Project         = var.project_url
    OfficialSource  = "https://github.com/isucon/isucon9-qualify/commit/${local.official_commit}"
    FrontendTree    = local.frontend_tree
    OS              = "ubuntu-26.04-resolute-arm64"
    BaseAMI         = local.source_ami
    BaseOwner       = local.source_owner
    BaseImageSerial = local.source_serial
    Timestamp       = local.timestamp_jst
  }
}

source "amazon-ebs" "kakomon9_qualify" {
  ami_name        = local.name
  ami_description = "kakomon9-qualify Go practice environment provisioned by cloud-init"
  region          = local.region
  source_ami      = local.source_ami
  instance_type   = "t4g.medium"
  ssh_username    = "ubuntu"

  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  iam_instance_profile = var.iam_instance_profile
  user_data_file       = "${path.root}/../cloud-init/user-data.yaml"

  tags          = local.tags
  snapshot_tags = local.tags
  encrypt_boot  = false

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 16
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.kakomon9_qualify"]

  # cloud-init waits for this local dist upload. No artifact is downloaded from
  # a floating ref by the instance.
  provisioner "shell" {
    inline = ["mkdir -p /tmp/kakomon9-qualify-dist"]
  }

  provisioner "file" {
    source      = "${path.root}/../dist/"
    destination = "/tmp/kakomon9-qualify-dist"
  }

  provisioner "shell" {
    inline = [
      "sudo install -d -m 0755 /opt/isuren-artifacts",
      "sudo rm -rf /opt/isuren-artifacts/kakomon9-qualify",
      "sudo mv /tmp/kakomon9-qualify-dist /opt/isuren-artifacts/kakomon9-qualify",
      "sudo touch /opt/isuren-artifacts/kakomon9-qualify.ready",
      "sudo cloud-init status --wait || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "test -f /var/lib/cloud/kakomon9-qualify-provisioned || (sudo tail -n 500 /var/log/cloud-init-output.log; exit 1)",
      "echo '--- goss validate output ---'",
      "sudo sed -n '/\\[kakomon9-qualify\\] 99-verify.sh: goss .* validate start/,/\\[kakomon9-qualify\\] 99-verify.sh: goss validate end/p' /var/log/cloud-init-output.log",
      "echo '--- span data ---'",
      "sudo sed -n '/\\[kakomon9-qualify\\] spans: begin/,/\\[kakomon9-qualify\\] spans: end/p' /var/log/cloud-init-output.log",
    ]
  }

  # Seal clone-local credentials and identity only after verification evidence
  # is captured. The self-signed TLS key is deliberately retained as a public
  # test fixture and documented in image provenance.
  provisioner "shell" {
    inline = [
      "sudo truncate -s 0 /home/ubuntu/.ssh/authorized_keys",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo systemctl stop systemd-random-seed.service",
      "sudo rm -f /var/lib/systemd/random-seed",
      "sudo rm -f /usr/local/sbin/kakomon9-qualify-provision",
      "sudo cloud-init clean --logs",
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/manifest.json"
  }
}
