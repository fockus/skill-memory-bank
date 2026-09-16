---
type: fix
topic: sprint1-review-blockers
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-13
---
# Plan: fix — sprint1-review-blockers · три воспроизведённых блокера судьи Sprint 1

**Baseline commit:** f3e23f1c18033e40b0d584d26a7b64bd96dc9422

## Context

**Problem:** cross-model ревью Sprint 1 `mb-work-cost-diet` ([reports/2026-09-13_sprint1-review.md](../reports/2026-09-13_sprint1-review.md), судья NO_GO) воспроизвело три дефекта, внесённых диапазоном `364164a..a18235b`:

- **I-194** (`scripts/mb-checklist-prune.sh:105`, blocker/logic) — идентичность архива = `## [checklist archive] <date> — <label>`, а ключ drop для legacy-секций = `legacy:<heading>`. Две архивируемые `### `-секции с одинаковым заголовком коллидируют: вторая пропускает append (заголовок уже есть), проходит подтверждение по тому же заголовку и попадает в `--drop`; `rewrite` по ключу `legacy:<heading>` удаляет ОБЕ секции, а в `progress.md` дошла только первая. Нарушение AGR-043 и DoD Stage 5 «каждый убранный блок найден в progress.md дословно». Восстановимо только из `.checklist.md.bak.<ts>`.
- **I-195** (`scripts/mb-checklist-v2.py:47`, major/security) — `_titles` и `_is_closed` клеят имя плана из маркера `<!-- mb-plan:… -->` на `plans_dir` без проверки basename/containment: маркер `../../secret/leak.md` читает файл вне банка и выводит его `# `-заголовок в checklist.md; через `_is_closed` подделанный маркер может «закрыть» живой план и увести его блок из реестра. Тот же класс уже закрыт для spec-локатора в `resolve_spec_source` (`scripts/mb-work-state-lib.sh:149-195`).
- **I-196** (`scripts/mb-work-state-lib.sh:117`, major/logic) — три строки коммита 85e39bb (`if not any(kind == "task"): continue`) правильно пропускают stage-only план, но также глотают реальный spec `tasks.md`, который пуст или с искалеченными маркерами: вместо `NOITEM` выходит `NOFILE`, `mb-work-state-eval.sh:121` превращает его в `MBW_DONE_GATE=unverified:no_declaration_surface` и `done` сертифицирует item с битой поверхностью декларации — вопреки контракту в том же файле (строки 76-82, 88).

**Expected result:** три регрессии закрыты по TDD (каждый новый тест виден красным до правки — AGR-027, красный прогон фиксируется в отчёте исполнителя), прежние тесты Stage 5 / eval-гейта зелёные, формат архивного заголовка и публичные интерфейсы скриптов не меняются, `I-194/I-195/I-196` в `backlog.md` → DONE со ссылкой на коммит.

**Related files:**
- `scripts/mb-checklist-prune.sh` (архивация legacy-секций: строки 96-115), `scripts/mb-checklist-v2.py` (`_titles`, `_is_closed`, `_archivable`), `memory_bank_skill/checklist_v2.py` (`legacy_key`, `rewrite`)
- `scripts/mb-work-state-lib.sh::eval_declaration` (строки 83-138) и его контракт (74-82); потребитель — `scripts/mb-work-state-eval.sh::eval_require_done_proof` (NOFILE → allowed, NOITEM → exit 5)
- Образец containment-проверки: `scripts/mb-work-state-lib.sh::resolve_spec_source`
- Тесты: `tests/pytest/test_mb_checklist_prune.py` (21), `tests/pytest/test_checklist_v2.py` (10), `tests/bats/test_mb_work_state_plan_source.bats` (2), `tests/bats/test_mb_work_state_eval*.bats`
- `CHANGELOG.md` § Unreleased → Fixed (одна строка на стадию)

**Не в объёме:** остальные 16 находок ревью (I-197…I-209 — бэклог), I-208 (22 красных теста в чужих подсистемах — отдельный слайс), I-192 (`go test` без таймаута).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: I-194 — архивация legacy-секций устойчива к одинаковым заголовкам

