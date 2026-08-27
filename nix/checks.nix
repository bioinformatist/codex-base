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
    touch $out
  '';
  stale-wording = mkTest "stale-wording" shellTools ''
    ! grep -R -n -E '(/codebase-design|/grilling|/domain-modeling|/improve-codebase-architecture|Agent tool|subagent_type|Claude|claude|CLAUDE|SendMessage|spin up parallel sub-agents|show --annotate +# ask the user)' ${generatedSkills}
    ! grep -R -n -E '(/home/[[:alnum:]_.-]+|/nix/store/|BEGIN (RSA |OPENSSH )?PRIVATE KEY|api[_-]?key[[:space:]]*=|token[[:space:]]*=)' ${srcRoot}/README.md ${srcRoot}/docs ${srcRoot}/plugins ${srcRoot}/vendor
    test "$(find ${srcRoot}/plugins/codex-base/licenses -type f | wc -l)" -eq 5
    touch $out
  '';
  mattpocock-skills = mkTest "mattpocock-skills-contract" shellTools ''
    expected='codebase-design diagnosing-bugs domain-modeling resolving-merge-conflicts tdd grilling handoff writing-for-agents to-questionnaire'
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
    grep -Fq 'Never overwrite an existing file, send or publish' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'Never request credentials' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq '**From role:** <role>, **To role:** <role>' ${generatedSkills}/to-questionnaire/SKILL.md
    grep -Fq 'at most three independent, high-value frontier questions' ${generatedSkills}/grilling/SKILL.md
    grep -Fq 'Do not implement automatically' ${generatedSkills}/grilling/SKILL.md
    grep -Fqx '  short_description: "Stress-test thinking in frontier rounds"' ${generatedSkills}/grilling/agents/openai.yaml
    grep -Fq 'otherwise produce 3 distinct designs yourself' ${generatedSkills}/codebase-design/DESIGN-IT-TWICE.md
    grep -Fq 'Leave lifecycle actions to separate authorization' ${generatedSkills}/resolving-merge-conflicts/SKILL.md
    grep -Fq 'Redact every secret first' ${generatedSkills}/diagnosing-bugs/SKILL.md
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
    assert builtins.hasAttr ".agents/skills/writing-for-agents" files;
    assert builtins.hasAttr ".agents/skills/to-questionnaire" files;
    assert builtins.hasAttr ".codex/AGENTS.md" files;
    assert builtins.hasAttr ".codex/rules/baseline.rules" files;
    assert builtins.all (path: !(builtins.hasAttr path files)) legacy;
    assert !(builtins.hasAttr ".agents/skills/improve" filesOff);
    assert !(builtins.hasAttr ".agents/skills/stop-slop" filesOff);
    assert !(builtins.hasAttr ".agents/skills/diagnosing-bugs" filesOff);
    assert !(builtins.hasAttr ".agents/skills/writing-for-agents" filesOff);
    assert !(builtins.hasAttr ".agents/skills/to-questionnaire" filesOff);
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
    mkTest "home-manager-contract" shellTools ''
      test -x ${hm.activationPackage}/activate
      for expected in \
        '/run/secrets/github' \
        '/run/secrets/context7' \
        'writable_roots = ["/home/tester/.cache/codex-shell","/tmp/writable"]' \
        '[mcp_servers.github]' \
        '[mcp_servers.mintlify_index]
url = "https://index.mintlify.com"
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
      for expected in \
        'Mintlify Index is a public documentation-search MCP server.' \
        '`mintlify_index` first with focused product and version terms.' \
        'output only when it is nonempty, relevant, covers the requested version, and' \
        'includes traceable source URLs. If the output is empty, irrelevant,' \
        'version-insufficient, or source-insufficient, immediately fall back to' \
        'anonymous `context7`; do not repeat an equivalent Mintlify query.' \
        'Use anonymous `context7` to resolve the exact library and version.' \
        '`context7_auth` only if anonymous Context7 is rate-limited, unavailable, or' \
        'still lacks the result; then use official primary documentation or source.' \
        'Never send secrets, credentials, or non-public internal content to Mintlify' \
        'Index or Context7.'; do
        grep -F -- "$expected" ${srcRoot}/config/AGENTS.md >/dev/null
      done
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
