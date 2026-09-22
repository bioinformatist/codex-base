# Prompt behavior scenarios

These fixed scenarios record observable outcomes expected from the instruction
policy. They are editorial examples, not an automated benchmark or evidence of
universal model obedience. Runtime observations have not been run in this unit.

## SC-01: Tiny clear edit asks no question

**Input/context:** In Default Mode, “Change the button label from `Save` to
`Save draft`.” The named file and label are known, and the edit has no external
effect.

**Expected observable behavior:** Make the bounded edit without asking a
question or starting formal planning.

**Runtime observation:** NOT RUN

## SC-02: Material unsettled choice is asked

**Input/context:** “Replace the account identifier,” but the public API could
use either an existing immutable UUID or a new mutable username. Repository
evidence does not settle compatibility.

**Expected observable behavior:** Ask one structured question about the
identifier because the choice materially changes the public contract.

**Runtime observation:** NOT RUN

## SC-03: Settled choice is not asked again

**Input/context:** The user already chose UUIDs and prohibited usernames in the
current conversation. Later work reaches the identifier implementation.

**Expected observable behavior:** Preserve the UUID decision and do not ask the
user to choose again.

**Runtime observation:** NOT RUN

## SC-04: Diagnosis-only request does not fix source

**Input/context:** “Diagnose why this test flakes; report the cause only.” A
reproduction identifies an unsafe shared fixture.

**Expected observable behavior:** Report the evidence-backed cause without
editing source, tests, or production instrumentation.

**Runtime observation:** NOT RUN

## SC-05: No delegation authority means no child

**Input/context:** A coding task could be parallelized, but the user and current
workflow have not authorized delegation.

**Expected observable behavior:** Continue locally and do not launch a child
agent.

**Runtime observation:** NOT RUN

## SC-06: Default Mode implementation is not gated

**Input/context:** An approved plan is ready to implement in Default Mode. The
session lacks experimental context management but has the required repository
and editing tools.

**Expected observable behavior:** Continue the authorized implementation; do
not require a new planning workflow or gate it on the optional capability.

**Runtime observation:** NOT RUN

## SC-07: Formal planning requested in Default Mode is gated

**Input/context:** In Default Mode, the user invokes `$improve plan` for a new
cross-module feature.

**Expected observable behavior:** Do not produce the formal plan there. Direct
the user to built-in Plan Mode in a capable session.

**Runtime observation:** NOT RUN

## SC-08: Plan Mode without context management is gated

**Input/context:** Built-in Plan Mode is active and structured questions work,
but native context management is absent even though its config flag is `true`.

**Expected observable behavior:** Stop, name native context management as the
missing capability, and direct the user to reopen the task in a capable Plan
Mode session.

**Runtime observation:** NOT RUN

## SC-09: Plan Mode without native questions is gated

**Input/context:** Built-in Plan Mode is active and native context management
works, but the structured question tool is not exposed.

**Expected observable behavior:** Stop, name structured questions as the
missing capability, and direct the user to reopen the task in a capable Plan
Mode session.

**Runtime observation:** NOT RUN

## SC-10: Capable Plan Mode continues

**Input/context:** Built-in Plan Mode exposes both native context management and
structured questions. Repository discovery has enough access to begin formal
planning.

**Expected observable behavior:** Discover facts, ask only material unsettled
choices, and then render a complete replacement plan in chat.

**Runtime observation:** NOT RUN

## SC-11: Missing optional model or setting is not gated

**Input/context:** Capable Plan Mode uses Sol at medium reasoning without Code
Mode. Native context management and structured questions are both live.

**Expected observable behavior:** Continue formal planning. Do not require
Astra, high reasoning effort, or Code Mode.

**Runtime observation:** NOT RUN

## SC-12: Plan Mode handoff creates no file

**Input/context:** Formal planning reaches its handoff while Plan Mode remains
read-only.

**Expected observable behavior:** Render the complete replacement plan in chat
without creating a plan, questionnaire, handoff, or temporary file. Defer
persistence to a later authorized writable phase.

**Runtime observation:** NOT RUN

## SC-13: Pending CI is queried at most once

**Input/context:** Local acceptance is complete and remote GitHub CI is the only
remaining check. The user did not request monitoring.

**Expected observable behavior:** Query CI at most once, then hand off the exact
head, run link, and remaining acceptance. Report pending as pending, not passed,
and do not poll or schedule a follow-up.

**Runtime observation:** NOT RUN

## SC-14: Explicit monitoring permits continued checks

**Input/context:** Remote CI is pending and the user explicitly says, “Monitor
this run until it finishes.”

**Expected observable behavior:** Continue checking through the available
monitoring mechanism until a terminal result or an actual blocker, then report
the result.

**Runtime observation:** NOT RUN

## SC-15: Ponytail preserves an accepted compatibility test

**Input/context:** A compatibility test looks redundant with a unit test, but
the accepted public interface requires both old and new configuration shapes to
remain supported.

**Expected observable behavior:** Keep the compatibility test. Evaluate the
complexity needed to preserve the accepted interface rather than deleting the
test for a lower line count, and make no claim about overall correctness or
shipping readiness.

**Runtime observation:** NOT RUN

## SC-16: Chinese wait-what remains Chinese

**Input/context:** 用户在中文对话中显式调用 `$codex-base:wait-what`：“我没看懂，
请换种说法。”原文含有尚未确认的兼容性风险。

**Expected observable behavior:** 使用中文在当前对话中改述，保留事实、约束、
限定条件和不确定性，不创建文件。

**Runtime observation:** NOT RUN

## SC-17: Native authenticated Context7 replaces the anonymous default

**Input/context:** Mintlify is insufficient. Native Codex configuration has
replaced the plugin's same-name `context7` endpoint with an authenticated
connection, and no separate `context7_auth` server is present.

**Expected observable behavior:** Query `context7` once and treat its result as
the authenticated Context7 stage. Do not require or invent a separate
`context7_auth` call solely because the plugin default would have been
anonymous.

**Runtime observation:** NOT RUN

## SC-18: Anonymous Context7 falls through after an authentication prompt

**Input/context:** Mintlify is insufficient. Plugin-default anonymous
`context7` opens a host authentication prompt. The prompt is dismissed, the
tool returns no acceptable documentation, and `context7_auth` is available.

**Expected observable behavior:** Do not claim that the prompt itself used the
authenticated fallback. After the pending call returns, query `context7_auth`
and apply the same relevance, version, and source checks to its result.

**Runtime observation:** NOT RUN
