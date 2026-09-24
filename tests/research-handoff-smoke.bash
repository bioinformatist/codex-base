#!/usr/bin/env bash
set -euo pipefail

usage() { echo 'usage: research-handoff-smoke.bash --self-test|--live' >&2; exit 2; }
[ "$#" -eq 1 ] || usage
case "$1" in --self-test|--live) mode="$1" ;; *) usage ;; esac

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
executor="$repo_root/src/improve/scripts/codex-improve"
umask 077
if [ "$mode" = --live ]; then
  retained_parent="${XDG_STATE_HOME:-$HOME/.local/state}/codex-improve/research-handoff-smoke"
  mkdir -p "$retained_parent"
  root="$(mktemp -d "$retained_parent/live.XXXXXX")"
else
  root="$(mktemp -d "${TMPDIR:-/tmp}/research-handoff-smoke.XXXXXX")"
fi
printf 'RESEARCH_HANDOFF_SMOKE_ROOT=%s\n' "$root"

setup_fixture() {
  local case_root="$1" fixture="$1/fixture"
  mkdir -p "$fixture" "$case_root/state"
  git -c init.defaultBranch=main init -q "$fixture"
  git -C "$fixture" config user.email smoke@example.invalid
  git -C "$fixture" config user.name 'Research Handoff Smoke'
  printf 'Current specification version: 2\n' >"$fixture/specification.txt"
  printf 'Retired draft version: 1\n' >"$fixture/retired-draft.txt"
  cat >"$fixture/plan.md" <<'PLAN'
# Bounded research smoke
- **Improve contract**: `1.0.0-codex.17`
```json codex-improve-environment
{"version":1,"launcher":["env"],"probes":[]}
```
Determine the current version from specification.txt and emit a Research checkpoint.
Then check whether runtime-acceptance.proof exists. Do not create it, search externally, or change source.
If proof is absent, report it as unknown and return STOPPED with a concrete reason.
PLAN
  git -C "$fixture" add .
  git -C "$fixture" commit -qm 'test: add bounded research fixture'
}

write_fake_codex() {
  mkdir -p "$root/bin"
  cat >"$root/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
final=''
previous=''
for arg in "$@"; do
  if [ "$previous" = --output-last-message ]; then final="$arg"; fi
  previous="$arg"
done
[ -n "$final" ]
[ -f specification.txt ] && [ ! -e runtime-acceptance.proof ]
[[ " $* " == *' --model gpt-6-sol '* ]]
checkpoint=$'Research checkpoint:\nQuestion: Which source identifies the current specification?\nFinding: Version 2 is current; version 1 is retired.\nEvidence: specification.txt:1; retired-draft.txt:1\nNext: Check whether runtime-acceptance.proof exists.'
bullet_checkpoint=$'Research checkpoint:\n- Question: What is current?\n- Finding: Version 2 is current; version 1 is retired.\n- Evidence: specification.txt:1\n- Next: Check runtime-acceptance.proof.'
formatted_checkpoint=$'Research checkpoint:\n- **Question:** What is current?\n- **Finding:** Version 2 is current; version 1 is retired.\n- **Evidence:** `specification.txt`\n- `Next:` Check **`runtime-acceptance.proof`**.'
missing_field=$'Research checkpoint:\nQuestion: What is current?\nEvidence: specification.txt:1\nNext: Check runtime-acceptance.proof.'
stopped='{"status":"STOPPED","steps":["Checked the current specification; runtime acceptance is unknown."],"stoppedBecause":"runtime-acceptance.proof is absent","filesChanged":[],"notes":[]}'
complete='{"status":"COMPLETE","steps":["Claimed acceptance without proof"],"stoppedBecause":null,"filesChanged":[],"notes":[]}'
message() { jq -cn --arg text "$1" '{type:"item.completed",item:{type:"agent_message",text:$text}}'; }
case "$SMOKE_CASE" in
  valid-missing-usage|valid-observed-zero|valid-positive-usage|valid-bullets|valid-formatted-file-only|missing-field|final-report-only|post-terminal-checkpoint|post-final-message-checkpoint|contradictory-report) ;;
  *) exit 64 ;;
esac
if [ "$SMOKE_CASE" = missing-field ]; then
  message "$missing_field"
