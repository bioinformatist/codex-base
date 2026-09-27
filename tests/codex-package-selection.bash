#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
export CODEX_PACKAGE_LOG="$tmp/log"
mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$CODEX_PACKAGE_LOG" "$tmp/conflict"
chmod 700 "$XDG_STATE_HOME"
cat > "$tmp/conflict/codex" <<EOF
#!/bin/sh
printf conflict >> '$tmp/conflict.log'
exit 97
EOF
cat > "$tmp/conflict/mcp-nixos" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/conflict/codex" "$tmp/conflict/mcp-nixos"
export PATH="$tmp/conflict:$PATH"
export CODEX_IMPROVE_CODEX="$tmp/stale-codex"

"$SELECTED_DOCTOR" > "$tmp/doctor.out"
grep -Fxq 'codex-cli selected' "$tmp/doctor.out"
test "$(cat "$CODEX_PACKAGE_LOG/--version.args")" = '--version'
test "$(cat "$CODEX_PACKAGE_LOG/plugin.args")" = $'plugin\nlist\n--marketplace\nopenai-curated'

git init -q "$tmp/repo"
git -C "$tmp/repo" config user.name Fixture
git -C "$tmp/repo" config user.email fixture@example.invalid
printf base > "$tmp/repo/tracked"
git -C "$tmp/repo" add tracked
git -C "$tmp/repo" commit -qm base
cat > "$tmp/plan.md" <<EOF
- **Improve contract**: \`1.0.0-codex.17\`
\`\`\`json codex-improve-environment
{"version":1,"launcher":["env","PATH=$tmp/conflict:$FIXTURE_LAUNCHER_PATH:$PATH"],"probes":[]}
\`\`\`
EOF
"$SELECTED_IMPROVE" execute "$tmp/plan.md" "$tmp/repo" > "$tmp/improve.json"
jq -e '.outcome == "COMPLETE" and .report.status == "COMPLETE" and .report.steps == ["selected"]' "$tmp/improve.json" >/dev/null
mapfile -t exec_args < "$CODEX_PACKAGE_LOG/exec.args"
test "${exec_args[0]}" = exec
test "${exec_args[1]}" = --strict-config
test "${exec_args[2]}" = --ephemeral
test "${exec_args[3]}" = --json
grep -Fxq -- '--output-last-message' "$CODEX_PACKAGE_LOG/exec.args"
grep -Fxq -- '-C' "$CODEX_PACKAGE_LOG/exec.args"
test "${exec_args[${#exec_args[@]}-1]}" = '-'
test ! -e "$tmp/conflict.log"

if "$UNUSABLE_IMPROVE" execute "$tmp/plan.md" "$tmp/repo" > "$tmp/unusable.out" 2> "$tmp/unusable.err"; then
  echo 'unusable selected CLI unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'missing required command' "$tmp/unusable.err"
test ! -e "$tmp/conflict.log"
