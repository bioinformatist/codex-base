{ pkgs, srcRoot, generatedSkills, packages, inputs, self }:
let
  mkTest = name: inputs': text: pkgs.runCommand name { nativeBuildInputs = inputs'; } text;
  shellTools = [ pkgs.bash pkgs.coreutils pkgs.gitMinimal pkgs.gnused pkgs.jq pkgs.shellcheck-minimal ];
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  instructionSentinel = "Appended instruction sentinel.";
  pluginValidator = "${inputs.codex-src}/codex-rs/skills/src/assets/samples/plugin-creator/scripts/validate_plugin.py";
  skillValidator = "${inputs.codex-src}/codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py";
  hm = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default {
      home.username = "tester"; home.homeDirectory = "/home/tester"; home.stateVersion = "26.05";
      programs.codexBase.enable = true;
      programs.codexBase.trustedProjects = [ /tmp/project /tmp/project ];
      programs.codexBase.writableRoots = [ /tmp/writable /tmp/writable ];
      programs.codexBase.githubTokenFile = /run/secrets/github;
      programs.codexBase.context7ApiKeyFile = /run/secrets/context7;
    } ];
  };
  hmOff = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default {
      home.username = "tester"; home.homeDirectory = "/home/tester"; home.stateVersion = "26.05";
      programs.codexBase.enable = true;
      programs.codexBase.stopSlop.enable = false;
      programs.codexBase.ponytail.enable = false;
      programs.codexBase.mattPocockSkills.enable = false;
      programs.codexBase.improve.enable = false;
      programs.codexBase.extraInstructions = instructionSentinel;
    } ];
  };
  selectedCodex = pkgs.writeShellScriptBin "codex" ''
    printf '%s\n' "$@" > "$CODEX_PACKAGE_LOG/''${1-unknown}.args"
    case "''${1-}" in
      --version) echo 'codex-cli selected' ;;
      plugin) echo 'github@openai-curated installed, enabled' ;;
      exec)
        echo '{"type":"thread.started"}'
        echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":2,"output_tokens":3}}'
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output-last-message" ]; then
            printf '%s\n' '{"status":"COMPLETE","steps":["selected"],"stoppedBecause":null,"filesChanged":[],"notes":[]}' > "$2"
            break
          fi
          shift
        done
        ;;
      *) exit 90 ;;
    esac
  '';
  unusableCodex = pkgs.runCommand "unusable-codex" { } ''
    mkdir -p "$out/bin"
    printf '#!/bin/sh\nexit 0\n' > "$out/bin/codex"
    chmod 644 "$out/bin/codex"
  '';
  hmSelected = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default {
      home.username = "tester"; home.homeDirectory = "/home/tester"; home.stateVersion = "26.05";
      programs.codexBase.enable = true;
      programs.codexBase.package = selectedCodex;
    } ];
  };
  hmSelectedOff = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ self.homeManagerModules.default {
      home.username = "tester"; home.homeDirectory = "/home/tester"; home.stateVersion = "26.05";
      programs.codexBase.enable = true;
      programs.codexBase.package = selectedCodex;
      programs.codexBase.improve.enable = false;
    } ];
  };
  selectedImprove = packages.codex-improve.override { codex = selectedCodex; };
  selectedDoctor = packages.codex-doctor.override { codex = selectedCodex; };
  unusableImprove = packages.codex-improve.override { codex = unusableCodex; };
  selectedClosure = pkgs.closureInfo { rootPaths = [ hmSelected.activationPackage ]; };
  files = hm.config.home.file;
  filesOff = hmOff.config.home.file;
  activation = hm.config.home.activation.codex-base-config.data;
  hmClosure = pkgs.closureInfo { rootPaths = [ hm.activationPackage ]; };
