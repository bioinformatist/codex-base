{
  pkgs,
  srcRoot,
  mattPocockSkillsSource,
  improveSource,
  stopSlopSource,
  ponytailSource,
  playwrightCliSource,
}:

let
  lib = pkgs.lib;
  stopSlopSkillMd = pkgs.writeText "stop-slop-SKILL.md" ''
    ---
    name: stop-slop
    description: Prose final-pass editor for GitHub issue bodies, pull request bodies, release notes, README/docs changes, public comments, and user-facing explanations. Use when Codex drafts or revises substantial prose that will be published or committed, especially when the user asks to polish, de-slop, make it less AI-written, improve a PR/issue body, or prepare docs text; do not use for ordinary code implementation, debugging transcripts, logs, quoted text, command output, API names, or Chinese conversational replies unless explicitly requested.
    ---

    # Stop Slop

    Use this skill as a final prose pass, after technical facts are correct.

    ## Workflow

    1. Preserve facts, scope, and intent.
    2. Leave code blocks, commands, logs, stack traces, quoted source text, identifiers, API names, filenames, branch names, commit messages, and test names unchanged unless the user explicitly asks to rewrite them.
    3. For English prose, remove formulaic AI phrasing, throat-clearing, empty emphasis, stock transitions, fake symmetry, inflated claims, and punchline endings.
    4. Prefer concrete nouns, direct verbs, and specific consequences over vague summaries.
    5. Keep useful technical caution. Do not remove uncertainty, caveats, or passive voice when they make the engineering claim more accurate.
    6. Keep the output in the user's requested language and tone. For Chinese output, use the reference files only as a smell list, not as English style rules.
    7. If a reference detail is needed, read only the relevant file:
       - `references/phrases.md` for filler phrases and stock wording.
       - `references/structures.md` for formulaic paragraph and sentence shapes.
       - `references/examples.md` for before/after patterns.

    ## Output Rules

    - Return the revised text, not a scoring report, unless asked.
    - Mention material factual changes separately if any were unavoidable.
    - Keep Markdown structure valid and preserve links.
    - Do not make the prose more combative or marketing-like.
  '';
  stopSlopOpenaiYaml = pkgs.writeText "stop-slop-openai.yaml" ''
    interface:
      display_name: "Stop Slop"
      short_description: "Polish publishable prose without AI tells"
      default_prompt: "Use $stop-slop to tighten this PR or issue text without changing technical facts."
    policy:
      allow_implicit_invocation: true
  '';
  stopSlopSkill = pkgs.runCommand "codex-stop-slop-skill" { } ''
    mkdir -p "$out/agents" "$out/references"
    cp ${stopSlopSource}/LICENSE "$out/LICENSE"
    cp ${stopSlopSource}/references/*.md "$out/references/"
    cp ${stopSlopSkillMd} "$out/SKILL.md"
    cp ${stopSlopOpenaiYaml} "$out/agents/openai.yaml"
  '';
  exactReplacement =
    old: new:
    lib.escapeShellArgs [
      "--replace-fail"
      old
      new
    ];
  mkMattPocockSkill =
    {
      name,
      path,
      description,
      displayName,
      shortDescription,
      defaultPrompt,
      allowImplicit ? true,
      postPatch ? "",
      semanticGuard ? "",
    }:
    let
      skillHeader = pkgs.writeText "${name}-SKILL-header.md" ''
        ---
        name: ${name}
        description: ${description}
        ---
      '';
      openaiYaml = pkgs.writeText "${name}-openai.yaml" ''
        interface:
          display_name: "${displayName}"
          short_description: "${shortDescription}"
          default_prompt: "${defaultPrompt}"
        policy:
          allow_implicit_invocation: ${if allowImplicit then "true" else "false"}
      '';
    in
    pkgs.runCommand "codex-mattpocock-${name}-skill" { } ''
      mkdir -p "$out"
      cp -R ${mattPocockSkillsSource}/${path}/. "$out/"
      chmod -R u+w "$out"

      rm -f "$out/SKILL.md"
      cat ${skillHeader} > "$out/SKILL.md"
      awk '
        BEGIN { dashes = 0 }
        /^---$/ && dashes < 2 { dashes++; next }
        dashes >= 2 { print }
      ' ${mattPocockSkillsSource}/${path}/SKILL.md >> "$out/SKILL.md"

      mkdir -p "$out/agents"
      cp ${openaiYaml} "$out/agents/openai.yaml"

      ${postPatch}

      if grep -R -n -E \
        '^(allowed-tools|argument-hint|disable-model-invocation):|Claude|claude|Agent tool|subagent_type|`/[a-z][a-z-]+` (skill|Skill)' \
        "$out"; then
        echo "${name} contains unadapted Claude-oriented skill instructions" >&2
        exit 1
      fi

      ${semanticGuard}
    '';
  diagnosingBugsSkill = mkMattPocockSkill {
    name = "diagnosing-bugs";
    path = "skills/engineering/diagnosing-bugs";
    description = "Disciplined diagnosis loop for hard bugs, regressions, flaky failures, and performance problems with unclear cause. Use for root-cause debugging after a concrete symptom exists; do not use for routine implementation or speculative cleanup.";
    displayName = "Diagnosing Bugs";
    shortDescription = "Debug hard bugs with a tight feedback loop";
    defaultPrompt = "Use $diagnosing-bugs to build a tight repro loop and diagnose this bug.";
    semanticGuard = ''
      grep -Fq 'Redact every secret first' "$out/SKILL.md"
      grep -Fq 'show the invocation and its output, redacted' "$out/SKILL.md"
      grep -Fq 'credential stays in the environment' "$out/SKILL.md"
    '';
  };
  tddSkill = mkMattPocockSkill {
    name = "tdd";
    path = "skills/engineering/tdd";
    description = "Test-driven development with red-green-refactor and behavior-focused tests. Use when the user explicitly wants test-first work, a regression test before a fix, or integration tests that drive a feature through a public interface.";
    displayName = "TDD";
    shortDescription = "Drive changes through behavior tests";
    defaultPrompt = "Use $tdd to implement this change through a red-green-refactor loop.";
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        ${exactReplacement
          ''
            **Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything, so agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

            Ask: "What's the public interface, and which seams should we test?"
          ''
          ''
            **Test only at settled seams.** Before writing any test, write down the seams under test. Derive them from an accepted plan, specification, or repository evidence when those sources already settle the public boundary. Ask the user only when the seam is materially ambiguous. No test is written at an unsupported seam; this keeps testing effort on critical paths and complex logic instead of every edge case.

            Ask only when needed: "What's the public interface, and which seams should we test?"
          ''} \
        ${exactReplacement
          ''
            - **Refactoring is not part of the loop.** It belongs to the review stage (see the `code-review` skill), not the red → green implementation cycle.
          ''
          ''
            - **Refactor only while green.** After the minimal implementation passes, improve structure without changing behavior; keep the tests green throughout, then begin the next red → green slice.
          ''
        }
    '';
    semanticGuard = ''
      grep -Fq 'accepted plan, specification, or repository evidence' "$out/SKILL.md"
      grep -Fq 'Ask the user only when the seam is materially ambiguous.' "$out/SKILL.md"
      grep -Fq 'Refactor only while green.' "$out/SKILL.md"
    '';
  };
  codebaseDesignSkill = mkMattPocockSkill {
    name = "codebase-design";
    path = "skills/engineering/codebase-design";
    description = "Shared vocabulary for designing deep modules, interfaces, seams, adapters, leverage, and locality. Use when designing or reshaping module boundaries, making code more testable, or evaluating interface depth.";
    displayName = "Codebase Design";
    shortDescription = "Design deeper modules and cleaner seams";
    defaultPrompt = "Use $codebase-design to evaluate this module interface and seam placement.";
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'spin up parallel sub-agents to design the interface several radically different ways' \
        'use parallel sub-agents when multi-agent tools are available, or design the interface several radically different ways yourself'
      substituteInPlace "$out/DESIGN-IT-TWICE.md" \
        --replace-fail 'Spawn 3+ sub-agents in parallel. Each must produce a **radically different** interface for the deepened module.' \
        'When multi-agent tools are available, spawn 3+ sub-agents in parallel; otherwise produce 3 distinct designs yourself. Each must produce a **radically different** interface for the deepened module.'
    '';
    semanticGuard = ''
      grep -Fq 'or design the interface several radically different ways yourself' "$out/SKILL.md"
      grep -Fq 'otherwise produce 3 distinct designs yourself' "$out/DESIGN-IT-TWICE.md"
    '';
  };
  grillingSkill = mkMattPocockSkill {
    name = "grilling";
    path = "skills/productivity/grilling";
    description = "Explicit-only interview loop for stress-testing a plan, decision, or idea. Use only when the user asks to grill, interrogate, interview, or stress-test their thinking before action.";
    displayName = "Grilling";
    shortDescription = "Stress-test thinking in frontier rounds";
    defaultPrompt = "Use $grilling to stress-test this plan before implementation.";
    allowImplicit = false;
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail "Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait." \
        "Finding _facts_ is your job, never the user's. Discover repository and environment facts before asking questions, using available tools directly. The _decisions_ are the user's: put each to them and wait."
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'Ask the whole frontier in one round: number each question and give your recommended answer.' \
        'Ask at most three independent, high-value frontier questions in one round: number each question and give your recommended answer.' \
        --replace-fail 'Do not act on it until the user confirms you have reached a shared understanding.' \
        'End by reporting the shared understanding and open decisions. Do not implement automatically; implementation requires a separate user request.'
    '';
    semanticGuard = ''
      grep -Fq 'at most three independent, high-value frontier questions' "$out/SKILL.md"
      grep -Fq 'Discover repository and environment facts before asking questions' "$out/SKILL.md"
      grep -Fq 'Do not implement automatically' "$out/SKILL.md"
    '';
  };
  handoffSkill = mkMattPocockSkill {
    name = "handoff";
    path = "skills/productivity/handoff";
    description = "Explicit-only workflow that writes a redacted continuation handoff to a unique temporary Markdown file. Use only when the user explicitly asks for a handoff for another session.";
    displayName = "Handoff";
    shortDescription = "Write a redacted temporary session handoff";
    defaultPrompt = "Use $handoff to prepare a redacted continuation document for the next session.";
    allowImplicit = false;
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        ${exactReplacement
          ''
            Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

            Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

            Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

            Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

            If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
          ''
          ''
            # Handoff

            Write exactly one uniquely named Markdown file under `$TMPDIR` when set, otherwise `/tmp`; never write the handoff in the repository. Use a collision-resistant name such as `codex-handoff-<timestamp>-<random>.md`. Report its absolute path when finished and do not automatically start a new session.

            Include the next-session focus, repository path, branch and HEAD, working-tree status, objective, settled decisions, relevant artifacts by path or URL, completed verification, blockers, exact next actions, and remaining authorization boundaries. If the user supplied a next-session focus, tailor the document to it.

            Recommend only relevant Skills that are actually available in the current environment. Do not duplicate full plans, diffs, or other existing artifacts; reference them instead.

            Redact secrets, credentials, passwords, tokens, personally identifiable information, and user content that is not needed for continuation.
          ''
        }
    '';
    semanticGuard = ''
      grep -Fq 'under `$TMPDIR` when set, otherwise `/tmp`' "$out/SKILL.md"
      grep -Fq 'never write the handoff in the repository' "$out/SKILL.md"
      grep -Fq 'do not automatically start a new session' "$out/SKILL.md"
      grep -Fq 'Redact secrets, credentials, passwords, tokens' "$out/SKILL.md"
    '';
  };
  domainModelingSkill = mkMattPocockSkill {
    name = "domain-modeling";
    path = "skills/engineering/domain-modeling";
    description = "Build and sharpen a project's domain model. Use only when actively changing glossary or ubiquitous-language terms, or recording a durable architectural decision; merely reading CONTEXT.md is not a trigger.";
    displayName = "Domain Modeling";
    shortDescription = "Sharpen domain language and durable decisions";
    defaultPrompt = "Use $domain-modeling to resolve domain terminology or record an ADR-worthy decision.";
  };
  resolvingMergeConflictsSkill = mkMattPocockSkill {
    name = "resolving-merge-conflicts";
    path = "skills/engineering/resolving-merge-conflicts";
    description = "Resolve existing conflict hunks during an in-progress Git merge or rebase. Use when Git reports unresolved merge/rebase conflicts; do not use for ordinary branch integration or speculative cleanup.";
    displayName = "Resolving Merge Conflicts";
    shortDescription = "Resolve active Git conflicts without finishing Git state";
    defaultPrompt = "Use $resolving-merge-conflicts to resolve the current merge or rebase conflicts safely.";
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        ${exactReplacement
          ''
            1. **See the current state** of the merge/rebase. Check git history, and the conflicting files.

            2. **Find the primary sources** for each conflict. Understand deeply why each change was made, and what the original intent was. Read the commit messages, check the PRs, check original issues/tickets.

            3. **Resolve each hunk.** Preserve both intents where possible. Where incompatible, pick the one matching the merge's stated goal and note the trade-off. Do **not** invent new behaviour. Always resolve; never `--abort`.

            4. Discover the project's **automated checks** and run them, typically typecheck, then tests, then format. Fix anything the merge broke.

            5. **Finish the merge/rebase.** Stage everything and commit. If rebasing, continue the rebase process until all commits are rebased.
          ''
          ''
            1. **Inspect the exact Git state.** Determine whether a merge or rebase is in progress, read the history and status, and list the paths and hunks that are currently conflicted.

            2. **Find the primary intent sources.** Use the relevant commits, messages, pull requests, issues, accepted plans, and surrounding code to understand why each side changed.

            3. **Resolve only existing conflict hunks.** Preserve both intents where compatible. Where they conflict, follow the stated integration goal and report the trade-off. Do not invent new behavior or broaden the change.

            4. **Verify and report.** Stage only verified conflict-resolution paths when staging is needed to mark them resolved, and report the exact staged set. Run the relevant repository checks and fix only failures caused by the resolution.

            5. **Leave lifecycle actions to separate authorization.** Do not continue or abort the merge/rebase, commit, push, force-push, reset, discard with checkout, or clean up without separate user authorization.
          ''
        }
    '';
    semanticGuard = ''
      grep -Fq 'Stage only verified conflict-resolution paths' "$out/SKILL.md"
      grep -Fq 'Do not continue or abort the merge/rebase' "$out/SKILL.md"
      if grep -F -e 'Always resolve; never `--abort`' -e 'Stage everything and commit' -e 'continue the rebase process' "$out/SKILL.md"; then
        echo "resolving-merge-conflicts retains automatic Git lifecycle actions" >&2
        exit 1
      fi
    '';
  };
  writingForAgentsSkill = mkMattPocockSkill {
    name = "writing-for-agents";
    path = "skills/productivity/writing-for-agents";
    description = "Write substantial agent-consumed guidance such as skills, AGENTS.md instructions, and documents reached by agent context pointers. Do not use for ordinary README or user-facing prose.";
    displayName = "Writing for Agents";
    shortDescription = "Write substantial guidance agents consume";
    defaultPrompt = "Use $writing-for-agents to improve this agent-consumed guidance.";
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'an `AGENTS.md` / `CLAUDE.md`, a doc reached by a pointer' \
        'an `AGENTS.md`, a doc reached by a pointer'
      substituteInPlace "$out/SKILL-MECHANICS.md" \
        ${exactReplacement
          ''
            - A **model-invoked** skill keeps a `description`, so the agent can fire it autonomously, and other skills can reach it. You can still type its name: model-invocation always _includes_ user reach; a description only ever adds agent discovery, never removes the human's. The description is the skill's top-level context pointer, forced to stay loaded at all times: permanent context load in exchange for discoverability. A model-invoked skill whose content is all reference is also one home for shared reference: another skill can invoke it, so reference needed by several skills lives in one place. Mechanics: omit `disable-model-invocation`, and write a model-facing description carrying the trigger branches (the pointer-writing rules in `SKILL.md` apply in full).
          ''
          ''
            - A **model-invoked** skill permits autonomous invocation. When the harness exposes its `description` for discovery, that description helps the agent decide when to invoke it. You can still type the skill's name: autonomous invocation adds agent discovery without removing human reach. Metadata exposure may consume context, so use the description as the skill's top-level context pointer. A model-invoked skill whose content is all reference can also be one home for shared reference: other guidance can point to it, so reference needed by several skills lives in one place. Mechanics: set `policy.allow_implicit_invocation: true` in `agents/openai.yaml`; this permits autonomous invocation and uses the description for discovery when the harness exposes it. Write a model-facing description carrying the trigger branches (the pointer-writing rules in `SKILL.md` apply in full).
          ''} \
        ${exactReplacement
          ''
            - A **user-invoked** skill strips the description from the agent's reach: only the human typing its name can invoke it, and no other skill can. Zero context load, but it spends cognitive load: you are the index that must remember it exists. Mechanics: set `disable-model-invocation: true`; the `description` becomes human-facing: a one-line summary, trigger lists stripped.
          ''
          ''
            - A **user-invoked** skill is explicit-only. Mechanics: set `policy.allow_implicit_invocation: false` in `agents/openai.yaml`; this prevents autonomous invocation, but the skill may still appear in catalogs or UI and its metadata may still have context cost. The human explicitly invokes it. Keep the `description` human-facing: a one-line summary with trigger lists stripped. The human also carries the cognitive load of remembering the skill exists.
          ''} \
        ${exactReplacement
          ''
            Pick model-invocation only when the agent must reach the skill on its own, or another skill must. If it only ever fires by hand, make it user-invoked and pay no context load.

            Shared reference that two user-invoked skills both need can live in neither: with no descriptions, neither can fire the other. Push it to a plain file outside the skill system: external reference any skill can point at.
          ''
          ''
            Pick model-invocation only when the agent must reach the skill on its own. If it only ever fires by hand, make it user-invoked and let the human decide when to invoke it. Catalog visibility and metadata context cost depend on the harness.

            Shared reference that two user-invoked skills both need should live in a plain file outside the skill system: external reference any skill can point at without altering its invocation policy.
          ''} \
        ${exactReplacement
          ''
            The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a model-invoked skill when you have a distinct leading word that should trigger it on its own (a trigger word you actually use in your prompts), or another skill must reach it. You pay context load for the new always-loaded description, so that independent reach has to be worth it.
          ''
          ''
            The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a model-invoked skill when you have a distinct leading word that should trigger it on its own (a trigger word you actually use in your prompts). When the harness exposes the new description, its metadata may add context cost, so that independent reach has to be worth it.
          ''} \
        ${exactReplacement
          ''
            When user-invoked skills multiply past what you can remember, that piled-up cognitive load is cured by a **router skill**: one user-invoked skill that names the others and when to reach for each, so the human has one skill to remember instead of many. It can only hint, never fire them: user-invoked skills have no description, so nothing but the human can reach them.
          ''
          ''
            When user-invoked skills multiply past what you can remember, that piled-up cognitive load is reduced by a **router skill**: one user-invoked skill that names the others and when to reach for each, so the human has one skill to remember instead of many. Router skills help humans discover explicit-only skills but do not change those invocation policies; the human still explicitly invokes each routed skill.
          ''}
    '';
    semanticGuard = ''
      ! grep -Eiq 'claude|disable-model-invocation' "$out/SKILL.md" "$out/SKILL-MECHANICS.md"
      grep -Fq 'agents/openai.yaml' "$out/SKILL-MECHANICS.md"
      grep -Fq 'permits autonomous invocation and uses the description for discovery when the harness exposes it' "$out/SKILL-MECHANICS.md"
      grep -Fq 'prevents autonomous invocation, but the skill may still appear in catalogs or UI' "$out/SKILL-MECHANICS.md"
      grep -Fq 'Router skills help humans discover explicit-only skills but do not change those invocation policies' "$out/SKILL-MECHANICS.md"
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
        "$out/SKILL-MECHANICS.md"
      grep -Fq 'Do not use for ordinary README or user-facing prose.' "$out/SKILL.md"
    '';
  };
  toQuestionnaireSkill = mkMattPocockSkill {
    name = "to-questionnaire";
    path = "skills/productivity/to-questionnaire";
    description = "Explicit-only workflow that writes a safe Markdown questionnaire for another person. Use only when the user explicitly asks for a questionnaire.";
    displayName = "To Questionnaire";
    shortDescription = "Write a safe questionnaire for another person";
    defaultPrompt = "Use $to-questionnaire to draft this questionnaire safely.";
    allowImplicit = false;
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'Write it to `to-questionnaire-<slug>.md` in the current directory (slug from the topic) and report the path.' 'Write exactly one collision-resistant Markdown file under `$TMPDIR` when set, otherwise `/tmp`, and report its absolute path. Never overwrite an existing file, send or publish the questionnaire, or write it in the repository.' \
        --replace-fail '**From:** <the user>, **To:** <the recipient>, **How your answers will be used:** <where they go>' '**From role:** <role>, **To role:** <role>, **How your answers will be used:** <where they go>'
      sed -i '/Turn something the user/a Never request credentials, authentication tokens, API keys, passwords, or other secret values. Prefer roles and only include personal information necessary for the questionnaire.' "$out/SKILL.md"
    '';
    semanticGuard = ''
      grep -Fq 'otherwise `/tmp`' "$out/SKILL.md"
      grep -Fq 'Never overwrite an existing file, send or publish' "$out/SKILL.md"
      grep -Fq 'Never request credentials' "$out/SKILL.md"
    '';
  };
  playwrightCliSkillHeader = pkgs.writeText "playwright-cli-SKILL-header.md" ''
    ---
    name: playwright-cli
    description: Automate browser interactions, inspect web pages, and work with Playwright tests using a headless-first CLI workflow.
    ---
  '';
  playwrightCliSkillOpenaiYaml = pkgs.writeText "playwright-cli-openai.yaml" ''
    interface:
      display_name: "Playwright CLI"
      short_description: "Automate and inspect browsers headlessly"
      default_prompt: "Use $playwright-cli to inspect and automate this web page with a headless-first workflow."
    policy:
      allow_implicit_invocation: true
  '';
  playwrightCliSkill = pkgs.runCommand "codex-playwright-cli-skill" { } ''
    mkdir -p "$out"
    cp -R ${playwrightCliSource}/skills/playwright-cli/. "$out/"
    chmod -R u+w "$out"
    rm -f "$out/SKILL.md"
    cat ${playwrightCliSkillHeader} > "$out/SKILL.md"
    awk '
      BEGIN { dashes = 0 }
      /^---$/ && dashes < 2 { dashes++; next }
      dashes >= 2 { print }
    ' ${playwrightCliSource}/skills/playwright-cli/SKILL.md >> "$out/SKILL.md"
    mkdir -p "$out/agents"
    cp ${playwrightCliSkillOpenaiYaml} "$out/agents/openai.yaml"

    substituteInPlace "$out/SKILL.md" \
      ${exactReplacement
        ''
          # Browser Automation with playwright-cli
        ''
        ''
          # Browser Automation with playwright-cli

          Use a headless-first workflow. Prefer snapshots and screenshots for inspection and feedback; do not open an interactive dashboard unless the user explicitly requests interactive annotation and a graphical session is available.
        ''} \
      ${exactReplacement
        ''
          # launch the dashboard for UI review / design feedback — user annotates the page, you receive the annotated screenshot, snapshot, and notes
          playwright-cli show --annotate
        ''
        ''
          # only after an explicit request for interactive annotation and after confirming a graphical session is available
          playwright-cli show --annotate
        ''} \
      ${exactReplacement
        ''
          Ask the user for UI review or design feedback. The user draws boxes on the live page and types comments; you receive the annotated screenshot, the snapshot of the marked region, and the user's notes. Use this whenever the user asks for "UI review", "design feedback", or to "ask the user what they think / want / mean":
        ''
        ''
          Use interactive annotation only when the user explicitly requests it and a graphical session is available. Otherwise use snapshots or screenshots for UI review and design feedback. When enabled, the user can draw boxes on the live page and add comments:
        ''
      }
    substituteInPlace "$out/references/test-generation.md" \
      ${exactReplacement
        ''
          playwright-cli show --annotate          # ask the user to point at something
        ''
        ''
          playwright-cli show --annotate          # explicit request plus graphical session only
        ''} \
      ${exactReplacement
        ''
          playwright-cli show --annotate         # ask the user to point somewhere
        ''
        ''
          playwright-cli show --annotate         # explicit request plus graphical session only
        ''
      }

    grep -Fq 'Use a headless-first workflow.' "$out/SKILL.md"
    grep -Fq 'user explicitly requests it and a graphical session is available' "$out/SKILL.md"
    if grep -R -n -E '^(allowed-tools|argument-hint|disable-model-invocation):|Use this whenever|show --annotate +# ask the user' "$out"; then
      echo "playwright-cli retains Claude-only metadata or unconditional GUI instructions" >&2
      exit 1
    fi
  '';
  skills = {
    docs-routing = srcRoot + "/src/docs-routing";
    diagnosing-bugs = diagnosingBugsSkill;
    tdd = tddSkill;
    codebase-design = codebaseDesignSkill;
    grilling = grillingSkill;
    handoff = handoffSkill;
    domain-modeling = domainModelingSkill;
    resolving-merge-conflicts = resolvingMergeConflictsSkill;
    writing-for-agents = writingForAgentsSkill;
    to-questionnaire = toQuestionnaireSkill;
    stop-slop = stopSlopSkill;
    playwright-cli = playwrightCliSkill;
  };
in
pkgs.runCommand "codex-base-generated-skills" { } ''
  mkdir -p "$out"
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: skill: ''
    mkdir -p "$out/${name}"
    cp -R ${skill}/. "$out/${name}/"
  '') skills)}

  for name in ponytail-review ponytail-audit ponytail-debt; do
    mkdir -p "$out/$name"
    cp -R ${ponytailSource}/skills/$name/. "$out/$name/"
  done

  mkdir -p "$out/improve"
  cp -R ${srcRoot}/src/improve/. "$out/improve/"
  chmod -R u+w "$out/improve"
  rm -rf "$out/improve/tests"
  cp ${improveSource}/LICENSE.md "$out/improve/LICENSE.md"

  if grep -R -n -E \
    '(/codebase-design|/grilling|/domain-modeling|/improve-codebase-architecture|Agent tool|subagent_type|Claude|claude|SendMessage|show --annotate +# ask the user)' \
    "$out"; then
    echo "generated skills contain stale host-agent wording" >&2
    exit 1
  fi
''
