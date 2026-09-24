#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

packages_file="$source_root/nix/packages.nix"

fail() {
  echo "codex release updater test: $*" >&2
  exit 1
}

assignment() {
  local name="$1"
  local matches value

  matches="$(sed -n -E "s/^[[:space:]]*${name} = \"([^\"]*)\";[[:space:]]*$/\\1/p" "$packages_file")"
  [[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)" -eq 1 ]] \
    || fail "expected exactly one nonempty ${name} assignment in nix/packages.nix"
  value="$(printf '%s\n' "$matches" | sed -n '1p')"
  [[ -n "$value" ]] || fail "${name} must not be empty"
  printf '%s\n' "$value"
}

current_version="$(assignment codexVersion)"
current_codex_hash="$(assignment codexHash)"
current_host_hash="$(assignment codexCodeModeHostHash)"

# Use arbitrary fixture digests for the current release; map them to actual hashes
# from the checked-out nix/packages.nix.
current_codex_hex="0246e2e773834e07f0fb5249ed6ebad12e4591e608f8c7bb97dd6a9690544c36"
current_host_hex="0146adfaac8363ec9fcdb5895f7624db5b2e8617a283887938b7fb97a1dd4356"
new_codex_hex="1111111111111111111111111111111111111111111111111111111111111111"
new_host_hex="2222222222222222222222222222222222222222222222222222222222222222"
new_codex_hash="sha256-ERERERERERERERERERERERERERERERERERERERERERE="
new_host_hash="sha256-IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI="
simulated_version="${current_version}-fixture"

make_repo() {
  local name="$1"
  local repo="$test_root/$name/repo"

  mkdir -p "$repo/nix" "$repo/scripts"
  cp "$source_root/README.md" "$source_root/README.zh-CN.md" \
    "$source_root/flake.nix" "$source_root/flake.lock" "$repo/"
  cp "$source_root/nix/packages.nix" "$repo/nix/"
  cp "$source_root/scripts/check-codex-release" "$source_root/scripts/update-codex-release" "$repo/scripts/"
  chmod -R u+rw "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Updater Test"
  git -C "$repo" config user.email "updater-test@example.invalid"
  git -C "$repo" add .
  git -C "$repo" commit -qm baseline
  printf '%s\n' "$repo"
}

make_fixture() {
  local path="$1"
  local tag="$2"
  local codex_digest="$3"
  local host_digest="$4"

  jq -n \
    --arg tag "$tag" \
    --arg codex_digest "$codex_digest" \
    --arg host_digest "$host_digest" \
    '{
      tag_name: $tag,
      assets: [
        {name: "codex-x86_64-unknown-linux-musl.tar.gz", digest: $codex_digest},
        {name: "codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz", digest: $host_digest}
      ]
    }' > "$path"
}

make_fake_nix() {
  local bin_dir="$1"
  local bash_path

  bash_path="$(command -v bash)"
  [[ -n "$bash_path" && -x "$bash_path" ]] || fail "cannot resolve executable bash path"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/nix" <<'EOF'
#!__BASH_PATH__
set -euo pipefail

if [[ "${1-}" == "hash" && "${2-}" == "convert" ]]; then
  digest="${!#}"
  case "$digest" in
    __CURRENT_CODEX_HEX__)
      echo "__CURRENT_CODEX_HASH__"
      ;;
    __CURRENT_HOST_HEX__)
      echo "__CURRENT_HOST_HASH__"
      ;;
    1111111111111111111111111111111111111111111111111111111111111111)
      echo 'sha256-ERERERERERERERERERERERERERERERERERERERERERE='
      ;;
    2222222222222222222222222222222222222222222222222222222222222222)
      echo 'sha256-IiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiIiI='
      ;;
    *)
      echo "unexpected digest: $digest" >&2
      exit 1
      ;;
  esac
  exit 0
fi

if [[ "${1-}" == "flake" && "${2-}" == "update" && "${3-}" == "codex-src" ]]; then
  ref="$(awk -F'\"' '/codex-src = {/ { print $2; exit }' flake.nix)"
  ref="${ref#github:openai/codex/}"
  jq --arg ref "$ref" '.nodes["codex-src"].original.ref = $ref' flake.lock > flake.lock.new
  mv flake.lock.new flake.lock
  if [[ -n "${FAKE_NIX_EXTRA_PATH:-}" ]]; then
    printf 'unexpected\n' > "$FAKE_NIX_EXTRA_PATH"
  fi
  exit 0
fi

