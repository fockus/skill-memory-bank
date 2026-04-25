# Plan: refactor — core-files-v3-1

## Context

**Problem:** Четыре core-файла `.memory-bank/` (`status.md`, `roadmap.md`, `checklist.md`, `backlog.md`) утратили чёткие границы ответственности:

- `checklist.md` разросся в archive-журнал (403 строки в live-файле репо) и хранит все этапы всех фич начиная с v2.0.0;
- `backlog.md` из template'а банальный (`## Ideas (пока нет)`), все идеи текут в `roadmap.md § Отложено` и `status.md § v3.1+ backlog` → дублирование;
- `status.md` и `roadmap.md` имеют дублирующие секции "что дальше" (`Roadmap → ⬜ Next` vs `Next steps`);
- `mb-plan-sync.sh` поддерживает только один `<!-- mb-active-plan -->` → при нескольких параллельных планах второй перезатирает первый;
- нет явных links `idea → plan → done`, история теряется.

Подтверждённые дизайн-ответы от пользователя (2026-04-21):

1. Size caps — рекомендации, не enforce;
2. Multi-active-plan — без лимита;
3. Recently-done — default 10, env `MB_RECENT_DONE_LIMIT`;
4. Idea IDs — monotonic global `I-001, I-002, ...`;
5. `backlog.md` split — YAGNI, не делаем;
6. Migration — автоматический `--apply` (с backup в `.memory-bank/.pre-migrate/`);
7. Scope — `v3.1.0` мажорный рефактор;
8. Extra: `/mb compact` также ужимает `checklist.md` (удаляет done-секции) и `roadmap.md` (компрессит "Отложено" / "Отклонено" в BACKLOG).

**Expected result:** `v3.1.0` shipped. Четыре core-файла с чёткими границами, два новых скрипта (`mb-idea.sh`, `mb-idea-promote.sh`, `mb-adr.sh`), расширенные `mb-plan-sync.sh` / `mb-plan-done.sh` / `mb-compact.sh`, one-shot migrator, живой `.memory-bank/` репо мигрирован и проходит все drift-checks, PyPI `3.1.0` + Homebrew bump + GitHub Release.

**Related files:**
- `templates/.memory-bank/{STATUS,plan,checklist,BACKLOG}.md`
- `references/structure.md`
- `scripts/mb-plan-sync.sh`, `scripts/mb-plan-done.sh`, `scripts/mb-compact.sh`
- `scripts/mb-idea.sh` (new), `scripts/mb-idea-promote.sh` (new), `scripts/mb-adr.sh` (new), `scripts/mb-migrate-structure.sh` (new)
- `commands/mb.md`, `commands/mb-cursor.md` (cursor dispatcher)
- `install.sh` (новые скрипты в списке копирования)
- `.memory-bank/` (dogfood migration)
- `README.md`, `CHANGELOG.md`, `docs/MIGRATION-v3.0-v3.1.md` (new)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: RED — тесты для новых форматов и скриптов

**What to do:**
- Добавить `tests/bats/test_plan_sync_multi.bats` — multi-active-plan: два `mb-plan-sync.sh` подряд не перезатирают друг друга, entries в обоих `status.md` и `roadmap.md` под `<!-- mb-active-plans -->` блоком.
- Добавить `tests/bats/test_plan_done_multi.bats` — `mb-plan-done.sh` убирает entry из обоих файлов, prepends в `<!-- mb-recent-done -->` в `status.md` с trim до 10 (или `MB_RECENT_DONE_LIMIT`), удаляет секции `## <Plan title> — Stage N:` из `checklist.md`, меняет status в BACKLOG с `PLANNED → DONE`.
- Добавить `tests/bats/test_idea.bats` — `mb-idea.sh "title" [priority]` appends `I-NNN` c `[<PRIORITY>, NEW, YYYY-MM-DD]`, auto-increment через весь файл, idempotent (дубликат title не создаёт два I-NNN).
- Добавить `tests/bats/test_idea_promote.bats` — `mb-idea-promote.sh I-007 feature` создаёт plan, меняет status `NEW → PLANNED`, добавляет `Plan:` link, запускает `mb-plan-sync.sh`.
- Добавить `tests/bats/test_adr.bats` — `mb-adr.sh "title"` appends `ADR-NNN` skeleton, monotonic ID.
- Добавить `tests/bats/test_compact_checklist.bats` — `/mb compact --apply` удаляет секции checklist, где все items ✅ **и** соответствующий план в `plans/done/`.
- Добавить `tests/bats/test_compact_plan_md.bats` — `/mb compact --apply` мигрирует `roadmap.md § Отложено` / `## Отклонено` в `backlog.md` как DEFERRED / DECLINED ideas (auto I-NNN).
- Добавить `tests/bats/test_migrate_structure.bats` — 4 fixture-сценария: (a) legacy v3.0 structure (status.md с `⬜ Next`, roadmap.md с "Отложено"), (b) идемпотентный повторный запуск (no-op), (c) backup `.pre-migrate/` создан, (d) post-migration — `mb-drift.sh` clean.
- RED-подтверждение: все новые тесты фейлят (0/N green).

