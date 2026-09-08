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
        --replace-fail 'A discipline for hard bugs. Skip phases only when explicitly justified.' 'Start from a concrete symptom and gather read-only evidence. A reproduction tightens hypotheses but is not a prerequisite for inspecting relevant code, history, configuration, or logs.' \
        --replace-fail '**This is the skill.** Everything else is mechanical. If you have a **tight** pass/fail signal for the bug (one that goes red on _this_ bug), you will find the cause; bisection, hypothesis-testing, and instrumentation all just consume it. If you don'"'"'t have one, no amount of staring at code will save you.' '**Prefer a tight, symptom-specific pass/fail signal when one is practical.** Scale reproduction work to the request, risk, and available environment. Read-only evidence can still support a useful diagnosis when no runnable loop is available.' \
        --replace-fail 'Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**' 'Try the least invasive, highest-signal reproduction that fits the authorized scope. Stop when further experiments are disproportionate, require unavailable access, or would cross an authorization boundary; report the limitation.' \
        --replace-fail '5. **Replay a captured trace.** Save a real network request / payload / event log to disk; replay it through the code path in isolation.' '5. **Replay an authorized captured trace.** If writes and the captured data are in scope, save a redacted request, payload, or event log and replay it through the code path in isolation.' \
        --replace-fail '6. **Throwaway harness.** Spin up a minimal subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.' '6. **Temporary harness.** When implementation is authorized, use a minimal subset of the system that exercises the bug path without changing unrelated source or services.' \
        --replace-fail '7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs and look for the failure mode.' '7. **Property / fuzz loop.** For intermittent wrong output, use a bounded sample sized to the failure rate, cost, and risk; record the seed and observed rate.' \
        --replace-fail 'The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×, parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable; 1% is not, so keep raising the rate until it'"'"'s debuggable.' 'The goal is a reproduction rate high enough to distinguish hypotheses. Use a bounded number of attempts based on runtime and observed failure rate; add concurrency, stress, narrowed timing windows, or injected delays only when safe and within scope. Record both attempts and failures.' \
        --replace-fail 'Stop and say so explicitly. List what you tried. Ask the user for: (a) access to whatever environment reproduces it, (b) a redacted captured artifact (HAR file, log dump, core dump, screen recording with timestamps), or (c) permission to add temporary production instrumentation. Do **not** proceed to hypothesise without a loop.' 'Say so explicitly, list the evidence gathered and proportionate attempts made, and continue with labeled hypotheses where the evidence supports them. Ask only for missing access or a redacted artifact that is material to the diagnosis. Production instrumentation requires explicit authorization and must stay within the requested scope.' \
        --replace-fail '### Completion criterion: a tight loop that goes red' '### When a runnable loop is available' \
        --replace-fail 'Phase 1 is done when the loop is **tight** and **red-capable**: you can name **one command** (a script path, a test invocation, a curl) that you have **already run at least once** (show the invocation and its output, redacted), and that is:' 'Before relying on a runnable loop, name the command and run it when safe (show the invocation and its output, redacted). Prefer a loop that is:' \
        --replace-fail 'If you catch yourself reading code to build a theory before this command exists, **stop: jumping straight to a hypothesis is the exact failure this skill prevents.** No red-capable command, no Phase 2.' 'Read-only inspection may precede a red-capable command. Do not claim reproduction or a confirmed cause until the evidence supports it.' \
        --replace-fail 'Do not proceed until you have reproduced **and** minimised.' 'If reproduction is possible, minimise it proportionally; otherwise continue diagnosis from the available evidence and record the limitation.' \
        --replace-fail 'Generate **3–5 ranked hypotheses** before testing any of them. Single-hypothesis generation anchors on the first plausible idea.' 'Generate and rank the distinct hypotheses justified by the evidence. Consider alternatives before committing to the first plausible cause, but do not invent hypotheses to meet a quota.' \
        --replace-fail '**Show the ranked list to the user before testing.** They often have domain knowledge that re-ranks instantly ("we just deployed a change to #3"), or know hypotheses they'"'"'ve already ruled out. Cheap checkpoint, big time saver. Don'"'"'t block on it; proceed with your ranking if the user is AFK.' 'Report the ranked hypotheses and why they differ. Run safe, in-scope read-only probes without waiting; ask the user first only when a test needs a material choice, new access, or additional authorization.' \
        --replace-fail '## Phase 4: Instrument' '## Phase 4: Probe or instrument within scope' \
        --replace-fail '**Tag every debug log** with a unique prefix, e.g. `[DEBUG-a4f2]`. Cleanup at the end becomes a single grep. Untagged logs survive; tagged logs die.' 'Add debug logging only when source changes are authorized. Tag each added log with a unique prefix such as `[DEBUG-a4f2]`, track the changed paths, and remove only that temporary instrumentation before handoff.' \
        --replace-fail '## Phase 5: Fix + regression test' '## Phase 5: Authorized fix + regression test' \
        --replace-fail 'Write the regression test **before the fix**, but only if there is a **correct seam** for it.' 'When implementation is authorized, write the regression test **before the fix**, but only if there is a **correct seam** for it.' \
        --replace-fail '## Phase 6: Cleanup' '## Phase 6: Verify and report authorized changes' \
        --replace-fail 'Required before declaring done:' 'For an authorized implementation, verify proportionally before declaring done:' \
        --replace-fail '- [ ] Original repro no longer reproduces (re-run the Phase 1 loop)' '- [ ] The original repro no longer reproduces when a runnable loop exists' \
        --replace-fail '- [ ] Regression test passes (or absence of seam is documented)' '- [ ] The authorized regression test passes, or the absence of a correct seam is documented' \
        --replace-fail '- [ ] All `[DEBUG-...]` instrumentation removed (`grep` the prefix)' '- [ ] Temporary instrumentation added during this task is removed and its unique prefix no longer appears' \
        --replace-fail '- [ ] Throwaway prototypes deleted (or moved to a clearly-marked debug location)' '- [ ] Temporary artifacts created during this task are reported and removed only when that cleanup is authorized' \
        --replace-fail '- [ ] The hypothesis that turned out correct is stated in the commit / PR message, so the next debugger learns' '- [ ] The supported root cause and verification evidence are reported to the user'
      sed -i '/## Phase 1: Build a feedback loop/i ## Scope\n\nDiagnosis-only requests stop after reporting the supported cause, confidence, and next verification. Apply a fix or add a regression test only when implementation is authorized; keep changes within the approved scope.\n' "$out/SKILL.md"
    '';
    semanticGuard = ''
      grep -Fq 'Redact every secret first' "$out/SKILL.md"
      grep -Fq 'show the invocation and its output, redacted' "$out/SKILL.md"
      grep -Fq 'credential stays in the environment' "$out/SKILL.md"
      grep -Fq 'Diagnosis-only requests stop after reporting' "$out/SKILL.md"
      grep -Fq 'Read-only inspection may precede a red-capable command.' "$out/SKILL.md"
      grep -Fq 'do not invent hypotheses to meet a quota' "$out/SKILL.md"
      grep -Fq 'Production instrumentation requires explicit authorization' "$out/SKILL.md"
      ! grep -Fq -e 'no amount of staring at code' -e 'Refuse to give up' -e 'run 1000 random inputs' -e 'Loop the trigger 100×' -e 'Generate **3–5 ranked hypotheses**' "$out/SKILL.md"
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
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'call the Skill tool with "codebase-design" for the vocabulary' 'consult the available `codebase-design` guidance for the vocabulary'
    '';
    semanticGuard = ''
      grep -Fq 'accepted plan, specification, or repository evidence' "$out/SKILL.md"
      grep -Fq 'Ask the user only when the seam is materially ambiguous.' "$out/SKILL.md"
      grep -Fq 'Refactor only while green.' "$out/SKILL.md"
      ! grep -Fq 'Skill tool' "$out/SKILL.md"
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
        'use parallel sub-agents only when delegation is authorized and multi-agent tools are available, or compare several viable interfaces yourself'
      substituteInPlace "$out/DESIGN-IT-TWICE.md" \
        --replace-fail 'use this parallel sub-agent pattern' 'use this comparison workflow' \
        --replace-fail 'Before spawning sub-agents, write a user-facing explanation' 'Before producing alternatives, write a user-facing explanation' \
        --replace-fail 'Show this to the user, then immediately proceed to Step 2. The user reads and thinks while the sub-agents work in parallel.' 'Show this to the user, then proceed to Step 2 without requiring confirmation when the constraints are already settled.' \
        --replace-fail '### 2. Spawn sub-agents' '### 2. Produce alternatives' \
        --replace-fail 'Spawn 3+ sub-agents in parallel. Each must produce a **radically different** interface for the deepened module.' \
        'When delegation is authorized and multi-agent tools are available, use parallel sub-agents; otherwise produce distinct viable designs yourself. Each design must offer a meaningfully different interface for the deepened module.' \
        --replace-fail 'Prompt each sub-agent with a separate technical brief' 'Develop each design from the same technical brief' \
        --replace-fail 'Give each agent a different design constraint:' 'Give each design a different constraint:' \
        --replace-fail '- Agent 1:' '- Design 1:' \
        --replace-fail '- Agent 2:' '- Design 2:' \
        --replace-fail '- Agent 3:' '- Design 3:' \
        --replace-fail '- Agent 4 (if applicable):' '- Design 4 (if applicable):' \
        --replace-fail 'Include both [SKILL.md](SKILL.md) vocabulary and CONTEXT.md vocabulary in the brief so each sub-agent names things consistently with the architecture language and the project'"'"'s domain language.' 'Use both [SKILL.md](SKILL.md) vocabulary and available CONTEXT.md vocabulary so every design names things consistently with the architecture language and the project'"'"'s domain language.' \
        --replace-fail 'Each sub-agent outputs:' 'Each design includes:'
    '';
    semanticGuard = ''
      grep -Fq 'only when delegation is authorized' "$out/SKILL.md"
      grep -Fq 'otherwise produce distinct viable designs yourself' "$out/DESIGN-IT-TWICE.md"
      ! grep -Fq -e 'Before spawning sub-agents' -e '### 2. Spawn sub-agents' -e 'Each sub-agent outputs:' "$out/DESIGN-IT-TWICE.md"
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
        'Ask at most three independent, high-value frontier questions about material unresolved decisions in one round. Prefer a usable structured-question tool when available; otherwise ask concise numbered questions. Give your recommended answer.' \
        --replace-fail 'The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed.' 'The session is done when no material unresolved decision remains. Respect choices already settled by the user or authoritative evidence; do not exhaust speculative branches.' \
        --replace-fail 'Do not act on it until the user confirms you have reached a shared understanding.' \
        'End by reporting the shared understanding and open decisions. Do not implement automatically; implementation requires a separate user request.'
    '';
    semanticGuard = ''
      grep -Fq 'at most three independent, high-value frontier questions' "$out/SKILL.md"
      grep -Fq 'Discover repository and environment facts before asking questions' "$out/SKILL.md"
      grep -Fq 'Do not implement automatically' "$out/SKILL.md"
      grep -Fq 'structured-question tool when available' "$out/SKILL.md"
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

            When writing is allowed, write exactly one uniquely named Markdown file under `$TMPDIR` when set, otherwise `/tmp`; never write the handoff in the repository. Use a collision-resistant name such as `codex-handoff-<timestamp>-<random>.md`. When writing is forbidden, render the complete handoff in chat and create no file. Report the absolute path when a file is written and do not automatically start a new session.

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
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'Create files lazily: only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.' 'Create files lazily and only with write authorization. When writing is forbidden, render the proposed glossary or ADR change in chat. If authorized and no `CONTEXT.md` exists, create one when the first term is resolved; create `docs/adr/` only when the first ADR is needed.' \
        --replace-fail 'When a term is resolved, update `CONTEXT.md` right there.' 'When a term is resolved and writing is authorized, update `CONTEXT.md` right there. Otherwise render the exact proposed update in chat.'
    '';
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

            5. **Respect the exact lifecycle authorization.** Do not continue or abort the merge/rebase, commit, push, force-push, reset, discard with checkout, or clean up unless that exact action is already authorized. Do not repeat an approval request for an action the user has explicitly approved.
          ''
        }
    '';
    semanticGuard = ''
      grep -Fq 'Stage only verified conflict-resolution paths' "$out/SKILL.md"
      grep -Fq 'Do not repeat an approval request' "$out/SKILL.md"
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
        --replace-fail 'Write it to `to-questionnaire-<slug>.md` in the current directory (slug from the topic) and report the path.' 'When writing is allowed, write exactly one collision-resistant Markdown file under `$TMPDIR` when set, otherwise `/tmp`, and report its absolute path. When writing is forbidden, render the complete questionnaire in chat and create no file. Never overwrite an existing file, send or publish the questionnaire, or write it in the repository.' \
        --replace-fail 'Done when the file exists and every item the user named in step 2 is covered by a question.' 'Done when either the complete questionnaire is rendered in chat or the authorized file exists, and every item the user named in step 2 is covered by a question.' \
        --replace-fail '**From:** <the user>, **To:** <the recipient>, **How your answers will be used:** <where they go>' '**From role:** <role>, **To role:** <role>, **How your answers will be used:** <where they go>'
      sed -i '/Turn something the user/a Never request credentials, authentication tokens, API keys, passwords, or other secret values. Prefer roles and only include personal information necessary for the questionnaire.' "$out/SKILL.md"
    '';
    semanticGuard = ''
      grep -Fq 'otherwise `/tmp`' "$out/SKILL.md"
      grep -Fq 'the complete questionnaire is rendered in chat or the authorized file exists' "$out/SKILL.md"
      grep -Fq 'every item the user named in step 2 is covered by a question' "$out/SKILL.md"
      grep -Fq 'Never overwrite an existing file, send or publish' "$out/SKILL.md"
      grep -Fq 'Never request credentials' "$out/SKILL.md"
    '';
  };
  waitWhatSkill = mkMattPocockSkill {
    name = "wait-what";
    path = "skills/productivity/wait-what";
    description = "Explicit-only request to restate the previous explanation plainly in the current conversation language while preserving facts and uncertainty.";
    displayName = "Wait, What?";
    shortDescription = "Restate the last explanation plainly";
    defaultPrompt = "Use $wait-what to restate the last explanation plainly in the current conversation language.";
    allowImplicit = false;
    postPatch = ''
      substituteInPlace "$out/SKILL.md" \
        --replace-fail 'Wait, I don'"'"'t understand where you'"'"'ve got to here. Re-pitch that: give me a little bit of context, talk in ASD-STE100 Simplified Technical English, and use the ubiquitous language from `CONTEXT.md` (follow `CONTEXT-MAP.md` to the right one if the repo has more than one).' 'Restate the previous explanation in the current conversation language. Add only the context needed to understand it, use plain language and the project'"'"'s established terms, and preserve all facts, constraints, caveats, and uncertainty. Do not write a file or change the underlying decision.'
    '';
    semanticGuard = ''
      grep -Fq 'current conversation language' "$out/SKILL.md"
      grep -Fq 'preserve all facts, constraints, caveats, and uncertainty' "$out/SKILL.md"
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
    wait-what = waitWhatSkill;
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
    chmod -R u+w "$out/$name"
  done

  substituteInPlace "$out/ponytail-review/SKILL.md" \
    --replace-fail 'The diff'"'"'s best outcome is getting shorter.' 'The best outcome is the lowest supported complexity that preserves correctness, accepted behavior and interfaces, and necessary checks.' \
    --replace-fail '✅ `L12-38: stdlib: 27-line validator class. "@" in email, 1 line, real validation is the confirmation mail.`' '✅ `L12-38: stdlib: hand-rolled URL parser for validated inputs. The standard URL parser, preserving the accepted input and error behavior.`' \
    --replace-fail 'End with the only metric that matters: `net: -<N> lines possible.`' 'End with the supported finding count. You may estimate net lines as secondary context, never as the acceptance criterion.' \
    --replace-fail 'If there is nothing to cut, say `Lean already. Ship.` and stop.' 'If there is nothing supported to cut, say `Lean for over-engineering. Correctness and shipping readiness were not assessed.` and stop.' \
    --replace-fail 'Scope: over-engineering and complexity only. Correctness bugs, security holes,' 'Scope: over-engineering and complexity only. Preserve accepted interfaces, behavior, and required tests. Correctness bugs, security holes,'

  sed -i '/Use when the user says "audit this$/ { N; s/"audit this\n  codebase", //; }' "$out/ponytail-audit/SKILL.md"
  substituteInPlace "$out/ponytail-audit/SKILL.md" \
    --replace-fail '## Hunt

Deps the stdlib or platform already ships' '## Hunt

Report a cut only when repository evidence supports it and the replacement preserves accepted behavior and checks.

Deps the stdlib or platform already ships' \
    --replace-fail 'End with `net: -<N> lines, -<M> deps possible.` Nothing to cut: `Lean already. Ship.`' 'End with the supported finding count; estimated lines and dependencies are secondary context. Nothing supported to cut: `Lean for over-engineering. Correctness and shipping readiness were not assessed.`' \
    --replace-fail 'Scope: over-engineering and complexity only. Correctness bugs, security holes,' 'Scope: over-engineering and complexity only. Preserve accepted interfaces, behavior, and required tests. Correctness bugs, security holes,'

  substituteInPlace "$out/ponytail-debt/SKILL.md" \
    --replace-fail '`grep -rnE '"'"'(#|//) ?ponytail:'"'"' .`  (add other comment prefixes if your stack uses them)' '`grep -rnE --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=build --exclude-dir=dist --exclude-dir=out --exclude-dir=target --exclude-dir=.next --exclude-dir=coverage '"'"'(#|//) ?ponytail:'"'"' .` (add other comment prefixes if the stack uses them)' \
    --replace-fail 'Reads and reports only, changes nothing. To persist it, ask and it writes the
ledger to a file (e.g. `PONYTAIL-DEBT.md`). One-shot. "stop ponytail-debt" or
"normal mode" to revert.' 'Reads and reports only; never writes, edits, stages, or persists a ledger. One-shot. "stop ponytail-debt" or "normal mode" to revert.'

  grep -Fq 'Preserve accepted interfaces, behavior, and required tests.' "$out/ponytail-review/SKILL.md"
  grep -Fq 'Correctness and shipping readiness were not assessed.' "$out/ponytail-review/SKILL.md"
  grep -Fq 'Preserve accepted interfaces, behavior, and required tests.' "$out/ponytail-audit/SKILL.md"
  ! grep -Ezq '"audit this[[:space:]]+codebase"' "$out/ponytail-audit/SKILL.md"
  grep -Fq -- '--exclude-dir=node_modules' "$out/ponytail-debt/SKILL.md"
  grep -Fq -- '--exclude-dir=.git' "$out/ponytail-debt/SKILL.md"
  grep -Fq 'never writes, edits, stages, or persists a ledger' "$out/ponytail-debt/SKILL.md"

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
