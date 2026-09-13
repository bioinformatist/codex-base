#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: research-handoff-smoke.bash --self-test|--live" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
case "$1" in --self-test|--live) mode="$1" ;; *) usage ;; esac

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
roles_source="$repo_root/src/improve/config/roles.json"
executor="$repo_root/src/improve/scripts/codex-improve-exec"
environment_json='{"version":1,"launcher":[],"probes":[],"probeOmissionReason":"The smoke uses the locked development environment."}'
umask 077
if [ "$mode" = --live ]; then
  state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  retained_parent="$state_home/codex-improve/research-handoff-smoke"
  mkdir -p "$retained_parent"
  retained_root="$(mktemp -d "$retained_parent/live.XXXXXX")"
else
  retained_root="$(mktemp -d "${TMPDIR:-/tmp}/research-handoff-smoke.XXXXXX")"
fi
roles_file="$retained_root/roles.json"
summary="$retained_root/summary.txt"
last_case_root=""

report_evidence() {
  printf 'RESEARCH_HANDOFF_SMOKE_ROOT=%s\n' "$retained_root"
  printf 'RESEARCH_HANDOFF_SMOKE_ROLES=%s\n' "$roles_file"
  printf 'RESEARCH_HANDOFF_SMOKE_SUMMARY=%s\n' "$summary"
  if [ -n "$last_case_root" ]; then
    printf 'RESEARCH_HANDOFF_SMOKE_RESULT=%s\n' "$last_case_root/result.txt"
    printf 'RESEARCH_HANDOFF_SMOKE_STDERR=%s\n' "$last_case_root/stderr.txt"
    printf 'RESEARCH_HANDOFF_SMOKE_PREFINAL=%s\n' "$last_case_root/pre-final-events.jsonl"
    printf 'RESEARCH_HANDOFF_SMOKE_MESSAGES=%s\n' "$last_case_root/research-messages.json"
    if [ -s "$last_case_root/result.txt" ]; then
      printf 'RESEARCH_HANDOFF_SMOKE_ARTIFACT=%s\n' \
        "$(field "$last_case_root/result.txt" IMPROVE_EXEC_ARTIFACT_DIR)"
      printf 'RESEARCH_HANDOFF_SMOKE_EVENTS=%s\n' \
        "$(field "$last_case_root/result.txt" IMPROVE_EXEC_EVENT_LOG)"
      printf 'RESEARCH_HANDOFF_SMOKE_FINAL=%s\n' \
        "$(field "$last_case_root/result.txt" IMPROVE_EXEC_FINAL_OUTPUT)"
      printf 'RESEARCH_HANDOFF_SMOKE_METRICS=%s\n' \
        "$(field "$last_case_root/result.txt" IMPROVE_EXEC_METRICS)"
    fi
  fi
}
trap report_evidence EXIT

jq -c '.standard |= (.tokenLimit = 12000 | .initialTimeout = 120
  | .reminders = [4000, 2000, 1000] | .networkAccess = false)' \
  "$roles_source" >"$roles_file"

setup_fixture() {
  local case_root="$1" fixture="$1/fixture"
  mkdir -p "$fixture" "$case_root/state"
  git -c init.defaultBranch=main init -q "$fixture"
  git -C "$fixture" config user.email smoke@example.invalid
  git -C "$fixture" config user.name "Research Handoff Smoke"
  printf '%s\n' 'Current specification version: 2' >"$fixture/specification.txt"
  printf '%s\n' 'Retired draft version: 1' >"$fixture/retired-draft.txt"
  {
    printf '%s\n' '# Bounded research smoke'
    # The fixture intentionally contains literal Markdown backticks.
    # shellcheck disable=SC2016
    printf '%s\n' '- **Improve contract**: `1.0.0-codex.16`'
    printf '%s\n' '```json codex-improve-environment' "$environment_json" '```'
    printf '%s\n' 'Determine the current version from the current specification and emit a Research checkpoint.'
    printf '%s\n' 'Then check whether runtime-acceptance.proof exists. Do not create it, search externally, or change source.'
    printf '%s\n' 'If proof is absent, report it as unknown and return STOPPED with a concrete reason.'
  } >"$fixture/plan.md"
  git -C "$fixture" add .
  git -C "$fixture" commit -qm 'test: add bounded research fixture'
}

