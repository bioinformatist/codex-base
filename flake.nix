{
  description = "Self-contained Codex Base plugin and Home Manager environment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-tools.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = { url = "github:nix-community/home-manager/release-26.05"; inputs.nixpkgs.follows = "nixpkgs"; };
    mattpocock-skills = { url = "github:mattpocock/skills/2ab958093e83e0ec752e6c1c5932da465bf23e0c"; flake = false; };
    shadcn-improve = { url = "github:shadcn/improve/03369ee6d7cafbfcecc4346539b05b3dc0a603bb"; flake = false; };
    stop-slop = { url = "github:hardikpandya/stop-slop/8da1f030185bdfe8471220585162991eaeb970e9"; flake = false; };
    ponytail = { url = "github:DietrichGebert/ponytail/v4.8.3"; flake = false; };
    playwright-cli = { url = "github:microsoft/playwright-cli/v0.1.17"; flake = false; };
    codex-src = { url = "github:openai/codex/rust-v0.150.1"; flake = false; };
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
      basePackages = import ./nix/packages.nix { inherit pkgs; skills = generatedSkills; };
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
    };
}
