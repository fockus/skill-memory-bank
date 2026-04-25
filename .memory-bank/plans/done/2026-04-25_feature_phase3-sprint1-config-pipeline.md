---
type: feature
topic: phase3-sprint1-config-pipeline
status: done
sprint: 1
phase_of: skill-v2-phase-3
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 3 Sprint 1 — `/mb config` + `pipeline.yaml`

## Context

Phase 2 закрыл input/output traceability вертикаль (`/mb discuss` → context → `/mb sdd` → spec triple → `/mb plan --sdd` → traceability). Phase 3 строит execution engine. Sprint 1 — фундамент: декларативный `pipeline.yaml`, который Sprint 2 (`/mb work`) будет читать для маппинга stage-pipeline / roles / review-rubric / severity-gate / sprint-context-guard.

## Spec references

- `specs/mb-skill-v2/design.md` §8.1 — `/mb work` сигнатура (consumer pipeline.yaml)
- §8.4 — sprint_context_guard (190k hard stop)
- §8.5 — Review loop ядро (severity_gate, max_cycles)
- §9 — Полная схема `pipeline.yaml`

## Out of scope (deferred to Sprint 2)

- Сам `/mb work` — отдельный Sprint 2.
- Hook'и (`context-slim-pre-agent.sh`, `pre-agent-protected-paths.sh`) — Phase 4.
- Реальное использование `roles.override_if_skill_present` — требует runtime detection через работающий /mb work.
- `sdd.full_mode_path` enforcement — уже работает through hard-coded paths в Phase 2 scripts.

## Definition of Done (SMART)

- ✅ `references/pipeline.default.yaml` существует, валиден против схемы, содержит все 8 секций из spec §9 (version, roles, stage_pipeline, budget, protected_paths, sprint_context_guard, review_rubric, sdd)
- ✅ `scripts/mb-pipeline-validate.sh <path>` — exit 0 для default, exit 1 + stderr для malformed
- ✅ Validation покрывает: missing required keys, неизвестные severity_gate keys, version != 1, незарегистрированные роли в stage_pipeline, отрицательные значения budget/sprint_context_guard, неизвестные `on_max_cycles` action'ы
- ✅ `scripts/mb-pipeline.sh` — dispatcher с подкомандами:
  - `init [--force] [mb_path]` — копирует default в `<bank>/pipeline.yaml`, idempotency guard, `--force` overwrites
  - `show [mb_path]` — печатает resolved pipeline (project override → default)
  - `validate [mb_path]` — валидирует resolved config
  - `path [mb_path]` — печатает путь до effective config (project или fallback)
- ✅ `commands/config.md` — slash command spec с frontmatter (`description:` + `allowed-tools: [Bash, Read]`)
- ✅ `commands/mb.md` — router row `config <subcommand>` + `### config <subcommand>` секция
- ✅ Tests: pytest >= 335+N (новые: pipeline-default + validate + pipeline-cli + registration)
- ✅ shellcheck + ruff clean
- ✅ Bank artifacts обновлены (checklist Phase 3 Sprint 1 ✅, status pivots на Sprint 2, roadmap "Recently completed", CHANGELOG `[Unreleased]` Added)
- ✅ Plan → `plans/done/`, status: done

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED tests

**TDD failing tests:**

1. `tests/pytest/test_pipeline_default_yaml.py`:
   - File `references/pipeline.default.yaml` exists и парсится PyYAML.
   - Содержит ключи: `version`, `roles`, `stage_pipeline`, `budget`, `protected_paths`, `sprint_context_guard`, `review_rubric`, `sdd`.
   - `version == 1`.
   - `roles` содержит как минимум: developer, backend, frontend, ios, android, architect, devops, qa, analyst, reviewer, verifier (полный список из spec §9).
   - `stage_pipeline` — list из 3 элементов: implement / review / verify steps.
   - Review step содержит `severity_gate` с keys blocker/major/minor (все integers ≥0) и `max_cycles ≥ 1`.
   - `sprint_context_guard.soft_warn_tokens < hard_stop_tokens`.
   - `review_rubric` содержит секции: logic, code_rules, security, scalability, tests; каждая — non-empty list строк.

2. `tests/pytest/test_mb_pipeline_validate.py`:
   - `scripts/mb-pipeline-validate.sh references/pipeline.default.yaml` → exit 0.
   - Missing key (e.g. `roles`) → exit 1 + stderr содержит "missing".
   - Wrong version (`version: 2`) → exit 1 + "version".
   - Severity_gate с unknown key (`fatal: 0`) → exit 1.
   - Unknown role в `stage_pipeline.role` (например `role: nonexistent`) → exit 1.
   - `roles.<x>` без `agent` → exit 1.
   - Negative budget value → exit 1.
   - `sprint_context_guard.hard_stop_tokens` <= `soft_warn_tokens` → exit 1.
   - Empty file → exit 1.
   - Non-existent file → exit 1 + "not found".
   - Valid minimal config (только required keys) → exit 0.

