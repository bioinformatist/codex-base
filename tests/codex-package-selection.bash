#!/usr/bin/env bash
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache"
export CODEX_PACKAGE_LOG="$tmp/log" NATIVE_FIXTURE_LOG="$tmp/native.jsonl"
mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$CODEX_PACKAGE_LOG" "$tmp/conflict"
chmod 700 "$XDG_STATE_HOME"
cat > "$tmp/conflict/codex" <<EOF2
#!/bin/sh
printf conflict >> '$tmp/conflict.log'
exit 97
EOF2
cat > "$tmp/conflict/mcp-nixos" <<'EOF2'
#!/bin/sh
exit 0
EOF2
chmod +x "$tmp/conflict/codex" "$tmp/conflict/mcp-nixos"
export PATH="$tmp/conflict:$PATH"
export CODEX_IMPROVE_CODEX="$tmp/stale-codex"

"$SELECTED_DOCTOR" > "$tmp/doctor.out"
grep -Fxq 'selected native doctor' "$tmp/doctor.out"
test "$(cat "$CODEX_PACKAGE_LOG/doctor.args")" = doctor
test "$(cat "$CODEX_PACKAGE_LOG/plugin.args")" = $'plugin\nlist\n--marketplace\nopenai-curated'

git init -q "$tmp/repo"
git -C "$tmp/repo" config user.name Fixture
git -C "$tmp/repo" config user.email fixture@example.invalid
printf base > "$tmp/repo/tracked"
git -C "$tmp/repo" add tracked
git -C "$tmp/repo" commit -qm base
cat > "$tmp/plan.md" <<EOF2
- **Improve contract**: \`1.0.0-codex.20\`
\`\`\`json codex-improve-environment
{"version":1,"launcher":["env","PATH=$tmp/conflict:$FIXTURE_LAUNCHER_PATH:$PATH"],"probes":[]}
\`\`\`
\`\`\`json codex-improve-routing
{"version":1,"lane":"standard","writePaths":["tracked"],"requiredEvidence":[]}
\`\`\`
\`\`\`json codex-improve-gates
{"version":1,"gates":[]}
\`\`\`
EOF2
# A FIFO keeps the selected App Server connected until its native root is frozen.
mkfifo "$tmp/control"
"$SELECTED_IMPROVE" session "$tmp/plan.md" "$tmp/repo" < "$tmp/control" > "$tmp/improve.jsonl" &
client=$!
exec 3> "$tmp/control"
printf '%s\n' '{"op":"close"}' >&3
wait "$client"
exec 3>&-
jq -se 'any(.[]; .ready.implementation.model == "gpt-6.1-sol") and any(.[]; .result.closed == true)' "$tmp/improve.jsonl" >/dev/null
test "$(cat "$CODEX_PACKAGE_LOG/--strict-config.args")" = $'--strict-config\napp-server'
test ! -e "$tmp/conflict.log"

if "$UNUSABLE_IMPROVE" session "$tmp/plan.md" "$tmp/repo" > "$tmp/unusable.out" 2> "$tmp/unusable.err"; then
  echo 'unusable selected CLI unexpectedly succeeded' >&2
  exit 1
fi
grep -Fq 'selected Codex is not executable' "$tmp/unusable.err"
test ! -e "$tmp/conflict.log"