**Role:** developer

**What to do:**
- `memory_bank_skill/checklist_v2.py`: ключ legacy-секции становится уникальным по содержимому — `legacy_key(section, text) = "legacy:<sha1(text)[:8]>:<heading>"`, где `text` — дословный текст секции (`lines[start:end]`, rstrip). Одна реализация; `rewrite()` (строка 246) и `_archivable()` в `scripts/mb-checklist-v2.py` (строка 77) используют ЕЁ, а не собственные f-строки. Две байт-идентичные секции могут делить ключ — это допустимо (текст один и тот же, информация не теряется); секции с одинаковым заголовком и разным телом ключ не делят.
- `scripts/mb-checklist-prune.sh` (цикл 102-114): и решение «уже архивировано» (строка 105), и подтверждение перед `--drop` (строка 109) проверяют ПОЛНЫЙ архивируемый текст `heading + "\n\n" + body` как непрерывную подстроку `progress.md`, а не только заголовок. Проверка — маленькая функция `_archived <progress> <text-file>` на `python3 -` (stdlib, чтение в строку, `text in content`); `grep -F` с многострочным паттерном не годится (сопоставляет строки по отдельности). Формат заголовка `## [checklist archive] <date> — <label>` НЕ меняется (на него завязаны тесты и `references/structure.md`).
- Сообщение `[warn] archive append unconfirmed …` сохраняется для случая, когда полный текст не найден.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка (I-194).

**Testing (TDD — tests BEFORE implementation, красный прогон обязателен):**
- `tests/pytest/test_mb_checklist_prune.py`:
  - `test_two_legacy_sections_with_same_heading_both_reach_progress_before_removal` — чеклист с двумя `### Closed work` секциями (обе ссылаются на `plans/done/…`, тела `FIRST BODY MARKER` / `SECOND BODY MARKER`, без ⬜); после `--apply`: оба тела в `progress.md`, ни одного в `checklist.md`, `progress.count("## [checklist archive]") == 2`, rc 0. До правки: второе тело отсутствует в progress.md и удалено из чеклиста — это воспроизведение судьи.
  - `test_stale_archive_heading_without_body_does_not_certify_removal` — `progress.md` заранее содержит только заголовок `## [checklist archive] <today> — <label>` (без тела), лок append занят (`.work-progress.lock` + `MB_PROGRESS_APPEND_LOCK_TIMEOUT=0`, как в `test_archive_append_unconfirmed_leaves_checklist_untouched`): секция остаётся в чеклисте, `unconfirmed` в stderr. До правки: секция удаляется по одному заголовку.
- `tests/pytest/test_checklist_v2.py`:
  - `test_rewrite_drops_only_the_legacy_section_named_by_its_key` — две секции с одним заголовком, `drop={legacy_key(first, text_first)}` → первая исчезает, вторая (другое тело) остаётся.
