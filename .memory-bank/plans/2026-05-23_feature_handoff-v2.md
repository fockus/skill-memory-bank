---
type: feature
topic: handoff-v2
status: queued
depends_on: ["2026-05-24_fix_ci-baseline-wave-0.md"]
parallel_safe: true
linked_specs: ["specs/handoff-v2/design.md"]
sprint: 1
phase_of: harness-upgrade
created: 2026-05-23
baseline_commit: bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
---

# Plan: feature — Handoff 2.0 (S3 of harness-upgrade)

**Baseline commit:** bf4fceea6065bdf84fac9f2a18c3b4c346d88dd1
**Linked spec:** [.memory-bank/specs/handoff-v2/design.md](../specs/handoff-v2/design.md)
**Sprint type:** single Sprint, 5 stages. Independent of S1/S2 — can ship in parallel.

## Context

**Problem.** Long-running sessions lose state at three weak points: (a) on PreCompact the existing hook is read-only (just warns about compaction candidates), so no fresh capsule is written before context shrinks; (b) `/mb done` is only gated when an active plan exists, allowing sessions to close with red tests or rule violations otherwise; (c) `progress.md` append-only discipline is enforced only by prompt — a stray Edit can silently rewrite history.

**Expected result.** PreCompact auto-actualizes a handoff capsule (`.memory-bank/handoff/latest.md`) that SessionStart prefers when fresh. `/mb done` runs deterministic gates (tests + rules + placeholders) regardless of plan presence, requires `--force --reason` to bypass. A hash chain in `index.json:progress_chain` lets `mb-drift.sh` detect tampering as CRITICAL.

**Related files:**
- Spec: `.memory-bank/specs/handoff-v2/design.md`
- Existing PreCompact hook: `hooks/mb-compact-reminder.sh` (to be rewritten)
- Existing SessionStart hook: `hooks/mb-session-start-context.sh` (to be extended)
- Existing done command: `commands/done.md`
- Existing drift: `scripts/mb-drift.sh`
- Existing manager: `agents/mb-manager.md`
- Existing index helper: `scripts/_lib.sh` + Python rebuild script

**Sprint boundaries.** Source files in scope: ~9. Bats tests new: ~14.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Handoff capsule script + template

**What to do:**
- Create `scripts/mb-handoff.sh` with subcommands: `--actualize`, `--read`, `--rotate`.
  - `--actualize`: collects active_plan, last 5 progress entries (heading + first 2 lines), top 10 unchecked checklist items, top 3 HIGH backlog items; assembles `latest.md` per spec §4 format; truncates to 1500 chars total; archives previous if present.
  - `--read`: prints `latest.md` to stdout if exists, else exit 1.
  - `--rotate`: prunes archive/ to N=10 newest files.
- Create `templates/handoff.md` matching spec §4 structure (this is reference only; `mb-handoff.sh` generates body).
- Implement single-writer lock via `flock` on `.memory-bank/handoff/.lock` (2-second timeout).

**Testing (TDD):**
- `tests/bats/test_mb_handoff_actualize.bats` ≥4 cases:
  - actualize writes latest.md with all 5 sections present;
  - actualize archives previous when one exists;
  - rotation prunes archive to N=10;
  - lock prevents concurrent actualize (simulated via background sleep);
  - total char count ≤ 1500.

**DoD (SMART):**
- [ ] `scripts/mb-handoff.sh` exists, executable, `shellcheck` clean.
- [ ] `templates/handoff.md` exists with §4 structure.
- [ ] Lock mechanism works (bats assertion).
- [ ] `test_mb_handoff_actualize.bats` PASS (≥5 cases).
- [ ] `mb-rules-check.sh` clean on new files.

**Code rules:** SRP — handoff writer ≠ rotation policy ≠ lock helper; if exceeded ~250 lines, split into a helper.

---

<!-- mb-stage:2 -->
### Stage 2: PreCompact hook rewrite + SessionStart capsule injection

**What to do:**
- Rename `hooks/mb-compact-reminder.sh` → `hooks/mb-pre-compact.sh`. Rewrite body: invokes `bash scripts/mb-handoff.sh --actualize` with hard 2-second timeout (`timeout 2 bash ...`). On timeout: emit a WARN to stderr, exit 0 (never block compaction).
- Update `settings/hooks.json`: register `mb-pre-compact.sh` against `preCompact` event with the `# [memory-bank-skill]` marker so `merge-hooks.py` strips/re-appends it idempotently.
- Extend `hooks/mb-session-start-context.sh`:
  - After existing context assembly, check `mtime(.memory-bank/handoff/latest.md)` vs timestamp of last `## YYYY-MM-DD` heading in `progress.md`.
  - If handoff is newer, prepend a `## Handoff capsule (fresh)` block — truncate to 1500 chars from handoff body.
  - Existing 2500-char hard cap on injected context preserved; handoff counts against the same budget.
