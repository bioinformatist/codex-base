[简体中文](workflow.zh-CN.md) · [README](../README.md)

# Improve workflow

<a id="overview"></a>

## Overview

Improve is a planning and execution coordination workflow. For a small, clear task, edit directly. For work that needs a reviewed plan, the main path is:

**Clarify and check facts → Review the plan → Authorize → Execute in isolation → Verify and simplify → Independent review → Checkpoint**

A checkpoint is a reviewed, saved commit. Integration and external acceptance are separate steps and require their own authorization and evidence. Planning and review consume usage; they do not guarantee fewer tokens or lower cost.

![Improve workflow overview](assets/codex-base-workflow.svg)

[① Execution lanes](#execution) · [② Verification](#verification)

The formal planning target is `gpt-6.2-astra` with `xhigh` reasoning in built-in Plan Mode. An independent plan reviewer uses the same model and effort and may use read-only Default Mode. Both require direct native `new_context`, callable `get_context_remaining`, and structured questions available in that mode. Check trusted model/effort/mode metadata and actual tool exposure, including nested catalogs; a missing direct entry in a nested catalog does not prove a tool is absent. Check availability without actively switching context. A model name, configuration flag or context-window size alone is insufficient. Missing or unverified prerequisites make formal planning BLOCKED; ordinary Plan Mode can still offer a draft. Only the user's explicit choice permits an older Astra temporarily, with the same mode and capability requirements; there is no automatic switch. Code Mode remains a recommendation. See [configuration](configuration.md#native-codex-configuration) for troubleshooting.

Improve resolves material choices and presents a complete plan in chat without writing files. After the user accepts it and authorizes implementation, a writable phase can save the plan and execute it. Implementation, audits, and routine lifecycle bookkeeping do not require a new formal plan.

<a id="execution"></a>

## ① Execution lanes

An execution lane selects the implementation root's model and effort. The
connected client reads canonical roles and keeps the same loaded root through
continuation and revision. Native tools own team dispatch, messages and waits;
there is no model fallback or coordinator root timer. Sol 6.2 means
`gpt-6.2-sol`, Astra 6.2 means `gpt-6.2-astra`, and Luna means `gpt-6-luna`.
All roles use medium verbosity.

![Execution lane selection](assets/codex-base-routing.svg)

| Lane | Model / effort | Use when |
|---|---|---|
| economy | Luna / low | A limited task has clear boundaries, materials, and checks. |
| standard | Sol 6.2 / medium | Ordinary engineering work. |
| deep | Sol 6.2 / xhigh | Complex or high-risk engineering work. |
| writer | Astra 6.2 / xhigh | Writing has settled materials and conclusions and can be accepted independently. |

If missing or conflicting facts prevent accurate writing, writer stops the
affected work and reports the gap. Atomic code and documentation stay in one
engineering task. Scout (Sol 6.2/medium) reports sources and unresolved evidence
gaps. Scout and visual (Astra 6.2/xhigh) observe within the implementation team's
shared workspace-write authority. They are not separate read-only sandboxes. Formal
reviewer (Astra 6.2/high) starts in a fresh local read-only root; its descendants
inherit that boundary, with verified read-only external tools and image access.
Implementation shares 300k native rollout units; review has its own 100k.
Reminders are 150k/75k/30k and 50k/25k/10k remaining respectively. These are native
accounting units, not context length or a strict zero-overshoot promise.
See [architecture](architecture.md#executor-routing) and [new-task usage](improve-lifecycle.md).

Examples:

- **Ordinary engineering:** a reviewed plan selects standard, identifies paths and checks, and sends the result to independent review.
- **Settled writing:** a plan supplies writer with facts, conclusions, audience, terminology, paths, and acceptance. Writer stops affected work and reports missing or conflicting facts when they prevent accurate writing.
- **Original image analysis:** visual receives the original and collection evidence, then returns observations with locations and uncertainty to the executor and reviewer.

<a id="verification"></a>

## ② Verification

The plan chooses verification separately from the execution lane. Run the tests needed for the change, verify and simplify each implementation step, and independently review the candidate. A review and checkpoint bind to the candidate and required evidence; changed inputs can invalidate approval. Freeze every descendant and background terminal before capture; keep the implementation root loaded during independent review. Lost connection or root stops the task without a new budget. Permission to review does not itself authorize a commit, integration, push, or publication.

Before READY, the existing independent plan review traces the hardest acceptance case: operator authority → fixed inputs → artifacts and candidate binding → failure handling → final judge. Finish generation, confirm stopped agents and terminals, capture, check synchronization in the frozen Git workspace, export, then build/test outside the candidate. A package built before capture needs verified unchanged-input binding or a rebuild from the export. For bootstrap upgrades, distinguish the installed tool and its permissions from candidate-delivered capabilities; keep this run's executable, coordinator and roles fixed. A candidate cannot supply a missing capability needed to accept itself.

For model-backed behavior, select source/configuration evidence, existing events, static scenarios, offline protocol fixtures and builds without model calls. Do not launch dedicated subscription-consuming A/B, smoke, real-child, end-to-end, budget-limit or prompt experiments. Observe live behavior during otherwise required normal work; record unobserved behavior as `NOT RUN`. This leaves other verifiable work available, while required capabilities and gates still need their own evidence. A specified freeze procedure alone does not establish observed termination.

Review covers exactly `scope` and the plan's required evidence IDs; only
explicitly declared deferred acceptance may remain pending. A native-confirmed
failed/interrupted implementation can also be submitted with a budget_exhausted,
timed_out, cancelled or failed outcome, after the same connection, loaded-root,
freeze, candidate/scope and current PASS evidence checks. Unknown/running turns,
invalid completed reports and executor STOPPED do not qualify. Only a normally
completed valid independent APPROVE with unchanged inputs grants approval.

Failed turns and active cancellations retain bounded raw/parsed reports,
diagnostics, native status/errors and last known usage. Cancellation grants no
approval. Missing terminal confirmation or trustworthy final usage remains
explicitly unknown. For another review, organize `dossier.notes` as verified
facts with sources, unresolved questions, and candidate/input changes. The new
reviewer receives current validated evidence and only the immediately preceding
review snapshot, then makes an independent judgment. See the
[connected workflow](../src/improve/references/closing-the-loop.md).

![Verification paths](assets/codex-base-verification.svg)

Two conditional paths can both apply:

- **Visual:** when original-image analysis is needed, provide the original and collection evidence. The observing role returns observations with locations and uncertainty for implementation and review. It does not collect screenshots or replace independent review.
- **Bend:** Bend 2 is a language and tool for formal proofs of selected properties. When the plan selects proof work for an actual Bend implementation, `bend-proof` supplies evidence for specified properties and coverage limits to review. It supplements tests and independent review; it does not prove Rust, compilers, binaries, or the runtime environment. Neither installation automatically installs Bend or Lean, and the workflow does not migrate code to Bend to demonstrate proof capability.
