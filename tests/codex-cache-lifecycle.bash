#!/usr/bin/env bash
set -euo pipefail

if [[ $1 == --sandbox ]]; then
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    root=$(mktemp -d /var/tmp/codex-cache-lifecycle.XXXXXX)
else
    root=$(mktemp -d "${TMPDIR:-/tmp}/codex-cache-lifecycle.XXXXXX")
fi
trap 'status=$?; if (( status == 0 )); then chmod -R u+w -- "$root"; rm -rf -- "$root"; else echo "Fixture retained at $root" >&2; fi' EXIT
root=$(realpath -- "$root")

if [[ $1 == --sandbox ]]; then
    case "$root/" in
        "$(realpath /tmp)/"*|"$(realpath "$script_dir/..")/"*)
            echo "The sandbox fixture must be outside /tmp and the source tree" >&2
            exit 1
            ;;
    esac
    mkdir -p "$root/bootstrap" "$root/nix-conf" "$root/bootstrap-tmp"
    bootstrap_nix() {
        env -i PATH="$PATH" HOME="$root/bootstrap" TMPDIR="$root/bootstrap-tmp" \
            NIX_CONF_DIR="$root/nix-conf" nix --extra-experimental-features 'nix-command flakes' "$@"
    }
    fixture="$root/fixture.json"
    bootstrap_nix eval --impure --json --file "$script_dir/codex-cache-lifecycle.nix" \
        --apply "f: f { root = \"$root\"; sandbox = true; }" > "$fixture"
    dependency_paths=$(jq -er '.dependencies[]' "$fixture")
    mapfile -t dependencies <<< "$dependency_paths"
    bootstrap_nix build --no-link "${dependencies[@]}"
    tmpfiles_args=(--user)
else
    fixture=$1
    tmpfiles_args=("--root=$root")
fi

value() { jq -er "$1" "$fixture"; }
hm_shell=$(value .hmShell)
tmpfiles=$(value .tmpfiles)

load_home() {
    local home_expr=".homes[$1]" activation
    HOME=$(value "$home_expr.home")
    cache=$(value "$home_expr.cache")
    if [[ ${tmpfiles_args[0]} != --user ]]; then
        # Anchor path resolution below Nix's UID-mapped /build boundary.
        HOME="$root$HOME"
        cache="$root$cache"
        local invocation="$tmpfiles --user --create -" root_arg
        activation=$(value "$home_expr.activation")
        [[ $activation == *"$invocation"* ]]
        printf -v root_arg '%q' "${tmpfiles_args[0]}"
        printf '%s\n' "${activation/"$invocation"/"$tmpfiles $root_arg --create -"}" > "$root/activate"
    else
        jq -je "$home_expr.activation" "$fixture" > "$root/activate"
    fi
    export HOME
    mkdir -p "$HOME"
    value "$home_expr.tmpfiles" > "$root/login.conf"
}

activate() (
    # shellcheck source=/dev/null
    source "$hm_shell"
    # shellcheck source=/dev/null
    source "$root/activate"
)

check_cache() {
    test -d "$cache"
    test "$(stat -c '%a:%u:%g' "$cache")" = "700:$(id -u):$(id -g)"
}

unset DRY_RUN
load_home 0
DRY_RUN=1 activate
test ! -e "$cache"
activate
check_cache
mv -- "$cache" "$root/first-cache"

if [[ $1 == --sandbox ]]; then
    workspace="$root/workspace"
    sibling="${cache%/*}/sibling"
    mkdir -p "$workspace/tmp" "$workspace/tarball" "$sibling"
    codex=$(value .codex)
    nix=$(value .nix)
    bash_bin=$(value .bash)
    sandbox_path=$(value .sandboxPath)
    tar_bin=$(value .tar)

    run_codex() (
        cd "$workspace"
        env -i PATH="$sandbox_path" HOME="$HOME" CODEX_HOME="$HOME/.codex" \
            TMPDIR="$workspace/tmp" NIX_CONF_DIR="$root/nix-conf" \
            "$codex" -c 'sandbox_mode="workspace-write"' "$@"
    )

    # The sandboxed Bash expands the variables in this script.
    # shellcheck disable=SC2016
    run_codex sandbox -- "$bash_bin" -ec '
        : > workspace-marker
        test "$XDG_CACHE_HOME" = "$1"
        if mkdir -- "$XDG_CACHE_HOME"; then exit 1; fi
    ' bash "$cache"
    test -f "$workspace/workspace-marker"
    test ! -e "$cache"
fi

"$tmpfiles" "${tmpfiles_args[@]}" --create "$root/login.conf"
check_cache

if [[ $1 == --sandbox ]]; then
    printf '42\n' > "$workspace/tarball/default.nix"
    tarball="$workspace/local.tar"
    "$tar_bin" -cf "$tarball" -C "$workspace" tarball
    result=$(run_codex sandbox -- "$nix" --extra-experimental-features nix-command \
        eval --offline --store "local?root=$workspace/test-store" --impure \
        --expr "import (builtins.fetchTarball \"file://$tarball\")")
    test "$result" = 42

    # The sandboxed Bash expands the variables in this script.
    # shellcheck disable=SC2016
    run_codex sandbox -- "$bash_bin" -ec '
        : > "$XDG_CACHE_HOME/allowed"
        if : > "$1/denied"; then exit 1; fi
    ' bash "$sibling"
    test -f "$cache/allowed"
    # The sandboxed Bash expands the variables in this script.
    # shellcheck disable=SC2016
    run_codex -c 'sandbox_workspace_write.writable_roots=[]' sandbox -- "$bash_bin" -ec '
        test "$XDG_CACHE_HOME" = "$1"
        if : > "$XDG_CACHE_HOME/revoked"; then exit 1; fi
    ' bash "$cache"
fi

config="$HOME/.codex/config.toml"
cp -- "$config" "$root/before.toml"
printf 'keep\n' > "$cache/marker"
activate
test "$(cat "$cache/marker")" = keep
mv -- "$cache" "$root/removed-cache"
activate
check_cache
test ! -e "$cache/marker"
cmp "$root/before.toml" "$config"

first_cache=$cache
load_home 1
activate
check_cache
test "$first_cache" != "$cache"
test -d "$first_cache"
