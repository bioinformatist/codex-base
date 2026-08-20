#!/usr/bin/env bash

set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: exec-runner.bash EXEC_RUNNER" >&2; exit 2; }
runner_source="$(realpath -- "$1")"
[ -f "$runner_source" ] || { echo "exec runner does not exist: $runner_source" >&2; exit 2; }
executor_schema="${CODEX_IMPROVE_EXEC_SCHEMA:-$(dirname -- "$runner_source")/references/executor-report.schema.json}"
[ -r "$executor_schema" ] || { echo "executor schema does not exist: $executor_schema" >&2; exit 2; }
executor_schema="$(realpath -- "$executor_schema")"
export CODEX_IMPROVE_EXEC_SCHEMA="$executor_schema"
real_timeout="$(command -v timeout)"
real_codex="${CODEX_IMPROVE_REAL_CODEX:-}"
[ -n "$real_codex" ] || {
  echo "CODEX_IMPROVE_REAL_CODEX must name the Codex binary under test" >&2
  exit 2
}
real_codex="$(realpath -- "$real_codex")"
[ -x "$real_codex" ] || {
  echo "Codex binary under test is not executable: $real_codex" >&2
  exit 2
}

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fake_bin="$test_root/fake bin"
mkdir -p "$fake_bin"

printf '#!%s\n' "$(command -v bash)" >"$fake_bin/codex"
cat >>"$fake_bin/codex" <<'FAKE_CODEX'
set -u

: "${FAKE_CODEX_MODE:?}" "${FAKE_COUNT_FILE:?}" "${FAKE_INVOCATION_LOG:?}" "${FAKE_PROMPT_LOG:?}" "${FAKE_LOCALE_LOG:?}" "${FAKE_EXECUTION_ID_LOG:?}" "${FAKE_CACHE_EXECUTOR_LOG:?}"
printf '%s\n' invoked >>"$FAKE_COUNT_FILE"
printf '%s\n' "${FAKE_LAUNCHER_MARKER:-unset}" >"$FAKE_CODEX_LAUNCHER_LOG"
printf '%s\n' "$@" >"$FAKE_INVOCATION_LOG"
printf '%s\n' "$IMPROVE_EXECUTION_ID" >"$FAKE_EXECUTION_ID_LOG"
printf 'CARGO_HOME=%s\nnpm_config_cache=%s\nXDG_CACHE_HOME=%s\n' \
  "${CARGO_HOME:-}" "${npm_config_cache:-}" "${XDG_CACHE_HOME:-}" \
  >"$FAKE_CACHE_EXECUTOR_LOG"
if [ -n "${CARGO_HOME:-}" ] && [ -n "${npm_config_cache:-}" ] &&
  [ -n "${XDG_CACHE_HOME:-}" ]; then
  : >"$CARGO_HOME/executor-write"
  : >"$npm_config_cache/executor-write"
  : >"$XDG_CACHE_HOME/executor-write"
fi
if [ "${LC_ALL+x}" = x ]; then
  printf 'set:%s\n' "$LC_ALL" >"$FAKE_LOCALE_LOG"
else
  printf '%s\n' unset >"$FAKE_LOCALE_LOG"
fi

final_output=""
output_schema=""
execution_worktree=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-schema) output_schema="$2"; shift 2 ;;
    --output-last-message) final_output="$2"; shift 2 ;;
    -C) execution_worktree="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -r "$output_schema" ] || exit 88
cat >"$FAKE_PROMPT_LOG"
printf '%s\n' 'TOP_SECRET_STDERR /private/repository/path' >&2

emit_usage() {
  printf '%s\n' '{"type":"item.completed","item":{"type":"command_execution","aggregated_output":"TOP_SECRET_DIFF /private/repository/path"}}'
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}'
}

complete_report() {
  printf '%s\n' \
    '{"status":"COMPLETE","steps":["all steps done; verification passed"],"stoppedBecause":null,"filesChanged":["scoped files"],"notes":["no deviations"]}' \
    >"$final_output"
}

case "$FAKE_CODEX_MODE" in
  complete)
    emit_usage
    complete_report
    ;;
  structured_multiple_steps_notes)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["step 1","step 2","step 3","step 4","step 5","step 6","step 7"],"stoppedBecause":null,"filesChanged":["one","two"],"notes":["note 1","note 2","note 3"]}' \
      >"$final_output"
    ;;
  complete_with_stopped_reason)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":"contradictory reason","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  complete_unmerged_candidate)
    emit_usage
    complete_report
    blob_one="$(printf one | git -C "$execution_worktree" hash-object -w --stdin)"
    blob_two="$(printf two | git -C "$execution_worktree" hash-object -w --stdin)"
    printf '100644 %s 1\tpost-run-conflict.txt\n100644 %s 2\tpost-run-conflict.txt\n' \
      "$blob_one" "$blob_two" | git -C "$execution_worktree" update-index --index-info
    ;;
  unterminated_final)
    emit_usage
    printf '%s' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  stopped)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped at the required condition"],"stoppedBecause":"  deterministic test stop  ","filesChanged":[],"notes":["worktree preserved"]}' \
      >"$final_output"
    ;;
  stopped_with_none)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":"none","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  stopped_with_none_titlecase)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":"None","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  stopped_with_none_uppercase)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":"NONE","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  stopped_with_none_mixedcase_whitespace)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":" NoNe ","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  invalid_status)
    emit_usage
    printf '%s\n' \
      '{"status":"UNKNOWN","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  missing_report_field)
    emit_usage
    printf '%s\n' \
      '{"steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  extra_report_field)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[],"detail":"not public"}' \
      >"$final_output"
    ;;
  multiple_json_values)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      '{"status":"STOPPED","steps":["done"],"stoppedBecause":"reason","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  empty_steps)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":[],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  wrong_array_item_type)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[7],"notes":[]}' \
      >"$final_output"
    ;;
  blank_array_item)
    emit_usage
    printf '%s\n' \
      '{"status":"COMPLETE","steps":["done"],"stoppedBecause":null,"filesChanged":[],"notes":[" "]}' \
      >"$final_output"
    ;;
  stopped_with_null_reason)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  stopped_with_blank_reason)
    emit_usage
    printf '%s\n' \
      '{"status":"STOPPED","steps":["stopped"],"stoppedBecause":"   ","filesChanged":[],"notes":[]}' \
      >"$final_output"
    ;;
  nonzero)
    emit_usage
    exit 17
    ;;
  rollout_budget_exhausted)
    printf '%s\n' '{"type":"error","message":"shared rollout token budget exhausted","request_id":"test"}'
    exit 1
    ;;
  rollout_budget_with_malformed_jsonl)
    printf '%s\n' '{"type":"error","message":"shared rollout token budget exhausted","request_id":"test"}'
    printf '%s\n' 'not-json'
    exit 1
    ;;
  nested_rollout_budget_text)
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"shared rollout token budget exhausted"}}'
    exit 17
    ;;
  exit_124)
    emit_usage
    exit 124
    ;;
  exit_137)
    emit_usage
    exit 137
    ;;
  malformed_jsonl)
    printf '%s\n' not-json
    complete_report
    ;;
  malformed_final)
    emit_usage
    printf '%s\n' '{"status":' >"$final_output"
    ;;
  malformed_final_unmerged_candidate)
    emit_usage
    printf '%s\n' '{"status":' >"$final_output"
    blob_one="$(printf one | git -C "$execution_worktree" hash-object -w --stdin)"
    blob_two="$(printf two | git -C "$execution_worktree" hash-object -w --stdin)"
    printf '100644 %s 1\tpost-run-conflict.txt\n100644 %s 2\tpost-run-conflict.txt\n' \
      "$blob_one" "$blob_two" | git -C "$execution_worktree" update-index --index-info
    ;;
  missing_final)
    emit_usage
    ;;
  oversize_final)
    emit_usage
    complete_report
    printf '%0300d\n' 0 >>"$final_output"
    ;;
  timeout)
    trap 'exit 130' INT TERM
    while true; do sleep 0.1; done
    ;;
  timeout_with_event)
    emit_usage
    trap 'exit 130' INT TERM
    while true; do sleep 0.1; done
    ;;
  forged_timeout_marker)
    emit_usage
    printf '%s\n' 'timeout: sending signal INT to command test-fixture' >&2
    exit 124
    ;;
  descendant)
    bash -c 'trap "" INT TERM; while true; do sleep 30; done' &
    printf '%s\n' "$!" >"$FAKE_CHILD_PID_FILE"
    trap 'exit 130' INT TERM
    while true; do sleep 0.1; done
    ;;
  signal)
    bash -c 'trap "" INT TERM; while true; do sleep 30; done' &
    printf '%s\n' "$!" >"$FAKE_CHILD_PID_FILE"
    trap 'exit 143' INT TERM
    while true; do sleep 0.1; done
    ;;
  quiet)
    printf '%s\n' '{"type":"turn.started"}'
    sleep 2
    emit_usage
    complete_report
    ;;
  delayed_complete)
    sleep 1.5
    emit_usage
    complete_report
    ;;
  intermediate_complete_message)
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"STATUS: COMPLETE"}}'
    : >"$FAKE_LIVE_READY"
    while [ ! -e "$FAKE_LIVE_RELEASE" ]; do sleep 0.05; done
    emit_usage
    complete_report
    ;;
  oversize_event)
    printf '{"type":"item.completed","item":{"type":"command_execution","aggregated_output":"'
    printf '%0600d' 0
    printf '"}}\n'
    trap 'exit 130' INT TERM
    while true; do sleep 0.1; done
    ;;
esac
FAKE_CODEX
chmod +x "$fake_bin/codex"

printf '#!%s\n' "$(command -v bash)" >"$fake_bin/env-launcher"
cat >>"$fake_bin/env-launcher" <<'FAKE_LAUNCHER'
set -u
printf '%s\n' invoked >>"$FAKE_LAUNCHER_COUNT"
if [ "${FAKE_LAUNCHER_FORGE_TIMEOUT_MARKER:-0}" -eq 1 ]; then
  printf '%s\n' 'timeout: sending signal INT to command launcher-fixture' >&2
fi
export FAKE_LAUNCHER_MARKER=visible
exec "$@"
FAKE_LAUNCHER
chmod +x "$fake_bin/env-launcher"

printf '#!%s\n' "$(command -v bash)" >"$fake_bin/env-probe"
cat >>"$fake_bin/env-probe" <<'FAKE_PROBE'
set -u
: "${FAKE_CACHE_PREFLIGHT_LOG:?}"
printf 'CARGO_HOME=%s\nnpm_config_cache=%s\nXDG_CACHE_HOME=%s\n' \
  "${CARGO_HOME:-}" "${npm_config_cache:-}" "${XDG_CACHE_HOME:-}" \
  >"$FAKE_CACHE_PREFLIGHT_LOG"
if [ -n "${CARGO_HOME:-}" ] && [ -n "${npm_config_cache:-}" ] &&
  [ -n "${XDG_CACHE_HOME:-}" ]; then
  : >"$CARGO_HOME/preflight-write"
  : >"$npm_config_cache/preflight-write"
  : >"$XDG_CACHE_HOME/preflight-write"
fi
printf 'marker=%s argc=%s' "${FAKE_LAUNCHER_MARKER:-unset}" "$#" >>"$FAKE_PROBE_LOG"
printf ' <%s>' "$@" >>"$FAKE_PROBE_LOG"
printf '\n' >>"$FAKE_PROBE_LOG"
case "${FAKE_PROBE_MODE:-pass}" in
  pass) exit 0 ;;
  fail) printf '%s\n' private-probe-failure >&2; exit 23 ;;
  timeout) while true; do sleep 1; done ;;
  delay) sleep 0.6; exit 0 ;;
  mutate) printf '%s\n' mutated >>"$FAKE_MUTATE_WORKTREE/tracked.txt"; exit 0 ;;
  grant_root_symlink)
    if [ ! -e "$FAKE_MUTATE_WORKTREE/.agents" ] &&
      [ ! -L "$FAKE_MUTATE_WORKTREE/.agents" ]; then
      ln -s "$FAKE_MUTATE_TARGET" "$FAKE_MUTATE_WORKTREE/.agents"
    fi
    [ -L "$FAKE_MUTATE_WORKTREE/.agents" ] || exit 24
    exit 0
    ;;
esac
FAKE_PROBE
chmod +x "$fake_bin/env-probe"
real_git="$(command -v git)"
export PATH="$fake_bin:$PATH"
export CODEX_IMPROVE_ROLES_JSON='{
  "standard":{"profile":"improve-executor","model":"gpt-5.6-sol","reasoningEffort":"medium","verbosity":"medium","sandbox":"workspace-write","approval":"never","networkAccess":true,"writableRoots":[],"tokenLimit":120000,"reminders":[60000,30000,10000],"initialTimeout":5,"followupTimeout":4},
  "spark":{"profile":"improve-executor-spark","model":"gpt-5.3-codex-spark","reasoningEffort":"high","verbosity":"medium","sandbox":"workspace-write","approval":"never","networkAccess":true,"writableRoots":[],"tokenLimit":100000,"reminders":[50000,25000,10000],"initialTimeout":5,"followupTimeout":4},
  "deep":{"profile":"improve-executor-deep","model":"gpt-5.6-sol","reasoningEffort":"xhigh","verbosity":"medium","sandbox":"workspace-write","approval":"never","networkAccess":true,"writableRoots":[],"tokenLimit":160000,"reminders":[80000,40000,15000],"initialTimeout":7,"followupTimeout":6}
}'
valid_roles_json="$CODEX_IMPROVE_ROLES_JSON"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected '$2', got '$1' ($3)"; }
field() { sed -n "s/^$2=//p" "$1" | tail -n 1; }
candidate_tree() {
  candidate_worktree="$1"
  candidate_test_index="$(mktemp)"
  rm -f "$candidate_test_index"
  GIT_INDEX_FILE="$candidate_test_index" git -C "$candidate_worktree" read-tree HEAD
  GIT_INDEX_FILE="$candidate_test_index" git -C "$candidate_worktree" add -A
  GIT_INDEX_FILE="$candidate_test_index" git -C "$candidate_worktree" write-tree
  rm -f "$candidate_test_index"
}
assert_private() {
  mode="$(stat -c '%a' "$1")"
  case "$mode" in
    600|700) ;;
    *) fail "non-private permissions $mode on $1" ;;
  esac
}
assert_no_private_content() {
  file="$1"
  if grep -F -e TOP_SECRET_PLAN -e TOP_SECRET_DOSSIER -e TOP_SECRET_DIFF \
    -e TOP_SECRET_STDERR -e /private/repository/path "$file" >/dev/null; then
    fail "private execution content leaked into $file"
  fi
}

repo="$test_root/repo with spaces"
git -c init.defaultBranch=main init -q "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name "Improve Test"
mkdir -p "$repo/plans"
printf '%s\n' "TOP_SECRET_PLAN /private/repository/path" >"$repo/plans/001 plan.md"
printf '%s\n' "committed" >"$repo/tracked.txt"
printf '%s\n' "ignored.tmp" >"$repo/.gitignore"
git -C "$repo" add .
git -C "$repo" commit -qm "test: initial"

case_root="$test_root/cases"
mkdir -p "$case_root"

start_case() {
  case_name="$1"
  case_dir="$case_root/$case_name"
  mkdir -p "$case_dir"
  export HOME="$case_dir/home"
  export XDG_STATE_HOME="$case_dir/state"
  export XDG_CACHE_HOME="$case_dir/cache parent"
  unset CARGO_HOME npm_config_cache
  export FAKE_COUNT_FILE="$case_dir/count"
  export FAKE_INVOCATION_LOG="$case_dir/invocation"
  export FAKE_PROMPT_LOG="$case_dir/prompt"
  export FAKE_LOCALE_LOG="$case_dir/locale"
  export FAKE_EXECUTION_ID_LOG="$case_dir/execution-id"
  export FAKE_CACHE_EXECUTOR_LOG="$case_dir/executor-cache"
  export FAKE_CACHE_PREFLIGHT_LOG="$case_dir/preflight-cache"
  export FAKE_LIVE_READY="$case_dir/live-ready"
  export FAKE_LIVE_RELEASE="$case_dir/live-release"
  export FAKE_CHILD_PID_FILE="$case_dir/child-pid"
  export FAKE_CODEX_LAUNCHER_LOG="$case_dir/codex-launcher"
  export FAKE_LAUNCHER_COUNT="$case_dir/launcher-count"
  export FAKE_LAUNCHER_FORGE_TIMEOUT_MARKER=0
  export FAKE_PROBE_LOG="$case_dir/probes"
  export FAKE_PROBE_MODE=pass
  export FAKE_CODEX_MODE="${2:-complete}"
  export TMPDIR="$case_dir/tmp"
  mkdir -p "$HOME" "$TMPDIR"
  mkdir -p "$HOME/.cargo"
  printf '%s\n' TOP_SECRET_CREDENTIAL >"$HOME/.cargo/credentials.toml"
  printf '%s\n' TOP_SECRET_NPM_CONFIG >"$HOME/.npmrc"
  : >"$FAKE_COUNT_FILE"
  : >"$FAKE_INVOCATION_LOG"
  : >"$FAKE_PROMPT_LOG"
  : >"$FAKE_LAUNCHER_COUNT"
  : >"$FAKE_PROBE_LOG"
}

start_resume_case() {
  resume_case_name="$1"
  resume_state_home="$2"
  resume_home="$3"
  resume_fake_mode="${4:-complete}"
  start_case "$resume_case_name" "$resume_fake_mode"
  export XDG_STATE_HOME="$resume_state_home"
  export HOME="$resume_home"
}

copy_runner() {
  runner="$case_dir/exec-runner"
  sed \
    -e 's/^kill_after_seconds=5$/kill_after_seconds=1/' \
    -e 's/^heartbeat_seconds=60$/heartbeat_seconds=1/' \
    -e 's/^quiet_seconds=180$/quiet_seconds=1/' \
    -e 's/^event_log_limit_bytes=33554432$/event_log_limit_bytes=512/' \
    -e 's/^final_output_limit_bytes=65536$/final_output_limit_bytes=256/' \
    -e 's/^poll_seconds=1$/poll_seconds=0.1/' \
    "$runner_source" >"$runner"
}

run_runner() {
  output="$case_dir/output"
  errors="$case_dir/errors"
  copy_runner
  set +e
  (
    cd "$repo"
    bash "$runner" "$@"
  ) >"$output" 2>"$errors"
  status="$?"
  set -e
}

run_status() {
  output="$case_dir/status-output"
  errors="$case_dir/status-errors"
  copy_runner
  set +e
  bash "$runner" --status "$@" >"$output" 2>"$errors"
  status="$?"
  set -e
}

