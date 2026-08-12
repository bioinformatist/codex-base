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
  cp "$source_root/README.md" "$source_root/flake.nix" "$source_root/flake.lock" "$repo/"
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
  grep -Fq "installs Codex ${simulated_version} and Code Mode Host" "$repo/README.md"
  changed="$(git -C "$repo" diff --name-only | sort)"
  [[ "$changed" == $'README.md\nflake.lock\nflake.nix\nnix/packages.nix' ]] \
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

test_current_is_noop
test_new_release_updates_all_surfaces
test_malformed_metadata_fails_closed
test_dirty_checkout_is_rejected
test_extra_path_is_rejected

echo "Codex release updater tests passed."
