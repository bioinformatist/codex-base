# Skill mechanics

The skill-specific branch of [`writing-for-agents`](SKILL.md): what changes when the document is a skill (frontmatter, the invocation choice, and router skills). Everything else about writing it is the universal reference in `SKILL.md`.

## Invocation

Two choices, trading the two loads:

- A **model-invoked** skill permits autonomous invocation. When the harness exposes its `description` for discovery, that description helps the agent decide when to invoke it. You can still type the skill's name: autonomous invocation adds agent discovery without removing human reach. Metadata exposure may consume context, so use the description as the skill's top-level context pointer. A model-invoked skill whose content is all reference can also be one home for shared reference: other guidance can point to it, so reference needed by several skills lives in one place. Mechanics: set `policy.allow_implicit_invocation: true` in `agents/openai.yaml`; this permits autonomous invocation and uses the description for discovery when the harness exposes it. Write a model-facing description carrying the trigger branches (the pointer-writing rules in `SKILL.md` apply in full).
- A **user-invoked** skill is explicit-only. Mechanics: set `policy.allow_implicit_invocation: false` in `agents/openai.yaml`; this prevents autonomous invocation, but the skill may still appear in catalogs or UI and its metadata may still have context cost. The human explicitly invokes it. Keep the `description` human-facing: a one-line summary with trigger lists stripped. The human also carries the cognitive load of remembering the skill exists.

Pick model-invocation only when the agent must reach the skill on its own. If it only ever fires by hand, make it user-invoked and let the human decide when to invoke it. Catalog visibility and metadata context cost depend on the harness.

Shared reference that two user-invoked skills both need should live in a plain file outside the skill system: external reference any skill can point at without altering its invocation policy.

## Splitting by invocation

The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a model-invoked skill when you have a distinct leading word that should trigger it on its own (a trigger word you actually use in your prompts). When the harness exposes the new description, its metadata may add context cost, so that independent reach has to be worth it.

## Router skills

When user-invoked skills multiply past what you can remember, that piled-up cognitive load is reduced by a **router skill**: one user-invoked skill that names the others and when to reach for each, so the human has one skill to remember instead of many. Router skills help humans discover explicit-only skills but do not change those invocation policies; the human still explicitly invokes each routed skill.
