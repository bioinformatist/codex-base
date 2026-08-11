#!/usr/bin/env bash
set -euo pipefail

runner="$(realpath -- "$1")"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/worktree with spaces"
printf '#!%s\n' "$(command -v bash)" >"$root/bin/codex"
cat >>"$root/bin/codex" <<'SH'
printf '%s\n' "$@" >>"$SCOUT_INVOCATIONS"
cat >"$SCOUT_STDIN"
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = --output-last-message ]; then output="$2"; shift 2; else shift; fi
done
[ -z "$output" ] || printf 'memo\n' >"$output"
exit "${SCOUT_CODE:-0}"
SH
chmod +x "$root/bin/codex"
export PATH="$root/bin:$PATH" SCOUT_INVOCATIONS="$root/invocations" SCOUT_STDIN="$root/stdin"
roles='{"scout":{"profile":"improve-scout","model":"gpt-test","reasoningEffort":"high","verbosity":"low","sandbox":"read-only","approval":"never","networkAccess":false,"writableRoots":[],"tokenLimit":null,"reminders":[],"initialTimeout":480,"followupTimeout":null}}'
export CODEX_IMPROVE_ROLES_JSON="$roles"
output="$root/output with spaces.md"
printf 'one prompt\n' | bash "$runner" "$root/worktree with spaces" "$output"
test "$(cat "$SCOUT_STDIN")" = 'one prompt'
test "$(cat "$output")" = memo
test "$(grep -c '^exec$' "$SCOUT_INVOCATIONS")" -eq 1
for value in --strict-config --ephemeral --json --model gpt-test 'model_reasoning_effort="high"' 'model_verbosity="low"' 'approval_policy="never"' 'sandbox_mode="read-only"' --disable multi_agent --output-last-message "$output" -C "$root/worktree with spaces" -; do
  grep -Fx -- "$value" "$SCOUT_INVOCATIONS" >/dev/null
done
if grep -Fx -- -p "$SCOUT_INVOCATIONS" >/dev/null; then
  printf 'scout retained standalone -p profile lookup\n' >&2
  exit 1
fi
if grep -Fx -- timeout "$SCOUT_INVOCATIONS" >/dev/null; then
  printf 'scout runner owns an unexpected timeout wrapper\n' >&2
  exit 1
fi

if bash "$runner" >/dev/null 2>"$root/error"; then exit 1; fi
grep -F 'usage:' "$root/error" >/dev/null
if bash "$runner" "$root/missing" "$output" >/dev/null 2>"$root/error"; then exit 1; fi
grep -F 'worktree is not a directory' "$root/error" >/dev/null
for invalid in '{}' '{'; do
  if CODEX_IMPROVE_ROLES_JSON="$invalid" bash "$runner" "$root/worktree with spaces" "$output" </dev/null >/dev/null 2>"$root/error"; then exit 1; fi
  grep -F 'scout role configuration is missing or invalid' "$root/error" >/dev/null
done
if CODEX_IMPROVE_ROLES_JSON='' CODEX_IMPROVE_ROLES_FILE="$root/missing-roles" bash "$runner" "$root/worktree with spaces" "$output" </dev/null >/dev/null 2>"$root/error"; then exit 1; fi
grep -F 'role configuration is unavailable' "$root/error" >/dev/null

: >"$SCOUT_INVOCATIONS"
if SCOUT_CODE=23 bash "$runner" "$root/worktree with spaces" "$output" </dev/null; then exit 1; else status=$?; fi
test "$status" -eq 23
test "$(grep -c '^exec$' "$SCOUT_INVOCATIONS")" -eq 1
printf 'scout runner tests passed\n'
