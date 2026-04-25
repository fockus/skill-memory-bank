---
type: feature
topic: phase3-sprint3-review-loop
status: done
sprint: 3
phase_of: skill-v2-phase-3
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 3 Sprint 3 — review-loop ядро

## Context

Sprint 2 закрыл MVP `/mb work`: target resolution + range parsing + execution-plan emission + role-agent dispatch для implement step. Sprint 3 — review-loop ядро: после implement → mb-reviewer → severity_gate → fix-cycle (cap at max_cycles) → plan-verifier → stage-done. Плюс hard stops для `--auto` (max_cycles, verifier fail, protected paths, budget, sprint_context_guard).

Архитектура та же: deterministic helper scripts + workflow в `commands/work.md`.

## Spec references

- `specs/mb-skill-v2/design.md` §8.4 — `--auto` hard stops
- §8.5 — Review loop (5 шагов)
- §9 — `pipeline.yaml` severity_gate / max_cycles / on_max_cycles / protected_paths / sprint_context_guard / budget
- §11 — Verifier 7 checks (existing plan-verifier.md уже covers большинство)

## Out of scope (Phase 4)

- `--slim` / `--full` context strategy — требует hook'ов (`context-slim-pre-agent.sh`)
- Real `--allow-protected` enforcement в Write/Edit — требует `pre-agent-protected-paths.sh` hook
- `superpowers:requesting-code-review` skill auto-detection — Phase 4 Sprint 3 (installer wiring)

Sprint 3 делает helper scripts, которые Phase 4 hooks будут consume. `protected-check.sh` уже работает, но как deterministic check внутри workflow, а не runtime hook.

## Definition of Done (SMART)

- ✅ `scripts/mb-work-review-parse.sh <stdin>` — парсит structured reviewer output (verdict + counts + issues), валидирует shape, печатает normalized JSON + exit codes
- ✅ `scripts/mb-work-severity-gate.sh --counts <json> [--mb <path>]` — читает severity_gate из effective pipeline.yaml + counts из stdin/flag → exit 0 (PASS) или 1 (FAIL) + список нарушений
- ✅ `scripts/mb-work-budget.sh <subcommand>` — `init <budget>` (start tracking), `add <tokens>` (increment), `status` (current spent + thresholds), `check` (exit 0 OK / 1 warn / 2 stop). State в `<bank>/.work-budget.json` per session.
- ✅ `scripts/mb-work-protected-check.sh <files...> [--mb <path>]` — match changed files against `pipeline.yaml:protected_paths` globs → exit 0 (none) / 1 (matched, list to stderr)
- ✅ `agents/mb-reviewer.md` — production-grade prompt (Sprint 2 был scaffold): explicit rubric walk, severity guidance, JSON output schema, fix-cycle behavior
- ✅ `commands/work.md` — wire полный review-loop workflow: implement → review-parse → severity-gate → fix (if CHANGES_REQUESTED + cycle < max) → verify → stage-done; hard stops для --auto
- ✅ Tests: pytest >= 474+N (review-parse + severity-gate + budget + protected-check + reviewer scaffold update)
- ✅ shellcheck + ruff clean
- ✅ Bank artifacts обновлены (checklist Phase 3 Sprint 3 ✅, status pivots на Phase 4 Sprint 1, roadmap "Recently completed", CHANGELOG `[Unreleased]` Added)
- ✅ Plan → `plans/done/`, status: done

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED tests

**TDD failing tests:**

1. `tests/pytest/test_mb_work_review_parse.py` (~10 cases):
   - Valid JSON `{verdict, counts, issues}` → exit 0 + normalized output.
   - `verdict: APPROVED` + non-empty issues → still valid (warnings allowed).
   - `verdict: CHANGES_REQUESTED` + zero issues → exit 1 (inconsistent).
   - Missing `verdict` field → exit 1.
   - Invalid verdict value → exit 1.
   - Counts with negative numbers → exit 1.
   - Issue missing required fields (severity / file) → exit 1.
   - Severity not in {blocker, major, minor} → exit 1.
   - Empty stdin → exit 2 (usage).
   - Malformed JSON → exit 1 + parse error.
   - Plain-text fallback: `verdict: APPROVED` + `counts: {blocker: 0, major: 0, minor: 0}` lines parsed (когда reviewer возвращает Markdown a-la code block) → exit 0.

