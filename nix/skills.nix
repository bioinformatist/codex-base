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
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'hand off to the `/improve-codebase-architecture` skill with the specifics' \
        'recommend a follow-up architecture review with the specifics'
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
            **Test only at pre-agreed seams.** Before writing any test, write down the seams under test and confirm them with the user. No test is written at an unconfirmed seam. You can't test everything — agreeing the seams up front is how testing effort lands on the critical paths and complex logic instead of every edge case.

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
      substituteInPlace "$out/DESIGN-IT-TWICE.md" \
        --replace-fail 'Spawn 3+ sub-agents in parallel using the Agent tool. Each must produce a **radically different** interface for the deepened module.' \
        'When multi-agent tools are available, spawn 3+ sub-agents in parallel; otherwise produce 3 distinct designs yourself. Each must produce a **radically different** interface for the deepened module.'
    '';
  };
  grillingSkill = mkMattPocockSkill {
    name = "grilling";
    path = "skills/productivity/grilling";
    description = "Explicit-only interview loop for stress-testing a plan, decision, or idea. Use only when the user asks to grill, interrogate, interview, or stress-test their thinking before action.";
    displayName = "Grilling";
    shortDescription = "Stress-test a plan by asking one question at a time";
    defaultPrompt = "Use $grilling to stress-test this plan before implementation.";
    allowImplicit = false;
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

            Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

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

            4. Discover the project's **automated checks** and run them — typically typecheck, then tests, then format. Fix anything the merge broke.

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
    diagnosing-bugs = diagnosingBugsSkill;
    tdd = tddSkill;
    codebase-design = codebaseDesignSkill;
    grilling = grillingSkill;
    handoff = handoffSkill;
    domain-modeling = domainModelingSkill;
    resolving-merge-conflicts = resolvingMergeConflictsSkill;
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
