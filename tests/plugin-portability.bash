#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
packages="$repo/nix/packages.nix"

fail() {
  printf 'plugin portability: %s\n' "$1" >&2
  exit 1
}

for command in bash base64 cmp curl git jq od sed sha256sum tar timeout; do
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
[[ "$codex_sri" == sha256-* ]] || fail "codexHash is not an SRI SHA-256 digest"
codex_hex="$({ printf '%s' "${codex_sri#sha256-}" | base64 --decode; } | od -An -tx1 | tr -d ' \n')"
[[ "$codex_hex" =~ ^[[:xdigit:]]{64}$ ]] || fail "cannot decode codexHash"

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

export PATH="$root/bin:$PATH"
export HOME="$root/home"
export CODEX_HOME="$root/codex"
[[ "$(codex --version)" == "codex-cli $codex_version" ]] \
  || fail "downloaded Codex version does not match codexVersion"

codex plugin marketplace add "$repo" --json >"$root/marketplace-add.json"
codex plugin add codex-base@bioinformatist-codex --json >"$root/plugin-add.json"
plugin_root="$(jq -er '.installedPath | strings | select(length > 0)' "$root/plugin-add.json")"
improve="$plugin_root/skills/improve"

for relative in \
  .mcp.json \
  skills/docs-routing/SKILL.md \
  skills/docs-routing/agents/openai.yaml; do
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
  scripts/codex-improve-exec \
  scripts/codex-improve-review \
  scripts/codex-improve-scout; do
  [[ -f "$improve/$relative" ]] || fail "installed plugin is missing skills/improve/$relative"
done

cmp "$repo/plugins/codex-base/skills/improve/config/roles.json" "$improve/config/roles.json"
for profile in \
  improve-scout improve-executor improve-executor-spark improve-executor-deep \
  improve-reviewer improve-elegance-reviewer; do
  [[ ! -e "$improve/$profile.config.toml" ]] \
    || fail "installed plugin contains legacy profile $profile.config.toml"
done

bash "$repo/tests/improve/compatibility.bash"
CODEX_IMPROVE_REAL_CODEX="$root/bin/codex" \
  CODEX_IMPROVE_EXEC_SCHEMA="$improve/references/executor-report.schema.json" \
  bash "$repo/tests/improve/exec-runner.bash" "$improve/scripts/codex-improve-exec"
CODEX_IMPROVE_REVIEW_SCHEMA="$improve/references/review-verdict.schema.json" \
  bash "$repo/tests/improve/review-runner.bash" "$improve/scripts/codex-improve-review"
bash "$repo/tests/improve/scout-runner.bash" "$improve/scripts/codex-improve-scout"

printf 'non-Nix plugin portability passed with Codex %s\n' "$codex_version"
