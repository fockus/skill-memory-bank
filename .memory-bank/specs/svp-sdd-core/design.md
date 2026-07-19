# Design: svp-sdd-core

> Слайс S2 — ядро конвейера. Контракты и Eval-декларации (D-05); код — в work-фазе.
> Обязательное чтение: оба транскрипта (D-29).
> Ревизия 2 (2026-07-17): закрыты находки spec-ревью F-001…F-013 — грамматики Scope/Blocked-by
> зафиксированы здесь (S3/S5/S8 потребляют готовый контракт), red обязателен, добавлена батарея
> самопроверки генерации (C8).
> Ревизия 3 (2026-07-17): закрыты F-007 (candidate-артефакт разрешает парадокс «гейт до записи» —
> C3 получает `--tasks-file`, оркестратор пишет candidate и переносит его атомарно), F-009
> (исполняемый владелец exit-кодов spec-review — `mb-sdd-review-result.sh` + JSONL-append по
> umbrella NFR-005), F-010 (`mb-work-state.sh eval-red|eval-green` — eval пишется авторитетным
> writer'ом), R2-001 (C1 нормативно запрещает сужение Scope-грамматики потребителями), R2-002
> (preflight ≠ behavioral red), R2-003 (open questions вычищены); смысловой аудит — C6/C9
> (структурный Eval обязателен, waiver — исключение; один seam, D-17).
>
> **Namespace-предупреждение**: локальные `REQ-049…055` этого слайса — НЕ umbrella-REQ с теми же
> номерами (umbrella REQ-049…055 принадлежат S8/S1). Нумерация per-spec-local: traceability ключует
> по `(spec, req_id)`; ID выданы `scripts/mb-req-next-id.sh --spec svp-sdd-core`. Ссылки на
> umbrella-REQ в этом слайсе идут только через `covers_umbrella` во frontmatter requirements.md.

## Architecture

Три слоя:
1. **Prompt** — `commands/sdd.md` переписывается в конвейер: (0) контекст есть? нет → конвейер **сам запускает** discuss/self-interview (REQ-001), генерация только после появления транскрипта → (1) чтение транскрипта → (2) генерация requirements (stories+EARS) в staging `<bank>/tmp/sdd/<topic>/` → (3) design (§Contract: интерфейсы, seams по C9 — подтверждение с пользователем, Eval-декларации) в staging → (4) генерация **candidate** tasks.md v2 в `<bank>/tmp/sdd/<topic>/tasks.candidate.md` → (5) оценка бюджетов C3 по candidate → эскалация D-35 при превышении → (6) self-check DAG по candidate → (7) **батарея самопроверки C8** (`mb-sdd-self-check.sh --spec <staging-dir> --mb <bank>`, C8a) по **staged draft-триплету — accepted `specs/<topic>/tasks.md` ещё НЕ тронут** → (8) опц. spec_review C5 по staged draft → (9) **атомарный promotion** только после прохождения C8+review: `mb-sdd-candidate.sh publish` переносит candidate → `specs/<topic>/tasks.md` как **draft** (ещё НЕ accepted — C4a/C7); любой отказ гейта оставляет прежний accepted triple **byte-identical** → (10) переход draft→ready по C7 §Status state machine + отчёт. `commands/work.md` — врезка eval-first шага C6.
   > **Ревизия 5 (круг 4 ремедиация):** порядок шагов 7↔9 исправлен — C8 (и review) исполняются по staged draft ДО замены accepted `specs/<topic>/tasks.md`; publish/promotion — финальный гейтованный шаг (закрывает ревью-blocker «провал C8 уничтожает принятый tasks.md»). Step 0 стал исполняемым запуском интервью (REQ-001, был «остановись и вызови /mb discuss»). Все topic-based вызовы self-check несут `--mb <bank>` (global storage). Спорные места — консервативно к прозе; помечено судье.
2. **Скрипты** — `mb_work_items.py` (+v2-поля, дефолты, C2), `mb-spec-validate.sh` (+Eval-гейт REQ-007, +v2-поля, +waiver/seam/цикл-гейты, +проверки батареи), `mb-estimate-check.sh` (+режимы `--spec`/`--tasks-file`, C3), `mb-sdd-candidate.sh` (новый, candidate publish/discard, C4a), `mb-sdd-review-result.sh` (новый, C5), `mb-sdd-self-check.sh` (новый, батарея C8, C8a), `mb-work-state.sh` (+`eval-red`/`eval-green`, C6), `mb-sdd.sh` (byte-identical scaffold, C7).
3. **Шаблоны** — `references/templates.md`: tasks.md v2 блок, §Contract + seam-блок, структурный Eval, эскалационное меню D-35.

### Почему candidate, а не запись «на месте» (закрывает F-007)

REQ-010 требует остановиться **до записи** `specs/<topic>/tasks.md`, но бюджеты живут в `Budget:`
самих задач — оценивать нечего, пока tasks.md не сгенерирован. Парадокс снимается разделением
**сгенерированного** и **принятого** артефактов: шаг (4) пишет candidate в `<bank>/tmp/`, шаг (5)
оценивает **ровно его** (не существующий финальный файл), и только шаг (7) делает артефакт
принятым. Пока гейт не пройден, `specs/<topic>/tasks.md` не создаётся и не изменяется (REQ-053).

- `<bank>/tmp/sdd/<topic>/tasks.candidate.md` — путь обязателен именно в такой форме по двум
  причинам: (а) `mb_work_items.py::_derive_topic` для spec-источника возвращает `path.parent.name`
  (`scripts/mb_work_items.py:80-82`), поэтому каталог обязан называться `<topic>` — иначе парсер и
  батарея увидят чужой topic; (б) `<bank>/tmp/` лежит на той же ФС, что и `<bank>/specs/`, поэтому
  перенос — атомарный `rename(2)` (`mv`), а не копирование с окном полузаписи.
- Пишет candidate и переносит его **только оркестратор** (D-23); task-агенты его не трогают. Сам
  перенос/удаление выполняет детерминированный `scripts/mb-sdd-candidate.sh` (C4a) — не prompt-суждение.
- **Правило переноса (R3-003 — override сужен до spec-уровня):** перенос разрешён при `spec ∈ {ok,
  near}` **и** `task_over=none` **и** `stage_over=none`. `budget_override: user` во frontmatter
  `specs/<topic>/requirements.md` снимает **только** `spec=over` (вариант «г» D-35) и **только** при
  `task_over=none ∧ stage_over=none`. Если `task_over != none` **или** `stage_over != none`, candidate
  **всегда** блокируется и удаляется — override к hard-лимитам D-13 (задача ≤120k, этап ≤400k) не
  применяется НИКОГДА. `spec=near` — advisory (не блокирует). Обход возможен только для spec-рубежа
  ~1M; task/stage caps нерушимы.
- Любой другой исход: candidate удаляется, финальный файл остаётся byte-identical, отчёт —
  `sdd_status=blocked` (C7).

## Size gate before acceptance

Спека остаётся `draft`, пока каждая задача не несёт целочисленный `Budget ≤ 120000`, сумма каждого
Stage ≤ 400000, и spec-оценка равна сумме бюджетов задач. Диапазонная оценка не принимается.

## Interfaces

### C1. tasks.md v2 (грамматика полей)

В `<!-- mb-task:N -->`: `**Stage:** <n>` · `**Blocked-by:** <csv|none>` · `**Scope:** <glob-csv>` ·
`**Eval:** <command> — red: <условие>` (или `none — waiver: <reason>`, запрещено на gated) ·
`**Budget:** <tokens>`. Все опциональны для легаси (дефолты: stage=1, blocked-by=предыдущая задача,
scope=`["**"]`, eval=none, budget=120000).

- **Blocked-by-грамматика**: CSV; локальная ссылка — `<task-number>`; межспековая —
  `<topic>#<task-number>`; неизвестная ссылка валит spec-валидацию. Цикл в графе — валит
  spec-валидацию с печатью полного упорядоченного пути (REQ-052).
- **Scope-грамматика** (S3-C3 и S8 обязаны реализовать ровно эту семантику): CSV
  repo-relative **restricted glob**-паттернов (не полный POSIX-glob — закрывает R3-004). Разделитель
  пути всегда `/`; разрешены ТОЛЬКО литеральные символы пути, `*` внутри одного сегмента (ноль и
  более символов, никогда не пересекает `/`; допустим в любом сегменте и любой его части —
  `scripts/*.sh` валиден) и целый сегмент `**` (ноль и более сегментов). Абсолютные пути, `..`,
  пустые элементы и negation `!` запрещены. Пути диффа нормализуются относительно git root.
  Легаси-дефолт — `["**"]`. Scope task-агента не может включать `.memory-bank/**` (банк пишет
  только оркестратор, D-23).
- **Запрещённые метасимволы** (закрывает R3-004 — прежнее «любой POSIX glob» было недоопределено:
  алгоритм задавал только `*`/`**`, а `?`/`[]`/escape/brace оставались неклассифицированными):
  `?`, `[`, `]`, `{`, `}`, backslash-escape `\` и запятая ВНУТРИ элемента (`,` — только
  CSV-разделитель, без quoting/escaping) НЕ входят в грамматику. Любой из них в элементе → malformed:
  и парсер `mb_work_items.py` (T1), и `mb-spec-validate.sh` (T2) дают exit 2. Обязательные негативные
  контрактные кейсы (парсер T1 + валидатор T2, и синхронно потребители S3/S8): `src/?.py`,
  `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`, `src/a,b.py` — все пять отклоняются как malformed.
- **Ни сужать, ни расширять грамматику потребителям запрещено** (закрывает R2-001 + R3-004): элемент
  — repo-relative restricted glob по правилам выше и ровно он. Строка без глоб-метасимволов = точный
  путь; `dir/**` — частный случай рекурсивного префикса, а не единственная допустимая форма с
  глобом (R2-001). Потребитель реализует РОВНО эту грамматику: не сводит её к `dir/**` (R2-001) и не
  домысливает `?`/`[]`/brace-раскрытие сверх неё (R3-004). Дополнительных ограничений формы сверх
  C1 нет.
- **Пересечение двух Scope-списков** (потребляется S3-C1 для фронтир-дизъюнктности, закрывает
  SVP-PE-006): два списка конфликтуют ⟺ хотя бы одна пара паттернов имеет непустое пересечение
  языков. Пересечение считается **символьно, без обращения к файловой системе**: по сегментам —
  `**` поглощает ноль и более сегментов (DP по сегментам); внутри сегмента — DP по символам, где
  `*` соответствует любой подстроке без `/`, литералы пересекаются только при равенстве. Два
  списка дизъюнктны ⟺ ни одна пара не пересекается.
  Контрактная таблица (обязательные кейсы тестов потребителя): `src/**` vs `src/a.py` — конфликт;
  `src/*` vs `src/a.py` — конфликт; `src/*` vs `src/a/b.py` — дизъюнктны (`*` не пересекает `/`);
  `scripts/*.sh` vs `scripts/mb-x.sh` — конфликт; `scripts/*.sh` vs `scripts/mb-x.py` — дизъюнктны;
  `docs/**` vs `src/**` — дизъюнктны; `**` vs что угодно — конфликт.
- **Eval-грамматика и red-якорь** (делает C6/C8 исполнимыми, закрывает R2-002/R2-009 на уровне
  декларации): `**Eval:** <command> — red: <прозаическое условие>[; exit: <n>][; output~: <ERE>]`.
  - `exit:` — точный ожидаемый код возврата красного прогона; `output~:` — ERE, обязан совпасть с
    объединённым stdout+stderr красного прогона.
  - **`output~:` обязателен для задачи, покрывающей gated (SHALL/MUST) REQ; `exit:` — опционален и
    рекомендуется** (D-06: детерминизм требуется на gated, не везде). Для non-gated якоря
    опциональны; тогда C6 записывает `red_anchor: none` и red считается по `exit != 0`.
  - **Почему exit-якоря недостаточно (измерено на этом дереве 2026-07-17, а не предположено):**
    `bats <несуществующий файл>` → **exit 1** + `not ok 1 bats-gather-tests`, то есть тот же код,
    что и у настоящего провала теста. Exit-only якорь для bats-эвала принял бы «файла нет» за
    заявленный red — ровно дефект R2-002/R2-009, но уже внутри C6. `pytest <несуществующий файл>`
    → exit 4 (отличим от exit 1), но полагаться на различие по раннерам нельзя. ERE на выводе
    («что именно упало») отсекает оба случая, поэтому он и обязателен на gated.

    | Раннер | Missing target | Настоящий red | Exit-only якорь |
    |---|---|---|---|
    | `bats` | exit 1, `not ok 1 bats-gather-tests` | exit 1, `not ok N <имя теста>` | **обманывается** |
    | `pytest` | exit 4, `file or directory not found` | exit 1, `FAILED <nodeid>` | различает |
  - Красное условие описывает поведение **после материализации** eval-кода. «Файла теста нет» —
    не red-условие ни при каких обстоятельствах (D-05: eval-код пишется первым шагом задачи).
  - `red:`-проза обязательна всегда (читает человек); якоря — машинная часть того же условия.
  - Легаси-задачи без `**Eval:**` не затронуты (REQ-005/D-26).
- **Target-токены Eval-команды** (нужны C8-preflight): токены команды, содержащие `/` и не
  начинающиеся с `-`. `pytest tests/pytest/test_x.py` → один target; `bats a/x.bats && bats
  b/y.bats` → два. Правило детерминированно и не требует разбора семантики раннера.

### C2. `mb_work_items.py` JSON-расширение

Проекция pre-v2 ключей (`source/topic/item_no/kind/heading/body/role/agent/status/covers/dod_lines`)
на легаси-файлах остаётся **byte-identical** (контрактные фикстуры из всех текущих `specs/*/tasks.md`
до правок); полный JSON дополнительно содержит v2-ключи `stage`, `blocked_by[]`, `scope[]`,
`eval{cmd,red}`, `budget` с контрактными дефолтами C1.

### C3. `scripts/mb-estimate-check.sh` — режимы `--spec` и `--tasks-file`

Базовый скрипт создаёт S1 (`svp-interview-upgrade` C1: позиционный `<context-file>`, оценка по
`estimated_tokens.breakdown` шести категорий). S2 добавляет **два взаимоисключающих** режима поверх
него; позиционный режим S1 остаётся byte-identical.

```
bash scripts/mb-estimate-check.sh --spec <topic|spec-dir> [--mb <bank>]
bash scripts/mb-estimate-check.sh --tasks-file <path> [--mb <bank>]
```

- `--spec` — режим **принятой** спеки (verify/CI): topic резолвится в `<bank>/specs/<topic>/tasks.md`;
  явный spec-dir имеет приоритет.
- `--tasks-file` — режим **candidate** (гейт генерации, F-007): читается **ровно переданный файл**;
  триплет НЕ резолвится, существующий `specs/<topic>/tasks.md` не открывается и не влияет на вывод
  (тест «stale final игнорируется» обязателен). Отсутствующий файл → exit 2.
- `--spec` и `--tasks-file` вместе, как и любой из них вместе с позиционным `<context-file>` S1, —
  usage-ошибка (exit 2). Ровно один источник.
- **Флаги режимо-специфичны**: `--mb` применяется только к режимам `--spec`/`--tasks-file`;
  позиционный context-режим S1 принимает только `[--spec-budget]`. Флаг, не поддерживаемый активным
  режимом (напр. `--mb` в context-режиме, `--spec-budget` в spec/tasks-file), — usage-ошибка (exit 2).
- Читаются только явно записанные `Budget`; легаси-задачи без поля исключаются из сумм и
  перечисляются как `legacy_missing=<ids>` с одним stderr-warning.
- Целочисленные поля (`Budget`, frontmatter `total`/`stages`) парсятся **строгим full-match**:
  значение с любым не-цифровым хвостом (напр. `100junk`) — malformed (exit 2), а не молчаливое
  усечение до `100`.
- stdout (оба режима идентичны), по одной key=value строке: `task.<id>=<tokens>`,
  `stage.<id>=<tokens>`, `spec.total=<tokens>`, `task_over=<csv|none>`, `stage_over=<csv|none>`,
  `spec=ok|near|over`, `legacy_missing=<csv|none>`.
- `ok`: total < 900000; `near`: 900000–1000000 (advisory-эскалация); `over`: > 1000000 (D-35 hard stop).
- exit 0 = ok/near без task/stage overflow; 1 = любой task/stage/spec overflow; 2 = usage,
  неразрешимая спека/файл или malformed поле.
- **Скрипт — чистый чекер**: он не пишет, не переносит и не удаляет артефакты и не читает
  `budget_override`. Решение о переносе принимает оркестратор (§Architecture).

**Frontmatter-схема tasks.md (v2, фиксируется здесь):**

```yaml
---
estimated_tokens:
  total: <int>
  stages:
    "<stage-id>": <int>
---
```

- `total` обязан равняться сумме `Budget` всех задач с явным полем; каждый ключ `stages` — сумме
  `Budget` задач своего `Stage:`. Расхождение frontmatter ↔ вычисленных сумм → exit 1 (не 2:
  это содержательный overflow-класс ошибки, а не поломка формата).
- Агрегация `stage.<id>` идёт по **фактическому** `Stage:`-ID, **включая `Stage: 0`**: нулевой
  стейдж — полноценный стейдж, его сумма подчиняется D-13 stage-cap (≤400000) и попадает в
  `stage_over` при превышении; он не обходит проверку и не сворачивается в другой стейдж.
- Ключ `estimated_tokens` в tasks.md **не тот же**, что `estimated_tokens` в context-файле S1-C1:
  там `total` + `breakdown` шести категорий рубрики интервью, здесь `total` + `stages` из фактических
  `Budget`. Один скрипт, две схемы, разные входы — реализатор не унифицирует их.
- Frontmatter tasks.md — преамбула до первого `<!-- mb-task:N -->`, поэтому `mb_work_items.py`
  игнорирует её (`parts[0]` отбрасывается, `scripts/mb_work_items.py:219-224`): проекция pre-v2
  ключей C2 остаётся byte-identical.

### C4. Эскалационное меню D-35 (prompt-контракт) + реестр декомпозиции

4 варианта: разбить сейчас / MVP-урезка → реестр / umbrella+JIT / `budget_override: user` во
frontmatter; auto → self-interview слайсы + assumption-запись.

- До S4 единственный writer реестра — оркестратор через
  `scripts/mb-idea.sh "[SPEC:<group>] <child-topic>"` в `<bank>/backlog.md ## Ideas`;
  child-агенты возвращают только structured proposals.
- Каждый созданный child-триплет получает `group: <group>` и `parent_context: context/<umbrella>.md`
  во frontmatter.
- После S4 те же `[SPEC:<group>]`-записи пишутся типизированными сразу (writer S4-C4, call-site
  S2 byte-identical); мигратор S4 отвечает только за записи, созданные до апгрейда writer'а. S2 не
  пишет альтернативный registry-файл.
- Частичный отказ после создания части children: созданные остаются зарегистрированными со
  `status: draft`, незаписанные перечисляются в громком отчёте.

### C4a. `scripts/mb-sdd-candidate.sh` — детерминированный candidate lifecycle (закрывает R3-002/R3-003)

Механический перенос/удаление candidate — не prompt-суждение: pytest над `commands/sdd.md` проверяет
только ТЕКСТ, но не докажет атомарный `mv`, byte-identity финала и корректный разбор вердикта на
файловой системе (R3-002). Выносим лайфцикл в детерминированный helper; `commands/sdd.md` оставляет
за собой только оркестрацию.

```
bash scripts/mb-sdd-candidate.sh publish --topic <topic> --candidate <path> \
     --estimate-file <path> [--override user] [--mb <bank>]
bash scripts/mb-sdd-candidate.sh discard --topic <topic> --candidate <path> [--mb <bank>]
```

- `--candidate` обязан быть каноническим `<bank>/tmp/sdd/<topic>/tasks.candidate.md` (иначе usage,
  exit 2); `--estimate-file` — файл со stdout вердикта C3 (`mb-estimate-check.sh --tasks-file`),
  который helper разбирает как key=value (`spec=`, `task_over=`, `stage_over=`).
- **Правило publish (R3-003 — override сужен):**
  - `task_over != none` **или** `stage_over != none` → **всегда** `candidate=blocked reason=task_overflow`
    (или `stage_overflow`), candidate удаляется; `--override` игнорируется — hard-лимиты D-13 нерушимы.
  - иначе `spec ∈ {ok, near}` → publish разрешён; `spec=over` → publish разрешён **только** при
    `--override user`; без него → `candidate=blocked reason=spec_overflow`, candidate удаляется.
  - publish = same-filesystem `rename(2)` candidate → `<bank>/specs/<topic>/tasks.md`.
- **Инвариант byte-identity:** любой отказ (blocked/malformed/usage) оставляет существующий
  `specs/<topic>/tasks.md` **byte-identical**; publish запрещён при malformed вердикте C3
  (незнакомый ключ, отсутствие `spec=`) — exit 2.
- `discard` — удаляет candidate, финальный файл не трогает.
- **stdout**: ровно одна строка `candidate=published|discarded|blocked reason=<code>`
  (`reason=none` для published/discarded). **Exit**: 0 — published/discarded; 1 — domain block
  (spec/task/stage overflow); 2 — usage / malformed вердикт / неканонический путь.
- Пишет/переносит только оркестратор через этот helper (D-23); статус `requirements.md` он не меняет
  — publish кладёт триплет как **draft** (см. C7 §Status state machine).

### C5. spec-review: config + исполняемый владелец вердикта

**Разделение (закрывает F-009):** `commands/sdd.md` владеет **диспатчем модели** (только промпт
умеет вызвать агента); детерминированный helper владеет **валидацией, записью и exit-кодами** —
чтобы «exit 0/1/2» имели исполнителя, а не остались прозой в design (NFR-002).

**Config** в `references/pipeline.default.yaml`:

```yaml
sdd:
  spec_review: {enabled: false, agent: mb-reviewer, model: <exact>, thinking: medium}
```

- Записывается **инлайн-мапой** (не вложенным блоком) — это обязательное требование, а не стиль:
  `mb-pipeline-validate.sh` читает `sdd` через `parse_simple_mapping` (`scripts/mb-pipeline-validate.sh:320`),
  который берёт только строки с `indent == 2` и пропускает значение через `parse_value` →
  `parse_inline_map` (`scripts/mb-pipeline-validate.sh:177-195`). Инлайн-форма парсится **идентично**
  PyYAML-путём и PyYAML-optional fallback'ом; вложенный блок в fallback'е дал бы `spec_review: None`.
  Проверено на текущем коде: обе ветки дают `{'enabled': False, 'agent': 'mb-reviewer', 'model': …,
  'thinking': 'medium'}`.
- Следствие грамматики `parse_inline_map` (split по `,` затем по первому `:`): значения не должны
  содержать `,`; `model`/`agent` — единый токен. Валидатор обязан отклонить значение с запятой.
- Валидация в `mb-pipeline-validate.sh` (рядом с существующими `sdd.*`-проверками, строки 606-627):
  `spec_review` отсутствует → ок (дефолт off); присутствует → `enabled` boolean; при `enabled: true`
  — `agent`/`model` непустые строки, `thinking ∈ {low, medium, high}`.

**Helper** `scripts/mb-sdd-review-result.sh` — два подрежима (одна форма не годится: `same_model`
обязан решаться ДО диспатча, когда результата ревью ещё не существует):

```
bash scripts/mb-sdd-review-result.sh check  --generator-model <exact> --reviewer-model <exact> \
     --reviewer-agent <exact> --thinking <low|medium|high> [--mb <bank>]
bash scripts/mb-sdd-review-result.sh record --topic <topic> --attempt <n> \
     --generator-model <exact> --reviewer-model <exact> --reviewer-agent <exact> \
     --thinking <low|medium|high> --input <path|-> [--mb <bank>]
```

- `check` — вызывается перед диспатчем. Равные `--generator-model` и `--reviewer-model` → stderr
  `same_model`, exit 2; диспатч запрещён. Иначе exit 0.
- `record` — принимает **сырой JSON ревьюера** на `--input` (`-` = stdin); `commands/sdd.md` передаёт
  фактически резолвленные model ID, а не имена из конфига.
- Схема вердикта (валидируется строго; лишние поля — malformed):
  `{status: "reviewed"|"skipped", verdict: "APPROVED"|"CHANGES_REQUESTED"|null,
  reviewer: {agent, model, thinking}, issues: [{severity: "critical"|"major"|"minor"|"nit",
  category, req: string|null, description}], reason: string|null}`.
- Запись — **append-only JSONL** `<bank>/tmp/spec-review/<topic>.jsonl` (umbrella NFR-005: структурный
  лог в `<bank>/tmp/`, как pivot-log; было `.json` — перезапись стирала историю попыток). Одна
  компактная строка на попытку; helper добавляет обязательные `ts` (UTC ISO-8601) и `attempt`.
  История не перезаписывается; **последняя валидная строка — текущий вердикт**.
- Exit: 0 = APPROVED; 1 = CHANGES_REQUESTED; 2 = same_model / unavailable / malformed.
- `SKIPPED` (недоступная модель) — не молчание: пишется отдельной JSONL-строкой
  (`status: "skipped"`, `reason` непустой), exit 2, громкий отчёт.
- Пишет файл только оркестратор через этот helper (D-23); task-агенты не пишут.
- Интерактив: пропущенное ревью требует решения человека; auto: пропуск и решение оркестратора
  записываются до принятия спеки.

### C6. Eval-first шаг в `/mb work` (врезка; red ОБЯЗАТЕЛЕН)

- До implement: материализовать eval-код (D-05: это первый шаг задачи) и запустить точную
  Eval-команду.
- **Авторитетный writer состояния — существующий `scripts/mb-work-state.sh`** (закрывает F-010:
  ревизия 2 требовала записи в «текущий work-state», но у него нет ни поля `eval`, ни субкоманды —
  сегодня это только init/new-run-id/step/cycle/status/list/done/clear, `scripts/mb-work-state.sh:7-15`;
  `step` умеет лишь добавить строку в `steps[]`, `:215-237`). Прямое редактирование JSON запрещено —
  расширяем единственный writer:

```
bash scripts/mb-work-state.sh eval-red   --cmd-file <path> --output-re <ERE> \
     [--expected-exit <n>] [--run-id ID] [--mb <bank>]
bash scripts/mb-work-state.sh eval-green --cmd-file <path> [--run-id ID] [--mb <bank>]
```

- **Единственный исполнитель и судья Eval-команды — сам helper (закрывает F-010 полностью, не
  декларацией):** ревизия 3 приняла у caller-а уже вычисленные `--exit`/`--observed`/`--match` —
  вызов `eval-red --observed true --match true` или `eval-green --exit 0` мог записать успех **без
  доказательства**. Эти флаги удалены. Теперь red/green выводятся из НАБЛЮДАЕМОГО состояния,
  недоступного подмене флагом:
  - Обе субкоманды **сами** запускают byte-identical содержимое `--cmd-file` из git root
    (`bash <cmd-file>` в поддиректории repo root, окружение как в verify) и **сами** захватывают
    объединённый stdout+stderr и фактический exit. Caller не сообщает ни exit, ни output, ни verdict.
  - `eval-red` компилирует `--output-re` (ERE), запускает команду, вычисляет
    `red_match = (фактический combined output совпал с ERE) ∧ (--expected-exit не задан ИЛИ факт.exit
    == --expected-exit)` **внутри helper**. Возвращает `0` только когда все объявленные якоря совпали
    (наблюдён заявленный red); mismatch / foreign failure / уже-зелёная команда → exit 1;
    usage / битый state / некомпилируемый ERE → exit 2.
  - `eval-green` **сам** запускает сохранённую (byte-identical `--cmd-file`) команду и возвращает `0`
    только при фактическом `exit 0`; иначе exit 1. Дрейф `--cmd-file` относительно сохранённого
    `cmd` → exit 1; usage / битый state → exit 2 (через существующий `require_valid_state`,
    `scripts/mb-work-state.sh:87-96`).
  - Подставить `true`/`0` **через CLI** невозможно по построению — верификационные тесты обязаны это
    доказать (вызов с любыми аргументами не даёт green/red-observed, если фактический прогон их не
    подтверждает). Это утверждение ограничено CLI-поверхностью и **не** распространяется на прямую
    правку state-файла — см. модель доверия ниже.

**Модель доверия eval-пруфа (AGR-026).** Прежняя формулировка «verdict нельзя подделать, потому что
`sig` — keyed hash» была сильнее того, что реализация способна дать: ключ подписи лежит в самом
чекауте (`scripts/mb_work_eval_proof.py`), поэтому любой агент, способный отредактировать
`.work-state.json`, способен прочитать ключ и пересчитать подпись. Спека больше не заявляет
tamper-proof.

- **Целевая модель — подпись у оркестратора.** Ключ держит оркестрирующая сессия, а не сабагент.
  Сабагент исполняет eval-команду и возвращает `rc` + output; оркестратор проверяет результат,
  подписывает своим ключом и записывает proof. Публичный литерал `MBW_EVAL_PROOF_KEY` как «подпись»
  упраздняется. Принятая цена — раунд-трип на каждой задаче.
- **Честная деградация там, где оркестратора нет** (headless, `/mb drive`): гейт переходит в
  **checksum-режим** — целостность против случайной/ручной правки, но НЕ против намеренной подделки.
  Режим обязан быть явно помечен и в state-файле, и в пользовательском выводе; он не имеет права
  делать вид, что защищает. Прецедент — AGR-013 (honest degradation).
- **Текущая реализация — именно checksum-режим.** `sig` покрывает `cmd_hash`, red-поля, `green_exit`
  и объявленные якоря (`output_re`, `expected_exit`), поэтому рассогласованная ручная правка
  обнаруживается; против противника с доступом к чекауту он не защищает. Рукопожатие с оркестратором
  в этой ревизии НЕ реализуется — только текст спеки приведён в соответствие.
- `eval-red` атомарно создаёт в state-файле объект `eval: {cmd, red_exit, red_observed, red_match,
  green_exit}`, где `red_exit` — **фактический захваченный helper-ом exit** (не caller-ов),
  `red_observed = red_match`, `green_exit: null`.
- Команда передаётся **файлом**, а не строкой: только так byte-identity (`eval-green` vs `eval-red`)
  проверяема без потерь на shell-квотировании, и helper исполняет ровно то, что зафиксировано.
- Оба режима используют существующий singleton/per-run resolver (`state_path` + `mbw_state_slot`,
  `scripts/mb-work-state.sh:68-73`) и парсят свои флаги сами — по образцу `init`, который «has extra
  flags, so it parses on its own» (`scripts/mb-work-state.sh:98-103`). `parse_common_flags` НЕ
  меняется; вывод и exit-коды старых субкоманд остаются byte-identical (регрессионный тест
  обязателен).
- Схема state-файла в шапке скрипта дополняется ключом `eval` (документация — часть задачи).
- **`red_match` считает helper фактическим прогоном** (закрывает R2-002 на уровне исполнения): по
  якорям C1. Если объявлен только `output~:` (`--output-re`) — проверяется он один; `--expected-exit`
  добавляет проверку кода. Для gated-задачи `output~:` обязателен (REQ-055), поэтому посторонний
  сбой даёт `red_match=false` **механически**: `pytest` на отсутствующем файле — exit 4 вместо
  заявленного 1; `bats` на отсутствующем файле — exit 1 (совпадает по коду!), но фактический вывод
  `not ok 1 bats-gather-tests` не совпадает с ERE заявленного теста, поэтому red не наблюдён.
- `red_observed=true` только при `red_match=true`. Отсутствующий или несовпавший red = **FAIL**,
  блокирует implement; продолжить может только явный override пользователя, и он логируется.
- Verify вызывает `eval-green` — helper перезапускает байт-идентичную команду и требует фактический
  `green_exit=0`.

**Структурный Eval и waiver (REQ-049/050, аудит D-25-STRUCTURAL-EVAL).** D-25 состоит из двух
половин, и вторая (запрет `Eval: none` на gated) не заменяет первую:

- Задача без runtime-поверхности (доки/конфиги) **обязана** нести структурный Eval — наблюдаемо
  красный до реализации: наличие файла, наличие секции, exit линтера. Это норма, а не исключение:
  «file exists» красен ровно до создания файла, «section present» — до вставки секции, линтер — до
  правки. Отговорка «структурный Eval невозможно сделать красным» почти всегда ложна.
- `**Eval:** none — waiver: <reason>` — **явное исключение**, а не обычная замена: требует непустой
  причины, объясняющей, почему ни файловая, ни секционная, ни линтерная проверка не может быть
  красной; допустим только для non-gated задач; на gated — всегда fail (REQ-007/050).
- Каждый принятый waiver перечисляется в выводе валидатора — waiver'ы видимы, а не растворяются
  в зелёном прогоне.

### C7. `/mb sdd` и `scripts/mb-sdd.sh` (граница prompt/script)

- `commands/sdd.md` владеет полным конвейером генерации и пишет финальный триплет только после
  гейтов context/transcript/budget.
- Существующий `bash scripts/mb-sdd.sh <topic> [--force] [mb_path]` остаётся byte-identical и
  scaffold-only для прямых вызовов.
- `--scaffold-only` — алиас, выбирающий тот же существующий writer из `/mb sdd`; вывод и
  exit-коды скрипта не меняются.
- `/mb sdd` без `--scaffold-only` НЕ вызывает scaffold-writer до прохождения D-35.
- Отчёт команды: успех перечисляет три пути; отменённая/эскалированная генерация не пишет
  tasks.md, удаляет candidate и сообщает `sdd_status=blocked`; malformed контекст —
  `sdd_status=invalid`. Отчёт дополнительно печатает `eval.<task-id>=<eval_status>` по C8.

**Status state machine (REQ-012, закрывает R3-006).** «Публикация в `specs/`» ≠ «acceptance»:
шаг (7) кладёт триплет как **draft**, а не как принятый. Ни helper, ни оркестратор не называют
draft-файл accepted, пока он не прошёл C8 и разрешение ревью.

- Все новые/перегенерированные артефакты публикуются с `requirements.md: status: draft`.
- `status` меняется на `ready` **только** после `mb-sdd-self-check.sh` exit 0 (C8=pass) **и** одного
  из: ревью выключено (`sdd.spec_review.enabled=false`); ревью вернуло **APPROVED**
  (`mb-sdd-review-result.sh record` exit 0); либо явного решения человека/оркестратора принять
  спеку при **SKIPPED** или при отклонённых issue — это решение пишется отдельной JSONL-строкой
  (C5) до перехода в ready.
- C8-провал (`mb-sdd-self-check.sh` exit≠0) **или** **CHANGES_REQUESTED** (record exit 1) оставляют
  `status: draft`. Простой **SKIPPED** без явного решения — тоже draft (молча ready не становится).
- Правки после CHANGES_REQUESTED проходят полный цикл заново: новый candidate → C3 (гейт) →
  publish draft → C8 → ревью. Никаких «частичных» правок в принятом файле.
- Оркестратор/helper никогда не выводят «accepted» из одного лишь факта наличия файла в `specs/`.
- T7 проверяет переходы: `disabled → ready`, `APPROVED → ready`, `CHANGES_REQUESTED → draft`,
  `SKIPPED без решения → draft`.

### C8. Батарея самопроверки генерации (REQ-015)

После публикации триплета (шаг 7) и до spec_review конвейер обязан прогнать и пройти **на
опубликованном (draft) триплете** батарею C8.1–C8.5. Вся батарея исполняется детерминированным
helper-ом `mb-sdd-self-check.sh` (C8a, Task 9) — не prompt-суждением; `commands/sdd.md` только
вызывает helper и по его вердикту решает draft→ready (C7 §Status state machine):
1. `mb-spec-validate.sh <topic>` (+`--require-scenarios` при gated REQ);
2. паритет сценариев: `mb-scenario-extract.py` извлекает ровно столько блоков, сколько
   `### Scenario:`-заголовков; имена сценариев ASCII (test_id-слаги);
3. парс задач: `mb_work_items.py` парсит каждый блок, каждый резолвленный `agent` существует в
   таблице ролей (bare `Role:`);
4. **Eval preflight** (переписан — закрывает R2-002/R2-009; исполнитель — helper C8a, не оркестратор):
   - *Структурная часть (код, `mb-spec-validate.sh`)*: каждая `**Eval:**`-декларация разбирается по
     грамматике C1 — команда непуста, `red:`-проза непуста, target-токены являются repo-relative
     путями, `output~:`-ERE компилируется, у gated-задачи объявлен `output~:`-якорь (REQ-055).
   - *Поведенческая часть (детерминированный helper `mb-sdd-self-check.sh`, C8a)*: для каждой задачи
     helper резолвит target-токены. **Все target существуют** → helper исполняет команду и обязан
     наблюдать заявленный red-якорь → `eval_status: ready`. Команда **уже зелёная** или red не совпал
     с якорем → `eval_status: invalid`, ready заблокирован (фальшивый или несуществующий контракт).
     **Хотя бы один target отсутствует** → `eval_status: pending_materialization`; отсутствие target
     или самого раннера-инструмента **не считается observed red** (missing tool → `invalid` с
     reason `tool_unavailable`, но никогда не `ready` и не red).
   - Почему так: D-05 прямо откладывает написание eval-кода до первого шага `/mb work`
     (`context/sdd-vision-pipeline.md:40`), поэтому на генерации красных прогонов в общем случае
     физически нет — требовать их значило бы либо нарушить D-05, либо принимать «file not found»
     за доказательство (ровно тот дефект, который ревью нашло у S8, R2-009).
   - Helper печатает `eval.<task-id>=ready|pending_materialization|invalid` по каждой задаче.
   - **Фактический behavioral red остаётся обязательным гейтом C6** после материализации в
     `/mb work` — preflight его не заменяет и не ослабляет.
5. межспековые ссылки `Blocked-by` резолвятся в существующие спеки/задачи; цикл в графе —
   провал (REQ-052).
6. **Eval byte-identity design↔tasks (закрывает CPR-D)**: каждая `**Eval:**`-строка в
   `design.md` §Eval declarations обязана быть **byte-identical** `**Eval:**`-строке одноимённой
   задачи в `tasks.md`; расхождение (в т.ч. `\|` в якоре против `|`) → провал. Причина гейта:
   пайп-таблица в design вынуждала `\|`, а `\|` в POSIX ERE — литерал, из-за чего якорь дизайна
   расходился с исполняемым якорем задачи.

Любой провал (включая хотя бы один `invalid`) оставляет `status: draft`. `pending_materialization`
провалом не является — это честное «эвал ещё не материализован», а не «эвал красный».
Промпт-версия батареи уже в `commands/sdd.md` (§ Generation self-check); этот слайс переводит её в код.

### C8a. `scripts/mb-sdd-self-check.sh` — детерминированный исполнитель батареи (REQ-054, закрывает R3-001)

Поведенческий Eval-preflight (REQ-054) в ревизии 3 существовал только как prompt-текст в T4 — без
production seam, поэтому REQ-054 нельзя было ни исполнить детерминированно, ни оттрассировать
(формально висел на T8, который реализует work-time state, а не generation-preflight). Выносим всю
батарею C8 в helper; REQ-054 трассируется на его задачу (Task 9), T4 его **вызывает**.

```
bash scripts/mb-sdd-self-check.sh --spec <topic|spec-dir> [--mb <bank>]
```

- Исполняет C8.1–C8.5 над указанным триплетом; для каждой задачи вычисляет `eval_status` по
  поведенческому правилу выше (target-резолюция + фактический прогон существующих target; missing
  target → `pending_materialization`; уже-зелёная / несовпавший red / missing tool → `invalid`).
- **stdout**: первой строкой `self_check=ready|invalid`, затем по строке
  `eval.<task-id>=ready|pending_materialization|invalid` в порядке возрастания task-id.
- **Exit**: `0` — нет ни одного `invalid` и структурные проверки C8.1–C8.3/C8.5 прошли (ready);
  `1` — хотя бы один structural/behavioral violation (в т.ч. `eval.*=invalid`, цикл Blocked-by,
  провал spec-validate/паритета/роль-резолюции); `2` — usage / неразрешимый topic / malformed вход.
- `pending_materialization` **не** влияет на exit (это не провал) — self_check остаётся `ready`, если
  прочих invalid нет.
- Пишет только stdout/stderr (чекер, не writer): триплет и банк не изменяет; статус `requirements.md`
  меняет оркестратор по C7 §Status state machine, опираясь на exit helper-а.

### C9. §Contract seam-блок (REQ-051, D-17 / umbrella REQ-009)

Чтобы «один seam предпочтителен» проверялось кодом, а не на глаз, §Contract несёт машинно-читаемый
блок:

```markdown
**Seams:**
- <seam-1>
**Seam rationale:** <почему больше одного seam> ← обязателен ТОЛЬКО при ≥2 элементах
```

- Правило генерации (D-17): существующие seams > новые; seam максимально высокий; **по умолчанию
  ровно один**. Несколько допустимы, но требуют краткого rationale — согласовано с umbrella REQ-009
  («shall prefer a single seam — recording a brief rationale in `design.md` when more than one seam
  is agreed»).
- Детерминированный гейт (`mb-spec-validate.sh`): `≥2` элемента в `**Seams:**` без непустой строки
  `**Seam rationale:**` → violation с указанием количества seams. Один seam → rationale не требуется.
  Блок отсутствует → violation только для спек нового конвейера (легаси-спеки без §Contract
  не затрагиваются, D-26).
- Содержательное качество seam (тот ли он, максимально ли высокий) кодом не проверяется — это
  подтверждение пользователем на шаге (3) и предмет spec-review C5. Граница названа честно.

## Decisions

S2-A-01…07 + D-02/03/05/06/13/17/25/26/29/30/35 — в context-файлах. Грамматики Scope и Blocked-by
зафиксированы в C1 (ревизия 2, S3/S5/S8 потребляют без ревизии); ревизия 3 добавила туда
red-якоря Eval, семантику пересечения Scope-списков (для фронтира S3) и нормативный запрет сужать
грамматику на стороне потребителя.

**Namespace локальных REQ**: `REQ-049…055` — per-spec-local ID этого слайса, выданные
`scripts/mb-req-next-id.sh --spec svp-sdd-core` (скрипт считает максимум по `covers_umbrella`-ссылкам
и потому продолжил с 049). Они **не** совпадают по смыслу с umbrella REQ-049…055 (те принадлежат
S8/S1); traceability ключует по `(spec, req_id)`, как и предупреждает `mb-spec-validate.sh:26-31`.

## Eval declarations (red → green в work-фазе)

Red-условия описывают поведение **после материализации** теста (D-05: eval-код — первый шаг задачи
в `/mb work`). «Файла теста нет» нигде не заявляется как red: по C6 посторонний сбой = FAIL, а по
C8 отсутствующий target = `pending_materialization`, а не observed red. Каждая строка несёт
машинный якорь (C1), поэтому `red_match` считает код, а не человек.

**Byte-identity с `tasks.md` (закрывает CPR-D).** Строки `**Eval:**` ниже — **byte-identical**
соответствующим `**Eval:**`-строкам одноимённых задач в `tasks.md`; единственный источник истины
якоря — задача. Список НАМЕРЕННО не оформлен markdown-таблицей: пайп-таблица вынудила бы экранировать
`|` как `\|`, а `\|` в POSIX ERE матчит **литерал** `|`, а не альтернативу — такой `output~:`-якорь
никогда не сматчил бы настоящий провал (ровно расхождение, найденное CPR-D). Байт-идентичность
`design.md ↔ tasks.md` по каждому task проверяет батарея C8 (структурный чек в `mb-spec-validate.sh`,
исполняется `mb-sdd-self-check.sh`).

- **T1** — парсер tasks.md v2:
  **Eval:** `pytest tests/pytest/test_work_items_v2.py` — red: парсер не расширен, v2-ключей нет в JSON; exit: 1; output~: `FAILED tests/pytest/test_work_items_v2\.py::test_v2_fields_parsed`
- **T2** — валидатор (Eval/waiver/seam/цикл/restricted-glob/батарея):
  **Eval:** `bats tests/bats/test_mb_spec_validate_v2.bats` — red: валидатор не расширен, гейты не срабатывают и негативные фикстуры проходят «зелёными»; exit: 1; output~: `not ok [0-9]+ .*(eval_none_gated|blocked_by_cycle|seam_rationale)`
- **T3** — бюджет-оценка + candidate-режим:
  **Eval:** `bats tests/bats/test_mb_estimate_check_spec.bats` — red: режимов `--spec`/`--tasks-file` нет, скрипт трактует флаг как context-файл и отвечает usage-ошибкой; exit: 1; output~: `not ok [0-9]+ .*tasks_file`
- **T4** — конвейер генерации:
  **Eval:** `pytest tests/pytest/test_sdd_command_contract_v2.py` — red: конвейер не переписан, `commands/sdd.md` всё ещё содержит «does not auto-generate» и не содержит фаз; exit: 1; output~: `FAILED tests/pytest/test_sdd_command_contract_v2\.py::test_pipeline_phases_ordered`
- **T5** — candidate-lifecycle + эскалация D-35 (bats — основной, pytest — дополнительный в Testing):
  **Eval:** `bats tests/bats/test_mb_sdd_candidate.bats` — red: `scripts/mb-sdd-candidate.sh` не существует, конвейер не переписан; exit: 1; output~: `not ok [0-9]+ candidate_publish: `
- **T6** — scaffold-совместимость и шаблоны v2:
  **Eval:** `pytest tests/pytest/test_sdd_scaffold_compat.py` — red: совместимость и шаблоны не оформлены, `references/templates.md` не содержит v2-блока; exit: 1; output~: `FAILED tests/pytest/test_sdd_scaffold_compat\.py::test_templates_carry_v2_block`
- **T7** — spec_review config + владелец вердикта:
  **Eval:** `bats tests/bats/test_sdd_spec_review.bats` — red: `scripts/mb-sdd-review-result.sh` не существует, конфига и шага нет; exit: 1; output~: `not ok [0-9]+ .*(same_model|jsonl_append)`
- **T8** — eval-first врезка (self-executing helper):
  **Eval:** `bats tests/bats/test_work_eval_first.bats` — red: `mb-work-state.sh` не знает `eval-red`/`eval-green` (отвечает usage, exit 2), врезки в work.md нет; exit: 1; output~: `not ok [0-9]+ .*eval_red`
- **T9** — детерминированный исполнитель батареи C8a:
  **Eval:** `bats tests/bats/test_mb_sdd_self_check.bats` — red: `scripts/mb-sdd-self-check.sh` не существует (отвечает `command not found`/usage), preflight-логики нет; exit: 1; output~: `not ok [0-9]+ self_check: `

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Ломка парсера на боевых спеках | M | H | контрактные pytest-фикстуры из ВСЕХ текущих specs/ ДО правок (T1 первым); проекционная byte-identity C2 |
| Конвейер-промт слишком длинный (токены) | M | M | шаблоны/меню в templates.md, sdd.md держит только алгоритм |
| Батарея C8 замедляет генерацию | L | L | все проверки локальные и секундные; исполняются только эвалы с существующими target |
| spec_review плодит бесконечные правки | L | M | судья-человек/оркестратор терминирует (D-30), цикл один по умолчанию |
| T2 упирается в потолок бюджета (120k = cap): десять детерминированных проверок в одном скрипте | M | M | скелет `mb-spec-validate.sh` (разбор аргументов, сбор violations, `--json`) уже существует — правка инкрементальная (~15-25 строк bash + bats-кейс на проверку); при фактическом переполнении срабатывает дет-гард бюджета задачи (D-16/S5) и ADaPT-развилка — ровно тот сценарий, ради которого гарды и вводятся |
| Candidate осиротел (сессия умерла между записью и переносом) | L | L | `<bank>/tmp/sdd/<topic>/` — не принятый артефакт: следующий прогон перезаписывает candidate; принятый tasks.md не затронут по построению (REQ-053) |
| Инлайн-мапа `spec_review` ломается на значении с запятой | L | M | валидатор отклоняет `,` в значениях (C5); ограничение — следствие реального `parse_inline_map`, а не вкусовщина |

## NFR

- **NFR-004**: изменённые shell-входы работают под Bash 3.2 (macOS) и текущим Bash (Linux);
  пути с пробелами и не-C локаль остаются валидными.

## Cross-slice requests (правки в чужих спеках — не делаются здесь)

| # | Адресат | Запрос | Основание |
|---|---|---|---|
| X-01 | `svp-parallel-engine` (S3) | Убрать сужение формы Scope-элемента в C3 («либо точный файл, либо `dir/**`», `design.md:106-109`) — потреблять грамматику C1 как есть; заменить термин «POSIX glob» на **restricted glob** синхронно с C1 (только литералы + `*` в сегменте + сегмент `**`; `?`/`[]`/`{}`/escape/запятая-в-элементе → malformed exit 2); добавить контрактную таблицу пересечений C1 **и** пять негативных malformed-кейсов (`src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`, `src/a,b.py`) в Testing T1/T3 | R2-001 + R3-004 (моё ревью) + SVP-PE-006 |
| X-02 | `sdd-vision-pipeline` (umbrella) | Interface 5: `<bank>/tmp/spec-review/<topic>.json` → `.jsonl` (append-only), иначе конфликт с NFR-005 | F-009 |
| X-03 | `sdd-vision-pipeline` (umbrella) | Interface 1: дополнить грамматику tasks.md v2 red-якорями Eval (`output~:` обязателен на gated, `exit:` опционален) | F-009/R2-002, S8-R2-009 |
| X-04 | `sdd-vision-pipeline` (umbrella) | Покрытие umbrella REQ-022 (цикл `blocked_by` валит **spec-валидацию**) теперь формально со-владеется S2: REQ-022 **добавлен** в `covers_umbrella` этого слайса и ledger (R3-005) — spec-time рубеж закрыт локальным REQ-052; S3/Task 7 сохраняют runtime fail-fast фронтира как второй рубеж без изменений. Запрос к umbrella: добавить `REQ-022` в Covers umbrella Task 4 и в строку S2 таблицы umbrella design (два делегата REQ-022 — S2 spec-time + S3 runtime) | R3-005, SVP-PE-001 |
| X-05 | S1/S3/S5/S6/S8 | Дополнить `**Eval:**`-строки своих tasks.md якорями C1 (`output~:` на каждой gated-задаче). Особенно важно для bats-эвалов: измерено, что `bats` на отсутствующем файле возвращает exit 1 — тот же код, что и настоящий провал, поэтому exit-only якорь принял бы «файла нет» за red. Легаси-спеки вне группы не затронуты (D-26) | R2-002, R2-009 |
| X-06 | `svp-contract-test-loop` (S8) | Если S8 вводит детерминированный renderer (R2-010) — C7 не возражает: конвейер вправе делегировать рендер скрипту, но запись принятого триплета остаётся за оркестратором и проходит гейт C3 по candidate | S8 R2-010 |

## Open questions

— (закрыты ревизией 2: грамматика Scope зафиксирована в C1; имя флага — `--scaffold-only`, C7;
ревизия 3: порядок «candidate → гейт → атомарный перенос» закрыл вопрос о точке записи tasks.md).