2. `tests/pytest/test_mb_work_severity_gate.py` (~8 cases):
   - Counts `{blocker: 0, major: 0, minor: 2}` + default gate `{blocker: 0, major: 0, minor: 3}` → exit 0 (PASS).
   - Counts `{blocker: 1, ...}` + gate blocker=0 → exit 1 (blocker breach).
   - Counts `{major: 1, ...}` + gate major=0 → exit 1.
   - Counts `{minor: 5}` + gate minor=3 → exit 1.
   - Custom gate via project `pipeline.yaml` (init + edit) → respects override.
   - Counts JSON via `--counts-stdin` → reads stdin.
   - Missing severity field in counts → treated as 0.
   - Invalid counts JSON → exit 2.

3. `tests/pytest/test_mb_work_budget.py` (~7 cases):
   - `init 100000` → создаёт state файл с budget.
   - `add 25000` → spent=25000, status returns 25%.
   - `status` без init → exit 1 "no active budget".
   - `check` при spent < warn_at_percent → exit 0.
   - `check` при spent >= warn_at_percent (80%) → exit 1 (warn).
   - `check` при spent >= stop_at_percent (100%) → exit 2 (stop).
   - State persists between invocations (file based).

4. `tests/pytest/test_mb_work_protected_check.py` (~6 cases):
   - File matching `.env*` glob → exit 1.
   - File matching `ci/**` → exit 1.
   - File matching `terraform/**` → exit 1.
   - File NOT matching any glob → exit 0.
   - Multiple files, one matches → exit 1 + list of matches in stderr.
   - Empty file list → exit 0.

5. `tests/pytest/test_phase3_sprint3_registration.py` (~5 cases):
   - `agents/mb-reviewer.md` содержит JSON schema example.
   - `agents/mb-reviewer.md` содержит severity guidance + fix-cycle instructions.
   - `commands/work.md` upgraded — содержит "review-parse" / "severity-gate" / "fix-cycle" / "verify step" / "hard stops" mentions.
   - 4 helper scripts существуют (review-parse / severity-gate / budget / protected-check).

**DoD:**
- ✅ Все ~36 tests fail (RED, scripts/agent updates отсутствуют)
- ✅ pytest 474 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `scripts/mb-work-review-parse.sh`

**Implementation:**
- Args: `[--lenient]` (опциональный — accept Markdown fallback).
- Reads JSON from stdin, validates shape: `verdict ∈ {APPROVED, CHANGES_REQUESTED}`, `counts: {blocker, major, minor}` all int >= 0, `issues: [{severity, category, file, line, message, fix?}]`, severity ∈ {blocker, major, minor}.
- Cross-check: `verdict == CHANGES_REQUESTED` requires len(issues) > 0; `verdict == APPROVED` may have 0+ issues.
- If JSON parse fails и `--lenient` — try Markdown fallback (regex для verdict + counts).
- Output: normalized JSON to stdout.
- Exit codes: 0 valid / 1 schema error / 2 usage.

**DoD:**
- ✅ pytest `test_mb_work_review_parse.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:3 -->
## Stage 3: GREEN — `scripts/mb-work-severity-gate.sh`

**Implementation:**
- Args: `--counts <json> | --counts-stdin` + `[--mb <path>]` + `[--gate <json>]` (override).
- Read effective `pipeline.yaml` via `mb-pipeline.sh path`. Locate `stage_pipeline[step=review].severity_gate`.
- For each severity {blocker, major, minor}: counts[s] > gate[s] → breach. Missing in counts → treat as 0.
- Output: `[severity-gate] PASS` or `[severity-gate] FAIL: <severity>=<count> > gate=<limit>` lines.
- Exit codes: 0 PASS / 1 FAIL / 2 usage.

**DoD:**
- ✅ pytest `test_mb_work_severity_gate.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: GREEN — `scripts/mb-work-budget.sh`