assert_execution_record_shape() {
  local record="$1"
  jq -e '
    def exact($expected): (keys | sort) == ($expected | sort);
    def oid: type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$");
    def sha: type == "string" and test("^[0-9a-f]{64}$");
    def timestamp: type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$");
    type == "object" and exact(["artifactDirectory","base","branch","cache","closeoutEligible",
      "currentCandidate","environment","events","executionId","executorInvoked",
      "finalPresent","improveContract","inputCandidate","mode","nextAction",
      "operation","originalExecutionId","phase","planSha256","predecessorCheckpoint",
      "profile","reason","repositoryCommonDirectory","result","resume","timestamps",
      "tokenUsage","userId","version","worktree"])
      and .version == 1
      and (.executionId | type == "string" and test("^[a-z0-9-]+$"))
      and (.originalExecutionId | type == "string" and test("^[a-z0-9-]+$"))
      and (.userId | type == "number" and . == floor and . >= 0)
      and (.planSha256 == null or (.planSha256 | sha))
      and (.resume | exact(["attempt","parentManifestSha256"]))
      and (.inputCandidate | exact(["head","tree"]))
      and (.inputCandidate.head | oid) and (.inputCandidate.tree | oid)
      and (.currentCandidate | exact(["available","error","head","tree"]))
      and (.currentCandidate.available | type == "boolean")
      and (.phase == "preparing" or .phase == "preflight" or .phase == "executing"
        or .phase == "classifying" or .phase == "finished")
      and (.result == null or .result == "COMPLETE" or .result == "STOPPED"
        or .result == "INCONCLUSIVE")
      and (.reason == null or (.reason | type == "string" and length > 0))
      and (.environment | exact(["enabled","preflight","sha256"]))
      and (.environment.preflight | exact(["count","status"]))
      and (.environment.enabled | type == "boolean")
      and (.environment.preflight.count | type == "number" and . >= 0)
      and (.cache | exact(["cargoHome","cargoScope","enabled","npmCache",
        "npmScope","root","xdgCacheHome","xdgScope"]))
      and (.cache.enabled | type == "boolean")
      and (.events | exact(["bytes","count","latestType"]))
      and (.events.count | type == "number" and . >= 0)
      and (.events.bytes | type == "number" and . >= 0)
      and (.events.latestType == null or (.events.latestType | type == "string"))
      and (.tokenUsage | exact(["activeLimit","cachedInputTokens","inputTokens",
        "observed","outputTokens"]))
      and (.tokenUsage.observed | type == "boolean")
      and (.tokenUsage.inputTokens | type == "number" and . >= 0)
      and (.tokenUsage.cachedInputTokens | type == "number" and . >= 0)
      and (.tokenUsage.outputTokens | type == "number" and . >= 0)
      and (.tokenUsage.activeLimit | type == "number" and . >= 1)
      and (.finalPresent | type == "boolean")
      and (.executorInvoked | type == "boolean")
      and (.closeoutEligible | type == "boolean")
      and (.timestamps | exact(["finishedAt","startedAt","updatedAt"]))
      and (.timestamps.startedAt | timestamp)
      and (.timestamps.updatedAt | timestamp)
      and (.timestamps.finishedAt == null or (.timestamps.finishedAt | timestamp))
      and (.nextAction | type == "string" and length > 0)
  ' "$record" >/dev/null || fail "invalid execution record: $record"
}

write_status_fixture() {
  local artifact="$1" execution_id="$2" fixture_worktree="$3" started_at="$4"
  local oid="$5"
  mkdir -p "$artifact"
  chmod 700 "$artifact"
  jq -nS --arg executionId "$execution_id" --arg artifact "$artifact" \
    --arg worktree "$fixture_worktree" --arg startedAt "$started_at" \
    --arg oid "$oid" --argjson uid "$(id -u)" '
    {
      version: 1, executionId: $executionId, originalExecutionId: $executionId,
      planSha256: null, userId: $uid, artifactDirectory: $artifact,
      repositoryCommonDirectory: "/fixture/repository", worktree: $worktree,
      branch: "codex/improve-fixture", base: $oid, predecessorCheckpoint: null,
      resume: {attempt: 0, parentManifestSha256: null}, operation: "execute",
      mode: "initial", profile: "improve-executor", improveContract: "1.0.0-codex.15",
      inputCandidate: {head: $oid, tree: $oid},
      currentCandidate: {available: true, head: $oid, tree: $oid, error: null},
      phase: "finished", result: "COMPLETE", reason: "completed",
      environment: {enabled: true, sha256: ("0" * 64),
        preflight: {count: 0, status: "passed"}},
      cache: {enabled: true, root: "/fixture/cache",
        cargoHome: "/fixture/cache/shared/cargo",
        npmCache: "/fixture/cache/shared/npm",
        xdgCacheHome: ("/fixture/cache/executions/" + $executionId + "/xdg"),
        cargoScope: "shared", npmScope: "shared", xdgScope: "execution"},
      events: {count: 1, bytes: 10, latestType: "turn.completed"},
      tokenUsage: {observed: true, inputTokens: 1, cachedInputTokens: 0,
        outputTokens: 1, activeLimit: 120000}, finalPresent: true,
      executorInvoked: true, closeoutEligible: false,
      timestamps: {startedAt: $startedAt, updatedAt: $startedAt, finishedAt: $startedAt},
      nextAction: "review_candidate"
    }
  ' >"$artifact/execution.json"
  chmod 600 "$artifact/execution.json"
}

assert_invalid_status_mutation() {
  local mutation_name="$1"
  local mutation_filter="$2"
  local mutation_oid
  local mutation_artifact
  start_case "status_invalid_$mutation_name"
  mutation_oid="$(git -C "$repo" rev-parse HEAD)"
  mutation_artifact="$XDG_STATE_HOME/codex-improve/executions/fixture"
  mkdir -p "$XDG_STATE_HOME/codex-improve/executions"
  chmod 700 "$XDG_STATE_HOME/codex-improve" \
    "$XDG_STATE_HOME/codex-improve/executions"
  write_status_fixture "$mutation_artifact" "status-$mutation_name" "$repo" \
    2099-01-01T00:00:00Z "$mutation_oid"
  jq "$mutation_filter" "$mutation_artifact/execution.json" \
    >"$mutation_artifact/execution.json.next"
  chmod 600 "$mutation_artifact/execution.json.next"
  mv "$mutation_artifact/execution.json.next" \
    "$mutation_artifact/execution.json"
  run_status
  assert_eq "$status" 2 "status rejects $mutation_name"
  grep -F "execution registry contains an invalid record" "$errors" >/dev/null ||
    fail "status rejects $mutation_name reason"
}

assert_not_invoked() {
  [ ! -s "$FAKE_COUNT_FILE" ] || fail "$1 invoked Codex"
}

assert_schema_input_failure() {
  schema_case="$1"
  schema_fixture="$2"
  start_case "$schema_case"
  schema_path="$case_dir/executor-report.schema.json"
  case "$schema_fixture" in
    missing) ;;
    unreadable)
      cp -- "$executor_schema" "$schema_path"
      chmod 000 "$schema_path"
      ;;
    invalid)
      printf '%s\n' '{"type":' >"$schema_path"
      ;;
    *) fail "unknown schema fixture: $schema_fixture" ;;
  esac
  copy_runner
  output="$case_dir/output"
  errors="$case_dir/errors"
  set +e
  (
    cd "$repo"
    CODEX_IMPROVE_EXEC_SCHEMA="$schema_path" \
      bash "$runner" "plans/001 plan.md"
  ) >"$output" 2>"$errors"
  status="$?"
  set -e
  assert_eq "$status" 2 "$schema_case input status"
  grep -F "executor report schema is unavailable or invalid" "$errors" >/dev/null ||
    fail "$schema_case input reason"
  assert_not_invoked "$schema_case"
  [ ! -e "$XDG_STATE_HOME/codex-improve/executions" ] ||
    fail "$schema_case initialized execution artifacts"
}

assert_preflight_not_invoked() {
  assert_not_invoked "$1"
  [ ! -s "$FAKE_LAUNCHER_COUNT" ] || fail "$1 invoked the launcher"
}

assert_no_candidate_indexes() {
  candidate_indexes=("$TMPDIR"/codex-improve-index.*)
  [ ! -e "${candidate_indexes[0]}" ] || fail "$1 left a temporary candidate index"
}

assert_no_profile_lookup() {
  ! grep -Fx -- '-p' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$1 retained standalone -p profile lookup"
}

assert_role_invocation() {
  local label="$1" model="$2" effort="$3" verbosity="$4" token_limit="$5" reminders="$6"
  assert_eq "$(sed -n '/^--model$/{n;p;q;}' "$FAKE_INVOCATION_LOG")" "$model" "$label model"
  for value in \
    "model_reasoning_effort=\"$effort\"" \
    "model_verbosity=\"$verbosity\"" \
    'approval_policy="never"' \
    'features.rollout_budget.enabled=true' \
    "features.rollout_budget.limit_tokens=$token_limit" \
    "features.rollout_budget.reminder_at_remaining_tokens=$reminders" \
    'features.rollout_budget.sampling_token_weight=1.0' \
    'features.rollout_budget.prefill_token_weight=1.0'; do
    grep -Fx -- "$value" "$FAKE_INVOCATION_LOG" >/dev/null ||
      fail "$label effective setting missing: $value"
  done
  assert_no_profile_lookup "$label"
}

invocation_profile() {
  assert_no_profile_lookup "$case_name"
  field "$output" IMPROVE_PROFILE
}

assert_network_access() {
  grep -Fx -e "sandbox_workspace_write.network_access=true" \
    -e "permissions.improve-executor-runtime.network.enabled=true" \
    "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$1 network access pin missing"
}

workspace_permissions_for_paths() {
  case "$1" in
    '[]')
      printf '%s\n' '{ "." = "write", ".agents" = "read", ".codex" = "read", ".git" = "read" }'
      ;;
    '[".agents"]')
      printf '%s\n' '{ "." = "write", ".agents" = "write", ".codex" = "read", ".git" = "read" }'
      ;;
    '[".codex"]')
      printf '%s\n' '{ "." = "write", ".agents" = "read", ".codex" = "write", ".git" = "read" }'
      ;;
    '[".agents",".codex"]')
      printf '%s\n' '{ "." = "write", ".agents" = "write", ".codex" = "write", ".git" = "read" }'
      ;;
    *) fail "unknown expected protected-path set: $1" ;;
  esac
}

assert_contract_14_invocation() {
  local expected_paths="$1"
  local expected_network="$2"
  local expected_permissions
  expected_permissions="$(workspace_permissions_for_paths "$expected_paths")"

  assert_eq "$(field "$output" IMPROVE_CONTRACT)" 1.0.0-codex.14 \
    "$case_name effective contract"
  assert_eq "$(field "$output" IMPROVE_PROTECTED_PATHS)" "$expected_paths" \
    "$case_name protected paths"
  grep -Fx -- 'default_permissions="improve-executor-runtime"' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name split profile selection"
  grep -Fx -- 'permissions.improve-executor-runtime.filesystem.:root="read"' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name root read permission"
  grep -Fx -- "permissions.improve-executor-runtime.filesystem.:workspace_roots=$expected_permissions" \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name workspace permissions"
  grep -Fx -- 'permissions.improve-executor-runtime.filesystem.:tmpdir="write"' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name temp write permission"
  grep -Fx -- 'permissions.improve-executor-runtime.filesystem.:slash_tmp="write"' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name slash-tmp write permission"
  grep -Fx -- "permissions.improve-executor-runtime.network.enabled=$expected_network" \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name exact network permission"
  ! grep -Fx -- '--sandbox' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name retained --sandbox"
  ! grep -F -- 'sandbox_workspace_write' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name retained legacy workspace-write configuration"
  ! grep -F -- '.git" = "write"' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name granted .git write access"
  jq -e -s --argjson paths "$expected_paths" '
    last
    | .improve_contract == "1.0.0-codex.14"
      and .protected_paths == $paths
  ' "$metric" >/dev/null || fail "$case_name capability metric"
}

assert_contract_13_invocation() {
  assert_eq "$(field "$output" IMPROVE_CONTRACT)" 1.0.0-codex.13 \
    "$case_name effective contract"
  assert_eq "$(field "$output" IMPROVE_PROTECTED_PATHS)" '[]' \
    "$case_name protected paths"
  grep -Fx -- '--sandbox' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name legacy sandbox argument"
  grep -Fx -- 'workspace-write' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name legacy sandbox value"
  grep -Fx -- 'sandbox_workspace_write.network_access=true' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name legacy network argument"
  grep -Fx -- 'sandbox_workspace_write.writable_roots=[]' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name legacy writable roots"
  ! grep -F -- 'permissions.improve-executor-runtime' \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name used split permissions"
  jq -e -s '
    last
    | .improve_contract == "1.0.0-codex.13"
      and .protected_paths == []
  ' "$metric" >/dev/null || fail "$case_name compatibility metric"
}

assert_real_codex_accepts_invocation_config() {
  local compatibility_home="$case_dir/real-codex-home"
  local invocation_argument
  local expect_config_value=0
  local -a config_args=()
  mkdir -p "$compatibility_home"
  while IFS= read -r invocation_argument; do
    if [ "$expect_config_value" -eq 1 ]; then
      config_args+=(-c "$invocation_argument")
      expect_config_value=0
    elif [ "$invocation_argument" = -c ]; then
      expect_config_value=1
    fi
  done <"$FAKE_INVOCATION_LOG"
  [ "$expect_config_value" -eq 0 ] ||
    fail "$case_name has a dangling Codex config flag"
  [ "${#config_args[@]}" -gt 0 ] ||
    fail "$case_name recorded no Codex config arguments"
  if ! CODEX_HOME="$compatibility_home" "$real_codex" \
    "${config_args[@]}" debug prompt-input \
    "Improve config compatibility probe" \
    >"$case_dir/real-codex-output" 2>"$case_dir/real-codex-errors"; then
    sed -n '1,20p' "$case_dir/real-codex-errors" >&2
    fail "$case_name emitted config rejected by the pinned Codex"
  fi
}

assert_contract_15_cache() {
  local expected_paths="${1:-[]}"
  local expected_root
  local expected_cargo
  local expected_npm
  local expected_xdg
  local expected_config_key
  local expected_workspace_permissions
  local expected_filesystem_permissions
  expected_workspace_permissions="$(workspace_permissions_for_paths "$expected_paths")"
  expected_root="$(realpath -- "$XDG_CACHE_HOME/codex-improve")"
  expected_cargo="$expected_root/shared/cargo"
  expected_npm="$expected_root/shared/npm"
  expected_xdg="$expected_root/executions/$(field "$output" IMPROVE_EXECUTION_ID)/xdg"
  expected_config_key="$(jq -nr --arg value "$expected_root" '$value | @json')"
  expected_filesystem_permissions="{ \":root\" = \"read\", \":workspace_roots\" = $expected_workspace_permissions, \":tmpdir\" = \"write\", \":slash_tmp\" = \"write\", $expected_config_key = \"write\" }"
  assert_eq "$(stat -c '%a' "$expected_root")" 700 "$case_name cache root mode"
  assert_eq "$(stat -c '%a' "$expected_cargo")" 700 "$case_name Cargo cache mode"
  assert_eq "$(stat -c '%a' "$expected_npm")" 700 "$case_name npm cache mode"
  assert_eq "$(stat -c '%a' "$expected_xdg")" 700 "$case_name XDG cache mode"
  for cache_log in "$FAKE_CACHE_PREFLIGHT_LOG" "$FAKE_CACHE_EXECUTOR_LOG"; do
    grep -Fx "CARGO_HOME=$expected_cargo" "$cache_log" >/dev/null ||
      fail "$case_name Cargo cache environment"
    grep -Fx "npm_config_cache=$expected_npm" "$cache_log" >/dev/null ||
      fail "$case_name npm cache environment"
    grep -Fx "XDG_CACHE_HOME=$expected_xdg" "$cache_log" >/dev/null ||
      fail "$case_name XDG cache environment"
  done
  [ -e "$expected_cargo/preflight-write" ] &&
    [ -e "$expected_cargo/executor-write" ] || fail "$case_name Cargo cache writes"
  [ -e "$expected_npm/preflight-write" ] &&
    [ -e "$expected_npm/executor-write" ] || fail "$case_name npm cache writes"
  [ -e "$expected_xdg/preflight-write" ] &&
    [ -e "$expected_xdg/executor-write" ] || fail "$case_name XDG cache writes"
  [ ! -e "$expected_cargo/credentials.toml" ] ||
    fail "$case_name copied Cargo credentials"
  [ ! -e "$expected_root/.npmrc" ] || fail "$case_name copied npm config"
  grep -Fx -- \
    "permissions.improve-executor-runtime.filesystem=$expected_filesystem_permissions" \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name cache write grant"
  ! grep -F -- \
    "permissions.improve-executor-runtime.filesystem.$expected_config_key" \
    "$FAKE_INVOCATION_LOG" >/dev/null || fail "$case_name used a dynamic dotted cache key"
  artifact_dir="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  jq -e --arg root "$expected_root" --arg cargo "$expected_cargo" \
    --arg npm "$expected_npm" --arg xdg "$expected_xdg" '
      .cache == {
        enabled: true, root: $root, cargoHome: $cargo, npmCache: $npm,
        xdgCacheHome: $xdg, cargoScope: "shared", npmScope: "shared",
        xdgScope: "execution"
      }
    ' "$artifact_dir/execution.json" >/dev/null ||
    fail "$case_name execution cache record"
}

assert_legacy_cache_disabled() {
  artifact_dir="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  jq -e '.cache.enabled == false and .cache.root == null' \
    "$artifact_dir/execution.json" >/dev/null ||
    fail "$case_name legacy cache record"
  if ! grep -Fx 'CARGO_HOME=' "$FAKE_CACHE_EXECUTOR_LOG" >/dev/null ||
    ! grep -Fx 'npm_config_cache=' "$FAKE_CACHE_EXECUTOR_LOG" >/dev/null; then
    fail "$case_name legacy cache environment"
  fi
  ! grep -F -- 'filesystem."' "$FAKE_INVOCATION_LOG" >/dev/null ||
    fail "$case_name legacy cache grant"
}

assert_rejected_before_mutation() {
  assert_eq "$status" 2 "$1 status"
  assert_preflight_not_invoked "$1"
  [ ! -e "$XDG_STATE_HOME/codex-improve/worktrees" ] ||
    fail "$1 created a worktree"
  [ ! -e "$XDG_STATE_HOME/codex-improve/executions" ] ||
    fail "$1 created execution artifacts"
}

assert_transport_case() {
  expected_status="$1"
  expected_result="$2"
  expected_reason="$3"
  if [ "$status" != "$expected_status" ]; then
    sed 's/^/runner stderr: /' "$errors" >&2
  fi
  assert_eq "$status" "$expected_status" "$case_name status"
  if [ "$(field "$output" IMPROVE_EXEC_RESULT)" != "$expected_result" ]; then
    sed 's/^/runner output: /' "$output" >&2
    sed 's/^/runner stderr: /' "$errors" >&2
  fi
  assert_eq "$(field "$output" IMPROVE_EXEC_RESULT)" "$expected_result" "$case_name result"
  assert_eq "$(field "$output" IMPROVE_EXEC_EXIT_REASON)" "$expected_reason" "$case_name reason"
  case "$(field "$output" IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED)" in
    0|1) ;;
    *) fail "$case_name budget flag is not 0 or 1" ;;
  esac
  artifact_dir="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  case "$artifact_dir" in
    "$XDG_STATE_HOME/codex-improve/executions/"*) ;;
    *) fail "$case_name artifacts are outside per-user state: $artifact_dir" ;;
  esac
  [ -d "$artifact_dir" ] || fail "$case_name artifact directory missing"
  assert_private "$artifact_dir"
  for artifact in prompt.txt events.jsonl final.json final.txt stderr.log timeout.log; do
    [ -e "$artifact_dir/$artifact" ] || fail "$case_name missing $artifact"
    assert_private "$artifact_dir/$artifact"
  done
  [ -f "$artifact_dir/execution.json" ] || fail "$case_name missing execution.json"
  assert_private "$artifact_dir/execution.json"
  assert_execution_record_shape "$artifact_dir/execution.json"
  jq -e --arg result "$expected_result" --arg reason "$expected_reason" '
    .phase == "finished" and .result == $result and .reason == $reason
  ' "$artifact_dir/execution.json" >/dev/null ||
    fail "$case_name final execution record classification"
  assert_no_private_content "$artifact_dir/execution.json"
  metric="$XDG_STATE_HOME/codex-improve/execution-metrics.jsonl"
  [ -s "$metric" ] || fail "$case_name metric missing"
  assert_private "$metric"
  jq -e '(.fuse_flags.rollout_budget_exhausted | type) == "boolean"' "$metric" >/dev/null ||
    fail "$case_name budget metric fuse is not Boolean"
  ! grep -Fq 'IMPROVE_EXEC_STRUCTURED_OUTPUT=' "$output" ||
    fail "$case_name exposed a private structured output field"
  ! grep -Fq 'IMPROVE_EXEC_FINAL_VALIDATION_DETAIL=' "$output" ||
    fail "$case_name exposed a private final validation detail field"
  jq -e -s 'all(.[]; has("final_validation_detail") | not)' "$metric" >/dev/null ||
    fail "$case_name exposed a final validation detail metric"
  assert_no_private_content "$output"
  assert_no_private_content "$errors"
  assert_no_private_content "$metric"
}

