#!/usr/bin/env bash
set -euo pipefail

state="${1:?usage: check-image-state.sh sealed|web|bench}"
case "${state}" in
sealed | web | bench) ;;
*)
  echo "error: unknown image state: ${state}" >&2
  exit 64
  ;;
esac
test "$(id -u)" -eq 0
PROVENANCE_DIR=/opt/isuren-mondai/kakomon10-qualify
READY_MARKER=/var/lib/isuren-mondai/kakomon10-qualify/recipe-ready
SERVICES=(isuumo-go nginx mysql)

#
# 共通artifactの入力と配置を観測
#
# shellcheck source=/dev/null
. /etc/os-release
test "${ID}" = ubuntu
test "${VERSION_ID}" = 26.04
test "$(dpkg --print-architecture)" = arm64
test -x /home/isuren/isuumo/webapp/go/isuumo
test -x /home/isuren/isuumo/bench/bench
test -f /home/isuren/env.sh
test -f /www/data/index.html
test -f "${READY_MARKER}"
grep -Eq '^[0-9a-f]{40}$' "${READY_MARKER}"
grep -Fxq "recipe_commit=$(cat "${READY_MARKER}")" "${PROVENANCE_DIR}/recipe.txt"
grep -Eq '^recipe_tree=[0-9a-f]{40}$' "${PROVENANCE_DIR}/recipe.txt"
grep -Eq '^managed_source_tree=[0-9a-f]{40}$' "${PROVENANCE_DIR}/recipe.txt"
grep -Eq '^frontend_release_tag=kakomon10-qualify-frontend-v[0-9]+[.][0-9]+[.][0-9]+$' "${PROVENANCE_DIR}/recipe.txt"
grep -Eq '^frontend_release_sha256=[0-9a-f]{64}$' "${PROVENANCE_DIR}/recipe.txt"
(
  cd "${PROVENANCE_DIR}"
  sha256sum --check packages.tsv.sha256
)
for path in /opt/isuren-mondai-source /home/isuren/.kakomon10-qualify-staging \
  /home/isuren/go /home/isuren/.cache/go-build /var/tmp/isuren-mondai-kakomon10-qualify; do
  test ! -e "${path}"
done

#
# seal直後と起動後を分けて観測
#
for service in "${SERVICES[@]}"; do
  if [ "${state}" = bench ]; then
    test "$(systemctl is-enabled "${service}")" = disabled
  else
    test "$(systemctl is-enabled "${service}")" = enabled
  fi
  if [ "${state}" = web ]; then
    systemctl is-active --quiet "${service}"
  else
    if systemctl is-active --quiet "${service}"; then
      echo "error: ${service} is running in ${state} state" >&2
      exit 1
    fi
  fi
done

if [ "${state}" = sealed ]; then
  test ! -s /etc/machine-id
  test ! -e /var/lib/mysql/auto.cnf
  test ! -e /var/lib/systemd/random-seed
  test ! -s /home/ubuntu/.ssh/authorized_keys
  test ! -e /home/isuren/.ssh
  test ! -e /var/lib/cloud/instance
  test ! -e /var/lib/cloud/instances
  test ! -e /var/log/cloud-init-output.log
  test -z "$(find /etc/ssh -maxdepth 1 -name 'ssh_host_*' -print)"
  test -z "$(find /var/lib/mysql -maxdepth 1 -name '*.pem' -print)"
  test -z "$(ss -H -ltn '( sport = :80 or sport = :1323 or sport = :3306 )')"
else
  grep -Eq '^[0-9a-f]{32}$' /etc/machine-id
  test -s /etc/ssh/ssh_host_ed25519_key
  test -s /etc/ssh/ssh_host_ed25519_key.pub
  ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
  if [ "${state}" = web ]; then
    test -s /var/lib/mysql/auto.cnf
    mysql --defaults-file=/dev/null --user=root --skip-column-names -e 'SELECT @@server_uuid'
    test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e 'SELECT COUNT(*) FROM isuumo.chair')" -gt 0
    test "$(mysql --defaults-file=/dev/null --user=root --skip-column-names -e 'SELECT COUNT(*) FROM isuumo.estate')" -gt 0
    curl -fsS -o /dev/null http://127.0.0.1/
    curl -fsS -o /dev/null http://127.0.0.1/api/chair/search/condition
    nginx -t
  else
    test -z "$(ss -H -ltn '( sport = :80 or sport = :1323 or sport = :3306 )')"
  fi
  printf 'machine_id=%s\n' "$(cat /etc/machine-id)"
fi

printf 'kakomon10-qualify image state: %s ok\n' "${state}"
