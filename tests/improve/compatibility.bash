#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
roles="$root/src/improve/config/roles.json"
jq -e '
  [
    [.scout.profile,.scout.model,.scout.reasoningEffort,.scout.verbosity,.scout.sandbox,.scout.approval,.scout.networkAccess,.scout.initialTimeout],
    [.standard.profile,.standard.model,.standard.reasoningEffort,.standard.verbosity,.standard.sandbox,.standard.approval,.standard.networkAccess,.standard.tokenLimit,.standard.initialTimeout,.standard.followupTimeout],
    [.spark.profile,.spark.model,.spark.reasoningEffort,.spark.verbosity,.spark.sandbox,.spark.approval,.spark.networkAccess,.spark.tokenLimit,.spark.initialTimeout,.spark.followupTimeout],
    [.deep.profile,.deep.model,.deep.reasoningEffort,.deep.verbosity,.deep.sandbox,.deep.approval,.deep.networkAccess,.deep.tokenLimit,.deep.initialTimeout,.deep.followupTimeout],
    [.correctness.profile,.correctness.model,.correctness.reasoningEffort,.correctness.verbosity,.correctness.sandbox,.correctness.approval,.correctness.networkAccess,.correctness.tokenLimit,.correctness.initialTimeout],
    [.elegance.profile,.elegance.model,.elegance.reasoningEffort,.elegance.verbosity,.elegance.sandbox,.elegance.approval,.elegance.networkAccess,.elegance.tokenLimit,.elegance.initialTimeout]
  ] == [
    ["improve-scout","gpt-5.6-luna","high","low","read-only","never",false,480],
    ["improve-executor","gpt-5.6-sol","medium","medium","workspace-write","never",true,120000,1200,720],
    ["improve-executor-spark","gpt-5.3-codex-spark","high","medium","workspace-write","never",true,100000,1200,720],
    ["improve-executor-deep","gpt-5.6-sol","xhigh","medium","workspace-write","never",true,160000,1800,1080],
    ["improve-reviewer","gpt-5.6-sol","high","medium","read-only","never",false,100000,480],
    ["improve-elegance-reviewer","gpt-5.6-sol","high","medium","read-only","never",false,100000,480]
  ]
  and (.standard.reminders == [60000,30000,10000])
  and (.spark.reminders == [50000,25000,10000])
  and (.deep.reminders == [80000,40000,15000])
  and (.correctness.reminders == [50000,25000,10000])
  and (.elegance.reminders == [50000,25000,10000])
  and ([.[] | .writableRoots] | all(. == []))
' "$roles" >/dev/null
for script in "$root"/src/improve/scripts/*; do
  if grep -E -- '^[[:space:]]+-p([[:space:]]|$)|codex[[:space:]]+exec.*[[:space:]]-p([[:space:]]|$)' "$script" >/dev/null; then
    printf 'profile lookup remains in %s\n' "$script" >&2
    exit 1
  fi
done
for profile in improve-scout improve-executor improve-executor-spark improve-executor-deep improve-reviewer improve-elegance-reviewer; do
  grep -Fq -- "$profile" "$roles"
  test ! -e "$root/plugins/codex-base/skills/improve/$profile.config.toml"
done

require_text() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "$expected" "$file" || {
    printf 'missing Improve contract text in %s: %s\n' "$file" "$expected" >&2
    exit 1
  }
}

forbid_text() {
  local file="$1"
  local forbidden="$2"
  if grep -Fq -- "$forbidden" "$file"; then
    printf 'obsolete Improve contract text remains in %s: %s\n' \
      "$file" "$forbidden" >&2
    exit 1
  fi
}

skill="$root/src/improve/SKILL.md"
planning="$root/src/improve/references/planning-contract.md"
template="$root/src/improve/references/plan-template.md"
closeout="$root/src/improve/references/closing-the-loop.md"

require_text "$skill" 'version: "1.0.0-codex.15"'
require_text "$planning" "Contract version: \`1.0.0-codex.15\`"
require_text "$template" "**Improve contract**: \`1.0.0-codex.15\`"
require_text "$planning" "**Necessity**"
require_text "$skill" 'The runner owns plan and candidate identity'
require_text "$skill" 'Before writing or dispatching a triggered plan'
require_text "$planning" 'has a predecessor or dependency'
require_text "$planning" 'Only a route-selecting evidence plan'
require_text "$template" '## Route checkpoint'
require_text "$template" 'Only for a route-selecting evidence plan'
require_text "$closeout" 'exact named Fresh evidence'
require_text "$closeout" 'repository observation'
require_text "$planning" 'Revision or recovery count alone is never an'
require_text "$template" 'Initial implementation review covers the complete candidate diff.'
require_text "$template" 'After every code/test-changing step, run its named verification'
require_text "$closeout" "\`IMPROVE_EXEC_CLOSEOUT_ELIGIBLE=0\` or \`1\`"
require_text "$closeout" 'It never converts, masks, or overrides the original'
require_text "$closeout" 'This is a compact stepwise checkpoint contract'
require_text "$closeout" "Apply the installed \`\$ponytail-review\` skill once to the current diff."
require_text "$closeout" 'single-use across the candidate lifecycle, cannot recurse'
require_text "$closeout" "\`always-invalidated\`"

forbid_text "$skill" "\`.14\` environment dispatch"
forbid_text "$planning" 'Any candidate change creates a new tree identity and invalidates conclusions'
forbid_text "$closeout" 'run the full original plan gates'
forbid_text "$closeout" 'Re-run every done criterion'
forbid_text "$closeout" 'against the exact predecessor or acceptance evidence'
forbid_text "$template" 'and make at least one result close or stop a decision?'

cmp "$root/src/improve/config/roles.json" "$root/plugins/codex-base/skills/improve/config/roles.json"
printf 'Improve compatibility fixture passed\n'