in {
  codex-package-selection =
    assert hm.config.programs.codexBase.package == packages.codex;
    assert builtins.elem packages.codex hm.config.home.packages;
    assert builtins.elem packages.codex-improve hm.config.home.packages;
    assert builtins.elem packages.codex-doctor hm.config.home.packages;
    assert builtins.elem selectedCodex hmSelected.config.home.packages;
    assert builtins.elem selectedImprove hmSelected.config.home.packages;
    assert builtins.elem selectedDoctor hmSelected.config.home.packages;
    assert builtins.elem selectedCodex hmSelectedOff.config.home.packages;
    assert builtins.elem selectedDoctor hmSelectedOff.config.home.packages;
    assert !(builtins.elem selectedImprove hmSelectedOff.config.home.packages);
    assert !(builtins.elem packages.codex hmSelected.config.home.packages);
    mkTest "codex-package-selection" (shellTools ++ [ pkgs.jq selectedImprove selectedDoctor ]) ''
      grep -Fxq ${selectedCodex} ${selectedClosure}/store-paths
      ! grep -Fxq ${packages.codex} ${selectedClosure}/store-paths
      export SELECTED_DOCTOR=${selectedDoctor}/bin/codex-doctor
      export SELECTED_IMPROVE=${selectedImprove}/bin/codex-improve
      export UNUSABLE_IMPROVE=${unusableImprove}/bin/codex-improve
      export FIXTURE_LAUNCHER_PATH=${pkgs.lib.makeBinPath [ pkgs.python3 pkgs.gitMinimal packages.worktrunk pkgs.coreutils ]}
      bash ${srcRoot}/tests/codex-package-selection.bash
      touch $out
    '';
  generated-plugin-parity = mkTest "generated-plugin-parity" shellTools ''
    diff -ruN --no-dereference ${generatedSkills} ${srcRoot}/plugins/codex-base/skills
    touch $out
  '';
  plugin-schema = mkTest "plugin-schema" [ python pkgs.coreutils pkgs.gnugrep pkgs.jq ] ''
    python ${pluginValidator} ${srcRoot}/plugins/codex-base
    for skill in ${srcRoot}/plugins/codex-base/skills/*; do python ${skillValidator} "$skill"; done
    cmp ${inputs.adhx}/LICENSE ${generatedSkills}/adhx/LICENSE
    cmp ${inputs.adhx}/LICENSE ${srcRoot}/plugins/codex-base/licenses/adhx-MIT.txt
    test "$(jq -r '.sources[] | select(.name == "adhx") | .revision' ${srcRoot}/vendor/sources.json)" = "2dafb9c221398372d08f8dc75e857e801089f6b1"
    test "$(jq -r '.sources[] | select(.name == "adhx") | .includedPaths | join(" ")' ${srcRoot}/vendor/sources.json)" = "skills/adhx LICENSE"
    grep -Fqx 'name: adhx' ${generatedSkills}/adhx/SKILL.md
    grep -Fq 'allow_implicit_invocation: true' ${generatedSkills}/adhx/agents/openai.yaml
    grep -Fq 'Use $adhx ' ${generatedSkills}/adhx/agents/openai.yaml
    python - <<'PY'
    import json
    from pathlib import Path

    plugin = Path('${srcRoot}/plugins/codex-base')
    manifest = json.loads((plugin / '.codex-plugin/plugin.json').read_text())
    servers = json.loads((plugin / '.mcp.json').read_text())
    expected = {
        'mcpServers': {
            'mintlify_index': {
                'type': 'http',
                'url': 'https://index.mintlify.com/mcp',
            },
            'context7': {
                'type': 'http',
                'url': 'https://mcp.context7.com/mcp',
            },
        },
    }
    assert manifest['mcpServers'] == './.mcp.json'
    assert servers == expected
    PY
    touch $out
  '';
  stale-wording = mkTest "stale-wording" shellTools ''
    ! grep -R -n -E '(/codebase-design|/grilling|/domain-modeling|/improve-codebase-architecture|Agent tool|subagent_type|Claude|claude|CLAUDE|SendMessage|spin up parallel sub-agents|show --annotate +# ask the user)' ${generatedSkills}
    ! grep -R -n -E '(/home/[[:alnum:]_.-]+|/nix/store/|BEGIN (RSA |OPENSSH )?PRIVATE KEY|api[_-]?key[[:space:]]*=|token[[:space:]]*=)' \
      ${srcRoot}/README.md ${srcRoot}/README.zh-CN.md ${srcRoot}/CONTRIBUTING.md \
      ${srcRoot}/.github/PULL_REQUEST_TEMPLATE.md ${srcRoot}/docs \
      ${srcRoot}/plugins/codex-base/.codex-plugin/plugin.json \
      ${srcRoot}/plugins/codex-base/assets ${srcRoot}/vendor
    test "$(find ${srcRoot}/plugins/codex-base/licenses -type f | wc -l)" -eq 7
    touch $out
  '';
  mattpocock-skills = mkTest "mattpocock-skills-contract" shellTools ''
    expected='codebase-design diagnosing-bugs domain-modeling resolving-merge-conflicts tdd grilling handoff wait-what writing-for-agents to-questionnaire'
    actual=$(jq -r '.sources[] | select(.name == "mattpocock-skills") | .includedPaths[] | split("/")[-1]' ${srcRoot}/vendor/sources.json | paste -sd ' ' -)
    test "$actual" = "$expected"
    for skill in $expected; do test -d "${generatedSkills}/$skill"; done

    grep -Fq 'allow_implicit_invocation: true' ${generatedSkills}/writing-for-agents/agents/openai.yaml
    grep -Fq 'allow_implicit_invocation: false' ${generatedSkills}/to-questionnaire/agents/openai.yaml
    grep -Fq 'allow_implicit_invocation: false' ${generatedSkills}/wait-what/agents/openai.yaml
    test "$(jq -r '.sources[] | select(.name == "ponytail") | .patched' ${srcRoot}/vendor/sources.json)" = true
    touch $out
  '';
  shellcheck = mkTest "all-shell-scripts" shellTools ''
    while IFS= read -r file; do
      case "$file" in
        *.bash|*.sh) ;;
        *)
          IFS= read -r first_line < "$file" || true
          case "$first_line" in
            '#!'*bash*|'#!'*/sh*) ;;
            *) continue ;;
          esac ;;
      esac
      bash -n "$file"
      shellcheck "$file"
    done < <(find ${srcRoot}/scripts ${srcRoot}/src ${srcRoot}/tests -type f \( -name '*.bash' -o -name '*.sh' -o -perm -0100 \))
    touch $out
  '';
  codex-release-consistency = mkTest "codex-release-consistency" shellTools ''
    bash ${srcRoot}/scripts/check-codex-release
    touch $out
  '';
  codex-release-updater = mkTest "codex-release-updater-tests" (shellTools ++ [ python ]) ''
    bash ${srcRoot}/tests/codex-release-updater.bash
    touch $out
  '';
  workflow-lint = mkTest "workflow-lint" [ pkgs.actionlint pkgs.gnugrep ] ''
    actionlint ${srcRoot}/.github/workflows/*.yml
    workflow=${srcRoot}/.github/workflows/maintenance-codex.yml
    test "$(grep -Fxc '      - uses: actions/checkout@v4' "$workflow")" -eq 1
    grep -F -A 5 '      - uses: actions/checkout@v4' "$workflow" \
      | grep -Fqx '          ref: main'
    grep -Fq 'peter-evans/create-pull-request@5f6978faf089d4d20b00c7766989d076bb2fc7f1' "$workflow"
    touch $out
  '';
  typos = mkTest "public-docs-typos" [ pkgs.typos ] ''
    typos --config ${srcRoot}/typos.toml \
      ${srcRoot}/README.md ${srcRoot}/README.zh-CN.md \
      ${srcRoot}/CHANGELOG.md \
      ${srcRoot}/CONTRIBUTING.md ${srcRoot}/.github/PULL_REQUEST_TEMPLATE.md \
      ${srcRoot}/docs ${srcRoot}/plugins/codex-base/.codex-plugin/plugin.json
    touch $out
  '';
  docs-contract = mkTest "public-docs-contract" [ python pkgs.jq pkgs.gnugrep ] ''
    grep -Fq 'README.zh-CN.md' ${srcRoot}/README.md
    grep -Fq 'README.md' ${srcRoot}/README.zh-CN.md
    test "$(grep -Foc '](docs/assets/codex-base-workflow.svg)' ${srcRoot}/README.md)" -eq 1
    test "$(grep -Foc '](docs/assets/codex-base-workflow.zh-CN.svg)' ${srcRoot}/README.zh-CN.md)" -eq 1
    ! grep -Fq '](docs/assets/codex-base-workflow.zh-CN.svg)' ${srcRoot}/README.md
    ! grep -Fq '](docs/assets/codex-base-workflow.svg)' ${srcRoot}/README.zh-CN.md
    for readme in ${srcRoot}/README.md ${srcRoot}/README.zh-CN.md; do
      grep -Fq 'plugins/codex-base/assets/codex-base.svg' "$readme"
      grep -Fq '> [!NOTE]' "$readme"
      grep -Fq '> [!WARNING]' "$readme"
      grep -Fq 'actions/workflows/ci.yml/badge.svg' "$readme"
      grep -Fq 'img.shields.io/badge/license-MIT-blue.svg' "$readme"
      grep -Fq 'codex plugin marketplace add https://github.com/bioinformatist/codex-base' "$readme"
      grep -Fq 'codex plugin add codex-base@bioinformatist-codex' "$readme"
      grep -Fq 'codex plugin list --marketplace bioinformatist-codex' "$readme"
    done
    grep -Fq 'docs/architecture.md' ${srcRoot}/CONTRIBUTING.md
    grep -Fq 'docs/updating.md' ${srcRoot}/CONTRIBUTING.md
    grep -Fq 'codex mcp add context7_auth --url https://mcp.context7.com/mcp/oauth' ${srcRoot}/docs/configuration.md
    grep -Fq 'codex mcp add context7_auth --url https://mcp.context7.com/mcp/oauth' ${srcRoot}/docs/configuration.zh-CN.md
    grep -Fq 'programs.codexBase.context7ApiKeyFile = /run/secrets/context7-api-key;' ${srcRoot}/docs/configuration.md
    grep -Fq 'programs.codexBase.context7ApiKeyFile = /run/secrets/context7-api-key;' ${srcRoot}/docs/configuration.zh-CN.md
    test "$(grep -Foc '[Changelog](CHANGELOG.md)' ${srcRoot}/README.md)" -eq 1
    test "$(grep -Foc '[版本记录（英文）](CHANGELOG.md)' ${srcRoot}/README.zh-CN.md)" -eq 1
    test "$(grep -Fxoc '# Changelog' ${srcRoot}/CHANGELOG.md)" -eq 1
    release_version="$(jq -r '.version' ${srcRoot}/plugins/codex-base/.codex-plugin/plugin.json)"
    test "$(grep -Foc "## [$release_version]" ${srcRoot}/CHANGELOG.md)" -eq 1
    if grep -Fxq "## [$release_version] — Unreleased" ${srcRoot}/CHANGELOG.md; then
      ! grep -Fxq "[$release_version]: https://github.com/bioinformatist/codex-base/releases/tag/v$release_version" ${srcRoot}/CHANGELOG.md
    else
      grep -Fxq "## [$release_version]" ${srcRoot}/CHANGELOG.md
      grep -Fxq "[$release_version]: https://github.com/bioinformatist/codex-base/releases/tag/v$release_version" ${srcRoot}/CHANGELOG.md
    fi
    grep -Fq '52b9e4cc614749791b5d2e46d8c6bf8fd41592b0...b528a6e9fc902f1ef79d498db60ece95086afa7e' ${srcRoot}/CHANGELOG.md
    test -f ${srcRoot}/tests/prompt-scenarios.md
    test -f ${srcRoot}/docs/assets/prompts/codex-base-logo.md
    test -f ${srcRoot}/docs/assets/prompts/codex-base-workflow.md
    jq -e '.interface.composerIcon == "./assets/codex-base.svg" and .interface.logo == "./assets/codex-base.svg"' \
      ${srcRoot}/plugins/codex-base/.codex-plugin/plugin.json >/dev/null
    jq -e '
      . as $manifest
      | [$manifest.description, $manifest.interface.longDescription]
      | all(.[]; test("skills?|workflows?"; "i") and test("documentation|mcp"; "i"))
      and ($manifest.keywords | index("documentation") != null and index("mcp") != null)
    ' ${srcRoot}/plugins/codex-base/.codex-plugin/plugin.json >/dev/null
    python - <<'PY'
    import os
    import re
    import subprocess
    import tempfile
    import json
    import tomllib
    from pathlib import Path
    from xml.etree import ElementTree as ET

    root = Path('${srcRoot}')
    # Check each language's README entry point and detailed configuration guide.
    waiver_anchor = '<a id="temporary-context-waiver"></a>'
    waiver_image = 'docs/evidence/2026-09-12-tibo-context-management.png'
    assert (root / waiver_image).is_file()
    for readme_name, name in [
        ('README.md', 'docs/configuration.md'),
        ('README.zh-CN.md', 'docs/configuration.zh-CN.md'),
    ]:
        readme = (root / readme_name).read_text()
        guide = (root / name).read_text()
        assert readme.count(waiver_anchor) == 1, readme_name
        assert f']({name}#temporary-context-waiver)' in readme, readme_name
        assert f']({name}#native-codex-configuration)' in readme, readme_name
        assert f']({name}#context7-authentication)' in readme, readme_name
        assert guide.count(waiver_anchor) == 1, name
        note = guide.split(waiver_anchor, 1)[1]
        for required in [
            '2026-09-12',
            '](https://x.com/thsottiaux/status/2098612714704891959)',
            '](evidence/2026-09-12-tibo-context-management.png)',
        ]:
            assert required in note, (name, required)
    for name, target in [
        ('docs/architecture.md', '../README.md'),
        ('docs/capabilities.md', '../README.md'),
        ('docs/capabilities.zh-CN.md', '../README.zh-CN.md'),
    ]:
        document = root / name
        assert f']({target}#temporary-context-waiver)' in document.read_text(), name
        assert (document.parent / target).is_file(), name

    def ids(path):
        return [line.split('|')[1].strip() for line in path.read_text().splitlines()
                if line.startswith('| ') and not line.startswith('| ID ') and not line.startswith('|---')]
    expected_ids = [
        'global-agents', 'docs-routing', 'adhx', 'github-mcp', 'improve',
        'executor-routing', 'early-simplification', 'grilling',
        'ponytail-review', 'ponytail-audit', 'ponytail-debt',
        'diagnosing-bugs', 'tdd', 'codebase-design', 'domain-modeling',
        'merge-conflicts', 'playwright', 'stop-slop', 'handoff', 'wait-what',
        'questionnaire', 'writing-agents',
    ]
    assert ids(root / 'docs/capabilities.md') == expected_ids
    assert ids(root / 'docs/capabilities.zh-CN.md') == expected_ids

    credits = (root / 'docs/credits.md').read_text()
    sources = json.loads((root / 'vendor/sources.json').read_text())['sources']
    assert all(source['name'] in credits for source in sources)
    for path in [root / 'docs/assets/codex-base-workflow.svg',
                 root / 'docs/assets/codex-base-workflow.zh-CN.svg',
                 root / 'plugins/codex-base/assets/codex-base.svg']:
        svg = ET.parse(path).getroot()
        assert svg.get('viewBox') and svg.get('role') == 'img'
        assert any(node.tag.endswith('title') for node in svg)
        assert any(node.tag.endswith('desc') for node in svg)

    def parse_setup(path):
      text = path.read_text()
      blocks = re.findall(r'```toml\n(.*?)```', text, flags=re.S)
      candidates = []
      for block in blocks:
        data = tomllib.loads(block)
        if "plan_mode_reasoning_effort" in data:
          candidates.append((block, data))
      assert len(candidates) == 1, f"expected one setup fragment in {path}"
      fragment, setup = candidates[0]
      assert setup["plan_mode_reasoning_effort"] == "high"
      features = setup["features"]
      assert features["context_management"]["experimental_mode"] is True
      assert features["code_mode"]["enabled"] is True
      assert features["default_mode_request_user_input"] is True
      return fragment, setup

    expected_flags = (
      ("context_management", "true"),
      ("code_mode", "true"),
      ("default_mode_request_user_input", "true"),
    )
    setups = [parse_setup(path) for path in [root / 'docs/configuration.md', root / 'docs/configuration.zh-CN.md']]
    assert setups[0][1] == setups[1][1], "English and Chinese setup data differs"
    for fragment, _ in setups:
      with tempfile.TemporaryDirectory() as td:
        cfg = Path(td) / '.codex' / 'config.toml'
        cfg.parent.mkdir(parents=True, exist_ok=True)
        cfg.write_bytes(fragment.encode())
        result = subprocess.run(
          [str(Path('${packages.codex}') / 'bin' / 'codex'), 'features', 'list'],
          cwd=str(td),
          env={**os.environ, 'HOME': str(td), 'CODEX_HOME': str(cfg.parent)},
          capture_output=True,
          text=True,
          check=True,
        )
        output = result.stdout
        for flag, expected in expected_flags:
          for line in output.splitlines():
            if line.lstrip().startswith(flag):
              assert line.split()[-1] == expected, f"{flag} not {expected}"
              break
          else:
            raise AssertionError(f"{flag} not found in feature listing")
    PY
    touch $out
  '';
  improve-runtime = mkTest "improve-runtime-tests" (shellTools ++ [ python packages.worktrunk ]) ''
    python3 -B ${srcRoot}/tests/improve/test_runtime.py
    CODEX_IMPROVE_SKILL_ROOT=${generatedSkills}/improve python3 -B ${srcRoot}/tests/improve/test_runtime.py
    touch $out
  '';
  improve-package = mkTest "improve-package-resources" (shellTools ++ [ packages.codex-improve ]) ''
    grep -F "${generatedSkills}/improve/scripts/codex-improve" ${packages.codex-improve}/bin/codex-improve >/dev/null
    ${packages.codex-improve}/bin/codex-improve --help >/dev/null
    test -r ${generatedSkills}/improve/config/roles.json
    test -r ${generatedSkills}/improve/runtime/contracts.py
    test -r ${generatedSkills}/improve/runtime/transport.py
    test -r ${generatedSkills}/improve/runtime/git_worktree.py
    test -r ${generatedSkills}/improve/references/executor-report.schema.json
    test -r ${generatedSkills}/improve/references/review-verdict.schema.json
    test -r ${generatedSkills}/worktrunk/LICENSE
    test -r ${generatedSkills}/worktrunk/agents/openai.yaml
    touch $out
  '';
  codex-layout = packages.codex;
  home-manager =
    assert builtins.hasAttr ".agents/skills/improve" files;
    assert builtins.hasAttr ".agents/skills/worktrunk" files;
    assert builtins.hasAttr ".agents/skills/adhx" files;
    assert builtins.hasAttr ".agents/skills/docs-routing" files;
    assert builtins.hasAttr ".agents/skills/writing-for-agents" files;
    assert builtins.hasAttr ".agents/skills/to-questionnaire" files;
    assert builtins.hasAttr ".agents/skills/wait-what" files;
    assert builtins.hasAttr ".codex/AGENTS.md" files;
    assert builtins.hasAttr ".codex/rules/baseline.rules" files;
    assert !(builtins.hasAttr ".agents/skills/improve" filesOff);
    assert !(builtins.hasAttr ".agents/skills/worktrunk" filesOff);
    assert builtins.hasAttr ".agents/skills/docs-routing" filesOff;
    assert builtins.hasAttr ".agents/skills/adhx" filesOff;
    assert !(builtins.hasAttr ".agents/skills/stop-slop" filesOff);
    assert !(builtins.hasAttr ".agents/skills/diagnosing-bugs" filesOff);
    assert !(builtins.hasAttr ".agents/skills/writing-for-agents" filesOff);
    assert !(builtins.hasAttr ".agents/skills/to-questionnaire" filesOff);
    assert !(builtins.hasAttr ".agents/skills/wait-what" filesOff);
    assert hm.config.programs.codexBase.stopSlop.enable;
    assert hm.config.programs.codexBase.ponytail.enable;
    assert hm.config.programs.codexBase.mattPocockSkills.enable;
    assert hm.config.programs.codexBase.improve.enable;
    assert hmOff.config.programs.codexBase.githubTokenFile == null;
    assert hmOff.config.programs.codexBase.context7ApiKeyFile == null;
    assert builtins.elem packages.codex hm.config.home.packages;
    assert builtins.elem pkgs.curl hm.config.home.packages;
    assert builtins.elem packages.codex-improve hm.config.home.packages;
    assert builtins.elem packages.worktrunk hm.config.home.packages;
    assert pkgs.lib.hasInfix ''configFile="$HOME/.codex/config.toml"'' activation;
    assert pkgs.lib.hasInfix ''if [ -L "$configFile" ]; then rm -f "$configFile"; fi'' activation;
    mkTest "home-manager-contract" (shellTools ++ [ python ]) ''
      test -x ${hm.activationPackage}/activate
      for expected in \
        '/run/secrets/github' \
        '/run/secrets/context7' \
        'writable_roots = ["/home/tester/.cache/codex-shell","/tmp/writable"]' \
        '[mcp_servers.github]' \
        '[mcp_servers.mintlify_index]
url = "https://index.mintlify.com/mcp"
required = false
startup_timeout_sec = 30
tool_timeout_sec = 120' \
        '[mcp_servers.context7_auth]'; do
        found=1
        while IFS= read -r closure_path; do
          if grep -R -F -- "$expected" "$closure_path" >/dev/null 2>&1; then found=0; break; fi
        done <${hmClosure}/store-paths
        test "$found" -eq 0
      done
python - <<'PY'
import os
import stat
import subprocess
import tempfile
from pathlib import Path
import tomllib

closure = Path("${hmClosure}/store-paths").read_text().splitlines()
base_instructions = Path("${srcRoot}/config/AGENTS.md").read_bytes()
appended_instructions = Path("${filesOff.".codex/AGENTS.md".source}").read_bytes()
assert appended_instructions == base_instructions + b"\n" + b"${instructionSentinel}"
managed = [path for path in closure if path.endswith("-codex-base-config.toml")]
merge_helpers = [
    candidate
    for root in closure
    if (candidate := Path(root) / "bin" / "merge-codex-base-config").is_file()
    and os.access(candidate, os.X_OK)
]
assert len(managed) == 1, f"expected exactly one managed config in closure, got {len(managed)}"
assert len(merge_helpers) == 1, f"expected exactly one merge helper in closure, got {len(merge_helpers)}"

managed_path = Path(managed[0])
merge_helper = merge_helpers[0]

def run_merge(target: Path) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call([str(merge_helper), str(managed_path), str(target)])
    assert stat.S_IMODE(target.stat().st_mode) == 0o600
    return tomllib.loads(target.read_text())

def assert_managed(merged: dict) -> None:
    assert merged["model"] == "gpt-6-sol"
    assert merged["model_reasoning_effort"] == "medium"
    assert merged["model_verbosity"] == "medium"
    assert merged["plan_mode_reasoning_effort"] == "high"
    assert merged["sandbox_mode"] == "workspace-write"
    assert merged["approval_policy"] == "on-request"
    assert merged["web_search"] == "live"
    assert merged["mcp_oauth_credentials_store"] == "file"
    assert merged["features"]["context_management"]["experimental_mode"] is True
    assert merged["features"]["code_mode"]["enabled"] is True
    assert merged["features"]["default_mode_request_user_input"] is True
    assert merged["features"]["memories"] is True
    assert merged["features"]["hooks"] is True

with tempfile.TemporaryDirectory() as td:
    # Merge into an absent configuration.
    empty_target = Path(td) / ".codex" / "config.toml"
    assert not empty_target.exists()
    assert_managed(run_merge(empty_target))

    # Merge into a pre-populated config; owned managed values must win without erasing siblings.
    existing_path = Path(td) / "existing.toml"
    existing_path.write_text("""[history]\nfile = \"persisted.log\"\n\n[features]\nshell_snapshot = false\ncontext_management.experimental_mode = false\ndefault_mode_request_user_input = false\n\n[features.code_mode]\nenabled = false\ndefault_exec_yield_time_ms = 250\n""")
    merged = run_merge(existing_path)
    assert_managed(merged)
    assert merged["features"]["shell_snapshot"] is False
    assert merged["features"]["code_mode"]["default_exec_yield_time_ms"] == 250
    assert merged["history"] == {"file": "persisted.log"}

    repeated = run_merge(existing_path)
    assert_managed(repeated)
    assert repeated == merged
PY
      cmp ${generatedSkills}/docs-routing/SKILL.md ${files.".agents/skills/docs-routing".source}/SKILL.md
      cmp ${generatedSkills}/adhx/SKILL.md ${files.".agents/skills/adhx".source}/SKILL.md
      touch $out
    '';
  plugin-smoke = mkTest "plugin-smoke" [ packages.codex packages.worktrunk python pkgs.bash pkgs.coreutils pkgs.jq ] ''
    HOME="$TMPDIR/real-home" mkdir -p "$TMPDIR/real-home"
    HOME="$TMPDIR/real-home" bash ${srcRoot}/tests/plugin-smoke.bash
    touch $out
  '';
}
