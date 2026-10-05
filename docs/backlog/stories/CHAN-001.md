---
id: CHAN-001
title: Confirm the preset delivery route and the filter call shape
slug: confirm-the-preset-delivery-route-and-th
epic: EPIC-06
type: spike
status: in-review
phase: REVIEW
branch: story/CHAN-001-confirm-the-preset-delivery-route-and-th
depends_on: []      # story ids; phase.sh refuses to start this story until they are DONE
required_gates: []  # gate ids that are optional for the repo but binding for THIS story
---

## Context

Epic: `EPIC-06`. Two engineering questions stand between the preset design and
code, and both are recorded as unconfirmed:

- **CA-6** (`mechanics.md` §4.6): "Filtering developer-authored strings with
  `FilterStringAsync` per send, using the broadcast form of the result,
  satisfies C5", and "the sanctioned implementation for a preset wheel is
  reported to be `TextChatService` system messages (forum-reported, effective
  2026-01-09)".
- Brief §0d, "Implementation note for M3": engineering must confirm the
  system-message route against the API **before M3's channel story**.

The answers decide `CHAN-004`'s broadcast payload and filter port, and
`HUD-004`'s chat surface. This is a **spike**: its output is a recorded
decision in `docs/wiki/architecture.md` §9.5 and a note for the Game Designer on
CA-6's status. It may need a short Studio check by the operator.

**Which required gate would fail if this story's artifact broke:** none; the
artifact is a documented decision. The stories that implement it carry the
tests.

## Acceptance criteria

- **AC-1** — Given current Roblox creator documentation, when the spike reads
  it, then `architecture.md` §9.5 records, with links: the exact API call and
  arguments for filtering a developer-authored string sent on a user's behalf to
  all players (method, `fromUserId`, the `TextFilterContext` if any, and the
  result method for a broadcast); whether it yields; and its failure mode.
- **AC-2** — Given the same documentation, when the spike closes, then §9.5
  records whether a server can display a `TextChatService` system message to
  every client, or whether it must be displayed client-side (for example by
  `TextChannel:DisplaySystemMessage`) after a remote delivers the filtered text,
  and how the "system preset" label (C6) is attached. It also records whether a
  system message accepts the rich text `docs/wiki/design/components.md` C-13
  uses (a `face` attribute and `<b>`), and how a player name inside it is
  escaped.
- **AC-3** — Given AC-1 and AC-2, when the spike closes, then it states whether
  filtering must happen **per send** or may happen once per sender per session,
  quoting the guideline or API text that decides it; if neither decides it, it
  says so and `CHAN-004` keeps per send (the stricter reading, as the Lead PO
  took for CA-1).
- **AC-4** — Given the answers, when the spike closes, then `CHAN-004`
  and `HUD-004`'s `## Contract` blocks are updated to match, and a
  one-paragraph note of CA-6's status is handed to the Game Designer (owner of
  `mechanics.md` §4.6) in this story's `## Notes`.
- **AC-5** — If the documentation leaves AC-2 open, then the operator runs one
  Studio check — a system message displayed on every client with a
  "system preset" prefix — and its Output is pasted into `## Notes`.

## Contract

**Sources to read first:** Roblox creator docs for `TextService:FilterStringAsync`
and `TextFilterResult`; `TextChatService`, `TextChannel:DisplaySystemMessage`
and system messages; and the **Preset system guidelines** page the brief already
cites (`create.roblox.com/docs/chat/preset-system-guidelines`, source
`Roblox/creator-docs`, `content/en-us/chat/preset-system-guidelines.md`).
Forum posts are corroboration, not authority; record which is which.

**Oracle partition.** AC-1 to AC-3 are **settled by documentation**: quote it,
do not reason around it. AC-4 is mechanical. AC-5 is an observation.

## Out of scope

