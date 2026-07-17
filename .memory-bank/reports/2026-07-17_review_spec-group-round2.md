# Spec review, круг 2: группа sdd-vision-pipeline (9 спек + смысловой аудит, Codex gpt-5.6-sol, effort=high)

> Дата: 2026-07-17 · Повторная валидация после закрытия 96 находок круга 1.
> 9 технических ревьюеров (по одному на спеку; каждому передан raw-вердикт круга 1 для фактической проверки закрытий; S8 — первый полный аудит)
> + 1 смысловой аудитор всей группы (транскрипты интервью + леджеры решений + AGR → трассировка каждой смысловой единицы в спеки).

## Сводка вердиктов (технический круг)

| Спека | Вердикт | crit | major | minor | nit | REQ | UNFIXED/PARTIAL из круга 1 |
|---|---|---|---|---|---|---|---|
| sdd-vision-pipeline | CHANGES_REQUESTED | 1 | 8 | 3 | 0 | 54 | 1 |
| svp-adapt-escalation | CHANGES_REQUESTED | 0 | 5 | 0 | 0 | 10 | 4 |
| svp-brief | CHANGES_REQUESTED | 1 | 7 | 0 | 0 | 10 | 5 |
| svp-contract-test-loop | CHANGES_REQUESTED | 1 | 11 | 1 | 0 | 21 | 0 |
| svp-docs-wiki | CHANGES_REQUESTED | 0 | 10 | 0 | 0 | 11 | 6 |
| svp-interview-upgrade | CHANGES_REQUESTED | 0 | 6 | 0 | 0 | 22 | 3 |
| svp-parallel-engine | CHANGES_REQUESTED | 0 | 10 | 1 | 0 | 13 | 5 |
| svp-roadmap-backlog-db | CHANGES_REQUESTED | 3 | 9 | 0 | 0 | 12 | 6 |
| svp-sdd-core | CHANGES_REQUESTED | 1 | 4 | 1 | 0 | 15 | 3 |

Всего находок: **83** (из них 33 — не полностью закрытые находки круга 1, остальные — новые R2-*).

---

# Часть 1. Смысловой аудит группы (агент №10)

**Вердикт: INTENT_LOST_IN_PLACES**

Основной замысел сохранён: единый SDD-конвейер, бюджеты 120k/400k/~1M, группировка спек, DAG-параллель, fast-to-code, ADaPT, roadmap/backlog, brief/docs и почти весь S8. Однако полностью выпало требование распространить contract-first/eval-механику на `/mb plan`; ослаблены ICE-контракт, структурные eval для нерuntime-задач и несколько менее крупных деталей.

## Трассировка смысловых единиц

- **deferred_explicitly**: 2
- **lost**: 1
- **preserved**: 40
- **weakened**: 5

Не-preserved единицы:

- **D-07** · deferred_explicitly · svp-parallel-engine REQ-001/003/008, NFR-001, Out of Scope
  Односессионный frontier реализуется полностью для реально подключённого транспорта; Pi/OpenCode и прочие хосты явно деградируют с platform_limited, расширение вынесено в I-121/I-122 после подтверждённого self-interview.
- **D-14** · weakened · svp-roadmap-backlog-db REQ-001/002/012, design C1
  Сортировка и прогресс детерминированы, но подтверждённый контракт `{impact, confidence, ease}` заменён готовым integer `ice`; код больше не доказывает I×C×E и не хранит факт пользовательского подтверждения.
- **D-17** · weakened · umbrella REQ-009; svp-sdd-core REQ-003/design step 3
  Предпочтение existing/highest seam есть, но принцип «идеал — один seam» не стал требованием или проверяемым критерием.
- **D-18** · weakened · svp-interview-upgrade REQ-015/016/022
  Frontier batch-раунды сохранены, но параллельные fact-finding субагенты из решения отсутствуют.
- **D-25** · weakened · umbrella REQ-008; svp-sdd-core REQ-007, design C6
  Запрет Eval:none для gated сохранён, но обязательный структурный Eval для docs/config задач не сформулирован; вместо него допускается waiver для non-gated.
- **D-32** · weakened · svp-parallel-engine REQ-002/009/012; umbrella REQ-042/043
  Child-спека сохраняет group-or-large target и все варианты исполнения, но umbrella REQ-043 сужена только до group target.
- **INT-PLAN-CONTRACT-EVAL** · lost · в 9 spec triples отсутствуют требования или задача для commands/plan.md
  Прямая просьба заложить contract-first и кодовые eval не только в `/mb sdd`, но и в `/mb plan`, не получила D-ID и полностью выпала.
- **INT-MULTI-HOST-PARALLEL** · deferred_explicitly · svp-parallel-engine NFR-001/Out of Scope; backlog I-121/I-122
  Необеспеченные Pi/OpenCode/Cursor-пути не выданы за готовые: выбран sequential + platform_limited до отдельного transport harness.

## Потерянные/искажённые смыслы (lost_intents)

### [major] INT-PLAN-CONTRACT-EVAL

**Цитата-источник:** «хочется, чтобы этот скил был заложен в /mb sdd и даже /mb plan, чтобы был контракт-ферст и детерминированные критерии, по которым мы КОДОМ напишем верификацию… ллм будет проверять дополнительно, через ревью»

**Что потеряно:** Вся группа усиливает только SDD/tasks/work. Для plan-only пути нет Contract/Eval-деклараций, red/green-контракта, шаблона или задачи изменения `/mb plan`.

**Где должно приземлиться:** Umbrella requirements и отдельный child/task, покрывающий `commands/plan.md`, plan templates и plan validation.

**Как исправить:** Добавить gated requirement: новый `/mb plan` генерирует Contract/Eval declarations и использует тот же work-time materialization/verify contract, не дублируя S2/S8 реализацию.

### [major] D-14-ICE-SCHEMA

**Цитата-источник:** «ICE во frontmatter спек/планов (LLM предлагает, пользователь подтверждает); score=I×C×E — авторитетный порядок Next + pin-override»

**Что потеряно:** S4 revision 2 заменила объект impact/confidence/ease готовым integer `ice`. Это отсебятина, которая лишает код возможности проверить формулу и не фиксирует пользовательское подтверждение.

**Где должно приземлиться:** `svp-roadmap-backlog-db` requirements REQ-001, design C1, migration schema и roadmap-sync tests.

**Как исправить:** Хранить компоненты ICE и confirmation metadata либо явно зафиксировать отдельное пользовательское решение о переходе на integer; score вычислять скриптом.

### [minor] D-18-FACT-FINDING

**Цитата-источник:** «Опция frontier-раундов интервью (из batch-grill-me): все разблокированные вопросы одним раундом, параллельные fact-finding сабагенты; дефолт — по одному вопросу.»

**Что потеряно:** Batch вопросов реализован, параллельный fact-finding перед/внутри frontier-раунда отсутствует.

**Где должно приземлиться:** `svp-interview-upgrade` REQ-015 и Task 2 либо отдельная задача batch research dispatch.

**Как исправить:** Добавить опциональный параллельный fact-finding шаг с honest platform degradation; последовательный вопрос оставить default.

### [minor] D-17-SINGLE-SEAM

**Цитата-источник:** «Seam-шаг в design-фазе sdd: существующие seams > новые, максимально высокий, идеал — один; подтверждается пользователем»

**Что потеряно:** Спеки требуют existing/highest seam, но не фиксируют предпочтение одного seam и не требуют объяснить необходимость нескольких.

**Где должно приземлиться:** Umbrella REQ-009 и `svp-sdd-core` REQ-003/design generation contract.

**Как исправить:** Добавить критерий: один seam предпочтителен; несколько допустимы только с кратким rationale.

### [major] D-25-STRUCTURAL-EVAL

**Цитата-источник:** «Задача без runtime-поверхности (доки/конфиги) получает структурный Eval (файл существует/секция присутствует/линтер зелёный); `Eval: none` запрещён на gated»

**Что потеряно:** Сохранён только запрет Eval:none для gated. Обязательность структурного Eval для docs/config не стала REQ; S2 design даже вводит waiver для non-gated structural Eval.

**Где должно приземлиться:** `svp-sdd-core` requirements рядом с REQ-007/008, validator rules и fixture tests для docs/config tasks.

**Как исправить:** Добавить явный structural-eval fallback и тесты file/section/lint; waiver не должен быть обычной заменой наблюдаемому структурному Eval.

### [minor] D-32-LARGE-TARGET-UMBRELLA

**Цитата-источник:** «ворк должен спросить как всё делать: последовательно, параллельно — через тиммод или сабагентов, или посоветовать открыть ещё несколько сессий ... если задача очень большая и один ворк явно не справится»

**Что потеряно:** Child S3 сохраняет group-or-large target, но umbrella REQ-043 требует вопрос только для group target, создавая нормативное сужение на стыке.

**Где должно приземлиться:** Umbrella requirements REQ-043.

**Как исправить:** Заменить trigger на “group or estimated-large target” и сослаться на ту же детерминированную size rubric.

### [minor] AGR-018-UMBRELLA-WORDING

**Цитата-источник:** «Контрактная фаза = отдельная первая задача, не под-шаг каждой задачи.»

**Что потеряно:** Umbrella REQ-049 сформулирована как “place a contract task before every implementation task”, что можно прочитать как отдельную контрактную задачу перед каждой implementation task. Child REQ-001 корректно говорит exactly one.

**Где должно приземлиться:** Umbrella requirements REQ-049.

**Как исправить:** Переформулировать как “generate exactly one contract task ordered before all implementation tasks”.

### [minor] D-31-UMBRELLA-ORDER

**Цитата-источник:** «внутри группы ICE-приоритизация и хранение этой информации в роудмепе»

**Что потеряно:** Umbrella tasks header задаёт S6 перед S8, хотя ICE 360 у S8 выше ICE 336 у S6 и umbrella design/roadmap дают правильный порядок S8→S6.

**Где должно приземлиться:** `specs/sdd-vision-pipeline/tasks.md` строка порядка исполнения.

**Как исправить:** Синхронизировать header с design и roadmap: S2 → S8 → S6 → S3 → S5 с учётом зависимостей.


**Notes:** Аудит выполнен read-only; файлы не изменялись. Все транскрипты и леджеры были прочитаны до spec triples. Отклонённые пользователем альтернативы не классифицировались как потери. В S8 transcript осталась историческая фраза «подтверждение ожидается», но более поздний AGR-018 является подтверждённым источником истины, поэтому это не признано потерей спеки.

---

# Часть 2. Технические находки (severity ↓, затем спека)

### CRITICAL (7)

#### [sdd-vision-pipeline] SVP-008 · cross-slice · `.memory-bank/specs/sdd-vision-pipeline/tasks.md:6,32-181; .memory-bank/specs/svp-sdd-core/design.md:25-31`

**Проблема:** PARTIAL: hard-зависимости исправлены во frontmatter, но исполнимый DAG umbrella-задач остаётся неверным.

**Доказательство:** Umbrella design задаёт S7←S1, S8←S2, S6←S2, S3←S2, S5←S2+S3 (`design.md:32-38`), и child frontmatter с этим согласован. Однако в `tasks.md` единственное поле `Blocked-by` находится у T9/S8 и содержит `3` (`tasks.md:181`), то есть блокирует S8 по S4 вместо S2/T4. Остальные мета-задачи поля не имеют. S2-C1 задаёт legacy-default `blocked-by=предыдущая задача` (`svp-sdd-core/design.md:25-28`), поэтому после реализации v2 umbrella фактически превратится в цепь T1→T2→T3→T4→T5→T6→T7→T8, а T9 будет зависеть от T3. Это не заявленный DAG и допускает неверный порядок поставщиков.

**Рекомендация:** Закодировать hard DAG непосредственно в каждой мета-задаче, не полагаясь на заголовки и prose-порядок.

**Готовая правка:**

```
Добавить поля: T2/S1 — `**Blocked-by:** none`; T3/S4 — `**Blocked-by:** none`; T4/S2 — `**Blocked-by:** none`; T5/S6 — `**Blocked-by:** 4`; T6/S5 — `**Blocked-by:** 4, 7`; T7/S3 — `**Blocked-by:** 4`; T8/S7 — `**Blocked-by:** 2`; T9/S8 — заменить `**Blocked-by:** 3` на `**Blocked-by:** 4`. В заголовке T6 заменить `blocked by S2` на `blocked by S2, S3`; строку порядка `tasks.md:6` привести к design/roadmap: `T1 → T2 → T8 → T3 → T4 → T9 → T5 → T7 → T6`.
```

#### [svp-brief] R2-001 · contract · `.memory-bank/specs/svp-brief/design.md:18-21,41-42,106-118; .memory-bank/specs/svp-brief/tasks.md:18-30`

**Проблема:** C6 не имеет канала для готового LLM-текста, поэтому заявленная атомарная запись валидного brief невозможна.

**Доказательство:** Prompt должен владеть текстом Solution/Scenarios/Constraints/UX, а helper — атомарной записью (`design.md:18-21`). Но `create` принимает только topic/request/input/auto и сам «заполняет шаблон» (`:108-114`), без candidate/stdin/content аргумента. Task 1 дополнительно ставит вызов helper до «генерации текста» (`tasks.md:19-23`). Это либо создаст пустой шаблон до генерации, либо заставит prompt изменять destination после atomic write, нарушая C0 «structural validation before creation» (`design.md:41-42`). `context` также смешивает произвольное содержимое brief.md и список путей без framing или сортировки (`:115-118`).

**Рекомендация:** Передавать helper полностью сформированный candidate и оставить ему только validation/staging/atomic publish; context должен возвращать машинно-разбираемый manifest.

**Готовая правка:**

```
Заменить C6 на: «`create --mb <bank> --topic <topic> --candidate <complete-brief.md> [--input <path>]...`. Prompt сначала завершает анализ/вопросы/генерацию и пишет полный candidate в `<bank>/tmp/brief-<topic>.candidate.md`. Helper проверяет candidate через C1, сверяет frontmatter `inputs` и Attachments с basename переданных inputs, выполняет C5 для всех inputs, собирает staging directory под `<bank>/tmp/`, затем одним `mv` публикует `briefs/<topic>/`. При любой ошибке staging и candidate удаляются, destination не создаётся/не меняется. Success: stdout `brief=created path=briefs/<topic>/brief.md`, exit 0. Expected refusal: `brief=blocked reason=<invalid|secret|scan_unsupported|exists>`, exit 1. Usage/I-O: exit 2. `context --mb <bank> --topic <topic>` печатает либо одну строку `brief=absent`, либо `brief=present`, затем `brief_path=<relative-path>` и `input_path=<relative-path>` в `LC_ALL=C` порядке; body не печатается.» В Task 1 изменить порядок на «generate complete candidate → invoke helper → offer handoff» и убрать request flags из helper signature.
```

#### [svp-contract-test-loop] R2-001 · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:48`

**Проблема:** Не определён машиночитаемый реестр контрактных чекеров и evidence, поэтому verify не знает, что запускать.

**Доказательство:** C3 задаёт только `Layer: contract`, позицию и пять текстовых шагов (`design.md:48-53`). C7 возвращает `checker: "<cmd>"`, но не определяет producer, список команд или durable state (`design.md:72-76`). Формат red-артефакта оставлен открытым (`design.md:108-111`), хотя REQ-004 и REQ-021 требуют записать red и позднее повторить чекеры (`requirements.md:29,73-74`).

**Рекомендация:** До разработки зафиксировать единый executable contract для регистрации, red-прогона и verify-прогона чекеров.

**Готовая правка:**

```
Добавить в design.md:

`### C3a. Registry и runner контрактных чекеров`
`Контрактная задача завершает отчёт строкой MB_CONTRACT_RESULT_JSON={"checkers":[{"id":"<slug>","covers":["REQ-NNN"],"cmd":"<exact command>","cwd":"<repo-relative>"}]}. Оркестратор валидирует JSON и записывает список в существующий <bank>/.work-state.json либо <bank>/.work-state/<run_id>.json под ключом contract_checkers. scripts/mb-contract-gate.sh red|verify --run-id <id> --mb <bank> читает этот ключ и запускает команды byte-identical. red: каждый checker обязан завершиться ненулево по заявленной причине; green до реализации → exit 1, verdict=fake_red. verify: все checker должны вернуть 0; любой иной exit → verification FAIL. Exit 0=gate passed, 1=contract failure, 2=usage/schema/state error. stdout — один JSON с checker id, exit и output_sha256; stderr — диагностика.`

Добавить этот runner и его tests в Scope/DoD Task 5 и удалить Open Question о формате red-артефакта.
```

#### [svp-roadmap-backlog-db] F-003 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:64`

**Проблема:** PARTIAL: описанный Kahn-порядок не может сохранить legacy-вывод byte-identical

**Доказательство:** C2 требует раундовый Kahn: frontier эмитируется целиком по раундам (`design.md:64-80`), одновременно утверждая byte-identical деградацию без ice/pin (`design.md:73-75`). Текущая реализация — DFS (`scripts/mb-roadmap-sync.sh:175-212`). Для порядка файлов A,B,C, где A зависит от C, DFS даёт C,A,B, а описанный Kahn — B,C,A. Task 1 проверяет лишь сегодняшний corpus (`tasks.md:21,29`), поэтому несовместимость на валидном legacy-графе останется.

**Рекомендация:** Сохранить прежний DFS как явную ветку совместимости и тестировать зависимый legacy-граф, а не только текущий corpus.

**Готовая правка:**

```
Добавить перед шагом 1 C2: `If no item in the rendered section has a valid ice or pin, the script MUST call the existing dependency_order(items) implementation unchanged and return its exact ordering and warning output. The Kahn priority path is entered only when at least one item has ice or pin.` В Task 1 Testing добавить фикстуру A→C, B, C в файловом порядке A/B/C и assert legacy-вывода `C,A,B` byte-identical.
```

#### [svp-roadmap-backlog-db] F-012 · edge-case · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:244`

**Проблема:** UNFIXED: глобальная уникальность I-NNN снова сведена к сканированию одного backlog.md

**Доказательство:** C6 предписывает искать максимум только в `backlog.md` (`design.md:244-249`). Репозиторий уже содержит подтверждённую коллизию именно из-за этого алгоритма: `.memory-bank/backlog.md:504-506` описывает повторное выделение I-075 при существующем ID в progress.md. Это противоречит инварианту «I-NNN никогда не переиспользуются» (`context/svp-roadmap-backlog-db.md:61`). Дополнительно Task 2 Eval не запускает заявленный `test_mb_lock_helper.bats` (`tasks.md:53,56`), а Task 3 вообще не требует C6-lock для мигратора (`tasks.md:75-89`).

**Рекомендация:** Вернуть единый глобальный allocator и включить lock/allocator проверки в фактические Eval.

**Готовая правка:**

```
Заменить C6 allocation-текст на: `While holding <bank>/.locks/backlog.lock, every writer obtains the next I-NNN through one shared helper that scans backlog.md, progress.md, agreements.md and index.json when present; malformed optional sources are ignored with a warning, and next_id=max(all discovered I-NNN)+1. No writer implements its own allocator.` Изменить T2 Eval на `bats tests/bats/test_mb_backlog_state.bats && bats tests/bats/test_mb_lock_helper.bats`. В T3 добавить `mb_lock_acquire`/atomic-write в What to do и concurrent migrate-vs-idea test.
```

#### [svp-roadmap-backlog-db] R2-002 · feasibility · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:48`

**Проблема:** Новая state machine не интегрирована с существующим mb-idea-promote.sh

