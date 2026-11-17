{ pkgs, toolPkgs, mcpNixos, skills }:
let
  codexVersion = "0.169.0";
  codexHash = "sha256-mvTXUfzhg/rt6mKUN9UlLb9FjusEEwz0+XvoRGIeqYU=";
  codexCodeModeHostHash = "sha256-y+1qjSXoJoeSt1d2f7x21MYuhLz47kpj+XVH8N46rOs=";
  codexAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = codexHash;
  };
  codeModeHostAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
    hash = codexCodeModeHostHash;
  };
in let self = rec {
  github-mcp-server = toolPkgs.github-mcp-server.overrideAttrs (old: {
    version = "2.1.0";
    src = toolPkgs.fetchFromGitHub {
      owner = "github"; repo = "github-mcp-server"; tag = "v2.1.0";
      hash = "sha256-yMwLpdl8Zw+sAn+6IoFGdSHD2pjENYVrLrSWOzHJCLw=";
    };
    # Remove this override when nixpkgs-tools supplies GitHub MCP 2.1.0 or newer.
    vendorHash = "sha256-2RfJhHB5dL8fHZY1gunVRAGGA3pOAA1YOeyi40Tfovc=";
    ldflags = map (flag: builtins.replaceStrings [ old.version ] [ "2.1.0" ] flag) old.ldflags;
  });
  context7-mcp = toolPkgs.context7-mcp;
  mcp-nixos = mcpNixos.lib.mkMcpNixos { inherit pkgs; };
  codex = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex";
    version = codexVersion;
    src = codexAsset;
    sourceRoot = ".";
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    unpackPhase = ''
      tar -xzf "$src"
      tar -xzf ${codeModeHostAsset}
    '';
    installPhase = ''
      mkdir -p "$out/bin" "$out/libexec"
      install -m755 codex-x86_64-unknown-linux-musl "$out/libexec/codex"
      install -m755 codex-code-mode-host-x86_64-unknown-linux-musl "$out/libexec/codex-code-mode-host"
      makeBinaryWrapper "$out/libexec/codex" "$out/bin/codex" \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.ripgrep pkgs.bubblewrap pkgs.nixfmt ]}
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      test "$("$out/libexec/codex" --version | sed -n 's/^codex-cli //p')" = "${codexVersion}"
      test -x "$out/libexec/codex-code-mode-host"
      "$out/libexec/codex-code-mode-host" --help >/dev/null
    '';
    meta = { mainProgram = "codex"; platforms = [ "x86_64-linux" ]; };
  };
  playwright-cli = pkgs.writeShellScriptBin "playwright-cli" ''
    export PATH="${pkgs.nodejs_24}/bin:$PATH"
    export npm_config_cache="''${XDG_CACHE_HOME:-$HOME/.cache}/npm"
    exec ${pkgs.nodejs_24}/bin/npx -y @playwright/cli@0.1.24 "$@"
  '';
  codex-base-runtime = pkgs.pkgsStatic.rustPlatform.buildRustPackage {
    pname = "codex-base-runtime";
    version = "0.20.0";
    src = pkgs.lib.fileset.toSource {
      root = ../.;
      fileset = pkgs.lib.fileset.unions [ ../Cargo.toml ../Cargo.lock ../src/improve ../src/config-merge ../plugins/codex-base/skills/improve ];
    };
    cargoLock.lockFile = ../Cargo.lock;
    cargoBuildFlags = [ "--workspace" ];
    doCheck = false;
    postInstall = ''
      mkdir -p "$out/share/codex-base/skills/improve" "$out/share/licenses/codex-base"
      cp -R ${skills}/improve/. "$out/share/codex-base/skills/improve/"
      cp ${../LICENSE} "$out/share/licenses/codex-base/LICENSE"
    '';
    meta = { mainProgram = "codex-improve"; platforms = [ "x86_64-linux" ]; license = pkgs.lib.licenses.mit; };
  };
  merge-codex-base-config = pkgs.runCommand "merge-codex-base-config" { meta.mainProgram = "merge-codex-base-config"; } ''
    mkdir -p "$out/bin"
    ln -s ${self.codex-base-runtime}/bin/merge-codex-base-config "$out/bin/merge-codex-base-config"
  '';
  codex-improve = pkgs.lib.makeOverridable ({ codex ? self.codex }: pkgs.writeShellApplication {
    name = "codex-improve";
    runtimeInputs = [ pkgs.gitMinimal pkgs.coreutils ];
    text = ''
      export CODEX_IMPROVE_CODEX=${pkgs.lib.escapeShellArg "${codex}/bin/codex"}
      exec ${self.codex-base-runtime}/bin/codex-improve "$@"
    '';
  }) { };
  codex-doctor = pkgs.lib.makeOverridable ({ codex ? self.codex }: pkgs.writeShellApplication {
    name = "codex-doctor";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      ${codex}/bin/codex doctor "$@"
      ${codex}/bin/codex plugin list --marketplace openai-curated | grep -E '^github@openai-curated[[:space:]]+installed, enabled' >/dev/null
      command -v mcp-nixos >/dev/null || { echo "mcp-nixos: missing from PATH" >&2; exit 1; }
    '';
  }) { };
}; in self
