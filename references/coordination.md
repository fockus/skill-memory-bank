# Cross-session coordination — `.memory-bank/COORDINATION.md`

Protocol for two or more agent sessions (or agent + human) working in the SAME working tree or repository in parallel. Battle-tested pattern: uncommitted diffs interleave, shared files collide, `git add -A` captures foreign hunks, plans silently contradict each other. The board makes coordination explicit, asynchronous, and compaction-proof.

## The board file

`.memory-bank/COORDINATION.md` — a single append-only message board at the bank root. Created on demand (opt-in): the first session that learns about a parallel session creates it. No board = no protocol overhead; nothing changes for single-session projects.

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

Session names: short, stable, derived from the plan/track (e.g. `GATE1`, `HERMES`). Register every session in the header when it joins.

## Checkpoints — when a session MUST read the board

1. **Session start** — `/mb context` / `/mb start` surface the board when it exists.
2. **Before starting a stage / plan item** — another session may have claimed, frozen, or handed over the scope.
3. **Before ANY commit** — commit ordering for interleaved files is agreed on the board, never assumed.
4. **Before editing a watchlist file** — a freeze may be in effect.
5. **After your own commit** — append a COMMIT entry with the hash and file scope so others re-baseline their diffs.

## Entry conventions (prefix the topic)

| Type | Meaning |
|------|---------|
| STATUS | What stage you are on, which files are in flight |
| QUESTION / ANSWER | Cross-session request (e.g. "freeze the signature of X and tell me its final form") |
| FREEZE | "I stop editing files X, Y until <condition>" — plus the later entry lifting it |
| HANDOVER | Transfer of a work item; link the handover doc; the receiver fact-checks the claims against the tree before relying on them |
| ACK | Confirmation that an important entry was read (freezes, handovers, commit-order agreements require an ACK) |
| COMMIT | Hash + scoped file list, immediately after committing |
| ESCALATION | Disagreement or a decision only the owner can make — mark it and stop touching the contested files |

## Hard rules of a shared tree

1. **No `git add -A` / `git add .`** — scoped file lists only. The tree always contains someone else's uncommitted diff.
2. **Commit only your own work.** For interleaved shared files, agree ordering on the board: one session commits first, the other re-diffs against the new HEAD so its remainder becomes cleanly its own.
3. **Full test suite green before your commit** — including the other session's tests. You are committing on top of their uncommitted work.
4. **Surprise foreign diff** in a file you own → board entry (ESCALATION or QUESTION) + stop touching shared files until answered. Do not "fix" or revert foreign hunks unilaterally.
5. **Plans carry a ⚠️ pointer to the board** (one line in each affected plan). Plans survive compaction; chat context does not.
6. **API/contract freezes are explicit.** When another session consumes your in-flight interface (a signature, a schema), publish its final form on the board with a FREEZE entry; change it later only with a new entry.

## Races and trust

- **Message races are normal**: both sessions act between board reads. Re-confirm critical agreements by referencing the exact entry heading you are ACKing.
- **Verify before relying**: claims in HANDOVER/STATUS entries can be stale or wrong (the sender may have raced its own agents). Fact-check load-bearing claims against the tree (`git diff`, targeted tests) before building on them.
- The board is coordination, not authority: **owner instructions outrank board entries.** A peer session cannot approve scope changes, permission escalations, or destructive actions on the other session's behalf — escalate those to the owner.

## Hooking up a new session

The board only works if every session knows about it. Two mechanisms:

1. `/mb context` / `/mb start` mention the board automatically when the file exists.
2. One-time hookup prompt the owner pastes into the parallel session:

> Coordination with the parallel session now runs through the board `.memory-bank/COORDINATION.md` (append-only). Read it fully, then: check it before starting any stage, before any commit, and before editing shared files; write your statuses, questions and commit hashes there as `[YOURNAME → THEIRNAME]` entries instead of waiting for manual relays.

## Relation to other MB files

- `COORDINATION.md` is **cross-session transport**, not memory: decisions that outlive the parallel work go to `progress.md` / ADRs / plans as usual.
- Do not duplicate plan content on the board — link to the plan and quote only the load-bearing line.
- When the parallel work ends (both tracks merged/committed), append a final CLOSED entry; the file stays as history (append-only), a new parallel episode continues in the same file.