**Доказательство:** Task 2 включает `mb-idea-promote.sh` в Scope, но меняет в нём только lock (`tasks.md:45,48-52`). Текущий скрипт принимает NEW/TRIAGED и пишет состояние PLANNED (`scripts/mb-idea-promote.sh:11,69-75`). После S4 PLANNED отсутствует в допустимом алфавите и будет ошибкой `invalid_state` (`design.md:220-225`). Context явно требует расширить, а не забыть существующий путь (`context/svp-roadmap-backlog-db.md:20,60`).

**Рекомендация:** Определить v2/legacy поведение idea creation и promotion как часть C3 и Task 2.

**Готовая правка:**

```
Добавить в C3: `New items created after S4 carry **Type:** IDEA. For a v2 item, mb-idea-promote.sh accepts only READY, creates the plan, then atomically applies READY→IN-PROGRESS through the shared transition primitive; any other v2 state is rejected without a plan or partial mutation. Pure legacy items without v2 metadata retain the existing NEW|TRIAGED→PLANNED behavior until explicit migration. mb-bank-lint treats C4 legacy tokens on pure legacy items as compatibility warnings, not invalid_state errors.` Добавить эти ветки в Task 2 Testing/Eval.
```

#### [svp-sdd-core] F-007 · contract · `.memory-bank/specs/svp-sdd-core/design.md:12,45-57; .memory-bank/specs/svp-sdd-core/requirements.md:56-58; .memory-bank/specs/svp-sdd-core/tasks.md:66-72,89-95`

**Проблема:** PARTIAL: F-007 — бюджетный гейт до записи tasks.md невозможно выполнить через C3, который умеет читать только уже записанный tasks.md.

**Доказательство:** Архитектура ставит «(4) оценка бюджетов C3» раньше «(5) генерация tasks.md v2» (`design.md:12`), но C3 резолвит только `<bank>/specs/<topic>/tasks.md` (`design.md:45-48`). Одновременно REQ-010 требует остановиться до записи tasks.md (`requirements.md:57`). Не определён ни candidate-артефакт, ни вход C3 для ещё не принятого содержимого; при повторном запуске C3 может прочитать старый финальный tasks.md. Формат `estimated_tokens.stages` также не задан точной YAML-схемой (`design.md:56-57`).

**Рекомендация:** Разделить candidate и финальный tasks.md и дать estimate-check явный вход для candidate. Гейт обязан оценивать именно новое содержимое, а не существующий файл спеки.

**Готовая правка:**

```
В C3 добавить:
- `scripts/mb-estimate-check.sh --tasks-file <candidate-path> [--mb <bank>]` — взаимоисключающий с `--spec`; читает ровно переданный candidate и не резолвит существующий triple.
- Оркестратор генерирует candidate в `<bank>/tmp/sdd/<topic>/tasks.candidate.md`; task-агенты его не пишут.
- До прохождения C3/D-35 файл `<bank>/specs/<topic>/tasks.md` не создаётся и не изменяется. Существующий финальный tasks.md не используется для оценки нового candidate.
- После pass или `budget_override: user` оркестратор атомарно переносит candidate в финальный tasks.md; при blocked/invalid финальный файл остаётся byte-identical.
- Frontmatter-схема фиксируется как `estimated_tokens: {total: <int>, stages: {"<stage-id>": <int>}}`.

В Task 3 Testing добавить: candidate ok/over; stale final игнорируется; over не создаёт и не меняет final; отсутствие candidate → exit 2.
```

### MAJOR (70)

#### [sdd-vision-pipeline] R2-001 · eval · `.memory-bank/specs/sdd-vision-pipeline/requirements.md:162-165; scripts/mb-spec-validate.sh:228-264`

**Проблема:** Umbrella не проходит заявленный `mb-spec-validate.sh --require-scenarios`: отсутствуют сценарии для всех 54 REQ.

**Доказательство:** Раздел Scenarios содержит только комментарии о делегировании в child-слайсы (`requirements.md:162-165`). `python3 scripts/mb-scenario-extract.py .../sdd-vision-pipeline/requirements.md` возвращает 0 строк. Валидатор при `--require-scenarios` сравнивает определения REQ только со сценариями этого файла и печатает нарушение для каждого отсутствующего ID (`mb-spec-validate.sh:243-264`); он не знает о `covers_umbrella`. Следовательно, все REQ-001…054 считаются непокрытыми.

**Рекомендация:** Либо материализовать umbrella-сценарии, либо специфицировать и реализовать машинно-проверяемое делегирование до объявления батареи green.

**Готовая правка:**

```
Предпочтительный минимальный фикс без изменения валидатора: заменить комментарии `requirements.md:164-165` на 54 канонических блока `<!-- mb-scenario:N -->`, по одному на REQ-001…054, перенеся соответствующий GWT из owning child-слайса и заменив `**Covers:**` на umbrella-ID. Для REQ-038 добавить отдельный сценарий: `GIVEN README.md и commands/discuss.md цитируют mattpocock/skills; WHEN запускается attribution Eval; THEN оба файла содержат ссылку на источник и указание MIT`. После правки зафиксировать фактический green `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/sdd-vision-pipeline`.
```

#### [sdd-vision-pipeline] R2-002 · eval · `.memory-bank/specs/sdd-vision-pipeline/tasks.md:13-29; .memory-bank/specs/sdd-vision-pipeline/requirements.md:140`

**Проблема:** Eval T1 имеет настоящий red, но не проверяет обязательную MIT-атрибуцию.

**Доказательство:** REQ-038 требует credit `mattpocock/skills (MIT)` (`requirements.md:140`). Eval T1 проверяет лишь наличие строки `mattpocock/skills` в двух файлах (`tasks.md:21`), поэтому станет green от голой ссылки без лицензии. DoD также требует MIT только для README, а для `commands/discuss.md` — лишь ссылку (`tasks.md:26-29`). Прямой прогон Eval сейчас возвращает exit 1, то есть red настоящий, но green-сигнал слабее требования.

**Рекомендация:** Заменить word-grep поведенческой детерминированной проверкой полного attribution-контракта.

**Готовая правка:**

```
Заменить Eval на `**Eval:** bats tests/bats/test_mattpocock_attribution.bats — red: attribution-теста и MIT credits ещё нет`. В Testing записать: `Тест на README.md и commands/discuss.md требует в каждом файле ссылку https://github.com/mattpocock/skills и слово MIT в том же credits/source-блоке; отсутствие любого элемента возвращает non-zero`. В DoD заменить второй пункт на `commands/discuss.md содержит ссылку на источник и MIT attribution`.
```

#### [sdd-vision-pipeline] R2-003 · cross-slice · `.memory-bank/specs/svp-interview-upgrade/design.md:90-110; .memory-bank/specs/svp-brief/design.md:85-104; .memory-bank/specs/svp-brief/tasks.md:15-29`

**Проблема:** S7 потребляет несовместимый с S1 secret-scan CLI и не владеет необходимым расширением.

**Доказательство:** S1 определяет только `scripts/mb-secret-scan.sh --policy transcript <candidate-file>`, где `<private>` исключается, pragma запрещена, а exit 2 означает usage/read error (`svp-interview-upgrade/design.md:90-110`). S7 вызывает тот же скрипт без `--policy`, разрешает `<!-- mb-secret-ok -->`, не исключает `<private>` и переопределяет exit 2 как binary/unsupported (`svp-brief/design.md:85-101`). При этом S7 называет владельцем `sdd-openspec-parity`, хотя DAG блокирует S7 только по S1 (`design.md:90-91`). Scope T1 S7 не включает `scripts/mb-secret-scan.sh` (`tasks.md:15`), поэтому реализовать требуемую политику задача не может.

**Рекомендация:** Зафиксировать общий dispatcher и отдельную brief-input policy с непересекающимися exit-кодами и явным владельцем.

**Готовая правка:**

```
В S1-C5 добавить: `CLI dispatcher: scripts/mb-secret-scan.sh --policy <transcript|brief-input> <file>; unknown policy/usage/read error = exit 2`. В S7-C5 заменить вызов на `scripts/mb-secret-scan.sh --policy brief-input <source-path>` и определить: `0 clean; 1 secret; 2 usage/read error; 3 unsupported binary/type`. Для `brief-input` сохранить pragma `<!-- mb-secret-ok -->`, не считать `<private>` bypass; при exit 3 допустимы только решения `remove input` или `cancel`, без копирования unsupported-файла в MVP. В S7 Task 1 добавить `scripts/mb-secret-scan.sh` в Scope и текст `расширить S1-owned dispatcher политикой brief-input`; удалить утверждение о владельце `sdd-openspec-parity`.
```

#### [sdd-vision-pipeline] R2-004 · parent-decision · `.memory-bank/context/sdd-vision-pipeline.md:49; .memory-bank/specs/sdd-vision-pipeline/requirements.md:97; .memory-bank/specs/sdd-vision-pipeline/design.md:48; .memory-bank/specs/svp-roadmap-backlog-db/design.md:34-48`

**Проблема:** Group frontmatter хранит только готовый ICE score, вопреки D-14 и REQ-024 о вычислении I×C×E скриптом из frontmatter.

**Доказательство:** D-14 требует `score=I×C×E` и принцип «заполняется скриптом где возможно» (`context:49`); umbrella REQ-024 прямо говорит `impact×confidence×ease from frontmatter, computed and sorted by script` (`requirements.md:97`). Но Interface 4 оставляет `ice: <число>` (`design.md:48`), а S4-C1 сознательно фиксирует pre-computed plain integer (`svp-roadmap-backlog-db/design.md:38-47`). Реализатор не сможет проверить компоненты или пересчитать score; LLM/человек остаётся источником вычисляемого числа.

**Рекомендация:** Хранить три подтверждённых фактора и детерминированно вычислять/валидировать score.

**Готовая правка:**

```
Заменить C1-поле на `ice: {impact: <1..10>, confidence: <1..10>, ease: <1..10>}`; `mb-roadmap-sync.sh` вычисляет произведение, а `mb-bank-lint.sh` отклоняет отсутствующий/вне диапазона компонент. Обновить 8 child frontmatter: S1 `{8,9,7}`, S2 `{10,8,5}`, S3 `{9,7,4}`, S4 `{8,9,6}`, S5 `{7,7,6}`, S6 `{6,8,7}`, S7 `{8,8,7}`, S8 `{9,8,5}`. В umbrella Interface 4 записать тот же объект; `pin` остаётся отдельным override.
```

#### [sdd-vision-pipeline] R2-005 · feasibility · `.memory-bank/specs/svp-contract-test-loop/tasks.md:113-128; commands/mb.md:497-534`

**Проблема:** S8 Task 5 пытается расширять несуществующий `commands/verify.md`; реальный `/mb verify` находится в `commands/mb.md`.

**Доказательство:** Task Scope и What to do называют `commands/verify.md` (`tasks.md:119,123`), но `rg --files commands` такого файла не возвращает. Фактический контракт `/mb verify` расположен inline в `commands/mb.md` (`commands/mb.md:497-534`). Создание нового файла в текущем Scope не подключит его к маршрутизатору и оставит рабочую команду неизменной.

**Рекомендация:** Править фактическую точку входа либо явно специфицировать extraction+router migration.

**Готовая правка:**

```
Для минимального среза заменить Scope на `commands/mb.md, commands/work.md, tests/bats/test_mb_verify_contract_gate.bats`. В What to do заменить `commands/verify.md` на ``commands/mb.md` § `### verify`` и указать: `встроить прогон contract-checkers до итогового PASS; любой post-implementation checker exit≠0 принудительно даёт FAIL`.
```

#### [sdd-vision-pipeline] R2-006 · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:48-76,108-113; .memory-bank/specs/svp-contract-test-loop/tasks.md:113-131`

**Проблема:** S8 не определяет, где объявлены contract-checker команды и где хранится доказательство обязательного pre-implementation red.

**Доказательство:** C3 задаёт только `Layer: contract`, позицию и пять prose-шагов (`design.md:48-53`). C7 возвращает `checker: <cmd>`, но источник `<cmd>` не определён (`design.md:72-76`). Task 5 требует запускать «объявленные контрактные чекеры» (`tasks.md:122-126`), хотя ни tasks.md v2 S2-C1, ни S8-C3 не содержат поля с командами. Формат red-артефакта и даже необходимость `Layer: contract` оставлены открытыми вопросами (`design.md:108-113`). Реализатор вынужден угадывать discovery, состояние, восстановление после crash и проверку drift команды.

**Рекомендация:** Закрыть оба open question и добавить машинный реестр checker-команд с детерминированным evidence-контрактом.

**Готовая правка:**

```
В S8-C3 и S2-C1 добавить поле `**Contract-checkers:** ["<exact argv command>", ...]` на contract-задаче; пустой список при `contract_first: true` — validation error. Зафиксировать `**Layer:** contract` как обязательное значение. Оркестратор пишет `<bank>/tmp/contract-evidence/<topic>/task-<n>.json` со схемой `{commands:[{cmd, fixture_negative_exit, fixture_positive_exit, pre_impl_exit, post_impl_exit}], baseline_ref, recorded_at}`. До implement требуется `fixture_negative_exit != 0`, `fixture_positive_exit == 0`, `pre_impl_exit != 0`; `pre_impl_exit == 0` даёт `fake_red`. Verify перечитывает тот же файл, сверяет точное `cmd` и `baseline_ref`, запускает команды и требует `post_impl_exit == 0`. Обновить T3/T5 tests этими четырьмя случаями и удалить оба пункта Open questions.
```

#### [sdd-vision-pipeline] R2-007 · edge-case · `.memory-bank/specs/sdd-vision-pipeline/design.md:46; .memory-bank/specs/svp-parallel-engine/design.md:60-101; .memory-bank/specs/svp-parallel-engine/tasks.md:56-79`

**Проблема:** Claims-lock защищает гонку двух живых процессов, но после crash навсегда блокирует все мутации и допускает чтение частично дописываемой JSONL.

**Доказательство:** Контракт обещает owner-token mkdir-lock (`umbrella design.md:46`), но S3 описывает только `mkdir`, retry, `trap` и `rmdir` (`parallel-engine/design.md:67-71`): token/PID/timestamp внутри lock, проверка владельца при release и stale-lock reclaim отсутствуют. `trap` не исполняется после SIGKILL/падения хоста, поэтому каждый следующий вызов завершится lock-timeout exit 3. `list` намеренно читает JSONL без lock (`design.md:89-90`), хотя concurrent append может дать временно оборванную последнюю строку и exit 2. Тесты проверяют удерживаемый lock, но не crash/reclaim (`tasks.md:71-79`).

**Рекомендация:** Дописать полный owner-token lifecycle и консистентное чтение.

**Готовая правка:**

```
В C2 записать: после успешного `mkdir` создать `<lock>/owner` с `token`, `pid`, `host`, `session_id`, `acquired_at`; release удаляет lock только при совпадении token. При contention live owner ждётся до timeout; dead PID на том же host либо возраст старше `MB_CLAIMS_LOCK_TTL` допускает атомарный reclaim через `mv <lock> <lock>.reclaim.<token>`, проигравший `mv` повторяет acquisition. `list` либо берёт тот же lock, либо ждёт его освобождения и затем читает полный snapshot; partial trailing JSON считается retryable, не corrupt state. Добавить bats: SIGKILL owner→reclaim; два одновременных reclaimer→один победитель; чужой token не release; list во время append не видит partial JSON.
```

#### [sdd-vision-pipeline] R2-008 · parent-decision · `.memory-bank/specs/svp-parallel-engine/tasks.md:132-160; rules/RULES.md:698-705`

**Проблема:** Multi-session тест требует сгенерированный ACK, хотя по правилам ACK должен добавить получатель.

**Доказательство:** Task 4 поручает оркестратору генерировать записи COORDINATION.md (`tasks.md:140-141`), а Testing требует `STATUS/FREEZE/ACK` (`tasks.md:157`). Правило проекта говорит, что freeze/handover/commit-order требуют ACK «from the other side» (`rules/RULES.md:703`), и peer не может одобрять расширение полномочий (`rules/RULES.md:705`). Инициатор, создающий собственный ACK, фальсифицирует протокол координации.

**Рекомендация:** Разделить инициирующую запись и подтверждение другой сессией.

**Готовая правка:**

```
Заменить What to do на: `Оркестратор инициатора append-ит STATUS и при необходимости FREEZE/HANDOVER, но никогда ACK; состояние остаётся pending до ACK, append-нутого receiving session.` Заменить тест на: `инициатор создаёт STATUS+FREEZE без ACK; до foreign ACK shared-watchlist недоступен; ACK с другим session_id активирует соглашение; self-ACK отклоняется`.
```

#### [svp-adapt-escalation] R2-001 · cross-slice · `.memory-bank/specs/svp-contract-test-loop/design.md:72`

**Проблема:** S8 объявляет S5 потребителем `fake_red`, но S5 не определяет мост к своему единственному agent-signal.

**Доказательство:** S8-C7 выдаёт `{"contract_task":{"status":"fake_red","checker":"<cmd>"}}` и заявляет совместимость через `complexity_escalation` (`specs/svp-contract-test-loop/design.md:72-76`). S5-C4 принимает только envelope с `status` и `complexity_escalation`; отсутствие последнего считается invalid report (`specs/svp-adapt-escalation/design.md:208-222`). Ни одна сторона не определяет, кто и как преобразует fake_red, поэтому S8-вердикт либо остановится как malformed, либо не вызовет ADaPT.

**Рекомендация:** Зафиксировать единый envelope для fake_red на обеих сторонах межслайсового контракта.

**Готовая правка:**

```
В S8-C7 заменить пример на:
`MB_WORK_RESULT_JSON={"status":"BLOCKED","contract_task":{"status":"fake_red","checker":"<cmd>"},"complexity_escalation":{"reason":"fake_red","estimated_tokens":<current-task-Budget>}}`.
В S5-C4 добавить: `contract_task` необязателен, но если `contract_task.status == fake_red`, то `complexity_escalation` обязан быть non-null, `reason` обязан равняться `fake_red`, а `estimated_tokens` — положительному Budget текущей задачи; несоответствие → `invalid_implementer_report`. Добавить в Task 3 Bats-кейс, подтверждающий один opened event с trigger `agent_signal` для этого envelope.
```

#### [svp-adapt-escalation] SVP-AE-007 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:108`

**Проблема:** PARTIAL: SVP-AE-007 — двухфазность восстановлена, но формат записей escalation JSONL всё ещё не определён.

**Доказательство:** REQ-007 требует matching `opened`/`resolved` JSONL records (`requirements.md:49`), а context требует общие ключи `item_id`/`cycle`/`mode` (`context/svp-adapt-escalation.md:34,52`). Design задаёт только stdout решения (`design.md:108-117`) и словесно предписывает append событий (`design.md:134-150`), не определяя JSON-поля `event`, `run_id`, `item_id`, `cycle`, `mode`, resolution metadata или формат `clean`. Реализатор и читатель лога вынуждены независимо изобрести несовместимые схемы.

**Рекомендация:** Зафиксировать полные схемы всех трёх типов записей и правила валидации/свёртки.

**Готовая правка:**