assert_closeout_eligible() {
  assert_eq "$(field "$output" IMPROVE_EXEC_CLOSEOUT_ELIGIBLE)" "$1" \
    "$case_name closeout eligibility"
}

assert_invalid_report_preserved() {
  preserved_worktree="$(field "$output" IMPROVE_WORKTREE)"
  [ -d "$preserved_worktree" ] || fail "$case_name worktree was not preserved"
  preserved_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  [ -d "$preserved_artifact" ] ||
    fail "$case_name artifacts were not preserved"
  [ -s "$preserved_artifact/events.jsonl" ] ||
    fail "$case_name event evidence was not preserved"
  [ -s "$preserved_artifact/final.json" ] ||
    fail "$case_name raw report evidence was not preserved"
  assert_eq "$(field "$output" IMPROVE_CANDIDATE_AVAILABLE)" 1 \
    "$case_name candidate availability"
}

assert_execution_id_inherited() {
  assert_eq "$(<"$FAKE_EXECUTION_ID_LOG")" \
    "$(field "$output" IMPROVE_EXECUTION_ID)" \
    "$case_name inherited execution identity"
}

start_case help
run_runner --help
assert_eq "$status" 0 "help status"
grep -F -- "--deep --revise WORKTREE EXPECTED_TREE DOSSIER" "$output" >/dev/null ||
  fail "help omits deep revision mode"
grep -F -- "--spark PLAN" "$output" >/dev/null ||
  fail "help omits Spark initial mode"
grep -F -- "--spark --revise WORKTREE EXPECTED_TREE DOSSIER" "$output" >/dev/null ||
  fail "help omits Spark revision mode"
grep -F -- "codex-improve-exec --recover WORKTREE EXPECTED_TREE DOSSIER" "$output" >/dev/null ||
  fail "help omits standard recovery mode"
grep -F -- "--spark --recover WORKTREE EXPECTED_TREE DOSSIER" "$output" >/dev/null ||
  fail "help omits Spark recovery mode"
grep -F -- "--deep --recover WORKTREE EXPECTED_TREE DOSSIER" "$output" >/dev/null ||
  fail "help omits deep recovery mode"
grep -F -- "--spark --next CHECKPOINT PLAN" "$output" >/dev/null ||
  fail "help omits Spark next mode"
grep -F -- "--deep --next CHECKPOINT PLAN" "$output" >/dev/null ||
  fail "help omits deep next mode"
protected_help='[--allow-protected-path .agents] [--allow-protected-path .codex] [--spark|--deep]'
grep -F -- "--environment-json '<json>' $protected_help PLAN" \
  "$output" >/dev/null || fail "help omits protected-path-capable initial mode"
grep -F -- "--environment-json '<json>' $protected_help --next CHECKPOINT PLAN" \
  "$output" >/dev/null || fail "help omits protected-path-capable next mode"
grep -F -- "--environment-json '<json>' $protected_help --revise WORKTREE EXPECTED_TREE DOSSIER" \
  "$output" >/dev/null || fail "help omits protected-path-capable revision mode"
grep -F -- "--environment-json '<json>' $protected_help --recover WORKTREE EXPECTED_TREE DOSSIER" \
  "$output" >/dev/null || fail "help omits protected-path-capable recovery mode"
grep -F -- "--status [WORKTREE_OR_EXECUTION_ID]" "$output" >/dev/null ||
  fail "help omits status mode"
assert_not_invoked help

start_case status_no_state
run_status
assert_eq "$status" 2 "status without state"
grep -F "Improve execution state is unavailable" "$errors" >/dev/null ||
  fail "status without state reason"
[ ! -e "$XDG_STATE_HOME" ] || fail "status without state mutated state"

start_case status_extra_argument
run_status one two
assert_eq "$status" 2 "status extra argument"
grep -F -- "--status accepts at most one selector" "$errors" >/dev/null ||
  fail "status extra argument reason"

start_case status_invalid_record
mkdir -p "$XDG_STATE_HOME/codex-improve/executions/bad"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions" \
  "$XDG_STATE_HOME/codex-improve/executions/bad"
printf '%s\n' '{"version":1}' \
  >"$XDG_STATE_HOME/codex-improve/executions/bad/execution.json"
chmod 600 "$XDG_STATE_HOME/codex-improve/executions/bad/execution.json"
run_status
assert_eq "$status" 2 "status invalid record"
grep -F "execution registry contains an invalid record" "$errors" >/dev/null ||
  fail "status invalid record reason"

start_case status_nonprivate_record
status_oid="$(git -C "$repo" rev-parse HEAD)"
status_artifact="$XDG_STATE_HOME/codex-improve/executions/nonprivate"
mkdir -p "$XDG_STATE_HOME/codex-improve/executions"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions"
write_status_fixture "$status_artifact" status-nonprivate "$repo" \
  2099-01-01T00:00:00Z "$status_oid"
chmod 644 "$status_artifact/execution.json"
run_status
assert_eq "$status" 2 "status nonprivate record"
grep -F "permissions are not private" "$errors" >/dev/null ||
  fail "status nonprivate record reason"

start_case status_symlink_artifact
mkdir -p "$XDG_STATE_HOME/codex-improve/executions" "$case_dir/real-artifact"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions" "$case_dir/real-artifact"
ln -s "$case_dir/real-artifact" \
  "$XDG_STATE_HOME/codex-improve/executions/link"
run_status
assert_eq "$status" 2 "status symlink artifact"
grep -F "execution registry contains a symbolic link" "$errors" >/dev/null ||
  fail "status symlink artifact reason"

start_case status_symlink_improve_root
mkdir -p "$XDG_STATE_HOME" "$case_dir/real-improve/executions"
chmod 700 "$case_dir/real-improve" "$case_dir/real-improve/executions"
ln -s "$case_dir/real-improve" "$XDG_STATE_HOME/codex-improve"
run_status
assert_eq "$status" 2 "status symlink Improve root"
grep -F "must not be a symbolic link" "$errors" >/dev/null ||
  fail "status symlink Improve root reason"

start_case status_symlink_execution_root
mkdir -p "$XDG_STATE_HOME/codex-improve" "$case_dir/real-executions"
chmod 700 "$XDG_STATE_HOME/codex-improve" "$case_dir/real-executions"
ln -s "$case_dir/real-executions" \
  "$XDG_STATE_HOME/codex-improve/executions"
run_status
assert_eq "$status" 2 "status symlink execution root"
grep -F "must not be a symbolic link" "$errors" >/dev/null ||
  fail "status symlink execution root reason"

start_case status_symlink_record
status_oid="$(git -C "$repo" rev-parse HEAD)"
mkdir -p "$XDG_STATE_HOME/codex-improve/executions/fixture" \
  "$case_dir/real-record"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions" \
  "$XDG_STATE_HOME/codex-improve/executions/fixture" "$case_dir/real-record"
write_status_fixture "$case_dir/real-record" status-record-link "$repo" \
  2099-01-01T00:00:00Z "$status_oid"
ln -s "$case_dir/real-record/execution.json" \
  "$XDG_STATE_HOME/codex-improve/executions/fixture/execution.json"
run_status
assert_eq "$status" 2 "status symlink record"
grep -F "must not be a symbolic link" "$errors" >/dev/null ||
  fail "status symlink record reason"

start_case status_duplicate_execution_id
status_oid="$(git -C "$repo" rev-parse HEAD)"
status_root="$XDG_STATE_HOME/codex-improve/executions"
mkdir -p "$status_root"
chmod 700 "$XDG_STATE_HOME/codex-improve" "$status_root"
write_status_fixture "$status_root/first" duplicate-id "$repo" \
  2099-01-01T00:00:00Z "$status_oid"
write_status_fixture "$status_root/second" duplicate-id "$repo" \
  2100-01-01T00:00:00Z "$status_oid"
run_status duplicate-id
assert_eq "$status" 2 "status duplicate execution ID"
grep -F "duplicate execution ID" "$errors" >/dev/null ||
  fail "status duplicate execution ID reason"

assert_invalid_status_mutation nested_extra '.events.rawContent = "private"'
assert_invalid_status_mutation path_type '.worktree = 1'
assert_invalid_status_mutation resume_lineage '.resume.attempt = 2'
assert_invalid_status_mutation operation '.operation = "candidate"'
assert_invalid_status_mutation profile '.profile = ""'
assert_invalid_status_mutation contract '.improveContract = "future"'
assert_invalid_status_mutation candidate '.currentCandidate.error = "private"'
assert_invalid_status_mutation environment \
  '.environment.preflight.status = "unknown"'
assert_invalid_status_mutation cache '.cache.cargoScope = "execution"'
assert_invalid_status_mutation events '.events.count = 0.5'
assert_invalid_status_mutation tokens '.tokenUsage.activeLimit = 0'
assert_invalid_status_mutation timestamps '.timestamps.finishedAt = null'
assert_invalid_status_mutation phase_result '.phase = "executing"'
assert_invalid_status_mutation next_action '.nextAction = "retry"'

start_case status_artifact_identity
status_oid="$(git -C "$repo" rev-parse HEAD)"
status_artifact="$XDG_STATE_HOME/codex-improve/executions/fixture"
mkdir -p "$XDG_STATE_HOME/codex-improve/executions"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions"
write_status_fixture "$status_artifact" status-artifact-identity "$repo" \
  2099-01-01T00:00:00Z "$status_oid"
jq '.artifactDirectory = "/wrong/artifact"' "$status_artifact/execution.json" \
  >"$status_artifact/execution.json.next"
chmod 600 "$status_artifact/execution.json.next"
mv "$status_artifact/execution.json.next" "$status_artifact/execution.json"
run_status
assert_eq "$status" 2 "status artifact identity"
grep -F "invalid record identity" "$errors" >/dev/null ||
  fail "status artifact identity reason"

assert_schema_input_failure missing_schema missing
assert_schema_input_failure unreadable_schema unreadable
assert_schema_input_failure invalid_schema invalid

for invalid_network_case in missing string null; do
  start_case "invalid_network_access_$invalid_network_case"
  case "$invalid_network_case" in
    missing)
      CODEX_IMPROVE_ROLES_JSON="$(
        jq -c 'del(.standard.networkAccess)' <<<"$valid_roles_json"
      )"
      ;;
    string)
      CODEX_IMPROVE_ROLES_JSON="$(
        jq -c '.spark.networkAccess = "true"' <<<"$valid_roles_json"
      )"
      ;;
    null)
      CODEX_IMPROVE_ROLES_JSON="$(
        jq -c '.deep.networkAccess = null' <<<"$valid_roles_json"
      )"
      ;;
  esac
  export CODEX_IMPROVE_ROLES_JSON
  run_runner "plans/001 plan.md"
  assert_eq "$status" 2 "$invalid_network_case network access status"
  grep -F "generated executor role configuration is missing or invalid" \
    "$errors" >/dev/null ||
    fail "$invalid_network_case network access rejection reason"
  assert_not_invoked "invalid_network_access_$invalid_network_case"
done
export CODEX_IMPROVE_ROLES_JSON="$valid_roles_json"

start_case invalid
run_runner --revise
assert_eq "$status" 2 "invalid argument status"
assert_not_invoked invalid

start_case spark_then_deep
run_runner --spark --deep "plans/001 plan.md"
assert_eq "$status" 2 "Spark/deep argument status"
grep -F -- "--spark and --deep are mutually exclusive" "$errors" >/dev/null ||
  fail "Spark/deep rejection reason missing"
assert_not_invoked spark_then_deep

start_case deep_then_spark
run_runner --deep --spark "plans/001 plan.md"
assert_eq "$status" 2 "deep/Spark argument status"
grep -F -- "--spark and --deep are mutually exclusive" "$errors" >/dev/null ||
  fail "deep/Spark rejection reason missing"
assert_not_invoked deep_then_spark

valid_environment_json="$(
  jq -nc \
    --arg launcher "$fake_bin/env-launcher" \
    --arg probe "$fake_bin/env-probe" \
    '{
      version: 1,
      launcher: [$launcher],
      probes: [
        {argv: [$probe, "literal ; $(touch never)", "two words"], timeoutSeconds: 1},
        {argv: [$probe, "second"], timeoutSeconds: 1}
      ]
    }'
)"
environment_plan="$repo/plans/012 environment.md"
write_environment_artifact() {
  target="$1"
  json="$2"
  {
    printf '%s\n' '# Environment execution'
    # shellcheck disable=SC2016 # Markdown backticks are intentional literals.
    printf '%s\n' '- **Improve contract**: `1.0.0-codex.14`'
    printf '%s\n' '```json codex-improve-environment'
    printf '%s\n' "$json"
    printf '%s\n' '```'
    printf '%s\n' 'TOP_SECRET_PLAN /private/repository/path'
  } >"$target"
}
write_environment_artifact "$environment_plan" "$valid_environment_json"

start_case environment_missing_cli
run_runner "$environment_plan"
assert_eq "$status" 2 "missing environment CLI status"
assert_not_invoked environment_missing_cli
[ ! -e "$XDG_STATE_HOME/codex-improve/worktrees" ] ||
  fail "missing environment CLI created a worktree"

start_case environment_json_not_first
run_runner --deep --environment-json "$valid_environment_json" "$environment_plan"
assert_eq "$status" 2 "environment JSON order status"
assert_preflight_not_invoked environment_json_not_first

start_case protected_without_environment
run_runner --allow-protected-path .agents "$environment_plan"
assert_rejected_before_mutation protected_without_environment

start_case protected_before_environment
run_runner --allow-protected-path .agents --environment-json \
  "$valid_environment_json" "$environment_plan"
assert_rejected_before_mutation protected_before_environment

start_case protected_after_lane
run_runner --environment-json "$valid_environment_json" --deep \
  --allow-protected-path .agents "$environment_plan"
assert_rejected_before_mutation protected_after_lane

start_case protected_missing_value
run_runner --environment-json "$valid_environment_json" --allow-protected-path
assert_rejected_before_mutation protected_missing_value

start_case environment_mismatch
mismatched_environment="$(jq -c '.probes[0].timeoutSeconds = 2' <<<"$valid_environment_json")"
run_runner --environment-json "$mismatched_environment" "$environment_plan"
assert_eq "$status" 2 "mismatched environment status"
assert_not_invoked environment_mismatch
[ ! -e "$XDG_STATE_HOME/codex-improve/worktrees" ] ||
  fail "mismatched environment created a worktree"

start_case environment_extra_key
invalid_environment="$(jq -c '.unexpected = true' <<<"$valid_environment_json")"
invalid_plan="$repo/plans/012 invalid environment.md"
write_environment_artifact "$invalid_plan" "$invalid_environment"
run_runner --environment-json "$invalid_environment" "$invalid_plan"
assert_eq "$status" 2 "extra environment key status"
assert_not_invoked environment_extra_key

invalid_environment_case() {
  invalid_name="$1"
  invalid_json="$2"
  invalid_artifact="$repo/plans/012-$invalid_name.md"
  write_environment_artifact "$invalid_artifact" "$invalid_json"
  start_case "environment_$invalid_name"
  run_runner --environment-json "$invalid_json" "$invalid_artifact"
  assert_eq "$status" 2 "$invalid_name environment status"
  assert_preflight_not_invoked "environment_$invalid_name"
}

invalid_environment_case malformed '{"version":'
invalid_environment_case launcher_count "$(
  jq -nc --arg probe "$fake_bin/env-probe" \
    '{version:1,launcher:[range(0;17)|"launcher"],probes:[{argv:[$probe],timeoutSeconds:1}]}'
)"
invalid_environment_case probe_count "$(
  jq -nc --arg probe "$fake_bin/env-probe" \
    '{version:1,launcher:[],probes:[range(0;17)|{argv:[$probe],timeoutSeconds:1}]}'
)"
invalid_environment_case argv_count "$(
  jq -nc '{version:1,launcher:[],probes:[{argv:[range(0;33)|"arg"],timeoutSeconds:1}]}'
)"
invalid_environment_case empty_argv \
  '{"version":1,"launcher":[],"probes":[{"argv":[],"timeoutSeconds":1}]}'
invalid_environment_case empty_argv_value \
  '{"version":1,"launcher":[],"probes":[{"argv":[""],"timeoutSeconds":1}]}'
invalid_environment_case empty_launcher_value \
  '{"version":1,"launcher":[""],"probes":[{"argv":["true"],"timeoutSeconds":1}]}'
invalid_environment_case probe_extra_key \
  '{"version":1,"launcher":[],"probes":[{"argv":["true"],"timeoutSeconds":1,"extra":true}]}'
invalid_environment_case control_character "$(
  jq -nc '{version:1,launcher:["bad\u000aarg"],probes:[{argv:["true"],timeoutSeconds:1}]}'
)"
invalid_environment_case timeout_low \
  '{"version":1,"launcher":[],"probes":[{"argv":["true"],"timeoutSeconds":0}]}'
invalid_environment_case timeout_high \
  '{"version":1,"launcher":[],"probes":[{"argv":["true"],"timeoutSeconds":901}]}'
invalid_environment_case timeout_fraction \
  '{"version":1,"launcher":[],"probes":[{"argv":["true"],"timeoutSeconds":1.5}]}'
invalid_environment_case omission_missing \
  '{"version":1,"launcher":[],"probes":[]}'
invalid_environment_case omission_empty \
  '{"version":1,"launcher":[],"probes":[],"probeOmissionReason":""}'
invalid_environment_case omission_forbidden \
  '{"version":1,"launcher":[],"probes":[{"argv":["true"],"timeoutSeconds":1}],"probeOmissionReason":"not empty"}'

oversized_value="$(printf '%016500d' 0)"
invalid_environment_case oversized "$(
  jq -nc --arg value "$oversized_value" \
    '{version:1,launcher:[$value],probes:[{argv:["true"],timeoutSeconds:1}]}'
)"

start_case environment_missing_block
missing_block_plan="$repo/plans/012-missing-block.md"
# shellcheck disable=SC2016 # Markdown backticks are intentional literals.
printf '%s\n' '- **Improve contract**: `1.0.0-codex.14`' >"$missing_block_plan"
run_runner --environment-json "$valid_environment_json" "$missing_block_plan"
assert_eq "$status" 2 "missing environment block status"
assert_preflight_not_invoked environment_missing_block

start_case environment_duplicate_block
duplicate_plan="$repo/plans/012-duplicate-block.md"
write_environment_artifact "$duplicate_plan" "$valid_environment_json"
{
  printf '%s\n' '```json codex-improve-environment'
  printf '%s\n' "$valid_environment_json"
  printf '%s\n' '```'
} >>"$duplicate_plan"
run_runner --environment-json "$valid_environment_json" "$duplicate_plan"
assert_eq "$status" 2 "duplicate environment block status"
assert_preflight_not_invoked environment_duplicate_block

start_case environment_unterminated_block
unterminated_plan="$repo/plans/012-unterminated-block.md"
{
  # shellcheck disable=SC2016 # Markdown backticks are intentional literals.
  printf '%s\n' '- **Improve contract**: `1.0.0-codex.14`'
  printf '%s\n' '```json codex-improve-environment'
  printf '%s\n' "$valid_environment_json"
} >"$unterminated_plan"
run_runner --environment-json "$valid_environment_json" "$unterminated_plan"
assert_eq "$status" 2 "unterminated environment block status"
assert_preflight_not_invoked environment_unterminated_block

