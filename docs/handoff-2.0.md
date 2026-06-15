# Handoff 2.0 — capsules, done-gates, append-only integrity

Handoff 2.0 (spec `handoff-v2`) hardens the layer that lets a long-running agent
survive context compaction and session boundaries. It adds three independent
mechanisms:

1. **Handoff capsule** — a ≤1500-byte snapshot written before compaction and
   restored at the next session start.
2. **Mandatory `/mb done` gates** — tests + rules + placeholder scan, even when
   no plan is active, with an auditable `--force` override.
3. **Append-only physical integrity** — a sha256 hash chain over `progress.md`
   that turns silent tampering of historic entries into a CRITICAL drift.

Each mechanism is independent; you can rely on any one without the others.

---

## 1. Handoff capsule

### What it is

A small, self-contained Markdown file at `.memory-bank/handoff/latest.md` that
captures the *minimum a fresh session needs to resume*. It is injected verbatim
into the next session's context — it is never re-parsed back through the model.

```markdown
---
capsule_version: 1
created: 2026-06-15T09:00:00Z
trigger: pre_compact | manual_update
session_id: <id or null>
active_plan: <relative path or null>
active_stage: <stage_no or null>
---

# Handoff capsule — 2026-06-15 09:00 UTC

## Now (what is in progress right this minute)
- …

## Done since last capsule
- …

## Open blockers
- … (or "None")

## Next concrete step
- ONE sentence

## Pointers (file paths the next session should read first)
- status.md
- checklist.md
```

The five `## ` sections are **always present**, even when content is truncated:
the builder reserves the section skeleton first and byte-fits only the variable
bullet lists, so the hard 1500-byte cap can never drop "Next concrete step" or
"Pointers". Over-long bullets are clipped with `…`; the whole capsule is valid
UTF-8 (multibyte codepoints are never cut).

### How it is produced

`scripts/mb-handoff.sh` owns the lifecycle:

| Command | Effect |
| --- | --- |
| `mb-handoff.sh --actualize [bank] [trigger]` | Build `handoff/latest.md`; archive any previous capsule to `handoff/archive/<YYYY-MM-DDTHHMMSSZ>.md` first (colon-free, copy-then-atomic-rename so the old capsule is never lost on interrupt). |
| `mb-handoff.sh --read [bank]` | Print `latest.md` (exit 1 if absent). |
| `mb-handoff.sh --rotate [N] [bank]` | Prune `archive/` to the N newest by mtime (default 10). |

Content is collected from the active bank: `active_plan` (first link in the
roadmap `<!-- mb-active-plans -->` block), the last 5 `progress.md` entries, the
top unchecked checklist items (both `⬜` and `- [ ]` dialects), and the top
**open** HIGH backlog items (DONE/RESOLVED/DECLINED/DEFERRED items are excluded).

Writes are single-writer-safe via a portable `mkdir` lock with an owner token —
a release only removes a lock it still owns, so a stale writer cannot clobber a
fresh one.

### Lifecycle

```
preCompact event
   └─ hooks/mb-pre-compact.sh   (≤2s, NEVER blocks compaction)
         └─ mb-handoff.sh --actualize <bank> pre_compact
               └─ writes handoff/latest.md (archives the previous one)

next SessionStart
   └─ hooks/mb-session-start-context.sh
         └─ if latest.md is NEWER than the most recent progress.md date heading,
            PREPEND the capsule (truncated) ahead of the normal context
```

**The PreCompact hook never blocks compaction.** It bounds the actualize to a
~2-second budget (portable background-poll-and-kill — no `timeout`/`flock`), and
on timeout, failure, or an unresolved bank it emits a one-line stderr WARN and
exits 0. The whole actualize process tree is killed on timeout, so no orphan
keeps writing after the hook returns. Opt out entirely with
`MB_PRECOMPACT_HANDOFF=off`.

**SessionStart freshness.** The capsule is prepended only when its mtime is newer
than the *most recent* `## YYYY-MM-DD` heading in `progress.md` (the maximum date
across all headings, not the first). Otherwise the existing status/checklist/
roadmap context is used unchanged.

---

## 2. Mandatory `/mb done` gates

`scripts/mb-done-gates.sh` runs three independent checks, each emitting one JSON
line, and is wired in as step 0 of `/mb done` (see `commands/done.md`):

1. **tests** — dispatches the test runner. No stack / `not_applicable` → PASS
   with a logged WARN (never a silent fail).
2. **rules** — `scripts/mb-rules-check.sh` over the changed set (passed as both
   `--files` and `--diff-files`, so the CRITICAL TDD-delta check actually runs).
   Any CRITICAL violation = fail.