```
Добавить после C1.1:
`<bank>/tmp/escalations.jsonl` содержит ровно один JSON object на строку. Допустимы только схемы:
- opened: `{"event":"opened","escalation_id":"<id>","run_id":"<id>","item_id":"<key>","cycle":<int>,"mode":"autonomous|hitl","triggers":["<token>"],"degraded_guards":["<token>"],"consecutive":<int>}`;
- resolved: `{"event":"resolved","escalation_id":"<id>","run_id":"<id>","item_id":"<key>","cycle":<int>,"mode":"autonomous|hitl","resolution":"continue|simplify|replan|skip|stub_continue","replan_kind":null|"decomposition"|"requirement_change","backlog_id":null|"I-NNN","spec_topic":null|"<slug>"}`;
- clean: `{"event":"clean","run_id":"<id>","item_id":"<key>","cycle":<int>}`.
`triggers` и `degraded_guards` сортируются и дедуплицируются. Неизвестный event, отсутствующий/лишний ключ или неверный тип делает лог невалидным: команда завершается exit 1 без append. Свёртка resolved выполняется по escalation_id; последнее валидное resolved-событие побеждает.`
```

#### [svp-adapt-escalation] SVP-AE-008 · parent-decision · `.memory-bank/specs/svp-adapt-escalation/design.md:128`

**Проблема:** PARTIAL: SVP-AE-008 — `replan` по-прежнему не различает декомпозицию и смену требований.

**Доказательство:** Родительское D-16 явно разделяет «декомпозиция или смена требований» (`context/sdd-vision-pipeline-interview.md:56-57`), а REQ-005 сохраняет обе ветви (`requirements.md:40`). CLI принимает только общий enum `replan` и необязательный `--spec-topic` (`design.md:128-132`), а таблица безусловно обещает новую child-спеку даже для смены требований (`design.md:234-239`). Кроме того, идемпотентность сравнивает лишь resolution, поэтому исправление spec-topic при том же `replan` молча потеряется (`design.md:136-139`).

**Рекомендация:** Сделать вид перепланирования обязательной частью resolution payload и определить разные переходы.

**Готовая правка:**

```
Заменить контракт resolve для `replan` на:
`mb-work-adapt.sh resolve ... --resolution replan --replan-kind <decomposition|requirement_change> [--spec-topic <slug>]`.
`--replan-kind` обязателен только для replan. При `decomposition` обязателен `--spec-topic`: создаётся child-спека через decomposed-spec registry и интервью. При `requirement_change` `--spec-topic` запрещён: child-спека не создаётся, item остаётся pending, а следующий запуск разрешён только после утверждённой правки текущих Requirements/Scope/DoD. Идемпотентность сравнивает полный tuple `(resolution,replan_kind,backlog_id,spec_topic)`; полностью одинаковый tuple — no-op, изменение любого поля — append корректирующего resolved-события. Добавить отдельный Bats-сценарий для каждой ветви.
```

#### [svp-adapt-escalation] SVP-AE-009A · eval · `.memory-bank/specs/svp-adapt-escalation/design.md:152`

**Проблема:** PARTIAL: SVP-AE-009 — verify-гейт всё ещё принимает default-on или реально неограждённый стаб.

**Доказательство:** C6 требует default-off flag, полный Protocol/Interface, docstring и размещение реализации за флагом (`design.md:247-251`); это также обязательное правило проекта (`rules/RULES.md:377-380`). Однако verify-stub проверяет лишь наличие маркера, backlog ID и второго текстового упоминания имени флага (`design.md:160-165`). Например, `FLAG=1` и неиспользуемое упоминание токена пройдут. Task 5 не содержит негативных случаев для default-on, маркера вне docstring или кода вне gate (`tasks.md:162-166`).

**Рекомендация:** Добавить детерминированное поведенческое доказательство flag-off/flag-on к каждому backlog-linked stub.

**Готовая правка:**

```
Дополнить C6 и C1.4:
`Каждый backlog-элемент стаба обязан содержать строку **Stub Eval:** <command>. Команда выполняется из repo root и детерминированно проверяет три факта: (1) при отсутствующем/default-off флаге сохраняется прежний путь; (2) при flag-on активируется полная stub-реализация; (3) MB-ADAPT-STUB находится в docstring этой реализации. verify-stub получает обязательный --repo <root>, извлекает Stub Eval из связанного I-NNN и запускает его с timeout 120 секунд. Отсутствующий Stub Eval, non-zero, timeout или default-on fixture дают violation и exit 1; отсутствующий test runner даёт fail-loud exit 2.`
В Task 5 добавить Bats-фикстуры: `default-on → FAIL`, `маркер вне docstring → FAIL`, `токен флага не управляет stub path → FAIL`, `flag-off/flag-on behavioral command green → PASS`.
```

#### [svp-adapt-escalation] SVP-AE-009B · cross-slice · `.memory-bank/specs/svp-adapt-escalation/design.md:253`

**Проблема:** PARTIAL: SVP-AE-009 — создание READY backlog item не согласовано с фактическим контрактом S4-C3.

**Доказательство:** Child context требует READY-элемент (`context/svp-adapt-escalation.md:33`). S5 вызывает `mb-idea.sh`, который создаёт обычный элемент, а затем неопределённо обещает «перевод» через API с parent (`design.md:253-258`). Фактический S4-C3 предоставляет только `transition` и `list` (`specs/svp-roadmap-backlog-db/design.md:121-127`); READY требует предварительных переходов и behavioral `**Brief:**` (`:129-149`), а parent задаётся отдельной строкой (`:151-155`). API для записи Brief/Parent отсутствует. В roadmap S4 всегда исполняется раньше S5 (`.memory-bank/roadmap.md:97`), поэтому ветка «до S4» неприменима.

**Рекомендация:** Добавить в S4 атомарный контракт метаданных и записать в S5 точную последовательность переходов.

**Готовая правка:**

```
В S4-C3 добавить:
`mb-backlog-state.sh annotate <I-NNN> --brief <TEXT> --parent <I-NNN|none> [--mb PATH]`. Команда атомарно добавляет или заменяет ровно строки `**Brief:**` и `**Parent:**`; проверяет behavioral Brief и parent по тем же правилам, что READY-гейт; stdout `item=<id> annotated`, exit 1 domain validation, exit 2 usage/not-found.
В S5-C6 заменить абзац создания на точную последовательность:
`id=$(bash scripts/mb-idea.sh "[ADAPT] <spec-topic>#<task-id>: <reason>" HIGH <bank>)`; затем `transition $id NEEDS-INFO`; `annotate $id --brief "When <FLAG> is off, existing behavior remains; when enabled, the deferred <reason> path is supplied by the staged implementation." --parent <originating-I-NNN-or-none>`; `transition $id TRIAGED`; `transition $id READY`. Любой non-zero останавливает stub path до правки кода. Удалить ветку «до S4».
```

#### [svp-brief] R2-002 · consistency · `.memory-bank/specs/svp-brief/design.md:41-47; .memory-bank/specs/svp-brief/tasks.md:3-16,43-73`

**Проблема:** Task 1 обязан вызвать валидатор, который создаётся только следующей независимой Task 2.

**Доказательство:** C0 требует structural validation до публикации (`design.md:41-42`). Task 1 реализует helper по C0/C2/C5/C6 (`tasks.md:43-45`), но её `Blocked-by: none` и Scope не содержат валидатор (`:14-15`). Валидатор создаёт Task 2, также `Blocked-by: none` (`:48-73`), тогда как объявленный порядок — `1 → 2 → 3 → 4` (`:5`). Следовательно, Task 1 не может выполнить собственный DoD в заявленном порядке.

**Рекомендация:** Исполнить validator task до command/helper task и выразить зависимость в DAG.

**Готовая правка:**

```
В преамбуле tasks.md заменить порядок на `2 → 1 → 3 → 4`. В Task 1 заменить `**Blocked-by:** none` на `**Blocked-by:** 2`. Task 2 оставить `Blocked-by: none`; Tasks 3 и 4 оставить blocked by 1. В Task 1 Testing добавить проверку, что helper действительно вызывает уже реализованный `scripts/mb-brief-validate.sh` до publish.
```

#### [svp-brief] R2-003 · eval · `.memory-bank/specs/svp-brief/tasks.md:103-123; .memory-bank/specs/svp-brief/design.md:81-84,126-136; rules/RULES.md:291-311`

**Проблема:** Eval Task 4 зелёнеет от одной строки и не проверяет две трети заявленного DoD.

**Доказательство:** Task 4 требует routing row, отдельный блок и изменения README.md/CLAUDE.md (`tasks.md:113-115`), но Eval — только `grep -q 'brief <topic>' commands/mb.md` (`:117`). Он пройдёт от комментария или строки без dispatch и вообще не читает README/CLAUDE.md. Это нарушает правило, что assert проверяет бизнес-факт (`rules/RULES.md:291-311`).

**Рекомендация:** Заменить одиночный grep структурным Bats-тестом всех трёх артефактов.

**Готовая правка:**

```
В Scope Task 4 добавить `tests/bats/test_mb_brief_docs.bats`. Заменить Eval на: «`bats tests/bats/test_mb_brief_docs.bats` — red: test file is materialized first; assertions fail because routing/block/pipeline entries are absent.» Testing: «Assert that the Routing table contains an exact `brief <topic>` row dispatching to `commands/brief.md`; the command section contains the exact C0 synopsis; both README.md and CLAUDE.md contain `brief → discuss → sdd → work`. Match complete rows/sections, not isolated `brief` tokens.»
```

#### [svp-brief] SVP-BRIEF-001 · edge-case · `.memory-bank/specs/svp-brief/requirements.md:56-57; .memory-bank/specs/svp-brief/design.md:70-72,92-104; .memory-bank/specs/svp-brief/tasks.md:25-29`

**Проблема:** PARTIAL: BRIEF-001 запретил тихое копирование, но результат «явного решения» для unsupported-файла не определён.

**Доказательство:** REQ-010 требует «explicit user decision before any copy happens» (`requirements.md:57`), C2 одновременно разрешает попадание в inputs только для `scan=clean` (`design.md:70-72`), а C5 лишь говорит «требует явного решения пользователя» (`design.md:96-98`). Task 1 трактует exit 2 как безусловную блокировку без механизма продолжения (`tasks.md:27-29`). Не определено, может ли решение разрешить небезопасную копию, исключить файл или только отменить операцию.

**Рекомендация:** Запретить override для неинспектируемого файла в MVP и определить единственные допустимые продолжения.

**Готовая правка:**

```
Заменить REQ-010 на: «- **REQ-010** (unwanted): If a source cannot be scanned because it is unreadable, binary, or unsupported, then the system shall abort before destination mutation, print `brief=blocked reason=scan_unsupported` on stdout and one `scan=unsupported path=<path>` line per source on stderr, and require a fresh invocation after the source is removed, converted, or excluded; an unsupported source shall never be copied in MVP.» В Scenario 4 заменить THEN на тот же abort/no-mutation/rerun контракт. В C5 записать: «scanner exit 2 maps to `/mb brief` exit 1; no override flag exists in MVP».
```

#### [svp-brief] SVP-BRIEF-002 · cross-slice · `.memory-bank/specs/svp-brief/design.md:85-98; .memory-bank/specs/svp-interview-upgrade/design.md:90-110; .memory-bank/specs/svp-interview-upgrade/tasks.md:96-115`

**Проблема:** PARTIAL: BRIEF-002 добавил blocked_by S1, но S7 вызывает несовместимый secret-scan контракт и неверно назначает владельца.

**Доказательство:** S1 фиксирует единственный CLI `scripts/mb-secret-scan.sh --policy transcript <candidate-file>` (`svp-interview-upgrade/design.md:90`) и прямо оставляет другие policies вне слайса (`:108-110`). Политика transcript игнорирует `<private>` и запрещает pragma (`:95-99`). S7 вызывает скрипт без `--policy` (`svp-brief/design.md:87-91`), принимает `mb-secret-ok` (`:92-95`), ошибочно утверждает, что добавляет отсутствовавший в S1 exit 2 (`:92`), и называет владельцем sdd-openspec-parity, хотя скрипт создаёт S1 Task 4 (`svp-interview-upgrade/tasks.md:96-115`).

**Рекомендация:** Расширять S1-owned CLI отдельной совместимой policy, не переопределяя transcript.

**Готовая правка:**

```
Заменить C5 первым абзацем: «S7 расширяет созданный S1 скрипт новой политикой и вызывает только `scripts/mb-secret-scan.sh --policy inputs <source-path>`. S1 владеет executable и policy `transcript`; S7 владеет policy `inputs`, семантика которой соответствует sdd-openspec-parity: `<private>` не исключается из scan, а `<!-- mb-secret-ok -->` подавляет только находку на своей или предыдущей строке. Общие exit codes остаются 0=clean, 1=blocked, 2=usage/read/unsupported». В Task 1 установить `Blocked-by: svp-interview-upgrade#4`, добавить в Scope `scripts/mb-secret-scan.sh, tests/bats/test_mb_secret_scan_inputs.bats` и удалить утверждения, что владельцем CLI является sdd-openspec-parity.
```

#### [svp-brief] SVP-BRIEF-003 · contract · `.memory-bank/specs/svp-brief/design.md:25-45; .memory-bank/specs/svp-brief/tasks.md:25-29; .memory-bank/context/svp-brief.md:70-72`

**Проблема:** PARTIAL: BRIEF-003 добавил C0, но `--update`, `--request-file` и `--auto` всё ещё требуют догадок.

**Доказательство:** Сигнатура C0 не содержит `--update` (`design.md:25`), однако существующий brief должен предлагать вызов с этим флагом и неописанным подтверждением (`:43-45`); Task 1 повторяет конфликт (`tasks.md:25-29`). Для `--request-file` не заданы regular-file/readability/empty-content ошибки, хотя такие правила подробно заданы только для `--input` (`design.md:31-38`). `--auto` записывает неопределённый `assumptions_note` (`:39-40`), которого нет ни в C1 frontmatter, ни среди девяти секций.

**Рекомендация:** Убрать update из MVP и полностью определить request-source и место auto-assumptions.

**Готовая правка:**

```
В C0 добавить: «`--request` MUST contain non-whitespace text. `--request-file` MUST name an existing readable non-symlink regular file whose content is non-whitespace; violation prints `error=request_unreadable path=<p>` or `error=request_empty` and exits 2 before writes. Under `--auto`, frontmatter MUST contain non-empty scalar `assumptions_note`; without `--auto` that key MUST be absent.» Заменить existing-topic bullet на: «If `briefs/<topic>/brief.md` exists, stdout is exactly `brief=exists path=briefs/<topic>/brief.md`, exit is 1, stderr is empty, and no file is changed. Update/versioning is out of scope.» Удалить все ссылки на `--update` и confirmation из context/tasks.
```

#### [svp-brief] SVP-BRIEF-004 · contract · `.memory-bank/specs/svp-brief/design.md:47-66; .memory-bank/specs/svp-brief/tasks.md:58-73`

**Проблема:** PARTIAL: BRIEF-004 уточнил валидатор, но error-протокол для frontmatter и нескольких нарушений остаётся неоднозначным.

**Доказательство:** C1 требует для каждого нарушения строку `error=<code> section=<name>` и порядок девяти секций (`design.md:59-61`), но `frontmatter_invalid` не имеет определённого `<name>` и позиции относительно section-errors. Не сказано, агрегируются ли несколько невалидных frontmatter-полей. Task 2 обещает фиксированный порядок (`tasks.md:59-62`), поэтому разные корректные на вид реализации дадут несовместимые потоки.

**Рекомендация:** Зафиксировать точные строки, агрегацию и глобальный порядок diagnostics.

**Готовая правка:**

```
Заменить stderr-блок C1 на: «Content diagnostics are emitted in this order: (1) at most one aggregate `error=frontmatter_invalid section=frontmatter`; (2) section diagnostics in the canonical nine-section order. For one section, `missing_section` or `duplicate_section` is emitted before `empty_essence|empty_goal`. Usage failures emit exactly `error=usage`; an existing but unreadable file emits exactly `error=io path=<path>`; both exit 2 and produce no stdout. Tests MUST assert the complete stdout, stderr and ordering for a fixture containing simultaneous frontmatter, missing-section and empty-section errors.»
```

#### [svp-brief] SVP-BRIEF-006 · eval · `.memory-bank/specs/svp-brief/tasks.md:11-45; .memory-bank/specs/svp-brief/requirements.md:32-39; .memory-bank/specs/svp-sdd-core/design.md:88-98`

**Проблема:** PARTIAL: BRIEF-006 заменил grep на Bats, но Task 1 не проверяет REQ-003/REQ-004, которые заявлены в Covers.

**Доказательство:** Task 1 покрывает REQ-003 и REQ-004 (`tasks.md:12`), однако перечисленные Bats-кейсы проверяют filesystem, scan, collision, exists и handoff (`:35-40`) — нет ни ясного intent без вопросов, ни неясного intent с максимум пятью вопросами, ни `--auto` с assumptions_note. Это оставляет два gated REQ без code-verifiable доказательства, вопреки eval-first контракту S2-C6 (`svp-sdd-core/design.md:88-98`).

**Рекомендация:** Добавить детерминированные structural contract assertions для prompt-команды и точный auto-кейс.

**Готовая правка:**

```
Дополнить Task 1 Testing: «`test_mb_brief_command.bats` MUST structurally assert in `commands/brief.md` the complete branch: after input analysis, empty/unclear Essence or Goal invokes at most five light questions; when both are clear the AskUserQuestion branch is skipped; `--auto` always skips it and requires non-empty `assumptions_note`. Assertions MUST match the complete branch clauses, not isolated words. Add fixtures/assertions mapped to REQ-003 and REQ-004 in test names.» В Eval declaration перечислить эти три кейса.
```

#### [svp-contract-test-loop] R2-002 · feasibility · `.memory-bank/specs/svp-contract-test-loop/tasks.md:119`

**Проблема:** Task 5 расширяет несуществующий `commands/verify.md`.

**Доказательство:** Task 5 Scope и действия называют `commands/verify.md` (`tasks.md:119,123`), design повторяет этот путь (`design.md:16`). Фактический список `commands/` такого файла не содержит; действующий `/mb verify` расположен в `commands/mb.md:497-534`, а per-item verify — в `commands/work.md:366-389`. Контекст также ошибочно заявляет существование файла (`context/svp-contract-test-loop.md:52`).

**Рекомендация:** Привязать изменение к реальным entry points репозитория.

**Готовая правка:**

```
Заменить во всех четырёх местах `commands/verify.md` на `commands/mb.md § verify`; Scope Task 5 записать как `commands/mb.md, commands/work.md, scripts/mb-contract-gate.sh, tests/bats/test_mb_verify_contract_gate.bats`. В design.md Architecture п.3 написать: `commands/mb.md § verify и commands/work.md §5c вызывают scripts/mb-contract-gate.sh verify`.
```

#### [svp-contract-test-loop] R2-003 · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:38`

**Проблема:** Резолвер не может реализовать exit 1 для отсутствующего «объявленного в спеке» источника.

**Доказательство:** CLI принимает только `--repo`, `--mb`, `--json` (`design.md:38`), но exit 1 зависит от источника, объявленного в конкретной спеке (`design.md:44-45`, REQ-017). Ни путь к спеке, ни повторяемый аргумент источника в интерфейсе не предусмотрены. Scenario 9 требует именно этот путь (`requirements.md:158-165`).

**Рекомендация:** Добавить явный вход для declared sources и определить разницу между discovery и validation.

**Готовая правка:**

```
Заменить C2 synopsis на `scripts/mb-rules-resolve.sh [--repo PATH] [--mb BANK] [--spec SPEC_DIR] [--declared-source PATH ...] [--json]`. Добавить: `Без --spec/--declared-source команда выполняет discovery. С --spec она читает rule_source entries из design.md § Quality DoD; --declared-source добавляет явные entries. Каждый declared path обязан существовать: иначе stdout пуст, stderr rule_source_missing=<path>, exit 1; fallback в этом режиме запрещён. Exit 2 — usage/malformed Quality DoD.`
```

