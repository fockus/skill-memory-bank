---
type: feature
topic: phase4-sprint1-critical-hooks
status: done
sprint: 1
phase_of: skill-v2-phase-4
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 4 Sprint 1 — 4 critical hooks

## Context

Phase 3 закрыл execution engine + review-loop. Phase 4 Sprint 1 — runtime hooks: deterministic intercept-points which Claude Code dispatches before/after tool calls. Spec §13 определяет 4 critical hooks. Sprint 1 ships scripts + tests + docs; installer-level wiring → Phase 4 Sprint 3.

## Spec references

- `specs/mb-skill-v2/design.md` §13 — 4 hooks table
- §8.6 — `--slim` context strategy (consumed by hook #4 в Sprint 2)
- §9 — `pipeline.yaml:protected_paths` (read by hook #1)

## Out of scope (Phase 4 Sprint 2/3)

- Wiring `--slim`/`--full` flag → `MB_WORK_MODE` env propagation through `/mb work` (Sprint 2).
- `sprint_context_guard` runtime token watcher (Sprint 2).
- Auto-registration of hooks in Claude Code settings.json (Sprint 3 installer).
- `superpowers:requesting-code-review` skill detection (Sprint 3).

Sprint 1 ships the hook scripts as standalone, deterministic, tested infrastructure. They can be manually registered in `~/.claude/settings.json` per the docs we ship; Sprint 3 will automate registration via `install.sh`.

## Definition of Done (SMART)

- ✅ `hooks/mb-protected-paths-guard.sh` — PreToolUse Write/Edit. Reads JSON from stdin, extracts `tool_input.file_path`, runs `mb-work-protected-check.sh` against it. Exit 2 (block) если match и `MB_ALLOW_PROTECTED` != 1. Exit 0 otherwise.
- ✅ `hooks/mb-plan-sync-post-write.sh` — PostToolUse Write. If file_path matches `plans/**.md` или `specs/**.md` → run chain `mb-plan-sync.sh` → `mb-roadmap-sync.sh` → `mb-traceability-gen.sh`. Each step best-effort (warn on failure, don't block). Skip steps which scripts don't exist.
- ✅ `hooks/mb-ears-pre-write.sh` — PreToolUse Write. If file_path matches `specs/*/requirements.md` или `context/*.md` → extract `tool_input.content`, pipe через `mb-ears-validate.sh`. Exit 2 if validation fails (with stderr listing violations). Exit 0 otherwise.
- ✅ `hooks/mb-context-slim-pre-agent.sh` — PreToolUse Task. If `MB_WORK_MODE=slim` → emit advisory JSON output suggesting reduced context (Sprint 1 stops at advisory; Sprint 2 wires actual prompt rewrite). Otherwise no-op.
- ✅ `references/hooks.md` — installation guide: `~/.claude/settings.json` snippets для каждого hook'а с matchers + commands.
- ✅ Tests: pytest >= 517+N (per-hook unit tests + registration)
- ✅ shellcheck clean
- ✅ Bank artifacts обновлены (checklist Phase 4 Sprint 1 ✅, status pivots на Sprint 2, roadmap "Recently completed", CHANGELOG `[Unreleased]` Added)
- ✅ Plan → `plans/done/`, status: done

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED tests

**TDD failing tests:**

1. `tests/pytest/test_hook_protected_paths.py` (~6 cases):
   - JSON with `tool_input.file_path: "src/foo.py"` → exit 0 (no match).
   - JSON with `tool_input.file_path: ".env.production"` → exit 2.
   - JSON with `tool_input.file_path: "ci/build.yaml"` → exit 2.
   - `MB_ALLOW_PROTECTED=1` env + protected file → exit 0.
   - JSON without `tool_input.file_path` → exit 0 (other tool, ignored).
   - Tool name not Write/Edit → exit 0 (event filter).

2. `tests/pytest/test_hook_plan_sync_post_write.py` (~5 cases):
   - JSON with file_path под `plans/foo.md` → triggers (exit 0 + stdout shows chain).
   - JSON with file_path под `specs/bar/requirements.md` → triggers.
   - JSON with file_path вне plans/specs → no-op (exit 0, no chain).
   - Tool name != Write → no-op.
   - Missing chain script (`mb-status-refresh.sh` doesn't exist) → still exit 0 with warning.

3. `tests/pytest/test_hook_ears_pre_write.py` (~6 cases):
   - JSON with content valid EARS in `specs/foo/requirements.md` → exit 0.
   - JSON with content invalid EARS in `specs/foo/requirements.md` → exit 2.
   - JSON with content valid EARS in `context/foo.md` → exit 0.
   - JSON with content valid EARS in `src/foo.py` → exit 0 (no path match, no validation).
   - Tool name != Write → exit 0.
   - Missing `tool_input.content` → exit 0 (defensive).

4. `tests/pytest/test_hook_context_slim.py` (~4 cases):
   - `MB_WORK_MODE=slim` + Task tool input → stdout contains advisory or empty + exit 0.
   - `MB_WORK_MODE=full` → no-op (exit 0, no stdout).
   - `MB_WORK_MODE` unset → no-op.
   - Tool name != Task → no-op.

5. `tests/pytest/test_phase4_sprint1_registration.py` (~5 cases):
   - Each of 4 hooks exists в `hooks/`.
   - `references/hooks.md` exists и mentions всех 4 hooks.
   - `references/hooks.md` содержит settings.json examples (matchers + commands).

**DoD:**
- ✅ Все ~26 tests fail (RED, scripts отсутствуют)
- ✅ pytest 517 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `hooks/mb-protected-paths-guard.sh`

**Implementation:**
- Read JSON via `jq` from stdin.
- Extract `tool_name` (must be `Write` or `Edit`, else exit 0).
- Extract `tool_input.file_path` (else exit 0).
- If `MB_ALLOW_PROTECTED=1` → exit 0 with advisory.
- Run `bash scripts/mb-work-protected-check.sh "$file_path"`.
- If exit 1 (matched) → emit clear stderr message + exit 2 (hard block).
- Else exit 0.

**DoD:**
- ✅ pytest `test_hook_protected_paths.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:3 -->
## Stage 3: GREEN — `hooks/mb-plan-sync-post-write.sh`

**Implementation:**
- Read JSON via `jq`.
- Extract `tool_name` (Write only).
- Extract `tool_input.file_path` — must match `plans/**.md` или `specs/**.md` glob (using bash case ... esac).
- Best-effort chain: for each script (`mb-plan-sync.sh`, `mb-roadmap-sync.sh`, `mb-traceability-gen.sh`):
  - If script exists → run it; on non-zero, log warning on stderr.
  - If absent → skip silently (script may not be installed).
- Always exit 0 (PostToolUse hook should not block).

**DoD:**
- ✅ pytest `test_hook_plan_sync_post_write.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: GREEN — `hooks/mb-ears-pre-write.sh`

**Implementation:**
- Read JSON via `jq`.
- Extract `tool_name` (Write only).
- Extract `tool_input.file_path`.
- Match path against `specs/*/requirements.md` или `context/*.md` (path or basename match).
- Extract `tool_input.content`.
- If content empty → exit 0.
- Pipe content into `bash scripts/mb-ears-validate.sh -` (read from stdin).
- If exit non-zero → emit stderr `[ears-pre-write] EARS validation failed:` + the validator's stderr; exit 2.
- Else exit 0.

**DoD:**
- ✅ pytest `test_hook_ears_pre_write.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:5 -->
## Stage 5: GREEN — `hooks/mb-context-slim-pre-agent.sh`

**Implementation:**
- Read JSON via `jq`.
- Extract `tool_name` (must be `Task`, else exit 0).
- If `MB_WORK_MODE` != `slim` → exit 0 (no-op).
- Emit advisory stderr: `[context-slim] MB_WORK_MODE=slim detected; Sprint 1 ships advisory only — Sprint 2 wires actual prompt trim.`
- Exit 0 (advisory only, no block).

**DoD:**
- ✅ pytest `test_hook_context_slim.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:6 -->
## Stage 6: `references/hooks.md` + bank close-out

1. `references/hooks.md` — installation guide:
   - One section per hook (4 sections).
   - For each: purpose, event type (PreToolUse / PostToolUse), matcher (tool name + path glob), command (script path + jq pipeline), `~/.claude/settings.json` snippet.
   - Note: Sprint 3 installer will auto-register; Sprint 1 = manual.
2. Update bank:
   - `checklist.md` — Phase 4 Sprint 1 ✅
   - `status.md` — pivot на Phase 4 Sprint 2 (`--slim`/`--full` end-to-end)
   - `roadmap.md` — Recently completed entry
   - `CHANGELOG.md` `[Unreleased]` Added entry
3. Plan → `plans/done/`, status: done.
4. progress.md append.

**Registration tests:**
- All 4 hooks present.
- `references/hooks.md` mentions each hook + has settings.json snippets.

**DoD:**
- ✅ Registration tests PASSED
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