write_fake_executor() {
  local fake_executor="$1"
  cat >"$fake_executor" <<'FAKE_EXECUTOR'
#!/usr/bin/env bash
set -euo pipefail
: "${SMOKE_ARTIFACT:?}" "${SMOKE_CASE:?}" "${SMOKE_EXPECTED_ENVIRONMENT:?}"
: "${SMOKE_EXPECTED_WORKTREE:?}" "${SMOKE_INVOCATIONS:?}" "${SMOKE_PRODUCTION_ROLES:?}"
: "${SMOKE_RETURNED_WORKTREE:?}" "${SMOKE_UNRELATED_WORKTREE:?}"
printf x >>"$SMOKE_INVOCATIONS"
[ "$#" -eq 3 ] && [ "$1" = --environment-json ]
[ "$2" = "$SMOKE_EXPECTED_ENVIRONMENT" ] && [ "$3" = plan.md ]
[ "$PWD" = "$SMOKE_EXPECTED_WORKTREE" ]
jq -e --slurpfile production "$SMOKE_PRODUCTION_ROLES" '
  .standard.model == "gpt-5.6-sol"
  and .standard.reasoningEffort == "medium"
  and .standard.tokenLimit == 12000
  and .standard.initialTimeout == 120
  and .standard.reminders == [4000, 2000, 1000]
  and .standard.networkAccess == false
  and (del(.standard) == ($production[0] | del(.standard)))
  and ((.standard | del(.tokenLimit, .initialTimeout, .reminders, .networkAccess))
    == ($production[0].standard
      | del(.tokenLimit, .initialTimeout, .reminders, .networkAccess)))
' \
  <<<"$CODEX_IMPROVE_ROLES_JSON" >/dev/null
grep -Fx 'Current specification version: 2' specification.txt >/dev/null
grep -Fx 'Retired draft version: 1' retired-draft.txt >/dev/null
[ ! -e runtime-acceptance.proof ]

git -C "$PWD" worktree add --detach -q "$SMOKE_RETURNED_WORKTREE" HEAD
reported_worktree="$SMOKE_RETURNED_WORKTREE"
if [ "$SMOKE_CASE" = unrelated-worktree ]; then
  git -c init.defaultBranch=main init -q "$SMOKE_UNRELATED_WORKTREE"
  reported_worktree="$SMOKE_UNRELATED_WORKTREE"
fi

mkdir -p "$SMOKE_ARTIFACT"
events="$SMOKE_ARTIFACT/events.jsonl"
final="$SMOKE_ARTIFACT/final.json"
metrics="$SMOKE_ARTIFACT/metrics.jsonl"
rendered="$SMOKE_ARTIFACT/final.txt"
: >"$events"
checkpoint=$'Research checkpoint:\nQuestion: Which source identifies the current specification?\nFinding: The specification is current; the draft is explicitly retired.\nEvidence: specification.txt:1; retired-draft.txt:1\nNext: Determine whether runtime-acceptance.proof exists.'
bullet_checkpoint=$'Research checkpoint:\n- Question: What is current?\n- Finding: Version 2 is current; version 1 is retired.\n- Evidence: specification.txt:1\n- Next: Check runtime-acceptance.proof.'
formatted_checkpoint=$'Research checkpoint:\n- **Question:** What is current?\n- **Finding:** Version 2 is current; version 1 is retired.\n- **Evidence:** `specification.txt`\n- `Next:` Check **`runtime-acceptance.proof`**.'
missing_field_checkpoint=$'Research checkpoint:\n- Question: What is current?\n- Evidence: specification.txt\n- Next: Check runtime-acceptance.proof.'
stopped='{"status":"STOPPED","steps":["Reviewed the current and retired sources; runtime acceptance remains unknown."],"stoppedBecause":"runtime-acceptance.proof is absent, so acceptance is unknown","filesChanged":[],"notes":[]}'
complete='{"status":"COMPLETE","steps":["Claimed acceptance without its proof"],"stoppedBecause":null,"filesChanged":[],"notes":[]}'
json_looking='{"status":"COMPLETE","steps":["intermediate hypothesis only"],"stoppedBecause":null,"filesChanged":[],"notes":[]}'

agent_message() {
  jq -cn --arg text "$1" \
    '{type:"item.completed",item:{type:"agent_message",text:$text}}' >>"$events"
}
turn_completed() {
  if [ "$1" = observed-zero ]; then
    printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}' >>"$events"
  else
    printf '%s\n' '{"type":"turn.completed"}' >>"$events"
  fi
}