#### [svp-contract-test-loop] R2-004 · contract · `.memory-bank/specs/svp-contract-test-loop/tasks.md:39`

**Проблема:** Парсер `layers` не имеет определённого API, входного файла или выходной схемы; Scope также не разрешает создание дочернего модуля.

**Доказательство:** C1 говорит лишь о frontmatter «спеки» (`design.md:23-36`), хотя triple имеет несколько файлов. Task 2 назначает `scripts/mb_work_items.py`, который фактически принимает только путь к `tasks.md` и возвращает `list[WorkItem]` (`scripts/mb_work_items.py:4-16`); его модель не содержит layers (`scripts/mb_work_items.py:54-68`). Scope `memory_bank_skill/` (`tasks.md:39`) — literal directory, который не покрывает дочерний файл при S2 glob-семантике (`svp-sdd-core/design.md:32-35`).

**Рекомендация:** Зафиксировать канонический owner frontmatter и отдельный typed API layers.

**Готовая правка:**

```
В C1 добавить: `Канонический блок layers хранится только в requirements.md frontmatter.` В design.md добавить интерфейс: `memory_bank_skill.spec_layers.read_spec_layers(requirements_path: Path, pipeline_path: Path) -> SpecLayers`, где `SpecLayers` содержит три bool и три optional reason; ошибки возвращаются как `SpecLayersError(code, field)`. CLI: `python3 -m memory_bank_skill.spec_layers --requirements PATH --pipeline PATH --json`; stdout — `{"contract_first":bool,"integration_tests":bool,"e2e_tests":bool,"reasons":{...},"source":"spec|pipeline"}`, exit 0/1/2. Scope Task 2 заменить на `memory_bank_skill/spec_layers.py, tests/pytest/test_spec_layers.py`; `mb_work_items.py` не менять.
```

#### [svp-contract-test-loop] R2-005 · consistency · `.memory-bank/specs/svp-contract-test-loop/requirements.md:26`

**Проблема:** Условие «есть хотя бы один gated REQ» потеряно в design и validator task.

**Доказательство:** REQ-001 требует contract task только при `contract_first: true` и наличии gated requirement (`requirements.md:26`). C3 требует её при любом `contract_first: true` (`design.md:50-53`), Task 3 повторяет безусловный гейт (`tasks.md:68-71`), тогда как Risks снова утверждает, что без gated REQ задача не обязательна (`design.md:102-103`). Термин gated в S8 также не определён; родитель определяет его как SHALL/MUST (`context/sdd-vision-pipeline.md:41`).

**Рекомендация:** Сделать predicate gated формальной частью C3 и validator tests.

**Готовая правка:**

```
Заменить C3 условие на: `has_gated_req=true, если requirements.md содержит хотя бы одну EARS-дефиницию с нормативным SHALL или MUST; SHOULD/MAY не gated. Валидатор требует ровно одну Layer: contract только при contract_first=true AND has_gated_req=true. При contract_first=true AND has_gated_req=false контрактная задача не требуется и validator печатает contract_layer=not_applicable.` Добавить обе ветки в Task 3 Testing.
```

#### [svp-contract-test-loop] R2-006 · cross-slice · `.memory-bank/specs/svp-contract-test-loop/design.md:72`

**Проблема:** Заявленная совместимость `fake_red` с S5 не соответствует интерфейсу S5 и может ослабить hard stop.

**Доказательство:** S8 публикует отдельный объект `contract_task.status=fake_red` и утверждает, что новый сигнал не вводится (`design.md:72-76`). S5 принимает только `--eval-status green|red|absent` (`svp-adapt-escalation/design.md:44,59`) и envelope `complexity_escalation` (`svp-adapt-escalation/design.md:208-222`); `fake_red` отсутствует. Более того, S5 поднимает `eval_not_green` лишь после `max_cycles` (`svp-adapt-escalation/design.md:86`), а REQ-005 требует немедленного провала.

**Рекомендация:** Не маршрутизировать fake_red через ADaPT; оставить его локальным немедленным гейтом.

**Готовая правка:**

```
Заменить C7 заголовок и последнюю строку на: `### C7. fake_red verdict (consumer — /mb work)` и `fake_red является локальным hard stop контрактной задачи: item остаётся open, implement не диспатчится. Он не преобразуется в complexity_escalation и не проходит через решения continue/stub_continue S5. При последующих ручных попытках S5 может видеть только общий eval_status=red по своему существующему контракту.`
```

#### [svp-contract-test-loop] R2-007 · parent-decision · `.memory-bank/specs/sdd-vision-pipeline/tasks.md:181`

**Проблема:** Исполняемый umbrella DAG разрешает S8 до S2, вопреки parent design и roadmap.

**Доказательство:** S8 заявляет `blocked_by: [svp-sdd-core]` (`requirements.md:5`). Parent design и roadmap ставят S2 перед S8 (`sdd-vision-pipeline/design.md:35,38`; `roadmap.md:91-97`). Но umbrella Task 9 имеет `Blocked-by: 3` (`sdd-vision-pipeline/tasks.md:174-181`), где Task 3 — S4, а S2 — Task 4 (`sdd-vision-pipeline/tasks.md:72-78`). Порядок в преамбуле также ставит S6 перед S8 (`sdd-vision-pipeline/tasks.md:6`).

**Рекомендация:** Исправить source-of-truth umbrella tasks до исполнения группы.

**Готовая правка:**

```
В `.memory-bank/specs/sdd-vision-pipeline/tasks.md` заменить у Task 9 `**Blocked-by:** 3` на `**Blocked-by:** 4`. Строку порядка заменить на `T1 сразу; далее T2 (S1) → T8 (S7) → T3 (S4) → T4 (S2) → T9 (S8) → T5 (S6) → T7 (S3) → T6 (S5)`.
```

#### [svp-contract-test-loop] R2-008 · consistency · `.memory-bank/specs/svp-contract-test-loop/tasks.md:5`

**Проблема:** Локальный Blocked-by DAG не кодирует заявленный порядок и допускает конкурентную правку общих файлов.

**Доказательство:** Преамбула заявляет строгий порядок 1→2→3→4→5→6 (`tasks.md:5`). Фактически T1 и T2 оба unblocked (`tasks.md:13,38`), T5 зависит только от T3 (`tasks.md:118`), T6 — только от T1 (`tasks.md:144`). T4 и T6 обе затрагивают `references/pipeline.default.yaml` (`tasks.md:91,145`), а T5 и T6 обе меняют `commands/work.md` (`tasks.md:119,145`). Кроме того, T4 требует изменение validator config (`tasks.md:99,108`), но `scripts/mb-pipeline-validate.sh` отсутствует в Scope.

**Рекомендация:** Согласовать текстовый порядок, DAG и Scope так, чтобы shared writers были сериализованы.

**Готовая правка:**

```
Преамбулу заменить на `Порядок по Blocked-by: {1,2} → 3 → 4 → 5 → 6 → 7 → 8.` Установить: T3 `Blocked-by: 2`; T4 `Blocked-by: 1, 3`; T5 `Blocked-by: 4`; T6 `Blocked-by: 5`; T7 `Blocked-by: 6`; T8 `Blocked-by: 7`. В Scope T4 добавить `scripts/mb-pipeline-validate.sh, tests/bats/test_mb_pipeline_sdd_layers.bats`.
```

#### [svp-contract-test-loop] R2-009 · eval · `.memory-bank/specs/svp-contract-test-loop/tasks.md:22`

**Проблема:** Заявленная батарея red-прогонов не проверяет red-условия: все Eval test targets отсутствуют.

**Доказательство:** Все восемь задач ссылаются на новые test-файлы (`tasks.md:22,47,73,101,128,153,179,206`); проверка файлов показала, что ни один не существует. Повторный pytest-прогон без capture/cache завершился exit 4 `file or directory not found`, а не заявленным behavioral red. Это не удовлетворяет S2-C6: посторонний сбой не принимается (`svp-sdd-core/design.md:90-95`) и S2-C8 требует совпадения red-condition (`svp-sdd-core/design.md:120-121`).

**Рекомендация:** Развести generation-time проверку декларации и work-time semantic red; отсутствие test-файла не считать red evidence.

**Готовая правка:**

```
В `svp-sdd-core/design.md` C8 п.4 и `commands/sdd.md:156-160` записать: `На generation self-check Eval-команда проверяется на синтаксис, допустимый runner и соответствие Scope; отсутствие ещё не материализованного test-файла не считается red. В /mb work исполнитель сначала пишет Eval-тест, затем оркестратор запускает его до product implementation; только совпавший semantic red выставляет red_observed=true/red_match=true.` В roadmap/status S8 заменить утверждение `eval-гейты подтверждённо красные` на `Eval declarations structurally checked; semantic red pending work`.
```

#### [svp-contract-test-loop] R2-010 · eval · `.memory-bank/specs/svp-contract-test-loop/tasks.md:101`

**Проблема:** T4/T7 обещают кодом проверить генерацию `/mb sdd`, но генератор остаётся LLM-промптом без deterministic seam.

**Доказательство:** T4 Eval требует генерацию task order на fixture (`tasks.md:101-104`), T7 — реальную цепочку `/mb sdd`→validator→parser (`tasks.md:174-179`). Родитель фиксирует, что полный generator принадлежит `commands/sdd.md`, а `mb-sdd.sh` остаётся scaffold-only (`svp-sdd-core/design.md:100-105`). Следовательно pytest либо вызывает LLM, либо лишь grep-ит prompt/template и не доказывает REQ-002/007/008/009.

**Рекомендация:** Вынести детерминированную материализацию layer-блоков в callable seam, оставив оркестратору запись triple.

**Готовая правка:**

```
Добавить в design.md интерфейс: `python3 scripts/mb-sdd-layers-render.py --requirements PATH --tasks PATH --pipeline PATH --rules-json PATH` печатает новый tasks.md в stdout и Quality DoD JSON в stderr; файлов не пишет. Exit 0=rendered, 1=invalid layers/scenario mapping, 2=usage. commands/sdd.md вызывает renderer и только затем оркестратор пишет triple. Добавить script в Scope T4 и использовать его напрямую в T4/T7 Eval.
```

#### [svp-contract-test-loop] R2-011 · consistency · `.memory-bank/specs/svp-contract-test-loop/tasks.md:182`

**Проблема:** Собственные integration/e2e задачи S8 нарушают C4: используют сокращения и номера вместо точных `test_id`.

**Доказательство:** C4 требует перечислять `test_id` формата extractor в DoD (`design.md:57-59`). T7 Testing содержит `REQ-001__…` и другие ellipsis-placeholder (`tasks.md:182`), а DoD перечисляет только номера сценариев (`tasks.md:186`). T8 повторяет это (`tasks.md:209-213`). Извлечённые стабильные IDs доступны и уникальны.

**Рекомендация:** Заменить сокращения точными extractor IDs в Testing и DoD.

**Готовая правка:**

```
В Task 7 записать: `DoD scenario test_ids: REQ-001__contract_task_comes_first, REQ-007__two_test_layers_at_the_end_of_the_spec, REQ-011__fast_mode_refusal_is_recorded, REQ-012__legacy_spec_read_without_mutation, REQ-015__project_rules_beat_bank_rules, REQ-017__missing_rule_source_fails_loudly.` В Task 8: `DoD scenario test_ids: REQ-004__fake_red_fails_the_contract_task, REQ-003__checker_without_a_negative_fixture_rejected, REQ-006__unobservable_requirement_escalates, REQ-020__verify_runs_the_contract_checkers.` Удалить все `…`.
```

#### [svp-contract-test-loop] R2-012 · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:67`

**Проблема:** Quality DoD delivery не привязана к реальному payload assembler, поэтому внешние reviewer/judge её не гарантированно получат.

**Доказательство:** C6 ограничивается фразой «review_rubric дополняется при dispatch» без формата и точки сборки (`design.md:67-70`). Task 6 меняет agent prompts и pipeline default, но не реальный reviewer payload assembler (`tasks.md:145-156`). Фактически reviewer payload строит `scripts/mb-review.sh` (`commands/work.md:391-409`), а orchestrated reviewer не перечитывает файлы (`agents/mb-reviewer.md:36-44`). Judge получает отдельный prompt (`commands/work.md:425-435`).

**Рекомендация:** Определить эпизодическую сборку одного нормализованного Quality DoD-блока во всех трёх payload; project pipeline не мутировать.

**Готовая правка:**

```
Заменить C6 на: `mb-rules-resolve.sh --spec <spec-dir> --json формирует один canonical JSON. Оркестратор рендерит его как раздел ## Quality DoD с отсортированными строками - [kind] path и checker command. Тот же байтовый блок: (1) добавляется в implementer prompt commands/work.md §5a; (2) передаётся scripts/mb-review.sh --quality-dod-json <path|-> и попадает в ## Plan context; (3) добавляется в judge prompt §5e. pipeline.yaml и pipeline.default.yaml не мутируются.` В Scope Task 6 добавить `scripts/mb-review.sh`; удалить `references/pipeline.default.yaml`; Eval должен сравнить sha256 трёх rendered blocks.
```

#### [svp-docs-wiki] F-004 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:40-69; .memory-bank/specs/svp-docs-wiki/tasks.md:104-108,240-243`

**Проблема:** PARTIAL: F-004 — CLI/state contract стал подробнее, но остаётся внутренне противоречивым и не определяет writer для page metadata.

**Доказательство:** State содержит `pages.<slug>.source_files/updated_at` в design.md:60-62, однако `write-page` принимает только slug и Markdown в design.md:42, `set-sha` принимает только SHA в design.md:45, а state «пишет только set-sha» в design.md:66-68. Кроме того, общий контракт относит malformed slug к exit 2 в design.md:48-50, тогда как T3 требует exit 5 в tasks.md:104-106. `--docs-path` объявлен необязательным с default resolution в design.md:33,73-76, но lint считает его отсутствие malformed CLI в design.md:177-179 и tasks.md:240-243.

**Рекомендация:** Определить единственную финальную запись полного state и унифицировать usage-коды и optional path semantics.

**Готовая правка:**

```
Заменить строку `set-sha` в C1 на: `set-sha <sha>` — stdin обязан содержать JSON `{"pages":{"<slug>":{"source_files":["<repo-relative>"],"updated_at":"<RFC3339>"}}}`; команда атомарно записывает полный state C2 и печатает `{"sha":"<sha>","updated_at":"<RFC3339>","pages":<n>}`. В C2 добавить: `Оркестратор накапливает page metadata из валидированных agent results и передаёт полный pages map в финальный set-sha; никакая другая команда state не изменяет.` В T3 заменить `невалидный slug … exit 5` на `exit 2`. В C8/T7 заменить пример malformed CLI `отсутствующий --docs-path` на `явно переданный invalid --docs-path`; отсутствие флага обязано использовать C3 precedence/default.
```

#### [svp-docs-wiki] F-005 · edge-case · `.memory-bank/specs/svp-docs-wiki/design.md:98-123`

**Проблема:** PARTIAL: F-005 — повтор после crash дублирует append-only log, а утверждение об автоматическом освобождении mkdir-lock при смерти процесса неверно.

**Доказательство:** C5 предписывает pages→log→index→state и повтор того же диапазона после любого сбоя до set-sha в design.md:110-123. Pages перезаписываются, но log является append-only по design.md:92, поэтому crash после log-append создаст вторую запись при replay. Design.md:117 утверждает, что смерть процесса освобождает lock, хотя каталог, созданный mkdir, после завершения процесса остаётся. Автоматическое снятие любого lock старше часа в design.md:102-104 также допускает второй writer поверх живого долгого запуска.

**Рекомендация:** Сделать log replay идемпотентным и определить owner-aware lock recovery.

**Готовая правка:**

```
В C5 записать: `run_id = "<base_sha>..<target_sha>" фиксируется до диспатча. log-append принимает обязательный --run-id; log entry включает run_id в description и является no-op с {"appended":false} при уже существующей записи этого run_id. Повтор до set-sha поэтому не дублирует log.` Заменить lock-текст на: `После mkdir оркестратор атомарно пишет owner.json {pid,host,started_at,base_sha,target_sha}. При конфликте lock не снимается, пока локальный owner pid жив; мёртвый owner снимается только после stale timeout 1h. SIGKILL оставляет каталог, поэтому recovery всегда проходит через owner.json.` Добавить T4 тесты crash после log и живого lock старше часа.
```

#### [svp-docs-wiki] F-006 · contract · `.memory-bank/context/svp-docs-wiki.md:25,60-63; .memory-bank/specs/svp-docs-wiki/design.md:78-83`

**Проблема:** PARTIAL: F-006 — path_mismatch обнаруживается только для git-tracked state и молча пропускает валидный untracked state.

**Доказательство:** Контекст безусловно требует остановку, если state не перенесён вместе с каталогом, в context.md:25,60-63. Реализация C3 ищет только «среди git-tracked файлов» в design.md:78-83. После bootstrap до первого commit либо при ignored/generated wiki старый state будет untracked; смена docs.path тогда даст второй bootstrap вместо требуемого path_mismatch.

**Рекомендация:** Искать state независимо от git index, сохраняя containment и детерминированность.

**Готовая правка:**

