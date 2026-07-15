# Cross-session coordination

When two or more agent sessions (or an agent and a human) work in the **same** working tree or
repository at the same time, uncommitted diffs interleave, shared files collide, `git add -A`
captures a foreign hunk that isn't yours to commit, and plans silently start contradicting each
other. The coordination board makes this explicit, asynchronous, and compaction-proof instead of
relying on manual relays between sessions.

## The board file

`.memory-bank/COORDINATION.md` is a single append-only message board at the bank root. It is
created on demand — opt-in: the first session that learns about a parallel session creates it. No
board means no protocol overhead; nothing changes for single-session projects.

### File layout

```markdown
# Cross-session coordination board — <project>

**Protocol:** append-only. Entry heading: `## [FROM → TO] YYYY-MM-DD HH:MM — topic`.
Never edit or delete old entries (same invariant as progress.md).
**Sessions:** `NAME1` = <plan/track file> · `NAME2` = <plan/track file>
**Shared-files watchlist:** <files both sessions touch>

**Checkpoints (when to read the board):** session start · before starting any
stage/plan item · before ANY commit · before editing a watchlist file ·
after your own commit (write the hash here).

**Hard rules of a shared tree:** (see below — copy them into the header)

---

## [NAME1 → NAME2] 2026-07-12 23:50 — topic
<message>
```

Session names should be short and stable, derived from the plan or track they represent (for
example `GATE1`, `HERMES`). Every session that joins the coordination gets registered in the
header.

## Checkpoints — when a session MUST read the board

1. **Session start** — `/mb context` / `/mb start` surface the board automatically when it exists.
2. **Before starting a stage / plan item** — another session may have already claimed, frozen, or
   handed over that scope.
3. **Before ANY commit** — commit ordering for interleaved files is agreed on the board, never
   assumed from local context.
4. **Before editing a watchlist file** — a freeze may currently be in effect on it.
5. **After your own commit** — append a `COMMIT` entry with the hash and file scope so the other
   session(s) know to re-baseline their diffs against the new HEAD.

## Entry conventions

Every entry heading is prefixed with a type so a reader can scan the board quickly:

| Type | Meaning |
|------|---------|
| STATUS | What stage you are on, which files are in flight. |
| QUESTION / ANSWER | Cross-session request — e.g. "freeze the signature of X and tell me its final form." |
| FREEZE | "I stop editing files X, Y until `<condition>`" — plus the later entry that lifts it. |
| HANDOVER | Transfer of a work item; link the handover doc. The receiver fact-checks the claims against the tree before relying on them. |
| ACK | Confirmation that an important entry was read. Freezes, handovers, and commit-order agreements all require an ACK before the counterpart proceeds. |
| COMMIT | Hash + scoped file list, written immediately after committing. |
| ESCALATION | A disagreement, or a decision only the owner can make — mark it and stop touching the contested files until resolved. |

## Hard rules of a shared tree

1. **No `git add -A` / `git add .`** — scoped file lists only. The working tree almost always
   contains someone else's uncommitted diff; a blanket add will capture it.
2. **Commit only your own work.** For interleaved shared files, agree the ordering on the board:
   one session commits first, the other re-diffs against the new HEAD so its own remainder becomes
   cleanly attributable to it.
3. **Full test suite green before your commit** — including the other session's tests. You are
   committing on top of their still-uncommitted work, so a red suite could be either of you.
4. **A surprise foreign diff** in a file you own is a board entry (`ESCALATION` or `QUESTION`), not
   something to silently fix or revert. Stop touching shared files until it's answered.
5. **Plans carry a pointer to the board** — one line in each affected plan noting the board exists.
   Plans survive compaction; chat context does not.
6. **API/contract freezes are explicit.** When another session is about to consume your in-flight
   interface (a signature, a schema), publish its final form on the board with a `FREEZE` entry;
   change it later only through a new entry, never silently.

## Races and trust

Message races are normal: both sessions act between board reads, so a stale read is expected, not
a bug. Re-confirm critical agreements by referencing the exact entry heading you are ACKing rather
than paraphrasing it. Claims inside `HANDOVER`/`STATUS` entries can themselves be stale or wrong —
the sender may have raced its own subagents — so fact-check load-bearing claims (`git diff`,
targeted test runs) against the actual tree before building on them.

The board is a coordination mechanism, not an authority: **owner instructions always outrank board
entries.** A peer session cannot approve scope changes, permission escalations, or destructive
actions on another session's behalf; those escalate to the human owner.

## Hooking up a new session

The board only works if every session actually knows about it:

1. `/mb context` and `/mb start` mention the board automatically whenever the file exists.
2. For a session that hasn't seen it yet, paste this one-time hookup prompt:

   > Coordination with the parallel session now runs through the board
   > `.memory-bank/COORDINATION.md` (append-only). Read it fully, then: check it before starting
   > any stage, before any commit, and before editing shared files; write your statuses, questions
   > and commit hashes there as `[YOURNAME → THEIRNAME]` entries instead of waiting for manual
   > relays.

## Relation to other Memory Bank files

`COORDINATION.md` is **cross-session transport**, not long-term memory: decisions that outlive the
parallel work still go to `progress.md`, ADRs, or plans as usual — do not treat the board as a
substitute for those. Do not duplicate plan content on the board either; link to the plan and quote
only the one load-bearing line that matters for the coordination point being made. When the
parallel work ends (both tracks merged or committed), append a final `CLOSED` entry — the file
itself stays as history (it is append-only start to finish), and a later parallel episode simply
continues appending to the same file.

## Related

- [/mb work](mb-work.md) — the execution loop that checks the board for an active `FREEZE` before
  claiming an item's files, and halts as a hard stop under `--auto` when one is found.
- `references/coordination.md` — the source protocol document this page is migrated from.
