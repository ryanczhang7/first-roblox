# The backlog

**This backlog covers milestones M0, M1 and M2. It is not the whole product, and
the last story in it is not the last story of the game.**

`/plan-product` was run scoped to M0–M2 on 2026-09-15, deliberately. The reason,
recorded in `docs/wiki/product-brief.md` §0c and `docs/wiki/architecture.md` §0:

- **M0–M2 are genre-independent.** The toolchain, the gates, the
  `Lobby → Assignment → Round → Resolution → Post` phase machine and the trust
  boundary are identical under every genre candidate — demonstrated by their
  surviving the genre actually changing, in product-brief amendment 8, without a
  line of them moving.
- **M3 onward is not.** The vertical slice — the signal channel, the Procedure, the
  instance generator, the map, the UI — depends on open questions **T5 through T9**
  and on playtests that have not been run. `playtest.md: P-V` bears on amendment 8
  itself and should run before M3.

Planning M3 now would mean inventing answers to those questions. **Do not add M3
stories to this backlog until they are answered.** The open questions and their
owners are tabulated in product-brief §0c.

## Epics, in order

| Epic | Milestone | What it delivers |
|---|---|---|
| `EPIC-00` | M0 | The toolchain is installed, the gates are real, an empty place builds |
| `EPIC-01` | M1 | A round runs itself, start to finish, with no Roblox in the room |
| `EPIC-02` | M2 | The server is the only source of truth, and it says so out loud |

## Stories, in build order

    1.  BOOT-001    bootstrap: toolchain, gates, walking skeleton
    2.  ROUND-001   injected clock and seeded randomness, and the guard
    3.  ROUND-002   session and round-timing constants, checked against tuning.md
    4.  ROUND-003   the five-phase lifecycle on an injected clock
    5.  ROUND-004   lobby holds below players_min, caps at players_max
    6.  ROUND-005   three ways a round ends, with a deterministic reason
    7.  TEL-001     telemetry envelope, bucket mapping, injectable sink
    8.  NET-001     remote declaration, schema validation, the no-raw-remote guard
    9.  NET-002     phase legality
    10. NET-003     per-player rate limiting
    11. SEAT-001    the seeded single-cycle derangement
    12. SEAT-002    allowlist projection - nothing of anyone else's
    13. SEAT-003    disconnect, key transfer to the supplier, rejoin grace
    14. TEL-002     the B6 events a server round can observe
    15. TEL-003     rejection telemetry from the net wrapper

`depends_on` in each story's frontmatter enforces the order that matters;
`phase.sh set` refuses to start a story whose dependencies are not DONE.

`HARNESS-001` … `HARNESS-005` are harness-improvement stories inherited with the
template. They are independent of this backlog and can be taken at any time.

## Before starting

Run `/setup-environment`. Planning chose a toolchain; it did not install one, and
**nothing in `docs/wiki/stack.md` has ever been executed** — no part of the Roblox
toolchain is present on the machine that planned this. `BOOT-001`'s single most
valuable output is deleting that file's `# UNVERIFIED` banner honestly.
