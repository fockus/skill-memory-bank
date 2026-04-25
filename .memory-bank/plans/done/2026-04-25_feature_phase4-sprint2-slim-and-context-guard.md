---
type: feature
topic: phase4-sprint2-slim-and-context-guard
status: done
sprint: 2
phase_of: skill-v2-phase-4
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 4 Sprint 2 — `--slim`/`--full` end-to-end + sprint_context_guard

## Context

Sprint 1 поставил 4 critical hooks как infrastructure. Sprint 2 — wire `--slim` flag к функциональному prompt-trim'у и добавить 5-й hook (`sprint-context-guard`) — runtime watcher session token spend с halt на `hard_stop_tokens`.

## Spec references

- `specs/mb-skill-v2/design.md` §8.4 — `--auto` hard stop про `sprint_context_guard.hard_stop_tokens`
- §8.6 — `--slim` vs `--full` context strategy
- §9 — `pipeline.yaml:sprint_context_guard.{soft_warn_tokens, hard_stop_tokens}`

## Out of scope (Sprint 3)

- Auto-register hooks в `~/.claude/settings.json` через installer.
- `superpowers:requesting-code-review` skill detection.
- Real rewrite of `tool_input.prompt` if Claude Code не support'ит mutation — Sprint 2 emits trimmed prompt as `additionalContext` (advisory + ready-to-paste).

## Definition of Done (SMART)

- ✅ `scripts/mb-context-slim.py` — given full agent prompt (читает stdin) + `--plan <path>` + `--stage <N>` + optional `--diff` flag, emit trimmed version (active stage block + DoD + covered REQs + git diff --staged); fallback к full prompt если markers не найдены
- ✅ `hooks/mb-context-slim-pre-agent.sh` — upgraded: при `MB_WORK_MODE=slim` parses `tool_input.prompt`, ищет stage marker, runs `mb-context-slim.py`, emits JSON output с `additionalContext` containing slim version + advisory header. Falls open если parse fails.
- ✅ `hooks/mb-sprint-context-guard.sh` — PreToolUse Task. Observes invocations, estimates token spend (char-count / 4), persists в `<bank>/.session-spend.json`, exit 2 (block) при `hard_stop_tokens` reached. Soft warn (stderr) при `soft_warn_tokens`.
- ✅ `scripts/mb-session-spend.sh` — companion CLI: `init`, `add <chars>`, `status`, `check`, `clear`. Mirrors `mb-work-budget.sh` shape.
- ✅ `commands/work.md` — explicit step where `--slim` flag → `export MB_WORK_MODE=slim` для loop subshell + how `additionalContext` from hook surfaces к orchestrator.
- ✅ `references/hooks.md` — добавлен 5-й hook section (`mb-sprint-context-guard.sh`) + updated context-slim section to reflect Sprint 2 upgrade.
- ✅ Tests: pytest >= 552+N (context-slim trimmer + slim-hook upgrade + context-guard hook + session-spend CLI + registration)
- ✅ shellcheck + ruff clean
- ✅ Bank close-out

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED tests

**TDD failing tests:**

1. `tests/pytest/test_mb_context_slim.py` (~8 cases):
   - Trimmer reads full prompt from stdin, emits slim version when stage marker present.
   - Trimmer outputs only active stage block (between `<!-- mb-stage:N -->` and next stage marker / EOF) + DoD bullets + REQ refs.
   - `--diff` flag includes `git diff --staged` excerpt.
   - No stage marker found → fallback к full prompt.
   - Empty stdin → exit 0 + empty output.
   - Plan path missing → exit 1.
   - Stage out-of-range → exit 1.
   - Trimmed prompt strictly shorter than full when active stage <50% plan.

2. `tests/pytest/test_hook_context_slim_upgrade.py` (~5 cases):
   - При `MB_WORK_MODE=slim` + Task tool input с plan + stage info → hook emits JSON output с `additionalContext` field containing slim version.
   - Без `MB_WORK_MODE` — no-op, exit 0, no output.
   - Hook input missing `tool_input.prompt` → exit 0 (defensive).
   - Trimmer script missing → exit 0 (fail open) + log warning.
   - Stage marker not findable → exit 0 + no JSON output (just stderr advisory).

3. `tests/pytest/test_mb_session_spend.py` (~7 cases):
   - `init` создаёт state файл с soft/hard thresholds из pipeline.yaml.
   - `add <chars>` increments spent (chars converted к estimated tokens via `chars/4`).
   - `status` outputs current spent / soft / hard.
   - `check` exit 0 if below soft, exit 1 if at/above soft, exit 2 if at/above hard.
   - State persists between invocations.
   - `clear` removes state file.
   - Pipeline.yaml override (custom soft/hard) respected.