```
Заменить C3 scan-контракт на: `Перед bootstrap resolver выполняет отсортированный filesystem scan repo root по имени .mb-docs-state.json, исключая .git/**, resolved docs.path и пути, чей realpath выходит за repo. Scan включает tracked, untracked и ignored файлы. Один кандидат → error=path_mismatch; несколько → error=ambiguous_state candidates=<sorted-csv>; ни одного → bootstrap.` В T1 добавить отдельные тесты tracked и untracked old state.
```

#### [svp-docs-wiki] F-007 · parent-decision · `.memory-bank/specs/svp-docs-wiki/design.md:148-156; references/pipeline.default.yaml:10-34; scripts/mb-agent-caps.sh:13-20,241-244`

**Проблема:** PARTIAL: F-007 — поведение деградации описано, но отсутствует исполнимый контракт определения транспорта и требуемого model tier.

**Доказательство:** C7 говорит об «отсутствующем транспорте» или «недоступном tier» в design.md:153-156, не называя resolver, его аргументы, output или exit. Фактический resolver `mb-agent-caps.sh resolve --role` печатает key=value в scripts/mb-agent-caps.sh:13-20 и отклоняет роль без model в :241-244. В текущих roles нет `docs_author`/`docs_synthesizer` в references/pipeline.default.yaml:10-34, а задачи S6 добавляют только agent prompt files и docs.path. Поэтому Haiku/Sonnet resolution и platform_limited остаются на усмотрение исполнителя.

**Рекомендация:** Привязать C7 к существующему capability resolver и зарегистрировать обе роли.

**Готовая правка:**

```
Добавить в C7: `До lock и любой записи оркестратор вызывает bash scripts/mb-agent-caps.sh resolve --role docs_author --mb <bank>, затем resolve --role docs_synthesizer --mb <bank>, и принимает только stdout transport/model/thinking/substituted. Любой non-zero или model другого tier завершает /mb docs с exit 6 и stderr result=platform_limited platform_limited=subagent-dispatch role=<role>; writers не вызываются.` В C9/T6 добавить roles `docs_author: {agent: mb-docs-author, model: haiku}` и `docs_synthesizer: {agent: mb-docs-synthesizer, model: sonnet}`, а также fallback mapping haiku/sonnet. Добавить MB_CAPS_FIXTURE-тесты success, missing transport и missing tier.
```

#### [svp-docs-wiki] F-008 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:125-146; .memory-bank/specs/svp-docs-wiki/design.md:42-45`

**Проблема:** PARTIAL: F-008 — JSON-схемы агентов появились, но не совместимы с writer API и не задают перенос результатов в конечную wiki.

**Доказательство:** Author возвращает title/source_files/wikilinks в design.md:127-133, но write-page принимает только slug и Markdown в :42. Synthesizer возвращает index_entries, log_entry `{sha,pages,summary}` и отдельные contradictions в :135-140; `index` самостоятельно регенерирует каталог из pages в :44, `log-append` принимает `{op,desc}` в :43, а операции применения contradictions к body нет. Тем самым index_entries не имеют потребителя, log fields не совпадают, contradictions не попадают на страницу, а source_files не попадают в state.

**Рекомендация:** Сделать synthesizer output финальным writer-ready результатом и удалить непотребляемые поля.

**Готовая правка:**

```
Заменить C6 schema synthesizer на `{"pages":[{"slug":"string","title":"string","body_markdown":"string","source_files":["string"],"wikilinks":["string"]}],"log_entry":{"op":"ingest|bootstrap","description":"string"}}`. Добавить: `pages — финальные страницы после cross-page pass; все найденные противоречия уже отрендерены внутри body_markdown в секции ## Contradictions. Оркестратор вызывает write-page для каждого body, строит pages metadata для финального set-sha, вызывает log-append с op/description и затем index. index_entries и отдельный contradictions array удалены как не имеющие consumer.` Обновить T5 exact-schema test соответственно.
```

#### [svp-docs-wiki] F-010 · eval · `.memory-bank/specs/svp-docs-wiki/design.md:164-179; .memory-bank/specs/svp-docs-wiki/tasks.md:228-246`

**Проблема:** PARTIAL: F-010 — exact exit/code assertions добавлены, но source_leakage невозможно вычислить из lint input или wiki-фикстуры.

**Доказательство:** `source_leakage` определяется как исторический факт «docs_store.py записал что-либо вне…» в design.md:175. Команда lint получает только resolved docs path и состояние файлов после записи; manifest сделанных writes, baseline или audit log контрактом не передаются. T7 одновременно требует представить каждое нарушение статической `wiki-broken` fixture в tasks.md:235-243. Более того, разрешённое множество в design.md:175 не включает легитимный state и lock этого же прогона.

**Рекомендация:** Убрать непроверяемую историю записи из структурного lint и проверять immutable sources на orchestration boundary.

**Готовая правка:**

```
Удалить `source_leakage` из C8, T7 и списка восьми кодов; оставить семь структурно наблюдаемых кодов. В T4 добавить интеграционный тест Scenario 6: до прогона вычислить SHA-256 для graph.json, `<bank>/codebase/wiki/**` и изменяемых source files, после прогона сравнить hashes и дополнительно утверждать, что фактический write manifest содержит только `<docs-path>/pages/**`, `index.md`, `log.md`, `.mb-docs-state.json` и временный `.mb-docs.lock`. Любое отклонение должно завершать run до set-sha.
```

#### [svp-docs-wiki] R2-001 · parent-decision · `.memory-bank/specs/svp-docs-wiki/tasks.md:120-136; .memory-bank/specs/svp-sdd-core/design.md:32-36`

**Проблема:** T4 гарантированно нарушит заявленный Scope при подключении CLI dispatcher.

**Доказательство:** T4 Scope ограничен `commands/mb.md`, test и fixtures в tasks.md:120-122, но сама задача требует подключить недостающие subcommands и финально собрать `scripts/mb-docs.py` в :135-136. S2-C1 требует, чтобы Scope перечислял repo-relative изменяемые файлы, а runtime сверяет фактический diff, в svp-sdd-core/design.md:32-36. Реализация по тексту задачи поэтому вызовет scope escalation.

**Рекомендация:** Добавить все исполняемые orchestration/dispatcher-файлы в T4 Scope.

**Готовая правка:**

```
Заменить T4 поле на `**Scope:** commands/mb.md, scripts/mb-docs.py, memory_bank_skill/docs_run.py, tests/pytest/test_mb_docs_command.py, tests/fixtures/docs-repo/**`. Если `docs_run.py` не будет принят как seam, удалить его из списка, но `scripts/mb-docs.py` обязателен при сохранении текущего What to do.
```

#### [svp-docs-wiki] R2-002 · feasibility · `.memory-bank/specs/svp-docs-wiki/design.md:10-23; .memory-bank/specs/svp-docs-wiki/tasks.md:114-149`

**Проблема:** Behavioral Eval T4 не имеет исполняемого orchestration seam: вся run-логика существует только как инструкция в commands/mb.md.

**Доказательство:** Architecture перечисляет executable модули state/ingest/store/lint, но сам pipeline помещает в `/mb docs` prompt orchestration в design.md:10-23. T4 изменяет только command Markdown и тест, однако Eval обещает pytest-проверки порядка writes, crash replay, lock, dirty worktree и platform_limited в tasks.md:124-146. Pytest не может вызвать Markdown-команду как функцию; без нового seam он сможет проверить лишь наличие текста или протестировать другую, не production-wired последовательность.

**Рекомендация:** Вынести детерминированную state machine одного run в вызываемый модуль с инъецируемой границей host dispatch.

**Готовая правка:**

```
Добавить в design Interfaces: `memory_bank_skill.docs_run.run_docs(config: DocsRunConfig, dispatcher: DocsDispatchPort) -> DocsRunResult`. `DocsDispatchPort` содержит один метод `dispatch(*, role: str, model: str, payload: dict) -> dict`. `run_docs` единолично реализует lock→snapshot→packs→dispatch→validation→pages→log→index→lint→set-sha; `commands/mb.md` только создаёт host adapter и вызывает seam. Добавить `memory_bank_skill/docs_run.py` в T4 Scope. T4 pytest обязан вызывать именно `run_docs` с in-memory fake dispatcher и fault injection после каждого write step.
```

#### [svp-docs-wiki] R2-003 · eval · `.memory-bank/specs/svp-docs-wiki/tasks.md:184-215; .memory-bank/specs/svp-docs-wiki/tasks.md:117-146`

**Проблема:** REQ-007 проверяется только на уровне config/resolver; фактическая генерация в выбранный каталог оставлена ручной.

**Доказательство:** T6 Eval запускает Bats для docs.path/validator в tasks.md:206, а Scenario 5 прямо обозначен как «воспроизведён вручную» в :208-212. T4 behavioral test не покрывает REQ-007, его Covers содержит только REQ-001/002/011 в :117-119 и он не blocked by T6. Поэтому команда может корректно резолвить project-wiki/, но продолжать писать в default docs/, а все кодовые Eval останутся зелёными.

**Рекомендация:** Добавить end-to-end path assertion в production orchestration test и упорядочить T6 перед T4.

**Готовая правка:**

```
Изменить T4 на `**Covers:** REQ-001, REQ-002, REQ-007, REQ-011` и `**Blocked-by:** 1, 2, 3, 5, 6, 7`; в верхнем порядке Stage 2 заменить `4 → 6` на `6 → 4`. В T4 Testing добавить: `pipeline docs.path=project-wiki/; snapshot docs/**; run_docs пишет page/index/log/state только под project-wiki/**; docs/** byte-identical после прогона`. Удалить формулировку «воспроизведён вручную» из T6.
```

#### [svp-docs-wiki] R2-004 · consistency · `.memory-bank/context/svp-docs-wiki.md:64-67; .memory-bank/specs/svp-docs-wiki/requirements.md:18-57`

**Проблема:** Решение об удалённых сущностях потеряно между context и spec triple.

**Доказательство:** Context фиксирует: «Страница удалённой сущности — помечается deprecated, не удаляется молча» в context.md:65. Среди REQ-001…REQ-011 в requirements.md:18-57 нет требования для deletion, C10 не передаёт deletion status, задачи и сценарии его не тестируют. Реализующий агент может оставить ложную активную страницу либо удалить её, нарушив исходное решение.

**Рекомендация:** Формализовать уже принятое deletion-поведение без расширения продуктового scope.

**Готовая правка:**

```
Добавить `REQ-012 (unwanted): If the target diff deletes an entity that has a wiki page, then the system shall retain that page, mark it deprecated with deletion evidence and target SHA, and shall not silently delete it or leave it active.` В C10 добавить `deleted_files:["<repo-relative>"]`. Добавить сценарий GIVEN существующая page + deleted source / WHEN run / THEN page сохранена и содержит `Status: deprecated` и target SHA. Добавить REQ-012 в Covers T2 и T4 и кодовый T4 test.
```

#### [svp-interview-upgrade] R2-001 · eval · `.memory-bank/specs/svp-interview-upgrade/tasks.md:30`

**Проблема:** Новые red-декларации несовместимы с родительским eval-first протоколом и будут отклонены как fake/foreign red.

**Доказательство:** Все Eval описывают red через отсутствие тестового файла: `tasks.md:30,57,83,112,139,165`. Но сама спека требует сначала написать Bats-файл (`design.md:4`, `tasks.md:32`), а S2-C6 требует «материализовать и запустить» Eval и признаёт red только при совпадении с заявленным условием (`svp-sdd-core/design.md:90-95`). После материализации тестовый файл уже существует, поэтому заявленное условие «файл отсутствует» наблюдаться не может.

**Рекомендация:** Описывать red после материализации теста: конкретная assertion должна падать из-за отсутствующей реализации или обязательного контрактного блока.

**Готовая правка:**

```
Во всех шести `**Eval:**` удалить фразу `файл теста отсутствует → bats exit ≠ 0`. Записать: T1 — `red: Bats-файлы материализованы; assertions падают из-за отсутствующих C8 script/rule 11/rule 14/template`; T2 — `red: падают assertions final-gate, batch degradation и partial-answer`; T3 — `red: test file exists, invocation of missing mb-estimate-check.sh fails the expected script-present assertion`; T4 — `red: падают scanner/transcript-mode/two-phase-write assertions`; T5 — `red: падают glossary mutation/context-output assertions`; T6 — `red: падает flag-matrix/assumptions contract`. Те же формулировки перенести в таблицу `design.md:166-173`.
```

#### [svp-interview-upgrade] R2-002 · feasibility · `.memory-bank/specs/svp-interview-upgrade/tasks.md:132`

**Проблема:** Task 5 не может выполнить собственный DoD внутри объявленного Scope.

**Доказательство:** T5 Scope содержит только `commands/discuss.md`, `references/templates.md` и тест (`tasks.md:132`), но задача требует добавить строку в `/mb context`-выдачу (`tasks.md:137,146`). Фактическую выдачу собирает `scripts/mb-context.sh` (`scripts/mb-context.sh:33-89`); этот файл и даже `commands/mb.md` отсутствуют в Scope. По S2-C1 фактический diff должен соответствовать declared Scope (`svp-sdd-core/design.md:32-36`).

**Рекомендация:** Добавить реальный writer context-выдачи в Scope и проверять его поведение на банке с glossary и без него.

**Готовая правка:**

```
Заменить T5 Scope на `commands/discuss.md, references/templates.md, scripts/mb-context.sh, tests/bats/test_discuss_glossary.bats`. В Testing добавить: «fixture bank без glossary.md → output byte-identical текущему; fixture bank с glossary.md → ровно одна строка `Glossary: <path>` и первая непустая строка/ссылка на файл; повторный вызов не меняет банк».
```

#### [svp-interview-upgrade] R2-003 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:100`

**Проблема:** Secret scanner не фиксирует допустимые значения `<pattern>` и порядок нескольких findings.

**Доказательство:** C5 обещает точный stderr `<file>:<line>:<pattern>` (`design.md:100-102`), но `<pattern>` нигде не определён: возможны `EMAIL_RE`, `email`, `APIKEY_RE`, конкретный regex или совпавший текст. Не определён и порядок нескольких findings. T4 ожидает этот формат (`tasks.md:115`), поэтому автор теста и автор реализации вынуждены независимо угадывать значения.

**Рекомендация:** Сделать reason labels и ordering частью публичного CLI-контракта.

**Готовая правка:**

```
Дополнить C5: «`pattern` is exactly `email` or `api_key`. Findings are emitted in ascending `(line, column)` order; multiple findings on one line produce separate stderr lines. Private-span masking preserves original line numbers. Matched secret text is never printed. For blocked input stdout contains exactly one `scan=blocked` line.» Добавить Bats-кейсы для email+API key в одном файле, двух findings на одной строке и проверки отсутствия самого секрета в stderr.
```

#### [svp-interview-upgrade] SVP-IU-002 · eval · `.memory-bank/specs/svp-interview-upgrade/design.md:159`

**Проблема:** PARTIAL: Bats заменили inline-grep, но пять задач всё ещё проверяют текст prompt-файла вместо заявленного поведения.

**Доказательство:** `design.md:180` прямо признаёт: «Prompt-слой в принципе не исполняется в bats — структурные тесты доказывают только текст/структуру», а Scenarios остаются ручными. `tasks.md:60`, `tasks.md:117`, `tasks.md:142` и `tasks.md:168` требуют главным образом co-occurrence слов/фраз. Например, T5 принимает REQ-017/018 по соседству `glossary.md`/«немедлен» и `конфликт`/`challenge`, не проверяя создание/обновление файла и блокировку конфликтного требования.

**Рекомендация:** Для prompt-as-code определить строгий структурный контракт с негативными mutation fixtures; файловые эффекты проверять реальными helper-вызовами на временном банке.

**Готовая правка:**

```
Добавить в `design.md` § Eval declarations: «Prompt-backed Eval MUST parse the named section/rule, assert every normative clause in that same ordered block, and run negative mutation fixtures where removal or alteration of each clause makes the test fail. A bare word/co-occurrence assertion is forbidden. Requirements with filesystem effects MUST additionally invoke the responsible deterministic helper against a fixture bank.» В T1/T2/T4/T5/T6 заменить текущие co-occurrence-пункты на точные section-parser assertions и mutation fixtures; для T5 добавить fixture-run `mb-context.sh` и проверку фактического glossary-файла.
```

#### [svp-interview-upgrade] SVP-IU-003 · cross-slice · `.memory-bank/specs/svp-brief/design.md:85`

**Проблема:** PARTIAL: базовый scanner-контракт S1 определён, но его первый потребитель S7 вызывает другой CLI и называет другого владельца.

**Доказательство:** S1 определяет только `scripts/mb-secret-scan.sh --policy transcript <candidate-file>` и объявляет владельцем текущий слайс (`svp-interview-upgrade/design.md:90-110`). S7, который явно `blocked_by: [svp-interview-upgrade]`, вызывает `scripts/mb-secret-scan.sh <source-path>` без `--policy`, утверждает, что это «тот же CLI-контракт», и называет владельцем `sdd-openspec-parity` (`svp-brief/design.md:85-101`). Фактически `sdd-openspec-parity` расширяет внутренний `mb-spec-validate.sh`, а общего CLI не создаёт (`sdd-openspec-parity/tasks.md:118-136`).

**Рекомендация:** Зафиксировать S1 как владельца базового CLI, а S7 — как владельца расширения policy `inputs`, сохранив межслайсовую зависимость S7→S1.

**Готовая правка:**

```
В `svp-brief/design.md` C5 заменить вызов на `scripts/mb-secret-scan.sh --policy inputs <source-path>` и текст владельца на: «S1 owns the base CLI and transcript policy; S7 extends the same CLI with policy inputs». В Task 1 S7 добавить в Scope `scripts/mb-secret-scan.sh, tests/bats/test_mb_secret_scan_inputs.bats` и определить для `inputs`: `<private>` не подавляет finding, `<!-- mb-secret-ok -->` на/над строкой подавляет только эту строку, unsupported/binary → `scan=unsupported`, exit 2. В S1 C5 явно указать: неизвестная policy до расширения S7 → usage error, exit 2.
```

#### [svp-interview-upgrade] SVP-IU-005 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:136`

**Проблема:** PARTIAL: artifact validator добавлен, но transcript grammar недостаточно точна для детерминированной реализации.

**Доказательство:** C8 требует «заголовок с topic+датой», «≥1 пара вопрос/ответ», «финальный гейт» и упоминание отклонённых альтернатив «там, где решение их отклонило» (`design.md:145-151`), но не задаёт точные Markdown-маркеры этих сущностей. C4 также описывает только семантическую структуру (`design.md:84-88`). Реализатору придётся угадывать, как код отличает вопрос от ответа, решение с отклонениями от решения без них и где искать final gate. T4 проверяет лишь отсутствие `## Q&A` и final gate (`tasks.md:116`).

**Рекомендация:** Задать каноническую машинно-парсимую Markdown-грамматику transcript и негативные fixtures на каждый обязательный элемент.

**Готовая правка:**

```
Заменить C4/C8 transcript grammar на:
`# Interview transcript: <topic> (<YYYY-MM-DD>)`
`## Унаследовано`
`- <D-ID>: <text>` или `- none`
`## Q&A`
`### Q<N>: <question>`
`**Answer:** <near-verbatim text>`
`**Decision:** <D-ID> — <text>`
`**Rejected alternatives:** none | <text>`
`## Final gate`
`**Question:** <text>`
`**Answer:** <text>`
C8 MUST require this order, ISO date, monotonically increasing Q numbers, ≥1 complete Q&A block, and exactly one Final gate. Добавить T4 fixtures: missing Answer, missing Decision, missing Rejected alternatives, duplicate Final gate, invalid date и out-of-order Q numbers — каждый exit 1 с детерминированным reason code.
```

#### [svp-parallel-engine] R2-001 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:32-47,60-76; .memory-bank/specs/svp-parallel-engine/tasks.md:132-135`

**Проблема:** Frontier и claims используют несогласованный TTL: C1 не принимает TTL, хотя должен отфильтровывать stale claims.

**Доказательство:** C1 принимает `--claims` и решает, какие claims активны: `.memory-bank/specs/svp-parallel-engine/design.md:32-47`. Настраиваемый TTL существует только в C2 и pipeline config: `.memory-bank/specs/svp-parallel-engine/design.md:60-76`. Task 4 подключает `claim_ttl_seconds`, но не определяет передачу одного значения обоим потребителям: `.memory-bank/specs/svp-parallel-engine/tasks.md:132-135`. При нестандартном TTL frontier и mutation state-machine могут расходиться.

**Рекомендация:** Сделать TTL и тестовое время единым явным входом C1/C2.

**Готовая правка:**

```
Изменить C1 на `mb_work_items.py <path> --frontier --claims <path> --running-scopes <path> --ttl <seconds> [--now <unix-seconds>]`. Default TTL = 7200; active claim определяется как `last_event == claim && now - timestamp <= ttl`. Invalid TTL/time завершает exit 2. Task 4 обязан прочитать `parallel.claim_ttl_seconds` один раз и передать одинаковое значение C1 и C2. Добавить тесты TTL 1/7200, boundary `age == ttl` и deterministic `--now`.
```

#### [svp-parallel-engine] R2-002 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:119-122; scripts/mb-work-state.sh:7-15`

**Проблема:** C4 не задаёт исполняемый контракт выбора execution/intervention mode, критерий large target и precedence.

**Доказательство:** Design говорит только, что выбор фиксируется в `mb-work-state.sh`: `.memory-bank/specs/svp-parallel-engine/design.md:119-122`. Текущий script предоставляет `init|step|cycle|status|done` и не имеет mode API: `scripts/mb-work-state.sh:7-15`. Не определены аргументы, поля state, вывод, exit-коды, порог large target и приоритет CLI/config/интерактивного ответа.

**Рекомендация:** Зафиксировать отдельную state operation и детерминированный порядок источников настройки.

**Готовая правка:**

```
Добавить C4 API: `mb-work-state.sh configure-mode --state <path> --item-count <n> [--execution sequential|parallel] [--intervention hitl|autonomous] [--default-execution <mode>] [--default-intervention <mode>]`. Target считается large при `item-count >= 3`; group target всегда требует оба выбора. Precedence: explicit CLI > сохранённый state > интерактивный ответ для group/large > pipeline default. Вывод: `{"execution":"...","intervention":"...","source":"cli|state|answer|config"}`; exit 0 success, 2 invalid/missing required answer. State хранит оба mode и source неизменно после первого успешного выбора. Добавить matrix tests для precedence и threshold 2/3.
```

#### [svp-parallel-engine] R2-003 · feasibility · `.memory-bank/specs/svp-parallel-engine/design.md:103-117; .memory-bank/specs/svp-parallel-engine/tasks.md:94-115,129-162; scripts/mb-work-diff.sh:89-99,111-127; .memory-bank/specs/svp-adapt-escalation/design.md:34-48`

**Проблема:** Scope guard принимает готовый diff-file, но спека не назначает production producer; текущий helper теряет untracked и fail-open превращает недоступный git в пустой успешный diff.

**Доказательство:** C3 требует staged/modified/deleted/rename source+dest/untracked из `--diff-file`: `.memory-bank/specs/svp-parallel-engine/design.md:103-117`. Task 3/4 не расширяют producer: `.memory-bank/specs/svp-parallel-engine/tasks.md:94-115,129-162`. Существующий `mb-work-diff.sh` использует `git diff`, не включает untracked и при недоступном git возвращает пустой stdout: `scripts/mb-work-diff.sh:89-99,111-127`. Пустой diff по Task 3 считается `ok`, тогда как S5-C1 предусматривает `scope_status=unavailable`: `.memory-bank/specs/svp-adapt-escalation/design.md:34-48`. Это создаёт тихий обход guard.

**Рекомендация:** Назначить producer, включить все категории путей и согласовать unavailable с S5.

**Готовая правка:**

```
Расширить `mb-work-diff.sh` операцией `--scope-paths`, печатающей C-сортированное объединение modified, staged, deleted, обеих сторон rename и untracked paths. При отсутствии repo/git или ошибке чтения вернуть exit 3 и JSON `{"status":"unavailable","reason":"<code>"}`, а не пустой список. C3 должен возвращать status `ok|violation|unavailable` с exit 0|1|3; пустой успешный список допустим только после успешного git collection. Добавить `scripts/mb-work-diff.sh` в Scope Task 3/4 и тесты untracked, rename source/destination, deleted и unavailable. В S5-C1 использовать тот же enum без преобразования unavailable в ok.
```

#### [svp-parallel-engine] R2-004 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:124-144; .memory-bank/specs/svp-roadmap-backlog-db/design.md:106-110; .memory-bank/roadmap.md:77-95`

**Проблема:** C5 fallback на roadmap не имеет общей грамматики и уже расходится с текущим и будущим форматами S4.

**Доказательство:** S3 обещает fallback к roadmap `## Group:` table при отсутствующем blocked_by: `.memory-bank/specs/svp-parallel-engine/design.md:124-144`. Текущий roadmap использует заголовок с emoji/date и Markdown table: `.memory-bank/roadmap.md:77-95`. S4-C2 проектирует `## Group: <name>` с отдельными строками `<topic> — ... — blocked_by=...`, не таблицу: `.memory-bank/specs/svp-roadmap-backlog-db/design.md:106-110`. Не определены parser grammar, precedence при частичном frontmatter и поведение при расхождении.

**Рекомендация:** Не использовать человекочитаемый roadmap как неформализованную резервную БД зависимостей.

**Готовая правка:**

```
Заменить C5 fallback: `Frontmatter is authoritative. If all members have group and ice but any member lacks blocked_by, emit an ICE-only ordered list with {"degraded":true,"reason":"blocked_by_unavailable"} and do not infer dependency edges from roadmap prose. If group membership or ICE is missing, exit 2 with the sorted missing fields. Roadmap is display-only and never overrides frontmatter.` Добавить tests для полного metadata, missing blocked_by, missing group/ice и roadmap disagreement.
```

#### [svp-parallel-engine] R2-005 · parent-decision · `.memory-bank/specs/svp-parallel-engine/tasks.md:151-162; references/coordination.md:43-51; rules/RULES.md:702-704`

**Проблема:** Task 4 требует автоматически генерировать ACK, хотя ACK по coordination protocol должен подтверждаться другой сессией.

**Доказательство:** Task 4 test перечисляет generated `STATUS/FREEZE/ACK` entries: `.memory-bank/specs/svp-parallel-engine/tasks.md:151-162`. Протокол определяет ACK как подтверждение чтения принимающей стороной и требует ACK для freeze/handover: `references/coordination.md:43-51`, `rules/RULES.md:702-704`. Оркестратор не может достоверно создать ACK от имени ещё не ответившей сессии.

**Рекомендация:** Генерировать запрос подтверждения, а ACK оставлять принимающей сессии.

**Готовая правка:**

```
В Task 4 заменить тестовый пункт на: `group worktree setup appends STATUS, FREEZE and QUESTION entries with awaiting_ack=true; it never emits ACK on behalf of another session. The receiving session appends ACK after reading the entry, and dispatch remains blocked until that ACK exists.` Обновить C5/state-machine: pending freeze имеет status `awaiting_ack`; timeout приводит к deterministic `wait`/escalate, но не к synthetic ACK.
```

#### [svp-parallel-engine] SVP-PE-001 · parent-decision · `.memory-bank/specs/sdd-vision-pipeline/requirements.md:73-82; .memory-bank/specs/svp-parallel-engine/design.md:49-58; .memory-bank/specs/svp-parallel-engine/tasks.md:17-38`

**Проблема:** PARTIAL: umbrella REQ-022 требует отклонять циклы при валидации спеки, но ревизия 2 добавляет только runtime-проверку frontier.

**Доказательство:** Umbrella REQ-022 требует fail до принятия спеки: `.memory-bank/specs/sdd-vision-pipeline/requirements.md:78`. Child C1 проверяет цикл при `mb_work_items.py --frontier`, то есть уже во время исполнения: `.memory-bank/specs/svp-parallel-engine/design.md:49-58`. Task 1 меняет только parser и его тесты: `.memory-bank/specs/svp-parallel-engine/tasks.md:17-38`. Валидатор спецификаций в scope отсутствует.

**Рекомендация:** Оставить runtime-защиту S3, но назначить compile-time проверку владельцу S2 и исправить umbrella mapping.

**Готовая правка:**

```
В `svp-sdd-core/requirements.md` добавить: `- **REQ-016** (unwanted): If a v2 tasks.md Blocked-by graph contains a cycle, then spec validation shall exit non-zero before acceptance and print the complete ordered cycle path.` Добавить сценарий self-cycle и `A -> B -> C -> A`; включить REQ-016 в Covers/Testing задачи S2, расширяющей `mb-spec-validate.sh`. В umbrella tasks перенести покрытие REQ-022 с S3 на S2. В S3 оставить REQ-013 как дополнительную runtime-защиту, но удалить REQ-022 из `covers_umbrella` S3.
```

#### [svp-parallel-engine] SVP-PE-004 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:60-101`

**Проблема:** PARTIAL: атомарность claim улучшена, но контракт событий, stdout, lock recovery и bounded retry всё ещё неоднозначен.

**Доказательство:** C2 перечисляет `claim|release|release-stale|list` и общий event schema, но не задаёт точный stdout для каждого исхода и формат bulk release/list: `.memory-bank/specs/svp-parallel-engine/design.md:60-90`. Lock снимается при normal/INT/TERM, однако crash/SIGKILL оставит каталог блокировки; восстановление stale lock и числовая граница retry не определены: `.memory-bank/specs/svp-parallel-engine/design.md:67-76`. Реализующий агент вынужден выбрать несовместимые семантики самостоятельно.

**Рекомендация:** Зафиксировать полную state-machine C2, машинный вывод и восстановление осиротевшей блокировки.

**Готовая правка:**

```
Заменить C2 CLI-контракт на: `mb-work-claims.sh <claim|release|release-stale|list> --claims <path> [--task <id>] --session <id> [--ttl <seconds>] [--now <unix-seconds>]`. Каждая mutation печатает ровно один JSON object: `{"op":"<op>","task_id":"<id>","session_id":"<id>","status":"claimed|released|released_stale|occupied|not_owner|not_stale","released":["<sorted-id>"]}`. `list` печатает C-сортированный JSONL active-claims. Exit: 0 — transition выполнен/list; 1 — допустимый отказ state-machine; 2 — invalid input/state file; 3 — lock timeout. Lock хранит `owner.json` с host/pid/created_at; ожидание ограничено 5 секундами. Осиротевший lock снимается только при совпадении host и мёртвом PID либо возрасте более 30 секунд. Добавить тест SIGKILL/stale-lock recovery и тесты каждого stdout/exit результата.
```

#### [svp-parallel-engine] SVP-PE-006 · cross-slice · `.memory-bank/specs/svp-parallel-engine/requirements.md:72-79; .memory-bank/specs/svp-parallel-engine/design.md:32-47,152-156; .memory-bank/specs/svp-sdd-core/design.md:25-36`

**Проблема:** PARTIAL: синтаксис Scope делегирован S2-C1, но не определено пересечение двух glob-языков и конфликты между кандидатами одного frontier.

**Доказательство:** Сценарий требует сериализовать конфликтующие T3/T5: `.memory-bank/specs/svp-parallel-engine/requirements.md:72-79`. C1 сравнивает кандидата только с `running-scopes`: `.memory-bank/specs/svp-parallel-engine/design.md:42-47`. S2-C1 определяет сопоставление одного glob с путём, но не пересечение двух glob-паттернов: `.memory-bank/specs/svp-sdd-core/design.md:25-36`. Поэтому два одновременно свободных кандидата могут попасть в один frontier, хотя их Scope пересекаются.

**Рекомендация:** Добавить общий детерминированный алгоритм overlap и учитывать уже выбранные frontier-кандидаты.

**Готовая правка:**

```
В C1 записать: `Two Scope lists conflict iff at least one pattern pair has a non-empty language intersection under S2-C1. Intersection is computed symbolically by segment DP without filesystem expansion: literals intersect only when equal; * consumes exactly one non-empty segment; ** consumes zero or more segments. Frontier candidates are visited in deterministic (stage_no, item_no) order; a candidate is selected only when its Scope is disjoint from every active running claim and every candidate already selected into this frontier.` Добавить contract cases `src/**` vs `src/a.py` = conflict, `src/*` vs `src/a/b.py` = disjoint, `docs/**` vs `src/**` = disjoint и сценарий T3/T5.
```

#### [svp-parallel-engine] SVP-PE-008 · parent-decision · `.memory-bank/context/sdd-vision-pipeline.md:42; .memory-bank/context/sdd-vision-pipeline-interview.md:39; .memory-bank/context/svp-parallel-engine-interview.md:8-15; .memory-bank/specs/svp-parallel-engine/requirements.md:58; .memory-bank/specs/svp-parallel-engine/design.md:169-177`

**Проблема:** PARTIAL: вместо production wiring для Pi/OpenCode ревизия 2 сузила full mode до Claude Code, нарушив подтверждённое parent-решение D-07.

**Доказательство:** D-07 и umbrella interview требуют full mode на Claude Code, Pi и OpenCode: `.memory-bank/context/sdd-vision-pipeline.md:42`, `.memory-bank/context/sdd-vision-pipeline-interview.md:39`. Child interview это повторяет: `.memory-bank/context/svp-parallel-engine-interview.md:8-15`. Текущая REQ-008 переводит host без dispatch в platform_limited, а design относит Pi/OpenCode к деградации: `.memory-bank/specs/svp-parallel-engine/requirements.md:58`, `.memory-bank/specs/svp-parallel-engine/design.md:169-177`. При этом adapter-parity уже даёт этим host genuine dispatch primitive; отсутствует именно `/mb work` role-routing.

**Рекомендация:** Восстановить согласованный трёхhostовый scope либо получить явное новое решение пользователя, superseding D-07.

**Готовая правка:**

```
Добавить C6 `Host dispatch adapter`: host определяется через `MB_AGENT`/`mb_detect_host`; Claude Code использует native Task, Pi и OpenCode разрешают каждую роль через `mb-subinvoke-resolve.sh --agent <host> --role <role>` и передают один prompt `mb-engineering-core + host tooling + role + work item`. Full mode разрешается host только после positive dispatch contract test; `platform_limited` применяется лишь при фактически отсутствующем/неуспешном adapter route. Разбить реализацию на отдельную задачу host wiring и задачу parity tests, каждая с бюджетом ≤120k.
```

#### [svp-parallel-engine] SVP-PE-009 · eval · `.memory-bank/specs/svp-parallel-engine/design.md:21-28,179-197; .memory-bank/specs/svp-parallel-engine/tasks.md:125-162,217-240`

**Проблема:** PARTIAL: grep заменён на Bats, но Eval по-прежнему не связан с исполняемым production scheduler и не доказывает заявленную параллельность.

**Доказательство:** Оркестрация остаётся инструкцией в `commands/work.md`, а не исполняемым интерфейсом: `.memory-bank/specs/svp-parallel-engine/design.md:21-28,197`. Task 4 меняет prompt/config/state и запускает Bats, но не создаёт scheduler/dispatcher seam: `.memory-bank/specs/svp-parallel-engine/tasks.md:125-162`. Task 6 обещает positive Claude Code actual parallel run через Bats без интерфейса, которым тест может вызвать native Task: `.memory-bank/specs/svp-parallel-engine/tasks.md:217-240`. Такой тест может доказать лишь модель или наличие текста.

**Рекомендация:** Вынести scheduler decision engine в детерминированный CLI; markdown-команда должна только исполнять его действия.

**Готовая правка:**

```
Добавить контракт `python3 scripts/mb_parallel_scheduler.py <init|next|complete|fail> --run-id <id> --source <plan-or-spec> --max-agents <n> --execution <sequential|parallel> --intervention <hitl|autonomous> --mb <path>`. State path: `<bank>/tmp/parallel-runs/<run-id>.json`. `next` печатает один JSON object с C-сортированным `actions`, где action — `dispatch|wait|judge|escalate|done`; dispatch содержит task_id, role, prompt_file и claim token. Scheduler обязан выполнить frontier/scope/claim до выдачи dispatch и выдавать максимум N dispatch actions. `commands/work.md` только вызывает CLI и актует actions. Task 4 Bats должен прогонять реальный CLI с fake dispatcher/judge; Task 6 — проверять host route selection и payload native adapter, а не искать текст в markdown.
```

#### [svp-roadmap-backlog-db] F-005 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:151`

**Проблема:** PARTIAL: формат stdout для list и list --tree по-прежнему не определён

**Доказательство:** C3 фиксирует только порядок parent/children и ошибки (`design.md:151-155`). Не определены формат строки, поля, экранирование title, визуальное вложение и порядок плоского list. Сценарий требует «визуальное вложение» (`requirements.md:131-133`), оставляя реализатору выбор несовместимых форматов.

**Рекомендация:** Зафиксировать единый машинно-парсируемый вывод обоих list-режимов.

**Готовая правка:**

```
Добавить в C3: ``list` emits one stdout line per item: `item=<I-NNN> state=<STATE> parent=<I-NNN|none> depth=0 title=<JSON-string>`, ordered by numeric I-ID. `list --tree` emits the same grammar in pre-order with `depth=<non-negative-int>`; parent precedes descendants and siblings use numeric I-ID ascending. `title` is a compact JSON string literal. On missing parent or cycle, stdout is empty and stderr contains `code=missing_parent path=<...>` or `code=parent_cycle path=<...>`.`
```

#### [svp-roadmap-backlog-db] F-008 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:220`

**Проблема:** PARTIAL: lint-протокол не задаёт экранирование и расходится по числу кодов

**Доказательство:** C5 объявляет `file=<relative-path>` и `detail=<escaped-text>`, но не определяет escape grammar (`design.md:220-227`), хотя NFR требует пути с пробелами (`context/svp-roadmap-backlog-db.md:56`). Task 4 перечисляет 7 кодов — 3 warning и 4 error (`tasks.md:179-180`), но Testing и DoD требуют «6 кодов» (`tasks.md:185,190`).

**Рекомендация:** Сделать вывод однозначно парсируемым и исправить счётчик на семь.

**Готовая правка:**

```
Заменить C5-строку на: `severity=<warning|error> code=<code> file=<JSON-string> line=<positive-int|0> detail=<JSON-string>`, где JSON-строки создаются через `json.dumps(value, ensure_ascii=False, separators=(',', ':'))`. В Task 4 заменить оба упоминания `6 кодов` на `7 кодов` и потребовать отдельный test case для каждого из `no_ice`, `orphan_group`, `duplicate_pin`, `progress_mismatch`, `invalid_state`, `ready_without_brief`, `parent_cycle`.
```

#### [svp-roadmap-backlog-db] F-010 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:163`

**Проблема:** PARTIAL: similarity определена, но новый --force не встроен в существующий positional CLI

**Доказательство:** C3 требует явный `--force` (`design.md:163-169`), Task 8 повторяет это (`tasks.md:153-160`), но текущий публичный контракт — `mb-idea.sh <title> [priority] [mb_path]` без флагов (`scripts/mb-idea.sh:4-11`). Позиция флага, конфликт с priority/path, usage и backward compatibility не заданы.

**Рекомендация:** Зафиксировать расширенную грамматику и регрессионно удержать старые вызовы.

**Готовая правка:**

```
Добавить в C3: ``mb-idea.sh [--force] <title> [priority] [mb_path]`; `--force` is accepted only before `<title>`, bypasses only the similarity rejection, and does not bypass title idempotency or validation. Unknown flags exit 2 before mutation. Existing invocations without flags remain byte-identical.` В Task 8 Eval добавить старый positional-вызов и `--force`-вызов.
```

#### [svp-roadmap-backlog-db] F-013 · parent-decision · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:135`

**Проблема:** PARTIAL: выделенная Task 7 потеряла обязательный Bash 3.2 portability-гейт

**Доказательство:** NFR-004 распространяется на все новые/расширенные shell scripts (`context/svp-roadmap-backlog-db.md:56`). Task 7 расширяет `mb-backlog-state.sh`, но её Testing содержит только функциональные bats и shellcheck (`tasks.md:135-137`), в отличие от остальных shell-задач. Поэтому исправление F-013 неполное.

**Рекомендация:** Добавить тот же portability acceptance в Task 7.

**Готовая правка:**

```
После `tasks.md:136` добавить: `- Portability: run syntax/tests under Bash 3.2 on macOS and current Bash on Linux; forbid associative arrays, mapfile/readarray and GNU-only flags without fallback; include a bank path containing spaces.`
```

#### [svp-roadmap-backlog-db] R2-001 · consistency · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:231`

**Проблема:** Исправление lock-контракта основано на устаревшем описании mb-agree.sh и внутренне противоречиво

**Доказательство:** C6 утверждает, что текущий mb-agree stale-reclaim использует небезопасный `rm -rf`, требует заменить его на `mv`, но одновременно требует побитового parity (`design.md:231-242`). Фактический `mb-agree.sh` уже использует PID-liveness, повторное чтение owner-token и атомарный следующий mkdir (`scripts/mb-agree.sh:117-164`); его комментарий прямо объясняет, почему одновременный `rm -rf` мёртвого owner безопасен. Context при этом обещает переиспользовать существующий паттерн (`context/svp-roadmap-backlog-db.md:26`).

**Рекомендация:** Синхронизировать C6 с фактическим алгоритмом и убрать несовместимое требование mv-reclaim.

**Готовая правка:**

```
Заменить `design.md:235-242` на: `mb_lock_acquire copies the current mb-agree.sh owner-token algorithm: atomic mkdir; PID-liveness check; owner-token re-read before reclaim; TTL fallback only when owner is unreadable; unconditional timeout accounting; and owner-token comparison on release. Two contenders may both remove a proven-dead lock, but only one can win the following mkdir. The shared contract tests execute identical fixtures against the old private functions and the new helper.`
```

#### [svp-roadmap-backlog-db] R2-003 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:128`

**Проблема:** S3 и S4 определяют разные authoritative-порядки одной группы

**Доказательство:** S4-C2 сортирует готовый frontier по pin↑, ice↓, created↑, topic↑ и сохраняет legacy-tail (`svp-roadmap-backlog-db/design.md:67-86`). S3-C5 заявляет потребление схемы S4-C1, но сортирует только ICE↓/topic↑ и даже не возвращает pin/created (`svp-parallel-engine/design.md:128-140`; `svp-parallel-engine/tasks.md:184-196`). Поэтому roadmap и `/mb work <group>` могут исполнять одну группу в разном порядке.

**Рекомендация:** Сделать S3 прямым потребителем того же ordering contract.

**Готовая правка:**

```
В S3-C5 и Task 5 заменить ordering на: `At each dependency-ready frontier, use the S4-C2 comparator pin ascending → ice descending → created ascending → topic ascending, followed by the S4 legacy_tail rule. Member JSON includes pin and created. The resolver and roadmap renderer MUST share the same fixture table and produce the same topic order.` Добавить cross-slice fixture с duplicate pin, missing ice и равным ice.
```

#### [svp-roadmap-backlog-db] R2-004 · cross-slice · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:201`

**Проблема:** Typed SPEC registry имеет мигратор, но не имеет production writer после S4

**Доказательство:** S4 заявляет, что после миграции writer переключится на typed format (`design.md:201-216`), однако ни одна S4 task этого не делает. S1 продолжает писать `[SPEC:<group>]` через mb-idea.sh (`svp-interview-upgrade/design.md:132-134`), S2 — тем же способом (`svp-sdd-core/design.md:64-70`, `svp-sdd-core/tasks.md:114`). По roadmap S2 выполняется после S4, поэтому он создаст новые legacy-prefix записи уже после однократной миграции.

**Рекомендация:** Сохранить существующий S1/S2 вызов, но научить mb-idea.sh после S4 писать typed form напрямую.

**Готовая правка:**

```
Добавить в C4: `mb-idea.sh recognizes an exact title prefix [SPEC:<group>] <child-topic>. For new writes it omits the prefix from the stored title and emits **Type:** SPEC, **Group:** <group>, **Parent:** none and **Spec:** <child-topic> atomically; its stdout remains the allocated I-NNN. mb-backlog-migrate.sh handles only records created before this writer upgrade.` Добавить `scripts/mb-idea.sh` в Task 3 Scope, поставить `Blocked-by: 2`, поднять Budget до 120000 и добавить writer+legacy-migration parity tests.
```

#### [svp-roadmap-backlog-db] R2-005 · eval · `.memory-bank/specs/svp-roadmap-backlog-db/requirements.md:118`

**Проблема:** Сценарий Structural lint подаёт повреждения не в те источники данных

**Доказательство:** Scenario 8 задаёт ручной процент в `backlog.md` и no-ice элемент в `roadmap.md` (`requirements.md:122-124`). По C2 проценты находятся в generated roadmap block, а `ice` читается из plan/spec frontmatter (`design.md:88-104`, `design.md:106-110`). Реализация по design не сможет получить ожидаемые findings из указанного GIVEN.

**Рекомендация:** Исправить GIVEN на реальные source-of-truth файлы.

**Готовая правка:**

```
Заменить Scenario 8 GIVEN на: `- GIVEN в generated Group-секции roadmap.md процент вручную изменён, а specs/foo/requirements.md не содержит ice:`. Остальные WHEN/THEN оставить без изменения.
```

#### [svp-roadmap-backlog-db] R2-006 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:106`

**Проблема:** orphan_group невозможно обнаружить из определённого источника групп

**Доказательство:** C2 создаёт множество групп исключительно сканированием текущих `specs/*/requirements.md` (`design.md:106-110`), но затем требует warning для группы без единого члена (`design.md:110-111`). Такая группа не может попасть в множество из этого источника. Task 6 требует соответствующий тест, не определяя второй источник (`tasks.md:103-111`).

**Рекомендация:** Определить orphan как stale generated heading, уже присутствующий в roadmap fence.

**Готовая правка:**

```
Заменить orphan-правило на: `Before rendering, read existing ## Group: <slug> headings only from the current autosync fence. A slug present there but absent from the groups discovered in specs/*/requirements.md is an orphan_group warning. It is omitted from the new rendered block. Manual Group headings outside the fence are never interpreted as registry data.`
```

#### [svp-sdd-core] F-009 · contract · `.memory-bank/specs/svp-sdd-core/design.md:74-86; .memory-bank/specs/svp-sdd-core/tasks.md:149-168; .memory-bank/context/sdd-vision-pipeline.md:125-129; scripts/mb-pipeline-validate.sh:313-320`

**Проблема:** PARTIAL: F-009 — схема результата появилась, но нет исполняемого владельца exit-кодов/нормализации модели, а формат хранения противоречит родительскому JSONL-контракту.

**Доказательство:** C5 назначает exit 0/1/2, но называет только config `pipeline.yaml: sdd.spec_review`, без скрипта или функции, которая возвращает эти коды (`design.md:74-84`). Task 7 изменяет pipeline validator и prompt, но не содержит исполняемого result-parser/runner в Scope (`tasks.md:156-165`). Текущий `mb-pipeline-validate.sh` лишь загружает `sdd` (`scripts/mb-pipeline-validate.sh:313-320`). Кроме того, child пишет один `<topic>.json` (`design.md:79`), тогда как parent NFR-005 требует структурный append-log JSONL в `<bank>/tmp/` (`context/sdd-vision-pipeline.md:129`).

**Рекомендация:** Зафиксировать prompt/script seam: prompt владеет модельным dispatch, отдельный детерминированный helper валидирует метаданные и результат, пишет append-only JSONL и возвращает exit-код.

**Готовая правка:**

```
Заменить C5 на контракт:
`bash scripts/mb-sdd-review-result.sh --topic <topic> --generator-model <exact> --reviewer-agent <exact> --reviewer-model <exact> --thinking <low|medium|high> --input <path|-> [--mb <bank>]`
- `commands/sdd.md` владеет dispatch и передаёт helper сырой JSON ревьюера и фактически резолвленные model IDs.
- Равные generator/reviewer model → stderr `same_model`, exit 2, dispatch запрещён.
- Helper строго валидирует текущую C5-схему и append-ит одну компактную строку в `<bank>/tmp/spec-review/<topic>.jsonl`; обязательные дополнительные поля: `ts`, `attempt`.
- Exit 0 = APPROVED; 1 = CHANGES_REQUESTED; 2 = same_model/unavailable/malformed. SKIPPED тоже записывается отдельной JSONL-строкой и никогда не принимается молча.
- Последняя валидная строка является текущим verdict; история не перезаписывается.