- `install.sh`: when migrating old skill, detect `mb-compact-reminder.sh` and remove it (idempotent); add `mb-pre-compact.sh`.

**Testing (TDD):**
- `tests/bats/test_mb_pre_compact_hook.bats` ≥3 cases: hook completes <2s on a small bank; hook exits 0 on timeout simulation (using a stub that sleeps 5s); hook is idempotent (running twice produces consistent state).
- `tests/bats/test_mb_session_start_handoff.bats` ≥3 cases: fresh handoff is prepended; stale handoff is not prepended; truncation respects 1500 char cap.

**DoD (SMART):**
- [ ] `hooks/mb-pre-compact.sh` exists, replaces `mb-compact-reminder.sh`, `shellcheck` clean.
- [ ] `settings/hooks.json` registers the new hook idempotently (verified by running `merge-hooks.py` twice).
- [ ] `hooks/mb-session-start-context.sh` integration covers the freshness check.
- [ ] Both bats files PASS.
- [ ] `install.sh` migration logic verified by running on a fixture bank with old script present.

**Code rules:** KISS — hook body is a thin wrapper; complexity lives in `mb-handoff.sh`.

---

<!-- mb-stage:3 -->
### Stage 3: Mandatory done-gates + commands/done.md update

**What to do:**
- Create `scripts/mb-done-gates.sh` running spec §5 checks: dispatch `Task(mb-test-runner)`, run `mb-rules-check.sh`, run `mb-rules-check.sh --placeholders-only` (new flag — add to existing rules-check if not present).
- Add `--placeholders-only` flag to `mb-rules-check.sh` that runs ONLY the placeholder scan. Deny list configurable via `pipeline.yaml:done_placeholders.deny`.
- Update `commands/done.md`:
  - Add step 0: `bash scripts/mb-done-gates.sh` runs first.
  - On non-zero exit without `--force`: exit 2 with structured stderr.
  - On `--force --reason "<text>"`: append `### NOTE: /mb done --force — gates failed: <gate-list>: <reason>` to today's section in `progress.md`, store `.memory-bank/tmp/done-gate-failure-<ts>.json`, continue.
  - Reject `--force` without `--reason`.
- `references/pipeline.default.yaml`: add `done_gates: { enabled: true, required: [tests_pass, no_critical_violations, no_placeholders], allow_force: true }`.

**Testing (TDD):**
- `tests/bats/test_mb_done_gates.bats` ≥5 cases:
  - all gates pass → exit 0;
  - tests fail without `--force` → exit 2;
  - rules fail without `--force` → exit 2;
  - placeholder hit without `--force` → exit 2;
  - `--force --reason "text"` on failure → exit 0 with progress.md NOTE appended + tmp file written;
  - `--force` without `--reason` → exit 2.

**DoD (SMART):**
- [ ] `scripts/mb-done-gates.sh` exists, executable, `shellcheck` clean.
- [ ] `scripts/mb-rules-check.sh` has `--placeholders-only` flag.
- [ ] `commands/done.md` documents step 0 with `--force --reason` semantics.
- [ ] `references/pipeline.default.yaml` carries `done_gates` block.
- [ ] `test_mb_done_gates.bats` PASS (≥5 cases).

**Code rules:** Fail-fast (no silent passes); `--force` requires explicit user intent.

---

<!-- mb-stage:4 -->
### Stage 4: Progress hash chain + drift integration

**What to do:**
- Create `scripts/mb-progress-chain.sh` with subcommands:
  - `--rebuild-tail [N=20]`: walks `progress.md`, hashes each entry body (heading line through line before next heading or EOF), writes `index.json:progress_chain.tail`.
  - `--verify`: re-reads chain, recomputes, exits 0 on match, 2 on mismatch with structured JSON to stdout.
- Extend `scripts/mb-drift.sh`: add `check_progress_chain` to the standard run; CRITICAL severity on mismatch.
- Update `agents/mb-manager.md`:
  - Document that every progress.md append MUST be followed by `bash scripts/mb-progress-chain.sh --rebuild-tail`.
  - Add this to the `action: done` and `action: update` flows.
- Update Python `mb-index-rebuild.py` (existing) to preserve `progress_chain` key during rebuild (round-trip safe). New pytest covers this.

