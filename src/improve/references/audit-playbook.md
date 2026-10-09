# Audit Playbook

Use this alongside Ponytail Audit for Improve-specific dependency, developer experience, documentation, and product direction findings. Give a scout only the relevant section and the finding format. Adapt depth to repo size.

A finding is only a finding with evidence. "Probably has N+1 queries somewhere" is not a finding; `orders/api.ts:142 issues one query per order item inside a loop` is.

---

## 1. Dependencies & Migrations

- Major-version lag on core framework/runtime (not every minor bump — the ones with real cost to staying behind: EOL, security-fix cutoffs, ecosystem incompatibility).
- Deprecated APIs in use that have announced removal timelines.
- Abandoned dependencies (no release in years, archived repos) on critical paths.
- Duplicate dependencies solving the same problem (two date libs, two HTTP clients).
- Lockfile/manifest drift, version pinning inconsistencies across a monorepo.
- For each migration candidate, estimate blast radius (files touched) — that drives effort and whether to recommend it at all.

## 2. DX & Tooling

- Missing or broken: typecheck script, lint config, formatter, pre-commit hooks, editorconfig.
- Slow feedback loops: dev-server or test startup measured in minutes, no watch mode, CI without caching.
- Onboarding friction: README setup steps that are wrong/incomplete, undocumented required env vars, no `.env.example`.
- Missing `AGENTS.md` — for repos where agents will execute the plans, this is high-leverage: recommend one and include its outline as a plan.
- Error messages/logging: unstructured logs on services, missing request IDs/correlation, debugging requiring code changes.

## 3. Docs

Lowest default priority — only flag where absence has a concrete cost:

- Public API surface (published packages) without reference docs.
- Architectural decisions nobody can reconstruct (why X over Y) for actively-contested areas.
- Stale docs that are actively wrong (worse than missing) — setup instructions, API examples that no longer compile.

## 4. Direction — features & where to take this next

Forward-looking: not what's broken, but what this codebase wants to become. **Grounding rule:** every suggestion must cite evidence from the repo itself — a suggestion that could apply to any project in the category ("add dark mode", "add AI") is noise, not a finding. Sources of grounded direction signal:

- **Unfinished intent**: TODO/FIXME clusters around one theme, feature flags never rolled out, stubbed or half-built modules, commented-out feature code, abandoned mid-feature work visible in git history.
- **Stated-but-undelivered**: README/docs/roadmap promises with no corresponding code, CLI flags or config options that are no-ops, issue templates for features that don't exist. A PRD or `PRODUCT.md` that names users, use cases, or a direction the code hasn't caught up to is the strongest grounding signal there is — prefer it over inferred intent, and never propose something a decision doc already rejected (note the contradiction instead).
- **Surface asymmetries**: one-directional pairs (export without import, create without bulk-create, webhooks out but not in), entities with CRUD minus one, a public API that internal code clearly needed and hand-rolled around.
- **The adjacent possible**: capabilities the existing architecture makes disproportionately cheap — a plugin system one interface away, a public API one route file from the existing service layer, an integration the data model already supports.
- **Friction worth productizing**: things users of this project evidently do by hand around it (visible in docs, examples, issues) that the project could absorb.

Direction findings use the standard format with two adaptations: **Impact** is product/user value (who wants this and why now), and **Confidence** reflects how grounded the evidence is — not certainty that it's the right call. Strategy belongs to the maintainer; the advisor's job is grounded options with honest trade-offs. Effort estimates here are coarser; say so. Plans for selected direction findings are usually a *design/spike plan* (investigate, prototype, define the API, list open questions) rather than a build-everything plan — scope them that way.

---

## Finding format

Every finding, from every category and every subagent, comes back in this shape:

```markdown
### [CATEGORY-NN] Short imperative title

- **Evidence**: `path/file.ts:123` — one-sentence description of what's there. (Repeat per location; 2–5 strongest locations, note "and ~N similar sites" if widespread.)
- **Impact**: What goes wrong / what's being paid because of this. Concrete: "every order-list render issues 1+N queries", not "suboptimal".
- **Effort**: S (hours) / M (a day-ish) / L (multi-day) — for the *fix*, including tests.
- **Risk**: What the fix could break; LOW/MED/HIGH plus one line why.
- **Confidence**: HIGH (read the code, certain) / MED (strong signal, needs verification) / LOW (smell, needs investigation). LOW-confidence findings may be reported but get an "investigate" plan, not a "fix" plan.
- **Fix sketch**: 1–3 sentences. Not the plan — just enough to judge effort honestly.
```

## Prioritization rubric

Order findings by **leverage = impact ÷ effort, discounted by confidence and fix-risk**. Tiebreakers:

1. Anything that unblocks other findings (verification baseline, characterization tests) floats up.
2. Security findings with HIGH confidence float above equivalent-leverage non-security findings.
3. Prefer findings whose fix has a clean verification story — executor models succeed at those.
4. "Not worth doing" is a valid verdict; record it with one line of reasoning so the user knows it was considered.
