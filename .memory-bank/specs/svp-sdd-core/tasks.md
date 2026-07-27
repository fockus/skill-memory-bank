---
estimated_tokens:
  total: 950000
  stages:
    "1": 400000
    "2": 330000
    "3": 220000
---

# Tasks: svp-sdd-core

> Слайс S2 (ICE 400). Eval первым (red) → реализация (green).
> Порядок: 1 → 2 → 3 → 9 (детерминированное основание + self-check) → 4 → 5 → 6 (конвейер) → 7 → 8 (eval-first).
> Роли — bare (парсер добавляет `mb-` сам). Бюджеты: Stage 1 = 400k, Stage 2 = 330k, Stage 3 = 220k; итого 950k (`spec=near`, advisory — <1M, не блокирует).
> Ревизия 3 (2026-07-17): бюджеты подняты под работу, добавленную закрытием F-007/F-009/F-010 и
> смыслового аудита (candidate-режим C3, helper C5, state-субкоманды C6, структурный Eval/seam/цикл
> в валидаторе). Frontmatter `estimated_tokens` — схема C3; сверяется `mb-estimate-check.sh`.
> Ревизия 4 (2026-07-18, круг 3): F-010 закрыт реальным швом — `eval-red`/`eval-green` сами гоняют
> команду (флаги `--observed`/`--match`/`--exit` удалены); поведенческий preflight вынесен в
> детерминированный `mb-sdd-self-check.sh` (Task 9, REQ-054 → T9, снят с T8); candidate-lifecycle —
> в `mb-sdd-candidate.sh` (T5, override сужен до spec=over); restricted-glob грамматика C1; status
> state machine draft→ready (T7).
> Red-условия несут машинные якоря C1 (`exit:` / `output~:`) и описывают поведение ПОСЛЕ
> материализации теста — «файла нет» red'ом не считается (C8-preflight → `pending_materialization`).

<!-- mb-task:1 -->
## Task 1: Парсер tasks.md v2 (контракт-ферст)

**Stage:** 1
**Covers:** REQ-004, REQ-005
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb_work_items.py, tests/pytest/test_work_items_v2.py, tests/fixtures/**
**Budget:** 100000

**What to do:**
- Контрактные pytest-фикстуры из ВСЕХ текущих specs/*/tasks.md (легаси-снимок JSON) — ДО любых правок: проекция pre-v2 ключей (`source/topic/item_no/kind/heading/body/role/agent/status/covers/dod_lines`) остаётся byte-identical.
- Расширить `mb_work_items.py` по C1/C2: v2-поля с дефолтами, грамматики Blocked-by (`<n>` | `<topic>#<n>`) и Scope (repo-relative **restricted glob** — только литералы + `*` внутри сегмента + сегмент `**`; без `..`/абсолютных/negation; запрещённые метасимволы `?`/`[`/`]`/`{`/`}`/escape/запятая-в-элементе → malformed exit 2, R3-004), разбор `**Eval:**` на `{cmd, red, exit, output_re}` по red-якорной грамматике C1.
- Frontmatter tasks.md (`estimated_tokens`) — преамбула до первого маркера: подтвердить тестом, что она игнорируется и проекция C2 не меняется.

**Eval:** `pytest tests/pytest/test_work_items_v2.py` — red: парсер не расширен, v2-ключей нет в JSON; exit: 1; output~: `FAILED tests/pytest/test_work_items_v2\.py::test_v2_fields_parsed`

**Testing (TDD — tests BEFORE implementation):**
- pytest: проекция pre-v2 ключей byte-identical на легаси-корпусе; каждое v2-поле; дефолты; смешанный файл; невалидные Blocked-by отклоняются; **restricted-glob malformed-кейсы (R3-004): `src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`, `src/a,b.py` — все пять отклоняются как malformed**; валидные `scripts/*.sh`, `dir/**`, точный путь — приняты; `Eval:` с якорями `exit:`/`output~:` и без них; frontmatter не влияет на проекцию.
- Bash 3.2/portability не затрагивается (python), но фикстуры включают пути с пробелами.

