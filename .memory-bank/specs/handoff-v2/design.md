---
spec_id: handoff-v2
topic: Handoff 2.0 — PreCompact actualize, mandatory done-gates, append-only integrity
status: ready
author: brainstorming-session
created: 2026-05-23
parent_roadmap: harness-upgrade (S3 of S1..S4)
addresses_gaps: [GAP-4, GAP-6, GAP-8]
non_addresses: [GAP-1, GAP-2, GAP-3, GAP-5, GAP-7, GAP-9, GAP-10]
depends_on_specs: []
breaking_changes: no in v4 (mandatory gates staged behind config until v5)
---

# Handoff 2.0 — Design

Sub-project **S3** of the harness upgrade. Strengthens the persistence layer that lets long-running agents survive context resets and session boundaries. Independent of S1/S2 — can ship in parallel.

Addresses: PreCompact auto-actualization (GAP-6), mandatory done-gates even without an active plan (GAP-4), and physical (not just process) append-only integrity for `progress.md` (GAP-8).

## 1. Goals & Non-goals

### Goals

- **G1 (GAP-6)** — On the `preCompact` event, automatically trigger `/mb update` (a lightweight actualize) that writes a fresh **handoff capsule** to `.memory-bank/handoff/latest.md`. SessionStart prefers this over `progress.md` when newer.
- **G2 (GAP-4)** — `/mb done` runs a mandatory gate set even when no active plan exists: `mb-test-runner` (deterministic) + `mb-rules-enforcer` (deterministic checks only) + placeholder scan. Failures require `--force` with an explanatory line appended to `progress.md`.
- **G3 (GAP-8)** — Physical integrity check on `progress.md` append-only invariant. Hash chain of last N entries lives in `.memory-bank/index.json:progress_chain`. `mb-drift.sh` verifies the chain on every drift run; deviation produces a CRITICAL drift report.

### Non-goals

