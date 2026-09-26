{ pkgs, skills }:
let
  codexVersion = "0.157.1";
  codexHash = "sha256-6YwejgKOgTf6LSQVyC7Fjns3AaYn41VKrOWzyjFFSvI=";
  codexCodeModeHostHash = "sha256-NRb5uLvmvAbue9uSspOhfqsZSz8QubnqEMW4Oely1/w=";
  worktrunkVersion = "0.79.0";
  worktrunkHash = "sha256-uMGQsdZSNw759rj0aUotaDG1si9LeJ8EdhKq0ydkxs8=";
  codexAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = codexHash;
  };
  codeModeHostAsset = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-code-mode-host-x86_64-unknown-linux-musl.tar.gz";
    hash = codexCodeModeHostHash;
  };
  worktrunkAsset = pkgs.fetchurl {
    url = "https://github.com/max-sixty/worktrunk/releases/download/v${worktrunkVersion}/worktrunk-x86_64-unknown-linux-musl.tar.xz";
    hash = worktrunkHash;
  };
  worktrunk = pkgs.stdenvNoCC.mkDerivation {
    pname = "worktrunk";
    version = worktrunkVersion;
    src = worktrunkAsset;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.gnutar pkgs.xz ];
    installPhase = ''
      mkdir -p "$out/bin" "$out/share/licenses/worktrunk"
      tar -xJf "$src" --strip-components=1 -C "$out/bin" \
        worktrunk-x86_64-unknown-linux-musl/wt \
        worktrunk-x86_64-unknown-linux-musl/git-wt
      tar -xOJf "$src" worktrunk-x86_64-unknown-linux-musl/LICENSE \
        > "$out/share/licenses/worktrunk/LICENSE"
      chmod 755 "$out/bin/wt" "$out/bin/git-wt"
      chmod 644 "$out/share/licenses/worktrunk/LICENSE"
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/wt" --version | grep -F '${worktrunkVersion}'
      test -x "$out/bin/git-wt"
      test -s "$out/share/licenses/worktrunk/LICENSE"
    '';
    meta = { mainProgram = "wt"; platforms = [ "x86_64-linux" ]; license = [ pkgs.lib.licenses.mit pkgs.lib.licenses.asl20 ]; };
  };
in let self = rec {
  inherit worktrunk;
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
    exec ${pkgs.nodejs_24}/bin/npx -y @playwright/cli@0.1.19 "$@"
  '';
  codex-improve = pkgs.lib.makeOverridable ({ codex ? self.codex }: pkgs.writeShellApplication {
    name = "codex-improve";
    runtimeInputs = [ pkgs.python3 pkgs.gitMinimal worktrunk ];
    text = ''
      export CODEX_IMPROVE_CODEX=${pkgs.lib.escapeShellArg "${codex}/bin/codex"}
      exec python3 -B ${skills}/improve/scripts/codex-improve "$@"
    '';
  }) { };
  codex-doctor = pkgs.lib.makeOverridable ({ codex ? self.codex }: pkgs.writeShellApplication {
    name = "codex-doctor";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      ${codex}/bin/codex --version
      ${codex}/bin/codex plugin list --marketplace openai-curated | grep -E '^github@openai-curated[[:space:]]+installed, enabled' >/dev/null
      command -v mcp-nixos >/dev/null || { echo "mcp-nixos: missing from PATH" >&2; exit 1; }
    '';
  }) { };
}; in self
