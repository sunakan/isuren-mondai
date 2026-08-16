#!/usr/bin/env bash
# kakomon13/kakomon14のPacker AMI build taskでのOTel trace送信を共有するヘルパー。
# EC2側のtarget別all.shは生データ記録のみを行い、実際のspan生成・OTLP送信はここ(Mac側)が
# packer build完了後に一括して行う(APIキーをEC2/AMIへ一切渡さないための設計。詳細は
# tmp/20260814205658-otel-trace-plan.md参照)。送信手段はMackerelがOTLP/HTTP JSONを受理しない
# (http/protobuf必須)ことが判明したため、curl+jqではなくotel-cliを使う。

# OTEL_EXPORTER_OTLP_ENDPOINT未設定ならtrace送信自体を丸ごとスキップする。
otel_tracing_enabled() {
  [ -n "${OTEL_EXPORTER_OTLP_ENDPOINT:-}" ]
}

# 1回のspan送信がbuild全体を遅延させないようタイムアウトを短くし、失敗しても後続処理を止めない
# (--failを付けないため、otel-cli自身も送信失敗時にexit 0で返す。||で更に念押しする)。
# --tp-ignore-env: otel-cliはTRACEPARENT環境変数が(シェルにたまたま残っている等の理由で)
# 設定されていると自動的にそれを親として採用してしまう(実際に検証で確認済み)。
# trace/span/parent-idは全て--force-*で明示的に指定するため、環境変数由来の暗黙の親付与を止める。
otel_span() {
  otel-cli span --tp-ignore-env --timeout "${OTEL_CLI_TIMEOUT:-3s}" "$@" || true
}

# ナノ秒のUnixエポック(all.shがdate +%s%Nで記録した19桁の整数)を、otel-cliの--start/--endが
# 受け付ける「秒.ナノ秒」形式に変換する。
_otel_ns_to_epoch() {
  local ns="$1"
  echo "${ns:0:10}.${ns:10}"
}