**DoD:**
- [x] Проекция pre-v2 ключей byte-identical; полный JSON содержит корректные v2-ключи и дефолты
- [x] `eval{cmd,red,exit,output_re}` разбирается по C1; frontmatter игнорируется
- [x] pytest green (были red)
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Валидатор — v2-поля, Eval-гейты, структурный Eval, seam, цикл, проверки батареи

**Stage:** 1
**Covers:** REQ-006, REQ-007, REQ-015, REQ-049, REQ-050, REQ-051, REQ-052, REQ-055
**Role:** backend
**Blocked-by:** 1, sdd-openspec-parity#1, sdd-openspec-parity#3
**Scope:** scripts/mb-spec-validate.sh, tests/bats/test_mb_spec_validate_v2.bats, tests/fixtures/**
**Budget:** 120000

**What to do:**
- Расширить `mb-spec-validate.sh`: `Eval: none` на gated → fail (REQ-007); GWT-покрытие gated REQ (интеграция со scenario-гейтом sdd-openspec-parity, без дублирования); v2-поля; кодовые проверки батареи C8 — паритет сценариев (заголовки vs извлечённые блоки, ASCII-имена), роль-резолюция против таблицы ролей, резолюция межспековых Blocked-by.
- Структурная часть Eval-preflight C8 п.4: команда и `red:`-проза непусты; target-токены — repo-relative пути; `output~:`-ERE компилируется; gated-задача несёт `output~:`-якорь (REQ-055; exit-only не принимается); REQ-049 (структурный Eval объявлен) и REQ-050 (waiver: непустая причина, gated → fail, все принятые waiver'ы перечислены в выводе).
- Scope restricted-glob гейт (R3-004): элемент с запрещённым метасимволом (`?`/`[`/`]`/`{`/`}`/escape/запятая-в-элементе) → malformed, spec-валидация exit 2 (та же грамматика, что в парсере T1).
- Seam-гейт C9 (REQ-051): `≥2` элемента в `**Seams:**` без непустой `**Seam rationale:**` → violation.
- Цикл-гейт (REQ-052): граф `Blocked-by` проверяется до принятия спеки; цикл → exit non-zero + печать полного упорядоченного пути.
- **Eval byte-identity design↔tasks (CPR-D)**: каждая `**Eval:**`-строка в `design.md` §Eval declarations обязана быть byte-identical `**Eval:**`-строке одноимённой задачи в `tasks.md`; расхождение (в т.ч. `\|` против `|` в `output~:`-якоре) → провал. Предотвращает дрейф якоря между декларацией и исполняемой строкой (пайп-таблица в design → `\|`, а `\|` в POSIX ERE — литерал, не альтернатива).
- Легаси-инварианты: спеки без `**Eval:**`/`**Seams:**` не получают ни одной новой ошибки (D-26).

**Eval:** `bats tests/bats/test_mb_spec_validate_v2.bats` — red: валидатор не расширен, гейты не срабатывают и негативные фикстуры проходят «зелёными»; exit: 1; output~: `not ok [0-9]+ .*(eval_none_gated|blocked_by_cycle|seam_rationale)`

**Testing (TDD — tests BEFORE implementation):**
- bats: Eval:none на gated → fail; waiver без причины → fail; waiver на gated → fail; non-gated waiver с причиной → pass + перечислен в выводе; docs-задача без структурного Eval → fail; gated-задача без `output~:`-якоря → fail (exit-only якорь не принимается: `bats` на отсутствующем файле даёт тот же exit 1, что и настоящий провал — см. design C1); невалидный `output~:`-ERE → fail; restricted-glob malformed (`src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`, `src/a,b.py`) → fail exit 2, валидный `scripts/*.sh`/`dir/**` → pass (R3-004); **Eval design↔tasks byte-identity (CPR-D): фикстура с расходящимся якорем (design `\|` vs tasks `|`) → fail; идентичные → pass**; два seam без rationale → fail, с rationale → pass, один seam без rationale → pass; цикл `2 -> 3 -> 2` и self-cycle `1 -> 1` → fail с печатью пути; безмаркерные сценарии при заголовках → fail; кириллическое имя сценария → fail; `Role: mb-backend` → fail с подсказкой bare; неизвестный `<topic>#<n>` → fail; легаси-корпус — ноль новых ошибок.
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами; `LC_ALL=C`.

**DoD:**
- [x] Гейты (Eval/waiver/seam/цикл) + батарея-проверки реализованы; легаси-спеки валидны
- [x] Цикл печатает полный упорядоченный путь; waiver'ы перечислены в выводе
- [x] bats green (были red); shellcheck clean
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Бюджет-оценка spec-triple + candidate-режим

**Stage:** 1
**Covers:** REQ-009
**Role:** backend
**Blocked-by:** 1, svp-interview-upgrade#3
**Scope:** scripts/mb-estimate-check.sh, tests/bats/test_mb_estimate_check_spec.bats
**Budget:** 90000

**What to do:**
- Расширить `mb-estimate-check.sh` двумя взаимоисключающими режимами строго по C3: `--spec <topic|spec-dir>` (принятая спека) и `--tasks-file <path>` (candidate — гейт генерации, F-007). Только явные Budget, `legacy_missing`, key=value stdout, пороги ok/near/over, exit 0/1/2, сверка с frontmatter `estimated_tokens.{total,stages}`.
- `--tasks-file` читает РОВНО переданный файл: триплет не резолвится, существующий `specs/<topic>/tasks.md` не открывается. Позиционный context-режим S1 (`svp-interview-upgrade` C1) остаётся byte-identical; два источника одновременно → exit 2.
- Скрипт остаётся чистым чекером: ничего не пишет, не переносит и не читает `budget_override`.

**Eval:** `bats tests/bats/test_mb_estimate_check_spec.bats` — red: режимов `--spec`/`--tasks-file` нет, скрипт трактует флаг как context-файл и отвечает usage-ошибкой; exit: 1; output~: `not ok [0-9]+ .*tasks_file`

**Testing (TDD — tests BEFORE implementation):**
- bats: ok / near / over; task_over / stage_over; legacy_missing с одним warning; malformed Budget → exit 2; расхождение frontmatter ↔ stdout → exit 1.
- Candidate-кейсы (F-007): candidate ok → exit 0; candidate over → exit 1; **stale final игнорируется** (в `specs/<topic>/tasks.md` лежит старая мелкая спека, candidate большой → over, и наоборот); отсутствующий candidate → exit 2; `--spec` + `--tasks-file` вместе → exit 2; позиционный context-файл + `--tasks-file` → exit 2.
- Регрессия S1: позиционный `<context-file>`-режим byte-identical (stdout + exit) на фикстурах S1.
- Portability: Bash 3.2 (macOS) и Linux; GNU/BSD-утилиты; путь с пробелами; `LC_ALL=C`.

**DoD:**
- [x] Оба режима C3 реализованы; stale final доказано не влияет на оценку candidate
- [x] Позиционный режим S1 byte-identical; bats green (были red); shellcheck clean
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Конвейер генерации в commands/sdd.md

**Stage:** 2
**Covers:** REQ-001, REQ-002, REQ-003, REQ-013, REQ-015
**Role:** architect
**Blocked-by:** 1, 2, 3, 9
**Scope:** commands/sdd.md, tests/pytest/test_sdd_command_contract_v2.py
**Budget:** 120000

**What to do:**
- Переписать `commands/sdd.md` в конвейер (Architecture шаги 0–10): оркестрация discuss/self-interview; обязательное чтение транскриптов (отсутствие файла — громкая ошибка); генерация полного контента (stories+EARS, §Contract с seam-блоком C9 и подтверждением у пользователя, candidate tasks.md v2 с Eval/Scope/Budget); self-check DAG по candidate; батарея C8 как обязательный **шаг 7 на staged draft-триплете** `<bank>/tmp/sdd/<topic>/` — ДО промоушена, принятый `specs/<topic>/tasks.md` на этом шаге НЕ тронут (design rev 5, REQ-053: провал батареи не имеет права уничтожить принятый триплет) — конвейер **вызывает** детерминированный `mb-sdd-self-check.sh` (C8a, Task 9), а не воспроизводит preflight промптом; по его `self_check`/`eval.<task-id>` и exit решает draft→ready (C7 §Status state machine); отчётные статусы C7 (`sdd_status=blocked|invalid`).
- Candidate-seam (F-007): шаг 4 пишет `<bank>/tmp/sdd/<topic>/tasks.candidate.md`, шаг 5 гоняет `mb-estimate-check.sh --tasks-file` по нему; **шаг 9** публикует через `mb-sdd-candidate.sh publish` (draft) — только после прохождения C8 (шаг 7) и разрешения review (шаг 8); `specs/<topic>/tasks.md` до шага 9 не создаётся и не изменяется. Ветки меню D-35 и вызовы candidate-helper — задача 5.

**Eval:** `pytest tests/pytest/test_sdd_command_contract_v2.py` — red: конвейер не переписан, `commands/sdd.md` всё ещё содержит «does not auto-generate» и не содержит фаз; exit: 1; output~: `FAILED tests/pytest/test_sdd_command_contract_v2\.py::test_pipeline_phases_ordered`

**Testing (TDD — tests BEFORE implementation):**
- pytest по контракту команды: фазы 0–10 упорядочены; транскрипт-вход обязателен; candidate-seam присутствует и предшествует записи в specs/; **шаг 7 вызывает** `mb-sdd-self-check.sh` по staged draft и блокирует промоушен по его exit; **шаг 9** публикует как **draft** (не accepted) и только после C8+review — порядок связан тестом (`test_self_check_precedes_promotion`: позиция вызова self-check в документе строго меньше позиции `publish`); draft→ready только по C7 state machine; утверждение «does not auto-generate» удалено.
- Граница честности: pytest проверяет контракт prompt-файла (структуру и нормативные клаузы), а не поведение LLM — фактическая генерация проверяется ручными Scenarios ниже и батареей C8 на реальном топике.
- Ручные Scenarios §1, §2, §12, §14, §20 на фикстурном топике.

**DoD:**
- [x] Конвейер 0–10 с батареей C8 и candidate-seam; pytest green (был red)
- [x] Сценарии §1/§2/§12/§14/§20 отрабатывают
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Эскалация D-35, candidate-lifecycle, декомпозиция и реестр

**Stage:** 2
**Covers:** REQ-010, REQ-011, REQ-014, REQ-053
**Role:** architect
**Blocked-by:** 4
**Scope:** scripts/mb-sdd-candidate.sh, commands/sdd.md, references/templates.md, tests/bats/test_mb_sdd_candidate.bats, tests/pytest/test_sdd_escalation_d35.py
**Budget:** 120000

**What to do:**
- Новый `scripts/mb-sdd-candidate.sh` (C4a — детерминированный candidate lifecycle, F-007, REQ-010/053; закрывает R3-002/R3-003): `publish`/`discard`; publish разбирает вердикт C3 (`--estimate-file`), проверяет канонический путь candidate, делает same-filesystem `rename`; **override сужен (R3-003)**: `budget_override: user` снимает ТОЛЬКО `spec=over` при `task_over=none ∧ stage_over=none`; при `task_over != none` или `stage_over != none` — **всегда** blocked (hard-лимиты D-13 нерушимы, override не применяется); byte-identity финала при любом отказе; stdout `candidate=published|discarded|blocked reason=<code>`; exit 0/1/2. Publish кладёт триплет как **draft** (статус меняет оркестратор по C7 state machine).
- Врезка в `commands/sdd.md`: **шаг 9** зовёт `mb-sdd-candidate.sh publish` (не prompt-`mv`) — финальный гейтованный шаг после C8 (7) и review (8); эскалация D-35 → `discard` + `sdd_status=blocked`.
- Эскалационное меню D-35 по C4: 4 варианта; auto → self-interview слайсы + assumption; child-спеки → `group` + `parent_context` frontmatter; реестр только через `mb-idea.sh "[SPEC:<group>] <child-topic>"` (оркестратор — единственный writer до S4); частичный отказ — громкий отчёт с перечнем незаписанных children.

**Eval:** `bats tests/bats/test_mb_sdd_candidate.bats` — red: `scripts/mb-sdd-candidate.sh` не существует, конвейер не переписан; exit: 1; output~: `not ok [0-9]+ candidate_publish: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь)**: каждый bats-тест в `test_mb_sdd_candidate.bats` начинается с `candidate_publish: ` (обоснование X-05: `bats` на отсутствующем файле даёт `not ok 1 bats-gather-tests` с тем же exit 1 — якорь обязан быть положительным именованным префиксом).
- bats (C4a, ДО скрипта) — **четыре override-матрицы R3-003**: `spec=over` + task_over=none + stage_over=none + `--override user` → `candidate=published` exit 0; `task_over=<id>` + `--override user` → `candidate=blocked reason=task_overflow` exit 1; `stage_over=<id>` + `--override user` → `candidate=blocked reason=stage_overflow` exit 1; combined (task_over ∧ stage_over) + `--override user` → blocked exit 1. Плюс: `spec=ok/near` без overflow → published; `spec=over` без override → `blocked reason=spec_overflow`; при любом blocked/malformed финал byte-identical (снимок до/после); malformed вердикт (нет `spec=`) / неканонический `--candidate` → exit 2; `discard` удаляет candidate, финал не трогает; shellcheck clean.
- pytest (дополнительный, `test_sdd_escalation_d35.py`): каждая из 4 веток меню D-35; auto-ветка пишет assumption; запись реестра идёт через mb-idea.sh; частичный отказ оставляет созданные children в draft и перечисляет остальные; осиротевший candidate от прошлого прогона перезаписывается, а не принимается.
- Ручные Scenarios §5, §11, §13, §19.

**DoD:**
- [x] `mb-sdd-candidate.sh` (publish/discard, override сужен до spec=over) реализован; bats green (был red)
- [x] Candidate переносится атомарно только по вердикту гейта; task/stage-overflow всегда blocked даже с override; принятый tasks.md byte-identical при любом отказе
- [x] Меню D-35 + реестр + auto-ветка (pytest); Сценарии §5/§11/§13/§19 отрабатывают
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Scaffold-совместимость и шаблоны v2

**Stage:** 2
**Covers:** REQ-002, REQ-005, REQ-049, REQ-051
**Role:** developer
**Blocked-by:** 4
**Scope:** scripts/mb-sdd.sh, commands/sdd.md, references/templates.md, tests/pytest/test_sdd_scaffold_compat.py
**Budget:** 90000

**What to do:**
- Граница C7: `mb-sdd.sh` остаётся byte-identical scaffold-only; `--scaffold-only` в `/mb sdd` — алиас на тот же writer; конвейер не вызывает writer до D-35.
- Шаблоны в `references/templates.md`: блок задачи tasks.md v2 (с `**Eval:**`-строкой, несущей якорь `exit:`/`output~:`), §Contract с seam-блоком C9 (`**Seams:**` + `**Seam rationale:**`), образец **структурного Eval** для docs/config-задачи (REQ-049: наличие файла / наличие секции / exit линтера) и waiver-формы `none — waiver: <reason>` с пометкой «явное исключение, non-gated only», меню D-35.

**Eval:** `pytest tests/pytest/test_sdd_scaffold_compat.py` — red: совместимость и шаблоны не оформлены, `references/templates.md` не содержит v2-блока; exit: 1; output~: `FAILED tests/pytest/test_sdd_scaffold_compat\.py::test_templates_carry_v2_block`

**Testing (TDD — tests BEFORE implementation):**
- pytest: вывод mb-sdd.sh на фикстурах byte-identical до/после; `--scaffold-only` даёт тот же результат; templates.md содержит v2-блок с bare Role, seam-блок C9, структурный Eval-образец и waiver-форму с пометкой non-gated.

**DoD:**
- [x] C7 реализован; mb-sdd.sh byte-identical; pytest green (был red)
- [x] Шаблоны несут якорный Eval, seam-блок, структурный Eval и waiver-форму
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: spec_review — config + исполняемый владелец вердикта

**Stage:** 3
**Covers:** REQ-012
**Role:** developer
**Blocked-by:** 4
**Scope:** references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, scripts/mb-sdd-review-result.sh, commands/sdd.md, tests/bats/test_sdd_spec_review.bats
**Budget:** 110000

**What to do:**
- Схема C5 в `references/pipeline.default.yaml` — **инлайн-мапой** `spec_review: {enabled: false, agent, model, thinking}` (обязательно: `parse_simple_mapping`+`parse_inline_map` PyYAML-optional-пути; вложенный блок дал бы `None`) + проверки в `mb-pipeline-validate.sh` рядом с существующими `sdd.*` (строки 606-627).
- Новый `scripts/mb-sdd-review-result.sh` (F-009 — исполняемый владелец exit-кодов): `check` (same_model до диспатча → stderr `same_model`, exit 2) и `record` (строгая валидация схемы вердикта, append одной компактной строки в `<bank>/tmp/spec-review/<topic>.jsonl` с `ts`+`attempt`, exit 0 APPROVED / 1 CHANGES_REQUESTED / 2 same_model|unavailable|malformed).
- Шаг ревью в `commands/sdd.md`: промпт владеет диспатчем модели с транскриптом+спекой и передаёт helper'у сырой JSON и фактически резолвленные model ID; судья — человек/оркестратор; недоступность → SKIPPED loudly отдельной JSONL-строкой.
- **Status state machine draft→ready (C7, R3-006)**: все опубликованные триплеты — `status: draft`; переход в `ready` только при C8=pass (`mb-sdd-self-check.sh` exit 0) **и** одном из: ревью выключено / APPROVED / явное решение принять SKIPPED|отклонённые issue (пишется JSONL-строкой). C8-провал или CHANGES_REQUESTED → draft; SKIPPED без решения → draft. Правки после CHANGES_REQUESTED — новый candidate→C3→staged C8→ревью→атомарный промоушен (порядок шагов 7–9; промоушен последний, REQ-053).

**Eval:** `bats tests/bats/test_sdd_spec_review.bats` — red: `scripts/mb-sdd-review-result.sh` не существует, конфига и шага нет; exit: 1; output~: `not ok [0-9]+ .*(same_model|jsonl_append)`

**Testing (TDD — tests BEFORE implementation):**
- bats: валидный конфиг; конфиг со значением, содержащим `,` → reject; `enabled: true` без model/agent → reject; `thinking: extreme` → reject; same_model → reject до диспатча (exit 2, ноль записей); APPROVED → exit 0; CHANGES_REQUESTED → exit 1; unavailable → status=skipped + громкий отчёт + JSONL-строка; malformed JSON → exit 2; **append двух attempts** — вторая строка не затирает первую, последняя валидная строка = текущий вердикт.
- **Status-переходы (R3-006)**: `disabled → ready`, `APPROVED → ready`, `CHANGES_REQUESTED → draft`, `SKIPPED без решения → draft` — по exit `mb-sdd-review-result.sh` + `mb-sdd-self-check.sh`.
- Паритет загрузчиков: конфиг парсится идентично с PyYAML и без него (fallback-ветка).

**DoD:**
- [x] Схема + helper + шаг; exit-коды принадлежат скрипту, не прозе; status state machine draft→ready реализована и оттестирована (4 перехода)
- [x] JSONL append-only, история попыток не перезаписывается; bats green (были red); shellcheck clean
<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: Eval-first врезка в /mb work (red обязателен)

**Stage:** 3
**Covers:** REQ-008
**Role:** developer
**Blocked-by:** 1, 4
**Scope:** commands/work.md, scripts/mb-work-state.sh, tests/bats/test_work_eval_first.bats, tests/bats/test_mb_work_state_eval.bats
**Budget:** 110000

**What to do:**
- Расширить единственный durable writer состояния `scripts/mb-work-state.sh` субкомандами C6 (F-010 — сегодня в схеме нет ни поля `eval`, ни субкоманды, `scripts/mb-work-state.sh:7-15`). **Helper — единственный исполнитель и судья Eval-команды (закрытие F-010 реальным швом):** `eval-red --cmd-file <path> --output-re <ERE> [--expected-exit <n>]` и `eval-green --cmd-file <path>` — **флаги `--exit`/`--observed`/`--match` удалены**; обе субкоманды САМИ запускают byte-identical содержимое `--cmd-file` из git root, САМИ захватывают combined stdout+stderr и фактический exit. `eval-red` вычисляет `red_match` внутри helper (совпал ли факт. output с ERE и, если задан, факт. exit с `--expected-exit`); возвращает 0 только при наблюдённом заявленном red, mismatch/foreign/уже-зелёная → exit 1, некомпилируемый ERE/usage/битый state → exit 2; создаёт `eval:{cmd, red_exit=факт.захваченный, red_observed=red_match, red_match, green_exit:null}`. `eval-green` сам гоняет сохранённую (byte-identical) команду, 0 только при факт. exit 0; дрейф cmd → exit 1; usage/битый state → exit 2. Обе парсят свои флаги сами (образец `init`), переиспользуют `state_path`/`require_valid_state`; `parse_common_flags` не трогается; шапка-схема дополняется ключом `eval`.
- В `commands/work.md` implement-шаге — контракт C6: материализация eval-кода до реализации; запись через субкоманды выше (прямое редактирование JSON запрещено); helper сам матчит якоря C1 (`--output-re`/`--expected-exit`), посторонний сбой = FAIL и блокирует implement (только явный логируемый override продолжает); verify зовёт `eval-green` (helper сам гоняет и требует факт. green); waiver только для non-gated.

**Eval:** `bats tests/bats/test_work_eval_first.bats` — red: `mb-work-state.sh` не знает `eval-red`/`eval-green` (отвечает usage, exit 2), врезки в work.md нет; exit: 1; output~: `not ok [0-9]+ .*eval_red`

**Testing (TDD — tests BEFORE implementation):**
- bats (work.md): helper сам запускает cmd-file; совпадающий red принят; посторонний сбой (факт. output не совпал с `--output-re`, либо факт. exit ≠ `--expected-exit`) отклонён; отсутствие red блокирует; green обязателен в verify; дрейф команды = FAIL.
- bats (state) — **невозможность подмены (F-010)**: вызов `eval-red`/`eval-green` при команде, которая на самом деле НЕ даёт заявленный red / НЕ зелёная, возвращает exit 1 и НЕ пишет `red_observed=true`/green — подставить verdict аргументом нельзя; `eval-red` создаёт объект с `green_exit: null` и захваченным факт. `red_exit`; `eval-green` при byte-identical cmd+факт.green → 0, при дрейфе/красной → 1; без init → exit 2; per-run изоляция (`--run-id`) работает; **регрессия: вывод и exit-коды init/step/cycle/status/list/done/clear byte-identical**.
- Portability: Bash 3.2 (macOS) и Linux; `LC_ALL=C`.
- Ручной Scenario §4 на фикстурной задаче.

**DoD:**
- [x] C6 реализован (FAIL, не warning) через авторитетный writer; helper сам гоняет команду, подмена verdict через CLI невозможна (доказано тестом); старые субкоманды byte-identical
- [x] bats green (были red); shellcheck clean; сценарий §4 отрабатывает
<!-- /mb-task:8 -->

<!-- mb-task:9 -->
## Task 9: Детерминированный исполнитель батареи C8 — `mb-sdd-self-check.sh` (generation preflight)

**Stage:** 1
**Covers:** REQ-054, REQ-056
**Role:** backend
**Blocked-by:** 1, 2, 3
**Scope:** scripts/mb-sdd-self-check.sh, scripts/mb-sdd-self-check-eval.sh, tests/bats/test_mb_sdd_self_check.bats, tests/bats/test_mb_sdd_self_check_multi.bats, tests/bats/test_mb_sdd_self_check_phase.bats, tests/fixtures/**
**Budget:** 90000

**What to do:**
- Новый `scripts/mb-sdd-self-check.sh --spec <topic|spec-dir> [--mb <bank>]` (C8a — вынос поведенческого Eval-preflight REQ-054 из prompt в детерминированный seam, закрывает R3-001). Исполняет батарею C8.1–C8.5 над триплетом: вызывает `mb-spec-validate.sh` (структурная часть + gated-`output~:`), `mb-scenario-extract.py` (паритет), `mb_work_items.py` (парс + роль-резолюция), резолюцию межспековых `Blocked-by` (цикл → fail).
- **Поведенческий preflight (REQ-054, ядро задачи):** для каждой задачи резолвит target-токены Eval (токены с `/`, не начинающиеся с `-`, C1). Все target существуют → helper САМ исполняет команду и обязан наблюдать заявленный red-якорь → `eval.<id>=ready`; уже-зелёная / red не совпал с якорем → `invalid`; missing раннер-инструмент → `invalid` reason `tool_unavailable`; хотя бы один target отсутствует → `pending_materialization` (НЕ observed red, НЕ влияет на exit).
- stdout: первая строка `self_check=ready|invalid phase=generation|done`, затем `eval.<task-id>=…` по возрастанию task-id, и `eval.<task-id>.reason=<code>` у каждого `invalid` (I-172 — девять одинаковых `invalid` без единой причины стоили четырёх шагов чтения исходника). Exit: 0 нет invalid + структурные прошли; 1 любой structural/behavioral violation; 2 usage/неразрешимый topic/malformed. Чекер — банк/триплет не пишет.

**Eval:** `bats tests/bats/test_mb_sdd_self_check.bats tests/bats/test_mb_sdd_self_check_multi.bats tests/bats/test_mb_sdd_self_check_phase.bats` — red: `scripts/mb-sdd-self-check.sh` не существует (отвечает `command not found`/usage), preflight-логики нет; exit: 1; output~: `not ok [0-9]+ self_check: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь)**: каждый bats-тест в `test_mb_sdd_self_check.bats` начинается с `self_check: ` (обоснование X-05: `bats` на отсутствующем файле даёт `not ok 1 bats-gather-tests` с тем же exit 1 — якорь обязан быть положительным именованным префиксом).
- bats: фикстурный триплет с тремя задачами (§20) — target отсутствует → `pending_materialization` + self_check остаётся ready + exit 0; target существует и команда зелёная → `eval.<id>=invalid` + self_check=invalid + exit 1; target существует и падает с заявленным red-якорем → `ready`; missing раннер-инструмент при существующем target → `invalid tool_unavailable`, никогда не ready и не red; цикл `Blocked-by` → exit 1; безмаркерные сценарии/роль-коллизия → exit 1 (делегирует C8.1–C8.3); неразрешимый topic → exit 2; порядок строк `eval.*` по task-id; shellcheck clean.
- Двусторонняя проверка поведенческого правила: (A) отсутствующий target НЕ даёт observed red; (B) реальный совпавший red даёт `ready`.
- Portability: Bash 3.2 (macOS) и Linux; `LC_ALL=C`.
- Ручной Scenario §20 на фикстурном топике.

- **Фаза (REQ-056, AGR-037):** `--phase generation|done`, дефолт `generation`. В generation требуется наблюдаемый заявленный red (`pending_materialization` честен); в done требуется фактический green, а отсутствующий target — провал (`target_missing`), не «ещё не материализовано». C7 гейтит `draft→ready` по `--phase done`. Неизвестная фаза — usage exit 2; дефолт назван в usage и печатается в строке вердикта, потому что `self_check=invalid` без фазы означает противоположные вещи.

**DoD:**
- [x] `mb-sdd-self-check.sh` исполняет всю батарею C8; поведенческий preflight отделяет `pending_materialization` от `invalid`; missing target/tool никогда не observed red
- [x] stdout/exit по контракту C8a; чекер ничего не пишет; bats green (был red); shellcheck clean
- [x] Сценарий §20 отрабатывает
- [x] Фаза generation|done реализована и гейтит C7 (REQ-056); каждый `invalid` несёт причину (I-172); сценарий §22 отрабатывает
<!-- /mb-task:9 -->