unsupported_contract_plan="$repo/plans/012-unsupported-contract.md"
write_environment_artifact "$unsupported_contract_plan" "$valid_environment_json"
sed -i 's/1\.0\.0-codex\.14/1.0.0-codex.12/' "$unsupported_contract_plan"
start_case environment_unsupported_contract
run_runner --environment-json "$valid_environment_json" "$unsupported_contract_plan"
assert_eq "$status" 2 "unsupported .12 environment contract status"
assert_preflight_not_invoked environment_unsupported_contract
[ ! -e "$XDG_STATE_HOME/codex-improve/worktrees" ] ||
  fail "unsupported .12 contract created a worktree"

contract_15_plan="$repo/plans/015-contract.md"
write_environment_artifact "$contract_15_plan" "$valid_environment_json"
sed -i 's/1\.0\.0-codex\.14/1.0.0-codex.15/' "$contract_15_plan"
printf '%s\n' CONTRACT_15_PRE_HOOK_BYTES >>"$contract_15_plan"

future_contract_plan="$repo/plans/016-future-contract.md"
write_environment_artifact "$future_contract_plan" "$valid_environment_json"
sed -i 's/1\.0\.0-codex\.14/1.0.0-codex.16/' "$future_contract_plan"
start_case environment_future_contract
run_runner --environment-json "$valid_environment_json" "$future_contract_plan"
assert_eq "$status" 2 "future environment contract status"
assert_preflight_not_invoked environment_future_contract

legacy_environment_plan="$repo/plans/011-environment.md"
write_environment_artifact "$legacy_environment_plan" "$valid_environment_json"
sed -i 's/1\.0\.0-codex\.14/1.0.0-codex.11/' "$legacy_environment_plan"

undeclared_environment_plan="$repo/plans/undeclared-environment.md"
write_environment_artifact "$undeclared_environment_plan" "$valid_environment_json"
sed -i '/Improve contract/d' "$undeclared_environment_plan"

start_case protected_legacy_without_environment
run_runner --allow-protected-path .agents "$legacy_environment_plan"
assert_rejected_before_mutation protected_legacy_without_environment

start_case protected_undeclared_without_environment
run_runner --allow-protected-path .codex "$undeclared_environment_plan"
assert_rejected_before_mutation protected_undeclared_without_environment

start_case environment_legacy_opt_in complete
run_runner --environment-json "$valid_environment_json" "$legacy_environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "legacy environment opt-in status"

contract_13_plan="$repo/plans/013-compatibility.md"
write_environment_artifact "$contract_13_plan" "$valid_environment_json"
sed -i 's/1\.0\.0-codex\.14/1.0.0-codex.13/' "$contract_13_plan"
start_case contract_13_legacy_permissions complete
run_runner --environment-json "$valid_environment_json" "$contract_13_plan"
assert_transport_case 0 COMPLETE completed
assert_contract_13_invocation
assert_legacy_cache_disabled
[ -z "$(field "$output" IMPROVE_EXEC_CLOSEOUT_ELIGIBLE)" ] ||
  fail ".13 execution exposed .15 closeout eligibility"
[ -z "$(field "$output" IMPROVE_PLAN_SHA256)" ] ||
  fail ".13 execution exposed .15 plan identity"
! grep -F -- "On successive rollout reminders" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".13 prompt included the .15 rollout reminder"

start_case contract_13_manifest complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" "$contract_13_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
contract_13_worktree="$(field "$output" IMPROVE_WORKTREE)"
contract_13_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
contract_13_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
contract_13_manifest="$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)"
contract_13_state_home="$XDG_STATE_HOME"
contract_13_home="$HOME"
jq -e '
  .improveContract == "1.0.0-codex.13"
    and (has("protectedPaths") | not)
' "$contract_13_manifest" >/dev/null || fail ".13 generated manifest key shape"

legacy_13_artifact="$contract_13_state_home/codex-improve/executions/legacy-13-fixture"
cp -a -- "$contract_13_artifact" "$legacy_13_artifact"
jq --arg artifact "$(realpath -- "$legacy_13_artifact")" \
  '.artifactDirectory = $artifact' "$legacy_13_artifact/resume-manifest.json" \
  >"$legacy_13_artifact/resume-manifest.json.tmp"
mv -- "$legacy_13_artifact/resume-manifest.json.tmp" \
  "$legacy_13_artifact/resume-manifest.json"
sha256sum "$legacy_13_artifact/resume-manifest.json" | \
  sed 's/[[:space:]].*$//' >"$legacy_13_artifact/resume-manifest.sha256"
chmod 600 "$legacy_13_artifact/resume-manifest.json" \
  "$legacy_13_artifact/resume-manifest.sha256"

start_resume_case contract_13_legacy_manifest_resume \
  "$contract_13_state_home" "$contract_13_home" complete
run_runner --resume "$contract_13_worktree" "$contract_13_tree" \
  "$legacy_13_artifact"
assert_transport_case 0 COMPLETE completed
assert_contract_13_invocation

start_resume_case contract_13_generated_manifest_resume \
  "$contract_13_state_home" "$contract_13_home" complete
run_runner --resume "$contract_13_worktree" "$contract_13_tree" \
  "$contract_13_artifact"
assert_transport_case 0 COMPLETE completed
assert_contract_13_invocation

start_case contract_15_initial complete
contract_15_original="$test_root/contract-15-original.md"
cp -- "$contract_15_plan" "$contract_15_original"
contract_15_original_hash="$(
  sha256sum "$contract_15_original" | sed 's/[[:space:]].*$//'
)"
contract_15_hook="$repo/.git/hooks/post-checkout"
contract_15_hook_marker="$test_root/contract-15-post-checkout"
printf '#!%s\n' "$(command -v bash)" >"$contract_15_hook"
cat >>"$contract_15_hook" <<'PLAN_RACE_HOOK'
printf '%s\n' CONTRACT_15_POST_HOOK_BYTES >"$PLAN_RACE_SOURCE"
: >"$PLAN_RACE_MARKER"
PLAN_RACE_HOOK
chmod +x "$contract_15_hook"
export PLAN_RACE_SOURCE="$contract_15_plan"
export PLAN_RACE_MARKER="$contract_15_hook_marker"
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents "$contract_15_plan"
assert_transport_case 0 COMPLETE completed
[ -e "$contract_15_hook_marker" ] || fail ".15 plan race hook did not execute"
assert_eq "$(field "$output" IMPROVE_CONTRACT)" 1.0.0-codex.15 \
  ".15 effective contract"
assert_eq "$(field "$output" IMPROVE_PROTECTED_PATHS)" '[".agents"]' \
  ".15 protected paths"
assert_closeout_eligible 0
assert_contract_15_cache '[".agents"]'
contract_15_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
contract_15_worktree="$(field "$output" IMPROVE_WORKTREE)"
[ -f "$contract_15_artifact/plan.md" ] || fail ".15 plan snapshot missing"
assert_private "$contract_15_artifact/plan.md"
cmp "$contract_15_original" "$contract_15_artifact/plan.md" ||
  fail ".15 plan snapshot changed input bytes"
assert_eq "$(field "$output" IMPROVE_PLAN_SHA256)" \
  "$contract_15_original_hash" \
  ".15 plan SHA-256"
grep -F -- CONTRACT_15_PRE_HOOK_BYTES "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".15 prompt omitted pre-hook plan bytes"
! grep -F -- CONTRACT_15_POST_HOOK_BYTES "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".15 prompt included post-hook plan bytes"
grep -F -- "On successive rollout reminders" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".15 prompt omitted the rollout reminder"
grep -F -- "do not calculate or reconstruct candidate identity" \
  "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".15 prompt omitted runner-owned candidate identity"
[ ! -e "$contract_15_worktree/plans/015-contract.md" ] ||
  fail ".15 plan was copied into the candidate worktree"

contract_15_execution_id="$(field "$output" IMPROVE_EXECUTION_ID)"
contract_15_input_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
contract_15_runner_output="$output"
run_status "$contract_15_execution_id"
assert_eq "$status" 0 "status by execution ID"
assert_execution_record_shape "$output"
jq -e --arg id "$contract_15_execution_id" \
  '.executionId == $id and .phase == "finished" and .result == "COMPLETE"' \
  "$output" >/dev/null || fail "status by execution ID record"
assert_no_private_content "$output"

status_root="$XDG_STATE_HOME/codex-improve/executions"
write_status_fixture "$status_root/status-older" status-older \
  "$contract_15_worktree" 2099-01-01T00:00:00Z "$contract_15_input_tree"
write_status_fixture "$status_root/status-newer" status-newer \
  "$contract_15_worktree" 2100-01-01T00:00:00Z "$contract_15_input_tree"
run_status
assert_eq "$status" 0 "status newest"
jq -e '.executionId == "status-newer"' "$output" >/dev/null ||
  fail "status newest selection"
run_status "$contract_15_worktree"
assert_eq "$status" 0 "status by worktree"
jq -e '.executionId == "status-newer"' "$output" >/dev/null ||
  fail "status worktree newest selection"
run_status "$contract_15_execution_id"
assert_eq "$status" 0 "status exact ID precedence"
jq -e --arg id "$contract_15_execution_id" '.executionId == $id' \
  "$output" >/dev/null || fail "status exact ID precedence record"
run_status no-such-execution
assert_eq "$status" 2 "status missing execution"
grep -F "no matching Improve execution record" "$errors" >/dev/null ||
  fail "status missing execution reason"
run_status "$case_dir/no/such/worktree"
assert_eq "$status" 2 "status invalid worktree"
grep -F "status selector is neither an execution ID nor a worktree" \
  "$errors" >/dev/null || fail "status invalid worktree reason"

start_case status_atomic_replacement
status_oid="$(git -C "$repo" rev-parse HEAD)"
status_root="$XDG_STATE_HOME/codex-improve/executions"
status_artifact="$status_root/atomic"
mkdir -p "$status_root"
chmod 700 "$XDG_STATE_HOME/codex-improve" "$status_root"
write_status_fixture "$status_artifact" atomic-a "$repo" \
  2099-01-01T00:00:00Z "$status_oid"
cp "$status_artifact/execution.json" "$case_dir/atomic-a.json"
write_status_fixture "$status_artifact" atomic-b "$repo" \
  2100-01-01T00:00:00Z "$status_oid"
cp "$status_artifact/execution.json" "$case_dir/atomic-b.json"
(
  for atomic_iteration in $(seq 1 80); do
    if [ "$((atomic_iteration % 2))" -eq 0 ]; then
      cp "$case_dir/atomic-a.json" "$status_artifact/execution.json.next"
    else
      cp "$case_dir/atomic-b.json" "$status_artifact/execution.json.next"
    fi
    chmod 600 "$status_artifact/execution.json.next"
    mv "$status_artifact/execution.json.next" \
      "$status_artifact/execution.json"
  done
) &
atomic_writer_pid="$!"
for _ in $(seq 1 20); do
  run_status
  [ "$status" -eq 0 ] || {
    wait "$atomic_writer_pid" || true
    fail "status atomic replacement failed"
  }
  jq -e '.executionId == "atomic-a" or .executionId == "atomic-b"' \
    "$output" >/dev/null || {
    wait "$atomic_writer_pid" || true
    fail "status atomic replacement returned a mixed snapshot"
  }
  assert_execution_record_shape "$output"
done
wait "$atomic_writer_pid"

output="$contract_15_runner_output"
cp -- "$contract_15_original" "$contract_15_plan"
rm -- "$contract_15_hook"
unset PLAN_RACE_SOURCE PLAN_RACE_MARKER

start_case contract_15_cache_metacharacters complete
export XDG_CACHE_HOME="$case_dir/cache \"quoted\" \\ backslash"
run_runner --environment-json "$valid_environment_json" "$contract_15_plan"
assert_transport_case 0 COMPLETE completed
assert_contract_15_cache
assert_real_codex_accepts_invocation_config

start_case contract_15_manifest complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex "$contract_15_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_closeout_eligible 0
contract_15_resume_worktree="$(field "$output" IMPROVE_WORKTREE)"
contract_15_resume_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
contract_15_resume_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
contract_15_state_home="$XDG_STATE_HOME"
contract_15_home="$HOME"
jq -e '
  .improveContract == "1.0.0-codex.15"
    and .protectedPaths == [".codex"]
' "$contract_15_resume_artifact/resume-manifest.json" >/dev/null ||
  fail ".15 generated manifest contract"

start_resume_case contract_15_manifest_resume \
  "$contract_15_state_home" "$contract_15_home" complete
run_runner --resume "$contract_15_resume_worktree" "$contract_15_resume_tree" \
  "$contract_15_resume_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_CONTRACT)" 1.0.0-codex.15 \
  ".15 resumed contract"
assert_eq "$(field "$output" IMPROVE_PROTECTED_PATHS)" '[".codex"]' \
  ".15 resumed protected paths"
assert_closeout_eligible 0
assert_contract_15_cache '[".codex"]'

start_case status_live intermediate_complete_message
copy_runner
live_runner_output="$case_dir/live-runner-output"
live_runner_errors="$case_dir/live-runner-errors"
(
  cd "$repo"
  bash "$runner" --environment-json "$valid_environment_json" "$contract_15_plan"
) >"$live_runner_output" 2>"$live_runner_errors" &
live_runner_pid="$!"
for _ in $(seq 1 100); do
  [ -e "$FAKE_LIVE_READY" ] && break
  sleep 0.05
done
[ -e "$FAKE_LIVE_READY" ] || {
  : >"$FAKE_LIVE_RELEASE"
  wait "$live_runner_pid" || true
  fail "live status fixture did not reach Codex"
}
live_status_observed=0
for _ in $(seq 1 100); do
  run_status
  if [ "$status" -eq 0 ] && jq -e '
    .phase == "executing" and .result == null and .reason == null
      and .finalPresent == false and .nextAction == "wait"
      and .events.latestType == "item.completed"
  ' "$output" >/dev/null; then
    live_status_observed=1
    break
  fi
  sleep 0.05
done
: >"$FAKE_LIVE_RELEASE"
wait "$live_runner_pid"
live_runner_status="$?"
assert_eq "$live_status_observed" 1 "live status ignores COMPLETE-looking message"
output="$live_runner_output"
errors="$live_runner_errors"
status="$live_runner_status"
assert_transport_case 0 COMPLETE completed
assert_contract_15_cache

assert_legacy_compatibility_resume() {
  local seed_name="$1"
  local source_artifact="$2"
  local effective_contract="$3"
  local seed_worktree
  local seed_tree
  local seed_artifact
  local seed_manifest
  local seed_state_home
  local seed_home

  start_case "$seed_name" complete
  export FAKE_PROBE_MODE=fail
  run_runner --environment-json "$valid_environment_json" "$source_artifact"
  assert_transport_case 0 STOPPED environment_preflight_failed
  assert_eq "$(field "$output" IMPROVE_CONTRACT)" "$effective_contract" \
    "$seed_name effective execution contract"
  jq -e -s --arg contract "$effective_contract" '
    last
    | .improve_contract == $contract
      and .protected_paths == []
  ' "$metric" >/dev/null || fail "$seed_name effective contract metric"
  seed_worktree="$(field "$output" IMPROVE_WORKTREE)"
  seed_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
  seed_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  seed_manifest="$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)"
  seed_state_home="$XDG_STATE_HOME"
  seed_home="$HOME"
  jq -e '
    .improveContract == "1.0.0-codex.13"
      and (has("protectedPaths") | not)
  ' "$seed_manifest" >/dev/null || fail "$seed_name compatibility manifest shape"

  start_resume_case "${seed_name}_resume" "$seed_state_home" "$seed_home" complete
  export FAKE_PROBE_MODE=pass
  run_runner --resume "$seed_worktree" "$seed_tree" "$seed_artifact"
  assert_transport_case 0 COMPLETE completed
  assert_contract_13_invocation
}

assert_legacy_compatibility_resume legacy_11_manifest \
  "$legacy_environment_plan" 1.0.0-codex.11
assert_legacy_compatibility_resume undeclared_manifest \
  "$undeclared_environment_plan" undeclared

for invalid_path in '' .git .Agents .agents/ other ../.agents /tmp/.agents '.agent*'; do
  start_case "protected_invalid_${invalid_path//[^A-Za-z0-9]/_}"
  run_runner --environment-json "$valid_environment_json" \
    --allow-protected-path "$invalid_path" "$environment_plan"
  assert_rejected_before_mutation "invalid protected path $invalid_path"
done

start_case protected_duplicate
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --allow-protected-path .agents "$environment_plan"
assert_rejected_before_mutation protected_duplicate

start_case protected_duplicate_codex
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --allow-protected-path .codex "$environment_plan"
assert_rejected_before_mutation protected_duplicate_codex

start_case protected_contract_13
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents "$contract_13_plan"
assert_rejected_before_mutation protected_contract_13

start_case protected_candidate
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --candidate nowhere
assert_rejected_before_mutation protected_candidate

start_case protected_checkpoint
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --checkpoint nowhere deadbeef message
assert_rejected_before_mutation protected_checkpoint

omitted_environment_json='{"version":1,"launcher":[],"probes":[],"probeOmissionReason":"No project probe is required."}'
omitted_environment_plan="$repo/plans/012-omitted-probes.md"
write_environment_artifact "$omitted_environment_plan" "$omitted_environment_json"
start_case environment_valid_omission complete
run_runner --environment-json "$omitted_environment_json" "$omitted_environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_COUNT)" 0 \
  "approved empty probe count"

start_case environment_success complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --allow-protected-path .agents "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 1 "environment invoked marker"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed "environment preflight status"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_COUNT)" 2 "environment preflight count"
assert_contract_14_invocation '[".agents",".codex"]' true
! grep -F -- "On successive rollout reminders" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail ".14 prompt included the .15 rollout reminder"
assert_eq "$(wc -l <"$FAKE_LAUNCHER_COUNT")" 1 "single launcher invocation"
assert_eq "$(<"$FAKE_CODEX_LAUNCHER_LOG")" visible "Codex launcher marker"
assert_eq "$(wc -l <"$FAKE_PROBE_LOG")" 2 "sequential probe count"
grep -F 'marker=visible argc=2' "$FAKE_PROBE_LOG" >/dev/null ||
  fail "literal probe arguments or launcher marker missing"
sed -n '2p' "$FAKE_PROBE_LOG" | grep -F '<second>' >/dev/null ||
  fail "second probe did not run after the first"
[ ! -e "$repo/never" ] || fail "probe argument metacharacters were evaluated"
environment_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
for private_file in environment.json preflight.log preflight-status executor-invoked \
  prompt-body.txt; do
  assert_eq "$(stat -c '%a' "$environment_artifact/$private_file")" 600 \
    "$private_file permissions"
done
assert_eq "$(stat -c '%a' "$environment_artifact/environment-wrapper")" 700 \
  "environment wrapper permissions"
environment_hash="$(field "$output" IMPROVE_EXEC_ENVIRONMENT_HASH)"
jq -e --arg environment_hash "$environment_hash" '
  .executor_invoked == true
    and .environment_hash == $environment_hash
    and .preflight_count == 2
    and .preflight_status == "passed"
    and .improve_contract == "1.0.0-codex.14"
    and .protected_paths == [".agents", ".codex"]
' "$metric" >/dev/null || fail "environment metric fields"
environment_worktree="$(field "$output" IMPROVE_WORKTREE)"
environment_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
environment_state_home="$XDG_STATE_HOME"
environment_home="$HOME"

start_case environment_spark complete
run_runner --environment-json "$valid_environment_json" --spark "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "environment Spark profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment Spark preflight status"
assert_contract_14_invocation '[]' true

start_case environment_deep complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --deep "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "environment deep profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment deep preflight status"
assert_contract_14_invocation '[".agents"]' true