В Task 7 Scope добавить `scripts/mb-sdd-review-result.sh`; в bats проверить append двух attempts, same_model до dispatch, malformed и unavailable.
```

#### [svp-sdd-core] F-010 · feasibility · `.memory-bank/specs/svp-sdd-core/design.md:88-98; .memory-bank/specs/svp-sdd-core/tasks.md:171-191; scripts/mb-work-state.sh:7-15,215-237; commands/work.md:745-754`

**Проблема:** PARTIAL: F-010 — обязательный red описан, но запись eval-объекта в durable work-state не провязана к существующему state API и отсутствует в Scope задачи.

**Доказательство:** C6 требует записывать `eval:{cmd,red_exit,red_observed,red_match,green_exit}` в «текущий work-state» (`design.md:90-96`). Фактический `mb-work-state.sh` поддерживает только init/new-run-id/step/cycle/status/list/done/clear и его schema не содержит eval (`scripts/mb-work-state.sh:7-15`); `step` добавляет только строку в `steps[]` (`scripts/mb-work-state.sh:215-237`). Task 8 разрешает менять лишь `commands/work.md` и тест (`tasks.md:178`), поэтому контракт нельзя реализовать через авторитетный writer без прямого редактирования JSON или нарушения Scope.

**Рекомендация:** Расширить единственный durable state writer детерминированными eval-субкомандами и включить его в Task 8.

**Готовая правка:**

```
В C6 добавить:
- `bash scripts/mb-work-state.sh eval-red --cmd-file <path> --exit <n> --observed <true|false> --match <true|false> [--run-id ID] [--mb <bank>]` атомарно создаёт `eval` и ставит `green_exit: null`.
- `bash scripts/mb-work-state.sh eval-green --cmd-file <path> --exit <n> [--run-id ID] [--mb <bank>]` требует byte-identical содержимое cmd-file относительно сохранённого cmd; drift → exit 1, usage/corrupt state → exit 2.
- Оба режима используют существующий singleton/per-run resolver и не меняют вывод старых subcommands.

