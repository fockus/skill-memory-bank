---
type: fix
topic: ci-baseline-wave-0
status: in_progress
created: 2026-05-24
level: sprint
parallel_safe: false
baseline_commit: a9093ac8
phase_of: harness-upgrade-and-autopilot
sprint: 0
---

# Plan: fix — CI baseline (Wave 0 before Wave 1)

**Baseline commit:** `a9093ac8`

## Context

**Problem.** `test.yml` workflow на `main` падает **с 2026-04-25** (≈месяц). Никто не смотрел — `pages.yml` зелёный давал ложное ощущение порядка. До старта Wave 1 (reviewer-v2) CI обязательно должен быть зелёным: иначе новые регрессии не отличить от drift'а, и `/mb verify` не сможет служить gate'ом.

**Root causes:**

1. **Casing bit-rot** (Ubuntu only). Test-фикстуры пишут `BACKLOG.md` (uppercase), production scripts читают `backlog.md` (lowercase). macOS case-insensitive HFS+/APFS прятала проблему локально и при `mb-test-run.sh`. 7 файлов affected.
2. **Stale scaffold expectations** (оба OS). `test_mb_init_bank.bats` ожидает `STATUS.md`/`plan.md`/`BACKLOG.md`/`RESEARCH.md`. Scaffold создаёт `status.md`/`roadmap.md`/`backlog.md`/`research.md`. Произошёл refactor `plan.md → roadmap.md` без обновления теста.
3. **Real bugs accumulated** (compact safety, context --deep, research hypothesis, drift detectors, init scaffold, graph-rag adapters, file-change-log perms, get-lang cyrillic).
4. **Go-skip TAP format** (macOS only). `go: ... # skip go required` парсится gh как fail. Надо переключиться на `# SKIP` явно (bats `skip "reason"` builtin).

**Expected result.** `test.yml` зелёный на ubuntu-latest × {3.11, 3.12} и macos-latest × {3.11, 3.12} **на HEAD**. Никаких новых SKIP-ов больше необходимого.

**Related files:**
- Failed runs: `gh run list --branch main --workflow test.yml --limit 10`
- Production source-of-truth filenames: `scripts/mb-init-bank.sh:38` → `(status.md roadmap.md checklist.md backlog.md research.md progress.md lessons.md)`
- Legacy migration tests (DO NOT modify casing): `test_migrate_structure.bats`, `test_migrate_v2.bats`

---

## Stages

<!-- mb-stage:1 -->

### Stage 1: Casing — BACKLOG.md → backlog.md in 7 test files

**What to do:**

В 7 файлах заменить все литералы `BACKLOG.md` → `backlog.md`:
- `tests/bats/test_adr.bats`
- `tests/bats/test_idea.bats`
- `tests/bats/test_compact.bats`
- `tests/bats/test_compact_plan_md.bats`
- `tests/bats/test_compact_checklist.bats`
- `tests/bats/test_doctor_research_drift.bats`
- (`test_mb_init_bank.bats` — отдельно в Stage 2, нужен ещё рefactor `plan.md → roadmap.md`)

**НЕ трогать:** `test_migrate_structure.bats` (legitimate legacy fixture); `test_idea_promote.bats` (уже lowercase); `test_plan_sync.bats` (только comment).

**Testing:** локально на macOS оба варианта проходят (case-insensitive); реальная проверка — push → CI ubuntu-latest.

**DoD (SMART):**
- [ ] `grep -rn "BACKLOG\.md" tests/bats/` показывает только `test_migrate_*.bats`.
- [ ] Локально `bats tests/bats/test_adr.bats tests/bats/test_idea.bats` GREEN.
- [ ] После push: `adr` tests 5-8 + `idea` tests 201-207 GREEN на Ubuntu CI.

<!-- mb-stage:2 -->

### Stage 2: Init-bank scaffold expectations — STATUS/BACKLOG/RESEARCH lowercase + plan.md → roadmap.md

**What to do:**

В `tests/bats/test_mb_init_bank.bats` обновить ожидаемый scaffold под текущую source-of-truth:
- `STATUS.md` → `status.md`
- `BACKLOG.md` → `backlog.md`
- `RESEARCH.md` → `research.md`
- `plan.md` → `roadmap.md`
- 7 core files match `scripts/mb-init-bank.sh:38` exactly.

Аналогично — `tests/bats/test_get_lang_cyrillic.bats` (#341, #342: "auto-detects ru from cyrillic plan.md section") — проверить и обновить на `roadmap.md`.

**DoD:**
- [ ] Test 358 "init: default creates EN bank with all 7 core files" GREEN на обоих OS.
- [ ] Tests 360-362 (lang=ru/es/zh) GREEN.
- [ ] Tests 341, 342 (get-lang cyrillic) GREEN.

<!-- mb-stage:3 -->

### Stage 3: Go-skip TAP format (macOS)

**What to do:**

Найти тесты `go: ...` в bats suite, использующие самописный skip (printing `# skip ...`). Перевести на bats `skip "reason"` builtin → корректный TAP `ok N # skip reason`.

Файлы кандидаты: `tests/bats/test_mb_test_run_go*.bats` (если есть).

**DoD:**
- [ ] Tests 628-630 (go) на macOS показывают `ok N # skip` (зелёные), не `not ok`.

<!-- mb-stage:4 -->

### Stage 4: Real bugs — compact / context --deep / drift / research / file-change-log

**What to do:**

Чинить по подгруппам:
- `compact #66, #68` — safety pattern + BACKLOG archive logic
- `context #102` — `--deep without codebase/` graceful path
- `research #138-144` — hypothesis tracking gaps
- `drift #151, 153, 155, 157, 161, 164` — 6 detectors
- `file-change-log #165, 166` — owner-only 600 perms (likely Linux umask)
- `regression #324` — "Memory Bank structure tree still documented" doc check
- `context integration #435` — global registry mapping

**Approach:** для каждой подгруппы — отдельный исследовательский шаг (root cause из stderr) → точечный fix → bats green. Если подгруппа окажется большой, оторвать в I-NNN.

**DoD:**
- [ ] Все ≥18 fail'ов из категории B зелёные.

<!-- mb-stage:5 -->

### Stage 5: GraphRAG adapters #182-187

**What to do:**

Pi extension wrapper тесты (5 fails). После split на core/render/helper в коммите `bf4fcee` adapter expectations расходятся. Скорее всего — `adapters/pi_graph_rag_extension.ts` интерфейс или manifest changed.

**DoD:**
- [ ] Tests 182-185, 187 GREEN.
- [ ] Manual smoke: Pi extension manifest содержит ожидаемые tool names.

<!-- mb-stage:6 -->

### Stage 6: CI green + verify on PR

**What to do:**

- Создать small PR с финальными правками (если что-то осталось).
- Дождаться зелёного `test.yml` на main.
- Закрыть план через `/mb verify` → `/mb done`.

**DoD:**
- [ ] `gh run list --branch main --workflow test.yml --limit 1` показывает `success`.
- [ ] Wave 1 reviewer-v2 разблокирован.

---

## Gate (plan success criterion)

`gh run view <run-id-after-final-commit>` → conclusion: `success` на всех 4 матриц-комбинациях (ubuntu/macos × python 3.11/3.12).