start_case environment_network_denied complete
CODEX_IMPROVE_ROLES_JSON="$(
  jq -c '.standard.networkAccess = false' <<<"$valid_roles_json"
)"
export CODEX_IMPROVE_ROLES_JSON
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_contract_14_invocation '[".codex"]' false
export CODEX_IMPROVE_ROLES_JSON="$valid_roles_json"

empty_launcher_json="$(
  jq -c '.launcher = [] | .probes = [.probes[0]]' <<<"$valid_environment_json"
)"
empty_launcher_plan="$repo/plans/012-empty-launcher.md"
write_environment_artifact "$empty_launcher_plan" "$empty_launcher_json"
start_case environment_empty_launcher complete
run_runner --environment-json "$empty_launcher_json" "$empty_launcher_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(wc -l <"$FAKE_LAUNCHER_COUNT")" 0 "empty launcher invocation count"
assert_eq "$(<"$FAKE_CODEX_LAUNCHER_LOG")" unset "empty launcher Codex marker"
grep -F 'marker=unset' "$FAKE_PROBE_LOG" >/dev/null ||
  fail "empty launcher probe inherited a launcher marker"

start_case environment_probe_timeout complete
export FAKE_PROBE_MODE=timeout
run_runner --environment-json "$empty_launcher_json" "$empty_launcher_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 0 "timed-out probe invoked marker"
assert_preflight_not_invoked environment_probe_timeout

start_case environment_preflight_signal complete
export FAKE_PROBE_MODE=timeout
copy_runner
output="$case_dir/output"
errors="$case_dir/errors"
(
  cd "$repo"
  exec bash "$runner" --environment-json \
    "$empty_launcher_json" "$empty_launcher_plan"
) >"$output" 2>"$errors" &
wrapper_pid="$!"
for _ in $(seq 1 50); do
  [ -s "$FAKE_PROBE_LOG" ] && break
  sleep 0.1
done
[ -s "$FAKE_PROBE_LOG" ] || fail "preflight signal case did not start its probe"
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
status="$?"
set -e
assert_transport_case 1 INCONCLUSIVE wrapper_signal_TERM
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 0 \
  "preflight signal invoked marker"
[ -z "$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)" ] ||
  fail "preflight signal produced a resume manifest"
assert_preflight_not_invoked environment_preflight_signal

delay_environment_json="$(
  jq -c '.launcher = [] | .probes = [.probes[0]]' <<<"$valid_environment_json"
)"
delay_environment_plan="$repo/plans/012-delay.md"
write_environment_artifact "$delay_environment_plan" "$delay_environment_json"
start_case environment_timeout_independence delayed_complete
export FAKE_PROBE_MODE=delay
CODEX_IMPROVE_ROLES_JSON="$(jq -c '.standard.initialTimeout = 2' <<<"$valid_roles_json")"
export CODEX_IMPROVE_ROLES_JSON
run_runner --environment-json "$delay_environment_json" "$delay_environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 2 \
  "model retained full timeout after probe"
export CODEX_IMPROVE_ROLES_JSON="$valid_roles_json"

start_case environment_upgrade_failure complete
mkdir -p "$XDG_STATE_HOME/codex-improve/worktrees"
chmod 700 "$XDG_STATE_HOME/codex-improve"
chmod 755 "$XDG_STATE_HOME/codex-improve/worktrees"
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" "$environment_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(stat -c '%a' "$XDG_STATE_HOME/codex-improve/worktrees")" 700 \
  "legacy worktree root was made private"
upgrade_worktree="$(field "$output" IMPROVE_WORKTREE)"
upgrade_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
upgrade_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
upgrade_state_home="$XDG_STATE_HOME"
upgrade_home="$HOME"

start_resume_case environment_upgrade_resume \
  "$upgrade_state_home" "$upgrade_home" complete
run_runner --resume "$upgrade_worktree" "$upgrade_tree" "$upgrade_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 1 \
  "upgraded state resume invoked marker"
assert_contract_14_invocation '[]' true

start_case environment_failure complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex "$environment_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 0 "failed preflight invoked marker"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" failed "failed preflight status"
assert_not_invoked environment_failure
assert_eq "$(field "$output" IMPROVE_CONTRACT)" 1.0.0-codex.14 \
  "failed preflight contract"
assert_eq "$(field "$output" IMPROVE_PROTECTED_PATHS)" '[".codex"]' \
  "failed preflight protected paths"
jq -e -s '
  last
  | .improve_contract == "1.0.0-codex.14"
    and .protected_paths == [".codex"]
' "$metric" >/dev/null || fail "failed preflight capability metric"
failure_worktree="$(field "$output" IMPROVE_WORKTREE)"
failure_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
failure_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
failure_manifest="$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)"
failure_state_home="$XDG_STATE_HOME"
failure_home="$HOME"
[ -s "$failure_manifest" ] || fail "preflight failure resume manifest missing"
assert_private "$failure_manifest"
jq -e '
  .improveContract == "1.0.0-codex.14"
    and .protectedPaths == [".codex"]
    and .reason == "environment_preflight_failed"
    and .executorInvoked == false
    and .resumeAttempt == 0
' "$failure_manifest" >/dev/null || fail "preflight failure manifest schema"
jq -e --arg head "$(field "$output" IMPROVE_CANDIDATE_HEAD)" \
  --arg tree "$failure_tree" '
  .candidateHead == $head
    and .candidateTree == $tree
    and .base == $head
    and .environmentSha256 != ""
    and .promptBodySha256 != ""
' "$failure_manifest" >/dev/null || fail "preflight failure manifest identity"
assert_no_private_content "$output"
assert_no_private_content "$errors"
assert_no_private_content "$metric"

manifest_backup="$test_root/resume-manifest.backup"
manifest_hash_backup="$test_root/resume-manifest.sha256.backup"
environment_backup="$test_root/resume-environment.backup"
prompt_body_backup="$test_root/resume-prompt-body.backup"
cp "$failure_manifest" "$manifest_backup"
cp "$failure_artifact/resume-manifest.sha256" "$manifest_hash_backup"
cp "$failure_artifact/environment.json" "$environment_backup"
cp "$failure_artifact/prompt-body.txt" "$prompt_body_backup"

reject_modified_manifest() {
  rejection_name="$1"
  rejection_filter="$2"
  jq "$rejection_filter" "$manifest_backup" >"$failure_manifest"
  sha256sum "$failure_manifest" | sed 's/[[:space:]].*$//' \
    >"$failure_artifact/resume-manifest.sha256"
  start_resume_case "$rejection_name" "$failure_state_home" "$failure_home"
  run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
  assert_eq "$status" 2 "$rejection_name status"
  assert_preflight_not_invoked "$rejection_name"
  cp "$manifest_backup" "$failure_manifest"
  cp "$manifest_hash_backup" "$failure_artifact/resume-manifest.sha256"
}

reject_modified_manifest resume_legacy '.improveContract = "1.0.0-codex.11"'
reject_modified_manifest resume_wrong_reason '.reason = "environment_preflight_mutated_candidate"'
reject_modified_manifest resume_model_invoked '.executorInvoked = true'
reject_modified_manifest resume_inconclusive '.result = "INCONCLUSIVE"'
reject_modified_manifest resume_already_attempted '.resumeAttempt = 1'
reject_modified_manifest resume_wrong_tree '.candidateTree = .candidateHead'
reject_modified_manifest resume_stale_role '.role.profile = "stale-profile"'
reject_modified_manifest resume_wrong_user '.userId += 1'
reject_modified_manifest resume_unknown_protected \
  '.protectedPaths = [".git"]'
reject_modified_manifest resume_duplicate_protected \
  '.protectedPaths = [".codex", ".codex"]'
reject_modified_manifest resume_noncanonical_protected \
  '.protectedPaths = [".codex", ".agents"]'
reject_modified_manifest resume_wrong_protected_type \
  '.protectedPaths = ".codex"'
reject_modified_manifest resume_missing_protected 'del(.protectedPaths)'
reject_modified_manifest resume_cross_version_protected \
  '.improveContract = "1.0.0-codex.13"'
reject_modified_manifest resume_extra_manifest_key '.unexpected = true'

printf '%s\n' 'tampered' >>"$failure_manifest"
start_resume_case resume_tampered "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "tampered resume status"
assert_preflight_not_invoked resume_tampered
cp "$manifest_backup" "$failure_manifest"

printf '%s\n' 'tampered' >>"$failure_artifact/environment.json"
start_resume_case resume_environment_tampered "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "tampered resume environment status"
assert_preflight_not_invoked resume_environment_tampered
cp "$environment_backup" "$failure_artifact/environment.json"

printf '%s\n' 'tampered' >>"$failure_artifact/prompt-body.txt"
start_resume_case resume_prompt_tampered "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "tampered resume prompt status"
assert_preflight_not_invoked resume_prompt_tampered
cp "$prompt_body_backup" "$failure_artifact/prompt-body.txt"

chmod 644 "$failure_manifest"
start_resume_case resume_permissive "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "permissive resume status"
assert_preflight_not_invoked resume_permissive
chmod 600 "$failure_manifest"

start_case resume_outside_xdg
mkdir -p "$XDG_STATE_HOME/codex-improve/executions" \
  "$XDG_STATE_HOME/codex-improve/worktrees"
chmod 700 "$XDG_STATE_HOME/codex-improve" \
  "$XDG_STATE_HOME/codex-improve/executions" \
  "$XDG_STATE_HOME/codex-improve/worktrees"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "outside-XDG resume status"
assert_preflight_not_invoked resume_outside_xdg

start_resume_case resume_override "$failure_state_home" "$failure_home"
run_runner --deep --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "resume override status"
assert_preflight_not_invoked resume_override

start_resume_case resume_protected_override "$failure_state_home" "$failure_home"
run_runner --resume --allow-protected-path .agents \
  "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "resume protected override status"
assert_preflight_not_invoked resume_protected_override

failure_tracked_backup="$test_root/failure-tracked.backup"
cp "$failure_worktree/tracked.txt" "$failure_tracked_backup"
printf '%s\n' 'stale candidate' >>"$failure_worktree/tracked.txt"
start_resume_case resume_stale_candidate "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "stale resume candidate status"
assert_preflight_not_invoked resume_stale_candidate
cp "$failure_tracked_backup" "$failure_worktree/tracked.txt"

clone_resume_artifact() {
  local destination="$1"
  cp -a -- "$failure_artifact" "$destination"
  jq --arg artifact "$(realpath -- "$destination")" \
    '.artifactDirectory = $artifact' "$destination/resume-manifest.json" \
    >"$destination/resume-manifest.json.tmp"
  mv -- "$destination/resume-manifest.json.tmp" \
    "$destination/resume-manifest.json"
  sha256sum "$destination/resume-manifest.json" | \
    sed 's/[[:space:]].*$//' >"$destination/resume-manifest.sha256"
  chmod 600 "$destination/resume-manifest.json" \
    "$destination/resume-manifest.sha256"
}

content_race_bin="$test_root/resume-content-race-bin"
mkdir -p "$content_race_bin"
real_cp="$(command -v cp)"
real_sha256sum="$(command -v sha256sum)"
printf '#!%s\n' "$(command -v bash)" >"$content_race_bin/cp"
cat >>"$content_race_bin/cp" <<'RACE_CP'
set -euo pipefail
source_path="${1:-}"
if [ "$source_path" = "--" ]; then
  source_path="${2:-}"
fi
"$REAL_CP" "$@"
if [ "$source_path" = "$RACE_SOURCE" ] && [ ! -e "$RACE_MARKER" ]; then
  "$REAL_CP" -- "$RACE_REPLACEMENT" "$RACE_SOURCE"
  chmod 600 "$RACE_SOURCE"
  : >"$RACE_MARKER"
fi
RACE_CP
chmod +x "$content_race_bin/cp"
printf '#!%s\n' "$(command -v bash)" >"$content_race_bin/sha256sum"
cat >>"$content_race_bin/sha256sum" <<'RACE_SHA256'
set -euo pipefail
if [ "${1:-}" = "$RACE_SOURCE" ] && [ ! -e "$RACE_MARKER" ]; then
  "$REAL_SHA256SUM" "$@"
  status="$?"
  "$REAL_CP" -- "$RACE_REPLACEMENT" "$RACE_SOURCE"
  chmod 600 "$RACE_SOURCE"
  : >"$RACE_MARKER"
  exit "$status"
fi
exec "$REAL_SHA256SUM" "$@"
RACE_SHA256
chmod +x "$content_race_bin/sha256sum"

environment_race_artifact="$failure_state_home/codex-improve/executions/resume-environment-race"
clone_resume_artifact "$environment_race_artifact"
replacement_launcher="$test_root/replacement-launcher"
replacement_launcher_marker="$test_root/replacement-launcher-invoked"
printf '#!%s\n' "$(command -v bash)" >"$replacement_launcher"
cat >>"$replacement_launcher" <<'REPLACEMENT_LAUNCHER'
set -euo pipefail
: >"$REPLACEMENT_LAUNCHER_MARKER"
exec "$@"
REPLACEMENT_LAUNCHER
chmod +x "$replacement_launcher"
replacement_environment="$test_root/replacement-environment.json"
jq -cS -n --arg launcher "$replacement_launcher" '
  {
    version: 1,
    launcher: [$launcher],
    probes: [],
    probeOmissionReason: "Deterministic resume race replacement."
  }
' >"$replacement_environment"
environment_race_marker="$test_root/environment-race-mutated"

start_resume_case resume_environment_snapshot \
  "$failure_state_home" "$failure_home" complete
export RACE_SOURCE="$environment_race_artifact/environment.json"
export RACE_REPLACEMENT="$replacement_environment"
export RACE_MARKER="$environment_race_marker"
export REAL_CP="$real_cp"
export REAL_SHA256SUM="$real_sha256sum"
export REPLACEMENT_LAUNCHER_MARKER="$replacement_launcher_marker"
PATH="$content_race_bin:$PATH" run_runner --resume \
  "$failure_worktree" "$failure_tree" "$environment_race_artifact"
assert_transport_case 0 COMPLETE completed
[ -e "$environment_race_marker" ] || fail "resume environment race did not execute"
[ ! -e "$replacement_launcher_marker" ] ||
  fail "resume used replacement environment bytes"
fresh_environment_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
cmp -- "$environment_backup" "$fresh_environment_artifact/environment.json" ||
  fail "resume did not preserve authenticated environment bytes"
cmp -- "$replacement_environment" "$RACE_SOURCE" ||
  fail "resume environment race did not replace source authority"

prompt_race_artifact="$failure_state_home/codex-improve/executions/resume-prompt-race"
clone_resume_artifact "$prompt_race_artifact"
replacement_prompt="$test_root/replacement-prompt-body.txt"
printf '%s\n' PROMPT_RACE_REPLACEMENT >"$replacement_prompt"
prompt_race_marker="$test_root/prompt-race-mutated"

start_resume_case resume_prompt_snapshot \
  "$failure_state_home" "$failure_home" complete
export RACE_SOURCE="$prompt_race_artifact/prompt-body.txt"
export RACE_REPLACEMENT="$replacement_prompt"
export RACE_MARKER="$prompt_race_marker"
PATH="$content_race_bin:$PATH" run_runner --resume \
  "$failure_worktree" "$failure_tree" "$prompt_race_artifact"
assert_transport_case 0 COMPLETE completed
[ -e "$prompt_race_marker" ] || fail "resume prompt race did not execute"
! grep -F PROMPT_RACE_REPLACEMENT "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "resume prompt included replacement bytes"
fresh_prompt_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
cmp -- "$prompt_body_backup" "$fresh_prompt_artifact/prompt-body.txt" ||
  fail "resume did not preserve authenticated prompt bytes"
cmp -- "$replacement_prompt" "$RACE_SOURCE" ||
  fail "resume prompt race did not replace source authority"

race_artifact="$failure_state_home/codex-improve/executions/resume-race-fixture"
clone_resume_artifact "$race_artifact"
race_bin="$test_root/resume-race-bin"
race_marker="$test_root/resume-race-mutated"
mkdir -p "$race_bin"
printf '#!%s\n' "$(command -v bash)" >"$race_bin/git"
cat >>"$race_bin/git" <<'RACE_GIT'
set -euo pipefail
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "worktree" ] &&
  [ "${4:-}" = "list" ] && [ ! -e "$RACE_MARKER" ]; then
  jq '.protectedPaths = [".agents"]' "$RACE_MANIFEST" >"$RACE_MANIFEST.tmp"
  chmod 600 "$RACE_MANIFEST.tmp"
  mv -- "$RACE_MANIFEST.tmp" "$RACE_MANIFEST"
  : >"$RACE_MARKER"
fi
exec "$REAL_GIT" "$@"
RACE_GIT
chmod +x "$race_bin/git"

start_resume_case resume_manifest_snapshot "$failure_state_home" "$failure_home" complete
export RACE_MANIFEST="$race_artifact/resume-manifest.json"
export RACE_MARKER="$race_marker"
export REAL_GIT="$real_git"
PATH="$race_bin:$PATH" run_runner --resume \
  "$failure_worktree" "$failure_tree" "$race_artifact"
assert_transport_case 0 COMPLETE completed
[ -e "$race_marker" ] || fail "resume manifest race did not execute"
jq -e '.protectedPaths == [".agents"]' "$RACE_MANIFEST" >/dev/null ||
  fail "resume manifest race did not replace source authority"
assert_contract_14_invocation '[".codex"]' true

start_resume_case environment_resume "$failure_state_home" "$failure_home" complete
export FAKE_PROBE_MODE=pass
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 1 "resumed invoked marker"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed "resumed preflight status"
[ "$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)" != "$failure_artifact" ] ||
  fail "resume reused original artifact directory"
assert_eq "$(wc -l <"$FAKE_LAUNCHER_COUNT")" 1 "resume launcher invocation count"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "resume profile"
assert_contract_14_invocation '[".codex"]' true
grep -F "$(field "$output" IMPROVE_EXECUTION_ID)" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "resume prompt omitted fresh execution identity"

start_resume_case environment_resume_repeated "$failure_state_home" "$failure_home"
run_runner --resume "$failure_worktree" "$failure_tree" "$failure_artifact"
assert_eq "$status" 2 "repeated resume status"
assert_not_invoked environment_resume_repeated
assert_eq "$(wc -l <"$FAKE_LAUNCHER_COUNT")" 0 "repeated resume launcher count"

start_case environment_repeated_failure_seed complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" "$environment_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
repeat_worktree="$(field "$output" IMPROVE_WORKTREE)"
repeat_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
repeat_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
repeat_state_home="$XDG_STATE_HOME"
repeat_home="$HOME"
repeat_parent_hash="$(<"$repeat_artifact/resume-manifest.sha256")"

start_resume_case environment_repeated_failure "$repeat_state_home" "$repeat_home"
export FAKE_PROBE_MODE=fail
run_runner --resume "$repeat_worktree" "$repeat_tree" "$repeat_artifact"
assert_transport_case 0 STOPPED environment_preflight_failed
repeat_child_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
repeat_child_manifest="$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)"
jq -e --arg parent_hash "$repeat_parent_hash" '
  .resumeAttempt == 1
    and .parentManifestSha256 == $parent_hash
    and .originalExecutionId != .executionId
' "$repeat_child_manifest" >/dev/null || fail "repeated preflight manifest lineage"

start_resume_case environment_repeated_failure_blocked \
  "$repeat_state_home" "$repeat_home"
run_runner --resume "$repeat_worktree" "$repeat_tree" "$repeat_child_artifact"
assert_eq "$status" 2 "repeated preflight second resume status"
assert_preflight_not_invoked environment_repeated_failure_blocked

environment_dossier="$repo/plans/012 environment dossier.md"
write_environment_artifact "$environment_dossier" "$valid_environment_json"
start_resume_case environment_mutation \
  "$environment_state_home" "$environment_home" complete
