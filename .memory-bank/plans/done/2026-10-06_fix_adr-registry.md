---
type: fix
topic: adr-registry
status: queued
depends_on: ["2026-10-06_fix_anthropic-skill-guide-compliance-sprint1-skill.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-06
---
# Plan: fix — adr-registry · отдельный реестр ADR и короткие записи

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** ADR лежат в `backlog.md` (175 КБ) вперемешку с идеями: ADR-001…011 в середине файла
(`backlog.md:865–995`), ADR-012 — в отдельной секции `## ADR` в конце. Записи раздуты: ADR-012 — 3 КБ
(Context 563 симв., Rationale 552, Consequences 711), хотя `commands/adr.md` § 5 требует «одну строку».
Скелет `scripts/mb-adr.sh` (Context/Options/Decision/Rationale/Consequences) и § 4 промпта противоречат § 5.
Решение владельца — AGR-062.

**Expected result.** `.memory-bank/adr.md` — единственное место ADR (append-only, монотонные `ADR-NNN`,
superseded помечаются, не удаляются). Новая запись — 4 поля по 1–2 предложения, ≤ 1 200 байт; длинная
аргументация — в опциональную заметку `notes/` со ссылкой. Существующие 12 ADR перенесены дословно,
в `backlog.md` ADR больше нет (ссылки `решение ADR-009` в идеях остаются — ID не меняются).

**Related files:** `scripts/mb-adr.sh`, `commands/adr.md` (тело), `references/templates.md` (формат ADR),
`references/structure.md`, `rules/RULES.md` (§ backlog.md, File Formats), `agents/mb-manager.md`,
`agents/mb-doctor.md`, `agents/mb-architect.md`, `scripts/mb-init-bank.sh` (скаффолд), `scripts/mb-drift.sh`
и `scripts/mb-index*.{sh,py}` (если сканируют ADR в backlog), `scripts/mb-migrate-structure.sh` (миграция
существующих банков), тесты `tests/bats/test_mb_adr*.bats`.

Порядок после Sprint 1 Stage 3: Stage 3 добавляет оглавления в `references/templates.md` и `structure.md`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Реестр `adr.md` и `mb-adr.sh`

**What to do:**
- `mb-adr.sh` пишет в `<bank>/adr.md` (создаёт с заголовком `# Architecture Decision Records`, если нет);
  ID = max по `adr.md` **и** `backlog.md` (переходный период — без коллизий с ещё не мигрированными банками).
- Новый скелет:
  `### ADR-NNN — <title> [YYYY-MM-DD] · status: accepted` + `**Context:**`, `**Decision:**`,
  `**Alternatives:**`, `**Consequences:**` (по одной строке-подсказке «1–2 sentences»), опц. `**Details:** notes/…`.
- `mb-init-bank.sh`: новый банк получает `adr.md`; секцию ADR в `backlog.md` больше не создаёт.

**Testing (TDD — tests BEFORE implementation):**
- bats: пустой банк → `adr.md` создан, ADR-001; банк с ADR-012 в backlog.md и без adr.md → ADR-013 в adr.md;
  повторный вызов → ADR-014 (монотонность); backlog.md не изменён.
- bats: init нового банка создаёт `adr.md`, в `backlog.md` нет `## ADR`.

**DoD (Definition of Done):**
- [x] новые bats красные до, зелёные после; существующие `test_mb_adr*`/`test_init*` зелёные (или обновлены под новый контракт с пояснением)
- [x] `shellcheck` чистый

**Code rules:** SRP, KISS; без флагов совместимости (YAGNI).

---

<!-- mb-stage:2 -->
### Stage 2: Промпт `/mb adr` — только ключевое

**What to do:**
- `commands/adr.md` § 4–5: одна схема — 4 поля по 1–2 предложения, запись ≤ 1 200 байт; критерий
  «что ключевое»: что решили, почему (одна главная причина), какую альтернативу отвергли и чем, что
  станет дороже. Хронологию, логи, ID прогонов, перечни файлов — не писать; если нужно — `mb-note.sh`
  и ссылка `**Details:**`. Пример хорошей записи (≈6 строк) и одна строка «плохо: …».
- Убрать противоречие «одна строка» (§ 5) против многосекционного скелета; ссылки на `backlog.md` → `adr.md`.
- `references/templates.md`, `references/structure.md`, `rules/RULES.md` (File Formats, § backlog.md),
  `agents/mb-manager.md`, `agents/mb-doctor.md`, `agents/mb-architect.md`: ADR → `adr.md`.

**Testing (TDD):**
- pytest: в `commands/adr.md` нет «backlog.md» как места записи ADR; есть лимит размера; в перечисленных
  файлах ADR не адресуются в backlog.md (`grep`-контракт).

**DoD:**
- [x] тест красный до, зелёный после
- [x] `test_command_descriptions.py` и `test_skill_guide_compliance.py` зелёные (описание adr.md обновлено: «in adr.md»)

**Code rules:** один источник формата ADR — `references/templates.md`, остальные ссылаются.

---

<!-- mb-stage:3 -->
### Stage 3: Миграция существующих банков и этого репо

**What to do:**
- `mb-migrate-structure.sh` (или отдельная подкоманда, если структура скрипта не позволяет): переносит
  все блоки `### ADR-NNN …` (до следующего `### `/`## `) и строки `- ADR-NNN: …` из `backlog.md` в `adr.md`
  **дословно**, по возрастанию ID; пустую `## ADR`/`## Architectural decisions` секцию удаляет; идемпотентно;
  `--dry-run` по умолчанию, `--apply` пишет; бэкап `backlog.md` рядом (`.bak`).
- Прогнать на банке этого репо (`--apply`).

**Testing (TDD):**
- bats: фикстура с ADR в середине и в конце backlog → после `--apply` 0 `### ADR-` в backlog, все блоки
  в adr.md байт-в-байт; повторный запуск — no-op; `--dry-run` ничего не пишет.

**DoD:**
- [x] bats зелёные
- [x] в банке репо: `grep -c '^### ADR-' .memory-bank/backlog.md` = 0, в `adr.md` = 12; сумма байт блоков совпадает
- [x] `scripts/mb-drift.sh .` без новых находок

**Code rules:** данные не удаляются — только переносятся (AGR-043).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Скрипты/агенты, ищущие ADR в backlog.md, перестанут их видеть | M | grep-контракт Stage 2 + `mb-drift.sh`; ID ищется в обоих файлах в переходный период |
| Миграция порвёт backlog.md (вложенные `###` внутри ADR) | M | граница блока — следующий `### ADR-`/`### I-`/`## `; байт-проверка; `.bak` |
| Агент продолжит писать длинно | M | лимит в промпте + проверка размера в `mb-adr.sh` не нужна (YAGNI) — достаточно примера и лимита; контроль в ревью |

## Gate (plan success criterion)

В банке репо ADR только в `adr.md` (12 записей, дословно), `/mb adr` создаёт запись по новому скелету в `adr.md`,
все новые и затронутые тесты зелёные, полный pytest/bats без новых красных против baseline.