- Mutation-улики для верификатора (атрибуция уточнена по прогону verifier'а 2026-09-13, каждая мутация в изоляции): (а) вернуть ключ к `legacy:<heading>` → красный только третий (юнит) тест — CLI-тест №1 остаётся зелёным, потому что полнотекстовая проверка в prune всё равно доносит оба тела до progress.md; (б) вернуть проверку к `grep -qxF "$heading"` → красные первый и второй тесты.

**DoD (Definition of Done):**
- [x] Две `### `-секции с одинаковым заголовком и разными телами после `mb-checklist-prune.sh --apply`: оба тела дословно в `progress.md`, обе убраны из `checklist.md` (регрессионный тест зелёный, красный до правки — вывод красного прогона приложен в отчёте).
- [x] Подтверждение перед `--drop` и решение «уже архивировано» проверяют полный текст `heading+body` в `progress.md`; устаревший одинаковый заголовок без тела не сертифицирует удаление (тест зелёный, красный до правки).
- [x] Ключ drop legacy-секции уникален по содержимому и определён один раз в `memory_bank_skill/checklist_v2.py::legacy_key`; `grep -n '"legacy:' scripts/mb-checklist-v2.py memory_bank_skill/checklist_v2.py` показывает только эту реализацию.
- [x] Формат заголовка архива не изменён: прежние 21 теста `test_mb_checklist_prune.py` и 10 `test_checklist_v2.py` не редактировались и зелёные; `tests/bats/test_plan_done_v2.bats`, `test_plan_sync_v2.bats`, `test_work_checkbox_v2.bats` зелёные.
- [x] `shellcheck scripts/mb-checklist-prune.sh` без замечаний; `python3 -m py_compile` обоих python-файлов; `CHANGELOG.md` содержит строку про I-194.

**Edge cases:** секция, чьё тело — пустая строка (только заголовок): текст = заголовок, хэш от него; байт-идентичные дубликаты → один ключ, одна архивная запись, обе секции убраны (информация сохранена); `progress.md` отсутствует → «не архивировано», append создаёт файл; label с спецсимволами regex (`[`, `(`) — проверка подстрочная, не regex.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:2 -->
### Stage 2: I-195 — имя плана из маркера `mb-plan` никогда не выходит за `plans/`

**Role:** developer

**What to do:**
- `memory_bank_skill/checklist_v2.py`: `is_safe_plan_name(name: str) -> bool` — то же правило, что у `resolve_spec_source` (`scripts/mb-work-state-lib.sh:157-167`): непустое, без `/` и `\`, не начинается с `.`, все символы из `[A-Za-z0-9._-]`. Только объявление правила; файловая система здесь не трогается (модуль чистый).
- `scripts/mb-checklist-v2.py`: единственная точка склейки имени с путём — `_plan_file(plans_dir: Path | None, name: str, *, done: bool = False) -> Path | None`: `None`, если `plans_dir is None`, имя небезопасно, кандидат (`plans_dir/name` или `plans_dir/done/name`) не файл, либо `os.path.realpath(кандидат)` не лежит под `os.path.realpath(plans_dir)` (symlink наружу). `_titles` берёт первый непустой из `_plan_file(name)` / `_plan_file(name, done=True)`; `_is_closed` = `_plan_file(name, done=True) is not None and _plan_file(name) is None`. Больше ни одного `plans_dir / …` с маркерным значением в файле.
- Блок с небезопасным маркером НЕ удаляется и не «чинится» (AGR-043): он рендерится с fallback-заголовком (= сырое значение маркера) и никогда не считается закрытым.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка (I-195).

**Testing (TDD — tests BEFORE implementation, красный прогон обязателен):**
- `tests/pytest/test_checklist_v2.py`: `test_is_safe_plan_name` — `@pytest.mark.parametrize`: ok `2026-01-01_fix_x.md`, `x.md`; bad `../../secret/leak.md`, `/etc/passwd`, `.hidden.md`, `a/b.md`, `a\\b.md`, `..`, `` (пустая), `x y.md`.
- `tests/pytest/test_mb_checklist_prune.py` (CLI-интеграция через `mb-checklist-prune.sh --apply`, фикстура как у судьи):
  - `test_traversal_marker_never_reads_a_file_outside_plans_dir` — `<tmp>/secret/leak.md` с `# top secret project title`; чеклист с `<!-- mb-plan:../../secret/leak.md -->` + `## x — 0/1` + `- ⬜ Stage 1 — s`; после `--apply`: `top secret` отсутствует в checklist.md и progress.md, блок с маркером на месте, rc 0. До правки: заголовок утекает в checklist.md.
  - `test_symlinked_done_plan_outside_the_bank_is_not_closed` — `plans/done/2026-01-01_fix_z.md` → symlink на файл вне банка, `plans/2026-01-01_fix_z.md` отсутствует, блок `2/2`; после `--apply` блок остаётся в чеклисте, progress.md не создан. До правки: блок архивируется как закрытый.
- Mutation-улики (атрибуция по фактическому прогону 2026-09-16, каждая мутация в изоляции): убрать realpath-containment → красный `test_symlinked_done_plan_outside_the_bank_is_not_closed`; убрать вызов `is_safe_plan_name` → traversal-тест ОСТАЁТСЯ зелёным (containment ловит выход за `plans/` независимо), поэтому вызов guard'а доказывается отдельным тестом `test_a_marker_that_is_not_a_plain_basename_is_never_resolved` (маркер `done/<plan>.md` — файл внутри `plans/`, containment пропускает, спасает только правило имени).

**DoD (Definition of Done):**
- [x] Маркер `<!-- mb-plan:../../secret/leak.md -->` при существующем файле по этому пути: `apply` не читает файл (заголовок секрета отсутствует в checklist.md и progress.md), блок остаётся в чеклисте с fallback-заголовком (тест зелёный, красный до правки — вывод приложен).
- [x] `is_safe_plan_name` отвергает абсолютный путь, `..`, разделители `/` и `\`, ведущую точку, пробел и пустое имя (параметризованный тест зелёный).
- [x] Symlink в `plans/done/`, ведущий вне банка, не делает план закрытым — блок не архивируется (тест зелёный, красный до правки).
- [x] Одна точка склейки: `grep -n 'plans_dir /' scripts/mb-checklist-v2.py` находит только тело `_plan_file`; `_titles` и `_is_closed` вызывают его.
- [x] Прежние тесты Stage 5 (см. Stage 1 DoD) зелёные без правок; `python3 -m py_compile`; `CHANGELOG.md` содержит строку про I-195.

**Edge cases:** `plans_dir` не существует (`realpath` даёт несуществующий путь — кандидат не файл → None); маркер с пробелами внутри значения (MARKER_RE уже strip'ает края; внутренний пробел → небезопасно); имя из одних точек; регистр расширения не проверяется (не наша забота — `mb-plan.sh` всегда пишет `.md`).

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

<!-- mb-stage:3 -->
### Stage 3: I-196 — пустой или искалеченный spec `tasks.md` даёт NOITEM, а не NOFILE

**Role:** developer

**What to do:**
- `scripts/mb-work-state-lib.sh::eval_declaration` (python-блок, строки 108-136): признак поверхности декларации — резолвнутый файл с именем `tasks.md` (для source=spec `resolve_spec_source` гарантирует канонический `<bank>/specs/<topic>/tasks.md`; legacy-позиционные вызовы тоже ведут на `…/tasks.md`; план — всегда `<date>_<type>_<topic>.md`). Для такого файла отсутствие `task`-элементов (пустой файл, прозa без маркеров, искалеченные маркеры) И исключение парсера (`ValueError` mixed markers, любой другой сбой) → `NOITEM` немедленно (fail closed). Для файла-не-поверхности (план со stage-элементами или без маркеров) поведение прежнее: `continue` → `NOFILE`. Признак по форме файла, а не по пятому аргументу: `eval_declared_cmd`/`eval_declared_anchors` вызываются и с пустым `legacy`, а kind-гейт на пустом значении вернул бы ровно регрессию 85e39bb.
- Контракт в комментарии (строки 74-82) дополняется: `NOITEM — the declaration file resolved but has no such task, or is empty/unparseable (a broken surface never certifies)`; комментарий у гейта (`# A plan (stage-only items) carries no Eval surface…`) переписывается под новую логику.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка (I-196).

**Testing (TDD — tests BEFORE implementation, красный прогон обязателен):**
- `tests/bats/test_mb_work_state_plan_source.bats` (+3, та же фикстура `setup`):
  - `work_state_plan: an empty spec tasks.md is a broken surface — done refused (exit 5)` — `tasks.md` пустой; `init spec 1 --source-path … --source-topic demo` rc 0; `done` rc 5, в stderr `not found in the declared source` / `refusing to certify`; `status` НЕ содержит `unverified:no_declaration_surface`.
  - `work_state_plan: a spec tasks.md with mangled markers is a broken surface — done refused (exit 5)` — `tasks.md` = проза + маркер-опечатка `mbtask:1` в HTML-комментарии (без дефиса) → rc 5.
  - `work_state_plan: a spec tasks.md the parser rejects (mixed markers) is a broken surface — done refused (exit 5)` — файл содержит и stage-маркер `mb-stage:1`, и task-маркер `mb-task:1` (оба как HTML-комментарии) → `parse_work_items` бросает `ValueError` → rc 5.
  - Существующие два теста файла (план-стадия → `unverified:no_declaration_surface`; tasks.md без нужного item → exit 5) не редактируются и остаются зелёными.
- Mutation-улика: вернуть безусловный `continue` → все три новых теста красные, старые зелёные.

**DoD (Definition of Done):**
- [x] Пустой `specs/demo/tasks.md`: `init spec 1` rc 0, `done` rc 5 с сообщением про сломанный binding, `eval_gate` не равен `unverified:no_declaration_surface` (тест зелёный, красный до правки — вывод приложен).
- [x] Искалеченные маркеры и mixed-markers (`ValueError` парсера) → `done` rc 5 (два теста зелёные, красные до правки).
- [x] Stage-only план по-прежнему сертифицируется `unverified:no_declaration_surface`; `tasks.md` без нужного item — по-прежнему NOITEM (прежние 2 теста файла не редактировались и зелёные).
- [x] Контракт NOITEM/NOFILE в комментарии `mb-work-state-lib.sh` (74-82) описывает новое поведение; `tests/bats/test_mb_work_state_eval.bats` и `test_mb_work_state_eval_r3.bats` зелёные.
- [x] `shellcheck scripts/mb-work-state-lib.sh` без новых замечаний; `CHANGELOG.md` содержит строку про I-196.

**Edge cases:** несколько кандидатов в списке (SRC_PATH + SRC_TOPIC на один и тот же файл) — первый резолвнутый `tasks.md` решает; `tasks.md`, где есть task-элементы, но нужного номера нет — NOITEM как раньше; `tasks.md` с `Eval: none` — WAIVED как раньше; отсутствие файла вовсе — NOFILE как раньше.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Хэш-ключ legacy-секции расходится между `plan` и `apply` в одном прогоне prune | L | Оба вызова читают один и тот же `checklist.md`; хэш от дословного текста секции, не от позиции — расхождение возможно только при параллельной правке чеклиста, которую и раньше не покрывали |
| Ужесточение containment ломает чей-то легитимный маркер с подпапкой | L | `mb-plan-sync.sh`/`mb-plan-done.sh` пишут только basename (`plan_path.name`); grep по `tests/fixtures` на маркеры с `/` перед правкой |
| NOITEM для пустого `tasks.md` ломает legacy-вызовы `init <topic> <n>` | L | Такие вызовы всегда резолвят `…/tasks.md`; для них NOITEM и есть контракт (review [9]); прежние bats-наборы eval-гейта — регресс-щит |
| Полная батарея не запускаема (I-192 `go test` без таймаута, I-208 22 красных) | H | Верификация целевыми наборами: `pytest tests/pytest/test_mb_checklist_prune.py tests/pytest/test_checklist_v2.py`, `bats tests/bats/test_mb_work_state*.bats tests/bats/test_*_v2.bats`; полная батарея не является гейтом этого плана (зафиксировано здесь явно) |

## Gate (plan success criterion)

- Три регрессионных набора (Stage 1–3) зелёные, и для каждого нового теста в отчёте исполнителя есть красный прогон до правки (AGR-027).
- Целевые наборы без регрессий: `test_mb_checklist_prune.py` 21+4, `test_checklist_v2.py` 10+2, `test_mb_work_state_plan_source.bats` 2+3, `test_mb_work_state_eval*.bats`, `test_*_v2.bats`.
- `scripts/mb-drift.sh .` без новых находок относительно baseline `f3e23f1`.
- `backlog.md`: I-194, I-195, I-196 → DONE со ссылкой на коммит; `CHANGELOG.md` § Unreleased → Fixed содержит три строки.
- Публичные интерфейсы (`mb-checklist-prune.sh` флаги, `mb-checklist-v2.py` подкоманды, формат `## [checklist archive] …`, verdict-набор `CMD/WAIVED/NOITEM/NOFILE`) не изменены.