export FAKE_PROBE_MODE=mutate
export FAKE_MUTATE_WORKTREE="$environment_worktree"
run_runner --environment-json "$valid_environment_json" --revise \
  "$environment_worktree" "$environment_tree" "$environment_dossier"
assert_transport_case 0 STOPPED environment_preflight_mutated_candidate
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 0 "mutation invoked marker"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" mutated "mutation status"
[ -z "$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)" ] ||
  fail "mutation produced a resume manifest"
assert_not_invoked environment_mutation

printf '%s\n' "dirty caller" >"$repo/dirty.txt"
export IMPROVE_EXECUTION_ID=ambient-caller-value
start_case initial complete
LC_ALL=C.UTF-8 run_runner "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
assert_execution_id_inherited
[ "$(<"$FAKE_EXECUTION_ID_LOG")" != ambient-caller-value ] ||
  fail "ambient execution identity was trusted"
assert_eq "$(<"$FAKE_LOCALE_LOG")" "set:C.UTF-8" "explicit caller locale"
assert_eq "$(field "$output" IMPROVE_MODE)" initial "initial mode"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "initial profile"
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 0 "initial raw Codex status"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 "normal initial timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 120000 "Standard token limit"
assert_eq "$(field "$output" IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED)" 0 "initial budget flag"
initial_worktree="$(field "$output" IMPROVE_WORKTREE)"
[ -d "$initial_worktree" ] || fail "initial worktree was not preserved"
[ ! -e "$initial_worktree/dirty.txt" ] || fail "dirty caller state entered initial worktree"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_HEAD)" \
  "$(git -C "$initial_worktree" rev-parse HEAD)" "initial candidate head"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_TREE)" \
  "$(git -C "$initial_worktree" rev-parse 'HEAD^{tree}')" "initial candidate tree"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_AVAILABLE)" 1 "initial candidate availability"
grep -F "starts from the caller's committed HEAD" "$errors" >/dev/null ||
  fail "initial dirty-caller warning is inaccurate"
assert_eq "$(grep -o TOP_SECRET_PLAN "$FAKE_PROMPT_LOG" | wc -l)" 1 "plan insertion count"
grep -Fx -- --strict-config "$FAKE_INVOCATION_LOG" >/dev/null || fail "strict config missing"
grep -Fx -- --ephemeral "$FAKE_INVOCATION_LOG" >/dev/null || fail "ephemeral mode missing"
grep -Fx -- --json "$FAKE_INVOCATION_LOG" >/dev/null || fail "JSONL mode missing"
grep -Fx -- --model "$FAKE_INVOCATION_LOG" >/dev/null || fail "model pin missing"
grep -Fx -- --sandbox "$FAKE_INVOCATION_LOG" >/dev/null || fail "sandbox pin missing"
assert_network_access "standard initial"
assert_role_invocation "standard initial" gpt-5.6-sol medium medium 120000 '[60000,30000,10000]'
grep -Fx -- memories "$FAKE_INVOCATION_LOG" >/dev/null || fail "memory disable missing"
grep -Fx -- goals "$FAKE_INVOCATION_LOG" >/dev/null || fail "goals disable missing"
grep -Fx -- multi_agent "$FAKE_INVOCATION_LOG" >/dev/null || fail "multi-agent disable missing"
if grep -Fx -- --ignore-user-config "$FAKE_INVOCATION_LOG" >/dev/null; then
  fail "user config was disabled"
fi
grep -Fx -- --output-last-message "$FAKE_INVOCATION_LOG" >/dev/null ||
  fail "final-message output missing"
grep -Fx -- --output-schema "$FAKE_INVOCATION_LOG" >/dev/null ||
  fail "output schema missing"
assert_eq "$(sed -n '/^--output-schema$/{n;p;q;}' "$FAKE_INVOCATION_LOG")" \
  "$executor_schema" "standard schema path"
grep -F -- "Do not load or reread the Improve skill" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "initial no-Improve/Ponytail boundary missing"
grep -F -- "A targeted reread is allowed after editing that" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "initial targeted-reread boundary missing"
grep -F -- "Return one JSON object matching the provided output schema." \
  "$FAKE_PROMPT_LOG" >/dev/null || fail "structured report contract missing"
jq -e '
  .mode == "initial"
  and .profile == "improve-executor"
  and .result == "COMPLETE"
  and .exit_reason == "completed"
  and .active_timeout_seconds == 5
  and .active_token_limit == 120000
  and .token_usage == {"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}
  and .usage_observed == true
  and .tool_event_count == 1
  and .command_execution_count == 1
  and .file_change_count == 0
  and .mcp_tool_call_count == 0
  and .web_search_count == 0
  and (.prompt_bytes | type) == "number"
  and (.execution_id | test("^[a-z0-9-]+$"))
  and .fuse_flags == {
    "absolute_timeout":false,
    "event_log_limit":false,
    "wrapper_signal":false,
    "rollout_budget_exhausted":false
  }
' "$metric" >/dev/null || fail "initial metric"
execution_id="$(field "$output" IMPROVE_EXECUTION_ID)"
case "$execution_id" in
  *[!a-z0-9-]*|'') fail "invalid execution identity: $execution_id" ;;
esac
assert_eq "$(jq -r '.execution_id' "$metric")" "$execution_id" "metric execution identity"
grep -F "Authoritative runtime metadata: IMPROVE_EXECUTION_ID=$execution_id" \
  "$FAKE_PROMPT_LOG" >/dev/null || fail "prompt execution identity"

start_case stopped stopped
unset LC_ALL
run_runner "plans/001 plan.md"
assert_transport_case 0 STOPPED completed
assert_eq "$(<"$FAKE_LOCALE_LOG")" unset "unset caller locale"
grep -Fx -- "STATUS: STOPPED" "$output" >/dev/null || fail "STOPPED report not printed"
grep -Fx -- "STOPPED BECAUSE: deterministic test stop" "$output" >/dev/null ||
  fail "STOPPED reason was not trimmed and rendered"

start_case structured_multiple_steps_notes structured_multiple_steps_notes
run_runner "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
structured_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
jq -e '
  (.steps | length) == 7
    and (.notes | length) == 3
    and .stoppedBecause == null
' "$structured_artifact/final.json" >/dev/null ||
  fail "structured_multiple_steps_notes raw artifact"
for prefix in STATUS STEPS "FILES CHANGED" NOTES; do
  assert_eq "$(grep -c "^$prefix:" "$structured_artifact/final.txt")" 1 \
    "structured_multiple_steps_notes $prefix prefix count"
done
assert_eq "$(wc -l <"$structured_artifact/final.txt")" 4 \
  "structured_multiple_steps_notes rendered line count"
grep -Fx -- \
  'STEPS: ["step 1","step 2","step 3","step 4","step 5","step 6","step 7"]' \
  "$structured_artifact/final.txt" >/dev/null ||
  fail "structured_multiple_steps_notes compact steps"
grep -Fx -- 'FILES CHANGED: ["one","two"]' \
  "$structured_artifact/final.txt" >/dev/null ||
  fail "structured_multiple_steps_notes compact files"
grep -Fx -- 'NOTES: ["note 1","note 2","note 3"]' \
  "$structured_artifact/final.txt" >/dev/null ||
  fail "structured_multiple_steps_notes compact notes"
! grep -q '^STOPPED BECAUSE:' "$structured_artifact/final.txt" ||
  fail "structured_multiple_steps_notes rendered stopped prefix"
assert_eq "$(field "$output" IMPROVE_EXEC_FINAL_OUTPUT)" \
  "$structured_artifact/final.txt" "compatible final output path"

start_case complete_unmerged_candidate complete_unmerged_candidate
run_runner "plans/001 plan.md"
assert_transport_case 1 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_CANDIDATE_AVAILABLE)" 0 \
  "post-run candidate availability"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_ERROR)" unmerged_index \
  "post-run candidate error"
[ -z "$(field "$output" IMPROVE_CANDIDATE_TREE)" ] ||
  fail "unavailable post-run candidate emitted a tree"
assert_no_candidate_indexes complete_unmerged_candidate

start_case deep deep
export FAKE_CODEX_MODE=complete
run_runner --deep "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep "deep profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 7 "deep initial timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 160000 "deep token limit"
assert_network_access "deep initial"
assert_role_invocation "deep initial" gpt-5.6-sol xhigh medium 160000 '[80000,40000,15000]'
assert_eq "$(sed -n '/^--output-schema$/{n;p;q;}' "$FAKE_INVOCATION_LOG")" \
  "$executor_schema" "deep schema path"

start_case spark complete
run_runner --spark "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark "Spark profile"
assert_eq "$(invocation_profile)" improve-executor-spark "Spark invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 "Spark initial timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 "Spark token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "Spark invocation count"
assert_network_access "Spark initial"
assert_role_invocation "Spark initial" gpt-5.3-codex-spark high medium 100000 '[50000,25000,10000]'
assert_eq "$(sed -n '/^--output-schema$/{n;p;q;}' "$FAKE_INVOCATION_LOG")" \
  "$executor_schema" "Spark schema path"
grep -F -- "The user explicitly requires every verification command in the plan." \
  "$FAKE_PROMPT_LOG" >/dev/null || fail "Spark initial verification requirement missing"

start_case spark_nonzero nonzero
run_runner --spark "plans/001 plan.md"
assert_transport_case 1 INCONCLUSIVE codex_exit_17
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark "failed Spark profile"
assert_eq "$(invocation_profile)" improve-executor-spark "failed Spark invoked profile"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "failed Spark invocation count"
spark_failure_worktree="$(field "$output" IMPROVE_WORKTREE)"
[ -d "$spark_failure_worktree" ] || fail "failed Spark worktree was not preserved"

transport_failure() {
  name="$1"
  fake_mode="$2"
  expected_reason="$3"
  start_case "$name" "$fake_mode"
  run_runner "plans/001 plan.md"
  assert_transport_case 1 INCONCLUSIVE "$expected_reason"
  preserved_worktree="$(field "$output" IMPROVE_WORKTREE)"
  [ -d "$preserved_worktree" ] || fail "$name worktree was not preserved"
}

transport_failure nonzero nonzero codex_exit_17
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 17 "nonzero raw Codex status"
transport_failure rollout_budget_exhausted rollout_budget_exhausted rollout_budget_exhausted
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 1 "budget raw Codex status"
assert_eq "$(field "$output" IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED)" 1 "budget flag"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "budget invocation count"
jq -e '.fuse_flags.rollout_budget_exhausted == true' "$metric" >/dev/null ||
  fail "budget metric fuse"
transport_failure rollout_budget_with_malformed_jsonl rollout_budget_with_malformed_jsonl codex_exit_1
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 1 "malformed budget raw Codex status"
assert_eq "$(field "$output" IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED)" 0 "malformed budget flag"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "malformed budget invocation count"
jq -e '.fuse_flags.rollout_budget_exhausted == false' "$metric" >/dev/null ||
  fail "malformed budget metric fuse"
transport_failure nested_rollout_budget_text nested_rollout_budget_text codex_exit_17
assert_eq "$(field "$output" IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED)" 0 "nested budget flag"
jq -e '.fuse_flags.rollout_budget_exhausted == false' "$metric" >/dev/null ||
  fail "nested budget text set metric fuse"
transport_failure exit_124 exit_124 codex_exit_124
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 124 "natural 124 raw Codex status"
jq -e '.fuse_flags.absolute_timeout == false' "$metric" >/dev/null ||
  fail "natural 124 set timeout fuse"
transport_failure exit_137 exit_137 codex_exit_137
assert_eq "$(field "$output" IMPROVE_EXEC_EXIT)" 137 "natural 137 raw Codex status"
jq -e '.fuse_flags.absolute_timeout == false' "$metric" >/dev/null ||
  fail "natural 137 set timeout fuse"
transport_failure malformed_jsonl malformed_jsonl invalid_event_log
transport_failure malformed_final malformed_final invalid_final_output
assert_invalid_report_preserved
transport_failure complete_with_stopped_reason complete_with_stopped_reason \
  invalid_final_output
assert_invalid_report_preserved
transport_failure stopped_with_none stopped_with_none \
  invalid_final_output
assert_invalid_report_preserved
transport_failure stopped_with_none_titlecase stopped_with_none_titlecase \
  invalid_final_output
assert_invalid_report_preserved
transport_failure stopped_with_none_uppercase stopped_with_none_uppercase \
  invalid_final_output
assert_invalid_report_preserved
transport_failure stopped_with_none_mixedcase_whitespace \
  stopped_with_none_mixedcase_whitespace invalid_final_output
assert_invalid_report_preserved
transport_failure missing_final missing_final empty_final_output
transport_failure oversize_final oversize_final final_output_limit

contract_15_transport_case() {
  local name="$1"
  local fake_mode="$2"
  local expected_reason="$3"
  local expected_eligible="$4"
  start_case "$name" "$fake_mode"
  run_runner --environment-json "$valid_environment_json" "$contract_15_plan"
  assert_transport_case 1 INCONCLUSIVE "$expected_reason"
  assert_closeout_eligible "$expected_eligible"
}

contract_15_transport_case closeout_budget rollout_budget_exhausted \
  rollout_budget_exhausted 1
start_case closeout_absolute_with_event timeout_with_event
quiet_timeout_bin="$case_dir/quiet-timeout-bin"
mkdir -p "$quiet_timeout_bin"
printf '#!%s\n' "$(command -v bash)" >"$quiet_timeout_bin/timeout"
cat >>"$quiet_timeout_bin/timeout" <<'QUIET_TIMEOUT'
set -euo pipefail
args=()
for arg in "$@"; do
  [ "$arg" = --verbose ] || args+=("$arg")
done
exec "$REAL_TIMEOUT" "${args[@]}"
QUIET_TIMEOUT
chmod +x "$quiet_timeout_bin/timeout"
REAL_TIMEOUT="$real_timeout" PATH="$quiet_timeout_bin:$PATH" \
  run_runner --environment-json "$valid_environment_json" "$contract_15_plan"
assert_transport_case 1 INCONCLUSIVE absolute_timeout
assert_closeout_eligible 1
contract_15_transport_case closeout_invalid_final malformed_final \
  invalid_final_output 1
contract_15_transport_case closeout_empty_final missing_final \
  empty_final_output 1
contract_15_transport_case closeout_final_limit oversize_final \
  final_output_limit 1
contract_15_transport_case closeout_forged_timeout_marker \
  forged_timeout_marker codex_exit_124 0
contract_15_transport_case closeout_disallowed_reason nonzero codex_exit_17 0
contract_15_transport_case closeout_invalid_event_log malformed_jsonl \
  invalid_event_log 0
contract_15_transport_case closeout_candidate_unavailable \
  malformed_final_unmerged_candidate invalid_final_output 0

start_case closeout_launcher_forged_timeout_marker nonzero
export FAKE_LAUNCHER_FORGE_TIMEOUT_MARKER=1
run_runner --environment-json "$valid_environment_json" "$contract_15_plan"
assert_transport_case 1 INCONCLUSIVE codex_exit_17
assert_closeout_eligible 0
launcher_forgery_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
grep -Fx 'timeout: sending signal INT to command launcher-fixture' \
  "$launcher_forgery_artifact/stderr.log" >/dev/null ||
  fail "launcher timeout forgery missing from diagnostic log"
if grep -F 'timeout: sending signal INT to command' \
  "$launcher_forgery_artifact/timeout.log" >/dev/null; then
  fail "launcher timeout forgery entered trusted timeout log"
fi

invalid_report_case() {
  invalid_name="$1"
  transport_failure "$invalid_name" "$invalid_name" invalid_final_output
  assert_invalid_report_preserved
}

invalid_report_case invalid_status
invalid_report_case multiple_json_values
invalid_report_case missing_report_field
invalid_report_case extra_report_field
invalid_report_case empty_steps
invalid_report_case wrong_array_item_type
invalid_report_case blank_array_item
invalid_report_case stopped_with_null_reason
invalid_report_case stopped_with_blank_reason
transport_failure timeout timeout absolute_timeout
jq -e '.fuse_flags.absolute_timeout == true' "$metric" >/dev/null ||
  fail "deadline omitted timeout fuse"
timeout_log="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)/timeout.log"
grep -Fx 'codex-improve-exec: absolute timeout fired' "$timeout_log" >/dev/null ||
  fail "deadline omitted deterministic private timeout marker"
transport_failure oversize_event oversize_event event_log_limit
assert_eq "$(field "$output" IMPROVE_EXEC_EVENT_LOG_LIMIT_HIT)" 1 "event fuse field"

start_case descendant descendant
run_runner "plans/001 plan.md"
assert_transport_case 1 INCONCLUSIVE absolute_timeout
descendant_worktree="$(field "$output" IMPROVE_WORKTREE)"
[ -d "$descendant_worktree" ] || fail "descendant timeout removed worktree"
descendant_pid="$(<"$FAKE_CHILD_PID_FILE")"
for _ in $(seq 1 20); do
  kill -0 "$descendant_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$descendant_pid" 2>/dev/null; then
  kill -KILL "$descendant_pid" 2>/dev/null || true
  fail "timeout descendant survived"
fi

start_case quiet quiet
run_runner "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
jq -e '.quiet_interval_observed == true and .max_event_gap_seconds >= 1' "$metric" >/dev/null ||
  fail "quiet interval metric"
if grep -F 'no new JSONL event' "$errors" >/dev/null; then
  fail "quiet observation printed a second progress form"
fi
heartbeat_count="$(sed -n '/^codex-improve-exec: phase=.* elapsed=/p' "$errors" | wc -l)"
unique_heartbeat_count="$(
  sed -n 's/^codex-improve-exec: phase=.* elapsed=\([0-9][0-9]*\)s .*/\1/p' "$errors" |
    sort -u |
    wc -l
)"
assert_eq "$heartbeat_count" "$unique_heartbeat_count" "quiet heartbeat cadence"

start_case unterminated_final unterminated_final
run_runner "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed

start_case runtime_closure complete
copy_runner
runtime_bin="$case_dir/runtime-bin"
mkdir -p "$runtime_bin"
for command in \
  bash basename cat chmod codex cp date git id jq mkdir mktemp mv realpath rm \
  sed sha256sum sleep stat tail timeout tr wc; do
  ln -s "$(command -v "$command")" "$runtime_bin/$command"
done
output="$case_dir/output"
errors="$case_dir/errors"
set +e
(
  cd "$repo"
  PATH="$runtime_bin" "$runtime_bin/bash" "$runner" "plans/001 plan.md"
) >"$output" 2>"$errors"
status="$?"
set -e
assert_transport_case 0 COMPLETE completed

start_case signal signal
copy_runner
output="$case_dir/output"
errors="$case_dir/errors"
(
  cd "$repo"
  exec bash "$runner" "plans/001 plan.md"
) >"$output" 2>"$errors" &
wrapper_pid="$!"
for _ in $(seq 1 50); do
  [ -s "$FAKE_CHILD_PID_FILE" ] && break
  sleep 0.1
done
[ -s "$FAKE_CHILD_PID_FILE" ] || fail "signal case did not start descendant"
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
status="$?"
set -e
assert_transport_case 1 INCONCLUSIVE wrapper_signal_TERM
signal_worktree="$(field "$output" IMPROVE_WORKTREE)"
[ -d "$signal_worktree" ] || fail "signal removed worktree"
signal_child_pid="$(<"$FAKE_CHILD_PID_FILE")"
for _ in $(seq 1 20); do
  kill -0 "$signal_child_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$signal_child_pid" 2>/dev/null; then
  kill -KILL "$signal_child_pid" 2>/dev/null || true
  fail "signal-resistant descendant survived cancellation"
fi