- Writing any source. A probe for AC-5 is throwaway and never committed.
- Pings. CA-1 ("is a ping a preset?") is closed as far as it can be (§0d #23).

## Model guidance

<!-- plan.sh:generated:begin -->
Planned by `bash scripts/plan.sh write CHAN-001` from `.claude/harness/models.conf`.
A PLAN, not a record: a session setting or an explicit override can beat both
this and the agent's own `model:` field, and nothing here can see which won.
The orchestrator still writes down the model each dispatch **resolved** to, by
name, below the table. Only what lies BETWEEN these two markers is rewritten when
this command runs again; the rest of the section is yours and is preserved.

| Phase | Agent | Planned | Why |
|---|---|---|---|
| PLANNED | `lead-po` | `opus` | planning is the judgement phase: decomposition, the oracle partition, and what goes in the contract |
| RED | `test-developer` | `opus` | the lock freezes none of the paths this story names, so the contract is not an aid to the model here - it is the only enforcement there is. A weaker model against a safety net and a weaker model against nothing are different propositions |
| GREEN | `feature-developer` | `opus` | the failure mode of a weaker model here is reaching green by weakening a test, which is the one thing this harness exists to prevent |
| GATES | `feature-developer` | `opus` | same risk as GREEN, and a gate failure is where "make it stop complaining" is most tempting |
| REVIEW | `lead-po` | `opus` | reading review feedback against the contract is judgement, and a wrong call here ships |
| SCAFFOLD | `lead-po` | `opus` | source, tests and config in one indivisible derivation, with no failing test in front of any of it |

Lock coverage: APPLIES — all 1 path(s) scanned from the Contract text are harness/docs/ignored, so RED stays on the stronger model.
<!-- plan.sh:generated:end -->

Run by the Lead PO; the Studio half, if needed, by the operator. No RED or
GREEN dispatch exists for a spike.

**Resolved:**

- PLANNED - `lead-po` - `claude-opus-5-5` (Opus 5.5, from the session's own model
  identification; the /plan-product dispatch reported no override). 2026-09-30.
- PLANNED → REVIEW (spike) - `lead-po` - `claude-opus-5-5` (this session's own model;
  no dispatch: a spike is run by the Lead PO). 2026-10-05.

## Test plan

<!-- Filled by the Test Developer during RED: which tests, at which level,
     and which AC each one covers. -->

## Handoff: RED -> GREEN

<!-- Filled by the Test Developer at the end of RED. This is the ONLY channel
     to the Feature Developer, whose context is fresh. Must contain:
       * the exact command that runs the new tests
       * the failure output, and why it is the RIGHT failure
       * every file touched, and which AC each test covers
       * the EXPORT SHAPE the tests already pin: every module they import, the
         exact exported names and signatures, and the types the assertions
         destructure. Not a suggestion - a test already imports them, so a
         wrong guess is a compile error. Say what the tests do NOT constrain
         too, so it stays the implementer's choice.
       * any test that passed on arrival, and the probe or negative control
         that earns it
       * the EXPECTED VALUE of every negative control, as a table: threshold,
         candidate range, and the number the control measured. In RED the
         suite fails at import, so no assertion in it has run - the controls
         are claims until GREEN confirms them against the shipped module
       * anything discovered that changes the approach -->

## Regressions

<!-- REQUIRED if this story ever returned to RED after GREEN or GATES; omit
     otherwise. A test that is wrong is never edited into passing, and the
     return is not a footnote - it is the story failing to be one clean cycle,
     and the next person needs to know why. One block per return:
       * which test, what it asserted, and what was wrong with it
       * how the defect was found
       * what it asserts now
       * what earns it, since "watched it fail" cannot apply once the
         implementation exists - the corrected assertion passes on its first
         run and every run after, whether or not it asserts anything: either a
         PROBE (mutate the specific behaviour the test pins, paste the red,
         confirm the revert) or, where the defect was cost rather than
         correctness, a BEFORE/AFTER measurement taken under the gate command -
         not the plain test command, which is the faster one.
         PASTE THE OUTPUT. check-boundaries.sh refuses a PR whose Regressions
         or Gate probes section describes a failure without showing one
       * whether GREEN was a no-op, and the command output proving the source
         was untouched and still passes -->

## Gate results

<!-- Written by scripts/gates.sh itself on every full run, stamped with the
     commit and a hash of the code it ran against. Do not paste or edit it:
     check-boundaries.sh refuses a PR whose recorded run does not match the
     code being merged. -->

## Gate probes

<!-- REQUIRED if this story adds or changes a gate, its command, or its
     evidence line. Omit the section entirely otherwise.
     A gate that has never been observed to fail is not a gate: break the thing
     it guards, run the gate, paste the failure, revert. One block per gate:
       * what was broken, and where
       * the gate output proving it failed
       * confirmation the probe was reverted -->

## Scaffold inventory

<!-- REQUIRED for a bootstrap or chore story that writes production code under
     SCAFFOLD, where nothing forces a test to exist first, and for a spike that
     commits its throwaway code. Omit otherwise.
     One line per production file written, and for anything with behaviour
     rather than configuration, the test that covers it:
       src/core/palette.ts        - src/core/palette.test.ts
       vite.config.ts             - configuration, no behaviour
     check-boundaries.sh refuses the PR if any changed source file is not
     named here. -->

## Notes


**Spike run (lead-po, 2026-10-05).** Sources read from `Roblox/creator-docs` at
`9f840b1` (raw files: `chat/preset-system-guidelines.md`,
`reference/engine/classes/TextService.yaml`, `TextFilterResult.yaml`,
`TextChannel.yaml`, `TextChatService.yaml`, `TextChatMessage.yaml`,
`enums/TextFilterContext.yaml`, `chat/in-experience-text-chat.md`,
`chat/chat-window.md`, `chat/guidelines.md`, `ui/text-filtering.md`,
`ui/rich-text.md`), plus two staff DevForum posts and one community thread. The
findings, with links and quotes, are `architecture.md` §9.5.1.

| AC | Result |
|---|---|
| AC-1 | `FilterStringAsync(word, sender.UserId, Enum.TextFilterContext.PublicChat)` → `GetNonChatStringForBroadcastAsync()`; both yield; either may throw; "If it fails, do not display the text to any user"; never retry. §9.5.1 |
| AC-2 | `DisplaySystemMessage` is client-only and per-viewer, and does not filter: the server broadcasts filtered text, each client writes the line. Label in the line, `metadata = "system_preset"`. Rich text is how the chat UI renders; `<b>` and `face` are supported tags; five escape forms, `&` first. §9.5.1 |
| AC-3 | **Per send**, quoted: "This method should be called once each time a user submits a message." §9.5.1 |
| AC-4 | `CHAN-004` and `HUD-004` `## Contract` amended (both still PLANNED, so no `## Amendments` entry is due there; their acceptance criteria are untouched). Game Designer note below |
| AC-5 | **Not triggered.** AC-5 runs "if the documentation leaves AC-2 open"; the reference settles both halves of AC-2 (client-only, per-viewer). The one thing the docs do not state outright — that a `DisplaySystemMessage` *body* renders rich text — affects C-13's markup, not the route, and is already observed by `HUD-004`'s SC-C1 (its D-1, owner REVIEW). No Studio check was run; no probe code exists |

**Note for the Game Designer — CA-6's status (`mechanics.md` §4.6).** CA-6's
filtering half is **confirmed**: `TextService:FilterStringAsync` with the sender's
`UserId`, the broadcast form `GetNonChatStringForBroadcastAsync`, called once per
send — the API reference says so in as many words, and the preset guideline
requires every preset to go through `FilterStringAsync`. CA-6's delivery half is
**confirmed in shape, but not as a mandate**: system messages are possible only
client-side (`DisplaySystemMessage` shows a line to one client), so each client
writes its own "system preset" line from the server's filtered broadcast; the
guideline requires the label only *when* presets display within chat, and the
"forum-reported, effective 2026-01-09" claim that system messages are *the*
sanctioned route was not found in any official source. §4.2's presentation
change (presets in chat, labelled) therefore stands as a design choice C-13
already makes, not as a compliance requirement. One new fact belongs in §4.6:
Roblox staff announced (2026-03-26) a Roblox-defined preset service, due June
2026, that "all creators will need to migrate" to, and advised against building
custom systems "unless it's necessary"; as of 2026-10-05 nothing has appeared in
the API reference. Suggest recording it as **CA-9** with the operator's decision
(PO-1 below). Owner of the edit: the Game Designer.

**PO decisions (lead-po, 2026-10-05).**

1. **PO-1 — the announced preset service: OPEN, for the operator.** Building
   `CHAN-004`/`HUD-004` now is a custom preset system of exactly the kind Roblox
   advised against building before its own service ships. The spike does not
   decide this; it records it (§9.5.1) and keeps the design migratable (preset
   table as data, filtering as a port, chat line as a client model). The
   operator chooses before `CHAN-004` leaves PLANNED: build now (the presets are
   "necessary for the experience to function" — the design's communication is
   presets plus pings, with no free chat), or hold the preset stories until the
   service's shape is known.
2. **PO-2 — filter after the phase check.** `CHAN-004`'s contract now says a
   preset refused for its phase never reaches the filter. Its AC-4 and AC-6
   already imply it (a refusal is decided before anything is shown); the
   contract makes it testable.
3. **PO-3 — `PublicChat` context.** Set for honesty about the audience; the
   reference says the context does not change the filtered result, so nothing
   tests it.