3. **placeholders** — `mb-rules-check.sh --placeholders-only` scans the changed
   source for the deny tokens (`TODO`, `FIXME`, `XXX`, `...`, `pseudocode`).
   Any hit = fail. `tests/` fixtures and lines tagged
   `# mb-rules-check: allow-placeholder` are exempt; markdown/yaml/json/vendor
   files are never scanned.

Exit 0 only if every **required** gate passes; otherwise exit 2.

### Configuration

`pipeline.yaml:done_gates` (defaults in `references/pipeline.default.yaml`):

```yaml
done_gates:
  enabled: true
  required: [tests_pass, no_critical_violations, no_placeholders]
  allow_force: true

done_placeholders:
  deny: [TODO, FIXME, XXX, '\.\.\.', pseudocode]
```

`required` is honoured: drop a gate from the list and a failure there no longer
fails `/mb done` (all three JSON lines are still emitted for the record). With no
project config the defaults above apply. `enabled: false` skips the gate set.

### Force semantics

```
/mb done --force --reason "<one line>"
```

- `--force` requires a non-empty, single-line `--reason` — a reason containing a
  newline or carriage return is rejected before any side effect (no audit-log
  injection).
- A forced run past failing gates appends
  `### NOTE: /mb done --force — gates failed: <gates>: <reason>` under today's
  date heading in `progress.md`, and stores the gate detail in
  `.memory-bank/tmp/done-gate-failure-<ts>.json`.
- `allow_force: false` rejects `--force` outright. If a project `pipeline.yaml`
  exists but cannot be parsed, force **fails closed** (rejected) rather than
  silently defaulting to allowed.

---

## 3. Append-only physical integrity (hash chain)

`scripts/mb-progress-chain.sh` maintains a sha256 chain of the last `N=20`
`## YYYY-MM-DD` entries in `index.json:progress_chain`:

```json
{
  "version": 1,
  "tail": [{ "heading": "## 2026-06-15", "sha256": "…" }, …],
  "last_synced_at": "2026-06-15T01:24:12Z"
}
```

| Command | Effect |
| --- | --- |
| `mb-progress-chain.sh --rebuild-tail [bank]` | Recompute the chain (idempotent; preserves every other `index.json` key; backs up a malformed index to `index.json.bak` rather than clobbering it). |
| `mb-progress-chain.sh --verify [bank]` | Exit 0 if the recorded tail is an intact contiguous suffix of the file; exit 2 with a structured report on any tamper. |

`mb-drift.sh` runs `--verify` as part of every drift/doctor pass and raises a
**CRITICAL** drift on a mismatch, a deleted entry, an *ambiguous* match, or a
**malformed** `index.json` (a corrupt chain no longer silently disables the
check).

### What counts as tamper — and what doesn't

The hash covers each entry from its heading through the line before the next date
heading, in a **canonical form**:

- line endings are normalised to `\n` (CRLF↔LF-only changes are *not* tamper);
- trailing blank *separator* lines between entries are excluded — this is what
  keeps an entry's hash stable when a new dated entry is legitimately appended
  after it.

Everything else is integrity-covered: any change to entry **content**, or to
whitespace **inside** the body, flips the hash and surfaces as CRITICAL drift.
Editing a past entry — even cosmetically inside the body — is treated as
tampering by design; historic entries are immutable.

### Limits

- Only the last **20** date entries are chained. Edits to older entries are out
  of scope (raise `N` if your `progress.md` routinely churns deeper history).
- The chain is initialised lazily: the first `--rebuild-tail` (run automatically
  by `mb-doctor` on upgrade, or by `mb-manager` after a `progress.md` append)
  seeds it from the current state — it makes no retroactive integrity claim about
  entries written before initialisation.
- The chain detects tampering **after the fact**; it is not a write-blocking
  guard. (A PreToolUse guard on `Edit progress.md` was considered and rejected —
  see design §6 — because the chain also catches direct filesystem writes by
  other tools.)

---

## Files

| Path | Role |
| --- | --- |
| `scripts/mb-handoff.sh` | Capsule writer/reader/rotator |
| `memory_bank_skill/handoff_capsule.py` | Capsule body builder (5 sections, byte-cap) |
| `templates/handoff.md` | Static capsule format reference |
| `hooks/mb-pre-compact.sh` | PreCompact actualize (never blocks) |
| `hooks/mb-session-start-context.sh` | SessionStart capsule consumption |
| `scripts/mb-done-gates.sh` | Mandatory `/mb done` gate runner |
| `scripts/mb-progress-chain.sh` + `memory_bank_skill/progress_chain.py` | Hash-chain compute + verify |
| `scripts/mb-drift.sh` | Chain verification wired into drift/doctor |

See `.memory-bank/specs/handoff-v2/design.md` for the full design and rationale.
