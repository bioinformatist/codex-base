#!/usr/bin/env bash

set -euo pipefail

[ "$#" -eq 1 ] || {
  echo "usage: spark-availability.bash HELPER" >&2
  exit 2
}
helper="$(realpath -- "$1")"
[ -r "$helper" ] || {
  echo "helper does not exist: $helper" >&2
  exit 2
}

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fake_codex="$test_root/fake-codex"
request_log="$test_root/requests"
pid_log="$test_root/pid"
output="$test_root/output"
errors="$test_root/errors"
diagnostics="$test_root/diagnostics"

fail() {
  echo "spark availability test failed: $*" >&2
  [ ! -s "$errors" ] || sed 's/^/helper stderr: /' "$errors" >&2
  [ ! -s "$diagnostics" ] || sed 's/^/private diagnostic: /' "$diagnostics" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"
}

assert_reaped() {
  local pid
  pid="$(tail -n 1 "$pid_log")"
  [ ! -e "/proc/$pid" ] || fail "$case_name left app-server process $pid"
}

assert_requested() {
  grep -Fx -- "$1" "$request_log" >/dev/null ||
    fail "$case_name did not request $1"
}

assert_not_requested() {
  if grep -Fx -- "$1" "$request_log" >/dev/null; then
    fail "$case_name unexpectedly requested $1"
  fi
}

printf '#!%s\n' "$(command -v bash)" >"$fake_codex"
cat >>"$fake_codex" <<'FAKE_CODEX'
set -euo pipefail

[ "$#" -eq 1 ] && [ "$1" = app-server ] || exit 91
: "${FAKE_MODE:?}" "${FAKE_REQUEST_LOG:?}" "${FAKE_PID_LOG:?}"
printf '%s\n' "$$" >>"$FAKE_PID_LOG"

spark_model='{"model":"gpt-5.3-codex-spark","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"}]}'
hidden_model='{"model":"gpt-5.3-codex-spark","hidden":true,"supportedReasoningEfforts":[{"reasoningEffort":"high"}]}'
unsupported_model='{"model":"gpt-5.3-codex-spark","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"low"}]}'
other_model='{"model":"gpt-5.6-luna","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"high"}]}'

respond() {
  local id="$1" result="$2"
  if [ "$FAKE_MODE" = notifications ]; then
    printf '%s\n' '{"method":"account/updated","params":{"kind":"ordinary"}}'
    printf '%s\n' '{"method":"thread/status/changed"}'
  fi
  printf '{"id":%s,"result":%s}\n' "$id" "$result"
}

available_limits() {
  printf '%s' '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":25},"secondary":{"usedPercent":50},"spendControlReached":false,"rateLimitReachedType":null}}}'
}