3. `tests/pytest/test_mb_pipeline_cli.py`:
   - `mb-pipeline.sh init` в empty bank → создаёт `<bank>/pipeline.yaml` идентичный (по байтам) default.
   - Re-run `init` без `--force` → exit 1 + stderr "already exists".
   - `init --force` → перезаписывает.
   - `show` без project pipeline.yaml → печатает default content.
   - `show` с project pipeline.yaml → печатает project content (а не default).
   - `path` без project → возвращает absolute путь до `references/pipeline.default.yaml`.
   - `path` с project → возвращает absolute путь до `<bank>/pipeline.yaml`.
   - `validate` без аргумента — валидирует resolved config (project → default fallback).
   - `validate` с аргументом — валидирует указанный path.
   - Unknown subcommand → exit 2 + usage.

4. `tests/pytest/test_phase3_sprint1_registration.py`:
   - `commands/config.md` существует с frontmatter (description + allowed-tools).
   - `commands/mb.md` router содержит row с `config` (init/show/validate/path).
   - `commands/mb.md` содержит section `### config <subcommand>` с описанием подкоманд.
   - `references/pipeline.default.yaml` существует на ожидаемом пути.

**DoD:**
- ✅ Все ~30+ tests fail (RED, scripts/files отсутствуют)
- ✅ pytest 335 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `references/pipeline.default.yaml`

Полный контент по spec §9 (см. embedded YAML — version, roles 11 шт, stage_pipeline 3 step'а, budget, protected_paths 6 паттернов, sprint_context_guard, review_rubric 5 секций, sdd 5 ключей).

**DoD:**
- ✅ pytest `test_pipeline_default_yaml.py` PASSED
- ✅ YAML парсится без warnings

<!-- mb-stage:3 -->
## Stage 3: GREEN — `scripts/mb-pipeline-validate.sh`

**Implementation:**
- Bash + python heredoc (yaml.safe_load + structural validation).
- Validate: required top-level keys, version, roles structure (object с agent), stage_pipeline (list, role references must exist в roles), severity_gate keys ⊆ {blocker, major, minor}, max_cycles >= 1, on_max_cycles ∈ {stop_for_human, continue_with_warning}, budget non-negative (warn_at_percent ∈ [0,100], stop_at_percent), protected_paths is list, sprint_context_guard hard_stop > soft_warn (both > 0), review_rubric — non-empty lists, sdd boolean fields + covers_requirements_policy ∈ {warn, block, off}.
- Exit code: 0 success, 1 validation error, 2 usage error.
- Error messages: `[validate] <key>: <reason>` to stderr.

**DoD:**
- ✅ pytest `test_mb_pipeline_validate.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: GREEN — `scripts/mb-pipeline.sh` dispatcher

**Implementation:**
- `init [--force] [mb_path]` — resolve `<bank>=<mb>/.memory-bank`, target=`<bank>/pipeline.yaml`. Если existing и нет `--force` — exit 1. Иначе `cp` from `references/pipeline.default.yaml` (resolved relatively to script dir). Print created path.
- `show [mb_path]` — если `<bank>/pipeline.yaml` существует — `cat` его, иначе `cat` default.
- `path [mb_path]` — печатает `realpath` от resolved file.
- `validate [path] [mb_path]` — без аргумента: validate resolved (project → default). С аргументом: validate as-is.
- `--help` / unknown subcommand → exit 2 + usage.
- Использует `_lib.sh` для `mb_resolve_path` if available (но скрипт может работать без bank — для path/show на default).

**DoD:**
- ✅ pytest `test_mb_pipeline_cli.py` PASSED
- ✅ shellcheck clean

<!-- mb-stage:5 -->
## Stage 5: `commands/config.md` + router + bank close-out

1. `commands/config.md` — slash spec с usage, examples, аргументы.
2. `commands/mb.md`:
   - Router table row: `` `config <subcommand>` | Manage execution pipeline.yaml: init / show / validate / path ``
   - `### config <subcommand>` section: описание init/show/validate/path с примерами.
3. Bank update:
   - `checklist.md` — Phase 3 Sprint 1 ✅
   - `status.md` — pivot на Phase 3 Sprint 2 (`/mb work` review-loop)
   - `roadmap.md` — Recently completed entry
   - `CHANGELOG.md` `[Unreleased]` Added entry
4. Plan → `plans/done/`, status: done.
5. progress.md append.

**DoD:**
- ✅ Registration tests PASSED
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