start_case home_fallback complete
unset XDG_STATE_HOME
run_runner "plans/001 plan.md"
fallback_worktree="$(field "$output" IMPROVE_WORKTREE)"
case "$fallback_worktree" in
  "$HOME/.local/state/codex-improve/worktrees/"*) ;;
  *) fail "HOME state fallback was not used: $fallback_worktree" ;;
esac

start_case second_user complete
run_runner "plans/001 plan.md"
second_worktree="$(field "$output" IMPROVE_WORKTREE)"
case "$second_worktree" in
  "$XDG_STATE_HOME/codex-improve/worktrees/"*) ;;
  *) fail "second user XDG state was not used: $second_worktree" ;;
esac
case "$second_worktree" in
  "$fallback_worktree"|"$case_root/home_fallback/"*) fail "users shared state" ;;
esac

revision_worktree="$test_root/revision worktree"
git -C "$repo" worktree add -q -b codex/improve-revision-test "$revision_worktree" HEAD
printf '%s\n' "preserve this diff" >>"$revision_worktree/tracked.txt"
dossier="$test_root/revision dossier.md"
{
  printf '%s\n' "TOP_SECRET_DOSSIER /private/repository/path"
  printf '%s\n' "Original execution profile: improve-executor-deep"
  printf '%s\n' "Selected revision lane: supplied explicitly by the caller"
  printf '%s\n' "Routing evidence: the bounded revision was classified independently"
} >"$dossier"
revision_status_before="$(git -C "$revision_worktree" status --short)"
revision_tree="$(candidate_tree "$revision_worktree")"
worktrees_before="$(git -C "$repo" worktree list --porcelain)"

start_case stale_revision complete
run_runner --revise "$revision_worktree" "$(git -C "$revision_worktree" rev-parse 'HEAD^{tree}')" "$dossier"
assert_eq "$status" 2 "stale revision status"
assert_not_invoked stale_revision

start_case abbreviated_revision complete
run_runner --revise "$revision_worktree" "${revision_tree:0:12}" "$dossier"
assert_eq "$status" 2 "abbreviated revision status"
assert_not_invoked abbreviated_revision

start_case structured_validation_command_failure complete
copy_runner
failure_bin="$case_dir/failure-bin"
mkdir -p "$failure_bin"
real_jq="$(command -v jq)"
{
  printf '#!%s\n' "$(command -v bash)"
  # shellcheck disable=SC2016 # Literal fake-jq script fixture.
  printf '%s\n' 'for argument in "$@"; do'
  # shellcheck disable=SC2016 # Literal fake-jq script fixture.
  printf '%s\n' '  case "$argument" in *"def nonblank"*) exit 9 ;; esac'
  printf '%s\n' 'done'
  printf 'exec %q "$@"\n' "$real_jq"
} >"$failure_bin/jq"
chmod +x "$failure_bin/jq"
output="$case_dir/output"
errors="$case_dir/errors"
set +e
(
  cd "$repo"
  PATH="$failure_bin:$PATH" bash "$runner" --revise \
    "$revision_worktree" "$revision_tree" "$dossier"
) >"$output" 2>"$errors"
status="$?"
set -e
assert_transport_case 1 INCONCLUSIVE invalid_final_output
assert_invalid_report_preserved

start_case revision complete
run_runner --revise "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_execution_id_inherited
assert_eq "$(field "$output" IMPROVE_MODE)" revision "revision mode"
assert_eq "$(field "$output" IMPROVE_BRANCH)" codex/improve-revision-test "revision branch"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "revision profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 4 "normal revision timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 120000 "Standard revision token limit"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "revision diff preservation"
assert_eq "$(git -C "$repo" worktree list --porcelain)" "$worktrees_before" "revision worktree reuse"
assert_eq "$(grep -o TOP_SECRET_DOSSIER "$FAKE_PROMPT_LOG" | wc -l)" 1 "dossier insertion count"
assert_network_access "standard revision"
grep -F -- "Do not load or reread the" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "revision recon prohibition missing"
grep -F -- "A targeted reread is allowed after editing that" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "revision targeted-reread boundary missing"

start_case spark_revision complete
run_runner --spark --revise "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark "Spark revision profile"
assert_eq "$(invocation_profile)" improve-executor-spark "Spark revision invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 4 "Spark revision timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 "Spark revision token limit"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "Spark revision diff preservation"
assert_eq "$(git -C "$repo" worktree list --porcelain)" "$worktrees_before" "Spark revision worktree reuse"
grep -F -- "The user explicitly requires every verification command named by the dossier." \
  "$FAKE_PROMPT_LOG" >/dev/null || fail "Spark revision verification requirement missing"

start_case deep_revision complete
run_runner --deep --revise "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep "deep revision profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 6 "deep revision timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 160000 "deep revision token limit"

contract_state_home="$test_root/contract-state"
contract_home="$test_root/contract-home"
contract_worktree_root="$contract_state_home/codex-improve/worktrees"
contract_worktree="$contract_worktree_root/revision-test"
mkdir -p "$contract_worktree_root" "$contract_home"
chmod 700 "$contract_state_home/codex-improve" "$contract_worktree_root"
git -C "$repo" worktree add -q -b codex/improve-contract-revision-test \
  "$contract_worktree" HEAD
chmod 700 "$contract_worktree"
printf '%s\n' "preserve this contracted diff" >>"$contract_worktree/tracked.txt"
contract_tree="$(candidate_tree "$contract_worktree")"

start_contract_case() {
  start_case "$@"
  export XDG_STATE_HOME="$contract_state_home"
  export HOME="$contract_home"
}

ln -s .git "$contract_worktree/.agents"
unsafe_agents_tree="$(candidate_tree "$contract_worktree")"
git_pointer_hash="$(sha256sum "$contract_worktree/.git" | sed 's/[[:space:]].*$//')"
start_contract_case protected_root_symlink complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --revise \
  "$contract_worktree" "$unsafe_agents_tree" "$environment_dossier"
assert_eq "$status" 2 "granted-root symlink status"
assert_preflight_not_invoked protected_root_symlink
grep -Fx 'codex-improve-exec: granted protected path must be absent or a physical directory: .agents' \
  "$errors" >/dev/null || fail "granted-root symlink rejection reason"
assert_eq "$(sha256sum "$contract_worktree/.git" | sed 's/[[:space:]].*$//')" \
  "$git_pointer_hash" "granted-root symlink preserved .git"
[ ! -e "$contract_worktree/.git/improve-symlink-test" ] ||
  fail "granted-root symlink changed .git"
[ ! -e "$contract_state_home/codex-improve/executions" ] ||
  fail "granted-root symlink initialized execution artifacts"
rm -- "$contract_worktree/.agents"

printf '%s\n' unsafe-root >"$contract_worktree/.codex"
unsafe_codex_tree="$(candidate_tree "$contract_worktree")"
start_contract_case protected_root_file complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --revise \
  "$contract_worktree" "$unsafe_codex_tree" "$environment_dossier"
assert_eq "$status" 2 "granted-root file status"
assert_preflight_not_invoked protected_root_file
grep -Fx 'codex-improve-exec: granted protected path must be absent or a physical directory: .codex' \
  "$errors" >/dev/null || fail "granted-root file rejection reason"
rm -- "$contract_worktree/.codex"

start_contract_case protected_root_missing complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --revise \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_contract_14_invocation '[".agents"]' true

mkdir "$contract_worktree/.agents"
start_contract_case protected_root_directory complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --revise \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_contract_14_invocation '[".agents"]' true
rmdir "$contract_worktree/.agents"

contract_exclude="$(git -C "$contract_worktree" rev-parse --git-path info/exclude)"
contract_exclude_backup="$test_root/contract-exclude.backup"
cp -- "$contract_exclude" "$contract_exclude_backup"
printf '%s\n' '/.agents' >>"$contract_exclude"
contract_git_directory="$(
  git -C "$contract_worktree" rev-parse --path-format=absolute --git-common-dir
)"
contract_git_directory="$(realpath -- "$contract_git_directory")"
start_contract_case protected_root_probe_race complete
export FAKE_PROBE_MODE=grant_root_symlink
export FAKE_MUTATE_WORKTREE="$contract_worktree"
export FAKE_MUTATE_TARGET="$contract_git_directory"
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --revise \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 STOPPED environment_preflight_mutated_candidate
assert_eq "$(field "$output" IMPROVE_EXEC_INVOKED)" 0 \
  "granted-root probe race invoked marker"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" mutated \
  "granted-root probe race preflight status"
assert_eq "$(candidate_tree "$contract_worktree")" "$contract_tree" \
  "ignored granted-root symlink candidate identity"
git -C "$contract_worktree" check-ignore -q .agents ||
  fail "probe-created granted-root symlink was not ignored"
[ -L "$contract_worktree/.agents" ] ||
  fail "environment probe did not create granted-root symlink"
assert_eq "$(sha256sum "$contract_worktree/.git" | sed 's/[[:space:]].*$//')" \
  "$git_pointer_hash" "granted-root probe race preserved .git"
[ ! -e "$contract_git_directory/improve-symlink-test" ] ||
  fail "granted-root probe race changed .git"
[ -z "$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)" ] ||
  fail "granted-root probe race produced a resume manifest"
assert_not_invoked protected_root_probe_race
assert_eq "$(wc -l <"$FAKE_LAUNCHER_COUNT")" 1 \
  "granted-root probe race launcher count"
protected_root_race_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
grep -Fx 'codex-improve-exec: granted protected path must be absent or a physical directory: .agents' \
  "$protected_root_race_artifact/preflight.log" >/dev/null ||
  fail "granted-root probe race rejection reason"
rm -- "$contract_worktree/.agents"
cp -- "$contract_exclude_backup" "$contract_exclude"

start_case environment_revision_outside_xdg complete
run_runner --environment-json "$valid_environment_json" --revise \
  "$revision_worktree" "$revision_tree" "$environment_dossier"
assert_eq "$status" 2 "outside-XDG contracted revision status"
assert_preflight_not_invoked environment_revision_outside_xdg

start_contract_case environment_revision complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --revise \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor \
  "environment revision profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment revision preflight status"
assert_contract_14_invocation '[".codex"]' true

start_contract_case environment_spark_revision complete
run_runner --environment-json "$valid_environment_json" --spark --revise \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "environment Spark revision profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment Spark revision preflight status"
assert_contract_14_invocation '[]' true

start_case environment_deep_revision_failure complete
mkdir -p "$XDG_STATE_HOME/codex-improve/worktrees"
chmod 700 "$XDG_STATE_HOME/codex-improve"
chmod 755 "$XDG_STATE_HOME/codex-improve/worktrees"
deep_revision_worktree="$XDG_STATE_HOME/codex-improve/worktrees/revision-test"
git -C "$repo" worktree add -q -b codex/improve-resume-revision-test \
  "$deep_revision_worktree" HEAD
chmod 755 "$deep_revision_worktree"
printf '%s\n' "preserve this resumable diff" >>"$deep_revision_worktree/tracked.txt"
deep_revision_tree="$(candidate_tree "$deep_revision_worktree")"
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --allow-protected-path .codex --deep --revise \
  "$deep_revision_worktree" "$deep_revision_tree" "$environment_dossier"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(stat -c '%a' "$XDG_STATE_HOME/codex-improve/worktrees")" 700 \
  "legacy revision worktree root was made private"
assert_eq "$(stat -c '%a' "$deep_revision_worktree")" 700 \
  "legacy revision worktree was made private"
deep_revision_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
deep_revision_state_home="$XDG_STATE_HOME"
deep_revision_home="$HOME"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "failed environment deep revision profile"
jq -e '.protectedPaths == [".agents", ".codex"]' \
  "$deep_revision_artifact/resume-manifest.json" >/dev/null ||
  fail "deep revision manifest protected paths"

start_resume_case environment_deep_revision_resume \
  "$deep_revision_state_home" "$deep_revision_home" complete
run_runner --resume "$deep_revision_worktree" "$deep_revision_tree" \
  "$deep_revision_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_MODE)" revision \
  "resumed environment revision mode"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "resumed environment deep revision profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 6 \
  "resumed environment deep revision timeout"
assert_contract_14_invocation '[".agents",".codex"]' true
worktrees_before="$(git -C "$repo" worktree list --porcelain)"

start_case recovery complete
run_runner --recover "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_execution_id_inherited
assert_eq "$(field "$output" IMPROVE_MODE)" recovery "recovery mode"
assert_eq "$(field "$output" IMPROVE_BRANCH)" codex/improve-revision-test "recovery branch"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "recovery profile"
assert_eq "$(invocation_profile)" improve-executor "recovery invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 4 "normal recovery timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 120000 "Standard recovery token limit"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "recovery diff preservation"
assert_eq "$(git -C "$repo" worktree list --porcelain)" "$worktrees_before" "recovery worktree reuse"
assert_eq "$(grep -o TOP_SECRET_DOSSIER "$FAKE_PROMPT_LOG" | wc -l)" 1 "recovery dossier insertion count"
assert_network_access "standard recovery"
grep -F -- "completing exactly one bounded recovery slice after an inconclusive" \
  "$FAKE_PROMPT_LOG" >/dev/null || fail "recovery one-slice contract missing"
grep -F -- "Preserve the existing diff and" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "recovery diff preservation contract missing"
grep -F -- "only the dossier's permitted paths" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "recovery path boundary missing"
grep -F -- "COMPLETE means" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "recovery completion boundary missing"
grep -F -- "Never decompose or recover this slice." "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "recursive recovery prohibition missing"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "recovery invocation count"
jq -e '
  .mode == "recovery"
  and .profile == "improve-executor"
  and .result == "COMPLETE"
  and .exit_reason == "completed"
  and .active_timeout_seconds == 4
  and .active_token_limit == 120000
  and .token_usage == {"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}
  and .tool_event_count == 1
' "$metric" >/dev/null || fail "recovery metric"

start_case spark_recovery complete
run_runner --spark --recover "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_MODE)" recovery "Spark recovery mode"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark "Spark recovery profile"
assert_eq "$(invocation_profile)" improve-executor-spark "Spark recovery invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 4 "Spark recovery timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 "Spark recovery token limit"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "Spark recovery diff preservation"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "Spark recovery invocation count"

start_case deep_recovery complete
run_runner --deep --recover "$revision_worktree" "$revision_tree" "$dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_MODE)" recovery "deep recovery mode"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep "deep recovery profile"
assert_eq "$(invocation_profile)" improve-executor-deep "deep recovery invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 6 "deep recovery timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 160000 "deep recovery token limit"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "deep recovery diff preservation"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "deep recovery invocation count"

chmod 755 "$contract_worktree_root" "$contract_worktree"
start_contract_case environment_recovery_upgrade_failure complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" --recover \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(stat -c '%a' "$contract_worktree_root")" 700 \
  "legacy recovery worktree root was made private"
assert_eq "$(stat -c '%a' "$contract_worktree")" 700 \
  "legacy recovery worktree was made private"
recovery_upgrade_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"

start_resume_case environment_recovery_upgrade_resume \
  "$contract_state_home" "$contract_home" complete
run_runner --resume "$contract_worktree" "$contract_tree" \
  "$recovery_upgrade_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_MODE)" recovery \
  "resumed environment recovery mode"
assert_contract_14_invocation '[]' true

start_contract_case environment_recovery complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --recover \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor \
  "environment recovery profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment recovery preflight status"
assert_contract_14_invocation '[".agents"]' true

start_contract_case environment_spark_recovery complete
run_runner --environment-json "$valid_environment_json" --spark --recover \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "environment Spark recovery profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment Spark recovery preflight status"
assert_contract_14_invocation '[]' true

start_contract_case environment_deep_recovery complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --deep --recover \
  "$contract_worktree" "$contract_tree" "$environment_dossier"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "environment deep recovery profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment deep recovery preflight status"
assert_contract_14_invocation '[".codex"]' true

recovery_transport_case() {
  name="$1"
  fake_mode="$2"
  expected_status="$3"
  expected_result="$4"
  expected_reason="$5"
  start_case "$name" "$fake_mode"
  run_runner --recover "$revision_worktree" "$revision_tree" "$dossier"
  assert_transport_case "$expected_status" "$expected_result" "$expected_reason"
  assert_eq "$(field "$output" IMPROVE_MODE)" recovery "$name mode"
  assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "$name invocation count"
  assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "$name diff preservation"
}

recovery_transport_case recovery_stopped stopped 0 STOPPED completed
recovery_transport_case recovery_nonzero nonzero 1 INCONCLUSIVE codex_exit_17
recovery_transport_case recovery_budget rollout_budget_exhausted 1 INCONCLUSIVE rollout_budget_exhausted
recovery_transport_case recovery_timeout timeout 1 INCONCLUSIVE absolute_timeout
recovery_transport_case recovery_malformed malformed_jsonl 1 INCONCLUSIVE invalid_event_log

start_case recovery_signal signal
copy_runner
output="$case_dir/output"
errors="$case_dir/errors"
(
  cd "$repo"
  exec bash "$runner" --recover "$revision_worktree" "$revision_tree" "$dossier"
) >"$output" 2>"$errors" &
wrapper_pid="$!"
for _ in $(seq 1 50); do
  [ -s "$FAKE_CHILD_PID_FILE" ] && break
  sleep 0.1
done
[ -s "$FAKE_CHILD_PID_FILE" ] || fail "recovery signal case did not start descendant"
kill -TERM "$wrapper_pid"
set +e
wait "$wrapper_pid"
status="$?"
set -e
assert_transport_case 1 INCONCLUSIVE wrapper_signal_TERM
assert_eq "$(field "$output" IMPROVE_MODE)" recovery "recovery signal mode"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "recovery signal invocation count"
assert_eq "$(git -C "$revision_worktree" status --short)" "$revision_status_before" "recovery signal diff preservation"
recovery_signal_child_pid="$(<"$FAKE_CHILD_PID_FILE")"
for _ in $(seq 1 20); do
  kill -0 "$recovery_signal_child_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$recovery_signal_child_pid" 2>/dev/null; then
  kill -KILL "$recovery_signal_child_pid" 2>/dev/null || true
  fail "recovery signal-resistant descendant survived cancellation"
fi

candidate_worktree="$test_root/candidate worktree"
git -C "$repo" worktree add -q -b codex/improve-candidate-test "$candidate_worktree" HEAD
printf '%s\n' staged >>"$candidate_worktree/tracked.txt"
git -C "$candidate_worktree" add tracked.txt
printf '%s\n' unstaged >>"$candidate_worktree/tracked.txt"
real_index="$(git -C "$candidate_worktree" rev-parse --path-format=absolute --git-path index)"
index_hash_before="$(sha256sum "$real_index")"
cached_before="$(git -C "$candidate_worktree" diff --cached)"

start_case candidate_base
run_runner --candidate "$candidate_worktree"
assert_eq "$status" 0 "candidate status"
assert_not_invoked candidate_base
candidate_base_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_HEAD)" \
  "$(git -C "$candidate_worktree" rev-parse HEAD)" "candidate head"
assert_eq "$(sha256sum "$real_index")" "$index_hash_before" "candidate index bytes"
assert_eq "$(git -C "$candidate_worktree" diff --cached)" "$cached_before" "candidate cached diff"
assert_no_candidate_indexes candidate_base

printf '%s\n' untracked >"$candidate_worktree/untracked.txt"
start_case candidate_untracked
run_runner --candidate "$candidate_worktree"
candidate_untracked_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
[ "$candidate_untracked_tree" != "$candidate_base_tree" ] ||
  fail "untracked content did not alter candidate tree"
assert_eq "$(sha256sum "$real_index")" "$index_hash_before" "untracked candidate index bytes"
assert_no_candidate_indexes candidate_untracked

printf '%s\n' ignored >"$candidate_worktree/ignored.tmp"
start_case candidate_ignored
run_runner --candidate "$candidate_worktree"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_TREE)" \
  "$candidate_untracked_tree" "ignored untracked exclusion"