while IFS= read -r request; do
  method="$(jq -r '.method' <<<"$request")"
  printf '%s\n' "$method" >>"$FAKE_REQUEST_LOG"
  case "$method" in
    initialize)
      jq -e '
        .params.clientInfo == {
          name:"codex-improve", title:null, version:"1.0.0-codex.16"
        } and .params.capabilities == null
      ' <<<"$request" >/dev/null || exit 92
      respond "$(jq -r '.id' <<<"$request")" '{"serverInfo":{"name":"fake"}}'
      ;;
    initialized)
      ;;
    account/read)
      case "$FAKE_MODE" in
        api_key)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"account":{"type":"apiKey"}}'
          ;;
        malformed_account)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"account":[],"requiresOpenaiAuth":false}'
          ;;
        auth_error)
          printf '%s\n' 'native stderr FAKE_SECRET_TOKEN' >&2
          printf '{"id":%s,"error":{"code":-32000,"message":"authentication failed FAKE_SECRET_TOKEN"}}\n' \
            "$(jq -r '.id' <<<"$request")"
          ;;
        eof)
          exit 0
          ;;
        timeout)
          trap '' TERM
          while :; do sleep 1; done
          ;;
        *)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"account":{"type":"chatgpt"}}'
          ;;
      esac
      ;;
    model/list)
      cursor="$(jq -r '.params.cursor // empty' <<<"$request")"
      jq -e '.params | has("cursor") and .limit == 100 and .includeHidden == true' \
        <<<"$request" >/dev/null || exit 93
      case "$FAKE_MODE" in
        absent_model)
          respond "$(jq -r '.id' <<<"$request")" \
            "{\"data\":[${other_model}],\"nextCursor\":null}"
          ;;
        hidden_model)
          respond "$(jq -r '.id' <<<"$request")" \
            "{\"data\":[${hidden_model}],\"nextCursor\":null}"
          ;;
        unsupported_model)
          respond "$(jq -r '.id' <<<"$request")" \
            "{\"data\":[${unsupported_model}],\"nextCursor\":null}"
          ;;
        malformed_model)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"data":{"model":"wrong-shape"},"nextCursor":null}'
          ;;
        malformed_spark_metadata)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"data":[{"model":"gpt-5.3-codex-spark","hidden":"not-a-bool","supportedReasoningEfforts":[{"reasoningEffort":"high"}] }],"nextCursor":null}'
          ;;
        unrelated_model_metadata)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"data":[{"model":"gpt-5.6-luna","hidden":"not-a-bool","supportedReasoningEfforts":"bad"},{"model":"gpt-5.3-codex-spark","hidden":false,"supportedReasoningEfforts":[{"reasoningEffort":"high"}],"metadata":{"plan":"spark"}}],"nextCursor":null}'
          ;;
        pagination)
          if [ -z "$cursor" ]; then
            respond "$(jq -r '.id' <<<"$request")" \
              "{\"data\":[${other_model}],\"nextCursor\":\"second-page\"}"
          else
            [ "$cursor" = second-page ] || exit 94
            respond "$(jq -r '.id' <<<"$request")" \
              "{\"data\":[${spark_model}],\"nextCursor\":null}"
          fi
          ;;
        *)
          respond "$(jq -r '.id' <<<"$request")" \
            "{\"data\":[${spark_model}],\"nextCursor\":null}"
          ;;
      esac
      ;;
    account/rateLimits/read)
      case "$FAKE_MODE" in
        primary_exhausted)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":100},"secondary":null,"spendControlReached":false,"rateLimitReachedType":null}}}'
          ;;
        secondary_exhausted)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":10},"secondary":{"usedPercent":100},"spendControlReached":false,"rateLimitReachedType":null}}}'
          ;;
        absent_bucket)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{}}'
          ;;
        malformed_quota)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"primary":{"usedPercent":"secretly-not-a-number"},"secondary":null,"spendControlReached":false,"rateLimitReachedType":null}}}'
          ;;
        spend_control_exhausted)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":20},"secondary":null,"spendControlReached":true,"rateLimitReachedType":null}}}'
          ;;
        reached_type_exhausted)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":20},"secondary":null,"spendControlReached":false,"rateLimitReachedType":"quota"}}}'
          ;;
        unrelated_limit_bucket_ignored)
          respond "$(jq -r '.id' <<<"$request")" \
            '{"rateLimitsByLimitId":{"codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":25},"secondary":null,"spendControlReached":false,"rateLimitReachedType":null},"unrelated":{"primary":{"usedPercent":"bad"}}}}'
          ;;
        *)
          respond "$(jq -r '.id' <<<"$request")" "$(available_limits)"
          ;;
      esac
      ;;
    *) exit 95 ;;
  esac
done
FAKE_CODEX
chmod +x "$fake_codex"

export FAKE_REQUEST_LOG="$request_log"
export FAKE_PID_LOG="$pid_log"