В Task 8 Scope записать `commands/work.md, scripts/mb-work-state.sh, tests/bats/test_work_eval_first.bats, tests/bats/test_mb_work_state_eval.bats`. Добавить regression-тест byte-identical старых state-команд.
```

#### [svp-sdd-core] R2-001 · cross-slice · `.memory-bank/specs/svp-sdd-core/design.md:32-36; .memory-bank/specs/svp-parallel-engine/design.md:103-110,152-156`

**Проблема:** S2 и S3 по-разному определяют допустимые Scope-элементы, хотя S3 утверждает, что потребляет C1 без изменений.

**Доказательство:** S2 разрешает CSV произвольных repo-relative POSIX glob-паттернов и явно задаёт семантику `*`/`**` (`svp-sdd-core/design.md:32-35`). S3 сначала сужает элемент до «точного файла либо directory-префикса с /**» (`svp-parallel-engine/design.md:106-109`), хотя ниже утверждает, что реализует S2-C1 ровно (`svp-parallel-engine/design.md:152-156`). Паттерн вроде `scripts/*.sh`, уже используемый задачами группы, допустим по S2, но не является ни точным файлом, ни `dir/**` по формулировке S3.

**Рекомендация:** Сделать S3 чистым потребителем общей POSIX-glob грамматики без дополнительного ограничения формы.

**Готовая правка:**

```
В `svp-parallel-engine/design.md` C3 заменить предложение про форму элемента на:
«Каждый элемент — любой repo-relative POSIX glob из S2-C1. Строка без glob-метасимволов обозначает точный путь; `dir/**` является частным случаем рекурсивного префикса; `*` допустим в любом сегменте и не пересекает `/`; `**` пересекает любое число сегментов. Никаких дополнительных ограничений формы сверх S2-C1 нет.»

В S3 Task 3 Testing добавить общую контрактную таблицу: literal path, `scripts/*.sh`, `tests/fixtures/**`, запрещённые absolute/`..`/`!`.
```

#### [svp-sdd-core] R2-002 · eval · `.memory-bank/context/sdd-vision-pipeline.md:40; .memory-bank/specs/svp-sdd-core/design.md:88-98,112-124; .memory-bank/specs/svp-sdd-core/tasks.md:21,45,69,92,116,140,162,184`

**Проблема:** Generation battery называет отсутствующие тестовые файлы доказанным red, хотя родительский D-05 откладывает материализацию eval-кода до /mb work.

**Доказательство:** D-05 прямо запрещает писать eval-код на SDD-этапе и назначает его первым шагом `/mb work` (`context/sdd-vision-pipeline.md:40`). C6 также требует сначала материализовать Eval и отвергать посторонний сбой (`design.md:90-95`). Но C8 на генерации исполняет каждую Eval-команду и требует совпадения red-условия (`design.md:120-121`). Фактическая проверка показала, что все восемь target-файлов из tasks.md сейчас отсутствуют; следовательно, команды красные из-за missing target, а не из-за заявленных дефектов вроде «парсер не расширен» (`tasks.md:21`) или «режима --spec нет» (`tasks.md:69`).

**Рекомендация:** Развести generation preflight и поведенческий red: до work нельзя считать file-not-found доказательством контракта.

**Готовая правка:**

```
Заменить C8 пункт 4 и соответствующую часть REQ-015 на:
«Eval preflight: команда и её target детерминированно разбираются. Если target уже существует, команда исполняется и обязана дать заявленный red; уже-green или несовпавший red блокирует ready. Если eval-код по D-05 ещё не материализован, фиксируется `eval_status: pending_materialization`; отсутствие target/tool не считается observed red. Фактический behavioral red остаётся обязательным гейтом C6 после материализации в `/mb work`.»

В Task 4 Eval добавить проверки: missing target → pending, не observed red; existing already-green → invalid; existing matching-red → ready.
```

### MINOR (6)

#### [sdd-vision-pipeline] R2-009 · consistency · `.memory-bank/specs/svp-parallel-engine/requirements.md:63-70`

**Проблема:** Сценарий S3 всё ещё моделирует umbrella как группу из 6 спек вместо 8.

**Доказательство:** Scenario 1 содержит `GIVEN /mb work sdd-vision-pipeline (группа из 6 спек)` (`requirements.md:67`), тогда как umbrella design фиксирует восемь child-спек (`sdd-vision-pipeline/design.md:14-27`) и roadmap перечисляет S1–S8.

**Рекомендация:** Исправить фикстурное количество, чтобы сценарий проверял текущую группу.

**Готовая правка:**

```
Заменить строку на `- GIVEN /mb work sdd-vision-pipeline (группа из 8 child-спек)`.
```

#### [sdd-vision-pipeline] R2-010 · consistency · `.memory-bank/roadmap.md:97; .memory-bank/specs/svp-*/tasks.md`

**Проблема:** Roadmap сообщает 51 child-задачу с v2-полями, фактически их 52.

**Доказательство:** `roadmap.md:97` утверждает `51 задача`. Фактический task parser возвращает: S1=6, S2=8, S3=6, S4=8, S5=5, S6=7, S7=4, S8=8; сумма 52. Вместе с 9 umbrella-задачами parser возвращает 61.

**Рекомендация:** Исправить вычисляемый счётчик и не поддерживать его вручную.

**Готовая правка:**

```
Заменить `51 задача с v2-полями` на `52 задачи с v2-полями`. В будущем рендерить число как сумму записей `python3 scripts/mb_work_items.py specs/svp-*/tasks.md`, а не ручную константу.
```

#### [sdd-vision-pipeline] R2-011 · consistency · `.memory-bank/specs/sdd-vision-pipeline/design.md:6; .memory-bank/roadmap.md:79; .memory-bank/context/sdd-vision-pipeline.md:72-121`

**Проблема:** Umbrella и roadmap ошибочно приписывают REQ-049…054 родительскому context-файлу.

**Доказательство:** Design и roadmap называют `context/sdd-vision-pipeline.md` источником REQ-001…054. Фактически его Functional Requirements заканчиваются REQ-048 (`context.md:72-121`); REQ-049…053 пришли из S8/AGR-018, а REQ-054 добавлен закрытием SVP-012. Это ломает provenance при следующем spec-review.

**Рекомендация:** Указать фактические источники добавленных требований.

**Готовая правка:**

```
Заменить строку design на: `Входы: context/sdd-vision-pipeline.md (D-01…D-35, REQ-001…048); context/svp-contract-test-loop.md и AGR-018 (REQ-049…053); решение D-11 + закрытие SVP-012 (REQ-054)`. Ту же формулировку применить в roadmap.md:79.
```

#### [svp-contract-test-loop] R2-013 · consistency · `.memory-bank/context/svp-contract-test-loop-interview.md:3`

**Проблема:** Контекст всё ещё говорит, что assumptions ждут подтверждения, хотя AGR-018 уже является активным подтверждением.

**Доказательство:** Интервью дважды сообщает «ждут подтверждения» (`interview.md:3-4,79-82`), context повторяет это (`context/svp-contract-test-loop.md:58-59`). При этом активный AGR-018 фиксирует все решения S8 (`CLAUDE.md:77`).

**Рекомендация:** Синхронизировать исторический статус решения, не меняя принятые решения.

**Готовая правка:**

```
Заменить фразы ожидания на: `Assumptions S8-D-01…11 подтверждены пользователем и зафиксированы как AGR-018; статус ready.` В frontmatter context добавить `confirmed_by: AGR-018`.
```

#### [svp-parallel-engine] R2-006 · consistency · `.memory-bank/specs/svp-parallel-engine/requirements.md:63-70; .memory-bank/specs/sdd-vision-pipeline/design.md:14; .memory-bank/roadmap.md:88-95`

**Проблема:** Сценарий 1 фиксирует группу из 6 спецификаций, хотя группа содержит 8 child-слайсов.

**Доказательство:** Scenario 1 начинается с `a group of 6 specs`: `.memory-bank/specs/svp-parallel-engine/requirements.md:63-70`. Umbrella design и roadmap перечисляют 8 child specs: `.memory-bank/specs/sdd-vision-pipeline/design.md:14`, `.memory-bank/roadmap.md:88-95`. Число не влияет на алгоритм, но делает сценарий фактически неверным.

**Рекомендация:** Убрать хрупкое число либо заменить его текущим количеством.

**Готовая правка:**

```
Заменить `GIVEN a group of 6 specs` на `GIVEN a group of N specs with valid group, ice and blocked_by frontmatter` и добавить `AND N = 8 for the sdd-vision-pipeline fixture`.
```

#### [svp-sdd-core] R2-003 · consistency · `.memory-bank/context/svp-sdd-core.md:59-66,86-89; .memory-bank/specs/svp-sdd-core/design.md:128-129,158-160`

**Проблема:** Context одновременно объявляет Scope/flag закрытыми и оставляет их открытыми для будущего пересмотра.

**Доказательство:** Revision 2 говорит, что Scope-грамматика зафиксирована и open question снят (`context/svp-sdd-core.md:61-62`), а design повторяет, что вопросы закрыты (`design.md:128-129,158-160`). Однако `context/svp-sdd-core.md:88-89` всё ещё требует финализировать `--scaffold-only` и согласовать Scope с S3 при старте.

**Рекомендация:** Удалить устаревшие вопросы, чтобы реализаторы S3 не пересмотрели уже опубликованный контракт.

**Готовая правка:**

```
Заменить раздел `## Open Questions` в `context/svp-sdd-core.md` на:
`## Open Questions`

