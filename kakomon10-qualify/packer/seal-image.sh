#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" -eq 0
test -f /var/lib/cloud/kakomon10-qualify-provisioned
test -f /var/lib/isuren-mondai/kakomon10-qualify/recipe-ready
test -x /usr/local/libexec/kakomon10-qualify-check-image-state

#
# 問題serviceを停止してDB identityを除去
#
# enabledは維持し、fresh webの起動時にMySQLがUUIDと自動TLS鍵を生成する。
# env.shの本家DB値は公開練習用defaultなので保持する。
systemctl stop isuumo-go nginx mysql
rm -f /var/lib/mysql/auto.cnf /var/lib/mysql/*.pem
for unit in amazon-ssm-agent.service snap.amazon-ssm-agent.amazon-ssm-agent.service; do
  if systemctl cat "${unit}" >/dev/null 2>&1; then
    systemctl stop "${unit}"
  fi
done
rm -rf /var/lib/amazon/ssm /var/log/amazon/ssm

#
# build時のcacheと接続identityを除去
#
rm -rf /opt/isuren-mondai-source /home/isuren/.kakomon10-qualify-staging \
  /home/isuren/go /home/isuren/.cache/go-build /var/tmp/isuren-mondai-kakomon10-qualify
rm -f /tmp/kakomon10-qualify-frontend-release-tag /tmp/kakomon10-qualify-frontend-release-sha256
rm -rf /home/isuren/.ssh
rm -f /home/ubuntu/.ssh/authorized_keys /root/.ssh/authorized_keys
rm -f /home/ubuntu/.bash_history /home/isuren/.bash_history /root/.bash_history
rm -f /etc/ssh/ssh_host_*
systemctl stop systemd-random-seed.service
rm -f /var/lib/systemd/random-seed
hostnamectl set-hostname localhost
sed -i -E 's/^127[.]0[.]1[.]1[[:space:]].*/127.0.1.1 localhost/' /etc/hosts

#
# 次回起動のprovider初期化だけを残す
#
# 永続recipe-readyは保持する。古いUser Dataが再投入されてもrecipeを再実行しない。
# cloud-init自体はfresh EC2のSSH鍵生成とCFnのrole User Dataを実行する。
cloud-init clean --logs --seed
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

/usr/local/libexec/kakomon10-qualify-check-image-state sealed