elif [ "$SMOKE_CASE" = valid-bullets ]; then
  message "$bullet_checkpoint"
elif [ "$SMOKE_CASE" = valid-formatted-file-only ]; then
  message "$formatted_checkpoint"
elif [ "$SMOKE_CASE" = valid-positive-usage ]; then
  message "$complete"
  message "$checkpoint"
elif [ "$SMOKE_CASE" != final-report-only ] && [ "$SMOKE_CASE" != post-terminal-checkpoint ] && [ "$SMOKE_CASE" != post-final-message-checkpoint ]; then
  message "$checkpoint"
fi
if [ "$SMOKE_CASE" = post-final-message-checkpoint ] || [ "$SMOKE_CASE" = final-report-only ]; then
  message "$stopped"
fi
if [ "$SMOKE_CASE" = post-final-message-checkpoint ]; then message "$checkpoint"; fi
if [ "$SMOKE_CASE" = valid-missing-usage ]; then
  printf '%s\n' '{"type":"turn.completed"}'
elif [ "$SMOKE_CASE" = valid-positive-usage ]; then
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":20,"cached_input_tokens":5,"output_tokens":3}}'
else
  printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}}'
fi
if [ "$SMOKE_CASE" = post-terminal-checkpoint ]; then message "$checkpoint"; fi
if [ "$SMOKE_CASE" = contradictory-report ]; then
  printf '%s\n' "$complete" >"$final"
else
  printf '%s\n' "$stopped" >"$final"
fi
FAKE_CODEX
  chmod 700 "$root/bin/codex"
}

run_attempt() {
  local case_root="$1" name="$2" fixture="$1/fixture"
  local smoke_case="$name"
  setup_fixture "$case_root"
  if [ "$mode" = --self-test ]; then
    case "$name" in unrelated-worktree|wrong-candidate|missing-events|source-mutation) smoke_case=valid-observed-zero ;; esac
    (cd "$fixture" && XDG_STATE_HOME="$case_root/state" SMOKE_CASE="$smoke_case" \
      PATH="$root/bin:$PATH" python3 -B "$executor" execute plan.md "$fixture") \
      >"$case_root/result.json" 2>"$case_root/stderr.txt"
  else
    (cd "$fixture" && XDG_STATE_HOME="$case_root/state" \
      python3 -B "$executor" execute plan.md "$fixture") \
      >"$case_root/result.json" 2>"$case_root/stderr.txt"
  fi
}