run_case() {
  case_name="$1"
  FAKE_MODE="$2"
  expected_status="$3"
  expected_output="$4"
  export FAKE_MODE
  : >"$request_log"
  : >"$pid_log"
  : >"$output"
  : >"$errors"
  : >"$diagnostics"
  set +e
  timeout --signal=TERM --kill-after=4s 5s \
    bash "$helper" "$fake_codex" "$diagnostics" >"$output" 2>"$errors"
  status=$?
  set -e
  assert_eq "$status" "$expected_status" "$case_name status"
  assert_eq "$(<"$output")" "$expected_output" "$case_name output"
  assert_requested initialize
  assert_requested initialized
  assert_reaped
  if grep -F 'gpt-5.6-luna' "$request_log" >/dev/null; then
    fail "$case_name queried Luna quota"
  fi
}

run_case primary_exhausted primary_exhausted 0 luna
assert_eq "$(grep -c '^account/rateLimits/read$' "$request_log")" 1 "primary exhausted quota query count"
run_case available available 0 spark
assert_requested account/read
assert_requested model/list
assert_requested account/rateLimits/read
assert_eq "$(grep -c '^account/rateLimits/read$' "$request_log")" 1 "available quota query count"

run_case secondary_exhausted secondary_exhausted 0 luna

run_case absent_model absent_model 0 luna
assert_not_requested account/rateLimits/read
run_case hidden_model hidden_model 0 luna
assert_not_requested account/rateLimits/read
run_case unsupported_model unsupported_model 0 luna
assert_not_requested account/rateLimits/read
run_case unrelated_model_metadata unrelated_model_metadata 0 spark

run_case pagination pagination 0 spark
assert_eq "$(grep -c '^model/list$' "$request_log")" 2 "pagination page count"

run_case absent_bucket absent_bucket 0 luna
run_case unrelated_limit_bucket_ignored unrelated_limit_bucket_ignored 0 spark
run_case spend_control_exhausted spend_control_exhausted 0 luna
run_case reached_type_exhausted reached_type_exhausted 0 luna

run_case api_key api_key 0 luna
assert_not_requested model/list
assert_not_requested account/rateLimits/read

run_case malformed_account malformed_account 1 ''
grep -F 'failed during account/read: malformed native result' "$errors" >/dev/null ||
  fail 'malformed account safe error missing'
run_case malformed_model malformed_model 1 ''
grep -F 'failed during model/list: malformed native result' "$errors" >/dev/null ||
  fail 'malformed model safe error missing'
run_case malformed_spark_metadata malformed_spark_metadata 1 ''
grep -F 'failed during model/list: malformed native result' "$errors" >/dev/null ||
  fail 'malformed spark metadata safe error missing'
run_case malformed_quota malformed_quota 1 ''
grep -F 'failed during account/rateLimits/read: malformed native result' "$errors" >/dev/null ||
  fail 'malformed quota safe error missing'

run_case auth_error auth_error 1 ''
grep -F 'failed during account/read: native RPC error' "$errors" >/dev/null ||
  fail 'authentication safe error missing'
if grep -F 'FAKE_SECRET_TOKEN' "$errors" >/dev/null; then
  fail 'authentication failure leaked its secret'
fi
grep -F 'FAKE_SECRET_TOKEN' "$diagnostics" >/dev/null ||
  fail 'private authentication diagnostics were not retained'

run_case eof eof 1 ''
grep -F 'failed during account/read: unexpected native EOF' "$errors" >/dev/null ||
  fail 'EOF safe error missing'

run_case notifications notifications 0 spark

case_name=timeout
FAKE_MODE=timeout
export FAKE_MODE
: >"$request_log"
: >"$pid_log"
: >"$output"
: >"$errors"
: >"$diagnostics"
set +e
timeout --signal=TERM --kill-after=4s 1s \
  bash "$helper" "$fake_codex" "$diagnostics" >"$output" 2>"$errors"
status=$?
set -e
assert_eq "$status" 124 'timeout status'
grep -F 'failed during account/read: timeout' "$errors" >/dev/null ||
  fail 'timeout safe error missing'
assert_reaped

echo 'spark availability tests passed'
