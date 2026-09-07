{ pkgs, srcRoot, generatedSkills, packages, inputs, self }:
let
  mkTest = name: inputs': text: pkgs.runCommand name { nativeBuildInputs = inputs'; } text;
  shellTools = [ pkgs.bash pkgs.coreutils pkgs.gitMinimal pkgs.gnused pkgs.jq pkgs.shellcheck-minimal ];
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
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
    } ];
  };
  files = hm.config.home.file;
  filesOff = hmOff.config.home.file;
  activation = hm.config.home.activation.codex-base-config.data;
  hmClosure = pkgs.closureInfo { rootPaths = [ hm.activationPackage ]; };
  legacy = map (n: ".codex/${n}.config.toml") [ "improve-scout" "improve-executor" "improve-executor-spark" "improve-executor-deep" "improve-reviewer" "improve-elegance-reviewer" ];
in {
  generated-plugin-parity = mkTest "generated-plugin-parity" shellTools ''
    diff -ruN --no-dereference ${generatedSkills} ${srcRoot}/plugins/codex-base/skills
    touch $out
  '';
  plugin-schema = mkTest "plugin-schema" [ python ] ''
    python ${pluginValidator} ${srcRoot}/plugins/codex-base
    for skill in ${srcRoot}/plugins/codex-base/skills/*; do python ${skillValidator} "$skill"; done
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
    test "$(find ${srcRoot}/plugins/codex-base/licenses -type f | wc -l)" -eq 5
    touch $out
  '';
  mattpocock-skills = mkTest "mattpocock-skills-contract" shellTools ''
    expected='codebase-design diagnosing-bugs domain-modeling resolving-merge-conflicts tdd grilling handoff wait-what writing-for-agents to-questionnaire'
    actual=$(jq -r '.sources[] | select(.name == "mattpocock-skills") | .includedPaths[] | split("/")[-1]' ${srcRoot}/vendor/sources.json | paste -sd ' ' -)
    test "$actual" = "$expected"
    for skill in $expected; do test -d "${generatedSkills}/$skill"; done

    grep -Fq 'allow_implicit_invocation: true' ${generatedSkills}/writing-for-agents/agents/openai.yaml
    grep -Fq 'permits autonomous invocation and uses the description for discovery when the harness exposes it' ${generatedSkills}/writing-for-agents/SKILL-MECHANICS.md
    grep -Fq 'prevents autonomous invocation, but the skill may still appear in catalogs or UI' ${generatedSkills}/writing-for-agents/SKILL-MECHANICS.md
    grep -Fq 'Router skills help humans discover explicit-only skills but do not change those invocation policies' ${generatedSkills}/writing-for-agents/SKILL-MECHANICS.md
    ! grep -Fq \
      -e 'forced to stay loaded at all times' \
      -e 'permanent context load' \
      -e 'strips the description from the agent' \
      -e 'No implicit catalog exposure' \
      -e 'Zero context load' \
      -e 'pay no context load' \
      -e 'with no descriptions' \
      -e 'always-loaded description' \
      -e 'user-invoked skills have no description' \
      -e 'nothing but the human can reach them' \
      ${generatedSkills}/writing-for-agents/SKILL-MECHANICS.md
    grep -Fq 'allow_implicit_invocation: false' ${generatedSkills}/to-questionnaire/agents/openai.yaml
    grep -Fq 'collision-resistant Markdown file' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'the complete questionnaire is rendered in chat or the authorized file exists' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'every item the user named in step 2 is covered by a question' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'Never overwrite an existing file, send or publish' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'Never request credentials' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq '**From role:** <role>, **To role:** <role>' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'allow_implicit_invocation: false' ${generatedSkills}/wait-what/agents/openai.yaml
    grep -Fq 'current conversation language' ${generatedSkills}/wait-what/SKILL.md
    grep -Fq 'preserve all facts, constraints, caveats, and uncertainty' ${generatedSkills}/wait-what/SKILL.md
    grep -Fq 'at most three independent, high-value frontier questions' ${generatedSkills}/grilling/SKILL.md
    grep -Fq 'Do not implement automatically' ${generatedSkills}/grilling/SKILL.md
    grep -Fqx '  short_description: "Stress-test thinking in frontier rounds"' ${generatedSkills}/grilling/agents/openai.yaml
    grep -Fq 'otherwise produce distinct viable designs yourself' ${generatedSkills}/codebase-design/DESIGN-IT-TWICE.md
    grep -Fq 'only when delegation is authorized' ${generatedSkills}/codebase-design/SKILL.md
    grep -Fq 'Do not repeat an approval request' ${generatedSkills}/resolving-merge-conflicts/SKILL.md
    grep -Fq 'Redact every secret first' ${generatedSkills}/diagnosing-bugs/SKILL.md
    grep -Fq 'Production instrumentation requires explicit authorization' ${generatedSkills}/diagnosing-bugs/SKILL.md
    grep -Fq 'do not invent hypotheses to meet a quota' ${generatedSkills}/diagnosing-bugs/SKILL.md
    ! grep -Fq 'Skill tool' ${generatedSkills}/tdd/SKILL.md
    grep -Fq 'Preserve accepted interfaces, behavior, and required tests.' ${generatedSkills}/ponytail-review/SKILL.md
    grep -Fq 'Correctness and shipping readiness were not assessed.' ${generatedSkills}/ponytail-audit/SKILL.md
    ! grep -Ezq '"audit this[[:space:]]+codebase"' ${generatedSkills}/ponytail-audit/SKILL.md
    grep -Fq -- '--exclude-dir=node_modules' ${generatedSkills}/ponytail-debt/SKILL.md
    grep -Fq -- '--exclude-dir=.git' ${generatedSkills}/ponytail-debt/SKILL.md
    grep -Fq 'never writes, edits, stages, or persists a ledger' ${generatedSkills}/ponytail-debt/SKILL.md
    test "$(jq -r '.sources[] | select(.name == "ponytail") | .patched' ${srcRoot}/vendor/sources.json)" = true
    touch $out
  '';
  shellcheck = mkTest "all-shell-scripts" shellTools ''
    while IFS= read -r file; do bash -n "$file"; shellcheck "$file"; done < <(find ${srcRoot}/scripts ${srcRoot}/src ${srcRoot}/tests -type f \( -name '*.bash' -o -name '*.sh' -o -perm -0100 \))
    touch $out
  '';
  codex-release-consistency = mkTest "codex-release-consistency" shellTools ''
    bash ${srcRoot}/scripts/check-codex-release
    touch $out
  '';
  codex-release-updater = mkTest "codex-release-updater-tests" shellTools ''
    bash ${srcRoot}/tests/codex-release-updater.bash
    touch $out
  '';
  workflow-lint = mkTest "workflow-lint" [ pkgs.actionlint pkgs.gnugrep ] ''
    actionlint ${srcRoot}/.github/workflows/*.yml
    workflow=${srcRoot}/.github/workflows/maintenance-codex.yml
    test "$(grep -Fxc '      - uses: actions/checkout@v4' "$workflow")" -eq 1
    grep -F -A 5 '      - uses: actions/checkout@v4' "$workflow" \
      | grep -Fqx '          ref: main'
    test "$(grep -Fxc '          git add README.md README.zh-CN.md flake.nix flake.lock nix/packages.nix' "$workflow")" -eq 1
    touch $out
  '';
  typos = mkTest "public-docs-typos" [ pkgs.typos ] ''
    typos --config ${srcRoot}/typos.toml \
      ${srcRoot}/README.md ${srcRoot}/README.zh-CN.md \
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
    grep -Fq 'anonymous Mintlify Index and Context7 HTTP endpoints' ${srcRoot}/README.md
    grep -Fq '匿名的 Mintlify Index 与 Context7 HTTP 端点' ${srcRoot}/README.zh-CN.md
    grep -Fq 'Enter built-in Plan Mode with `/plan` or Shift+Tab' ${srcRoot}/README.md
    grep -Fq '请先用 `/plan` 或 Shift+Tab 进入内置 Plan Mode' ${srcRoot}/README.zh-CN.md
    grep -Fq 'configured `true` values and a Plan Mode label do not prove that either capability is live' ${srcRoot}/README.md
    grep -Fq '配置值为 `true` 或界面显示 Plan Mode，都不能证明能力已经可用' ${srcRoot}/README.zh-CN.md
    ! grep -Fq 'not built-in Plan Mode' ${srcRoot}/README.md
    ! grep -Fq '不要使用内置 Plan Mode' ${srcRoot}/README.zh-CN.md
    grep -Fq '`src/docs-routing` is the canonical first-party documentation-routing skill.' ${srcRoot}/docs/architecture.md
    grep -Fq 'Adapted for Codex invocation, preservation, and reporting rules' ${srcRoot}/docs/credits.md
    grep -Fq 'Keep anonymous plugin MCP defaults' ${srcRoot}/CONTRIBUTING.md
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
    def ids(path):
        return [line.split('|')[1].strip() for line in path.read_text().splitlines()
                if line.startswith('| ') and not line.startswith('| ID ') and not line.startswith('|---')]
    expected_ids = [
        'global-agents', 'docs-routing', 'github-mcp', 'improve',
        'executor-routing', 'early-simplification', 'grilling',
        'ponytail-review', 'ponytail-audit', 'ponytail-debt',
        'diagnosing-bugs', 'tdd', 'codebase-design', 'domain-modeling',
        'merge-conflicts', 'playwright', 'stop-slop', 'handoff', 'wait-what',
        'questionnaire', 'writing-agents',
    ]
    assert ids(root / 'docs/capabilities.md') == expected_ids
    assert ids(root / 'docs/capabilities.zh-CN.md') == expected_ids

    # These are static editorial guards, not runtime behavior evidence.
    scenarios = (root / 'tests/prompt-scenarios.md').read_text()
    flat_scenarios = ' '.join(scenarios.split())
    architecture = (root / 'docs/architecture.md').read_text()
    assert 'not an automated benchmark or evidence of universal model obedience' in flat_scenarios
    headings = re.findall(r'^## (SC-\d{2}): .+$', scenarios, flags=re.M)
    assert headings == [f'SC-{number:02d}' for number in range(1, 17)]
    blocks = re.split(r'^## SC-\d{2}: .+$', scenarios, flags=re.M)[1:]
    assert len(blocks) == 16
    for block in blocks:
        assert block.count('**Input/context:**') == 1
        assert block.count('**Expected observable behavior:**') == 1
        assert block.count('**Runtime observation:** NOT RUN') == 1
    assert 'Codex Base has no model-index or per-model global guidance files' in ' '.join(architecture.split())
    for phrase in [
        'do not ask the user to choose again',
        'without editing source, tests, or production instrumentation',
        'do not launch a child agent',
        'Do not require Astra, high reasoning effort, or Code Mode',
        'Query CI at most once',
        'user explicitly says, “Monitor this run until it finishes.”',
        'Keep the compatibility test',
        '使用中文在当前对话中改述',
    ]:
        assert phrase in flat_scenarios
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
    setups = [parse_setup(path) for path in [root / 'README.md', root / 'README.zh-CN.md']]
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
  improve-exec = mkTest "improve-exec-tests" shellTools ''
    CODEX_IMPROVE_REAL_CODEX=${packages.codex}/bin/codex CODEX_IMPROVE_EXEC_SCHEMA=${srcRoot}/src/improve/references/executor-report.schema.json CODEX_IMPROVE_ROLES_FILE=${srcRoot}/src/improve/config/roles.json bash ${srcRoot}/tests/improve/exec-runner.bash ${srcRoot}/src/improve/scripts/codex-improve-exec
    touch $out
  '';
  improve-review = mkTest "improve-review-tests" shellTools ''
    CODEX_IMPROVE_REVIEW_SCHEMA=${srcRoot}/src/improve/references/review-verdict.schema.json CODEX_IMPROVE_ROLES_FILE=${srcRoot}/src/improve/config/roles.json bash ${srcRoot}/tests/improve/review-runner.bash ${srcRoot}/src/improve/scripts/codex-improve-review
    touch $out
  '';
  improve-scout = mkTest "improve-scout-tests" shellTools ''
    bash ${srcRoot}/tests/improve/scout-runner.bash ${srcRoot}/src/improve/scripts/codex-improve-scout
    touch $out
  '';
  improve-compatibility = mkTest "improve-compatibility" shellTools ''
    bash ${srcRoot}/tests/improve/compatibility.bash
    touch $out
  '';
  runner-packages = mkTest "runner-package-resources" shellTools ''
    grep -F "${generatedSkills}/improve/scripts/codex-improve-exec" ${packages.codex-improve-exec}/bin/codex-improve-exec >/dev/null
    grep -F "${generatedSkills}/improve/scripts/codex-improve-review" ${packages.codex-improve-review}/bin/codex-improve-review >/dev/null
    grep -F "${generatedSkills}/improve/scripts/codex-improve-scout" ${packages.codex-improve-scout}/bin/codex-improve-scout >/dev/null
    test -r ${generatedSkills}/improve/config/roles.json
    test -r ${generatedSkills}/improve/references/executor-report.schema.json
    test -r ${generatedSkills}/improve/references/review-verdict.schema.json
    touch $out
  '';
  codex-layout = packages.codex;
  home-manager =
    assert builtins.hasAttr ".agents/skills/improve" files;
    assert builtins.hasAttr ".agents/skills/docs-routing" files;
    assert builtins.hasAttr ".agents/skills/writing-for-agents" files;
    assert builtins.hasAttr ".agents/skills/to-questionnaire" files;
    assert builtins.hasAttr ".agents/skills/wait-what" files;
    assert builtins.hasAttr ".codex/AGENTS.md" files;
    assert builtins.hasAttr ".codex/rules/baseline.rules" files;
    assert builtins.all (path: !(builtins.hasAttr path files)) legacy;
    assert !(builtins.hasAttr ".agents/skills/improve" filesOff);
    assert builtins.hasAttr ".agents/skills/docs-routing" filesOff;
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
    assert builtins.elem packages.codex-improve-exec hm.config.home.packages;
    assert builtins.elem packages.codex-improve-review hm.config.home.packages;
    assert builtins.elem packages.codex-improve-scout hm.config.home.packages;
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
    assert merged["model"] == "gpt-5.6-sol"
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

    # Merge over the legacy boolean feature representation.
    legacy_path = Path(td) / "legacy.toml"
    legacy_path.write_text("""[history]\nfile = \"legacy.log\"\n\n[features]\ncode_mode = false\ncontext_management = false\ndefault_mode_request_user_input = false\nshell_snapshot = false\n""")
    legacy_merged = run_merge(legacy_path)
    assert_managed(legacy_merged)
    assert legacy_merged["features"]["shell_snapshot"] is False
    assert legacy_merged["history"] == {"file": "legacy.log"}

    legacy_repeated = run_merge(legacy_path)
    assert_managed(legacy_repeated)
    assert legacy_repeated == legacy_merged

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
      for clause in \
        'unless a higher-authority product-specific documentation workflow applies.' \
        'Query `mintlify_index` once with focused product and requested-version terms.' \
        'Accept the result only when it is nonempty, relevant, covers the requested version, and includes traceable source URLs.' \
        'Otherwise use anonymous `context7` to resolve the exact library and version. Do not repeat an equivalent Mintlify query.' \
        'Use `context7_auth` only when it is available and anonymous Context7 is rate-limited, unavailable, or still insufficient.' \
        'Then fall back to official primary documentation or source.' \
        'Never send secrets, credentials, private code, full prompts, or non-public internal content to either provider.' \
        'If a named tool is absent, advance to the next stage without automatically installing, authenticating, or retrying it.'; do
        grep -Fq "$clause" ${generatedSkills}/docs-routing/SKILL.md
      done
      grep -Fq 'Treat GitHub and Context7 tokens as per-user secrets.' ${srcRoot}/config/AGENTS.md
      ! grep -Fq 'Mintlify Index is a public documentation-search MCP server.' ${srcRoot}/config/AGENTS.md
      while IFS= read -r closure_path; do
        ! grep -R -E 'improve-(scout|executor|executor-spark|executor-deep|reviewer|elegance-reviewer)\.config\.toml' "$closure_path" >/dev/null 2>&1
      done <${hmClosure}/store-paths
      touch $out
    '';
  plugin-smoke = mkTest "plugin-smoke" [ packages.codex pkgs.bash pkgs.coreutils pkgs.jq ] ''
    HOME="$TMPDIR/real-home" mkdir -p "$TMPDIR/real-home"
    HOME="$TMPDIR/real-home" bash ${srcRoot}/tests/plugin-smoke.bash
    touch $out
  '';
}