- Calibrated reviewer (S1).
- Sprint contract / pivoting (S2).
- Multi-model role assignment (S4).
- Compaction archival policy changes (`mb-compact.sh` stays as-is).
- New SessionEnd autosave logic (existing `session-end-autosave.sh` keeps its placeholder behavior; we add reading from handoff but don't change writing).

## 2. Architecture overview

```
┌──────────────────────────────────┐         ┌────────────────────────────┐
│ Cursor / Claude Code "preCompact"│ ──────► │ hooks/mb-pre-compact.sh    │
│  hook event                      │         │ (REWRITTEN)                │
└──────────────────────────────────┘         └─────────────┬──────────────┘
                                                           │
                                                           ▼
                                              ┌─────────────────────────┐
                                              │ scripts/mb-handoff.sh   │
                                              │  --actualize            │
                                              │ writes handoff/latest.md│
                                              └────────────┬────────────┘
                                                           │
                                                           ▼
                                              ┌─────────────────────────┐
                                              │ .memory-bank/handoff/   │
                                              │   latest.md             │
                                              │   archive/<ts>.md       │
                                              └────────────┬────────────┘
                                                           │
                       (later, on next session)            │
                                                           ▼
┌──────────────────────────────────┐         ┌────────────────────────────┐
│ SessionStart                     │ ──────► │ hooks/mb-session-start-    │
│                                  │         │     context.sh (EXTENDED)  │
└──────────────────────────────────┘         │ prepends handoff/latest.md │
                                              │ if newer than progress.md │
                                              └────────────────────────────┘


/mb done — even without a plan:

  step 0: NEW gate set
    bash scripts/mb-done-gates.sh
       ├─ mb-test-runner (deterministic stack detection)
       ├─ mb-rules-enforcer (deterministic checks)
       └─ placeholder scan (mb-rules-check.sh --placeholders)
    FAIL → requires --force + explanatory line appended to progress.md
    PASS → existing /mb done flow

/mb drift / /mb doctor:

  NEW check: progress_chain integrity
    bash scripts/mb-progress-chain.sh --verify
       reads .memory-bank/index.json:progress_chain
       walks back N entries in progress.md
       recomputes hash chain
       CRITICAL drift on mismatch
```

## 3. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `scripts/mb-handoff.sh` | bash | Handoff capsule writer/reader: `--actualize`, `--read`, `--rotate` |
| `scripts/mb-done-gates.sh` | bash | Mandatory `/mb done` gate runner |
| `scripts/mb-progress-chain.sh` | bash | Hash chain compute + verify for `progress.md` |
| `templates/handoff.md` | markdown | Handoff capsule template skeleton |
| `tests/bats/test_mb_handoff_actualize.bats` | bats | Handoff write/read tests |
| `tests/bats/test_mb_done_gates.bats` | bats | Done-gates with and without plan |
| `tests/bats/test_mb_progress_chain.bats` | bats | Hash chain integrity tests |
| `tests/bats/test_mb_session_start_handoff.bats` | bats | SessionStart prepends handoff when fresh |
| `docs/handoff-2.0.md` | docs | User-facing guide |

### Project-owned (runtime)

- `.memory-bank/handoff/latest.md` — current capsule (overwritten each PreCompact)
- `.memory-bank/handoff/archive/<YYYY-MM-DDTHHMMSSZ>.md` — superseded capsules
- `.memory-bank/index.json:progress_chain` — JSON array of `{ entry_heading, sha256 }` for the last N entries

### Modified files

| Path | Change |
|------|--------|
| `hooks/mb-compact-reminder.sh` | Renamed/rewritten as `hooks/mb-pre-compact.sh`. Stops being read-only-reminder; now invokes `scripts/mb-handoff.sh --actualize` and writes a one-line marker to stderr so the user sees it. |
| `settings/hooks.json` | Registers `mb-pre-compact.sh` against the `preCompact` event; idempotent re-registration via `merge-hooks.py`. |
| `hooks/mb-session-start-context.sh` | After existing logic, checks `.memory-bank/handoff/latest.md` mtime vs the most recent `## YYYY-MM-DD` heading in `progress.md`. If handoff is newer, prepends a "Handoff capsule" section to the injected context (truncated to ~1500 chars). |
| `commands/done.md` | Step 0 runs `bash scripts/mb-done-gates.sh`. Failure exits with code 2 unless `--force` is passed; with `--force`, the script appends `### NOTE: /mb done --force — gates failed: <summary>` to `progress.md` before continuing. |
| `scripts/mb-drift.sh` | Adds `check_progress_chain` to the standard run; CRITICAL severity on mismatch. |
| `scripts/_lib.sh` (or wherever index.json is touched) | New helper `update_progress_chain` called from `mb-manager` after each `progress.md` append. |
| `agents/mb-manager.md` | Step that appends to `progress.md` is followed by a call to update the hash chain. The agent's prompt explicitly states the chain must stay in sync. |
| `CHANGELOG.md` | Enumerates: PreCompact behavior change, mandatory done-gates, progress hash chain. |

## 4. Handoff capsule — format and lifecycle

### Path and naming

- Current: `.memory-bank/handoff/latest.md`
- Archive: `.memory-bank/handoff/archive/<YYYY-MM-DDTHHMMSSZ>.md`

### Format

```markdown
---
capsule_version: 1
created: <ISO-8601 UTC>
trigger: pre_compact | manual_update
session_id: <if available>
active_plan: <relative path or null>
active_stage: <stage_no or null>
---

# Handoff capsule — <YYYY-MM-DD HH:MM UTC>

## Now (what is in progress right this minute)
- 1-3 bullets, concrete

## Done since last capsule
- 1-5 bullets

## Open blockers
- 1-3 bullets (or "None")

## Next concrete step
- ONE sentence

## Pointers (file paths the next session should read first)
- <path>
- <path>
```

Hard cap: 1500 chars including headers. The capsule is meant to be *injected verbatim*, not re-read into the LLM through a parsing step.

### Lifecycle

```
preCompact event fires
  ↓
hooks/mb-pre-compact.sh runs (≤2 seconds; hard timeout)
  ↓
scripts/mb-handoff.sh --actualize
  ├─ collects: active_plan from status.md mb-active-plans block
  ├─ collects: last 5 progress.md entries (heading + first 2 lines)
  ├─ collects: unchecked items from checklist.md (top 10)
  ├─ collects: open backlog HIGH items (top 3)
  ├─ writes latest.md (overwrite)
  └─ moves previous latest.md to archive/<ts>.md (if present)

Archive rotation:
  archive/ is pruned to N=10 newest files by mtime (mb-compact.sh integrates this)
```

### SessionStart consumption

`hooks/mb-session-start-context.sh` runs at SessionStart (existing behavior preserved). New addition:

```
if .memory-bank/handoff/latest.md exists AND
   mtime(latest.md) > timestamp_of_last_progress_entry:
     prepend the file body (truncated to 1500 chars) to the injected context
     log "[mb] using fresh handoff capsule" to stderr
```

Fallback: if no handoff or stale → existing behavior (status.md + checklist + roadmap).

## 5. Mandatory done-gates (GAP-4)

### Gate set

`scripts/mb-done-gates.sh` runs three independent checks in sequence. Each emits a structured JSON line to stdout.

1. **Tests**: dispatch `Task(mb-test-runner)` with scope=touched (if a baseline can be inferred from the most recent commit) else scope=full. Capture `tests_pass`.
2. **Rules (deterministic only)**: run `scripts/mb-rules-check.sh` (existing) on the working tree. Capture violation counts; CRITICAL = fail.
3. **Placeholders**: run `scripts/mb-rules-check.sh --placeholders-only` (new flag) — scans staged + uncommitted source for `TODO|FIXME|XXX|\.\.\.|pseudocode` markers. Any hit = fail (the deny list is configurable via `pipeline.yaml:done_placeholders.deny: [...]`).

### Configurability

`pipeline.yaml:done_gates`:

```yaml
done_gates:
  enabled: true              # NEW default
  required: [tests_pass, no_critical_violations, no_placeholders]
  allow_force: true          # if false, --force is rejected outright
```

If absent, the orchestrator falls back to `enabled: true` with the default required list.

### Force semantics

`/mb done --force --reason "<one-line>"`:
- Reason is mandatory when forcing; the script refuses without it.
- The reason is appended to `progress.md` as a `### NOTE: /mb done --force — gates failed: <gates>: <reason>` line under the current date heading (creating the heading if missing).
- The gate failures are stored in `.memory-bank/tmp/done-gate-failure-<ts>.json` for later audit.

## 6. Append-only physical integrity (GAP-8)

### Hash chain structure

`.memory-bank/index.json:progress_chain`:

```json
{
  "version": 1,
  "tail": [
    { "heading": "## 2026-05-23", "sha256": "..." },
    { "heading": "## 2026-05-22", "sha256": "..." },
    ...up to N=20 most recent date headings
  ],
  "last_synced_at": "<ISO-8601>"
}
```

`sha256` covers the contents from the heading line through the line before the next `## YYYY-MM-DD` heading (or EOF).

### Update flow

- After any append to `progress.md` (via `mb-manager` or scripts), `scripts/mb-progress-chain.sh --rebuild-tail` recomputes the last N entries and rewrites the array.
- The script is idempotent and safe to re-run.

### Verify flow

`scripts/mb-progress-chain.sh --verify`:
1. Read current chain from `index.json`.
2. For each entry in `tail`, locate the matching heading in `progress.md` and recompute the sha256 of its body.
3. If any mismatch → exit 2 with structured JSON report listing mismatched headings.
4. If a heading in `tail` is missing from `progress.md` → exit 2 (deletion detected).
5. Pass.

### Integration into drift

`scripts/mb-drift.sh` adds one new check:

```bash
check_progress_chain() {
    bash scripts/mb-progress-chain.sh --verify || {
        emit_critical "progress_chain_integrity" "$@"
    }
}
```

This makes `/mb doctor` and `/mb drift` surface tampering automatically.

### Why hash-chain over PreToolUse hook

A PreToolUse hook on Edit `progress.md` was considered. Rejected because:
- It blocks legitimate ad-hoc fixes (typos in current-date entry).
- It does not protect against direct file-system writes by other tools.
- The hash chain catches all tampering after-the-fact, not just by one specific tool.

The two could coexist later (defense-in-depth) but the chain is sufficient for S3.

## 7. Testing strategy

### Integration (≈70%)

- `test_mb_handoff_actualize.bats` — actualize writes latest.md with all 5 sections, archives previous, rotation prunes archive >N.
- `test_mb_done_gates.bats` — passing gates exit 0; failing gates without `--force` exit 2; with `--force --reason ...` exit 0 and `progress.md` gets a NOTE line; without `--reason`, force is rejected.
- `test_mb_progress_chain.bats` — rebuild produces deterministic shas; verify catches edit to old entry; verify catches deletion of entry from middle; multi-line entries handled.
- `test_mb_session_start_handoff.bats` — when latest.md is newer than last progress entry → prepended; when older → not prepended; truncation at 1500 chars.

### Unit (≈20%)

- Cover edge cases in `mb-progress-chain.sh`: empty progress.md, single-entry file, headings with unusual characters.

### E2E (≈10%, manual)

- Open a session, do trivial work, trigger PreCompact (or invoke `mb-handoff.sh --actualize` manually), verify the capsule is non-empty and well-formed. Start a fresh session; verify SessionStart context contains the capsule prefix.

### Static

- `shellcheck` on all new scripts.
- `mb-rules-check.sh` CLEAN.

## 8. Definition of Done (SMART)

- [ ] `scripts/mb-handoff.sh` exists with `--actualize`, `--read`, `--rotate`; `shellcheck` clean.
- [ ] `scripts/mb-done-gates.sh` exists; `shellcheck` clean; runs all 3 checks.
- [ ] `scripts/mb-progress-chain.sh` exists with `--rebuild-tail`, `--verify`; `shellcheck` clean.
- [ ] `templates/handoff.md` exists with §4 structure.
- [ ] `hooks/mb-pre-compact.sh` exists (or renamed from `mb-compact-reminder.sh`) and invokes `mb-handoff.sh --actualize`.
- [ ] `settings/hooks.json` registers `mb-pre-compact.sh` against `preCompact` event; idempotent.
- [ ] `hooks/mb-session-start-context.sh` prepends handoff capsule when fresh; truncation works.
- [ ] `commands/done.md` documents step 0 done-gates + `--force --reason` semantics.
- [ ] `scripts/mb-drift.sh` includes `check_progress_chain`.
- [ ] `agents/mb-manager.md` documents the chain-update obligation after every progress.md append.
- [ ] `references/pipeline.default.yaml` has `done_gates` block with the §5 defaults.
- [ ] All 4 bats files in §7 PASS.
- [ ] `docs/handoff-2.0.md` covers capsule format, done-gate semantics, hash chain.
- [ ] `CHANGELOG.md` enumerates the 3 changes.
- [ ] `/mb verify` clean — no regression in existing bats.

## 9. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| PreCompact hook exceeds time budget and blocks UI | Hard 2-second timeout inside `mb-pre-compact.sh`; on timeout, emit a one-line stderr WARN and exit 0 (never block compaction). |
| Handoff capsule grows past 1500 chars and harms SessionStart context budget | `mb-handoff.sh --actualize` hard-truncates each section to a per-section char limit; total assembly checks final size. |
| `mb-done-gates.sh` fails on stacks without a test framework configured | `mb-test-runner` already detects "no stack" and returns `not_applicable: true`; gate treats this as PASS for tests check (logged WARN). |
| Hash chain false positives on formatting-only edits (whitespace) | sha256 covers raw bytes; users editing past entries (even whitespace) trigger CRITICAL drift. This is INTENTIONAL — old entries are immutable. |
| Migration: existing `progress.md` has no chain yet | First run of `mb-progress-chain.sh --rebuild-tail` (called automatically by `mb-doctor` on upgrade or by `mb-manager` on next append) initialises the chain from the current state. No retroactive integrity claim. |
| Hash chain lives in `index.json` which is rebuilt by other scripts | The Python `mb-index-rebuild.py` (existing) MUST preserve `progress_chain`. New test in `test_mb_index_rebuild.py` confirms round-trip. |
| Conflict with parallel agents on `.memory-bank/handoff/` | Single-writer assumption: only `mb-pre-compact.sh` and `mb-manager` write. Lock file `.memory-bank/handoff/.lock` (fcntl) prevents concurrent writes from two PreCompact events. |

## 10. Out-of-scope follow-ups

- PreToolUse hook on `Edit progress.md` (defense in depth) — backlog.
- Cryptographic signing of progress entries — backlog.
- Multi-session handoff merge (when two agents work in parallel) — backlog.
- Handoff capsule semantic diff vs previous capsule (highlight what changed) — backlog.

## 11. Open questions to resolve during implementation

- N for `tail` length in `progress_chain` (defaulting to 20; revisit if `progress.md` files routinely exceed several hundred entries).
- Archive rotation threshold (N=10) — confirm via empirical look at `mb-compact.sh` defaults.
- Whether SessionStart should also embed the active plan stage diff if a plan was active — likely yes, but in handoff body, not as a separate section (avoid duplication).