report="$stopped"
case "$SMOKE_CASE" in
  valid-missing-usage)
    agent_message "$json_looking"; agent_message "$checkpoint"
    agent_message "$stopped"; turn_completed missing ;;
  valid-observed-zero)
    agent_message "$checkpoint"; agent_message "$stopped"
    turn_completed observed-zero ;;
  valid-bullets)
    agent_message "$bullet_checkpoint"; agent_message "$stopped"
    turn_completed observed-zero ;;
  valid-formatted-file-only)
    agent_message "$formatted_checkpoint"; agent_message "$stopped"
    turn_completed observed-zero ;;
  post-terminal-checkpoint)
    agent_message "$stopped"; turn_completed observed-zero
    agent_message "$checkpoint" ;;
  final-report-only)
    agent_message "$stopped"; turn_completed observed-zero ;;
  missing-messages) turn_completed observed-zero ;;
  wrong-final-status)
    report="$complete"; agent_message "$checkpoint"
    agent_message "$complete"; turn_completed observed-zero ;;
  fired-fuse|source-mutation)
    agent_message "$checkpoint"; agent_message "$stopped"
    turn_completed observed-zero ;;
  missing-field|unrelated-worktree)
    if [ "$SMOKE_CASE" = missing-field ]; then
      agent_message "$missing_field_checkpoint"
    else
      agent_message "$checkpoint"
    fi
    agent_message "$stopped"; turn_completed observed-zero ;;
  *) exit 64 ;;
esac
printf '%s\n' "$report" >"$final"
printf '%s\n' "$report" >"$rendered"

usage_observed=true
[ "$SMOKE_CASE" != valid-missing-usage ] || usage_observed=false
absolute_timeout=false
[ "$SMOKE_CASE" != fired-fuse ] || absolute_timeout=true
jq -cn --arg execution_id "self-test-$SMOKE_CASE" \
  --argjson usage_observed "$usage_observed" \
  --argjson absolute_timeout "$absolute_timeout" \
  '{execution_id:$execution_id,usage_observed:$usage_observed,
    token_usage:{input_tokens:0,cached_input_tokens:0,output_tokens:0},
    active_timeout_seconds:120,active_token_limit:12000,
    fuse_flags:{absolute_timeout:$absolute_timeout,event_log_limit:false,
      wrapper_signal:false,rollout_budget_exhausted:false}}' >"$metrics"
[ "$SMOKE_CASE" != source-mutation ] || \
  printf '%s\n' 'transiently changed' >>"$SMOKE_RETURNED_WORKTREE/specification.txt"