**Testing (TDD — tests BEFORE implementation):**
- bats-тесты × 7 новых файлов, суммарно ≥50 сценариев.
- Fixtures: `tests/fixtures/mb-legacy-v3-0/` (структура до миграции), `tests/fixtures/mb-empty/` (чистая пост-`init`).
- Проверка формата: после `mb-idea.sh` → grep `I-001` в BACKLOG; после `mb-plan-done.sh` → grep `<!-- mb-recent-done -->` содержит новую entry; после migrate → `mb-drift.sh` exit 0.

**DoD:**
- [ ] 7 новых bats файлов созданы
- [ ] RED confirmed: ≥50/N фейлят по причине "script/format not implemented"
- [ ] Fixtures готовы: `mb-legacy-v3-0/`, `mb-empty/`
- [ ] Запуск на main: `bats tests/bats/test_plan_sync_multi.bats tests/bats/test_plan_done_multi.bats tests/bats/test_idea.bats tests/bats/test_idea_promote.bats tests/bats/test_adr.bats tests/bats/test_compact_checklist.bats tests/bats/test_compact_plan_md.bats tests/bats/test_migrate_structure.bats` → фейлит по ENOENT / формат

**Code rules:** SOLID, DRY (общие helpers в bats `setup_file`), KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:2 -->
### Stage 2: Templates — новые форматы четырёх core-файлов

**What to do:**
- `templates/.memory-bank/status.md` → новый формат: `## Current phase`, `## Metrics`, `## Active plans` (с `<!-- mb-active-plans -->` markers), `## Recently done (last 10)` (с `<!-- mb-recent-done -->` markers), `## Roadmap (high level)` + deferred-link.
- `templates/.memory-bank/roadmap.md` → `## Current focus`, `## Active plans` (multi, с markers), `## Next up` (links на BACKLOG I-NNN), `## Deferred` (только ссылка на BACKLOG).
- `templates/.memory-bank/checklist.md` → комментарий `<!-- Only active phase tasks. Done phases archived to plans/done/. -->` + пустой starter.
- `templates/.memory-bank/backlog.md` → `## Ideas` с примером `I-001` + status lifecycle commentary (NEW / TRIAGED / PLANNED / DONE / DECLINED / DEFERRED) + `## ADR` с примером `ADR-001`.
- Все 4 template'а содержат валидные `<!-- mb-managed: ... -->` markers для sync-скриптов.

**Testing (TDD):**
- pytest `tests/pytest/test_templates_format.py` (new) — 4 теста: каждый template содержит обязательные секции + markers, размер ≤ рекомендованного cap (STATUS ≤80, plan ≤60 для recommendation, не enforce).
- bats smoke: `mb-init` на `tests/fixtures/mb-empty/` → все 4 файла читаются `mb-plan-sync.sh` (markers присутствуют).

**DoD:**
- [ ] 4 template'а переписаны
- [ ] pytest `test_templates_format.py` → 4 green
- [ ] bats smoke на `mb-init` в чистой директории → все markers найдены

---

<!-- mb-stage:3 -->
### Stage 3: references/structure.md — спецификация форматов

**What to do:**
- Переписать `references/structure.md` секции `### status.md`, `### roadmap.md`, `### checklist.md`, `### backlog.md` под новые форматы с markers.
- Добавить секцию `## File size recommendations (soft caps)`: STATUS ≤80, plan ≤60, checklist ≤100, BACKLOG unlimited, plan-file ≤300.
- Добавить секцию `## Idea lifecycle`: NEW → TRIAGED → PLANNED → (DONE | DECLINED | DEFERRED) + ASCII state diagram.
- Добавить секцию `## Cross-file wiring`: таблица "кто что синхронизирует" (`mb-plan-sync.sh` → STATUS + plan, `mb-plan-done.sh` → STATUS + plan + checklist + BACKLOG, `mb-idea*.sh` → BACKLOG + plan).
- Обновить `## ID schemes`: `I-NNN` (ideas, monotonic global), `ADR-NNN` (decisions), `H-NNN` (hypotheses, существующий), `EXP-NNN` (experiments, существующий).