echo "unexpected nix invocation: $*" >&2
exit 1
EOF
  sed -i \
    -e "s@#!__BASH_PATH__@#!${bash_path}@g" \
    -e "s@__CURRENT_CODEX_HASH__@${current_codex_hash}@g" \
    -e "s@__CURRENT_HOST_HASH__@${current_host_hash}@g" \
    -e "s@__CURRENT_CODEX_HEX__@${current_codex_hex}@g" \
    -e "s@__CURRENT_HOST_HEX__@${current_host_hex}@g" \
    "$bin_dir/nix"
  chmod +x "$bin_dir/nix"
}

run_update() {
  local repo="$1"
  local fixture="$2"
  local bin_dir="$3"

  PATH="$bin_dir:$PATH" bash "$repo/scripts/update-codex-release" --release-json "$fixture"
}

assert_clean() {
  local repo="$1"
  [[ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ]] \
    || fail "expected clean checkout in $repo"
}

test_current_is_noop() {
  local repo fixture bin_dir
  repo="$(make_repo current)"
  fixture="$test_root/current/release.json"
  bin_dir="$test_root/current/bin"
  make_fixture "$fixture" "rust-v${current_version}" "sha256:$current_codex_hex" "sha256:$current_host_hex"
  make_fake_nix "$bin_dir"

  run_update "$repo" "$fixture" "$bin_dir"
  assert_clean "$repo"
}

test_new_release_updates_all_surfaces() {
  local repo fixture bin_dir changed
  repo="$(make_repo newer)"
  fixture="$test_root/newer/release.json"
  bin_dir="$test_root/newer/bin"
  make_fixture "$fixture" "rust-v${simulated_version}" "sha256:$new_codex_hex" "sha256:$new_host_hex"
  make_fake_nix "$bin_dir"

  run_update "$repo" "$fixture" "$bin_dir"
  grep -Fqx "  codexVersion = \"${simulated_version}\";" "$repo/nix/packages.nix"
  grep -Fqx "  codexHash = \"$new_codex_hash\";" "$repo/nix/packages.nix"
  grep -Fqx "  codexCodeModeHostHash = \"$new_host_hash\";" "$repo/nix/packages.nix"
  grep -Fq "github:openai/codex/rust-v${simulated_version}" "$repo/flake.nix"
  [[ "$(jq -r '.nodes["codex-src"].original.ref' "$repo/flake.lock")" == "rust-v${simulated_version}" ]]
  grep -Fqx "The full Nix / Home Manager environment currently pins Codex ${simulated_version} and Code Mode Host." "$repo/README.md"
  grep -Fqx "Nix / Home Manager 完整环境当前固定 Codex ${simulated_version} 和 Code Mode Host。" "$repo/README.zh-CN.md"
  changed="$(git -C "$repo" diff --name-only | sort)"
  [[ "$changed" == $'README.md\nREADME.zh-CN.md\nflake.lock\nflake.nix\nnix/packages.nix' ]] \
    || fail "new release changed unexpected paths: $changed"
}

expect_metadata_failure() {
  local name="$1"
  local fixture_filter="$2"
  local repo fixture bin_dir
  repo="$(make_repo "$name")"
  fixture="$test_root/$name/release.json"
  bin_dir="$test_root/$name/bin"
  make_fixture "$fixture" "rust-v${simulated_version}" "sha256:$new_codex_hex" "sha256:$new_host_hex"
  jq "$fixture_filter" "$fixture" > "$fixture.tmp"
  mv "$fixture.tmp" "$fixture"
  make_fake_nix "$bin_dir"

  if run_update "$repo" "$fixture" "$bin_dir" >/dev/null 2>&1; then
    fail "$name metadata unexpectedly succeeded"
  fi
  assert_clean "$repo"
}

test_malformed_metadata_fails_closed() {
  expect_metadata_failure missing-host 'del(.assets[1])'
  expect_metadata_failure duplicate-codex '.assets += [.assets[0]]'
  expect_metadata_failure invalid-tag '.tag_name = "v0.148.0"'
  expect_metadata_failure unsafe-tag '.tag_name = "rust-v0.148.0&malformed"'
  expect_metadata_failure invalid-digest '.assets[0].digest = "sha256:not-hex"'
}

test_dirty_checkout_is_rejected() {
  local repo fixture bin_dir
  repo="$(make_repo dirty)"
  fixture="$test_root/dirty/release.json"
  bin_dir="$test_root/dirty/bin"
  make_fixture "$fixture" "rust-v${simulated_version}" "sha256:$new_codex_hex" "sha256:$new_host_hex"
  make_fake_nix "$bin_dir"
  printf 'dirty\n' >> "$repo/README.md"

  if run_update "$repo" "$fixture" "$bin_dir" >/dev/null 2>&1; then
    fail "dirty checkout unexpectedly succeeded"
  fi
  [[ "$(git -C "$repo" diff --name-only)" == README.md ]] \
    || fail "dirty checkout was mutated before rejection"
}

