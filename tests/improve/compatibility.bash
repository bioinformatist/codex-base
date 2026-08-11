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
cmp "$root/src/improve/config/roles.json" "$root/plugins/codex-base/skills/improve/config/roles.json"
printf 'Improve compatibility fixture passed\n'