**Testing (TDD):**
- Нет автоматических тестов — это документ. Manual review: каждый новый формат в docs совпадает с tempate'ом байт-в-байт (кроме пояснительного текста).

**DoD:**
- [ ] `references/structure.md` обновлён под 4 новых формата
- [ ] Секции "size caps", "idea lifecycle", "cross-file wiring", "ID schemes" добавлены
- [ ] `grep -c "<!-- mb-active-plans -->"` в structure.md + templates = matching count

---

<!-- mb-stage:4 -->
### Stage 4: mb-plan-sync.sh — multi-active + status.md sync

**What to do:**
- Сохранить обратную совместимость: если plan-файл имеет старый single-plan formalism → graceful upgrade на multi-формат (автодетект markers `<!-- mb-active-plan -->` → преобразуется в `<!-- mb-active-plans -->` блок c одним entry).
- Переписать функцию `update_active_plan_block()`: вместо `replace` делает `upsert` — ищет строку по basename plan-файла; если есть — обновляет title; если нет — appends в блок.
- Добавить параллельное обновление `status.md § Active plans` с тем же entry.
- Вывод: `[sync] plan=<name> stages=N added_to_checklist=M, status=upsert|new_entry`.

**Testing (TDD):**
- bats из Stage 1 → GREEN (0 фейлов в `test_plan_sync_multi.bats`).
- Regression: `test_plan_sync.bats` (существующий) → остаётся green.

**DoD:**
- [ ] `mb-plan-sync.sh` поддерживает multi-active
- [ ] Пишет в `status.md` + `roadmap.md`
- [ ] Backward-compat: старый `<!-- mb-active-plan -->` авто-upgradeится
- [ ] `test_plan_sync_multi.bats` → green
- [ ] `test_plan_sync.bats` → green (без регрессий)

---

<!-- mb-stage:5 -->
### Stage 5: mb-plan-done.sh — multi-active + recently-done + checklist + BACKLOG

**What to do:**
- Переписать: убирает entry из `<!-- mb-active-plans -->` в **обоих** `roadmap.md` и `status.md` (не весь блок).
- Prepends entry `- YYYY-MM-DD — [<title>](plans/done/<basename>)` в `<!-- mb-recent-done -->` в `status.md`; trim до `MB_RECENT_DONE_LIMIT` (default 10).
- **Удаляет** секции `## <Plan title> — Stage N:` из `checklist.md` (а не только ⬜→✅) — done фазы уходят в `plans/done/*.md`.
- Поиск связанной idea в `backlog.md` через grep `Plan: plans/<basename>` → меняет status с `PLANNED → DONE`, добавляет `Outcome:` плейсхолдер (пользователь заполняет вручную).

**Testing (TDD):**
- `test_plan_done_multi.bats` из Stage 1 → green.
- Regression: `test_plan_done.bats` (существующий) → может потребовать обновления fixture (не регрессия, а expected breaking change под новый формат).