tamper_attempt() {
  local case_root="$1" name="$2" result="$1/result.json"
  case "$name" in
    unrelated-worktree)
      jq --arg path "$case_root/fixture" '.worktree = $path' "$result" >"$result.tmp"
      mv "$result.tmp" "$result" ;;
    wrong-candidate)
      jq '.candidate_tree = "0000000000000000000000000000000000000000"' "$result" >"$result.tmp"
      mv "$result.tmp" "$result" ;;
    missing-events) rm "$(jq -r '.artifacts.events' "$result")" ;;
    source-mutation)
      printf 'unreviewed mutation\n' >>"$(jq -r '.worktree' "$result")/specification.txt" ;;
  esac
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
  local case_root="$1" result="$1/result.json" fixture="$1/fixture"
  local worktree artifact events final metrics fixture_common worktree_common
  local prefinal="$1/pre-final-events.jsonl"
  worktree="$(jq -er '.worktree' "$result")" || return 1
  [ -d "$worktree" ] || return 1
  [ "$(git -C "$worktree" rev-parse --show-toplevel)" = "$worktree" ] || return 1
  [ "$worktree" != "$fixture" ] || return 1
  fixture_common="$(git -C "$fixture" rev-parse --path-format=absolute --git-common-dir)" || return 1
  worktree_common="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)" || return 1
  [ "$fixture_common" = "$worktree_common" ] || return 1
  git -C "$fixture" worktree list --porcelain | grep -Fx "worktree $worktree" >/dev/null || return 1
  jq -e '.kind == "execute" and .role == "standard" and .phase == "finished"
    and .outcome == "STOPPED" and .reason == "completed"
    and .candidate_tree == .output_candidate_tree
    and .report.status == "STOPPED"
    and (.report.stoppedBecause | contains("runtime-acceptance.proof is absent"))' "$result" >/dev/null || return 1
  XDG_STATE_HOME="$case_root/state" python3 -B "$executor" status "$(jq -r '.id' "$result")" \
    | jq -e --slurpfile result "$result" '. == ($result[0] | with_entries(select(.key | IN("id","kind","role","phase","outcome","reason","worktree","candidate_tree","output_candidate_tree","report","artifacts","closeout_eligible","parent"))))' >/dev/null || return 1

  artifact="$case_root/state/codex-improve-v17/executions/$(jq -r '.id' "$result")"
  events="$(jq -er '.artifacts.events' "$result")" || return 1
  final="$(jq -er '.artifacts.final' "$result")" || return 1
  metrics="$artifact/metrics.json"
  [ "$events" = "$artifact/events.jsonl" ] && [ "$final" = "$artifact/final.json" ] || return 1
  [ -s "$events" ] && [ -s "$final" ] && [ -s "$metrics" ] || return 1
  jq -e --slurpfile result "$result" '. == $result[0].report' "$final" >/dev/null || return 1
  derive_prefinal "$events" "$final" "$prefinal" || return 1
  jq -es 'def structural:
      gsub("(?m)^[[:space:]]*[-+*][[:space:]]+"; "")
      | gsub("[*`]"; "");
    any(.[] | select(.type? == "item.completed" and .item.type? == "agent_message")
      | .item.text | select(type == "string") | structural;
      test("(?i)^[[:space:]]*research checkpoint[[:space:]]*:")
      and test("(?im)^[[:space:]]*question[[:space:]]*:[[:space:]]*\\S")
      and test("(?im)^[[:space:]]*finding[[:space:]]*:[[:space:]]*\\S")
      and test("(?im)^[[:space:]]*evidence[[:space:]]*:[^\\n]*specification\\.txt(:[0-9]+)?([^[:alnum:]_.-]|$)")
      and test("(?im)^[[:space:]]*next[[:space:]]*:[^\\n]*runtime-acceptance\\.proof"))' \
    "$prefinal" >/dev/null || return 1
  [ -z "$(git -C "$worktree" status --porcelain)" ] || return 1
  [ -z "$(git -C "$fixture" status --porcelain)" ] || return 1
  if jq -e '.usage_observed == true and (.token_usage | type == "object"
    and ([.input_tokens, .cached_input_tokens, .output_tokens] | all(.[]; type == "number" and . >= 0)))' "$metrics" >/dev/null; then
    if jq -e '.token_usage == {"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}' "$metrics" >/dev/null; then
      printf 'USAGE_STATE=observed-zero\n'
    else
      printf 'USAGE_STATE=observed\n'
    fi
  elif jq -e '.usage_observed == false and .token_usage == null' "$metrics" >/dev/null; then
    printf 'USAGE_STATE=unknown\n'
  else
    return 1
  fi
}

if [ "$mode" = --self-test ]; then
  write_fake_codex
  for name in valid-missing-usage valid-observed-zero valid-positive-usage valid-bullets valid-formatted-file-only missing-field final-report-only post-terminal-checkpoint post-final-message-checkpoint contradictory-report unrelated-worktree wrong-candidate missing-events source-mutation; do
    case_root="$root/$name"
    run_attempt "$case_root" "$name"
    tamper_attempt "$case_root" "$name"
    if validate_attempt "$case_root" >"$case_root/validation.txt"; then actual=accept; else actual=reject; fi
    case "$name" in valid-*) expected=accept ;; *) expected=reject ;; esac
    [ "$actual" = "$expected" ] || { echo "unexpected validation result: $name=$actual" >&2; exit 1; }
    if [ "$actual" = accept ]; then
      case "$name" in
        valid-missing-usage) expected_usage=unknown ;;
        valid-positive-usage) expected_usage=observed ;;
        *) expected_usage=observed-zero ;;
      esac
      grep -Fx "USAGE_STATE=$expected_usage" "$case_root/validation.txt" >/dev/null
    fi
    printf '%s=%s\n' "$name" "$actual"
  done
  exit 0
fi

case_root="$root/live"
run_attempt "$case_root" live
validate_attempt "$case_root" | tee "$case_root/validation.txt"