**Implementation:**
- Subcommands: `init <total_tokens> [--mb <path>]`, `add <tokens> [--mb <path>]`, `status [--mb <path>]`, `check [--mb <path>]`, `clear [--mb <path>]`.
- State file: `<bank>/.work-budget.json` — `{total: int, spent: int, warn_at_percent: int, stop_at_percent: int, started: ISO8601}`.
- `init` reads `pipeline.yaml:budget.warn_at_percent` and `stop_at_percent` defaults (80/100), accepts `--warn-at` / `--stop-at` overrides.
- `add` increments `spent`.
- `status` prints JSON or human-readable progress.
- `check` exit codes: 0 < warn / 1 warn (>= warn_at_percent) / 2 stop (>= stop_at_percent).
- `clear` deletes state file.

**DoD:**
- ✅ pytest `test_mb_work_budget.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:5 -->
## Stage 5: GREEN — `scripts/mb-work-protected-check.sh`

**Implementation:**
- Args: `<file...>` positional + `[--mb <path>]`.
- Read `pipeline.yaml:protected_paths` (list of globs).
- Match each input file path against globs (Python `fnmatch.fnmatch` + `**` handling via `pathlib.PurePath.match` или translate-to-regex для `**`).
- Exit 0 если none match, exit 1 если any match (list matches to stderr `[protected] <file> matches <glob>`).

**DoD:**
- ✅ pytest `test_mb_work_protected_check.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:6 -->
## Stage 6: Production-grade `agents/mb-reviewer.md`

Replace Sprint 2 scaffold с full review prompt:

- Inputs schema (plan path / stage / git diff / pipeline.yaml / linked spec).
- Per-category review walk (logic / code_rules / security / scalability / tests) с примерами.
- Severity decision tree (blocker / major / minor) с edge cases.
- Output JSON schema:
  ```json
  {
    "verdict": "APPROVED|CHANGES_REQUESTED",
    "counts": {"blocker": N, "major": N, "minor": N},
    "issues": [{"severity": "...", "category": "...", "file": "...", "line": N, "message": "...", "fix": "..."}]
  }
  ```
- Fix-cycle behavior на следующей итерации (читай предыдущий issue list, проверь что fix применён).
- "What you do NOT do" guardrails (no edits, no in-spirit approvals).

**DoD:**
- ✅ `tests/pytest/test_phase3_sprint3_registration.py` reviewer-content checks PASSED

<!-- mb-stage:7 -->
## Stage 7: `commands/work.md` — wire review-loop

Update Sprint 2's workflow section:

```
Per stage:
  1. Implement step — Task dispatch (existing Sprint 2 logic)
  2. Review step — Task dispatch к mb-reviewer; capture stdout
  3. Parse via mb-work-review-parse.sh
  4. Severity gate via mb-work-severity-gate.sh
  5. If FAIL и cycle < max_cycles:
     - Fix step: Task dispatch к implement role с issue list → goto 2
  6. If FAIL и cycle == max_cycles:
     - on_max_cycles: stop_for_human → halt + summary
     - on_max_cycles: continue_with_warning → proceed with warning logged
  7. Verify step — Task dispatch к plan-verifier
  8. If verifier PASS → stage-done; mark DoD; next stage
  9. If verifier FAIL → halt for human

Hard stops для --auto:
  - max_cycles reached без APPROVED → halt
  - verifier fail → halt
  - Write/Edit attempt в protected path без --allow-protected → halt
  - --budget exhausted (mb-work-budget.sh check exit 2) → halt
  - sprint_context_guard.hard_stop_tokens reached → halt
```

Add table of all flags actually wired in Sprint 3.

**DoD:**
- ✅ `commands/work.md` содержит все указанные секции
- ✅ registration tests PASSED

<!-- mb-stage:8 -->
## Stage 8: Bank close-out

1. Bank update: checklist (Phase 3 Sprint 3 ✅), status (pivot на Phase 4 Sprint 1), roadmap (Recently completed), CHANGELOG `[Unreleased]` Added.
2. Plan → `plans/done/`, status: done.
3. progress.md append.

**DoD:**
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
