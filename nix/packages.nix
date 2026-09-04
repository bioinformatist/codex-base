{ pkgs, skills }:
let
  codexVersion = "0.153.2";
  codexHash = "sha256-6M0RYAcfcl0qEMq4EHPdaBj8iwljchJdJ+9uZv3wl54=";
  codexCodeModeHostHash = "sha256-F3pFB7nMf5fxE6wDRpezn2pxqHaovVCP9tf1LzQuvko=";
  codexAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = codexHash;
  };
  codeModeHostAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
    hash = codexCodeModeHostHash;
  };
  runtimeInputs = [ pkgs.bash pkgs.coreutils pkgs.gitMinimal pkgs.gnused pkgs.jq ];
  mkRunner = name: pkgs.writeShellApplication {
    inherit name runtimeInputs;
    text = ''exec bash ${skills}/improve/scripts/${name} "$@"'';
  };
in rec {
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
    exec ${pkgs.nodejs_24}/bin/npx -y @playwright/cli@0.1.17 "$@"
  '';
  codex-improve-exec = mkRunner "codex-improve-exec";
  codex-improve-review = mkRunner "codex-improve-review";
  codex-improve-scout = mkRunner "codex-improve-scout";
  codex-doctor = pkgs.writeShellApplication {
    name = "codex-doctor";
    runtimeInputs = [ codex ];
    text = ''
      codex --version
      codex plugin list --marketplace openai-curated | grep -E '^github@openai-curated[[:space:]]+installed, enabled' >/dev/null
      command -v mcp-nixos >/dev/null || { echo "mcp-nixos: missing from PATH" >&2; exit 1; }
    '';
  };
}