result=STOPPED
[ "$SMOKE_CASE" != wrong-final-status ] || result=COMPLETE
printf 'IMPROVE_MODE=initial\nIMPROVE_WORKTREE=%s\nIMPROVE_BRANCH=main\n' "$reported_worktree"
printf 'IMPROVE_BASE=fixture-base\nIMPROVE_PROFILE=improve-executor\n'
printf 'IMPROVE_MODEL=gpt-5.6-sol\nIMPROVE_REASONING_EFFORT=medium\n'
printf 'IMPROVE_CONTRACT=1.0.0-codex.16\nIMPROVE_EXECUTION_ID=self-test-%s\n' "$SMOKE_CASE"
printf 'IMPROVE_EXEC_RESULT=%s\nIMPROVE_EXEC_EXIT_REASON=completed\n' "$result"
printf 'IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS=120\nIMPROVE_EXEC_ACTIVE_TOKEN_LIMIT=12000\n'
printf 'IMPROVE_EXEC_ARTIFACT_DIR=%s\nIMPROVE_EXEC_EVENT_LOG=%s\n' "$SMOKE_ARTIFACT" "$events"
printf 'IMPROVE_EXEC_FINAL_OUTPUT=%s\nIMPROVE_EXEC_METRICS=%s\n' "$rendered" "$metrics"
printf 'IMPROVE_CANDIDATE_AVAILABLE=1\nIMPROVE_CANDIDATE_HEAD=fixture-head\n'
printf 'IMPROVE_CANDIDATE_TREE=fixture-tree\n'
FAKE_EXECUTOR
  chmod 700 "$fake_executor"
}

field() {
  local output="$1" name="$2"
  sed -n "s/^$name=//p" "$output" | tail -n 1
}