# $BUILD_LOGからtargetの"[target] step: ..."/"[target] provisioning.all: ..."行を抜き出し、
# provisioning.all span(親: root_span_id)と各step span(親: provisioning.allがここで採番する
# span-id)を送信する。EC2側はspan-idを一切採番しない(生データのみ記録)ため、Mac側がここで
# 初めて採番し親子関係を組み立てる。
otel_emit_provisioning_spans() {
  local build_log="$1"
  local trace_id="$2"
  local root_span_id="$3"
  local target="${4:-kakomon14}"
  local service="${OTEL_SERVICE_NAME:-${target}-ami-build}"
  local log_prefix="\\[${target}\\]"

  if ! otel_tracing_enabled; then
    return 0
  fi

  local disk_total
  disk_total="$(grep -oE "${log_prefix} provisioning\\.all: disk_total_bytes=[0-9]+" "${build_log}" | tail -n1 | sed -nE 's/.*disk_total_bytes=([0-9]+).*/\1/p' || true)"

  local start_line
  start_line="$(grep -E "${log_prefix} provisioning\\.all: start_ns=" "${build_log}" | tail -n1 || true)"
  local provisioning_start_ns
  provisioning_start_ns="$(printf '%s\n' "${start_line}" | sed -nE 's/.*start_ns=([0-9]+).*/\1/p')"
  local provisioning_disk_before
  provisioning_disk_before="$(printf '%s\n' "${start_line}" | sed -nE 's/.*disk_before=([0-9]+).*/\1/p')"
  local received_traceparent
  received_traceparent="$(printf '%s\n' "${start_line}" | sed -nE 's/.*traceparent=(.*)$/\1/p')"

  local end_line
  end_line="$(grep -E "${log_prefix} provisioning\\.all: end_ns=" "${build_log}" | tail -n1 || true)"
  local provisioning_end_ns
  provisioning_end_ns="$(printf '%s\n' "${end_line}" | sed -nE 's/.*end_ns=([0-9]+).*/\1/p')"
  local provisioning_disk_after
  provisioning_disk_after="$(printf '%s\n' "${end_line}" | sed -nE 's/.*disk_after=([0-9]+).*/\1/p')"
  local provisioning_exit_status
  provisioning_exit_status="$(printf '%s\n' "${end_line}" | sed -nE 's/.*exit_status=([0-9]+).*/\1/p')"

  if [ -z "${provisioning_start_ns}" ] || [ -z "${provisioning_end_ns}" ]; then
    echo "otel: provisioning.allの開始/終了ログが見つからないため、trace送信をスキップします" >&2
    return 0
  fi

  # Mac側が生成しEC2へ渡したtraceparentと、EC2側が実際に受け取った値を突き合わせる
  # (Mac側が生成した値を無条件に信じず、cloud-init経由の伝播を検証するため)。
  # 一致しない場合も、trace自体は送信できているので警告のみに留めビルドは継続する。
  local expected_traceparent="00-${trace_id}-${root_span_id}-01"
  if [ "${received_traceparent}" != "${expected_traceparent}" ]; then
    echo "otel: 警告: traceparentの伝播が一致しません(期待値=${expected_traceparent}, 実際=${received_traceparent})" >&2
  fi

  local provisioning_span_id
  provisioning_span_id="$(openssl rand -hex 8)"
  local provisioning_status_code="ok"
  if [ "${provisioning_exit_status}" != "0" ]; then
    provisioning_status_code="error"
  fi

  otel_span \
    --service "${service}" \
    --name "provisioning.all" \
    --kind internal \
    --force-trace-id "${trace_id}" \
    --force-span-id "${provisioning_span_id}" \
    --force-parent-span-id "${root_span_id}" \
    --start "$(_otel_ns_to_epoch "${provisioning_start_ns}")" \
    --end "$(_otel_ns_to_epoch "${provisioning_end_ns}")" \
    --attrs "disk.total_bytes=${disk_total},disk.before_bytes=${provisioning_disk_before},disk.after_bytes=${provisioning_disk_after},disk.delta_bytes=$((provisioning_disk_after - provisioning_disk_before)),exit_status=${provisioning_exit_status}" \
    --status-code "${provisioning_status_code}"

  grep -E "${log_prefix} step: " "${build_log}" | while IFS= read -r line; do
    local step_script step_start_ns step_end_ns step_disk_before step_disk_after step_exit_status
    step_script="$(printf '%s\n' "${line}" | sed -nE 's/.*script=([^ ]+).*/\1/p')"
    step_start_ns="$(printf '%s\n' "${line}" | sed -nE 's/.*start_ns=([0-9]+).*/\1/p')"
    step_end_ns="$(printf '%s\n' "${line}" | sed -nE 's/.*end_ns=([0-9]+).*/\1/p')"
    step_disk_before="$(printf '%s\n' "${line}" | sed -nE 's/.*disk_before=([0-9]+).*/\1/p')"
    step_disk_after="$(printf '%s\n' "${line}" | sed -nE 's/.*disk_after=([0-9]+).*/\1/p')"
    step_exit_status="$(printf '%s\n' "${line}" | sed -nE 's/.*exit_status=([0-9]+).*/\1/p')"

    local step_status_code="ok"
    if [ "${step_exit_status}" != "0" ]; then
      step_status_code="error"
    fi

    otel_span \
      --service "${service}" \
      --name "${step_script}" \
      --kind internal \
      --force-trace-id "${trace_id}" \
      --force-span-id "$(openssl rand -hex 8)" \
      --force-parent-span-id "${provisioning_span_id}" \
      --start "$(_otel_ns_to_epoch "${step_start_ns}")" \
      --end "$(_otel_ns_to_epoch "${step_end_ns}")" \
      --attrs "disk.before_bytes=${step_disk_before},disk.after_bytes=${step_disk_after},disk.delta_bytes=$((step_disk_after - step_disk_before)),exit_status=${step_exit_status}" \
      --status-code "${step_status_code}"
  done || true
}
