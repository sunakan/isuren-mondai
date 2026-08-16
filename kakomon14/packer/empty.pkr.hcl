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

# packer-network.yamlのPackerInstanceProfile(AmazonSSMManagedInstanceCore付き)。
# ビルド中の一時インスタンスへSSM Session Manager経由で接続し、cloud-initの進行状況を
# 直接デバッグできるようにするため(mise-tasks/kakomon14/buildがCloudFormation Outputsから渡す)。
variable "iam_instance_profile" {
  type = string
}

variable "user_data_file" {
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
    Name         = local.name
    Project      = var.project_url
    Base         = var.base_url
    OS           = "ubuntu-26.04-resolute-arm64"
    Architecture = "arm64"
    SourceAMI    = var.source_ami
    Timestamp    = local.timestamp_jst
  }
}

# AMI buildではfrontendをビルドせず、事前ビルド済みReleaseを取得する。
# AMI build hostはt4g.small(2vCPU/2GiB)を採用する。実行時のインスタンスタイプとは別の設定である。
source "amazon-ebs" "kakomon14" {
  ami_name = local.name
  # "isucon"はさくらインターネット株式会社の商標のため、Public AMI化する方針を踏まえ含めない
  # (README.mdの注記、nginx TLS証明書のホスト名変更(commit 9ef6955)と同様の対応)。
  ami_description      = "kakomon14 webapp environment (Go) provisioned by cloud-init"
  region               = var.region
  source_ami           = var.source_ami
  instance_type        = "t4g.small"
  ssh_username         = "ubuntu"
  vpc_id               = var.vpc_id
  subnet_id            = var.subnet_id
  iam_instance_profile = var.iam_instance_profile

  # cloud-init/generate-user-data.pyが生成した一時ファイル。git cloneで実体を取得する構成の
  # ため内容はごく小さく、EC2 User Dataの16KB制限(base64後)を気にする必要がない。
  user_data_file = var.user_data_file

  tags          = local.ami_tags
  snapshot_tags = local.ami_tags

  # AWS管理キー(aws/ebs)で暗号化するとPublic AMIにできない
  # 暗号化しないことを明示
  encrypt_boot = false

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
      # OTel trace化用の生データ(all.sh参照)。mise-tasks/kakomon14/buildがpacker build完了後に
      # このビルドログからstep/provisioning.allの開始終了時刻・ディスク使用量を抜き出しspan化する。
      "echo '--- span data ---'",
      "sudo sed -n '/\\[kakomon14\\] spans: begin/,/\\[kakomon14\\] spans: end/p' /var/log/cloud-init-output.log",
    ]
  }

  # 80-frontend.shが解決した具体的なtagとarchive SHA-256を取得する。
  # AMIタグ(Frontend/FrontendSHA256)への焼き込みはmise-tasks/kakomon14/buildタスク側で行う
  # (この時点ではAMI IDがまだ存在しないため、tagsブロックに直接は書けない)。
  provisioner "file" {
    source      = "/tmp/kakomon14-frontend-release-tag"
    destination = "${path.root}/frontend-release-tag.txt"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/tmp/kakomon14-frontend-release-sha256"
    destination = "${path.root}/frontend-release-sha256.txt"
    direction   = "download"
  }

  # AMI化直前のクリーンアップ。ログ抽出・fileダウンロードより後に置く
  # (cloud-init cleanで/var/log/cloud-init-output.logが消え、それより前段のログ抽出が壊れるため)。
  provisioner "shell" {
    inline = [
      # ubuntuユーザーのauthorized_keysには、Packerが一時的に使うSSH公開鍵がAMI化後も残る
      # (対応する秘密鍵はPacker側の使い捨てで実害は低いが、公開するAMIに素性不明の鍵を
      # 残したくない)。
      "sudo rm -f /tmp/kakomon14-frontend-release-tag /tmp/kakomon14-frontend-release-sha256",
      "sudo truncate -s 0 /home/ubuntu/.ssh/authorized_keys",
      # machine-idはcloud-initのSSHホストキー再生成(cc_ssh)と異なりビルド時点の値がそのまま
      # クローンされた全インスタンスに引き継がれる(実機で複数インスタンスが同一machine-idを
      # 持つことを確認済み)。空にしておけば次回起動時にsystemdが自動生成する。
      "sudo truncate -s 0 /etc/machine-id",
      # cloud-initのsshモジュール(ssh_deletekeys: true、デフォルト)は起動時に既存鍵を検知して
      # 削除・再生成するため、鍵を消さなくても実行時の安全性(インスタンスごとに異なる鍵になること)
      # 自体は保たれる(実機確認済み)。ただしそれはcloud-init側の設定に依存した間接的な保証であり、
      # AWSの公開AMI作成ベストプラクティスは鍵ファイル自体をAMIスナップショットに残さないことを
      # 直接推奨しているため、より確実な対応として削除しておく。
      "sudo rm -f /etc/ssh/ssh_host_*",
      # systemdのrandom-seedも複製元から削除するのがイメージ作成の定石(起動時にsystemdが
      # 再生成する)。machine-id/SSH host keyほどの実害は無いが対応コストが低いため合わせて行う。
      # systemd-random-seed.serviceはConflicts=shutdown.target(ExecStop=...save)を持つため、
      # rm -fするだけだとPackerのインスタンス停止(内部的にはOS通常のshutdownシーケンス)時に
      # このExecStopが発火し、削除したファイルが保存し直されて復活してしまう(実機のunit定義で
      # 確認済み)。事前にサービス自体をstopしてinactiveにしておけば、shutdown時に再度stopが
      # 要求されてもExecStopは実行されない。
      "sudo systemctl stop systemd-random-seed.service",
      "sudo rm -f /var/lib/systemd/random-seed",
      # cloud-initはinstance-idの変化を検知してruncmd等を自動的に再実行するため、cleanしなくても
      # 機能的には問題ない(実機確認済み)。ただしAMIビルド時のログが新規起動インスタンスの
      # 初回ログに混在するとデバッグしづらいため、ログも含めてクリーンにしておく。
      "sudo cloud-init clean --logs",
    ]
  }
}
