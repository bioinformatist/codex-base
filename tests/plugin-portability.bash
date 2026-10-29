#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
packages="$repo/nix/packages.nix"

fail() {
  printf 'plugin portability: %s\n' "$1" >&2
  exit 1
}

for command in bash base64 cmp curl git jq od python3 sed sha256sum tar timeout xz readelf; do
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

: "${CODEX_BASE_RUNTIME_ARCHIVE:?set CODEX_BASE_RUNTIME_ARCHIVE to the archive to test}"
runtime_archive="$(readlink -f -- "$CODEX_BASE_RUNTIME_ARCHIVE")"
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
  skills/bend-proof/SKILL.md \
  skills/bend-proof/agents/openai.yaml \
  skills/bend-proof/references/minimal-example.md \
  skills/worktrunk/SKILL.md \
  skills/worktrunk/agents/openai.yaml \
  skills/worktrunk/LICENSE \
  skills/retro/SKILL.md \
  skills/retro/agents/openai.yaml \
  skills/prototype/SKILL.md \
  skills/prototype/agents/openai.yaml \
  skills/prototype/LOGIC.md \
  skills/prototype/UI.md; do
  [[ -f "$plugin_root/$relative" ]] || fail "installed plugin is missing $relative"
done
grep -Fqx '  allow_implicit_invocation: true' "$plugin_root/skills/bend-proof/agents/openai.yaml"
for skill in benchmark-checklist blast-radius deprecation-and-migration; do
  for file in SKILL.md agents/openai.yaml LICENSE; do test -f "$plugin_root/skills/$skill/$file"; done
  grep -Fqx '  allow_implicit_invocation: true' "$plugin_root/skills/$skill/agents/openai.yaml"
done
for skill in retro prototype; do
  grep -Fqx '  allow_implicit_invocation: false' "$plugin_root/skills/$skill/agents/openai.yaml" \
    || fail "installed $skill is not explicit-only"
done
grep -Fq '[LOGIC.md](LOGIC.md)' "$plugin_root/skills/prototype/SKILL.md" \
  || fail "installed prototype does not link LOGIC.md"
grep -Fq '[UI.md](UI.md)' "$plugin_root/skills/prototype/SKILL.md" \
  || fail "installed prototype does not link UI.md"
[[ ! -e "$plugin_root/skills/resolving-merge-conflicts" ]] \
  || fail "installed plugin contains resolving-merge-conflicts"

codex mcp list --json >"$root/mcp-defaults.json"
jq -e '
  length == 1
  and all(.[];
    .enabled == true
    and .transport.type == "streamable_http"
    and .transport.bearer_token_env_var == null
  )
  and any(.[];
    .name == "context7"
    and .transport.url == "https://mcp.context7.com/mcp"
  )
  and all(.[]; .name != "context7_auth")
' "$root/mcp-defaults.json" >/dev/null
codex mcp add context7 --url https://context7.example.invalid/mcp >/dev/null
codex mcp add context7_auth --url https://auth.example.invalid/mcp >/dev/null
codex mcp list --json >"$root/mcp-overridden.json"
jq -e 'length == 2
  and ([.[] | select(.name == "context7") | .transport.url] == ["https://context7.example.invalid/mcp"])
  and ([.[] | select(.name == "context7_auth") | .transport.url] == ["https://auth.example.invalid/mcp"])
  and all(.[]; .name != "mintlify_index")' "$root/mcp-overridden.json" >/dev/null

for relative in \
  SKILL.md \
  config/roles.json \
  references/executor-report.schema.json \
  references/review-verdict.schema.json \
  references/ponytail-core.md \
  scripts/codex-improve; do
  [[ -f "$improve/$relative" ]] || fail "installed plugin is missing skills/improve/$relative"
done

cmp "$repo/plugins/codex-base/skills/improve/config/roles.json" "$improve/config/roles.json"
if compgen -G "$improve/*.config.toml" >/dev/null; then
  fail "installed plugin contains runtime profile files"
fi

mkdir -p "$root/prefix" "$root/child-bin"
(cd "$(dirname "$runtime_archive")" && sha256sum --check SHA256SUMS)
tar -xzf "$runtime_archive" -C "$root/prefix"
cmp "$root/prefix/metadata.json" "$(dirname "$runtime_archive")/metadata.json"
jq -e '.version == 1 and .target == "x86_64-unknown-linux-musl" and .contract == "1.0.0-codex.19"
  and ((.distribution == "local-smoke" and .sourceCommit == null and .sourceTree == null)
       or (.distribution == "ci" and (.sourceCommit | test("^[0-9a-f]{40,64}$")) and (.sourceTree | test("^[0-9a-f]{40,64}$"))))' "$root/prefix/metadata.json" >/dev/null
for binary in codex-improve merge-codex-base-config; do
  readelf -h "$root/prefix/bin/$binary" | grep -Eq 'Machine:.*Advanced Micro Devices X86-64'
  if readelf -l "$root/prefix/bin/$binary" | grep -q INTERP || readelf -d "$root/prefix/bin/$binary" | grep -q NEEDED; then
    fail "$binary has a dynamic interpreter or shared dependency"
  fi
done
diff -ru "$repo/plugins/codex-base/skills/improve" "$root/prefix/share/codex-base/skills/improve"
test -f "$root/prefix/share/licenses/codex-base/LICENSE"
for path in runtime src tests target Cargo.toml Cargo.lock requirements-visual.txt; do
  test ! -e "$improve/$path"
done
# Only these host tools reach the native runtime and the shell model substitute.
for tool in git sh env cat basename sleep; do
  ln -s "$(command -v "$tool")" "$root/child-bin/$tool"
done
ln -s "$root/bin/wt" "$root/child-bin/wt"
PORTABLE_CHILD_PATH="$root/child-bin" python3 -B "$repo/tests/improve/test_runtime.py" "$root/prefix" "$improve"
PATH="$root/prefix/bin:$PATH" bash "$improve/scripts/codex-improve" --help >/dev/null
# The portable launcher's missing-runtime and self-recursion errors are explicit.
for tool in bash dirname readlink; do ln -s "$(command -v "$tool")" "$root/child-bin/$tool"; done
if PATH="$root/child-bin" bash "$improve/scripts/codex-improve" --help 2>"$root/missing.err"; then fail 'missing native runtime accepted'; fi
grep -Fq 'install the matching' "$root/missing.err"
ln -s "$improve/scripts/codex-improve" "$root/child-bin/codex-improve"
if PATH="$root/child-bin" bash "$improve/scripts/codex-improve" --help 2>"$root/recursive.err"; then fail 'recursive launcher accepted'; fi
grep -Fq 'resolves to this launcher' "$root/recursive.err"
printf 'non-Nix plugin portability passed with Codex %s\n' "$codex_version"
