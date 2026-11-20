{
  description = "Self-contained Codex Base plugin and Home Manager environment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-tools.url = "github:NixOS/nixpkgs/d5cc6833999746cffdfe0598f7bc801a57b887a9";
    mcp-nixos = { url = "github:utensils/mcp-nixos/v3.1.0"; inputs.nixpkgs.follows = "nixpkgs-tools"; };
    home-manager = { url = "github:nix-community/home-manager/release-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    mattpocock-skills = { url = "github:mattpocock/skills/d1478fcb140db0b93c0c8df17bcfd311844749d0"; flake = false; };
    shadcn-improve = { url = "github:shadcn/improve/03369ee6d7cafbfcecc4346539b05b3dc0a603bb"; flake = false; };
    stop-slop = { url = "github:hardikpandya/stop-slop/8da1f030185bdfe8471220585162991eaeb970e9"; flake = false; };
    ponytail = { url = "github:DietrichGebert/ponytail/7801d061243d7b753bad0e0b3c057cd250b11755"; flake = false; };
    playwright-cli = { url = "github:microsoft/playwright-cli/261206400b18cd0629a8b45dd14ea5488fcf261f"; flake = false; };
    codex-src = { url = "github:openai/codex/rust-v0.170.0"; flake = false; };
  };
  outputs = inputs@{ self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      srcRoot = self;
      generatedSkills = import ./nix/skills.nix {
        inherit pkgs srcRoot;
        mattPocockSkillsSource = inputs.mattpocock-skills;
        improveSource = inputs.shadcn-improve;
        stopSlopSource = inputs.stop-slop;
        ponytailSource = inputs.ponytail;
        playwrightCliSource = inputs.playwright-cli;
      };
      basePackages = import ./nix/packages.nix { inherit pkgs; toolPkgs = inputs.nixpkgs-tools.legacyPackages.${system}; mcpNixos = inputs.mcp-nixos; skills = generatedSkills; };
      sync = pkgs.writeShellApplication {
        name = "sync-vendored-skills";
        runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gitMinimal pkgs.nix ];
        text = ''exec bash ${./scripts/sync-vendored-skills} "$@"'';
      };
    in {
      homeManagerModules.default = import ./nix/home-manager.nix { inherit inputs self; };
      homeManagerModules.codexBase = self.homeManagerModules.default;
      packages.${system} = basePackages // { inherit sync; sync-vendored-skills = sync; generated-skills = generatedSkills; default = basePackages.codex; };
      apps.${system}.sync-vendored-skills = { type = "app"; program = "${sync}/bin/sync-vendored-skills"; };
      checks.${system} = import ./nix/checks.nix { inherit pkgs srcRoot generatedSkills inputs self; packages = basePackages; };
      devShells.${system}.default = pkgs.mkShell {
        CODEX_CONFIG_SCHEMA = "${inputs.codex-src}/codex-rs/core/config.schema.json";
        packages = [
          pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.git pkgs.curl pkgs.gnused
          pkgs.gnutar pkgs.jq pkgs.gh pkgs.shellcheck pkgs.actionlint pkgs.typos
          pkgs.rustc pkgs.cargo pkgs.rustfmt
          (pkgs.python3.withPackages (p: [ p.pyyaml p.pillow p.jsonschema ])) pkgs.librsvg basePackages.codex
        ];
      };
    };
}
