# Voice

The game says very little in words, and nothing the floor needs is *only* in
words (`accessibility.md` A-8). This page fixes the few words there are, so the
third story does not invent a fourth synonym.

## 1. Rules

1. **Words are redundancy, never the carrier.** Every word on the HUD sits next
   to a glyph that says the same thing.
2. **A 7-year-old's vocabulary.** Short, concrete, present tense. No game jargon
   on screen: never "supplier", "dependent", "actuator", "key class", "lens",
   "instability", "procedure", "par".
3. **Presets are the operator's words, verbatim** (T12). The client never
   capitalises, translates, abbreviates or punctuates them. No preset string
   ends in `.`, `!` or `?` (C6).
4. **No sentence on the HUD during a round.** Labels only. The one sentence in
   the game is the trace headline, after the round.
5. **Name steps, never players, in anything about the round's result** (T14).

## 2. The words

| Concept (internal) | Player-facing | Glyph | Notes |
|---|---|---|---|
| supplier, σ⁻¹(p) | **helper** ("Your helper") | `glyph.eye` | `roles.md` §2's suggestion, kept |
| dependent, σ(p) | **"You help"** as a label; "partner" in docs | `glyph.key` | "partner" is never shown on screen, because the docs also call the finale lamp a "partner lamp", and a child would reasonably think the two are related |
| actuator | machine | — | |
| key class | (none shown) | pattern | a child never needs the word |
| committed | done | `glyph.done` | |
| live | ready | `glyph.live` | "ready" only appears in the seat card's optional words; it is also a preset word, so it is avoided on the HUD |
| paired operation, finale | the big one | `glyph.finale` | no word on the HUD |
| par, canonical schedule | Best route | — | trace only |
| the other finale machine's helper and turner | the other pair | `glyph.pair` | trace headline only |
| instability | wrong turns | — | trace outcome only (C-24) |
| blackout | dark | `glyph.dark` | |
| spectate | "You'll join next round" | `glyph.eye` + `glyph.wait` | |
| rematch | Again | `glyph.again` | |

Seat card (C-05): "Your helper", "You", "You help", "Yours to turn", "You can see
these". Dial control (C-16): "Turn". Seat-change (C-22): "You can turn these too",
"No helper now. You can guess". Lobby (C-26): "Waiting for friends". Outcome
words: `components.md` C-24.

### 2.1 The phase label (`SLICE-004`, provisional)

`SLICE-004`'s skeleton shows the current phase as a word beside its countdown.
It implements no component (`components.md`), so until a HUD story replaces it
the word is the phase's own name, verbatim. This is an operator decision
(2026-10-08), not a vocabulary choice: rule 2 binds the components, and the HUD
stories that build them replace this label rather than reuse it.

| Phase (internal) | Player-facing |
|---|---|
| `Lobby` | Lobby |
| `Assignment` | Assignment |
| `Round` | Round |
| `Resolution` | Resolution |
| `Post` | Post |

The countdown beside it reads `m:ss` — minutes unpadded, seconds two digits
(`7:00`, `0:09`), the same text form as C-19.

## 3. The trace headline

The one sentence. `Trace.luau` produces it; the words are settled in
`mechanics.md` §7 (Game Designer, Q-G6, 2026-09-30), from the shape first
proposed here. Exactly one of:

    Step {n} waited {s} seconds for its helper.
    Step {n} waited {s} seconds for its turner.
    Step {n} waited {s} seconds for the other pair.     -- finale steps only
    Nobody waited long.

- `{n}` is the step's number in **par's canonical order** (`mechanics.md` §6.3,
  §7): T1[1] = 1, T2[1] = 2, T1[2] = 3, …, and the finale's two steps are 7
  (track 1) and 8 (track 2). The trace timeline (C-24) labels its blocks with the
  same numbers, so "Step 3" is the block marked 3.
- `{s}` is the wait **rounded down** to whole seconds. Numbers are fine here: the
  round is over and nothing is being relayed.
- **"Nobody waited long."** is used when no wait reaches
  `trace_headline_min_wait_seconds` (`tuning.md` §2, = `room_traversal_seconds`,
  8 today): a shorter wait is someone walking over, not someone being waited
  for. (This replaces the 5 s first proposed here.)
- Ends with a full stop. It is not a preset, so C6 does not apply; it is a
  sentence, and a child is taught that sentences end with one.
- At most 60 characters, so it fits two lines of `type.display` at `compact`
  (the longest possible is 45). PT on the model.
- No player name, no hue (T14). A no-contest round gets no headline.
- The client shows the string as `TraceView` carries it; it does not rebuild it.

## 4. Chat

If CA-6 holds, a preset in chat reads `system preset  {name}  {word}`
(`components.md` C-13). The label is lower case because it is a label, not a
sentence, and it matches the guideline's own spelling.