`— (закрыты ревизией 2: legacy-флаг — \`--scaffold-only\` по C7; Scope — POSIX-glob грамматика C1, потребляется S3/S5/S8 без ревизии).`
```

# Часть 3. Резюме по каждой спеке

### sdd-vision-pipeline (revision 2, re-review) — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие REQ и большинство исправлений первого круга восстановлены, но спека пока не исполнима как есть: фактический DAG umbrella-задач неверен, umbrella не проходит обязательный scenario-gate, а контракты secret-scan, ICE, claims-lock и S8 contract-checkers требуют угадывания. Найдена 1 critical, 8 major и 3 minor проблемы.

**Coverage:** REQ всего 54; REQ без задачи: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-033, REQ-034, REQ-035, REQ-036, REQ-037, REQ-038, REQ-039, REQ-040, REQ-041, REQ-042, REQ-043, REQ-044, REQ-045, REQ-046, REQ-047, REQ-048, REQ-049, REQ-050, REQ-051, REQ-052, REQ-053, REQ-054; недетерминированные эвалы: —.

Umbrella: 54/54 REQ покрыты задачами; 53/54 перечислены в covers_umbrella восьми child-спек, REQ-038 покрыт прямой T1. Все child-REQ покрыты задачами и локальными сценариями. Извлечено 89/89 child-сценариев, test_id уникальны. EARS — 9/9 green; task parser — 61 задача включая umbrella, ошибочных mb-mb-* ролей нет. Все объявленные Eval сейчас red; ложного уже-green Eval не найдено. Точный mb-spec-validate не смог создать mktemp из-за read-only sandbox, поэтому его проверки воспроизведены через EARS validator, scenario extractor, task parser и точный анализ кода валидатора. Umbrella extractor возвращает 0 сценариев, а scripts/mb-spec-validate.sh:243-264 при --require-scenarios неизбежно выдаёт 54 нарушения. Первый круг: SVP-001–007 и SVP-009–016 закрыты в исходном объёме; SVP-008 закрыта лишь частично. Оригинальная гонка SVP-010 с двумя победителями закрыта; дефект восстановления lock в R2-007 — новая находка.

**Сильные стороны:** Точное task-покрытие umbrella полное: 54/54 REQ, без orphan ID и без задач с несуществующими REQ.; Все 8 child-спек имеют согласованные group/covers_umbrella frontmatter; 53 umbrella-REQ делегированы child-слайсам, REQ-038 остаётся прямой задачей.; Каждый локальный child-REQ покрыт минимум одной child-задачей и минимум одним каноническим GWT-сценарием.; Батарея извлекла 89 сценариев и 89 уникальных test_id; все девять requirements.md проходят EARS validator.; Исправления ролей и Eval-path выполнены: task parser не создаёт mb-mb-* агентов, новые тестовые Eval указывают на CI-каталоги tests/bats и tests/pytest и сейчас действительно red.; Декомпозиция child-задач соблюдает лимиты ≤120k на задачу и ≤400k на Stage; задач-монстров и бессмысленной пыли не обнаружено.; Ревизия 2 полностью закрыла исходные проблемы REQ-022, Scope grammar, обязательного red, двухфазной escalation, brief C0, fast-to-code и CI test paths.

### svp-adapt-escalation (revision 2, re-review) — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Покрытие полное: 10/10 REQ связаны с задачами и сценариями. Из находок первого круга полностью закрыты SVP-AE-001–006 и SVP-AE-010–013; SVP-AE-007–009 закрыты лишь частично. Дополнительно найден один межслайсовый разрыв с S8. Итог: 5 major, поэтому спека пока не исполнима без угадывания контрактов.

**Coverage:** REQ всего 10; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Точное покрытие задач: T1→REQ-001,002,003,007,010; T2→REQ-003; T3→REQ-001; T4→REQ-004,005,006,008,010; T5→REQ-009. Извлечено 8 канонических сценариев, все REQ покрыты. mb-ears-validate, mb-scenario-extract --validate и mb_work_items.py завершились успешно. Все пять Eval-файлов и scripts/mb-work-adapt.sh фактически отсутствуют, поэтому заявленный red-предикат настоящий. Полный mb-spec-validate и Bats не смогли создать временные файлы в read-only sandbox (`Operation not permitted`); это ограничение среды, а не дефект спеки. Все заявленные существующие точки расширения найдены; новые имена свободны.

**Сильные стороны:** REQ/task coverage точное и двунаправленное: orphan ID отсутствуют.; Все 10 REQ покрыты восемью каноническими GIVEN/WHEN/THEN-сценариями с уникальными test_id.; Revision 2 исправила роли, tasks.md v2, отдельные loop-счётчики, report envelope, cascade stop и слабые grep-eval.; Пять Eval-команд являются детерминированными Bats-гейтами; их целевые файлы отсутствуют, поэтому red не сфальсифицирован текущим репозиторием.; Декомпозиция реалистична: 5 задач по 40k–100k токенов, этапы 190k и 160k — ниже заданных лимитов.

### svp-brief — CHANGES_REQUESTED

Повторный аудит подтверждает полное покрытие 10/10 REQ, но ревизия 2 всё ещё неисполнима как есть. Полностью закрыты SVP-BRIEF-005, SVP-BRIEF-007 и SVP-BRIEF-008. SVP-BRIEF-001/002/003/004/006 закрыты лишь частично. Кроме того, исправления внесли критическую дыру между LLM-генерацией и атомарным helper write, неправильный порядок задач и слабый Eval документации.

**Coverage:** REQ всего 10; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: Task 1 — Bats-план не проверяет заявленные REQ-003/REQ-004 и точную семантику --auto, Task 4 — grep одного фрагмента проверяет лишь наличие строки, но не dispatch и изменения README/CLAUDE.md.

Покрытие точно: 10 REQ, 4 задачи, все Covers ссылаются на существующие REQ; 6 scenario-блоков покрывают 10/10 REQ. mb-ears-validate.sh завершился с exit 0. mb-scenario-extract.py извлёк 6 JSONL-сценариев при 6 заголовках. mb_work_items.py распарсил 4/4 задачи. Полный mb-spec-validate.sh в принудительно read-only sandbox не дошёл до проверок: mktemp получил Operation not permitted; это ограничение среды, а не дефект спеки. Bats-команды также остановились на недоступном BATS_TMPDIR; rg подтвердил отсутствие трёх test-файлов и создаваемых scripts/commands. Eval T4 фактически red: grep exit 1.

**Сильные стороны:** SVP-BRIEF-005 закрыт полностью: scenario-layer каноничен, extractor даёт 6/6, все 10 gated REQ покрыты сценариями.; REQ→task покрытие полное и точное: 10/10; все четыре задачи имеют Covers, Testing, DoD, Stage, Scope и Budget.; SVP-BRIEF-007 закрыт: brief-stage и spec-stage canonical inputs теперь разделены согласованно с sdd-openspec-parity.; SVP-BRIEF-008 закрыт: target 60–100, допустимый диапазон 101–120 и warning >120 согласованы во всех слоях.; Внешняя зависимость S7→S1 отражена в requirements frontmatter, umbrella DAG и roadmap; размеры задач 40k–100k и этапов 100k/160k укладываются в родительские лимиты.

### svp-contract-test-loop — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие REQ → task → scenario полное, но спека пока не исполнима без догадок. Блокируют реализацию отсутствие машиночитаемого реестра контрактных чекеров, неверная точка расширения verify, недоопределённые contracts для layers/rules/Quality DoD, ложная совместимость с S5 и противоречивые DAG.

**Coverage:** REQ всего 21; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: T4: проверяет prompt-owned `/mb sdd`, но исполняемый renderer не определён, T5: verify-gейт оставлен plan-verifier/Markdown-команде без детерминированного runner, T6: доставка рубрики описана как dispatch-промпт без исполняемого payload contract, T7: заявляет реальный `/mb sdd` generation path, который принадлежит LLM-промпту, T8: полный spec→work→verify путь не имеет названного детерминированного runner.

Статический подсчёт: 21 REQ, 8 задач, 12 scenario headers и 12 markers; orphan ID нет. `mb-ears-validate.sh`, `mb-scenario-extract.py --validate`, извлечение 12 сценариев и `mb_work_items.py` прошли. Полный `mb-spec-validate.sh --require-scenarios` не смог создать временный файл в read-only sandbox (`mktemp: Operation not permitted`). Все восемь Eval target-файлов фактически отсутствуют; pytest с отключёнными capture/cache подтвердил exit 4 `file not found`, то есть заявленный поведенческий red не наблюдался.

**Сильные стороны:** Точное покрытие: все 21 REQ имеют task Covers; все 8 задач ссылаются только на существующие REQ.; Все 21 REQ покрыты 12 корректно извлекаемыми сценариями; scenario test_id уникальны и ASCII.; Stage budgets соблюдают лимит 400k: 160k, 220k, 180k и 200k; каждая задача ≤120k.; Явное отключение layers с причиной, legacy read-without-mutation и Testing Trophy разделены на отдельные требования и негативные сценарии.; Новые имена `mb-rules-resolve.sh` и Eval test-файлов свободны; остальные заявленные расширяемые файлы существуют, кроме отдельно найденного `commands/verify.md`.

### svp-docs-wiki (revision 2, re-review) — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие REQ полное, структура triple парсится, но осталось 10 major-дефектов: шесть находок первого круга закрыты лишь частично и четыре дефекта выявлены во втором проходе. Разработка по текущей версии потребует угадывать state/agent/dispatch-контракты, а часть заявленных Eval не способна доказать соответствующее требование.

**Coverage:** REQ всего 11; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: T4 — заявляет behavioral pytest оркестрации, но исполняемого orchestration seam в Scope нет., T6 — кодовый Eval проверяет конфиг/resolver, а end-to-end Scenario 5 оставлен ручным., T7 — source_leakage нельзя вывести из состояния wiki-фикстуры после завершённой записи..

Точное покрытие: T1→REQ-006; T2→REQ-001/005/009/010; T3→REQ-002/003; T4→REQ-001/002/011; T5→REQ-002/004; T6→REQ-007; T7→REQ-008. Все 11 REQ покрыты сценариями. EARS validator exit 0; scenario validate/extract exit 0, извлечено 9 сценариев; mb_work_items.py exit 0, извлечено 7 задач; у всех задач есть Covers/Testing/DoD. Полный mb-spec-validate был запущен, но read-only sandbox запретил его обязательный mktemp; эквивалентные составные проверки выполнены отдельно. Все семь Eval targets сейчас отсутствуют, поэтому ложнозелёных Eval нет; pytest/bats дополнительно не смогли стартовать из-за отсутствия writable temp. Полностью закрыты F-001, F-002, F-003, F-009, F-011, F-012, F-013; частично закрыты F-004, F-005, F-006, F-007, F-008, F-010.

**Сильные стороны:** Точное task coverage полное: все 11 текущих REQ покрыты, ссылок на несуществующие REQ и задач без Covers нет.; Scenario gate полный: 9 канонических сценариев покрывают все 11 REQ; extractor и scenario validator проходят.; Task v2 metadata исправлена: 7 задач парсятся, каждая имеет Stage/Blocked-by/Scope/Budget/Eval/Testing/DoD; task budgets ≤120k, Stage 1 = 400k, Stage 2 = 180k.; Межслайсовая зависимость S6→S2 согласована с umbrella DAG и ссылкой `svp-sdd-core#7`; F-003 закрыта.; Существующие extension points, названные для расширения, фактически существуют; новые docs modules, agents и test targets пока свободны.; Решения о внутреннем lint, dogfood path `project-wiki/`, read-only graph/wiki и honest degradation отражены значительно точнее, чем в ревизии 1.

### svp-interview-upgrade — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Повторный аудит: 7 из 10 находок первого круга закрыты полностью; SVP-IU-002, SVP-IU-003 и SVP-IU-005 закрыты лишь частично. Дополнительно найдены 3 регрессии/новых major-дефекта. Спека пока не исполнима без догадок: Eval остаются преимущественно text-structural, red-контракт противоречит eval-first workflow, secret-scan расходится с S7, transcript grammar недоопределена, а Scope T5 не позволяет изменить фактический `/mb context`.

**Coverage:** REQ всего 22; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: T1 — prompt-поведение принимается через co-occurrence текста; сценарии остаются ручными, T2 — final gate, batch и partial-answer проверяются только структурой Markdown, T4 — secret scanner проверяется кодом, но создание transcript по REQ-005 остаётся prompt-structural, T5 — обновление glossary проверяется co-occurrence, а не файловым поведением, T6 — семантика флагов и assumptions проверяется только текстом команды, T1–T6 — заявленный red основан на отсутствии тестовых файлов, хотя eval-first сначала материализует эти файлы.

Независимый подсчёт: 22/22 REQ покрыты 6 задачами; dangling REQ нет. `mb-ears-validate.sh` завершился с exit 0. `mb-scenario-extract.py --validate` завершился с exit 0 и извлёк 18 сценариев. `mb_work_items.py` завершился с exit 0 и извлёк 6 задач с валидными ролями. Полный `mb-spec-validate.sh --require-scenarios` не смог завершиться в read-only sandbox: его `mktemp` получил Operation not permitted. Точные Bats-команды также остановились на unwritable BATS_TMPDIR; инвентаризация подтвердила отсутствие всех объявленных Eval-файлов и трёх создаваемых скриптов. Полностью закрыты находки первого круга SVP-IU-001, 004, 006, 007, 008, 009, 010.

**Сильные стороны:** REQ→task и REQ→scenario покрытие полное: 22/22, без dangling ID.; Revision 2 полностью восстановила D-10/D-12/D-11: follow-up interview для child, defer-or-MVP и fast-to-code bypass.; C1 estimate checker теперь фиксирует схему, арифметику, пороги, stdout и exit-коды и согласован с S2 `--spec` extension.; Размеры реалистичны: каждая задача ≤110k, Stage 1 = 240k, Stage 2 = 205k, вся спека = 445k.; Сценарный экстрактор и parser задач проходят фактически; 18 сценариев и 6 задач извлекаются стабильно.; Спека учитывает Bash 3.2, honest degradation, atomic transcript write и запрет pragma bypass для transcript policy.

### svp-parallel-engine — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Повторный аудит: 5 из 10 находок первого круга закрыты полностью (PE-002, PE-003, PE-005, PE-007, PE-010), а PE-001, PE-004, PE-006, PE-008 и PE-009 закрыты лишь частично. Свежий проход выявил ещё 5 major-дефектов контрактов и 1 minor-рассинхрон. Локальная трассируемость полная, но спека пока не исполнима без существенных догадок.

**Coverage:** REQ всего 13; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: Task 4: Bats-эвал не имеет исполняемого production scheduler/dispatcher seam и потому не доказывает реальную параллельность, claim-before-dispatch и сериализацию judge., Task 6: заявленный positive Claude Code parallel run нельзя детерминированно вызвать из указанного Bats-теста; тест способен проверить только косвенную модель или текстовую конфигурацию..

REQ-001…REQ-013 покрыты задачами и сценариями; все 6 задач ссылаются только на существующие REQ. EARS validator, извлечение 12 сценариев и парсер 6 задач прошли. Полный mb-spec-validate --require-scenarios не завершился из-за запрета mktemp в read-only sandbox, поэтому его составные проверки выполнены отдельно. Все шесть Eval-target файлов отсутствуют, новые скрипты и frontier/group flags ещё отсутствуют — заявленное red-состояние подтверждено по репозиторию. Первый conjunct Task 4, mb-pipeline-validate для pipeline.default.yaml, уже green, а общий Eval остаётся red из-за отсутствующего Bats-файла.

**Сильные стороны:** Полная локальная трассируемость: 13/13 REQ покрыты задачами, все задачи имеют существующий Covers, 12 сценариев покрывают все 13 REQ.; Ревизия 2 полностью закрыла PE-002, PE-003, PE-005, PE-007 и PE-010: scenario markers восстановлены, v2 metadata добавлена, C1 source/output уточнены, group resolver унифицирован, group worktree semantics согласованы.; EARS-проверка, scenario extractor и task parser успешно обработали текущие артефакты; test_id сценариев уникальны.; Все заявленные расширяемые production-файлы существуют, а имена новых scripts/tests свободны; task/stage budgets не превышают заявленные лимиты.; Ревизия 2 добавила полезную runtime-защиту от DAG cycles и атомарную mutex-основу claims, хотя оба контракта требуют дальнейшего завершения.

### svp-roadmap-backlog-db — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Повторный аудит: полностью закрыты F-001, F-002, F-004, F-006, F-007, F-009 и F-011. Частично закрыты F-003, F-005, F-008, F-010, F-012 и F-013. Обнаружены новые межслайсовые и сценарные регрессии. Спека пока не исполнима без догадок: legacy-ordering противоречит алгоритму, глобальная уникальность I-NNN остаётся сломанной, state machine не интегрирована с mb-idea-promote.sh, а S3 использует иной групповой порядок.

**Coverage:** REQ всего 12; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

REQ→task покрытие полное: REQ-001→T1/T5; 002→T6/T5; 003→T6/T5; 004→T4; 005→T2/T5; 006→T7/T5; 007→T2/T5; 008→T8/T5; 009/010/011→T3; 012→T6/T4. Extractor извлёк 10 сценариев, покрывающих все 12 REQ; --validate exit 0. EARS validator exit 0. mb_work_items.py распарсил 8 задач, exit 0. Все восемь Eval сейчас red: соответствующие bats-файлы отсутствуют и команды возвращают exit 1. Полный mb-spec-validate --require-scenarios не завершился: read-only sandbox запретил его mktemp; это ограничение среды, а не дефект спеки.

**Сильные стороны:** Все 12 REQ имеют task-покрытие без ссылок на несуществующие REQ; все 8 задач покрывают существующие требования.; F-001 закрыт фактически: extractor валидирует и извлекает 10 канонических сценариев, покрывающих все gated REQ.; Миграционная таблица теперь охватывает реальный инвентарь legacy-статусов, а dry-run, backup и повторный no-op описаны явно.; Все восемь Eval являются исполняемыми командами и сейчас действительно red; новые имена скриптов свободны, а заявленные extension targets существуют.

### svp-sdd-core — revision 2 re-review — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Повторный аудит: 10 из 13 находок первого круга закрыты полностью; F-007, F-009 и F-010 закрыты частично. Покрытие REQ полное, размеры задач допустимы, сценарии и задачи извлекаются с паритетом. Однако остаются три major/critical дыры в исполняемых контрактах и две новые межслайсовые/родительские регрессии, поэтому разработку по спеке начинать рано.

**Coverage:** REQ всего 15; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Точное покрытие: REQ-001→T4; 002→T4,T6; 003→T4; 004→T1; 005→T1,T6; 006→T2; 007→T2; 008→T8; 009→T3; 010→T5; 011→T5; 012→T7; 013→T4; 014→T5; 015→T2,T4. Все 15 REQ имеют сценарии; 14 заголовков Scenario = 14 извлечённых блоков. 8 task-маркеров = 8 результатов mb_work_items.py; роли резолвятся без mb-mb-*.
Первый круг: F-001/002/003/004/005/006/008/011/012/013 — закрыты полностью; F-007/009/010 — частично.
Самопроверка: mb-ears-validate exit 0; scenario parity 14/14; task parser 8/8. Полный mb-spec-validate --require-scenarios не удалось подтвердить в read-only sandbox: скрипт завершился на mktemp с Operation not permitted. Все восемь Eval-target файлов сейчас отсутствуют; команды не зелёные, но это не доказывает заявленный поведенческий red — см. R2-002.

**Сильные стороны:** Полное и точное покрытие: 15/15 REQ задачами и сценариями; orphan REQ и пустых Covers нет.; F-001–F-006, F-008 и F-011–F-013 в основном исправлены предметно: canonical scenario markers, bare roles, v2 task fields, явные бюджеты и поведенческие test commands.; Декомпозиция укладывается в ограничения: каждая задача ≤120k, Stage totals 280k/300k/180k, spec total 760k.; Parser и scenario extractor фактически читают текущие артефакты с паритетом 8/8 и 14/14.