derive_prefinal() {
  local events="$1" final="$2" destination="$3"
  jq -s --slurpfile final "$final" '
    def is_final_message($report):
      .type? == "item.completed" and .item.type? == "agent_message"
      and (.item.text? | type == "string")
      and (try ((.item.text | fromjson) == $report) catch false);
    . as $events
    | ([range(0; length) as $index | $events[$index] as $event
        | select((($event.type? // "")
            | test("^turn\\.(completed|failed|cancelled)$"))
          or ($event | is_final_message($final[0])))
        | $index] | min // length) as $boundary
    | .[:$boundary][]
  ' "$events" >"$destination"
}

validate_attempt() {
  local case_root="$1" output="$1/result.txt" fixture="$1/fixture"
  local artifact execution_id events final rendered metrics metric worktree
  local fixture_common fixture_root worktree_common worktree_root
  local prefinal="$1/pre-final-events.jsonl" messages="$1/research-messages.json"
  worktree="$(field "$output" IMPROVE_WORKTREE)"
  [ -n "$worktree" ] && [ -d "$worktree" ] || return 1
  worktree_root="$(git -C "$worktree" rev-parse --show-toplevel)" || return 1
  worktree_root="$(cd -- "$worktree_root" && pwd -P)" || return 1
  [ "$worktree_root" = "$(cd -- "$worktree" && pwd -P)" ] || return 1
  fixture_root="$(git -C "$fixture" rev-parse --show-toplevel)" || return 1
  fixture_root="$(cd -- "$fixture_root" && pwd -P)" || return 1
  [ "$worktree_root" != "$fixture_root" ] || return 1
  fixture_common="$(git -C "$fixture" rev-parse --path-format=absolute \
    --git-common-dir)" || return 1
  worktree_common="$(git -C "$worktree" rev-parse --path-format=absolute \
    --git-common-dir)" || return 1
  [ "$(cd -- "$fixture_common" && pwd -P)" = \
    "$(cd -- "$worktree_common" && pwd -P)" ] || return 1
  git -C "$fixture" worktree list --porcelain \
    | grep -Fx "worktree $worktree_root" >/dev/null || return 1
  [ "$(field "$output" IMPROVE_PROFILE)" = improve-executor ] || return 1
  [ "$(field "$output" IMPROVE_MODEL)" = gpt-5.6-sol ] || return 1
  [ "$(field "$output" IMPROVE_REASONING_EFFORT)" = medium ] || return 1
  [ "$(field "$output" IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS)" = 120 ] || return 1
  [ "$(field "$output" IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT)" = 12000 ] || return 1
  [ "$(field "$output" IMPROVE_EXEC_RESULT)" = STOPPED ] || return 1
  [ "$(field "$output" IMPROVE_EXEC_EXIT_REASON)" = completed ] || return 1

  artifact="$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
  execution_id="$(field "$output" IMPROVE_EXECUTION_ID)"
  events="$(field "$output" IMPROVE_EXEC_EVENT_LOG)"
  final="$artifact/final.json"
  rendered="$(field "$output" IMPROVE_EXEC_FINAL_OUTPUT)"
  metrics="$(field "$output" IMPROVE_EXEC_METRICS)"
  [ "$events" = "$artifact/events.jsonl" ] || return 1
  [ "$rendered" = "$artifact/final.txt" ] || return 1
  [ -s "$events" ] && [ -s "$final" ] && [ -s "$rendered" ] && \
    [ -s "$metrics" ] || return 1
  jq -e -s 'length > 0 and all(.[]; type == "object")' "$events" >/dev/null || return 1
  jq -e '.status == "STOPPED"' "$final" >/dev/null || return 1
  metric="$(jq -ce -s --arg id "$execution_id" \
    '[.[] | select(.execution_id == $id)] | last // empty' "$metrics")" || return 1
  jq -e '.active_timeout_seconds == 120 and .active_token_limit == 12000
    and (.fuse_flags | .absolute_timeout == false
      and .event_log_limit == false and .wrapper_signal == false
      and .rollout_budget_exhausted == false)' <<<"$metric" >/dev/null || return 1

  derive_prefinal "$events" "$final" "$prefinal" || return 1
  jq -s '[.[] | select(.type? == "item.completed"
      and .item.type? == "agent_message") | .item.text
      | select(type == "string")
      | select((gsub("[*`]"; "")
        | test("(?i)^[[:space:]]*research checkpoint[[:space:]]*:")))]' \
    "$prefinal" >"$messages" || return 1
  jq -e 'def structural:
      gsub("(?m)^[[:space:]]*[-+*][[:space:]]+"; "")
      | gsub("[*`]"; "");
    any(.[] | structural;
      test("(?im)^[[:space:]]*question[[:space:]]*:[[:space:]]*\\S")
      and test("(?im)^[[:space:]]*finding[[:space:]]*:[[:space:]]*\\S")
      and test("(?im)^[[:space:]]*evidence[[:space:]]*:[^\\n]*specification\\.txt(:[0-9]+)?([^[:alnum:]_.-]|$)")
      and test("(?im)^[[:space:]]*next[[:space:]]*:[^\\n]*runtime-acceptance\\.proof"))' \
    "$messages" >/dev/null || return 1
  [ -z "$(git -C "$worktree" status --porcelain)" ] || return 1
  [ -z "$(git -C "$fixture" status --porcelain)" ] || return 1
  if jq -e '.usage_observed == true' <<<"$metric" >/dev/null; then
    printf '%s\n' 'USAGE_STATE=observed'
  else
    printf '%s\n' 'USAGE_STATE=unknown'
  fi
}

run_attempt() {
  local name="$1" case_root="$2" selected_executor="$3" runner_expectation="$4"
  local fixture="$2/fixture" invocation_count="$2/invocations"
  local artifact="$2/fake-artifact" roles_json runner_status
  setup_fixture "$case_root"
  : >"$invocation_count"
  roles_json="$(<"$roles_file")"
  if [ "$name" = altered-standard-limit ]; then
    roles_json="$(jq -c '.standard.tokenLimit = 11999' "$roles_file")"
  fi
  set +e
  (cd "$fixture" && XDG_STATE_HOME="$case_root/state" \
    CODEX_IMPROVE_ROLES_JSON="$roles_json" \
    SMOKE_ARTIFACT="$artifact" SMOKE_CASE="$name" \
    SMOKE_EXPECTED_ENVIRONMENT="$environment_json" \
    SMOKE_EXPECTED_WORKTREE="$fixture" SMOKE_PRODUCTION_ROLES="$roles_source" \
    SMOKE_RETURNED_WORKTREE="$case_root/returned-worktree" \
    SMOKE_UNRELATED_WORKTREE="$case_root/unrelated-worktree" \
    SMOKE_INVOCATIONS="$invocation_count" \
    bash "$selected_executor" --environment-json "$environment_json" plan.md) \
    >"$case_root/result.txt" 2>"$case_root/stderr.txt"
  runner_status=$?
  set -e
  [ "$(wc -c <"$invocation_count")" -eq 1 ] || return 1
  if [ "$runner_expectation" = reject ]; then
    [ "$runner_status" -ne 0 ] || return 1
    return 0
  fi
  [ "$runner_status" -eq 0 ] || return 1
}

