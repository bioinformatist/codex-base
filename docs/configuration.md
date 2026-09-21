[简体中文](configuration.zh-CN.md) · [Back to Quick start](../README.md#quick-start)

# Configuration and troubleshooting

Use this page for runtime settings, optional documentation-service credentials, and planning-capability troubleshooting. Installation and the shared CLI/desktop workflow are in the [README](../README.md#first-workflow).

- [Native Codex configuration](#native-codex-configuration)
- [Model choice](#model-choice)
- [Context7 authentication](#context7-authentication)
- [Temporary context-management waiver](#temporary-context-waiver)
- [Reverting runtime settings](#reverting-runtime-settings)

## Native Codex configuration

Home Manager already supplies these runtime defaults. For other installations, merge this fragment once into the execution host's persistent Codex config (`CODEX_HOME/config.toml`, default `~/.codex/config.toml`):

```toml
plan_mode_reasoning_effort = "high"

[features]
context_management.experimental_mode = true
code_mode.enabled = true
default_mode_request_user_input = true
```

| Setting | Purpose and dependency |
|---|---|
| `plan_mode_reasoning_effort` | Gives Plan Mode more reasoning effort; it does not change the model. |
| `context_management.experimental_mode` | Requests experimental native context management. Actual availability depends on the backend, account, starting model, and live session. Follow the shared [task-start instructions](../README.md#first-workflow). |
| `code_mode.enabled` | Requests Code Mode, which requires the matching Code Mode companion host. Home Manager installs that host; a standalone CLI may not have it. Set this to `false` if the host is unavailable. |
| `default_mode_request_user_input` | Makes structured questions available in Default Mode. It does not automatically invoke Grilling or another question workflow. |

This is a merge fragment, not a replacement file or per-start flag. Keep unrelated configuration intact. `plan_mode_reasoning_effort` is top-level; the three feature toggles belong in `[features]`. Update existing keys in place. Replace existing boolean `context_management` or `code_mode` entries with the dotted form above; do not keep both a boolean and table form or duplicate a TOML key.

After saving, [reload the execution runtime](../README.md#reload-after-an-update). Configured flags request features; they do not prove that the live task provides them or guarantee better results. The experiment requires an eligible ChatGPT session on the supported OpenAI backend; consult the current [model documentation](https://learn.chatgpt.com/docs/models#experimental-context-management) for availability. Missing native context management during formal planning is handled through the [per-plan waiver](#temporary-context-waiver), not repeated configuration changes.

The official [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) covers context management, Code Mode, and Plan Mode effort. The Default Mode question flag is supported by the verified Codex [feature declaration](https://github.com/openai/codex/blob/f0a1b8f0849d90960bc406b848f32e5a129b0457/codex-rs/features/src/lib.rs) and [request-user-input tests](https://github.com/openai/codex/blob/f0a1b8f0849d90960bc406b848f32e5a129b0457/codex-rs/core/tests/suite/request_user_input.rs).

## Model choice

These choices apply independently of the installation method. Home Manager manages the Sol defaults; installing the plugin alone leaves the user's model configuration intact.

| Work | Model and reasoning | Reason |
|---|---|---|
| Routine implementation, audits, research, and maintenance | `gpt-5.6-sol`, `medium` | Balances capability, latency, and token use. |
| Bounded planning without a native context-management requirement | `gpt-5.6-sol`, `high` | Allows more reasoning for constraints and tradeoffs while retaining the same model. Formal Improve planning still needs its prerequisite met or explicitly waived. |
| Formal Improve planning with native context management | Start a new `gpt-6-astra` task, then enter Plan Mode | The starting-model eligibility check makes switching an existing Sol task insufficient. |
| Difficult product or architecture choices, conflicting evidence, or unusually long investigations | `gpt-6-astra` | Its stronger reasoning can justify the extra cost even apart from the context-management requirement. |

See the official [Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) and [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) model pages. Higher effort or a stronger model is not automatically necessary for every plan.

The [README](../README.md#first-workflow) gives the CLI and desktop startup steps. For CLI users keeping Sol as their default, `codex -m gpt-6-astra` is the simplest one-off choice. Setting Astra as the persistent default or launching a personally configured Astra profile also works; Codex Base does not provide that profile. The official [CLI reference](https://learn.chatgpt.com/docs/developer-commands?surface=cli) documents these commands.

In the pinned Codex 0.155.1 implementation, the scope matters:

- Ordinary `/model` selection updates the current chat and attempts to persist the model and reasoning defaults. Plan Mode's “Plan mode only” reasoning choice instead saves the Plan effort override without saving a model default. See the [selection handlers](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/chatwidget/model_popups.rs).
- `/new` reads effective server defaults while preserving explicit launch-model and profile settings. It does not simply copy the previous chat's model. See [new-session configuration](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/app/new_session.rs) and its [tests](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/app/tests/new_session_tests.rs).
- Therefore `/model` → Astra → `/new` can start with Astra if the new default was saved and is effective. It can start with Sol if Sol remains the effective default or launch override. Inspect `/status`, `/debug-config`, and any configuration-save warning before drawing conclusions about a particular installation.

Context management has a separate [initialization check](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/core/src/session/token_budget.rs): its starting-model requirement is why a new Astra task matters, regardless of how that starting model was selected.

## Context7 authentication

Mintlify and Context7 supply public documentation over MCP, Codex's protocol for connecting external tools. Both installations use the same routing skill: Mintlify first, then Context7 when necessary, an authenticated Context7 fallback if the anonymous result is insufficient, and finally official primary sources. Native configuration can replace a plugin's same-name endpoint. Queries must contain only focused public lookup terms, never secrets or private content.

Anonymous Context7 needs no account. Authentication is optional and belongs to each user; Codex Base never bundles a shared key.

### Plugin-only installation

To retain anonymous-first routing, add a separate OAuth fallback:

```console
codex mcp add context7_auth --url https://mcp.context7.com/mcp/oauth
codex mcp login context7_auth
```

This leaves the plugin's `context7` endpoint unchanged. Context7's official [`npx ctx7 setup --codex`](https://context7.com/docs/clients/codex) command instead creates native authenticated configuration under the same `context7` name and may add agent guidance. That configuration overrides the plugin default. Use it only when authenticated Context7 should be the primary connection rather than a fallback.

### Nix / Home Manager

Point the module at a runtime secret file:

```nix
programs.codexBase.context7ApiKeyFile = /run/secrets/context7-api-key;
```

Keep the plaintext key out of Nix source and the Nix store. Manage the file with a secret manager such as SOPS or agenix. Home Manager retains anonymous `context7` and adds `context7_auth`, whose wrapper reads the file and passes `CONTEXT7_API_KEY` to the local MCP server.

### Verify authentication

After either change, [reload the runtime](../README.md#reload-after-an-update) and run `codex mcp list --json`. Registration alone does not prove that the credential works. For a one-time diagnostic, ask Codex to use `context7_auth` for a focused public documentation lookup. An `auth_status` of `unsupported` is normal for the Nix stdio adapter because Codex does not manage its API-key authentication.

An authentication prompt opened by anonymous Context7 pauses that tool call; it is not evidence that the authenticated fallback ran. Resolve or dismiss the prompt so the call can return and routing can continue.

<a id="temporary-context-waiver"></a>

## Temporary context-management waiver

If formal Improve planning lacks native context management, check the session's live tools and preserve existing configuration. Do not edit local configuration, repeatedly toggle features, modify skills, or rebuild the environment to work around this unavailability.

To continue, the user must explicitly waive only the native context-management prerequisite for one named plan and its same-scope review. This is not an automatic or global waiver: Plan Mode, structured questions, read-only planning, and all other authorization boundaries remain required. For example:

```text
I approve waiving the native context-management prerequisite only for this plan and its same-scope review. Keep Plan Mode, structured questions, read-only planning, and all other authorization boundaries. Do not change configuration or global skills for this waiver.
```

A waiver neither restores the capability nor guarantees planning quality. Once live availability is verified, new plans need no exception. Default Mode implementation, audits, and routine lifecycle bookkeeping are unaffected. Normal installation settings are not a fix for temporary service unavailability.

Historical context: on **2026-09-12**, Tibo (@thsottiaux) [announced](https://x.com/thsottiaux/status/2098612714704891959) disabling an opt-in context-management experiment that could cause early stops or replies to older messages. A [user-provided screenshot](evidence/2026-09-12-tibo-context-management.png) is retained as supporting evidence. The announcement identifies no configuration key and does not establish current access for a particular account, subscription, or client.

## Reverting runtime settings

Preserve unrelated configuration and restore `plan_mode_reasoning_effort` to its previous value. Explicitly set `context_management.experimental_mode`, `code_mode.enabled`, and `default_mode_request_user_input` to `false` when disabling these features. Deleting keys from an overlay or reverting source does not remove values already persisted in `config.toml`.

Home Manager users must also reverse the managed overlay before activation, or activation will set the managed values again. Follow the [reload instructions](../README.md#reload-after-an-update) after changing the effective configuration.
