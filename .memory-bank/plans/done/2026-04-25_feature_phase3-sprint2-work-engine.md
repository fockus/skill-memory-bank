---
type: feature
topic: phase3-sprint2-work-engine
status: done
sprint: 2
phase_of: skill-v2-phase-3
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 3 Sprint 2 — `/mb work` execution engine + 9 role-agents

## Context

Sprint 1 закрыл декларативный фундамент (`pipeline.yaml`). Sprint 2 строит executable engine: `/mb work <target>` resolves work item, parses range, генерирует execution plan, и dispatch'ит per-stage `implement` step через `Task` tool с auto-selected role-agent. Review-loop (severity gates / max_cycles / fix-cycle / verify-step) — Sprint 3.

Архитектурный принцип: `mb-work.sh` — детерминированный coordinator (resolve / range / plan-emit). Фактические Task tool-вызовы происходят из `commands/work.md` workflow-инструкций, которые читает Claude Code.

## Spec references

- `specs/mb-skill-v2/design.md` §8.1 — сигнатура `/mb work`
- §8.2 — резолв `<target>` (5 форм)
- §8.3 — `--range A-B` авто-детект уровня
- §8.5.1 — Implement step (Sprint 2 scope)
- §8.7 — примеры

## Out of scope (Sprint 3)