if [ "$mode" = --self-test ]; then
  fake_executor="$retained_root/fake-executor"
  write_fake_executor "$fake_executor"
  : >"$summary"
  while read -r name runner_expectation expectation usage_state; do
    case_root="$retained_root/$name"
    last_case_root="$case_root"
    run_attempt "$name" "$case_root" "$fake_executor" "$runner_expectation" || {
      echo "fake attempt failed before validation: $name" >&2; exit 1;
    }
    if [ "$runner_expectation" = reject ]; then
      printf '%s=fake-input-reject usage=n/a\n' "$name" | tee -a "$summary"
      continue
    fi
    if validate_attempt "$case_root" >"$case_root/validation.txt" 2>&1; then
      actual=accept
    else
      actual=reject
    fi
    [ "$actual" = "$expectation" ] || {
      echo "unexpected validation result for $name: $actual" >&2; exit 1;
    }
    if [ "$expectation" = accept ]; then
      grep -Fx "USAGE_STATE=$usage_state" "$case_root/validation.txt" >/dev/null || {
        echo "unexpected usage state for $name" >&2; exit 1;
      }
    fi
    printf '%s=%s usage=%s\n' "$name" "$actual" "$usage_state" | tee -a "$summary"
  done <<'SELF_TEST_CASES'
valid-missing-usage accept accept unknown
valid-observed-zero accept accept observed
valid-bullets accept accept observed
valid-formatted-file-only accept accept observed
post-terminal-checkpoint accept reject n/a
final-report-only accept reject n/a
missing-messages accept reject n/a
missing-field accept reject n/a
wrong-final-status accept reject n/a
fired-fuse accept reject n/a
source-mutation accept reject n/a
unrelated-worktree accept reject n/a
altered-standard-limit reject n/a n/a
SELF_TEST_CASES
  exit 0
fi

codex_version_file="$retained_root/codex-version.txt"
codex --version >"$codex_version_file"
[ "$(<"$codex_version_file")" = 'codex-cli 0.153.4' ] || {
  echo "live smoke requires codex-cli 0.153.4" >&2; exit 1;
}
case_root="$retained_root/live"
last_case_root="$case_root"
mkdir -p "$case_root"
setup_fixture "$case_root"
output="$case_root/result.txt"
errors="$case_root/stderr.txt"
set +e
(cd "$case_root/fixture" && XDG_STATE_HOME="$case_root/state" \
  CODEX_IMPROVE_ROLES_JSON="$(<"$roles_file")" \
  "$executor" --environment-json "$environment_json" plan.md) >"$output" 2>"$errors"
runner_status=$?
set -e
[ "$runner_status" -eq 0 ] || {
  echo "live smoke runner exited $runner_status" >&2; exit 1;
}
validate_attempt "$case_root" | tee "$case_root/validation.txt"
{
  printf 'live=accept\nexecution_id=%s\n' "$(field "$output" IMPROVE_EXECUTION_ID)"
  printf 'model=%s\neffort=%s\n' "$(field "$output" IMPROVE_MODEL)" \
    "$(field "$output" IMPROVE_REASONING_EFFORT)"
  printf 'artifact_dir=%s\n' "$(field "$output" IMPROVE_EXEC_ARTIFACT_DIR)"
} | tee "$summary"