**Testing (TDD):**
- `tests/bats/test_mb_progress_chain.bats` ≥6 cases:
  - rebuild produces deterministic shas;
  - rebuild N=20 keeps only newest 20;
  - verify catches edit to an old entry;
  - verify catches deletion of an entry from middle;
  - verify catches a re-order;
  - first run on a chain-less index initialises from current state.
- `tests/pytest/test_index_rebuild_preserves_chain.py` ≥2 cases: rebuild round-trips `progress_chain` unchanged.

**DoD (SMART):**
- [ ] `scripts/mb-progress-chain.sh` exists, executable, `shellcheck` clean.
- [ ] `mb-drift.sh` includes `check_progress_chain`.
- [ ] `agents/mb-manager.md` documents the chain-update obligation (both `done` and `update` actions).
- [ ] `mb-index-rebuild.py` preserves `progress_chain`.
- [ ] Both bats + pytest files PASS.

**Code rules:** Defense-in-depth — chain catches tampering after the fact; complements (not replaces) prompt discipline.

---

<!-- mb-stage:5 -->
### Stage 5: Docs + CHANGELOG + integration verify

**What to do:**
- Author `docs/handoff-2.0.md` covering: handoff capsule format/lifecycle; SessionStart freshness rule; done-gate semantics and `--force --reason` flow; hash chain semantics and how to handle a CRITICAL drift.
- Update `CHANGELOG.md` `[Unreleased]`:
  - PreCompact behavior change (no longer read-only; auto-actualize on every preCompact event).
  - Mandatory `done-gates` even without active plan; `--force --reason` required to bypass.
  - `progress.md` append-only enforced by hash chain integrity check (CRITICAL drift on mismatch).
- Integration smoke: synthetic session — make a tiny edit, trigger PreCompact (or run `mb-handoff.sh --actualize` manually), confirm capsule written; start a fresh session and verify SessionStart context contains the capsule prefix.

**Testing (TDD):**
- `tests/bats/test_handoff_e2e.bats` ≥2 cases:
  - end-to-end: PreCompact → capsule written → SessionStart picks it up (stubbed mtime).
  - `/mb done` happy path with all gates green.

**DoD (SMART):**
- [ ] `docs/handoff-2.0.md` exists, ≥150 lines, all spec §10 risks addressed.
- [ ] `CHANGELOG.md` enumerates all 3 S3 changes.
- [ ] Integration bats file PASS.
- [ ] Existing bats suite has 0 regressions.
- [ ] `/mb verify` clean on branch.

**Code rules:** Documentation reflects implementation, not aspiration.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| PreCompact hook blocks UI if `mb-handoff.sh` runs slow | M | Hard 2-second timeout enforced in `mb-pre-compact.sh`; on timeout emit WARN and exit 0. |
| Capsule grows past 1500 chars and consumes SessionStart context budget | M | Per-section char limits inside `mb-handoff.sh --actualize`; final assembly checks size; truncate with ellipsis if exceeded. |
| Hash chain collisions with `mb-index-rebuild.py` | M | Dedicated pytest verifies round-trip preservation; rebuild script change is part of this stage. |
| Done-gates block on stacks without a test framework | M | `mb-test-runner` returns `not_applicable: true` for unsupported stacks; gate treats this as PASS with WARN log. |
| First-run after upgrade has no chain | L | `mb-progress-chain.sh --rebuild-tail` initialises from current state on first invocation; no retroactive integrity claim. |
| Hash mismatch false positives on whitespace edits | L | Intentional — old entries are immutable; documented in `docs/handoff-2.0.md`. |
| Conflict with parallel agents writing to `progress.md` | L | Single-writer assumption (mb-manager); lock on chain rebuild step. |

## Gate (plan success criterion)

`/mb work 2026-05-23_feature_handoff-v2 --max-cycles 3 --auto` completes all 5 stages with `plan-verifier` PASS, **and**:

1. All new bats + pytest files PASS with 0 failures.
2. Existing bats + pytest suites have 0 regressions.
3. `shellcheck` clean on all new scripts.
4. `mb-rules-check.sh` clean.
5. `docs/handoff-2.0.md` + `CHANGELOG.md` updated.
6. Manual smoke: PreCompact event (or manual actualize) writes a valid `latest.md`; subsequent SessionStart includes the capsule.
7. Manual smoke: `/mb done` on a tiny dirty change exits 2 without `--force`, exits 0 with `--force --reason "test"` and appends NOTE to progress.md.
8. Manual smoke: tamper with an old progress entry, run `/mb doctor` — CRITICAL drift surfaces.