assert_no_candidate_indexes candidate_ignored

chmod +x "$candidate_worktree/tracked.txt"
start_case candidate_mode
run_runner --candidate "$candidate_worktree"
candidate_mode_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
[ "$candidate_mode_tree" != "$candidate_untracked_tree" ] ||
  fail "executable-bit change did not alter candidate tree"
assert_eq "$(sha256sum "$real_index")" "$index_hash_before" "mode candidate index bytes"
assert_no_candidate_indexes candidate_mode

rm "$candidate_worktree/tracked.txt"
start_case candidate_deletion
run_runner --candidate "$candidate_worktree"
candidate_deletion_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
[ "$candidate_deletion_tree" != "$candidate_mode_tree" ] ||
  fail "tracked deletion did not alter candidate tree"
assert_no_candidate_indexes candidate_deletion

ln -s untracked.txt "$candidate_worktree/symlink.txt"
start_case candidate_symlink
run_runner --candidate "$candidate_worktree"
[ "$(field "$output" IMPROVE_CANDIDATE_TREE)" != "$candidate_deletion_tree" ] ||
  fail "symlink state did not alter candidate tree"
assert_no_candidate_indexes candidate_symlink

unmerged_worktree="$test_root/unmerged worktree"
git -C "$repo" worktree add -q -b codex/improve-unmerged-test "$unmerged_worktree" HEAD
blob_one="$(printf one | git -C "$unmerged_worktree" hash-object -w --stdin)"
blob_two="$(printf two | git -C "$unmerged_worktree" hash-object -w --stdin)"
printf '100644 %s 1\tconflict.txt\n100644 %s 2\tconflict.txt\n' "$blob_one" "$blob_two" |
  git -C "$unmerged_worktree" update-index --index-info
start_case unmerged_candidate
run_runner --candidate "$unmerged_worktree"
assert_eq "$status" 2 "unmerged candidate status"
assert_not_invoked unmerged_candidate

hook_worktree="$test_root/hook worktree"
git -C "$repo" worktree add -q -b codex/improve-hook-test "$hook_worktree" HEAD
printf '%s\n' hook-change >>"$hook_worktree/tracked.txt"
printf '%s\n' hook-untracked >"$hook_worktree/hook-untracked.txt"
hook_tree="$(candidate_tree "$hook_worktree")"
hook_head_before="$(git -C "$hook_worktree" rev-parse HEAD)"
hooks_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks)"
printf '#!%s\nexit 23\n' "$(command -v bash)" >"$hooks_dir/pre-commit"
chmod +x "$hooks_dir/pre-commit"
start_case checkpoint_hook_failure
run_runner --checkpoint "$hook_worktree" "$hook_tree" "test: blocked checkpoint"
assert_eq "$status" 1 "failed checkpoint hook status"
assert_not_invoked checkpoint_hook_failure
assert_eq "$(git -C "$hook_worktree" rev-parse HEAD)" "$hook_head_before" "failed hook head"
assert_eq "$(git -C "$hook_worktree" rev-parse refs/heads/codex/improve-hook-test)" \
  "$hook_head_before" "failed hook branch"
assert_eq "$(git -C "$hook_worktree" write-tree)" "$hook_tree" "failed hook staged tree"
[ -e "$hook_worktree/hook-untracked.txt" ] || fail "failed hook cleaned untracked evidence"
[ -z "$(git -C "$repo" for-each-ref refs/codex-improve/checkpoints)" ] ||
  fail "failed hook left an internal checkpoint ref"

cat >"$hooks_dir/pre-commit" <<EOF
#!$(command -v bash)
printf '%s\n' hook-staged >hook-evidence.txt
git add hook-evidence.txt
EOF
chmod +x "$hooks_dir/pre-commit"
start_case checkpoint_hook_mutation
run_runner --checkpoint "$hook_worktree" "$hook_tree" "test: mutated checkpoint"
assert_eq "$status" 1 "mutating checkpoint hook status"
assert_not_invoked checkpoint_hook_mutation
assert_eq "$(git -C "$hook_worktree" rev-parse HEAD)" "$hook_head_before" "mutating hook head"
assert_eq "$(git -C "$hook_worktree" rev-parse refs/heads/codex/improve-hook-test)" \
  "$hook_head_before" "mutating hook branch"
assert_eq "$(git -C "$hook_worktree" status --short hook-evidence.txt)" \
  "A  hook-evidence.txt" "mutating hook evidence"
[ -z "$(git -C "$repo" for-each-ref refs/codex-improve/checkpoints)" ] ||
  fail "mutating hook left an internal checkpoint ref"
rm "$hooks_dir/pre-commit"

start_case checkpoint complete
run_runner --checkpoint "$revision_worktree" "$revision_tree" "test: improve checkpoint"
assert_eq "$status" 0 "checkpoint status"
assert_not_invoked checkpoint
checkpoint="$(field "$output" IMPROVE_CHECKPOINT)"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_HEAD)" "$checkpoint" "checkpoint candidate head"
assert_eq "$(field "$output" IMPROVE_CANDIDATE_TREE)" "$revision_tree" "checkpoint candidate tree"
assert_eq "$(git -C "$revision_worktree" rev-parse 'HEAD^{tree}')" "$revision_tree" "checkpoint commit tree"
[ -z "$(git -C "$repo" for-each-ref refs/remotes)" ] || fail "checkpoint created remote refs"

start_case next complete
run_runner --next "$checkpoint" "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
assert_execution_id_inherited
next_worktree="$(field "$output" IMPROVE_WORKTREE)"
assert_eq "$(git -C "$next_worktree" rev-parse HEAD)" "$checkpoint" "next worktree base"
assert_eq "$(field "$output" IMPROVE_BASE)" "$checkpoint" "next reported base"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" "next predecessor"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$repo" rev-parse main)" "caller branch unchanged"
[ ! -e "$next_worktree/dirty.txt" ] || fail "dirty caller content entered next worktree"
grep -F "$checkpoint" "$FAKE_PROMPT_LOG" >/dev/null || fail "next prompt omits predecessor"
grep -F "starts from explicit predecessor checkpoint $checkpoint" "$errors" >/dev/null ||
  fail "next dirty-caller warning is inaccurate"
assert_eq "$(field "$output" IMPROVE_MODE)" initial "standard next mode"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "standard next profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 \
  "standard next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 120000 \
  "standard next token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "standard next invocation count"
assert_network_access "standard next"

start_case contract_15_next complete
run_runner --environment-json "$valid_environment_json" --next \
  "$checkpoint" "$contract_15_plan"
assert_transport_case 0 COMPLETE completed
assert_closeout_eligible 0
contract_15_next_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
cmp "$contract_15_plan" "$contract_15_next_artifact/plan.md" ||
  fail ".15 next plan snapshot changed input bytes"
assert_private "$contract_15_next_artifact/plan.md"
assert_eq "$(field "$output" IMPROVE_PLAN_SHA256)" \
  "$(sha256sum "$contract_15_plan" | sed 's/[[:space:]].*$//')" \
  ".15 next plan SHA-256"

start_case spark_next complete
run_runner --spark --next "$checkpoint" "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
spark_next_worktree="$(field "$output" IMPROVE_WORKTREE)"
assert_eq "$(git -C "$spark_next_worktree" rev-parse HEAD)" "$checkpoint" \
  "Spark next worktree base"
assert_eq "$(field "$output" IMPROVE_MODE)" initial "Spark next mode"
assert_eq "$(field "$output" IMPROVE_BASE)" "$checkpoint" "Spark next reported base"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" \
  "Spark next predecessor"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "Spark next profile"
assert_eq "$(invocation_profile)" improve-executor-spark "Spark next invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 \
  "Spark next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 \
  "Spark next token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "Spark next invocation count"
assert_network_access "Spark next"
grep -F "$checkpoint" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "Spark next prompt omits predecessor"

start_case deep_next complete
run_runner --deep --next "$checkpoint" "plans/001 plan.md"
assert_transport_case 0 COMPLETE completed
deep_next_worktree="$(field "$output" IMPROVE_WORKTREE)"
assert_eq "$(git -C "$deep_next_worktree" rev-parse HEAD)" "$checkpoint" \
  "deep next worktree base"
assert_eq "$(field "$output" IMPROVE_MODE)" initial "deep next mode"
assert_eq "$(field "$output" IMPROVE_BASE)" "$checkpoint" "deep next reported base"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" \
  "deep next predecessor"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "deep next profile"
assert_eq "$(invocation_profile)" improve-executor-deep "deep next invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 7 \
  "deep next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 160000 \
  "deep next token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 "deep next invocation count"
assert_network_access "deep next"
grep -F "$checkpoint" "$FAKE_PROMPT_LOG" >/dev/null ||
  fail "deep next prompt omits predecessor"

start_case environment_spark_next complete
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .codex --allow-protected-path .agents --spark --next \
  "$checkpoint" "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "environment Spark next profile"
assert_eq "$(invocation_profile)" improve-executor-spark \
  "environment Spark next invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment Spark next preflight status"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_COUNT)" 2 \
  "environment Spark next probe count"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" \
  "environment Spark next predecessor"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 \
  "environment Spark next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 \
  "environment Spark next token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 \
  "environment Spark next invocation count"
assert_network_access "environment Spark next"
assert_contract_14_invocation '[".agents",".codex"]' true

start_case environment_deep_next complete
run_runner --environment-json "$valid_environment_json" --deep --next \
  "$checkpoint" "$environment_plan"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-deep \
  "environment deep next profile"
assert_eq "$(invocation_profile)" improve-executor-deep \
  "environment deep next invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_PREFLIGHT_STATUS)" passed \
  "environment deep next preflight status"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" \
  "environment deep next predecessor"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 7 \
  "environment deep next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 160000 \
  "environment deep next token limit"
assert_eq "$(wc -l <"$FAKE_COUNT_FILE")" 1 \
  "environment deep next invocation count"
assert_network_access "environment deep next"
assert_contract_14_invocation '[]' true

start_case environment_spark_next_failure complete
export FAKE_PROBE_MODE=fail
run_runner --environment-json "$valid_environment_json" \
  --allow-protected-path .agents --spark --next \
  "$checkpoint" "$environment_plan"
assert_transport_case 0 STOPPED environment_preflight_failed
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "failed environment Spark next profile"
jq -e '.protectedPaths == [".agents"]' \
  "$(field "$output" IMPROVE_EXEC_RESUME_MANIFEST)" >/dev/null ||
  fail "failed environment Spark next manifest protected paths"
next_failure_worktree="$(field "$output" IMPROVE_WORKTREE)"
next_failure_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
next_failure_artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
next_failure_state_home="$XDG_STATE_HOME"
next_failure_home="$HOME"

start_resume_case environment_next_resume \
  "$next_failure_state_home" "$next_failure_home" complete
run_runner --resume \
  "$next_failure_worktree" "$next_failure_tree" "$next_failure_artifact"
assert_transport_case 0 COMPLETE completed
assert_eq "$(field "$output" IMPROVE_MODE)" initial \
  "resumed environment next mode"
assert_eq "$(field "$output" IMPROVE_BASE)" "$checkpoint" \
  "resumed environment next base"
assert_eq "$(field "$output" IMPROVE_PREDECESSOR_CHECKPOINT)" "$checkpoint" \
  "resumed environment next predecessor"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor-spark \
  "resumed environment Spark next profile"
assert_eq "$(invocation_profile)" improve-executor-spark \
  "resumed environment Spark next invoked profile"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" 5 \
  "resumed environment Spark next timeout"
assert_eq "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" 100000 \
  "resumed environment Spark next token limit"
assert_contract_14_invocation '[".agents"]' true

start_case next_abbreviated
run_runner --next "${checkpoint:0:12}" "plans/001 plan.md"
assert_eq "$status" 2 "abbreviated next status"
assert_not_invoked next_abbreviated

foreign_repo="$test_root/foreign repo"
git init -q "$foreign_repo"
git -C "$foreign_repo" config user.email test@example.invalid
git -C "$foreign_repo" config user.name "Improve Test"
printf '%s\n' foreign >"$foreign_repo/foreign.txt"
git -C "$foreign_repo" add foreign.txt
git -C "$foreign_repo" commit -qm "test: foreign"
foreign_checkpoint="$(git -C "$foreign_repo" rev-parse HEAD)"
start_case next_foreign
run_runner --next "$foreign_checkpoint" "plans/001 plan.md"
assert_eq "$status" 2 "foreign next status"
assert_not_invoked next_foreign

non_tip_worktree="$test_root/non-tip worktree"
git -C "$repo" worktree add -q -b codex/improve-non-tip-test "$non_tip_worktree" main
printf '%s\n' first >"$non_tip_worktree/non-tip.txt"
git -C "$non_tip_worktree" add non-tip.txt
git -C "$non_tip_worktree" commit -qm "test: first checkpoint"
non_tip_checkpoint="$(git -C "$non_tip_worktree" rev-parse HEAD)"
printf '%s\n' second >>"$non_tip_worktree/non-tip.txt"
git -C "$non_tip_worktree" commit -qam "test: advance checkpoint"
start_case next_non_tip
run_runner --next "$non_tip_checkpoint" "plans/001 plan.md"
assert_eq "$status" 2 "non-tip next status"
assert_not_invoked next_non_tip

feature_worktree="$test_root/feature checkpoint"
git -C "$repo" worktree add -q -b feature/checkpoint "$feature_worktree" main
printf '%s\n' feature >"$feature_worktree/feature.txt"
git -C "$feature_worktree" add feature.txt
git -C "$feature_worktree" commit -qm "test: feature checkpoint"
feature_checkpoint="$(git -C "$feature_worktree" rev-parse HEAD)"
start_case next_non_improve
run_runner --next "$feature_checkpoint" "plans/001 plan.md"
assert_eq "$status" 2 "non-Improve next status"
assert_not_invoked next_non_improve

reject_case() {
  name="$1"
  shift
  start_case "$name"
  run_runner "$@"
  assert_eq "$status" 2 "$name status"
  assert_not_invoked "$name"
}

reject_case main_worktree --revise "$repo" "$revision_tree" "$dossier"
mkdir -p "$revision_worktree/subdir"
reject_case subdirectory --revise "$revision_worktree/subdir" "$revision_tree" "$dossier"
reject_case missing_dossier --revise "$revision_worktree" "$revision_tree" "$test_root/missing.md"
reject_case repeated_recovery --recover --recover "$revision_worktree" "$revision_tree" "$dossier"
reject_case revision_then_recovery --revise --recover "$revision_worktree" "$revision_tree" "$dossier"
reject_case recovery_then_revision --recover --revise "$revision_worktree" "$revision_tree" "$dossier"
reject_case lane_after_recovery --recover --spark "$revision_worktree" "$revision_tree" "$dossier"
reject_case recovery_main_worktree --recover "$repo" "$revision_tree" "$dossier"
reject_case recovery_subdirectory --recover "$revision_worktree/subdir" "$revision_tree" "$dossier"
reject_case recovery_missing_dossier --recover "$revision_worktree" "$revision_tree" "$test_root/missing.md"

other_worktree="$test_root/other worktree"
git -C "$repo" worktree add -q -b feature/not-improve "$other_worktree" HEAD
reject_case non_improve_branch --revise "$other_worktree" "$revision_tree" "$dossier"
reject_case recovery_non_improve_branch --recover "$other_worktree" "$revision_tree" "$dossier"

copied_worktree="$test_root/copied worktree"
cp -a "$revision_worktree" "$copied_worktree"
reject_case unregistered_worktree --revise "$copied_worktree" "$revision_tree" "$dossier"
reject_case recovery_unregistered_worktree --recover "$copied_worktree" "$revision_tree" "$dossier"

reject_case old_revision --revise "$revision_worktree" "$dossier"
reject_case old_spark_revision --spark --revise "$revision_worktree" "$dossier"
reject_case old_deep_revision --deep --revise "$revision_worktree" "$dossier"
reject_case old_recovery --recover "$revision_worktree" "$dossier"
reject_case old_spark_recovery --spark --recover "$revision_worktree" "$dossier"
reject_case old_deep_recovery --deep --recover "$revision_worktree" "$dossier"
reject_case spark_candidate --spark --candidate "$candidate_worktree"
reject_case deep_candidate --deep --candidate "$candidate_worktree"
reject_case spark_checkpoint --spark --checkpoint "$revision_worktree" "$revision_tree" message
reject_case deep_checkpoint --deep --checkpoint "$revision_worktree" "$revision_tree" message
reject_case lane_after_next --next --spark "$checkpoint" "plans/001 plan.md"
reject_case environment_after_lane_next --spark --environment-json \
  "$valid_environment_json" --next "$checkpoint" "$environment_plan"
reject_case resume_spark_override --resume --spark \
  "$next_failure_worktree" "$next_failure_tree" "$next_failure_artifact"

sha_repo="$test_root/sha256 repo"
if git init -q --object-format=sha256 "$sha_repo" 2>/dev/null; then
  git -C "$sha_repo" config user.email test@example.invalid
  git -C "$sha_repo" config user.name "Improve Test"
  printf '%s\n' sha256 >"$sha_repo/tracked.txt"
  git -C "$sha_repo" add tracked.txt
  git -C "$sha_repo" commit -qm "test: sha256"
  sha_worktree="$test_root/sha256 worktree"
  git -C "$sha_repo" worktree add -q -b codex/improve-sha256-test "$sha_worktree" HEAD
  printf '%s\n' changed >>"$sha_worktree/tracked.txt"
  start_case sha256_candidate
  run_runner --candidate "$sha_worktree"
  assert_eq "$status" 0 "SHA-256 candidate status"
  sha_candidate_tree="$(field "$output" IMPROVE_CANDIDATE_TREE)"
  assert_eq "${#sha_candidate_tree}" 64 "SHA-256 candidate tree length"
  assert_eq "$sha_candidate_tree" "$(candidate_tree "$sha_worktree")" \
    "SHA-256 candidate tree"
else
  echo "exec-runner: skipping SHA-256 candidate test (unsupported by installed Git)"
fi

bundled_skill="$test_root/complete bundled skill with spaces"
cp -a -- "$(dirname -- "$(dirname -- "$runner_source")")" "$bundled_skill"
chmod -R u+w "$bundled_skill"
bundled_repo="$test_root/bundled repo"
git -c init.defaultBranch=main init -q "$bundled_repo"
git -C "$bundled_repo" config user.email test@example.invalid
git -C "$bundled_repo" config user.name "Improve Test"
mkdir -p "$bundled_repo/plans"
printf '%s\n' bundled >"$bundled_repo/tracked.txt"
printf '%s\n' 'bundled resources' >"$bundled_repo/plans/001.md"
git -C "$bundled_repo" add .
git -C "$bundled_repo" commit -qm "test: bundled resources"
start_case bundled_resources complete
set +e
(
  cd "$bundled_repo"
  env -u CODEX_IMPROVE_ROLES_JSON -u CODEX_IMPROVE_ROLES_FILE \
    -u CODEX_IMPROVE_EXEC_SCHEMA \
    bash "$bundled_skill/scripts/codex-improve-exec" plans/001.md
) >"$case_dir/output" 2>"$case_dir/errors"
status="$?"
set -e
assert_eq "$status" 0 "bundled resource status"
output="$case_dir/output"
assert_eq "$(field "$output" IMPROVE_PROFILE)" improve-executor "bundled stable profile"
assert_eq "$(realpath -- "$(sed -n '/^--output-schema$/{n;p;q;}' "$FAKE_INVOCATION_LOG")")" \
  "$(realpath -- "$bundled_skill/references/executor-report.schema.json")" "bundled schema path"
assert_role_invocation "bundled standard" gpt-5.6-sol medium medium 120000 '[60000,30000,10000]'

echo "exec-runner: all tests passed"
