#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
packages="$repo/nix/packages.nix"

fail() {
  printf 'plugin portability: %s\n' "$1" >&2
  exit 1
}

for command in bash base64 cmp curl git jq od python3 sed sha256sum tar timeout xz; do
  command -v "$command" >/dev/null || fail "$command is required"
done

assignment() {
  local name="$1"
  local values
  values="$(sed -n -E "s/^[[:space:]]*${name} = \"([^\"]+)\";[[:space:]]*$/\\1/p" "$packages")"
  [[ "$(printf '%s\n' "$values" | sed '/^$/d' | wc -l)" -eq 1 ]] \
    || fail "expected one $name assignment in nix/packages.nix"
  printf '%s\n' "$values"
}

codex_version="$(assignment codexVersion)"
codex_sri="$(assignment codexHash)"
worktrunk_version="$(assignment worktrunkVersion)"
worktrunk_sri="$(assignment worktrunkHash)"
[[ "$codex_sri" == sha256-* ]] || fail "codexHash is not an SRI SHA-256 digest"
[[ "$worktrunk_sri" == sha256-* ]] || fail "worktrunkHash is not an SRI SHA-256 digest"
codex_hex="$({ printf '%s' "${codex_sri#sha256-}" | base64 --decode; } | od -An -tx1 | tr -d ' \n')"
worktrunk_hex="$({ printf '%s' "${worktrunk_sri#sha256-}" | base64 --decode; } | od -An -tx1 | tr -d ' \n')"
[[ "$codex_hex" =~ ^[[:xdigit:]]{64}$ ]] || fail "cannot decode codexHash"
[[ "$worktrunk_hex" =~ ^[[:xdigit:]]{64}$ ]] || fail "cannot decode worktrunkHash"

root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home" "$root/codex"

asset="$root/codex.tar.gz"
curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --output "$asset" \
  "https://github.com/openai/codex/releases/download/rust-v${codex_version}/codex-x86_64-unknown-linux-musl.tar.gz"
printf '%s  %s\n' "$codex_hex" "$asset" | sha256sum --check --status \
  || fail "downloaded Codex asset does not match codexHash"
tar -xzf "$asset" -C "$root/bin"
mv "$root/bin/codex-x86_64-unknown-linux-musl" "$root/bin/codex"
chmod +x "$root/bin/codex"

worktrunk_asset="$root/worktrunk.tar.xz"
curl --fail --location --retry 3 --retry-all-errors --silent --show-error \
  --output "$worktrunk_asset" \
  "https://github.com/max-sixty/worktrunk/releases/download/v${worktrunk_version}/worktrunk-x86_64-unknown-linux-musl.tar.xz"
printf '%s  %s\n' "$worktrunk_hex" "$worktrunk_asset" | sha256sum --check --status \
  || fail "downloaded Worktrunk asset does not match worktrunkHash"
tar -xJf "$worktrunk_asset" --strip-components=1 -C "$root/bin" \
  worktrunk-x86_64-unknown-linux-musl/wt \
  worktrunk-x86_64-unknown-linux-musl/git-wt
chmod +x "$root/bin/wt" "$root/bin/git-wt"

export PATH="$root/bin:$PATH"
export HOME="$root/home"
export CODEX_HOME="$root/codex"
[[ "$(codex --version)" == "codex-cli $codex_version" ]] \
  || fail "downloaded Codex version does not match codexVersion"
[[ "$(wt --version)" == "wt v$worktrunk_version" ]] \
  || fail "downloaded Worktrunk version does not match worktrunkVersion"

codex plugin marketplace add "$repo" --json >"$root/marketplace-add.json"
codex plugin add codex-base@bioinformatist-codex --json >"$root/plugin-add.json"
plugin_root="$(jq -er '.installedPath | strings | select(length > 0)' "$root/plugin-add.json")"
improve="$plugin_root/skills/improve"

for relative in \
  .mcp.json \
  skills/adhx/SKILL.md \
  skills/adhx/agents/openai.yaml \
  skills/adhx/LICENSE \
  skills/docs-routing/SKILL.md \
  skills/docs-routing/agents/openai.yaml \
  skills/worktrunk/SKILL.md \
  skills/worktrunk/agents/openai.yaml \
  skills/worktrunk/LICENSE; do
  [[ -f "$plugin_root/$relative" ]] || fail "installed plugin is missing $relative"
done

codex mcp list --json >"$root/mcp-defaults.json"
jq -e '
  length == 2
  and all(.[];
    .enabled == true
    and .transport.type == "streamable_http"
    and .transport.bearer_token_env_var == null
  )
  and any(.[];
    .name == "context7"
    and .transport.url == "https://mcp.context7.com/mcp"
  )
  and any(.[];
    .name == "mintlify_index"
    and .transport.url == "https://index.mintlify.com/mcp"
  )
  and all(.[]; .name != "context7_auth")
' "$root/mcp-defaults.json" >/dev/null
codex mcp add mintlify_index --url https://mintlify.example.invalid/mcp >/dev/null
codex mcp add context7 --url https://context7.example.invalid/mcp >/dev/null
codex mcp list --json >"$root/mcp-overridden.json"
jq -e '
  length == 2
  and ([.[] | select(.name == "mintlify_index")] | length == 1)
  and ([.[] | select(.name == "context7")] | length == 1)
  and any(.[];
    .name == "mintlify_index"
    and .transport.url == "https://mintlify.example.invalid/mcp"
  )
  and any(.[];
    .name == "context7"
    and .transport.url == "https://context7.example.invalid/mcp"
  )
' "$root/mcp-overridden.json" >/dev/null

for relative in \
  SKILL.md \
  config/roles.json \
  references/executor-report.schema.json \
  references/review-verdict.schema.json \
  runtime/contracts.py \
  runtime/transport.py \
  runtime/git_worktree.py \
  scripts/codex-improve; do
  [[ -f "$improve/$relative" ]] || fail "installed plugin is missing skills/improve/$relative"
done

cmp "$repo/plugins/codex-base/skills/improve/config/roles.json" "$improve/config/roles.json"
for profile in \
  improve-scout improve-executor improve-executor-spark improve-executor-luna-low improve-executor-deep \
  improve-reviewer improve-elegance-reviewer; do
  [[ ! -e "$improve/$profile.config.toml" ]] \
    || fail "installed plugin contains legacy profile $profile.config.toml"
done

python3 -B "$improve/scripts/codex-improve" --help >/dev/null
CODEX_IMPROVE_SKILL_ROOT="$improve" python3 -B "$repo/tests/improve/test_runtime.py"

printf 'non-Nix plugin portability passed with Codex %s\n' "$codex_version"