test_extra_path_is_rejected() {
  local repo fixture bin_dir
  repo="$(make_repo extra-path)"
  fixture="$test_root/extra-path/release.json"
  bin_dir="$test_root/extra-path/bin"
  make_fixture "$fixture" "rust-v${simulated_version}" "sha256:$new_codex_hex" "sha256:$new_host_hex"
  make_fake_nix "$bin_dir"

  if FAKE_NIX_EXTRA_PATH=unexpected.txt run_update "$repo" "$fixture" "$bin_dir" >/dev/null 2>&1; then
    fail "update touching an extra path unexpectedly succeeded"
  fi
  [[ -f "$repo/unexpected.txt" ]] || fail "fake nix did not exercise the extra-path case"
}

test_stable_sentence_is_required() {
  local language="$1"
  local case_name="$2"
  local repo fixture bin_dir readme sentence
  repo="$(make_repo "sentence-${language}-${case_name}")"
  fixture="$test_root/sentence-${language}-${case_name}/release.json"
  bin_dir="$test_root/sentence-${language}-${case_name}/bin"
  make_fixture "$fixture" "rust-v${simulated_version}" "sha256:$new_codex_hex" "sha256:$new_host_hex"
  make_fake_nix "$bin_dir"

  if [[ "$language" == en ]]; then
    readme="$repo/README.md"
    sentence="The full Nix / Home Manager environment currently pins Codex ${current_version} and Code Mode Host."
  else
    readme="$repo/README.zh-CN.md"
    sentence="Nix / Home Manager 完整环境当前固定 Codex ${current_version} 和 Code Mode Host。"
  fi

  case "$case_name" in
    missing)
      sed -i "\\|^${sentence}$|d" "$readme"
      ;;
    duplicate)
      printf '%s\n' "$sentence" >> "$readme"
      ;;
    malformed)
      sed -i "s|^${sentence}$|${sentence%?}!|" "$readme"
      ;;
  esac
  git -C "$repo" add "$readme"
  git -C "$repo" commit --amend --no-edit -qm baseline

  if run_update "$repo" "$fixture" "$bin_dir" >/dev/null 2>&1; then
    fail "$language $case_name stable sentence unexpectedly succeeded"
  fi
  assert_clean "$repo"
}

test_maintenance_workflow() {
  local workflow="$source_root/.github/workflows/maintenance-codex.yml"
  local fixture_dir="$test_root/maintenance-workflow"
  local bin_dir="$fixture_dir/bin"
  local bash_path
  mkdir -p "$bin_dir"
  bash_path="$(command -v bash)"

  # Assert GitHub wiring separately from the repository-owned shell behavior below.
  python3 - "$workflow" "$fixture_dir" <<'PY'
import pathlib
import sys
import yaml

workflow = yaml.safe_load(pathlib.Path(sys.argv[1]).read_text())
output = pathlib.Path(sys.argv[2])
triggers = workflow.get("on", workflow.get(True))  # PyYAML also accepts YAML 1.1's boolean key.
assert "workflow_dispatch" in triggers
assert triggers["schedule"] == [{"cron": "17 */4 * * *"}]
steps = workflow["jobs"]["update"]["steps"]
named = {step.get("name"): (index, step) for index, step in enumerate(steps)}
require = named["Require maintenance credential"][1]
checkout = next(step for step in steps if step.get("uses") == "actions/checkout@v4")
detect = named["Detect changes"][1]
cleanup_index, cleanup = named["Close stale pull request and branch"]
verify_index, verify = named["Verify update"]
publish_index, publish = named["Create or update maintenance pull request"]
ready_index, ready = named["Ready and auto squash maintenance pull request"]
assert require["env"]["MAINTENANCE_PAT"] == "${{ secrets.MAINTENANCE_PAT }}"
assert checkout["with"]["ref"] == "main"
assert checkout["with"]["token"] == "${{ secrets.MAINTENANCE_PAT }}"
assert workflow["jobs"]["update"]["env"]["MAINTENANCE_BRANCH"] == "maint/codex"
assert detect["id"] == "changes"
assert cleanup["if"] == "steps.changes.outputs.changed == 'false'"
assert cleanup["env"]["GH_TOKEN"] == "${{ secrets.MAINTENANCE_PAT }}"
assert verify["if"] == publish["if"] == ready["if"] == "steps.changes.outputs.changed == 'true'"
# GitHub's default success() applies to these step conditions when no status function is present.
assert cleanup_index < verify_index < publish_index < ready_index
assert "continue-on-error" not in verify
assert "continue-on-error" not in workflow["jobs"]["update"]
assert publish["id"] == "cpr"
assert publish["uses"] == "peter-evans/create-pull-request@5f6978faf089d4d20b00c7766989d076bb2fc7f1"
settings = publish["with"]
assert settings["token"] == "${{ secrets.MAINTENANCE_PAT }}"
assert settings["branch"] == "maint/codex" and settings["base"] == "main"
assert settings["add-paths"].splitlines() == [
    "README.md", "README.zh-CN.md", "flake.nix", "flake.lock", "nix/packages.nix"
]
bot = "github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"
assert settings["author"] == settings["committer"] == bot
assert ready["env"]["GH_TOKEN"] == "${{ secrets.MAINTENANCE_PAT }}"
assert "${{ steps.cpr.outputs.pull-request-number }}" in ready["run"]
assert "gh pr merge \"$pr_number\" --repo \"$GITHUB_REPOSITORY\" --auto --squash" in ready["run"]

(output / "cleanup.bash").write_text(cleanup["run"])
(output / "verify.bash").write_text(verify["run"])
# GitHub resolves the Action output before running the shell step.
(output / "ready.bash").write_text(ready["run"].replace(
    "${{ steps.cpr.outputs.pull-request-number }}", "${PR_NUMBER}"
))
PY

  cat > "$bin_dir/gh" <<'EOF'
#!__BASH_PATH__
set -euo pipefail
printf 'gh %s\n' "$*" >> "$FAKE_LOG"
case "$1 $2" in
  'pr list') printf '42\n' ;;
  'pr view') printf '%s\n' "$FAKE_IS_DRAFT" ;;