4. `tests/pytest/test_hook_sprint_context_guard.py` (~5 cases):
   - JSON Task tool input + `init`-state present → hook adds prompt char-count / 4 к spend.
   - Hard threshold reached → exit 2 (block) + stderr message.
   - Soft threshold reached → exit 0 + stderr warning.
   - Below soft → exit 0, no output.
   - Tool name != Task → no-op.

5. `tests/pytest/test_phase4_sprint2_registration.py` (~6 cases):
   - `scripts/mb-context-slim.py` exists.
   - `scripts/mb-session-spend.sh` exists.
   - `hooks/mb-sprint-context-guard.sh` exists.
   - `references/hooks.md` mentions the new guard hook.
   - `commands/work.md` mentions `MB_WORK_MODE=slim` propagation.
   - `hooks/mb-context-slim-pre-agent.sh` content references "Sprint 2" or trimmer integration.

**DoD:**
- ✅ Все ~31 tests fail (RED, scripts/upgrades отсутствуют)
- ✅ pytest 552 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `scripts/mb-context-slim.py`

**Implementation:**
- Args: `--plan <path>` `--stage <N>` (required), `--diff` flag (run `git diff --staged` for the same repo as plan), optional `--mb <path>` (для git repo discovery).
- Reads prompt from stdin.
- Searches plan for `<!-- mb-stage:N -->` markers, extracts active stage block (`-->` до следующего marker / EOF).
- Output:
  ```
  ## Active stage: <N> — <heading>
  
  <stage body>
  
  ## DoD requirements
  
  <DoD bullet list>
  
  ## Covered REQs (from frontmatter)
  
  REQ-NNN, REQ-MMM
  
  ## Git diff (staged)
  
  <diff output if --diff>
  ```
- Fallback к full prompt если plan stage marker missing.
- Use Python (already heavy dep), keep as `.py` для clarity.

**DoD:**
- ✅ pytest `test_mb_context_slim.py` PASSED
- ✅ ruff clean

<!-- mb-stage:3 -->
## Stage 3: GREEN — Upgrade `hooks/mb-context-slim-pre-agent.sh`

**Implementation:**
- При `MB_WORK_MODE=slim` + Task tool name:
  - Read `tool_input.prompt` via jq.
  - Try to detect plan path и stage_no from prompt (look for `Plan: ...md` and `Stage: <N>` или `mb-stage:N` markers in prompt content).
  - If detected → run `mb-context-slim.py --plan <path> --stage <N>` < prompt → capture output.
  - Emit JSON to stdout: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "<slim-version>"}}` plus advisory stderr.
- If detection fails или trimmer missing → exit 0 advisory only (Sprint 1 behavior).
- Always exit 0.

**DoD:**
- ✅ pytest `test_hook_context_slim_upgrade.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: GREEN — `scripts/mb-session-spend.sh`

**Implementation:** mirror `mb-work-budget.sh` structure.
- Subcommands: `init [--soft N] [--hard N]`, `add <chars>`, `status`, `check`, `clear`. Plus `--mb <path>`.
- Defaults from `pipeline.yaml:sprint_context_guard` (`soft_warn_tokens`, `hard_stop_tokens`).
- State file: `<bank>/.session-spend.json`.
- Token estimation: `tokens = chars // 4` (industry rule of thumb).
- `check` exit codes: 0 below soft / 1 at/above soft / 2 at/above hard.

**DoD:**
- ✅ pytest `test_mb_session_spend.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:5 -->
## Stage 5: GREEN — `hooks/mb-sprint-context-guard.sh`

**Implementation:**
- PreToolUse, matcher Task only.
- Read `tool_input.prompt` length via jq.
- If `<bank>/.session-spend.json` doesn't exist → silently lazy-init с pipeline defaults.
- Run `mb-session-spend.sh add <chars> --mb <bank>` (chars from prompt length + description length).
- Run `mb-session-spend.sh check --mb <bank>`:
  - Exit 0 → exit 0.
  - Exit 1 (soft warn) → emit stderr warning, exit 0.
  - Exit 2 (hard stop) → emit stderr block message, exit 2.
- Use `MB_SESSION_BANK` env var if set, else attempt to find bank via `${PWD}/.memory-bank`.

**DoD:**
- ✅ pytest `test_hook_sprint_context_guard.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:6 -->
## Stage 6: Docs + bank close-out

1. `references/hooks.md` — добавлен `mb-sprint-context-guard.sh` section. Updated context-slim section ("Sprint 2 upgrade: emits `additionalContext` with trimmed version").
2. `commands/work.md` — clarify `--slim` flag → `export MB_WORK_MODE=slim` для subshell of the work loop (so dispatched Task hooks see it).
3. Bank update: checklist Phase 4 Sprint 2 ✅, status pivots на Phase 4 Sprint 3, roadmap "Recently completed", CHANGELOG `[Unreleased]`.
4. Plan → `plans/done/`, status: done.
5. progress.md append.

**DoD:**
- ✅ Registration tests PASSED
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