**DoD:**
- [ ] Multi-active delete + recently-done prepend с trim по env
- [ ] Checklist секции удаляются (не только tick'ить)
- [ ] BACKLOG idea auto-status update
- [ ] `test_plan_done_multi.bats` → green
- [ ] `test_plan_done.bats` обновлён под новый формат (или deprecated-marked)

---

<!-- mb-stage:6 -->
### Stage 6: mb-idea.sh — capture idea

**What to do:**
- Новый `scripts/mb-idea.sh` (≤150 строк). Usage: `mb-idea.sh <title> [priority]`; priority ∈ `HIGH|MED|LOW` default `MED`.
- Logic: читает BACKLOG, находит max `I-NNN`, + 1; appends секцию `### I-NNN — <title> [<priority>, NEW, YYYY-MM-DD]` + плейсхолдеры `**Problem:**` / `**Sketch:**` / `**Plan:** —`.
- Idempotent по title: если `### I-\d+ — <title> ` уже существует → exit 0 с предупреждением, не дублирует.
- Output stdout: созданный ID (`I-042`).

**Testing (TDD):**
- `test_idea.bats` из Stage 1 → green.

**DoD:**
- [ ] `scripts/mb-idea.sh` создан, shellcheck 0 warnings
- [ ] Auto-increment через весь файл (не per-section)
- [ ] Idempotency по title
- [ ] `test_idea.bats` → green

---

<!-- mb-stage:7 -->
### Stage 7: mb-idea-promote.sh — idea → plan

**What to do:**
- Новый `scripts/mb-idea-promote.sh`. Usage: `mb-idea-promote.sh I-NNN <type>` (type: feature|fix|refactor|experiment).
- Logic: находит idea по ID → извлекает title → slug → создаёт plan через `mb-plan.sh $type $slug` → в BACKLOG меняет status `NEW|TRIAGED → PLANNED`, добавляет `**Plan:** [plans/<basename>](...)` → прогоняет `mb-plan-sync.sh` на новом плане.
- Validation: если idea уже `PLANNED|DONE|DECLINED` → exit с подсказкой.

**Testing (TDD):**
- `test_idea_promote.bats` из Stage 1 → green.

**DoD:**
- [ ] `scripts/mb-idea-promote.sh` создан, shellcheck 0
- [ ] Validates idea state
- [ ] Запускает mb-plan.sh + mb-plan-sync.sh
- [ ] `test_idea_promote.bats` → green

---

<!-- mb-stage:8 -->
### Stage 8: mb-adr.sh — ADR capture

**What to do:**
- Новый `scripts/mb-adr.sh`. Usage: `mb-adr.sh <title>`.
- Logic: BACKLOG `## ADR` section → max `ADR-NNN`, + 1 → appends skeleton с секциями `**Context:**`, `**Options:**`, `**Decision:**`, `**Rationale:**`, `**Consequences:**` + date.
- Output: созданный ID.

**Testing (TDD):**
- `test_adr.bats` из Stage 1 → green.

**DoD:**
- [ ] `scripts/mb-adr.sh` создан, shellcheck 0
- [ ] Monotonic ADR-NNN
- [ ] `test_adr.bats` → green

---

<!-- mb-stage:9 -->
### Stage 9: mb-compact.sh — расширение на checklist.md и roadmap.md

**What to do:**
- Существующий `mb-compact.sh` добавляет два новых источника candidates:
  - **checklist.md sections**: секция `## <title> — Stage N:` где **все** items ✅ **и** связанный plan-файл в `plans/done/*.md` старше `MB_COMPACT_CHECKLIST_DAYS` (default 30d). Удаляем секцию (материал уже в plans/done/).
  - **roadmap.md `## Отклонено` / `## Отложено`**: мигрирует bullets в BACKLOG как DECLINED / DEFERRED ideas (auto I-NNN), удаляет секции из roadmap.md.
- `--dry-run` (default) печатает: `checklist_sections_to_remove=N`, `plan_md_deferred=N`, `plan_md_declined=N`.
- `--apply` применяет.
- Safety: никогда не трогает секцию с `⬜` items (даже одна несделанная = active).

**Testing (TDD):**
- `test_compact_checklist.bats` → green.
- `test_compact_plan_md.bats` → green.
- Regression: `test_compact.bats` существующий → green.

**DoD:**
- [ ] 2 новых candidate source'а
- [ ] Миграция в BACKLOG через `mb-idea.sh` (reuse, не duplicate logic)
- [ ] Safety: активные секции не трогаются
- [ ] 3 bats файла green

---

<!-- mb-stage:10 -->
### Stage 10: mb-migrate-structure.sh — one-shot migrator

**What to do:**
- Новый `scripts/mb-migrate-structure.sh [--apply]`. Default = dry-run.
- Шаги:
  1. Backup `.memory-bank/.pre-migrate-<timestamp>/` (copy STATUS + plan + checklist + BACKLOG).
  2. `checklist.md`: секции с 100% ✅ и соответствующим plan в `plans/done/` → удаляем. Секции с частью ✅ + активный plan → оставляем (active).
  3. `roadmap.md`: секции `## Отклонено` / `## Отложено` → миграция в BACKLOG (через `mb-idea.sh` вызовы).
  4. `status.md`: `### ⬜ v3.1+ backlog` / `### ⬜ Next` блоки → BACKLOG DEFERRED ideas.
  5. Переписать `status.md` и `roadmap.md` под новые шаблоны с `<!-- mb-active-plans -->` и `<!-- mb-recent-done -->` markers (используя данные из `plans/*.md` + `plans/done/*.md`).
  6. BACKLOG: если пустой (только стандартный header) — переписать под новый формат с пустым starter; если есть содержимое → auto-assign I-NNN для безымянных bullets.
- Post-migration: запустить `mb-drift.sh` → exit 0.

**Testing (TDD):**
- `test_migrate_structure.bats` из Stage 1 → 4 сценария green.
- Идемпотентность: повторный запуск `--apply` → no-op, backup не создаётся повторно.

**DoD:**
- [ ] `scripts/mb-migrate-structure.sh` создан, ≤400 строк, shellcheck 0
- [ ] Backup при первом `--apply`
- [ ] Идемпотентность: второй `--apply` → no-op
- [ ] Post-migration: `mb-drift.sh` clean
- [ ] `test_migrate_structure.bats` → 4/4 green

---

<!-- mb-stage:11 -->
### Stage 11: commands/mb.md — новые subcommands

**What to do:**
- Добавить секции:
  - `### idea <title> [priority]` — capture idea (no subagent, direct `mb-idea.sh` call).
  - `### promote I-NNN <type>` — promote idea to plan (direct `mb-idea-promote.sh` call).
  - `### adr <title>` — capture ADR (direct `mb-adr.sh` call).
  - `### migrate [--apply]` — one-shot migrator (direct `mb-migrate-structure.sh` call). Default dry-run.
- Обновить `### compact` — задокументировать два новых candidate source'а (checklist.md sections, roadmap.md deferred/declined).
- Обновить `### Routing` — добавить 4 новых subcommand'а в таблицу.
- Обновить `### help` — router table покрывает 22 subcommand'а (было 18).

**Testing (TDD):**
- Не тестируется автоматически (это markdown), но smoke: `grep -c "^### " commands/mb.md` = 22.

**DoD:**
- [ ] 4 новых secton'а
- [ ] `### Routing` и `### help` обновлены
- [ ] `/mb help idea` в live-запуске возвращает раздел (через existing help-extract logic)

---

<!-- mb-stage:12 -->
### Stage 12: Dogfood — migrate наш `.memory-bank/`

**What to do:**
- Запустить `scripts/mb-migrate-structure.sh --apply` на корневом `.memory-bank/` репо.
- Verify: все существующие live-файлы приведены к новому формату; `plans/done/*.md` не затронуты; `progress.md` не затронут (append-only); `backlog.md` получил новые `I-NNN` для всех migrated идей.
- `mb-drift.sh` на мигрированном `.memory-bank/` → exit 0.
- Все pytest + bats + e2e → green (matrix).

**Testing (TDD):**
- Full test suite на live `.memory-bank/`:
  - `pytest -q` → без регрессий
  - `bats tests/bats tests/e2e` → без регрессий
  - `mb-drift.sh .memory-bank` → 0 warnings

**DoD:**
- [ ] `.memory-bank/status.md` ≤80 строк, соответствует новому формату
- [ ] `.memory-bank/roadmap.md` ≤60 строк, `<!-- mb-active-plans -->` содержит текущие планы
- [ ] `.memory-bank/checklist.md` содержит только незакрытые этапы
- [ ] `.memory-bank/backlog.md` содержит все `Отклонено`/`Отложено` как ideas с I-NNN
- [ ] `mb-drift.sh` clean
- [ ] Full test suite green

---

<!-- mb-stage:13 -->
### Stage 13: install.sh — новые скрипты + uninstall

**What to do:**
- `install.sh`: добавить `mb-idea.sh`, `mb-idea-promote.sh`, `mb-adr.sh`, `mb-migrate-structure.sh` в список копирования `scripts/*.sh` (wildcard уже копирует всё, но проверить chmod +x).
- `uninstall.sh`: проверить, что эти новые скрипты symmetrically удаляются через manifest (auto-tracked).
- `tests/e2e/test_install_uninstall.bats`: добавить 4 assertion'а на наличие новых скриптов после install.

**Testing (TDD):**
- `test_install_uninstall.bats` → existing green + 4 новых assertion green.

**DoD:**
- [ ] 4 скрипта присутствуют в `~/.claude/skills/memory-bank/scripts/` после install
- [ ] `chmod +x` корректный
- [ ] Uninstall roundtrip clean
- [ ] `test_install_uninstall.bats` → green

---

<!-- mb-stage:14 -->
### Stage 14: Docs — README + CHANGELOG + MIGRATION guide

**What to do:**
- `README.md`: обновить секцию "What it gives you" — добавить idea lifecycle + new subcommands. Обновить дерево `.memory-bank/` (уже сделано в предыдущем коммите — re-verify, добавить BACKLOG pointer если нужно).
- `CHANGELOG.md`: секция `## [3.1.0] — 2026-04-XX` с под-секциями:
  - Added: 4 новых скрипта, 4 новых subcommand'а, multi-active-plan support, idea/ADR lifecycle, migration script
  - Changed (BREAKING): format `status.md` / `roadmap.md` / `checklist.md` / `backlog.md` — migration auto через `/mb migrate --apply`
  - Deprecated: старый single `<!-- mb-active-plan -->` marker (backward-compat остаётся на 1 minor)
- `docs/MIGRATION-v3.0-v3.1.md` (new): пошаговый guide — что меняется, как запустить migration, rollback через backup folder.
- `site/index.html`: обновить hero snippet — добавить 1 строку про idea registry (опционально).

**Testing (TDD):**
- pytest `test_landing_page.py` + `test_docs_links.py` (если есть) → green.

**DoD:**
- [ ] README обновлён
- [ ] CHANGELOG 3.1.0 entry
- [ ] MIGRATION guide создан
- [ ] Внутренние ссылки на новые anchor'ы валидны

---

<!-- mb-stage:15 -->
### Stage 15: Release v3.1.0

**What to do:**
- Bump `VERSION`: `3.0.1 → 3.1.0`.
- Bump `memory_bank_skill/__init__.py::__version__`.
- `git tag -a v3.1.0 -m "..." && git push origin main --follow-tags`.
- Verify OIDC publish → PyPI `memory-bank-skill==3.1.0`.
- `packaging/homebrew/memory-bank.rb` bump url + sha256 для 3.1.0 tarball; push в `fockus/homebrew-tap`.
- GitHub Release с release notes (копия CHANGELOG 3.1.0 секции).

**Testing (TDD):**
- Publish workflow → green (environment `pypi` deployment green).
- `pipx install memory-bank-skill==3.1.0` в clean venv → CLI работает, `memory-bank version` печатает `3.1.0`.
- `brew upgrade fockus/tap/memory-bank` → 3.1.0.

**DoD:**
- [ ] VERSION + `__init__.py` bumped
- [ ] Tag `v3.1.0` запушен
- [ ] PyPI `3.1.0` опубликован (environment pypi зелёный)
- [ ] Homebrew formula обновлена
- [ ] GitHub Release создан с release notes

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Migration портит live `.memory-bank/` в чужих проектах | M | Обязательный backup `.pre-migrate-<timestamp>/` при `--apply`; idempotent повторный запуск; `--dry-run` default; MIGRATION guide с rollback-инструкцией |
| Multi-active marker обратно несовместим со старым `mb-plan-sync.sh` | M | Stage 4 реализует graceful auto-upgrade single → multi при первом sync; deprecated warning для старого marker'а на 1 минорный релиз |
| `backlog.md` разрастётся и станет медленным для grep | L | YAGNI до 500+ идей; awk/sed достаточны |
| Breaking change поломает downstream adapters (Cursor/Windsurf hook'и) | L | Adapters читают только RULES + `.memory-bank/` факт существования, не формат core-файлов; no impact |
| `/mb compact` удалит секции checklist, которые юзер считает активными | M | Safety-правило "любой ⬜ в секции → skip"; dry-run default; audit в STATUS после compact |
| ID-collision при параллельной работе двух разработчиков (оба создают `I-NNN`) | L | File-level lock через `flock`? YAGNI пока — single-user tool; git merge conflict алертит |

---

## Gate (plan success criterion)

План считается полностью выполненным, когда:

1. Все 15 stages DoD выполнены.
2. `pytest -q` + `bats tests/bats tests/e2e` → 0 регрессий (baseline после Stage 12 dogfood).
3. `shellcheck scripts/*.sh` → 0 warnings.
4. `ruff check .` → clean.
5. `mb-drift.sh .memory-bank` на репо → 0 warnings.
6. `pipx install memory-bank-skill==3.1.0` в clean env → `memory-bank version` печатает `3.1.0`; `memory-bank install --clients claude-code` в чистом project dir + `memory-bank init` → `.memory-bank/` соответствует новому формату.
7. GitHub Release v3.1.0 опубликован с MIGRATION guide pointer.
8. Homebrew formula bump merged в `fockus/homebrew-tap`.