esac
EOF
  cat > "$bin_dir/git" <<'EOF'
#!__BASH_PATH__
set -euo pipefail
printf 'git %s\n' "$*" >> "$FAKE_LOG"
[[ "$1" == ls-remote || "$1" == push ]]
EOF
  cat > "$bin_dir/nix" <<'EOF'
#!__BASH_PATH__
set -euo pipefail
printf 'nix %s\n' "$*" >> "$FAKE_LOG"
[[ "$1 $2" != 'flake check' ]]
EOF
  sed -i "s@__BASH_PATH__@${bash_path}@" "$bin_dir/gh" "$bin_dir/git" "$bin_dir/nix"
  chmod +x "$bin_dir/gh" "$bin_dir/git" "$bin_dir/nix"

  export PATH="$bin_dir:$PATH" FAKE_LOG="$fixture_dir/calls" \
    GITHUB_REPOSITORY=example/repo MAINTENANCE_BRANCH=maint/codex \
    PR_NUMBER=42 FAKE_IS_DRAFT=true

  # No changes: run the actual cleanup snippet against fake gh/git.
  bash "$fixture_dir/cleanup.bash"
  printf '%s\n' \
    'gh pr list --repo example/repo --state open --base main --head maint/codex --json number --jq .[].number' \
    'gh pr close 42 --repo example/repo --comment Closing because the pinned Codex release is current.' \
    'git ls-remote --exit-code --heads origin refs/heads/maint/codex' \
    'git push origin --delete maint/codex' > "$fixture_dir/expected"
  cmp -s "$fixture_dir/expected" "$FAKE_LOG" || fail "no-change cleanup did not close the PR and delete the branch"

  # Failed verification exits before the statically gated publish step.
  : > "$FAKE_LOG"
  if bash -e -o pipefail "$fixture_dir/verify.bash" >/dev/null 2>&1; then
    fail "failed verification unexpectedly succeeded"
  fi
  printf '%s\n' 'nix run .#sync-vendored-skills -- --check' \
    'nix flake check --allow-import-from-derivation' > "$fixture_dir/expected"
  cmp -s "$fixture_dir/expected" "$FAKE_LOG" || fail "verification did not stop at the failed check"

  # Existing draft becomes ready; the same Action output is used on the next update.
  : > "$FAKE_LOG"
  bash "$fixture_dir/ready.bash"
  FAKE_IS_DRAFT=false bash "$fixture_dir/ready.bash"
  printf '%s\n' \
    'gh pr view 42 --repo example/repo --json isDraft --jq .isDraft' \
    'gh pr ready 42 --repo example/repo' \
    'gh pr merge 42 --repo example/repo --auto --squash' \
    'gh pr view 42 --repo example/repo --json isDraft --jq .isDraft' \
    'gh pr merge 42 --repo example/repo --auto --squash' > "$fixture_dir/expected"
  cmp -s "$fixture_dir/expected" "$FAKE_LOG" || fail "draft readiness or repeated auto squash differed"
}

test_current_is_noop
test_new_release_updates_all_surfaces
test_malformed_metadata_fails_closed
test_dirty_checkout_is_rejected
test_extra_path_is_rejected
for language in en zh; do
  for case_name in missing duplicate malformed; do
    test_stable_sentence_is_required "$language" "$case_name"
  done
done
test_maintenance_workflow

echo "Codex release updater tests passed."
