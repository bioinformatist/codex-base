#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
real_home="$HOME"
snapshot() {
  if [ -e "$real_home/.codex" ]; then stat -c '%d:%i:%s:%Y:%Z:%a:%F' "$real_home/.codex"; else printf 'absent\n'; fi
  if [ -e "$real_home/.codex/config.toml" ]; then stat -c '%d:%i:%s:%Y:%Z:%a:%F' "$real_home/.codex/config.toml"; else printf 'config-absent\n'; fi
}
before="$(snapshot)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/home" "$root/codex"
export HOME="$root/home" CODEX_HOME="$root/codex"
codex plugin marketplace add "$repo" --json >"$root/marketplace-add.json"
jq -e --arg repo "$repo" '
  .marketplaceName == "bioinformatist-codex"
  and .alreadyAdded == false
  and .installedRoot == $repo
' "$root/marketplace-add.json" >/dev/null
codex plugin marketplace list --json >"$root/marketplaces.json"
jq -e --arg repo "$repo" '
  .marketplaces | any(
    .name == "bioinformatist-codex"
    and .root == $repo
    and .marketplaceSource == {"source": $repo, "sourceType": "local"}
  )
' "$root/marketplaces.json" >/dev/null
codex plugin list --marketplace bioinformatist-codex --available --json >"$root/available.json"
jq -e '
  .installed == []
  and (.available | any(
    .name == "codex-base"
    and .pluginId == "codex-base@bioinformatist-codex"
    and .marketplaceName == "bioinformatist-codex"
    and .version == "0.1.0"
    and .installed == false
    and .enabled == false
  ))
' "$root/available.json" >/dev/null
codex plugin add codex-base@bioinformatist-codex --json >"$root/plugin-add.json"
jq -e '
  .name == "codex-base"
  and .pluginId == "codex-base@bioinformatist-codex"
  and .marketplaceName == "bioinformatist-codex"
  and .version == "0.1.0"
  and (.installedPath | type == "string" and length > 0)
' "$root/plugin-add.json" >/dev/null
codex plugin list --json >"$root/installed.json"
jq -e '
  .available == []
  and (.installed | any(
    .name == "codex-base"
    and .pluginId == "codex-base@bioinformatist-codex"
    and .marketplaceName == "bioinformatist-codex"
    and .version == "0.1.0"
    and .installed == true
    and .enabled == true
  ))
' "$root/installed.json" >/dev/null
codex plugin remove codex-base@bioinformatist-codex --json >"$root/plugin-remove.json"
jq -e '
  .name == "codex-base"
  and .pluginId == "codex-base@bioinformatist-codex"
  and .marketplaceName == "bioinformatist-codex"
' "$root/plugin-remove.json" >/dev/null
codex plugin marketplace remove bioinformatist-codex --json >"$root/marketplace-remove.json"
jq -e '
  .marketplaceName == "bioinformatist-codex"
  and .installedRoot == null
' "$root/marketplace-remove.json" >/dev/null
test "$(snapshot)" = "$before"
printf 'isolated plugin lifecycle passed\n'
