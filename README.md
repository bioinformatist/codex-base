# codex-base

`codex-base` leads with Improve: a self-contained Codex workflow for auditing,
planning, isolated implementation, independent review, recovery, and explicit
checkpoint handoff. The plugin also carries a curated set of portable Codex
skills. It is Codex-only.

The plugin is the portable surface. It supplies namespaced skills such as
`$codex-base:improve` and bundles Improve's runners with the skill. It does not
install Codex, global `AGENTS.md`, MCP servers or secrets, PATH commands, Node,
or Playwright CLI.

The Nix flake is the full-fidelity Linux surface. Its Home Manager module
installs Codex 0.147.0 and Code Mode Host, Node 24, Playwright CLI 0.1.17,
global guidance and rules, MCP routing, unnamespaced skills such as `$improve`,
and the `codex-improve-*` PATH commands.

This repository owns the Codex and Code Mode Host release pins. Its dedicated
maintenance workflow updates both binaries, the matching Codex source pin, and
this version statement together; see [updating](docs/updating.md) for the
operator contract.

## Plugin installation

After the repository is published, add its marketplace and install the plugin:

```console
codex plugin marketplace add https://github.com/bioinformatist/codex-base
codex plugin add codex-base@bioinformatist-codex
```

Plugin-only Improve runners require Linux with Bash, GNU coreutils, Git, GNU
sed, jq, and Codex on PATH. Plugin installation never writes Improve profiles
or setup state into `~/.codex`.

## Nix and Home Manager

Add the flake input, make its `nixpkgs` input follow your own, then import the
module:

```nix
{
  inputs.codex-base = {
    url = "github:bioinformatist/codex-base";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  imports = [ inputs.codex-base.homeManagerModules.default ];
  programs.codexBase.enable = true;
}
```

Build individual packages with `nix build .#codex` or run the vendoring parity
gate with `nix run .#sync-vendored-skills -- --check`.

See [architecture](docs/architecture.md) for ownership boundaries.
