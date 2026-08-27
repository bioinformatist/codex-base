{ inputs, self }:
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.codexBase;
  system = pkgs.stdenv.hostPlatform.system;
  packages = self.packages.${system};
  toolPkgs = inputs.nixpkgs-tools.legacyPackages.${system};
  skillRoot = ../plugins/codex-base/skills;
  shellCacheHome = "${config.xdg.cacheHome}/codex-shell";
  writableRoots = lib.unique ([ shellCacheHome ] ++ map toString cfg.writableRoots);
  trustedProjects = lib.unique (map toString cfg.trustedProjects);
  githubTokenPath = if cfg.githubTokenFile == null then "" else toString cfg.githubTokenFile;
  context7KeyPath = if cfg.context7ApiKeyFile == null then "" else toString cfg.context7ApiKeyFile;
  githubMcp = pkgs.writeShellScriptBin "github-mcp-server" ''
    set -euo pipefail
    token=""
    token_file=${lib.escapeShellArg githubTokenPath}
    if [ -n "$token_file" ] && [ -r "$token_file" ]; then token="$(tr -d '\n' < "$token_file")"; fi
    if [ -z "$token" ] && [ -n "''${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then token="$GITHUB_PERSONAL_ACCESS_TOKEN"; fi
    if [ -z "$token" ]; then token="$(${pkgs.gh}/bin/gh auth token --hostname github.com 2>/dev/null || true)"; fi
    [ -n "$token" ] || { echo "GitHub token not found in configured file, environment, or gh auth" >&2; exit 1; }
    export GITHUB_PERSONAL_ACCESS_TOKEN="$token"
    exec ${toolPkgs.github-mcp-server}/bin/github-mcp-server stdio --toolsets context,issues,pull_requests,repos,users,orgs
  '';
  context7Auth = pkgs.writeShellScriptBin "context7-auth-mcp-server" ''
    set -euo pipefail
    key_file=${lib.escapeShellArg context7KeyPath}
    [ -r "$key_file" ] || { echo "Context7 API key file is not readable: $key_file" >&2; exit 1; }
    key="$(tr -d '\n' < "$key_file")"
    [ -n "$key" ] || { echo "Context7 API key file is empty: $key_file" >&2; exit 1; }
    export CONTEXT7_API_KEY="$key"
    exec ${toolPkgs.context7-mcp}/bin/context7-mcp
  '';
  trustedToml = lib.concatMapStringsSep "\n\n" (path: ''
    [projects."${path}"]
    trust_level = "trusted"
  '') trustedProjects;
  managedConfig = pkgs.writeText "codex-base-config.toml" ''
    model = "gpt-5.6-sol"
    model_reasoning_effort = "low"
    model_verbosity = "medium"
    plan_mode_reasoning_effort = "medium"
    personality = "pragmatic"
    sandbox_mode = "workspace-write"
    approval_policy = "on-request"
    web_search = "live"
    mcp_oauth_credentials_store = "file"

    [sandbox_workspace_write]
    writable_roots = ${builtins.toJSON writableRoots}

    [features]
    memories = true
    hooks = true

    [notice]
    hide_rate_limit_model_nudge = true

    [tui]
    status_line = ["model-with-reasoning", "current-dir", "context-remaining", "five-hour-limit", "weekly-limit", "thread-title"]

    [shell_environment_policy]
    set = { XDG_CACHE_HOME = "${shellCacheHome}" }

    ${trustedToml}

    [mcp_servers.github]
    command = "${githubMcp}/bin/github-mcp-server"

    [mcp_servers.mintlify_index]
    url = "https://index.mintlify.com"
    required = false
    startup_timeout_sec = 30
    tool_timeout_sec = 120

    [mcp_servers.context7]
    command = "${toolPkgs.context7-mcp}/bin/context7-mcp"
    required = false
    startup_timeout_sec = 30
    tool_timeout_sec = 120
    ${lib.optionalString (cfg.context7ApiKeyFile != null) ''

      [mcp_servers.context7_auth]
      command = "${context7Auth}/bin/context7-auth-mcp-server"
      required = false
      startup_timeout_sec = 30
      tool_timeout_sec = 120
    ''}

    [plugins."github@openai-curated"]
    enabled = true
  '';
  mergeConfig = pkgs.writeShellApplication {
    name = "merge-codex-base-config";
    runtimeInputs = [ (pkgs.python3.withPackages (p: [ p.tomlkit ])) ];
    text = ''
      python3 - "$@" <<'PY'
      import os, sys, tempfile
      from pathlib import Path
      import tomlkit
      managed_path, target_path = map(Path, sys.argv[1:3])
      managed = tomlkit.parse(managed_path.read_text())
      target = tomlkit.parse(target_path.read_text()) if target_path.exists() else tomlkit.document()
      def merge(dst, src):
          for key, value in src.items():
              if key in dst and hasattr(dst[key], "items") and hasattr(value, "items"):
                  merge(dst[key], value)
              else:
                  dst[key] = value
      merge(target, managed)
      target_path.parent.mkdir(parents=True, exist_ok=True)
      fd, tmp = tempfile.mkstemp(prefix=".config.toml.", dir=target_path.parent, text=True)
      try:
          with os.fdopen(fd, "w") as stream: stream.write(tomlkit.dumps(target))
          os.chmod(tmp, 0o600); os.replace(tmp, target_path)
      finally:
          if os.path.exists(tmp): os.unlink(tmp)
      PY
    '';
  };
  linkSkill = name: { source = skillRoot + "/${name}"; };
in {
  options.programs.codexBase = {
    enable = lib.mkEnableOption "the full Codex Base environment";
    trustedProjects = lib.mkOption { type = lib.types.listOf lib.types.path; default = [ ]; };
    writableRoots = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ (config.home.homeDirectory + "/.codex/memories") ];
    };
    githubTokenFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
    context7ApiKeyFile = lib.mkOption { type = lib.types.nullOr lib.types.path; default = null; };
    stopSlop.enable = lib.mkOption { type = lib.types.bool; default = true; };
    ponytail.enable = lib.mkOption { type = lib.types.bool; default = true; };
    mattPocockSkills.enable = lib.mkOption { type = lib.types.bool; default = true; };
    improve.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ packages.codex toolPkgs.mcp-nixos pkgs.nodejs_24 packages.playwright-cli packages.codex-doctor ]
      ++ lib.optionals cfg.improve.enable [ packages.codex-improve-exec packages.codex-improve-review packages.codex-improve-scout ];
    home.file = lib.mkMerge [
      {
        ".agents/skills/playwright-cli" = linkSkill "playwright-cli";
        ".agents/skills/stop-slop" = lib.mkIf cfg.stopSlop.enable (linkSkill "stop-slop");
        ".agents/skills/ponytail-review" = lib.mkIf (cfg.ponytail.enable || cfg.improve.enable) (linkSkill "ponytail-review");
        ".agents/skills/ponytail-audit" = lib.mkIf cfg.ponytail.enable (linkSkill "ponytail-audit");
        ".agents/skills/ponytail-debt" = lib.mkIf cfg.ponytail.enable (linkSkill "ponytail-debt");
        ".agents/skills/improve" = lib.mkIf cfg.improve.enable (linkSkill "improve");
        ".codex/AGENTS.md".source = ../config/AGENTS.md;
        ".codex/rules/baseline.rules".source = ../config/baseline.rules;
      }
      (lib.mkIf cfg.mattPocockSkills.enable (lib.genAttrs [
        ".agents/skills/diagnosing-bugs" ".agents/skills/tdd" ".agents/skills/codebase-design"
        ".agents/skills/grilling" ".agents/skills/handoff" ".agents/skills/domain-modeling"
        ".agents/skills/resolving-merge-conflicts"
        ".agents/skills/writing-for-agents" ".agents/skills/to-questionnaire"
      ] (path: linkSkill (baseNameOf path))))
    ];
    home.activation.codex-base-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      configFile="$HOME/.codex/config.toml"
      if [ -L "$configFile" ]; then rm -f "$configFile"; fi
      ${mergeConfig}/bin/merge-codex-base-config ${managedConfig} "$configFile"
    '';
  };
}
