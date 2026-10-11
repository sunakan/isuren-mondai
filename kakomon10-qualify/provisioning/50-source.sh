#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

#
# managed sourceの入力を確認
#
require_file "${MANAGED_SOURCE_DIR}/NOTICE.md"
require_file "${MANAGED_SOURCE_DIR}/LICENSE"
require_file "${MANAGED_SOURCE_DIR}/webapp/go/main.go"
require_file "${MANAGED_SOURCE_DIR}/webapp/mysql/db/0_Schema.sql"
require_file "${PROVISIONING_DIR}/runtime/env.sh"

#
# 本家の相対pathを保持して配置
#
# webappとbenchのcwd相対参照を維持する。
rm -rf "${APP_ROOT}"
install -d -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" "${APP_ROOT}"
rsync -a "${MANAGED_SOURCE_DIR}/webapp/" "${APP_ROOT}/webapp/"
rsync -a "${MANAGED_SOURCE_DIR}/bench/" "${APP_ROOT}/bench/"
rsync -a "${MANAGED_SOURCE_DIR}/initial-data/" "${APP_ROOT}/initial-data/"

#
# provenanceと読み取り専用検証を配置
#
install -m 0644 "${MANAGED_SOURCE_DIR}/LICENSE" "${PROVENANCE_DIR}/LICENSE"
install -m 0644 "${MANAGED_SOURCE_DIR}/NOTICE.md" "${PROVENANCE_DIR}/managed-source-NOTICE.md"
install -m 0644 "${PROVISIONING_DIR}/goss.yaml" "${PROVENANCE_DIR}/goss-fresh-boot.yaml"
install -d -m 0755 /usr/local/libexec
install -m 0755 "${PROJECT_ROOT}/kakomon10-qualify/scripts/benchmark_data.py" \
  /usr/local/libexec/kakomon10-qualify-check-benchmark-data
install -m 0755 "${PROJECT_ROOT}/kakomon10-qualify/scripts/check-image-state.sh" \
  /usr/local/libexec/kakomon10-qualify-check-image-state
install -m 0644 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${MANAGED_SOURCE_DIR}/LICENSE" "/home/${ISUREN_USER}/LICENSE"
# 本家の公開DB defaultをserviceと参加者shellで共有する。
install -m 0755 -o "${ISUREN_USER}" -g "${ISUREN_USER}" \
  "${PROVISIONING_DIR}/runtime/env.sh" "/home/${ISUREN_USER}/env.sh"

#
# exact recipeと公式起点を記録
#
cat >"${PROVENANCE_DIR}/recipe.txt" <<EOF
canonical_slug=kakomon10-qualify
recipe_commit=${RECIPE_COMMIT}
recipe_tree=$(git -C "${PROJECT_ROOT}" rev-parse "${RECIPE_COMMIT}:kakomon10-qualify")
managed_source_tree=$(git -C "${PROJECT_ROOT}" rev-parse "${RECIPE_COMMIT}:upstream/isucon10-qualify")
official_repository=https://github.com/isucon/isucon10-qualify.git
official_commit=7e6b6cfb672cde2c57d7b594d0352dc48ce317df
license=MIT; Copyright (c) 2020 isucon10-qualify
region=ap-northeast-1
os=ubuntu-26.04
architecture=arm64
source_ami=${SOURCE_AMI_ID:-not-applicable}
packer_amazon_plugin=1.8.2
application=:1323; nginx upstream=127.0.0.1:1323
application_environment=/home/${ISUREN_USER}/env.sh
benchmark=${APP_ROOT}/bench/bench
benchmark_cwd=${APP_ROOT}/bench
benchmark_result=final stdout JSON pass; exit 0 does not imply pass
reset=POST /initialize
frontend=CI/Release static export (Next.js, unmodified official version); see /www/data
EOF

chown -R "${ISUREN_USER}:${ISUREN_USER}" "${APP_ROOT}"
log "50-source.sh: managed source deployed to ${APP_ROOT}"