- Review-loop (severity gates + max_cycles + fix-cycle).
- Verify step integration (plan-verifier).
- `--auto` end-to-end автопилот hard-stops.
- `--budget` token tracking.
- `--slim`/`--full` context strategy (требует hook'ов из Phase 4).
- `--allow-protected` enforcement (требует pre-agent-protected-paths hook, Phase 4).
- `superpowers:requesting-code-review` override.

Sprint 2 emits в plan-output поля `review_step` / `verify_step` со статусом "deferred", чтобы Sprint 3 имел чёткую интеграционную точку.

## Definition of Done (SMART)

- ✅ `scripts/mb-work-resolve.sh <target>` — 5 форм резолва, печатает plan path(s) или error в stderr
- ✅ `scripts/mb-work-range.sh <plan-or-phase> --range <expr>` — парсит range, авто-детект уровня (stages для plan / sprints для phase), валидация bounds
- ✅ `scripts/mb-work-plan.sh [--target X] [--range A-B] [--dry-run]` — emits JSON Lines execution plan: per-stage objects с (basename, stage_no, heading, role, agent, dod, status). Включает `--dry-run` (no side-effects).
- ✅ Role auto-detection: heuristic по stage heading + body (frontend/backend/ios/android/devops/qa/analyst/architect/developer fallback). Tested.
- ✅ 9 implementer agents в `agents/`: `mb-developer.md`, `mb-backend.md`, `mb-frontend.md`, `mb-ios.md`, `mb-android.md`, `mb-architect.md`, `mb-devops.md`, `mb-qa.md`, `mb-analyst.md`. Каждый — frontmatter (`name`, `description`, `model: sonnet`) + role-specific guidance.
- ✅ 1 reviewer agent: `agents/mb-reviewer.md` — frontmatter + Sprint 3 placeholder для review-loop logic.
- ✅ `commands/work.md` — slash spec с workflow для Claude Code (target resolve → range → emit plan → loop через stages с Task dispatch).
- ✅ `commands/mb.md` — router row + `### work <target>` детальная секция.
- ✅ Tests: pytest >= 398+N (новые: resolve + range + plan + role-detect + agents-registration + work-registration).
- ✅ shellcheck + ruff clean.
- ✅ Bank artifacts обновлены (checklist Phase 3 Sprint 2 ✅, status pivots на Sprint 3, roadmap "Recently completed", CHANGELOG `[Unreleased]` Added).
- ✅ Plan → `plans/done/`, status: done.

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED — target resolver tests

**TDD failing tests in `tests/pytest/test_mb_work_resolve.py`:**

1. Form 1 (existing path): `mb-work-resolve.sh plans/2026-04-25_feature_phase3-sprint2-work-engine.md` → exit 0, prints absolute path.
2. Form 2 (substring search в plans/): `mb-work-resolve.sh phase3-sprint2` → finds the in-progress plan, prints its absolute path. Multiple matches → exit 2 + list.
3. Form 3 (topic name → specs/<topic>/tasks.md): создаём `specs/foo/tasks.md`, `mb-work-resolve.sh foo` → prints tasks.md path.
4. Form 4 (freeform ≥3 words): `mb-work-resolve.sh "fix the auth flake"` → exit 3 (требует interactive confirmation, который делает /mb work workflow). stderr содержит "freeform" и список candidate plans.
5. Form 5 (empty → active plan from roadmap): `mb-work-resolve.sh` без args + `<!-- mb-active-plans -->` блок с одним плана-line → exit 0 + plan path. Empty active block → exit 1 + "no active plan".
6. Не существующий path/topic/substring → exit 1 + "not found".
7. Substring matches multiple plans → exit 2 + ambiguity list.

**DoD:**
- ✅ Все 7+ тестов FAIL (script отсутствует)
- ✅ pytest 398 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `scripts/mb-work-resolve.sh`

**Implementation:**
- Args: `<target>` (optional) + опциональный `[mb_path]` trailing.
- Если target пустой → читать `<bank>/roadmap.md` `<!-- mb-active-plans -->` → `<!-- /mb-active-plans -->` блок, искать строки с `[plans/...](path)` маркер. 0 → exit 1; 1 → print + exit 0; 2+ → exit 2 + list.
- Если target — existing path: print abs path + exit 0.
- Если target NOT existing path:
  - Substring-поиск в `<bank>/plans/*.md` (excluding `done/`) → если 1 match — print + exit 0; 2+ → exit 2 + ambiguity; 0 — fall through.
  - Topic check: `<bank>/specs/<safe_target>/tasks.md` существует → print + exit 0.
  - Freeform check: ≥3 words → exit 3 + candidate list (active plans).
  - Иначе exit 1 "not found".
- Use `_lib.sh` for `mb_resolve_path`, `mb_sanitize_topic`.
- shellcheck clean.

**DoD:**
- ✅ pytest `test_mb_work_resolve.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:3 -->
## Stage 3: RED — range parser tests

**TDD in `tests/pytest/test_mb_work_range.py`:**

1. Single plan + `--range 2-4` (auto-detected level=stages) → emits stages 2,3,4 (matched against `<!-- mb-stage:N -->` markers in the plan).
2. Single plan + `--range 3` → emits только stage 3.
3. Single plan + `--range 2-` → emits stages 2 to end.
4. Plan + `--range 99` → exit 1 + "out of bounds".
5. Plan без `<!-- mb-stage:N -->` markers → exit 1 + "no stages".
6. Multiple plans (phase mode) — sprint level: 3 sprint-планов с `sprint:` frontmatter в одной phase → `--range 1-2` emits sprints 1,2.
7. Phase mode без sprint frontmatter → exit 1 + "phase mode requires sprint frontmatter".
8. Без `--range` → emits всё (default).

**DoD:**
- ✅ Все 8+ тестов FAIL
- ✅ pytest baseline зелёный

<!-- mb-stage:4 -->
## Stage 4: GREEN — `scripts/mb-work-range.sh`

**Implementation:**
- Args: `<plan-or-phase-glob> [--range <expr>] [mb_path]`.
- Plan input → stage-level: scan `<!-- mb-stage:N -->` markers, return ordered stage indices in range.
- Phase input (multiple plan paths) → sprint-level: parse frontmatter `sprint:` field, sort, return ordered sprint indices.
- Range expr parser: `N` (single), `A-B` (closed), `A-` (open-ended to max).
- Output: one element per line (stage_no or sprint plan path).
- Errors to stderr.

**DoD:**
- ✅ pytest `test_mb_work_range.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:5 -->
## Stage 5: RED — plan emitter tests

**TDD in `tests/pytest/test_mb_work_plan.py`:**

1. `mb-work-plan.sh --target <plan>` без range — emits one JSON Lines object per stage.
2. Each emitted object has fields: `plan` (basename), `stage_no`, `heading`, `role` (auto-detected), `agent` (mapped via pipeline.yaml), `status` ("pending"|"in-progress"|"done"), `dod_lines` (count of DoD bullets).
3. Role auto-detection: stage with "frontend" / "React" / "UI" → role=frontend. "backend" / "API" / "Pydantic" → backend. "iOS" / "Swift" / "SwiftUI" → ios. "Android" / "Kotlin" / "Jetpack" → android. "infra" / "Dockerfile" / "k8s" / "CI" → devops. "tests" / "QA" / "pytest" alone → qa. "schema" / "ADR" / "design doc" → architect. "metric" / "data analysis" / "SQL" → analyst. Default → developer.
4. Status detection: `<!-- mb-stage:N -->` followed by stage with all DoD `✅` → status=done. Mixed/empty → pending.
5. `--range 2-4` filters to those stages only.
6. `--dry-run` flag — same output but на stdout печатается human-readable summary header.
7. Empty target (no resolution) → exit 1.

**DoD:**
- ✅ Все 7+ тестов FAIL
- ✅ pytest baseline зелёный

<!-- mb-stage:6 -->
## Stage 6: GREEN — `scripts/mb-work-plan.sh`

**Implementation:**
- Args: `[--target X] [--range A-B] [--dry-run] [mb_path]`.
- Resolve target via `mb-work-resolve.sh`.
- Apply range via `mb-work-range.sh`.
- For each stage (from plan markers): extract heading, body, count DoD bullets, auto-detect role, look up agent in pipeline.yaml.
- Emit JSON Lines (one stage per line).
- `--dry-run`: prepend `## Execution Plan` header + per-stage human summary.
- Use `mb-pipeline.sh path` to find effective pipeline.yaml.
- Python heredoc for YAML loading (PyYAML).

**DoD:**
- ✅ pytest `test_mb_work_plan.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:7 -->
## Stage 7: 9 implementer + 1 reviewer agents

**Files (`agents/`):**

1. `mb-developer.md` — generic implementer fallback. Frontmatter: `name: mb-developer`, `description: Generic memory-bank developer agent for stage implementation when no specialist role matches`, `model: sonnet`. Body: TDD discipline + Clean Architecture + read RULES.md guidance.
2. `mb-backend.md` — backend specialist (API, services, DB). Frontmatter idem. Body: Pydantic / SQLAlchemy / FastAPI hints.
3. `mb-frontend.md` — frontend specialist (React/Vue/components, Tailwind).
4. `mb-ios.md` — iOS specialist (SwiftUI, Combine, async/await).
5. `mb-android.md` — Android specialist (Jetpack Compose, Kotlin, coroutines).
6. `mb-architect.md` — architecture/ADR/design-doc specialist.
7. `mb-devops.md` — CI/CD, Docker, infrastructure specialist.
8. `mb-qa.md` — testing specialist (TDD discipline, coverage, edge cases).
9. `mb-analyst.md` — data/analytics/SQL/metrics specialist.
10. `mb-reviewer.md` — review agent (Sprint 3 will fill в review-loop body; Sprint 2 ships scaffold).

Each agent ≤80 lines, frontmatter-only meaningful structure to keep token budget.

**Tests in `tests/pytest/test_mb_work_agents.py`:**
- All 10 files exist под `agents/`.
- Each has frontmatter с required keys (name, description, model).
- Each `name` matches filename basename without `.md`.
- Each `model` is `sonnet`.

**DoD:**
- ✅ pytest agents tests PASSED
- ✅ All 10 files lint-friendly (no fenced code injection issues)

<!-- mb-stage:8 -->
## Stage 8: `commands/work.md` + router + bank close-out

1. `commands/work.md` — slash spec. Sections: Why, Resolution, Range, Subagent dispatch (Task tool with `subagent_type` = resolved agent), Sprint 3 deferred items, Examples.
2. `commands/mb.md`:
   - Router table row: `` `work <target> [--range A-B] [--dry-run]` | Execute stages from a plan (Phase/Sprint scope). Auto-selects role-agent per stage. Sprint 2: dispatch + dry-run; Sprint 3 adds review-loop. ``
   - `### work <target>` section.
3. Bank update:
   - `checklist.md` — Phase 3 Sprint 2 ✅
   - `status.md` — pivot на Phase 3 Sprint 3 (review-loop ядро)
   - `roadmap.md` — Recently completed entry
   - `CHANGELOG.md` `[Unreleased]` Added entry
4. Plan → `plans/done/`, status: done.
5. progress.md append.

**Registration tests in `tests/pytest/test_phase3_sprint2_registration.py`:**
- `commands/work.md` exists with frontmatter.
- `commands/mb.md` router contains `work <target>` row.
- `commands/mb.md` contains `### work <target>` section.

**DoD:**
- ✅ Registration tests PASSED
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
