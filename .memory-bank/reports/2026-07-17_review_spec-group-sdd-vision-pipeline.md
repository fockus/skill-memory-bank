# Spec review: группа sdd-vision-pipeline (8 спек, Codex gpt-5.6-sol, effort=high)

> Дата: 2026-07-17 · 8 независимых ревьюеров, по одному на спеку, каждый с полным контекстом (spec triple + context + транскрипт интервью + umbrella-решения + правила проекта + соседние спеки).


> **ADDENDUM (2026-07-17, тот же день): все 96 находок закрыты.**
> Механические — скриптом (44 роли → bare; 51 сценарий канонизирован, имена → English из-за test_id-слагов; frontmatter group/ice/blocked_by на 8 спек). Umbrella + svp-sdd-core — оркестратором (грамматики Scope/Blocked-by зафиксированы в S2-C1; claims под mkdir-lock; эскалация двухфазная opened/resolved; red=FAIL вместо warning; +REQ-054 fast-to-code, +REQ-015 батарея самопроверки генерации). S1/S7/S4/S6 — Sonnet-фиксеры, S3/S5 — Opus-фиксеры (по решению пользователя); каждый верифицирован оркестратором независимо. Финальная батарея: EARS 9/9 · require-scenarios 8/8 · сценарии 89/89 (test_id уникальны) · задачи 51/51 (v2-поля) · все eval-гейты красные. Процесс-фикс: `commands/sdd.md` § Generation self-check. Корневые причины — в рефлексии сессии и `notes/2026-07-17_1300_spec-generation-needs-consumer-battery.md`.

## Сводка вердиктов

| Спека | Вердикт | crit | major | minor | nit | REQ | REQ без задачи |
|---|---|---|---|---|---|---|---|
| sdd-vision-pipeline | CHANGES_REQUESTED | 2 | 12 | 2 | 0 | 48 | REQ-022 — umbrella Task 7 заявляет покрытие, но в child-спеке svp-parallel-engine отсутствуют соответствующие REQ и задача на cycle-path validation |
| svp-adapt-escalation | CHANGES_REQUESTED | 2 | 11 | 0 | 0 | 9 | — |
| svp-brief | CHANGES_REQUESTED | 1 | 6 | 1 | 0 | 8 | — |
| svp-docs-wiki | CHANGES_REQUESTED | 0 | 13 | 0 | 0 | 9 | — |
| svp-interview-upgrade | CHANGES_REQUESTED | 0 | 8 | 2 | 0 | 19 | — |
| svp-parallel-engine | CHANGES_REQUESTED | 2 | 8 | 0 | 0 | 12 | — |
| svp-roadmap-backlog-db | CHANGES_REQUESTED | 1 | 12 | 0 | 0 | 12 | — |
| svp-sdd-core | CHANGES_REQUESTED | 0 | 12 | 1 | 0 | 14 | — |

## Все находки (severity ↓, затем спека)

### CRITICAL (8)

#### [svp-brief] SVP-BRIEF-001 · edge-case · `.memory-bank/context/svp-brief.md:53-56; rules/RULES.md:776-789`

**Проблема:** Предложенная обработка секретов может записать настоящий секрет в git.

**Доказательство:** Контекст требует копировать бинарные вложения as-is и разрешает очистку либо `<private>`: «секрет ... блокировать до очистки/`<private>`». Но правила прямо предупреждают: «protects index.json / mb-search, NOT git diff». Следовательно, `<private>` не делает исходник безопасным для хранения в `briefs/<topic>/inputs/`. Для бинарных PDF/схем поведение сканера вообще не определено.

**Рекомендация:** Сканировать все источники до копирования; `<private>` не считать способом разблокировать git-запись. Неинспектируемый или нечитаемый файл должен давать громкий отказ, а не тихое копирование.

**Готовая правка:**

```
Заменить edge-case на: «До создания `briefs/<topic>/` система SHALL просканировать каждый источник. `<private>` влияет только на индекс/search и SHALL NOT разблокировать сохранение найденного секрета. Продолжение разрешено только после удаления/редакции секрета либо явной построчной прагмы `<!-- mb-secret-ok -->`. Если тип файла нельзя проверить, команда SHALL завершиться без изменений с `scan=unsupported`, перечислить файлы и запросить явное решение пользователя; тихое копирование запрещено». В design C5 добавить: «scan выполняется до любой мутации destination; exit 0=clean, 1=findings, 2=unreadable/unsupported; только exit 0 разрешает автоматическое копирование».
```

#### [sdd-vision-pipeline] SVP-001 · feasibility · `Все восемь tasks.md; scripts/mb_work_items.py:240`

**Проблема:** 44 из 45 задач резолвятся в несуществующих агентов `mb-mb-*`.

**Доказательство:** Например, `.memory-bank/specs/sdd-vision-pipeline/tasks.md:31` содержит `**Role:** mb-architect`, а `scripts/mb_work_items.py:240` безусловно делает `agent = f"mb-{role}"`. Фактический parse дал `agent: mb-mb-architect`. Такая же ошибка присутствует в 44 задачах; только umbrella T1 использует корректный `developer`.

**Рекомендация:** Использовать в `Role` только bare role names, которые ожидает parser.

**Готовая правка:**

```
Во всех восьми tasks.md выполнить замены: `**Role:** mb-developer` → `**Role:** developer`; `mb-backend` → `backend`; `mb-architect` → `architect`; `mb-qa` → `qa`.
```

#### [sdd-vision-pipeline] SVP-002 · eval · `Все child requirements.md, разделы Scenarios`

**Проблема:** Ни один child-сценарий не является исполняемым SDD-сценарием.

**Доказательство:** Контракт требует marker + Covers (`rules/RULES.md:587-591`). Например, `.memory-bank/specs/svp-interview-upgrade/requirements.md:80-84` содержит только `### Scenario` и GIVEN/WHEN/THEN. Во всех семи child-файлах найдено 39 таких блоков, но нет ни одного `mb-scenario`/`**Covers:**`; `mb-scenario-extract.py` вернул `extracted=0` для каждого child.

**Рекомендация:** Перевести все сценарии в канонический формат и добавить сценарии для каждого gated REQ.

**Готовая правка:**

```
Каждый блок оформить так: `<!-- mb-scenario:N -->\n### Scenario: <name>\n**Covers:** REQ-...\n- GIVEN ...\n- WHEN ...\n- THEN ...`. Затем добавить блоки для локальных REQ, отсутствующих в `coverage_check.notes`, и добиться green от `mb-spec-validate.sh --require-scenarios <child>`.
```

#### [svp-adapt-escalation] SVP-AE-004 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:14-18`

**Проблема:** C1 не способен выразить все гарды REQ-002 и не определяет детерминированный источник отдельных verify/review/judge-счётчиков.

**Доказательство:** REQ-002 включает `eval not green after max cycles` (`requirements.md:18`), но C1 не принимает eval-status/count. Существующий mb-work-state хранит один общий `cycle` (`scripts/mb-work-state.sh:240-274`), а verify сейчас останавливается на первом FAIL (`commands/work.md:366-389`). `mb-work-budget.sh check` использует exit 1 и для WARN, и для отсутствующего бюджета, exit 2 — только STOP (`scripts/mb-work-budget.sh:229-256`), тогда как `--budget-status S` не имеет enum.

**Рекомендация:** Зафиксировать durable-счётчики, точные входные enum, сравнение порогов и приоритет относительно pivot/max_cycles.

**Готовая правка:**

```
Расширить C1: оркестратор записывает через `mb-work-state.sh step` события `eval_fail`, `verify_fail`, `review_cycle`, `judge_cycle`; `decide` получает их количества из `mb-work-state.sh status`. Бюджет триггерит только exit 2; exit 1 логируется как warning/unavailable. Порог срабатывает при `count >= threshold`. Eval сравнивается с `work-state.max_cycles`. ADaPT-check выполняется после фиксации неуспешного события, до pivot и до существующего on_max_cycles; политика 5f после решения ADaPT не изменяется. Usage/invalid input → exit 2, internal parse error → exit 1, валидное решение → exit 0.
```

#### [svp-adapt-escalation] SVP-AE-010 · consistency · `.memory-bank/context/svp-adapt-escalation.md:60`

**Проблема:** Edge-case разрешает NotImplemented без feature flag и только warning, прямо противореча REQ-004/009 и hard rules.

**Доказательство:** Context: «без флаг-механизма … NotImplemented-путь … verify предупреждает» (`context/svp-adapt-escalation.md:60`). Requirements требуют stub за flag и verification FAIL без него (`requirements.md:27,39`). Правила разрешают stub только за feature flag (`rules/RULES.md:377-380`).

**Рекомендация:** Удалить незаконную деградацию; отсутствие возможности поставить flag должно быть явной эскалацией.

**Готовая правка:**

```
Заменить строку edge-case на: `Auto-режим без доступного механизма feature flag — stub НЕ создаётся; решение принудительно меняется на fork_user с trigger=feature_flag_unavailable, run останавливается и сообщает проблему. NotImplemented/TODO и продолжение с warning запрещены.`
```

#### [svp-parallel-engine] SVP-PE-001 · coverage · `.memory-bank/context/svp-parallel-engine.md:9; .memory-bank/specs/sdd-vision-pipeline/requirements.md:78; .memory-bank/specs/sdd-vision-pipeline/tasks.md:122; .memory-bank/specs/svp-parallel-engine/tasks.md:9`

**Проблема:** Child-слайс заявляет покрытие umbrella REQ-022, но не содержит требования или теста на DAG-цикл.

**Доказательство:** Child context включает `REQ-022` в `covers_umbrella` (`context/svp-parallel-engine.md:9`). Umbrella требует: «IF ... blocked_by cycle, THEN ... SHALL fail ... and print the cycle path» (`specs/sdd-vision-pipeline/requirements.md:78`), а родительская задача S3 требует тест `DAG cycle → fail with cycle path` (`specs/sdd-vision-pipeline/tasks.md:122,131`). В child requirements нет локального аналога, а Task 1 покрывает только `REQ-003` и перечисляет DAG-варианты без cycle-path проверки (`specs/svp-parallel-engine/tasks.md:9,19`).

**Рекомендация:** Вернуть обязательный fail-fast контракт цикла в child requirements, сценарии и Task 1.

**Готовая правка:**

```
Добавить в requirements.md: `- **REQ-013** — IF the resolved blocked_by graph contains a cycle, THEN the orchestrator SHALL abort before claim or dispatch, exit non-zero, and print the complete ordered cycle path.` Добавить формальный сценарий с `**Covers:** REQ-013`, GIVEN граф `A → B → C → A`, WHEN вычисляется frontier, THEN exit non-zero, stdout пуст, stderr содержит `A -> B -> C -> A`, claims-файл не изменён. Изменить Task 1 на `**Covers:** REQ-003, REQ-013` и добавить этот тест в pytest Eval/DoD.
```

#### [svp-parallel-engine] SVP-PE-004 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:17; .memory-bank/specs/svp-parallel-engine/design.md:49`

**Проблема:** Claim-контракт не обеспечивает mutual exclusion и не способен представить release.

**Доказательство:** C2 задаёт запись только `{task_id, session_id, ts}` и алгоритм «append + пост-проверка последней записи» (`design.md:17-18`). При interleaving A append→A read и B append→B read оба процесса могут увидеть себя последними и начать dispatch. Формат без `op` не различает claim и release, хотя CLI обещает `release` и `release-stale`. Риск повторяет тот же неатомарный алгоритм (`design.md:49`). Параметр `--session` также отсутствует, хотя `session_id` обязателен в записи.

**Рекомендация:** Определить транзакционный portable lock, event schema, ownership и полные exit/output contracts.

**Готовая правка:**

```
Заменить C2 на: `mb-work-claims.sh claim|release --task <id> --session <id> --mb <bank>` и `mb-work-claims.sh release-stale|list --mb <bank> [--task <id>]`. State: append-only JSONL events `{"op":"claim|release","task_id":"...","session_id":"...","ts":<unix-seconds>}`; active owner = последняя валидная event для task. Любая read→validate→append операция выполняется под portable `mkdir <bank>/tmp/.work-claims.lock` lock с ограниченным retry; lock снимается trap-ом. `claim` разрешён только при отсутствии активного non-stale owner; `release` разрешён только owner-сессии; stale определяется как `now-ts > parallel.claim_ttl_seconds`. stdout всегда один JSON object. Exit: 0 success, 1 occupied/not-owner, 2 usage, 3 lock timeout или I/O error. Добавить race-test, который запускает два claim одновременно и доказывает ровно один exit 0 и ровно одного active owner.
```

#### [svp-roadmap-backlog-db] F-007 · feasibility · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:20`

**Проблема:** Миграция не определена для реальных legacy-статусов текущего backlog

**Доказательство:** C4 отображает только `PLANNED→IN-PROGRESS`, `DECLINED→WONTFIX`, `DEFERRED→TRIAGED` и прямо оставляет таблицу на T3 (`design.md:20-21`; `context/svp-roadmap-backlog-db.md:72`). Реальный backlog содержит `DONE <date>`, `OPEN`, `PROPOSED`, `RESOLVED <date>`, `DEFERRED` и `DECLINED` (`.memory-bank/backlog.md:15,46,111,158,227,471`). REQ-011 одновременно требует legacy readability without mutation (`requirements.md:34`).

**Рекомендация:** Финализировать migration table до разработки и разделить read compatibility и explicit apply.

**Готовая правка:**

```
Добавить таблицу: `NEW→NEW`; `TRIAGED|OPEN|PROPOSED→TRIAGED`; `PLANNED→IN-PROGRESS`; `DONE` или `DONE <date>→DONE`; `RESOLVED` или `RESOLVED <date...>→DONE`; `DECLINED→WONTFIX`; `DEFERRED→TRIAGED`. Добавить: `Without --apply, legacy entries remain readable and byte-identical and legacy-only states produce warnings. With --apply, only the status token is rewritten; ID, title, body and order remain byte-identical. A second --apply makes no changes and creates no new backup.`
```

### MAJOR (82)

#### [svp-brief] SVP-BRIEF-002 · cross-slice · `.memory-bank/specs/sdd-vision-pipeline/design.md:26-31; .memory-bank/specs/svp-brief/tasks.md:12-15`

**Проблема:** S7 объявлен незаблокированным, хотя Task 1 зависит от ещё не реализованного C5 слайса S1.

**Доказательство:** Umbrella помещает S7 во фронтир без блокеров. Task 1 требует «secret-scan-гейт (C5 из S1)». Фактическая проверка репозитория: `scripts/mb-secret-scan.sh` отсутствует. S1 определяет этот будущий контракт в `svp-interview-upgrade/design.md:41-44`.

**Рекомендация:** Сделать зависимость явной и согласовать её во всех артефактах группы.

**Готовая правка:**

```
В umbrella DAG заменить строку на: «S7 `blocked_by: S1` — `/mb brief` потребляет `scripts/mb-secret-scan.sh` по S1-C5». В roadmap для S7 установить `Blocked by: S1`. В начале `svp-brief/tasks.md` записать `Blocked by: svp-interview-upgrade`; в design C5 дать прямую ссылку на `specs/svp-interview-upgrade/design.md#c5-secret-scan-вызов` и повторить совместимые exit-коды.
```

#### [svp-brief] SVP-BRIEF-003 · contract · `.memory-bank/specs/svp-brief/design.md:10-22; .memory-bank/specs/svp-brief/tasks.md:12-15`

**Проблема:** Нет контракта самой `/mb brief`: не определено, как команда получает запрос и файлы, валидирует topic и переживает частичный отказ.

**Доказательство:** § Interfaces описывает только валидатор, структуру каталога, handoff и роутер. При этом Task 1 требует анализировать вложения, копировать их и обрабатывать повторный вызов. Не определены аргументы источников, collision/symlink policy, атомарность, поведение отсутствующего файла и точная семантика повторного запуска.

**Рекомендация:** Добавить до C1 полный интерфейс основной команды и убрать неопределённое версионирование либо специфицировать его отдельно.

**Готовая правка:**

```
Добавить в design: «### C0. `/mb brief <topic> [--input <path>]...` — `<topic>` MUST match `[a-z0-9][a-z0-9-]*`; request text берётся из текущего пользовательского сообщения; `--input` повторяемый и принимает только существующий regular file. UI-вложения SHALL быть преобразованы хостом в тот же список локальных путей; если это невозможно, команда сообщает `attachment=unavailable` и не притворяется, что файл прочитан. Symlink, directory, unreadable path, basename collision и path traversal SHALL fail before writes. Все scan/validation выполняются до атомарного создания каталога. Существующий `brief.md` SHALL return `brief=exists` без изменений и предложить только update/cancel; update требует явного подтверждения». Удалить из Task 1 неопределённый вариант «создать версию» до появления отдельного контракта.
```

#### [svp-brief] SVP-BRIEF-004 · contract · `.memory-bank/specs/svp-brief/design.md:12-16; .memory-bank/specs/svp-brief/tasks.md:32-38`

**Проблема:** Контракт `mb-brief-validate.sh` недостаточен для однозначной реализации и тестов.

**Доказательство:** C1 говорит лишь: «9 обязательных секций + непустой Essence/Goal; exit 0 / 1 ... key=value `brief=ok|invalid`». Не определены точные Markdown-заголовки и уровни, регистр, stdout/stderr, порядок ошибок, exit для usage/I/O, frontmatter validation и точный порог oversize. Task 2 при этом требует тест `oversize-warning`.

**Рекомендация:** Зафиксировать грамматику и полный CLI-протокол.

**Готовая правка:**

```
Заменить C1 на: «`scripts/mb-brief-validate.sh <brief.md>` принимает ровно один существующий regular file. Требуются ровно по одному H2: `Essence`, `Goal & Impact`, `References`, `Solution (JTBD)`, `Scenarios`, `Constraints`, `UX`, `Done Criteria`, `Attachments`; aliases и другой регистр запрещены. Frontmatter MUST содержать `topic`, ISO-date `created`, `status: ready|draft`, `inputs` как YAML-list относительных `inputs/...` путей. Essence и Goal & Impact MUST иметь хотя бы одну непустую строку вне комментариев. stdout: ровно `brief=ok` или `brief=invalid`; stderr: по одной строке `error=<code> section=<name>` в порядке списка выше. Exit 0=valid, 1=content invalid, 2=usage/I/O. 60–100 строк — target; при >120 stderr содержит `warning=oversize lines=<N> limit=120`, но exit остаётся 0 при прочей валидности».
```

#### [svp-brief] SVP-BRIEF-005 · coverage · `.memory-bank/specs/svp-brief/requirements.md:41-59; rules/RULES.md:584-600`

**Проблема:** Раздел Scenarios не является исполняемым scenario-layer и не покрывает четыре требования даже вручную.

**Доказательство:** Все три сценария записаны без `<!-- mb-scenario:N -->`, закрывающего маркера и `**Covers:**`. Проектный формат требует эти поля. `mb-scenario-extract.py` вернул пустой результат. В тексте заголовков упомянуты только REQ-001/002/003/008; REQ-004/005/006/007 отсутствуют.

**Рекомендация:** Оформить существующие сценарии канонически и добавить минимальные сценарии handoff/validation без расширения scope.

**Готовая правка:**

```
Обернуть каждый сценарий в `<!-- mb-scenario:N --> ... <!-- /mb-scenario:N -->` и добавить отдельную строку `**Covers:**`. Для первого указать `REQ-001, REQ-002, REQ-004, REQ-008`, для второго `REQ-003`, для третьего `REQ-001`. Добавить: `mb-scenario:4` с Covers `REQ-005, REQ-006`, GIVEN валидный ready-бриф с input, WHEN brief завершён и затем запускается discuss, THEN предложение содержит точный `/mb discuss <topic>`, а Phase 0 digest цитирует brief и input; `mb-scenario:5` с Covers `REQ-007`, GIVEN brief без `## UX`, WHEN запускается валидатор, THEN exit 1 и `error=missing_section section=UX`.
```

#### [svp-brief] SVP-BRIEF-006 · eval · `.memory-bank/specs/svp-brief/tasks.md:17-24,49-58,66-75; .memory-bank/context/sdd-vision-pipeline.md:40,60`

**Проблема:** Eval задач 1 и 3 проверяет имитацию требования, а Task 1 дополнительно принимает поведение вручную.

**Доказательство:** T1 проверяет только существование `commands/brief.md`, одно слово Done Criteria и любое слово brief в templates; это пройдёт без восьми секций, копирования, scan, лимита вопросов, Attachments и handoff. T3 — `grep -qi 'brief' commands/discuss.md`, который пройдёт от любого комментария. Testing требует ручных сценариев. D-05/D-25 требуют code-verifiable Eval и структурный Eval, действительно проверяющий контракт.

**Рекомендация:** Материализовать файловую часть команды в детерминированный helper и заменить grep/manual acceptance интеграционными Bats-тестами.

**Готовая правка:**

```
В design добавить один helper `scripts/mb-brief.sh create|context`: `create` реализует safe-copy/scan/atomic-store и вызывает C1; `context --mb <bank> --topic <topic>` печатает существующие `brief.md` и inputs либо `brief=absent`. Заменить T1 Eval на `bats tests/bats/test_mb_brief_command.bats` с кейсами: no-input, девять секций, copy+relative links, secret hard-block/no mutation, basename collision, existing-topic no-overwrite, exact handoff. Заменить T3 Eval на `bats tests/bats/test_mb_brief_discuss_handoff.bats`, проверяющий `brief=absent` preserves legacy Phase 0 и существующий brief+inputs попадает в deterministic source list. Удалить ручные сценарии из DoD как единственное доказательство; оставить их только supplemental smoke.
```

#### [svp-brief] SVP-BRIEF-007 · cross-slice · `.memory-bank/specs/svp-brief/design.md:41-43; .memory-bank/specs/sdd-openspec-parity/design.md:66-71`

**Проблема:** Путь источников брифа противоречит canonical inputs-registry SDD.

**Доказательство:** Brief design утверждает: «sdd/Sources ссылаются на `briefs/<topic>/inputs`». Контракт sdd-openspec-parity требует canonical copies в `specs/<topic>/inputs/` и валидирует относительные `inputs/` пути. Одна сторона предполагает ссылку на briefs, другая — физическую canonical copy внутри spec.

**Рекомендация:** Явно разделить brief-source и spec-source, не объявляя briefs-папку canonical для SDD.

**Готовая правка:**

```
Заменить mitigation на: «`briefs/<topic>/inputs/` — canonical только для brief-стадии. Phase 0 читает эти файлы как внешние источники. При создании spec контракт sdd-openspec-parity сохраняется без изменений: SDD копирует выбранные источники в `specs/<topic>/inputs/`, присваивает S-NN и валидирует локальные `inputs/...` пути. Прямые ссылки из `## Sources` на `briefs/.../inputs` не заменяют обязательную canonical copy».
```

#### [sdd-vision-pipeline] SVP-003 · coverage · `.memory-bank/specs/svp-parallel-engine/requirements.md:22-50; tasks.md:7-22`

**Проблема:** Umbrella REQ-022 потерян при переходе в child S3.

**Доказательство:** Umbrella требует падения с cycle path (`sdd-vision-pipeline/requirements.md:78`). Child S3 перечисляет frontier/claims/scope/group требования, но не содержит требования о DAG-цикле; Task 1 покрывает только локальный REQ-003 (`svp-parallel-engine/tasks.md:9`) и его Testing не требует cycle path (`:19`).

**Рекомендация:** Добавить локальное требование и включить его в контрактный тест frontier.

**Готовая правка:**

```
Добавить в S3 requirements: `- **REQ-013** (unwanted): If the Blocked-by graph contains a cycle, then frontier validation shall fail and output the complete cycle path. <!-- umbrella REQ-022 -->`. Изменить Task 1 Covers на `REQ-003, REQ-013`, а Eval дополнить кейсами self-cycle и A→B→C→A с проверкой `cycle_path=A,B,C,A`.
```

#### [sdd-vision-pipeline] SVP-004 · eval · `.memory-bank/specs/sdd-vision-pipeline/tasks.md:8-154`

**Проблема:** Все umbrella-задачи нарушают собственный контракт `Eval` на задачу.

**Доказательство:** T1 содержит команду только внутри Testing (`tasks.md:19-20`), T2–T8 имеют Testing/DoD, но ни одного поля `**Eval:**`. Это противоречит D-05 (`context/sdd-vision-pipeline.md:40`) и umbrella REQ-003/005.

**Рекомендация:** Дать T1 корректный Eval, а для мета-задач определить детерминированную проверку child-слайса либо явно сделать их неисполняемыми.

**Готовая правка:**

```
Для T1 записать `**Eval:** grep -qi 'mattpocock/skills' README.md && grep -qi 'mattpocock/skills' commands/discuss.md`. Для T2–T8 добавить `**Delegate:** <child-topic>` и `**Eval:** bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/<child-topic> && test "$(rg -c '^- \[ \]' .memory-bank/specs/<child-topic>/tasks.md)" -eq 0`; контракт `Delegate` описать в umbrella design Interfaces.
```

#### [sdd-vision-pipeline] SVP-005 · eval · `.memory-bank/specs/svp-adapt-escalation/tasks.md:75-86`

**Проблема:** Eval S5-T5 уже green до реализации.

**Доказательство:** Eval — `grep -q 'stub' agents/plan-verifier.md` (`tasks.md:83`). Он сейчас возвращает exit 0 из-за существующих общих упоминаний stub в `agents/plan-verifier.md:79` и `:170`, хотя требуемого feature-flag + backlog-link gate ещё нет.

**Рекомендация:** Заменить grep на негативный поведенческий тест verifier gate.

**Готовая правка:**

```
Заменить Eval на `bats tests/bats/test_plan_verifier_stub_gate.bats`; тест должен сначала создать fixture с bare stub и ожидать FAIL, затем fixture со stub + feature flag + backlog reference и ожидать PASS.
```

#### [sdd-vision-pipeline] SVP-006 · eval · `Child tasks с grep Eval`

**Проблема:** Многие Eval проверяют упоминание слова, а не заявленное поведение.

**Доказательство:** Примеры: `grep -qi 'brief' commands/discuss.md` якобы проверяет Phase-0 handoff (`svp-brief/tasks.md:52`); `grep -qE 'Eval' ... && grep ... 'red'` якобы проверяет red→green lifecycle (`svp-sdd-core/tasks.md:106`); `grep -q 'adapt' ...` якобы проверяет ADaPT fork (`svp-adapt-escalation/tasks.md:66`). Риски слабых grep прямо признаны в `svp-interview-upgrade/design.md:76`, но компенсированы только LLM/manual review.

**Рекомендация:** Поведенческие требования должны проверяться bats/pytest; grep оставить только для чисто документационных требований.

**Готовая правка:**

```
Заменить: S7-T3 → `bats tests/bats/test_brief_discuss_handoff.bats`; S2-T4 → `bats tests/bats/test_sdd_pipeline.bats`; S2-T5 → `bats tests/bats/test_sdd_spec_review_dispatch.bats`; S2-T6 → `bats tests/bats/test_work_eval_first.bats`; S5-T3/T4 → `bats tests/bats/test_work_adapt_integration.bats`; S3-T4 → `bats tests/bats/test_work_parallel_orchestration.bats`. В каждом Testing удалить формулировку `ручной Scenario` как единственный behavioral gate.
```

#### [sdd-vision-pipeline] SVP-007 · cross-slice · `Child requirements.md:1; svp-roadmap-backlog-db/design.md:11-15; svp-parallel-engine/design.md:26-27`

**Проблема:** Group/DAG metadata отсутствуют и в фактических child-спеках, и в межслайсовом контракте.

**Доказательство:** Все семь child requirements.md начинаются сразу с `# Requirements`, то есть не имеют frontmatter `group`/`ice`. S4-C1 требует только group/ice/pin (`design.md:11-12`), а S3-C5 обещает исполнение группы по DAG (`parallel-engine/design.md:26-27`), не определяя поле `blocked_by`, формат результата и exit-коды.

**Рекомендация:** Сделать frontmatter единственным источником group DAG и привести существующие child-спеки к этой схеме.

**Готовая правка:**

```
Добавить во frontmatter каждого child: `group: sdd-vision-pipeline`, объект `ice`, и `blocked_by: [...]`. Для S1/S4/S2/S6 — `[]`; S7 — `[svp-interview-upgrade]`; S3 — `[svp-sdd-core]`; S5 — `[svp-sdd-core, svp-parallel-engine]`. В S4-C1 добавить `blocked_by: [<spec-slug>...]`; в S3-C5 определить JSON-вывод `{group,members:[{topic,ice,blocked_by}]}` и exit 0/1(not found)/2(malformed DAG).
```

#### [sdd-vision-pipeline] SVP-008 · cross-slice · `sdd-vision-pipeline/design.md:28-30; svp-brief/design.md:8; svp-adapt-escalation/design.md:8`

**Проблема:** DAG разрешает запуск child-слайсов до обязательных поставщиков.

**Доказательство:** Umbrella объявляет S7 и S1 одновременно незаблокированными (`design.md:28`), хотя S7 использует secret-scan контракт S1 (`svp-brief/design.md:8`). S5 blocked only by S2 (`umbrella design.md:30`), но при отсутствии S3 отключает Scope guard (`svp-adapt-escalation/design.md:8`), несмотря на обязательный guard umbrella REQ-030.

**Рекомендация:** Сделать зависимости hard, иначе verify child-слайса не может подтвердить все Covers.

**Готовая правка:**

```
Изменить DAG: `S7 blocked_by: S1`; `S3 blocked_by: S2`; `S5 blocked_by: S2, S3`. Обновить umbrella design, tasks headings, roadmap Blocked by и child frontmatter одним и тем же набором.
```

#### [sdd-vision-pipeline] SVP-009 · contract · `svp-sdd-core/design.md:15-19,54,60; svp-parallel-engine/design.md:3-4,55`

**Проблема:** Грамматика Scope оставлена на будущую совместную ревизию, хотя S3 заблокирован S2 и должен потреблять готовый контракт.

**Доказательство:** S2-C1 говорит только `<glob-list>` (`design.md:16`), затем признаёт расхождение (`:54`) и оставляет грамматику открытым вопросом (`:60`). S3 сообщает, что первый шаг — ревизия уже выпущенного S2-C1 (`parallel-engine/design.md:3-4`). Реализатор вынужден угадывать разделители, `**`, нормализацию и запрещённые пути.

**Рекомендация:** Зафиксировать Scope grammar в S2 до начала S3 и дословно сослаться на неё в S3.

**Готовая правка:**

```
В S2-C1 записать: `Scope is a comma-separated list of repository-relative glob patterns. Trim whitespace; reject absolute paths, .. segments and empty items. Glob matching reuses the matcher semantics of mb-work-protected-check.sh; ** is recursive. Task-agent Scope may not include .memory-bank/**.` В S3-C3 заменить свободный `<globs>` ссылкой `parsed scope[] from S2-C1`.
```

#### [sdd-vision-pipeline] SVP-010 · edge-case · `.memory-bank/specs/svp-parallel-engine/design.md:17-18`

**Проблема:** Claim алгоритм допускает двойного победителя в гонке.

**Доказательство:** C2 предлагает `append + пост-проверка последней записи`. Если процесс A append+check завершит до append процесса B, оба увидят себя последними и оба объявят claim успешным. В репозитории уже есть переносимый mkdir-lock паттерн: `scripts/mb-work-progress-append.sh:17-18,62-69`.

**Рекомендация:** Сериализовать read-check-append одной переносимой блокировкой.

**Готовая правка:**

```
Переписать C2: `Mutating operations acquire an owner-token mkdir lock at <bank>/tmp/.work-claims.lock; under the lock read the latest event for task_id, validate transition, append one JSONL event, then release. Exit: 0 success; 1 occupied/not-owner; 2 usage or malformed state; 3 lock timeout. Lock TTL and stale-owner handling reuse mb-work-progress-append.sh.`
```

#### [sdd-vision-pipeline] SVP-011 · contract · `.memory-bank/specs/svp-brief/requirements.md:18-21; design.md:6-22`

**Проблема:** Интерфейс `/mb brief` не определяет, как передаются request и attachments.

**Доказательство:** REQ-001 требует копировать attached source documents (`requirements.md:18`), но design описывает только валидатор, каталог, handoff и router. Нет CLI-аргументов, правил множественных inputs, ошибок отсутствующего файла или конфликтов имён. Open question `--from-file` (`design.md:47`) откладывает часть основного входного контракта.

**Рекомендация:** Зафиксировать command contract до реализации.

**Готовая правка:**

```
Добавить C0: ``/mb brief <topic> [--request <text> | --request-file <path>] [--input <path>]... [--auto]``. Требуется ровно один request source; `--input` повторяем, принимает существующий regular file; одинаковые basename → fail с перечислением конфликтов; отсутствующий/нечитаемый input → fail до создания каталога; без input создаётся пустой `inputs/`; результат — путь `briefs/<topic>/brief.md` и предложение `/mb discuss <topic>`.
```

#### [sdd-vision-pipeline] SVP-012 · parent-decision · `.memory-bank/context/sdd-vision-pipeline.md:46; umbrella requirements.md:60; svp-interview-upgrade/requirements.md:44-47`

**Проблема:** D-11 потерян: остался отказ от decomposition, но исчез общий fast-to-code bypass интервью.

**Доказательство:** D-11 требует всегда доступную возможность отказаться от разбиения/интервью и быстрее перейти к коду (`context:46`). Umbrella REQ-014 и S1 REQ-009 разрешают только отклонить decomposition; требований или задач на bypass оставшегося интервью нет.

**Рекомендация:** Вернуть подтверждённый escape hatch без изменения quality-default.

**Готовая правка:**

```
Добавить umbrella `REQ-049`: `Where the user explicitly selects fast-to-code mode, the system shall allow bypassing the remaining interview and decomposition after recording the choice and its quality trade-off in context frontmatter; quality mode remains the default.` Добавить S1 `REQ-020` с тем же контрактом и включить его в Task 6 Covers/Eval.
```

#### [sdd-vision-pipeline] SVP-013 · parent-decision · `.memory-bank/specs/svp-sdd-core/design.md:30-31`

**Проблема:** Отсутствие red-фазы лишь warning, хотя D-05 и REQ-006 требуют обязательного наблюдаемого red.

**Доказательство:** C6 говорит `отсутствие red-фазы = warning` (`design.md:31`). Parent D-05 требует `observe it fail (red) before implementation` (`context:40`), а umbrella REQ-006 формулирует SHALL (`requirements.md:35`). Warning позволяет закрыть задачу без TDD.

**Рекомендация:** Сделать отсутствие доказательства red блокирующим verify gate.

**Готовая правка:**

```
Заменить последнюю фразу C6 на: `Verify SHALL fail the task when no pre-implementation Eval run with non-zero exit and matching command hash is recorded. Structural Eval that cannot be red requires an explicit waiver in the task and is allowed only for non-gated requirements.`
```

#### [sdd-vision-pipeline] SVP-014 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:14-15`

**Проблема:** JSONL escalation contract пытается записать resolution до того, как пользователь выбрал решение.

**Доказательство:** `mb-work-adapt.sh decide` одновременно возвращает fork и append-запись `{... decision, resolution}` (`design.md:14-15`). В interactive режиме resolution появляется только после AskUserQuestion, но отдельной команды/события для его записи нет.

**Рекомендация:** Разделить trigger/decision и resolution как append-only события.

**Готовая правка:**

```
Изменить C1 на два subcommand: `decide ...` append-ит `{event:"opened", escalation_id, ts, item, triggers, decision}` и печатает `escalation_id`; `resolve --mb <bank> --id <id> --resolution <continue|simplify|replan|skip|stub_continue>` append-ит `{event:"resolved", escalation_id, ts, resolution}`. Exit 2 для неизвестного id/невалидного resolution.
```

#### [svp-adapt-escalation] SVP-AE-001 · feasibility · `.memory-bank/specs/svp-adapt-escalation/tasks.md:10`

**Проблема:** Все специализированные роли записаны с лишним префиксом `mb-`, поэтому `/mb work` маршрутизирует задачи в fallback `mb-developer`.

**Доказательство:** В tasks.md используются `mb-backend`, `mb-architect`, `mb-qa` (строки 10, 61, 78). Парсер формирует `agent = f"mb-{role}"` в scripts/mb_work_items.py:238-240, а pipeline содержит ключи `backend`, `architect`, `qa` в references/pipeline.default.yaml:10-21. Фактический dry-run `mb-work-plan.sh` выдал `agent: mb-developer` для всех пяти задач.

**Рекомендация:** Использовать имена role-ключей pipeline без префикса.

**Готовая правка:**

```
Заменить роли задач по порядку на: T1 `**Role:** backend`; T2 `**Role:** developer`; T3 `**Role:** developer`; T4 `**Role:** architect`; T5 `**Role:** qa`.
```

#### [svp-adapt-escalation] SVP-AE-002 · sizing · `.memory-bank/specs/svp-adapt-escalation/tasks.md:6-89`

**Проблема:** Задачи не содержат обязательных полей tasks.md v2, поэтому бюджеты ≤120k/≤400k, Scope и DAG нельзя проверить кодом.

**Доказательство:** Design утверждает, что S5 использует tasks.md v2 Eval/Budget (`design.md:3`), но поиск по tasks.md не находит ни одного `Stage`, `Blocked-by`, `Scope` или `Budget`. Контракт S2 требует эти поля (`svp-sdd-core/design.md:15-19`), родительский D-13 задаёт лимиты (`context/sdd-vision-pipeline.md:48`).

**Рекомендация:** Добавить v2-поля ко всем пяти задачам до допуска спеки к исполнению.

**Готовая правка:**

```
Добавить: T1 `Stage: 1`, `Blocked-by: none`, `Scope: scripts/mb-work-adapt.sh, tests/bats/test_mb_work_adapt*.bats`, `Budget: 100000`; T2 `Stage: 1`, `Blocked-by: 1`, `Scope: references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_mb_pipeline_escalation.bats`, `Budget: 40000`; T3 `Stage: 1`, `Blocked-by: 2`, `Scope: commands/work.md, agents/mb-*.md, tests/bats/test_mb_work_adapt_report.bats`, `Budget: 50000`; T4 `Stage: 2`, `Blocked-by: 3`, `Scope: commands/work.md, tests/bats/test_mb_work_adapt_orchestration.bats`, `Budget: 100000`; T5 `Stage: 2`, `Blocked-by: 4`, `Scope: agents/plan-verifier.md, scripts/mb-work-adapt.sh, tests/bats/test_mb_work_adapt_verify.bats`, `Budget: 60000`.
```

#### [svp-adapt-escalation] SVP-AE-003 · coverage · `.memory-bank/specs/svp-adapt-escalation/requirements.md:41-77`

**Проблема:** Сценарии не являются машиночитаемыми, а REQ-006/007 не имеют даже семантических сценариев.

**Доказательство:** Секция содержит только заголовки `### Scenario` и GIVEN/WHEN/THEN, без `<!-- mb-scenario:N -->` и `**Covers:**`. scripts/mb-scenario-extract.py возвращает пустой результат. Формат обязателен для исполняемого test-plan (`rules/RULES.md:586-591`), а D-06 требует сценарий для gated REQ.

**Рекомендация:** Оформить существующие сценарии в стандартном формате и добавить два недостающих.

**Готовая правка:**

```
Перед пятью существующими сценариями добавить последовательные `<!-- mb-scenario:N -->`, а после заголовков — `**Covers:** REQ-001`, `REQ-002, REQ-003`, `REQ-004, REQ-009`, `REQ-005`, `REQ-008`. Добавить сценарий REQ-006: GIVEN выбран replan/decomposition; WHEN решение подтверждено; THEN новая child-спека зарегистрирована через decomposed-spec registry и получает interview/self-interview. Добавить сценарий REQ-007: GIVEN развилка завершилась решением; WHEN resolution зафиксирован; THEN ровно одна валидная JSONL-запись содержит trigger и resolution.
```

#### [svp-adapt-escalation] SVP-AE-005 · cross-slice · `.memory-bank/specs/svp-adapt-escalation/design.md:14`

**Проблема:** Enum режима и Scope-вердикта не совпадает с контрактом S3.

**Доказательство:** S5 принимает `--mode auto|interactive` и неопределённый `--scope-status S`. S3 сохраняет режимы `HITL|autonomous` (`svp-parallel-engine/design.md:23-24`) и выдаёт `scope=ok|violation` (`svp-parallel-engine/design.md:20-21`). Без маппинга S3 не может вызвать S5 однозначно.

**Рекомендация:** Установить единый runtime-enum и явно описать graceful degradation.

**Готовая правка:**

```
В C1 записать: `--mode autonomous|hitl` — канонические значения; `auto` является alias `autonomous`, `interactive` — alias `hitl`. `--scope-status ok|violation|unavailable`; только `violation` триггерит fork, `unavailable` добавляется в `degraded_guards` и явно попадает в summary.
```

#### [svp-adapt-escalation] SVP-AE-006 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:20-21`

**Проблема:** Описан только внутренний JSON-объект сигнала, но не контракт полного отчёта, извлечения или ошибки парсинга.

**Доказательство:** Context требует сигнал в «структурном отчёте» (`context/svp-adapt-escalation.md:30`), однако существующие role-agent контракты завершаются Markdown STATUS и SendMessage, например `agents/mb-developer.md:27-48`. C3 не задаёт delimiter, `null` для отсутствия сигнала, обязательность финальной строки или поведение malformed JSON.

**Рекомендация:** Зафиксировать единственный машинно-парсируемый envelope для всех исполнителей и fail-loud обработку повреждённого блока.

**Готовая правка:**

```
Добавить в C3: последний непустой блок отчёта обязан быть `MB_WORK_RESULT_JSON={"status":"DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT","complexity_escalation":null|{"reason":"<non-empty>","estimated_tokens":<positive-int>}}`. Отсутствие ключа трактуется как contract error; `null` — сигнала нет; malformed JSON/пустой reason/неположительная оценка → halt + `invalid_implementer_report`, никогда silent ignore. Перечислить точные файлы: developer, backend, frontend, ios, android, architect, devops, qa, analyst.
```

#### [svp-adapt-escalation] SVP-AE-007 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:14-15`

**Проблема:** `decide` обещает записать `resolution`, хотя интерактивное решение ещё неизвестно; обновить запись затем нечем.

**Доказательство:** C1 одновременно возвращает `fork_user` и append-ит JSONL с `resolution` (`design.md:14-15`). REQ-007 требует логировать каждую эскалацию и её разрешение (`requirements.md:37`). NFR требует совместимость с pivot-log (`context/svp-adapt-escalation.md:49`), но S5 использует `item`, тогда как pivot-log использует `item_id`, `cycle`, `mode` (`scripts/mb-work-pivot.sh:37-40`).

**Рекомендация:** Разделить принятие решения и финальную запись resolution, определить строгую схему и конкурентную запись одной строкой.

**Готовая правка:**

```
Заменить C1 на два subcommand: `decide ...` печатает JSON `{"event_id","decision","triggers","degraded_guards"}` без записи resolution; `record --event-id ID --item-id KEY --cycle N --decision MODE --resolution RESOLUTION [--backlog-id I-NNN]` атомарно append-ит одну строку в `<bank>/tmp/escalations.jsonl`. Схема строки: `ts,event_id,item_id,cycle,mode,triggers[],resolution,backlog_id,degraded_guards[]`. Повторный event_id — idempotent no-op; конфликтующее повторение — exit 1.
```

#### [svp-adapt-escalation] SVP-AE-008 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:23-24`

**Проблема:** Четыре интерактивных варианта являются только labels; их влияние на work-state, checkbox и повторный trigger не задано.

**Доказательство:** C4 перечисляет continue/simplify/replan/skip, но не описывает переходы состояния. Текущий work-item status допускает только pending/in-progress/done (`commands/work.md:270`), а checkbox можно переворачивать только после успешного done (`commands/work.md:449-455`).

**Рекомендация:** Для каждого resolution определить точный переход и запретить ложное завершение skipped/replanned item.

**Готовая правка:**

```
Добавить в C4: `continue_anyway` — записать override и продолжить текущий item, подавив только тот же trigger до следующей фазы; `simplify` — оставить item pending, остановить исполнение и потребовать утверждённую правку Scope/DoD перед новым run; `replan_decompose`/`replan_requirement_change` — оставить item pending, зарегистрировать новую spec/change и завершить текущий run без checkbox flip; `skip` — добавить `adapt_skip` в work-state steps, перейти к следующему item без checkbox flip и перечислить незакрытый item в итоговом summary.
```

#### [svp-adapt-escalation] SVP-AE-009 · parent-decision · `.memory-bank/specs/svp-adapt-escalation/design.md:23-27`

**Проблема:** Контракт stub/backlog/verify оставлен на усмотрение LLM и не соблюдает «MD как БД» и orchestrator-only запись банка.

**Доказательство:** C4 говорит лишь «feature-флаг + docstring + беклог», C5 — «найден stub-маркер», но сам marker, имя флага, default-off, связь с I-NNN и кодовая проверка не заданы. S4 предоставляет script-контракт backlog (`svp-roadmap-backlog-db/design.md:17-24`), D-23 разрешает писать банк только оркестратору (`context/sdd-vision-pipeline.md:58`).

**Рекомендация:** Сделать stub и backlog machine-verifiable, а запись backlog выполнять только через оркестраторские скрипты.

**Готовая правка:**

```
Добавить: docstring стаба содержит строку `MB-ADAPT-STUB backlog=I-NNN flag=<NAME>`; `<NAME>` — существующий или созданный named default-off feature flag. Оркестратор вызывает `mb-idea.sh "[ADAPT] <item>: <reason>" HIGH <bank>`, сохраняет возвращённый I-NNN, а при наличии S4 переводит запись через backlog-state API. Добавить `mb-work-adapt.sh verify-stub --diff <range> --backlog <path>`: каждый marker обязан ссылаться на существующий backlog ID и flag token в том же changed file; нарушение → exit 1.
```

#### [svp-adapt-escalation] SVP-AE-011 · eval · `.memory-bank/specs/svp-adapt-escalation/tasks.md:83`

**Проблема:** Eval T5 — фальшивый red: он уже проходит в текущем репозитории.

**Доказательство:** Eval — `grep -q 'stub' agents/plan-verifier.md`. Файл уже содержит `stub` в текущей проверке placeholder-ов (`agents/plan-verifier.md:79`) и критериях (`agents/plan-verifier.md:170`); фактический exit-код grep равен 0 до реализации.

**Рекомендация:** Заменить grep на новый поведенческий тест, который действительно красный без ADaPT-гейта.

**Готовая правка:**

```
Заменить Eval T5 на `bats tests/bats/test_mb_work_adapt_verify.bats`. Кейсы: marker+flag+существующий I-NNN → pass; отсутствует flag → fail; отсутствует backlog ID → fail; голый NotImplemented/TODO → fail; два валидных stub → оба перечислены в summary.
```

#### [svp-adapt-escalation] SVP-AE-012 · eval · `.memory-bank/specs/svp-adapt-escalation/tasks.md:32-69`

**Проблема:** Eval T2–T4 проверяют слова, а не заявленные контракты; T4 переносит ключевое поведение в ручную проверку.

**Доказательство:** T2 ищет любое `escalation` (`tasks.md:32`) и не проверяет defaults/ranges; T3 проверяет только mb-developer, хотя DoD требует всех исполнителей (`tasks.md:47-55`); T4 проходит от любых слов `adapt` и `stub` (`tasks.md:66`), а auto/interactive проверяются вручную (`tasks.md:69`). Это слабее D-05/D-25 и пользовательского требования кодовых eval.

**Рекомендация:** Заменить word-grep на fixture-driven Bats/структурные проверки точного контракта.

**Готовая правка:**

```
T2 Eval: `bats tests/bats/test_mb_pipeline_escalation.bats` с defaults 3/3/2, cascade=3 и отказом для zero/negative/non-int/unknown key. T3 Eval: `bats tests/bats/test_mb_work_adapt_report.bats` плюс цикл grep по developer/backend/frontend/ios/android/architect/devops/qa/analyst. T4 Eval: `bats tests/bats/test_mb_work_adapt_orchestration.bats` с проверкой порядка adapt-before-pivot, четырёх resolution, auto stub path, decomposition registry, skip без checkbox flip и полного summary.
```

#### [svp-adapt-escalation] SVP-AE-013 · consistency · `.memory-bank/context/svp-adapt-escalation.md:62`

**Проблема:** Решение «третья подряд эскалация останавливает run» потеряло stop-семантику и не имеет REQ/Covers.

**Доказательство:** Context требует «каскад эскалаций (>2 подряд) — стоп» (`context/svp-adapt-escalation.md:62`). Design оставляет лишь рекомендацию (`design.md:24`), а сценарий заканчивается только рекомендацией (`requirements.md:73-77`). Ни один REQ не формулирует stop, хотя T1 упоминает cascade.

**Рекомендация:** Восстановить принятое поведение как gated requirement и определить reset последовательности.

**Готовая правка:**

```
Добавить `REQ-010 (unwanted): If cascade_stop consecutive ADaPT escalations occur within one run, then the system shall stop before dispatching the next item and report a recommendation to revise the whole spec.` Уточнить: успешное завершение item без эскалации сбрасывает consecutive count; двойной trigger одной развилки считается одной эскалацией. Добавить REQ-010 в Covers T1 и T4 и к cascade-сценарию.
```

#### [svp-docs-wiki] F-001 · coverage · `.memory-bank/specs/svp-docs-wiki/requirements.md:41-71`

**Проблема:** Ни один сценарий не распознаётся SDD-инструментами, а REQ-003, REQ-008 и REQ-009 не имеют даже эквивалентного прозаического сценария.

**Доказательство:** `.memory-bank/specs/svp-docs-wiki/requirements.md:41-71` содержит заголовки GIVEN/WHEN/THEN, но не содержит `<!-- mb-scenario:N -->` и `**Covers:**`. Канонический формат обязателен по `rules/RULES.md:586-591`. Фактический запуск `python3 scripts/mb-scenario-extract.py .memory-bank/specs/svp-docs-wiki/requirements.md` вернул ноль записей.

**Рекомендация:** Преобразовать существующие пять сценариев в канонические блоки и добавить сценарии для provenance/read-only и lint.

**Готовая правка:**

```
Перед существующими сценариями добавить маркеры и Covers: scenario:1→REQ-001,REQ-002,REQ-006; scenario:2→REQ-005; scenario:3→REQ-004; scenario:4→REQ-001; scenario:5→REQ-007. Затем добавить: `<!-- mb-scenario:6 -->\n### Scenario: Источники остаются неизменными\n**Covers:** REQ-003, REQ-009\n**GIVEN** существуют graph/wiki и связанные страницы с известными хешами\n**WHEN** выполняется `/mb docs`\n**THEN** evidence pack содержит ссылки на оба источника, страницы содержат wikilinks, а хеши source-файлов не изменяются` и `<!-- mb-scenario:7 -->\n### Scenario: Lint возвращает машинный результат\n**Covers:** REQ-008\n**GIVEN** валидное и отдельно повреждённое wiki-дерево\n**WHEN** выполняется внутренний lint\n**THEN** валидное дерево даёт exit 0, повреждённое — exit 1 и стабильные ключи ошибок`.
```

#### [svp-docs-wiki] F-002 · parent-decision · `.memory-bank/specs/svp-docs-wiki/tasks.md:1-88`

**Проблема:** Child-spec не выполняет родительский task v2 contract: отсутствуют Stage, Blocked-by, Scope и Budget; также нет обязательного group/ICE frontmatter.

**Доказательство:** Родительские решения требуют эти поля: `.memory-bank/context/sdd-vision-pipeline.md:38` — задачи имеют stages, blocked_by, Scope, Eval и budgets; `:49` — task ≤120k и stage ≤400k; `:66` — child-spec содержит group frontmatter. В `.memory-bank/specs/svp-docs-wiki/tasks.md:6-88` у задач есть Covers/What/Eval/DoD/Testing, но нет четырёх обязательных полей. `.memory-bank/specs/svp-docs-wiki/requirements.md:1` начинается сразу с заголовка без frontmatter.

**Рекомендация:** Добавить metadata child-слайса и полностью привести все задачи к task v2 contract.

**Готовая правка:**

```
В начало requirements.md добавить `---\ntopic: svp-docs-wiki\ngroup: sdd-vision-pipeline\nice:\n  impact: 6\n  confidence: 8\n  ease: 7\nstatus: ready\n---`. В каждый mb-task добавить `**Stage:**`, `**Blocked-by:**`, `**Scope:**`, `**Budget:**`; установить T1 Stage 1/none/≤120000, T3-T5 Stage 2/T1/≤60000 каждая, T2 Stage 3/T1,T3,T4,T5/≤60000. Scope должен перечислять только фактически изменяемые файлы.
```

#### [svp-docs-wiki] F-003 · cross-slice · `.memory-bank/specs/svp-docs-wiki/tasks.md:57-71`

**Проблема:** S6 и S2 изменяют одни и те же pipeline-файлы, но машинная зависимость между слайсами не зафиксирована.

**Доказательство:** S6 T4 расширяет `references/pipeline.default.yaml` и `scripts/mb-pipeline-validate.sh` в `.memory-bank/specs/svp-docs-wiki/tasks.md:63`. S2 T5 меняет те же файлы в `.memory-bank/specs/svp-sdd-core/tasks.md:87-92`. При этом `.memory-bank/roadmap.md:92` помечает S6 как Ready и `Blocked by —`, хотя `:96` задаёт порядок S2 → S6.

**Рекомендация:** Сделать последовательность S2 → S6 частью исполняемого dependency contract, а не только текста roadmap.

**Готовая правка:**

```
В frontmatter S6 записать `blocked_by: [svp-sdd-core]`; в задачах S6 T4 записать `**Blocked-by:** svp-sdd-core/T5`; в umbrella DAG и `.memory-bank/roadmap.md` заменить для S6 `Blocked by —` на `Blocked by svp-sdd-core`.
```

#### [svp-docs-wiki] F-004 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:14-18`

**Проблема:** CLI и state contract неполны и внутренне расходятся, поэтому реализация должна угадывать аргументы, JSON-схемы, stdout и exit-коды.

**Доказательство:** `.memory-bank/specs/svp-docs-wiki/design.md:14-15` перечисляет только имена операций `state`, `packs --since`, `write-page`, `log-append`, `index`, `set-sha`, `lint`. На `:17-18` state описан как `{sha, updated_at, pages...}`, тогда как C1 обещает `last_run`; точные типы, форматы pack/output и exit-коды отсутствуют. Контракт-ферст обязателен по `rules/RULES.md:228-233`.

**Рекомендация:** Заменить перечень операций полным versioned CLI/state contract.

**Готовая правка:**

```
Записать в §Interfaces: `python3 scripts/mb-docs.py [--repo-root PATH] [--mb-path PATH] [--docs-path PATH] <state|packs|write-page|log-append|index|set-sha|lint>`. State schema: `{"version":1,"sha":null|"<40-hex>","updated_at":null|"<RFC3339>","pages":{"<slug>":{"source_files":["<repo-relative>"],"updated_at":"<RFC3339>"}}}`. `state` печатает один JSON; `packs` печатает JSONL с ключами `pack_id,mode,files,path/status,symbols,wiki_refs,excerpts`; mutating commands печатают один result JSON. Exit codes: 0 success/no-op, 2 usage/schema, 3 git unavailable, 4 unreachable base SHA, 5 I/O или validation failure. Удалить `last_run` либо определить его как точный alias `updated_at`.
```

#### [svp-docs-wiki] F-005 · edge-case · `.memory-bank/specs/svp-docs-wiki/design.md:26-30`

**Проблема:** Не определена атомарность run: частичный сбой после записи страниц может привести к продвижению SHA и безвозвратному пропуску изменений.

**Доказательство:** Pipeline на `.memory-bank/specs/svp-docs-wiki/design.md:26-30` описан только как последовательность diff→packs→agents→write→lint→state. Контекст требует empty diff no-op и обработку unreachable SHA в `.memory-bank/context/svp-docs-wiki.md:56-59`, но не задаёт lock, snapshot SHA, dirty-worktree policy и commit point. T1 отдельно реализует `write-*` и `set-sha` на `.memory-bank/specs/svp-docs-wiki/tasks.md:12`, оставляя опасный порядок вызовов на усмотрение исполнителя.

**Рекомендация:** Определить один транзакционный run contract, где state является последней commit-точкой.

**Готовая правка:**

```
Добавить в design: `run получает target_sha=HEAD один раз, берёт exclusive lock <docs.path>/.mb-docs.lock и строит diff base_sha..target_sha. Dirty tracked worktree является exit 2 без записи. Page/index/log пишутся через temp+atomic rename. State SHA обновляется последним и только после успешной записи всех артефактов и lint exit 0. Любой сбой удаляет временные файлы, сохраняет прежний state и возвращает ненулевой exit. Empty diff не меняет pages/log/state. Unreachable base SHA возвращает exit 4 и не запускает автоматический bootstrap.`
```

#### [svp-docs-wiki] F-006 · contract · `.memory-bank/context/svp-docs-wiki.md:25,58`

**Проблема:** Правила разрешения docs.path и обнаружения переноса state не определены; требуемое предупреждение после смены пути технически невозможно получить только из нового каталога.

**Доказательство:** `.memory-bank/context/svp-docs-wiki.md:25` кладёт state в `<docs.path>/.mb-docs-state.json`, а `:58` требует предупреждать при переименовании/смене docs.path. `.memory-bank/specs/svp-docs-wiki/design.md:17-18` описывает лишь чтение state по текущему пути. Решение интервью `.memory-bank/context/svp-docs-wiki-interview.md:11` отклоняет env и выбирает pipeline config, но precedence и path validation отсутствуют.

**Рекомендация:** Зафиксировать precedence, containment и детерминированный path-mismatch check.

**Готовая правка:**

```
Добавить: `docs.path разрешается в порядке CLI --docs-path > project pipeline.yaml docs.path > default docs/. Путь должен быть repo-relative, после realpath оставаться внутри repo, не содержать '..' и не проходить через symlink наружу. Перед bootstrap оркестратор ищет tracked `.mb-docs-state.json` вне resolved docs.path; если найден ровно один, возвращает exit 2 с error=path_mismatch, old_path и new_path. При нескольких кандидатах возвращает error=ambiguous_state. Автоматический перенос запрещён.`
```

#### [svp-docs-wiki] F-007 · parent-decision · `.memory-bank/specs/svp-docs-wiki/requirements.md:38-39`

**Проблема:** Не задана честная деградация при отсутствии graph/wiki или host-subagent транспорта, хотя родительская спека требует fail-open/honest degradation.

**Доказательство:** REQ-009 на `.memory-bank/specs/svp-docs-wiki/requirements.md:39` требует reuse существующих graph/wiki, но не задаёт поведение при их отсутствии; фактически `.memory-bank/codebase/wiki/` сейчас отсутствует. Родительские NFR требуют cross-platform honest degradation в `.memory-bank/context/sdd-vision-pipeline.md:127-129`. Решение интервью `.memory-bank/context/svp-docs-wiki-interview.md:10` требует host subagents и отклоняет прямой API, но failure mode не описан.

**Рекомендация:** Добавить два unwanted-behaviour REQ и покрыть их задачами и кодовыми Eval.

**Готовая правка:**

```
Добавить `REQ-010: IF graph или wiki отсутствует/нечитаем, THEN оркестратор SHALL продолжить из git diff/excerpts, вернуть `degraded_sources` и SHALL NOT создавать либо изменять отсутствующий источник.` Добавить `REQ-011: IF выбранный host не предоставляет требуемый subagent dispatch/model tier, THEN оркестратор SHALL завершиться до записи файлов с `platform_limited`, ненулевым exit и неизменным state.` Добавить Covers REQ-010 к pack task, REQ-011 к command/agent task и pytest-сценарии для обоих режимов.
```

#### [svp-docs-wiki] F-008 · feasibility · `.memory-bank/specs/svp-docs-wiki/tasks.md:40-54`

**Проблема:** T3 ссылается на несуществующий шаблон report-delivery/SendMessage и не определяет форматы результатов writer/synthesizer.

**Доказательство:** `.memory-bank/specs/svp-docs-wiki/tasks.md:46` требует report-delivery contract `(SendMessage)` «по образцу mb-wiki-*». Фактически `agents/mb-wiki-author.md:9-11,46` требует вернуть только Markdown-статью, а `agents/mb-wiki-synthesizer.md:17-38` — отдельный строгий JSON; поиск `rg 'Report delivery|SendMessage' agents/mb-wiki-*` не находит такого контракта.

**Рекомендация:** Убрать ложную ссылку на precedent и определить два точных output contracts; запись банка оставить только оркестратору.

**Готовая правка:**

```
Заменить T3/Design текстом: `mb-docs-writer возвращает ровно JSON {"page":{"slug":string,"title":string,"body_markdown":string,"source_files":[string],"wikilinks":[string]}}. mb-docs-synthesizer возвращает ровно JSON {"index_entries":[{"path":string,"summary":string}],"log_entry":{"sha":string,"pages":[string],"summary":string}}. Агентам запрещены file-write tools; оркестратор валидирует JSON schema и единолично вызывает write-page/index/log-append.`
```

#### [svp-docs-wiki] F-009 · eval · `.memory-bank/specs/svp-docs-wiki/tasks.md:31,48,65`

**Проблема:** Eval задач T2–T4 проверяют наличие слов/файлов, а не заявленные CLI, agent и config contracts; T4 способен стать ложнозелёным.

**Доказательство:** T2 Eval на `.memory-bank/specs/svp-docs-wiki/tasks.md:31` — только `grep -q '### docs' commands/mb.md`. T3 Eval на `:48` проверяет существование файлов и строку `Report delivery`, не output schema или write prohibition. T4 Eval на `:65` проверяет строку `docs:` и запуск общего validator; текущий `scripts/mb-pipeline-validate.sh:352-364` проверяет обязательные ключи, но не отвергает и не валидирует неизвестный `docs`, поэтому произвольный `docs:` сделает Eval зелёным.

**Рекомендация:** Заменить grep-эвалы исполняемыми contract tests с exact assertions.

**Готовая правка:**

```
Для T2 записать `**Eval:** pytest -q tests/pytest/test_mb_docs_command.py` с проверками router, dry-run, empty diff и точной последовательности операций. Для T3: `pytest -q tests/pytest/test_mb_docs_agents.py`, проверяющий регистрацию tiers, JSON schemas, запрет write tools и orchestration-only writes. Для T4: `bats tests/bats/test_mb_docs_pipeline.bats`, проверяющий default `docs/`, project override, wrong type, absolute path, `..`, symlink escape и фактический resolver, а не наличие YAML-ключа.
```

#### [svp-docs-wiki] F-010 · eval · `.memory-bank/specs/svp-docs-wiki/tasks.md:82`

**Проблема:** Негативная половина T5 Eval принимает любой ненулевой exit, включая crash, usage error и отсутствие скрипта.

**Доказательство:** `.memory-bank/specs/svp-docs-wiki/tasks.md:82` использует `! python3 scripts/mb-docs.py lint --docs tests/fixtures/broken-docs`. Такая проверка зелёная для любого failure mode и не подтверждает REQ-008 про broken links, missing index entries, index format и source leakage.

**Рекомендация:** Проверять точный exit-код и структурированный набор нарушений для каждого правила lint.

**Готовая правка:**

```
Заменить Eval на `bats tests/bats/test_mb_docs_lint.bats`. Тесты должны отдельно утверждать: valid fixture→exit 0; broken wikilink→exit 1 и `error=broken_wikilink`; отсутствующий index entry→exit 1 и `error=missing_index_entry`; malformed index→exit 1 и `error=invalid_index_entry`; source leakage→exit 1 и `error=source_leakage`; invalid CLI/schema→exit 2.
```

#### [svp-docs-wiki] F-011 · consistency · `.memory-bank/context/svp-docs-wiki.md:64,68`

**Проблема:** Публичность lint остаётся открытым решением, но T5 поручает исполнителю решить её во время разработки.

**Доказательство:** `.memory-bank/context/svp-docs-wiki.md:64` исключает query/lint как отдельные публичные команды из scope, а `:68` оставляет `/mb docs --lint` открытым вопросом. `.memory-bank/specs/svp-docs-wiki/tasks.md:80` требует «решить, нужен ли публичный `/mb docs --lint`», нарушая требование исполнимой спеки без продуктовых догадок.

**Рекомендация:** Закрыть решение до реализации в пользу минимального уже необходимого внутреннего lint.

**Готовая правка:**

```
Записать в context/design/tasks: `В v1 lint является внутренним subcommand scripts/mb-docs.py lint и обязательным verification step обычного /mb docs run. Публичный /mb docs --lint не добавляется в этом слайсе.` Удалить Open Question и фразу «решить, нужен ли» из T5.
```

#### [svp-docs-wiki] F-012 · feasibility · `.memory-bank/specs/svp-docs-wiki/tasks.md:63`

**Проблема:** Dogfood override `docs/wiki` остаётся внутри публикуемого MkDocs-дерева и противоречит исключению публикации из scope.

**Доказательство:** T4 задаёт project override `docs/wiki` в `.memory-bank/specs/svp-docs-wiki/tasks.md:63`. `mkdocs.yml:5` устанавливает `docs_dir: docs`, а `:74-79` описывает строгую nav/orphan integrity. `.memory-bank/context/svp-docs-wiki.md:64` явно исключает публикацию; `CLAUDE.md:69` фиксирует English-only docs site, тогда как generated project wiki не имеет такого контракта.

**Рекомендация:** Dogfood-хранилище разместить вне MkDocs docs_dir, не меняя пользовательский default `docs/`.

**Готовая правка:**

```
Заменить project dogfood override на `.memory-bank/pipeline.yaml: docs.path: project-wiki/`. В design явно записать: `Default для внешнего проекта остаётся docs/; override этого репозитория — project-wiki/, вне mkdocs docs_dir. Публикация generated wiki и добавление его в mkdocs nav не входят в слайс.`
```

#### [svp-docs-wiki] F-013 · sizing · `.memory-bank/specs/svp-docs-wiki/tasks.md:6-20`

**Проблема:** T1 объединяет state machine, git diff, batching, packs, storage, index/log и lint; это task-монстр и дублирует ответственность T5.

**Доказательство:** `.memory-bank/specs/svp-docs-wiki/tasks.md:12` помещает в T1 семь CLI-операций, bootstrap/delta, unreachable SHA, batching, запись страниц, лог, индекс и lint. T5 на `:74-88` повторно реализует lint. Design сводит всё к одному `scripts/mb-docs.py` на `.memory-bank/specs/svp-docs-wiki/design.md:7`, хотя `rules/RULES.md:137` считает интерфейс с более чем тремя разнородными публичными методами кандидатом на разделение. Числового batching cap нет, несмотря на edge case `.memory-bank/context/svp-docs-wiki.md:57`.

**Рекомендация:** Оставить mb-docs.py тонким dispatcher и разделить T1 по ответственностям с явными лимитами evidence pack.

**Готовая правка:**

```
Сузить T1 до versioned state + atomic store в `memory_bank_skill/docs_state.py`. Добавить отдельную задачу pack builder в `memory_bank_skill/docs_ingest.py` с лимитами не более 12 файлов, 40 excerpt lines, 10 symbols и 5 decision/wiki refs на pack; добавить отдельную задачу page/index/log store в `memory_bank_skill/docs_store.py`. T5 единолично владеет `memory_bank_skill/docs_lint.py`. `scripts/mb-docs.py` остаётся тонким CLI dispatcher. Каждой задаче задать Budget ≤120000, а сумме Stage ≤400000.
```

#### [svp-interview-upgrade] SVP-IU-001 · coverage · `.memory-bank/specs/svp-interview-upgrade/requirements.md:78`

**Проблема:** Ни один сценарий не является машиночитаемым и не обеспечивает обязательный scenario gate.

**Доказательство:** В `.memory-bank/specs/svp-interview-upgrade/requirements.md:78-114` сценарии оформлены обычными заголовками и GIVEN/WHEN/THEN, но без `<!-- mb-scenario:N -->` и `**Covers:**`. Формат сценарного блока закреплён в `rules/RULES.md:587-591`. Родительское решение D-06 требует GIVEN/WHEN/THEN + Eval для всех SHALL/MUST-требований, а все 19 child-REQ сформулированы через SHALL.

**Рекомендация:** Преобразовать сценарии в канонические блоки и добавить сценарии для требований, не покрытых существующими примерами.

**Готовая правка:**

```
Перед каждым сценарием добавить последовательный `<!-- mb-scenario:N -->`, затем строку `**Covers:** REQ-...`. Сохранить существующие 6 сценариев и добавить gated-сценарии минимум для `REQ-001, REQ-005, REQ-006, REQ-011, REQ-014, REQ-015, REQ-016, REQ-017, REQ-019`. После правки требовать успешный запуск `python3 scripts/mb-scenario-extract.py --validate .memory-bank/specs/svp-interview-upgrade/requirements.md`.
```

#### [svp-interview-upgrade] SVP-IU-002 · eval · `.memory-bank/specs/svp-interview-upgrade/tasks.md:19`

**Проблема:** Пять из шести задач принимаются по наличию слов, а не по заявленному поведению.

**Доказательство:** Eval для T1, T2, T4, T5 и T6 в `tasks.md:19,39,80,100,120` состоят из `grep`. Их Testing-секции в `tasks.md:22,42,83,103,123` оставляют ключевые сценарии ручной проверке. `design.md:76` прямо признаёт, что grep проверяет только наличие текста, и предлагает компенсировать это LLM-review и manual scenarios. Это противоречит D-05 о детерминированном кодовом Eval.

**Рекомендация:** Сохранить grep только как дополнительную статическую проверку, а приёмку задач перевести на red-first Bats-тесты с fixtures и точными структурными/поведенческими assertions.

**Готовая правка:**

```
Создать до реализации `tests/bats/test_discuss_interview_upgrade.bats`. Для каждой задачи добавить фильтруемый тест: T1 — создание и закрытие interview plan; T2 — frontier ≤4, batch-round и self-review; T4 — clean/secret/private transcript и отсутствие записи при блокировке; T5 — идемпотентное обновление glossary из подтверждённых терминов; T6 — матрица допустимых и ошибочных комбинаций флагов. Заменить каждый `**Eval:** grep ...` на `**Eval:** bats tests/bats/test_discuss_interview_upgrade.bats --filter '<точное имя сценария>'`; grep оставить вторым необязательным check.
```

#### [svp-interview-upgrade] SVP-IU-003 · cross-slice · `.memory-bank/specs/svp-interview-upgrade/design.md:41`

**Проблема:** Контракт secret scanner ссылается на отсутствующий артефакт и расходится с owning-слайсом и privacy-решением.

**Доказательство:** Child-context требует переиспользовать scanner из sdd-openspec без дублирования (`context/svp-interview-upgrade.md:28,36,75`). Child-design требует `scripts/mb-secret-scan.sh <file>` и допускает `<!-- mb-secret-ok -->` (`design.md:41-44,57,77`), но такого файла в репозитории нет. `sdd-openspec-parity/design.md:73-78` описывает только внутреннюю проверку `specs/<topic>/inputs/`, а его T6 расширяет `mb-spec-validate.sh`, не создавая общий CLI (`sdd-openspec-parity/tasks.md:119-136`). Roadmap запускает S1 раньше этого независимого трека. Кроме того, `context/svp-interview-upgrade.md:52,83` и `requirements.md:57,102` допускают только очистку или `<private>`, тогда как pragma позволяет сохранить найденный секрет открытым.

**Рекомендация:** Назначить одного владельца общего scanner-контракта и разделить политики transcript и imported-inputs; transcript policy не должна разрешать pragma bypass.

**Готовая правка:**

```
В T4 явно создать общий `scripts/mb-secret-scan.sh` и заменить C5 текстом: `bash scripts/mb-secret-scan.sh --policy transcript <candidate-file>`; stdout — ровно `scan=clean` или `scan=blocked`; stderr при блокировке — `<file>:<line>:<pattern>`; exit 0 — clean, 1 — finding, 2 — usage/read error. Политика `transcript` игнорирует содержимое внутри `<private>...</private>`, но НЕ признаёт `<!-- mb-secret-ok -->`. Кандидат сначала пишется в `<bank>/tmp/interview-transcript-<topic>.candidate.md`, после exit 0 атомарно переносится в context; при exit 1/2 целевой файл не меняется. Добавить обязательные Bats-тесты clean, key blocked, private allowed, pragma still blocked, target unchanged. В sdd-openspec-parity заменить внутренний дубликат вызовом того же CLI с отдельной политикой `--policy inputs`.
```

#### [svp-interview-upgrade] SVP-IU-004 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:20`

**Проблема:** Формат и алгоритм estimate-контракта оставлены на решение во время реализации.

**Доказательство:** `design.md:20-24` задаёт breakdown с ключами `modules/scripts/tests/docs`, тогда как коэффициенты в `design.md:31-34` используют другие категории: new script, prompt change, Python module, test file, docs page, external API. Не определено, являются значения количеством или токенами, как проверяются subtotal/total и что выводить при malformed input. `design.md:83` прямо оставляет точный flat/nested формат на T3, нарушая contract-first. Также в S1 ещё нет per-task/per-stage чисел, хотя интерфейс обещает проверять три бюджета.

**Рекомендация:** Зафиксировать схему, арифметику, stdout и exit-коды до TDD; в этом слайсе проверять только доступный spec-total, оставив task/stage extension владельцу S2.

**Готовая правка:**

```
Заменить C1/C3 контрактом: `estimated_tokens.breakdown` содержит `shell_scripts`, `prompt_changes`, `python_modules`, `test_files`, `docs_pages`, `external_integrations`; каждая категория имеет `{count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}`; `subtotal=count*unit_tokens`, `total=sum(subtotal)`. CLI: `bash scripts/mb-estimate-check.sh <context-file> [--spec-budget 1000000]`. stdout: `estimate=ok|over_spec|missing|malformed total=<N|0> spec_budget=<N>`; exit 0 — ok, 1 — over_spec, 2 — missing/malformed/usage. S1 сравнивает только spec-total; task/stage budgets пометить контрактом последующего S2. Удалить open question в `design.md:83`.
```

#### [svp-interview-upgrade] SVP-IU-005 · consistency · `.memory-bank/context/svp-interview-upgrade.md:69`

**Проблема:** NFR-002 о кодовой проверке interview plan и transcript потерян между context и design/tasks.

**Доказательство:** `context/svp-interview-upgrade.md:69` требует скриптом проверять наличие и формат estimate, interview plan и transcript. В design описан только `mb-estimate-check.sh`; C2 в `design.md:26-29` и задачи T1/T4 полагаются на prompt-текст, grep и ручной сценарий. Машинного интерфейса для проверки структуры plan/transcript нет.

**Рекомендация:** Добавить детерминированный artifact validator и включить его red-first тесты в T1/T4.

**Готовая правка:**

```
Добавить в § Interfaces: `bash scripts/mb-interview-artifact-check.sh plan|transcript <file> [--require-closed]`. Режим `plan` проверяет обязательные заголовки, только checklist-строки `- [ ]`/`- [x]`, inherited-раздел и отсутствие открытых пунктов при `--require-closed`; режим `transcript` проверяет topic/date, inherited decisions, Q&A, final gate, decisions и rejected alternatives. stdout: `artifact=ok|invalid open_topics=<N>`; stderr: `<file>:<line>:<reason>`; exit 0 — valid, 1 — structurally invalid/open, 2 — usage/read error. T1 сначала добавляет fixtures valid/open/malformed/resume; T4 — valid transcript и missing-section. Eval обеих задач запускает соответствующие Bats-тесты.
```

#### [svp-interview-upgrade] SVP-IU-006 · parent-decision · `.memory-bank/specs/svp-interview-upgrade/requirements.md:45`

**Проблема:** Child-спека унаследовала не все обязательные варианты декомпозиции из D-10/D-12.

**Доказательство:** Umbrella D-10/D-12 требует, чтобы child-spec имела собственное интервью и чтобы spec-sized ветка предлагала выбор: отложить child либо упростить до MVP (`context/sdd-vision-pipeline.md:45-47`; также `sdd-vision-pipeline-interview.md:43-45`). Child REQ-009/010 в `requirements.md:45-46` предлагает только grouped decomposition с возможностью decline/register-and-continue. Собственное интервью child и альтернатива MVP отсутствуют также в T3 (`tasks.md:56`).

**Рекомендация:** Восстановить оба принятых родительских решения без изменения выбранного escape hatch.

**Готовая правка:**

```
Заменить REQ-009 на: `When grouped decomposition is recommended, the system shall propose named child specs, state that each accepted child receives its own follow-up interview, and allow the user to decline the recommendation.` Добавить `REQ-020` после REQ-010: `If an interview branch is estimated at spec size, then the system shall offer either deferring it as a child spec or simplifying it to an MVP inside the current topic before continuing.` Добавить `REQ-020` в `T3 **Covers:**`, Actions, DoD и gated GIVEN/WHEN/THEN-сценарий.
```

#### [svp-interview-upgrade] SVP-IU-007 · cross-slice · `.memory-bank/specs/svp-interview-upgrade/requirements.md:1`

**Проблема:** Child-спека не содержит group/ICE metadata, необходимую соседнему roadmap/backlog DB-слайсу.

**Доказательство:** Все три child-файла начинаются непосредственно с Markdown-заголовка и не имеют YAML frontmatter. Umbrella design требует вручную пометить каждый child `group: sdd-vision-pipeline` (`.memory-bank/specs/sdd-vision-pipeline/design.md:11-13`) и определяет поля group/ice (`design.md:40`). S4 discovery читает эти поля из `requirements.md` (`.memory-bank/specs/svp-roadmap-backlog-db/design.md:11-12`). Без них group target и ICE-очередь не обнаружат S1.

**Рекомендация:** Добавить канонический frontmatter в requirements.md и проверять его структурным Eval.

**Готовая правка:**

```
Добавить в начало `.memory-bank/specs/svp-interview-upgrade/requirements.md`:
---
topic: svp-interview-upgrade
group: sdd-vision-pipeline
status: ready
ice:
  impact: 8
  confidence: 9
  ease: 7
blocked_by: []
---
Затем добавить в T1 Eval кодовую проверку, что `group`, три числовых ICE-поля и parseable `blocked_by` присутствуют. Если утверждённые ICE-значения уже хранятся в roadmap, использовать именно их вместо приведённых чисел.
```

#### [svp-interview-upgrade] SVP-IU-008 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:46`

**Проблема:** Интерфейс `--batch`, `--self` и `--auto` не определяет допустимые комбинации и ошибки.

**Доказательство:** `design.md:46-48` и `tasks.md:116-118` только перечисляют три флага. Не определено, допустим ли `--auto` без `--self`, что происходит с пустым brief, совместим ли `--batch` с self-review, как флаги ведут себя при существующем draft/ready context и как сигнализируются cancel/usage errors. Реализующий агент вынужден выбрать семантику самостоятельно.

**Рекомендация:** Зафиксировать grammar, compatibility matrix и observable outcomes командного интерфейса.

**Готовая правка:**

```
Заменить C6 контрактом: ``/mb discuss <topic> [--batch] [--self "<brief>" [--auto]]``. `--auto` без `--self` и пустой/whitespace-only brief завершаются usage error до записи файлов; `--batch` совместим с `--self` и меняет только размер frontier; существующий draft возобновляет сохранённый plan; для ready context сохраняется действующий выбор edit/overwrite/cancel; `--self` без `--auto` всегда требует package confirmation; `--self --auto` разрешает продолжение только после успешных deterministic checks. Добавить таблицу expected status/result для success, cancelled/draft и usage error и Bats/structural fixtures на каждую комбинацию.
```

#### [svp-parallel-engine] SVP-PE-002 · eval · `.memory-bank/specs/svp-parallel-engine/requirements.md:53; scripts/mb-scenario-extract.py:5; scripts/mb-spec-validate.sh:228`

**Проблема:** Все сценарии записаны в неисполняемом формате, поэтому gated scenario coverage формально равно нулю.

**Доказательство:** requirements.md содержит обычные заголовки `### Scenario`, но ни одного `<!-- mb-scenario:N -->` и `**Covers:**` (`requirements.md:53-87`). Экстрактор распознаёт только marker + heading + Covers (`scripts/mb-scenario-extract.py:5-19,130-166`). Фактический запуск экстрактора вернул 0 строк; `mb-spec-validate.sh --require-scenarios` поэтому считает непокрытыми все 12 REQ (`scripts/mb-spec-validate.sh:228-265`).

**Рекомендация:** Преобразовать существующие сценарии в машинно-извлекаемые и добавить сценарии для пяти требований, отсутствующих даже на уровне заголовков.

**Готовая правка:**

```
Перед шестью существующими сценариями добавить последовательные `<!-- mb-scenario:N -->`, а сразу после заголовка — `**Covers:**`: group questions→REQ-002; frontier→REQ-003; claim race→REQ-004, REQ-005; scope violation→REQ-006; unsupported host→REQ-008; autonomous→REQ-010. Затем добавить формальные GIVEN/WHEN/THEN блоки для REQ-001 (два независимых frontier item и N=2 запускаются одновременно), REQ-007 (task agent пытается изменить банк, запись отклоняется, orchestrator применяет результат), REQ-009 (group members упорядочены DAG→ICE), REQ-011 (два завершения одновременно, judge запускается строго последовательно), REQ-012 (multi-session генерирует валидные STATUS/FREEZE/ACK записи COORDINATION.md).
```

#### [svp-parallel-engine] SVP-PE-003 · parent-decision · `.memory-bank/specs/svp-sdd-core/design.md:15; .memory-bank/context/sdd-vision-pipeline.md:48; .memory-bank/specs/svp-parallel-engine/tasks.md:6`

**Проблема:** Все шесть задач нарушают tasks.md v2: отсутствуют Stage, Blocked-by, Scope и Budget; зависимость TTL также направлена назад.

**Доказательство:** S2-C1 определяет обязательные поля v2: `Stage`, `Blocked-by`, `Scope`, `Eval`, `Budget` (`specs/svp-sdd-core/design.md:15-19`). Родительское D-13 ограничивает task ≤120k и stage ≤400k (`context/sdd-vision-pipeline.md:48`). В child tasks у всех блоков есть только Covers/Role/What to do/Eval/Testing/DoD (`tasks.md:6-107`). Кроме того, T2 требует «TTL из конфига» (`tasks.md:31`), хотя конфиг создаётся только T4 (`tasks.md:65`) при заявленном порядке 1→2→3→4 (`tasks.md:4`).

**Рекомендация:** Сделать tasks.md валидным входом S2 и явно выразить реальные зависимости.

**Готовая правка:**

```
Добавить поля: T1 `Stage: 1`, `Blocked-by: none`, `Scope: [scripts/mb_work_items.py, tests/test_work_items_frontier.py, обе design.md]`, `Budget: 120000`; T2 `Stage: 2`, `Blocked-by: 1`, `Scope: [scripts/mb-work-claims.sh, references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_mb_work_claims.bats]`, `Budget: 120000`; T3 `Stage: 2`, `Blocked-by: 1`, `Scope: [scripts/mb-work-scope-check.sh, tests/bats/test_mb_work_scope_check.bats]`, `Budget: 120000`; T5 `Stage: 2`, `Blocked-by: 1`, `Scope: [scripts/mb-work-resolve.sh, tests/bats/test_mb_work_resolve_group.bats]`, `Budget: 120000`; T4 `Stage: 3`, `Blocked-by: 1, 2, 3, 5`, `Scope: [commands/work.md, references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, scripts/mb-work-state.sh, tests/bats/test_mb_work_parallel_orchestration.bats]`, `Budget: 120000`; T6 `Stage: 4`, `Blocked-by: 4`, `Scope: [commands/work.md, tests/bats/test_mb_work_parallel_parity.bats]`, `Budget: 120000`. Передать владение `parallel.claim_ttl_seconds` в T2, чтобы TTL существовал до реализации claims.
```

#### [svp-parallel-engine] SVP-PE-005 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:14; scripts/mb_work_items.py:13; scripts/mb_work_items.py:275`

**Проблема:** C1 не передаёт source tasks.md и ломает существующий JSONL-контракт парсера.

**Доказательство:** Новый интерфейс записан как `mb_work_items.py --frontier --claims <file> ...` и обещает JSON-массив (`design.md:14-15`). Текущий CLI требует ровно позиционный `<path>` и печатает один JSON object на строку (`scripts/mb_work_items.py:13-16,275-293`). Не определены source path, done-set, schema элемента, статус пустого frontier и backward compatibility default-вызова.

**Рекомендация:** Расширить существующий CLI без изменения его default output и полностью описать frontier inputs/outputs.

**Готовая правка:**

```
Переписать C1 так: `python3 scripts/mb_work_items.py <tasks-or-plan-path> [--frontier --claims <jsonl-path> --running-scopes <json-file>]`. Без `--frontier` stdout и exit остаются byte-identical текущему JSONL. С `--frontier` stdout также JSONL, один v2 item на строку с полями `kind,no,title,stage,blocked_by,scope,eval,budget`; порядок `(stage,no)`. Done-state берётся из checkbox/marker исходного файла, active claims — из C2, running scopes — из JSON array. Пустой допустимый frontier: exit 0, пустой stdout; malformed input: exit 2; unresolved blocker: exit 3 с blocker report в stderr.
```

#### [svp-parallel-engine] SVP-PE-006 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:20; .memory-bank/specs/svp-parallel-engine/design.md:55; .memory-bank/specs/svp-sdd-core/design.md:54; .memory-bank/specs/svp-adapt-escalation/design.md:14`

**Проблема:** Scope остаётся открытым вопросом, хотя от него зависят frontier, runtime guard и S5 ADaPT.

**Доказательство:** C3 принимает неформализованное `--scope <globs>` и печатает неструктурированное `scope=...` (`parallel-engine/design.md:20-21`), а грамматика прямо оставлена open (`design.md:55`). S2 также оставляет её S3 (`svp-sdd-core/design.md:54`). S5 ожидает отдельный `--scope-status S` (`svp-adapt-escalation/design.md:14-15`), но формат передачи между C3 и S5 не определён. Не описаны absolute/`..`, directory recursion, rename/delete/untracked и overlap semantics.

**Рекомендация:** Закрыть Scope grammar до T1 и дать S5 однозначный машинный verdict.

**Готовая правка:**

```
Добавить в S2-C1 и S3-C3: `Scope` — JSON array repo-relative POSIX paths; элемент — exact file либо directory prefix с суффиксом `/**`; absolute paths, `..`, empty и glob-метасимволы кроме завершающего `/**` запрещены. Два scope пересекаются при равенстве exact paths, exact path внутри prefix или пересечении prefix. C3: `mb-work-scope-check.sh --task <id> --scope-json <json-array> --diff-file <newline-paths-file>`; учитываются modified, staged, deleted, renamed destination/source и untracked paths. stdout — один JSON object `{"task_id":"...","scope_status":"ok|violation","outside":[...]}`; exit 0 ok, 1 violation, 2 usage/input error. S5 получает точное значение `.scope_status` через `--scope-status`.
```

#### [svp-parallel-engine] SVP-PE-007 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:26; .memory-bank/specs/svp-roadmap-backlog-db/design.md:11; scripts/mb-work-resolve.sh:4; scripts/mb-work-plan.sh:78`

**Проблема:** Group resolver не имеет источника межспековых blocked_by и его список несовместим с текущим single-path stdout.

**Доказательство:** C5 требует упорядочивать members по DAG+ICE (`parallel-engine/design.md:26-27`), но S4 frontmatter содержит только `group`, `ice`, optional `pin`; blockers существуют лишь в rendered group section (`roadmap-backlog-db/design.md:11-15`). Текущий `mb-work-resolve.sh` гарантирует один absolute path на stdout (`scripts/mb-work-resolve.sh:4-15`), а `mb-work-plan.sh` сохраняет stdout в одну переменную и проверяет `[ -f "$PLAN" ]` (`scripts/mb-work-plan.sh:78-87`). Вывод списка сломает текущих callers.

**Рекомендация:** Не менять default resolver; добавить отдельный group-manifest режим и единый источник blocked_by.

**Готовая правка:**

```
Расширить S4-C1 frontmatter полем `blocked_by: [topic,...]`. Добавить C5 API: `bash scripts/mb-work-resolve.sh --group <slug> --json --mb <bank>`; stdout — один JSON object `{"group":"...","members":[{"topic":"...","tasks_path":"/abs/...","ice":252,"blocked_by":[...]}]}` в topological order, при равном ICE — `topic` ascending. Обычный `[target]` остаётся byte-identical single-path. Exit 2 — unknown group/member, exit 3 — malformed metadata, exit 4 — cycle с полным cycle path. Указать, что group orchestration, а не `mb-work-plan.sh`, является единственным consumer нового режима. Добавить regression test текущего single-target stdout.
```

#### [svp-parallel-engine] SVP-PE-008 · feasibility · `.memory-bank/context/svp-parallel-engine.md:51; .memory-bank/specs/svp-parallel-engine/tasks.md:64; .memory-bank/specs/adapter-parity/tasks.md:117; tests/bats/test_platform_limited_honesty.bats:417`

**Проблема:** Спека обещает full mode на Pi/OpenCode, но не содержит задачи, которая подключает существующий dispatch primitive к `/mb work`.

**Доказательство:** NFR-001 требует full mode на Claude Code, Pi и OpenCode (`context/svp-parallel-engine.md:51`). T4 меняет только config и prompt orchestration (`tasks.md:64-70`), T6 тестирует лишь fallback (`tasks.md:98-104`). Фактический adapter-parity аудит говорит, что `/mb work` не имеет per-role headless dispatch ни на одном non-Claude host и `mb-subinvoke-resolve.sh` не вызывается production caller-ом (`specs/adapter-parity/tasks.md:117-126`). Действующий negative test требует `role-routing` platform_limited на Pi/OpenCode и отсутствие host routing (`tests/bats/test_platform_limited_honesty.bats:417-451`).

**Рекомендация:** Добавить в контракт и Task 4 реальное production wiring, а Task 6 разделить на positive parity для Pi/OpenCode и fallback только для действительно неподдерживаемого host.

**Готовая правка:**

```
Добавить C6: `/mb work` определяет host через `MB_AGENT`, разрешает роль командой `scripts/mb-subinvoke-resolve.sh --agent "$MB_AGENT" --role "$ROLE"`, передаёт prompt только через `MB_FANOUT_PROMPT` и запускает до `max_agents` child processes; Claude Code сохраняет native Task path. Exit 2 resolver-а означает sequential fallback с одним предупреждением; остальные ошибки останавливают dispatch. В T4 Scope добавить `scripts/mb-subinvoke-resolve.sh` и production caller в work executor. В T6 добавить positive tests для `claude-code`, `pi`, `opencode`, которые доказывают реальный per-role dispatch, и negative test unknown host. После green удалить `role-routing` из accepted Pi/OpenCode `platform_limited`; base/declined manifests не менять.
```

#### [svp-parallel-engine] SVP-PE-009 · eval · `.memory-bank/specs/svp-parallel-engine/tasks.md:67; .memory-bank/specs/svp-parallel-engine/tasks.md:69; commands/work.md:324`

**Проблема:** Task 4 проверяется grep-словами и ручными сценариями, а не поведением шести покрываемых требований.

**Доказательство:** Eval ищет только `parallel`, `HITL|autonomous` и `claims` (`tasks.md:67`), а Testing требует ручной прогон (`tasks.md:69-70`). Любые упоминания слов сделают Eval зелёным без лимита N, claim-before-dispatch, judge serialization, orchestrator-only writes, board generation или autonomous escalation. Один conjunct `grep -q 'claims' commands/work.md` уже проходит на существующем описании source claim (`commands/work.md:324`).

**Рекомендация:** Заменить grep/manual Eval детерминированным integration Bats test с fake dispatcher и fake judge.

**Готовая правка:**

```
Заменить T4 Eval на `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml && bats tests/bats/test_mb_work_parallel_orchestration.bats`. В Bats обязательно проверить: N=2 никогда не создаёт более двух одновременных workers; claim записан до dispatch; два независимых item выполняются параллельно; overlapping scope не dispatch-ится; judge max concurrency равен 1; task-agent не изменяет bank, а orchestrator применяет ровно одну запись; multi-session создаёт валидные STATUS/FREEZE/ACK entries; HITL останавливается на issue, autonomous продолжает только до escalation и выдаёт полный итоговый report. Удалить ручные Scenario из DoD как completion gate.
```

#### [svp-parallel-engine] SVP-PE-010 · consistency · `.memory-bank/context/svp-parallel-engine-interview.md:10; commands/work.md:170; .memory-bank/specs/svp-parallel-engine/tasks.md:82`

**Проблема:** Group execution без worktree automation не согласован с действующим запретом same-worktree inter-plan parallelism.

**Доказательство:** Интервью сознательно отклонило автоматическое создание worktree (`context/svp-parallel-engine-interview.md:10`). Текущий `/mb work` разрешает inter-plan parallel runs только в отдельных worktrees (`commands/work.md:170`). T5 при этом исполняет members группы по DAG+ICE (`tasks.md:82`), но не определяет, считаются ли разные member specs inter-plan runs и когда same-tree dispatch допустим.

**Рекомендация:** Явно определить group как один orchestration run и сохранить запрет на независимые inter-plan sessions без добавления worktree automation.

**Готовая правка:**

```
Добавить в C5/Decisions: `A group target is one orchestrator-owned run, not multiple independent /mb work runs. Members may execute concurrently in the current worktree only after C1 proves pairwise-disjoint Scope; any overlap serializes those members. Separate user-started inter-plan sessions remain worktree-only under the existing commands/work.md rule. The orchestrator never creates or switches worktrees automatically.` Добавить Bats case: disjoint group members dispatch together; overlapping members serialize; two independent same-tree group sessions fail before dispatch.
```

#### [svp-roadmap-backlog-db] F-001 · eval · `.memory-bank/specs/svp-roadmap-backlog-db/requirements.md:44`

**Проблема:** Ни один сценарий не участвует в scenario gate

**Доказательство:** Сценарии записаны обычными заголовками без `<!-- mb-scenario:N -->` и `**Covers:**` (`requirements.md:44-80`). Штатный формат требует оба маркера (`rules/RULES.md:587`; `scripts/mb-scenario-extract.py:8-16,130-148`). Фактический запуск extractor вернул ноль сценариев.

**Рекомендация:** Перевести существующие сценарии в машинный формат и добавить сценарии для четырёх непокрытых требований.

**Готовая правка:**

```
Обернуть существующие сценарии блоками `<!-- mb-scenario:N -->` и добавить `**Covers:**`: ICE pin→REQ-001; changed progress→REQ-002, REQ-012; invalid transition→REQ-005; READY without brief→REQ-007; similar WONTFIX→REQ-008; migration→REQ-010, REQ-011. Добавить четыре блока: `Group render` с Covers REQ-003, `Structural lint` с Covers REQ-004, `Parent hierarchy` с Covers REQ-006 и `SPEC registry migration` с Covers REQ-009. Каждый блок должен содержать GIVEN/WHEN/THEN и проверяемый ожидаемый exit/output.
```

#### [svp-roadmap-backlog-db] F-002 · cross-slice · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:11`

**Проблема:** Групповой renderer не получит входных данных: child-спеки не имеют требуемого frontmatter

**Доказательство:** C1 требует читать `group`, `ice` и `pin` из frontmatter (`design.md:11-12`), но target и соседние `requirements.md` начинаются сразу с H1, например `.memory-bank/specs/svp-roadmap-backlog-db/requirements.md:1`. S3 рассчитывает потреблять эти данные (`svp-docs-wiki/design.md:26-27`). T1 упоминает только bootstrap roadmap-блока, но не backfill metadata (`tasks.md:11-13`).

**Рекомендация:** Зафиксировать полную схему metadata и включить bootstrap всех child-слайсов в T1.

**Готовая правка:**

```
Добавить в C1 контракт: `topic: <slug>`, `group: <slug>`, `ice: {impact: 1..10, confidence: 1..10, ease: 1..10}`, `pin: <positive-int|null>`, `status: <planned|in-progress|done>`, `created: YYYY-MM-DD`, `blocked_by: [<topic>...]`. Добавить в T1: `Bootstrap frontmatter for every svp-* child requirements.md using the umbrella ICE table; set group=sdd-vision-pipeline, preserve existing file bodies byte-identically, and encode S3/S5 blocked_by=svp-sdd-core. Eval must assert all group members are discovered.`
```

#### [svp-roadmap-backlog-db] F-003 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:14`

**Проблема:** Не определено взаимодействие ICE, pin и dependency ordering

**Доказательство:** C2 говорит только «ICE-first ordering, optional positive pin» (`design.md:14-15`). Текущий sync уже выполняет dependency-aware ordering (`scripts/mb-roadmap-sync.sh:171-217`). Родительский контракт требует, чтобы dependencies доминировали над ICE (`sdd-vision-pipeline/design.md:26-31`), а child-context отдельно задаёт no-ICE tail и created-date ties (`context/svp-roadmap-backlog-db.md:60-61`). Поведение при duplicate pin и pin через blocker отсутствует.

**Рекомендация:** Описать один детерминированный topological ordering contract.

**Готовая правка:**

```
Заменить ordering-часть C2 текстом: `Order nodes with Kahn topological sort. Only dependency-ready nodes participate in priority selection. Among ready nodes sort by: valid pin ascending; then complete ICE score descending; then created ascending; then topic lexicographically. A pin never crosses an unsatisfied dependency. Duplicate pins use the remaining keys and emit warning code=duplicate_pin. Missing ICE sorts after complete ICE and emits warning code=no_ice. If no node has ICE or pin, preserve the legacy order byte-identically.`
```

#### [svp-roadmap-backlog-db] F-004 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:15`

**Проблема:** Формула прогресса и формат stage/task counters не определены

**Доказательство:** REQ-002 требует процент и stage/task counters (`requirements.md:18-20`), но C2 задаёт только неоднозначный пример `NN% (done/in-progress/planned)` (`design.md:15`). `mb-work-checkbox.sh` меняет DoD-checkboxes, но не предоставляет готовую модель состояний (`scripts/mb-work-checkbox.sh:114-175`). Родительский D-14 требует отображать отдельно stage и task counters (`context/sdd-vision-pipeline.md:51`).

**Рекомендация:** Задать источник истины, классификацию, округление и точную грамматику вывода.

**Готовая правка:**

```
Добавить в C2: `A task/stage is done when every DoD checkbox is checked; in_progress when at least one DoD checkbox is checked or its work-state is active; otherwise planned. progress_percent=floor(100*checked_DoD/total_DoD); total_DoD=0 yields 0. Render: progress=<N>% stages(done=<d>,in_progress=<i>,planned=<p>,total=<t>) tasks(done=<d>,in_progress=<i>,planned=<p>,total=<t>). A legacy spec without Stage fields is one stage. Counters are recomputed from source files on every render and never parsed back from roadmap.md.`
```

#### [svp-roadmap-backlog-db] F-005 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:17`

**Проблема:** Backlog state CLI неполон, а brief gate противоречит задаче

**Доказательство:** C3 определяет лишь `mb-backlog-state.sh <I-NNN> <new-state>` и exit 0/1 (`design.md:17-18`), не задавая путь банка, stdout/stderr, полный adjacency graph, list/tree API или reason input. REQ-007 требует не допускать READY без behavioural brief (`requirements.md:30`), но T2 оставляет path leakage только warning (`tasks.md:31-32`).

**Рекомендация:** Зафиксировать state-machine CLI и сделать brief validation блокирующей.

**Готовая правка:**

```
Заменить C3 контрактом: `mb-backlog-state.sh transition <I-NNN> <NEW_STATE> [--reason TEXT] [--mb PATH]`; `mb-backlog-state.sh list [--tree] [--mb PATH]`. Разрешённые edges: `NEW→NEEDS-INFO`, `NEEDS-INFO→TRIAGED`, `TRIAGED→NEEDS-INFO|READY`, `READY→IN-PROGRESS`, `IN-PROGRESS→DONE|WONTFIX`; terminal states не имеют выходов. WONTFIX требует непустой `--reason`. Success stdout: `item=<id> old_state=<old> new_state=<new>`; domain rejection exit 1; usage/not-found exit 2; diagnostics идут в stderr. `--tree` выводит parent before children, siblings by numeric ID, а missing parent/cycle завершает exit 1. READY без `Brief` или с path/line-number references должен завершаться exit 1, не warning.
```

#### [svp-roadmap-backlog-db] F-006 · cross-slice · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:20`

**Проблема:** Формат `[SPEC:<group>]` registry не определён для S1/S2/S5

**Доказательство:** C4 обещает преобразовать prefix в «typed-line registry», но не задаёт секцию, поля или parser grammar (`design.md:20-21`). S1 создаёт `[SPEC:<group>]` записи (`svp-interview-upgrade/design.md:50-52`), S2 и S5 должны их читать (`svp-sdd-core/design.md:24-25`; `svp-adapt-escalation/design.md:23-24`).

**Рекомендация:** Определить один Markdown record contract, используемый всеми тремя слайсами.

**Готовая правка:**

```
Добавить в C4: `A decomposed-spec registry entry remains an ordinary backlog item under ## Ideas and has: heading "### I-NNN — <title> [<PRIORITY>, <STATE>, <DATE>]", followed by "**Type:** SPEC", "**Group:** <slug>", "**Parent:** <I-NNN|none>", and "**Spec:** <topic>". Writers MUST emit this form; readers MUST accept it. Migration removes only the [SPEC:<group>] title prefix, writes Type/Group fields, and preserves ID, title remainder, body, order, priority, state and date.`
```

#### [svp-roadmap-backlog-db] F-008 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:23`

**Проблема:** Lint output и severity/exit semantics не определены

**Доказательство:** C5 задаёт только области, четыре кода и exit 0/1 (`design.md:23-24`). Context называет `no-ice` и `orphan_group` warnings (`context/svp-roadmap-backlog-db.md:60-61`), но не объясняет, влияют ли warnings на exit. `progress_mismatch` требует вычислить expected render, тогда как текущий sync имеет только записывающий путь (`scripts/mb-roadmap-sync.sh:284-287`).

**Рекомендация:** Добавить read-only render/check seam и точный key=value protocol.

**Готовая правка:**

```
Добавить: `mb-roadmap-sync.sh --check [MB_PATH]` computes expected autosync content in memory, never writes, and exits 1 only when rendered content is stale. `mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]` emits one line per finding: `severity=<warning|error> code=<code> file=<relative-path> line=<n> detail=<escaped-text>`. Codes `no_ice`, `orphan_group`, `duplicate_pin` are warnings; `progress_mismatch`, `invalid_state`, `ready_without_brief`, `parent_cycle` are errors. Exit 0 means no errors, exit 1 means at least one error, exit 2 means invalid invocation. Lint must never mutate bank files.`
```

#### [svp-roadmap-backlog-db] F-009 · eval · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:87`

**Проблема:** Task 5 Eval — настоящий red, но проверяет лишь наличие двух слов

**Доказательство:** Eval равен `grep -q 'NEEDS-INFO' commands/mb.md && grep -q 'ice:' references/templates.md` (`tasks.md:87`). Сейчас он red, но станет green от любого несвязанного упоминания и не проверит transition graph, READY/WONTFIX rules, parent hierarchy, full metadata schema или CLAUDE invariant.

**Рекомендация:** Заменить keyword grep структурным детерминированным тестом документационного контракта.

**Готовая правка:**

```
Заменить Eval на `bats tests/bats/test_mb_roadmap_backlog_docs.bats`. Тест должен извлечь документированные блоки и assert exact: полный список allowed transitions; READY brief gate; WONTFIX reason/out-of-scope behavior; поля `topic/group/ice/pin/status/created/blocked_by`; одинаковый CLI synopsis в `commands/mb.md` и script `--help`; новый invariant в `CLAUDE.md`.
```

#### [svp-roadmap-backlog-db] F-010 · edge-case · `.memory-bank/specs/svp-roadmap-backlog-db/requirements.md:31`

**Проблема:** Не определён детерминированный алгоритм поиска похожего WONTFIX

**Доказательство:** REQ-008 требует подсказку при похожей идее (`requirements.md:31`), а scenario ожидает её до создания duplicate (`requirements.md:70-74`). Design не задаёт normalization, similarity threshold, output, exit code или override (`design.md:17-24`). Реализатор вынужден выбрать семантику самостоятельно.

**Рекомендация:** Зафиксировать простую локальную формулу без LLM и сетевых зависимостей.

**Готовая правка:**

```
Добавить в C3: `Similarity is computed only against WONTFIX/out-of-scope titles. Normalize with Unicode casefold, replace non-alphanumeric characters with spaces, and keep unique tokens of length >=4. score=|candidate∩existing|/min(|candidate|,|existing|); empty token sets score 0. score>=0.5 is a match. On match, print `similar_out_of_scope=<I-NNN> score=<0..1>` and reject creation with exit 1 unless explicit `--force` is supplied. Ties resolve by lowest numeric I-ID.`
```

#### [svp-roadmap-backlog-db] F-011 · sizing · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:5`

**Проблема:** T1 и особенно T2 превышают установленный предел одного work item

**Доказательство:** T1 объединяет metadata parser, dependency-safe ICE/pin ordering, progress model, group renderer и bootstrap (`tasks.md:5-18`). T2 объединяет state machine, brief validator, hierarchy renderer, out-of-scope registry и similarity integration (`tasks.md:22-37`). Родительское решение ограничивает задачу 120k токенов (`context/sdd-vision-pipeline.md:48-49`).

**Рекомендация:** Разделить независимые production seams без перенумерации существующих task IDs.

**Готовая правка:**

```
Оставить mb-task:1 только для metadata parser + ICE/pin ordering; добавить mb-task:6 для progress/group rendering/bootstrap, blocked_by task 1. Оставить mb-task:2 для transition engine + brief gate; добавить mb-task:7 для parent/tree behavior, blocked_by task 2; добавить mb-task:8 для out-of-scope registry + similarity, blocked_by task 2. Для каждого записать `Budget: <=120000 tokens`, отдельные Covers/DoD/Testing/Eval.
```

#### [svp-roadmap-backlog-db] F-012 · edge-case · `.memory-bank/context/svp-roadmap-backlog-db.md:56`

**Проблема:** Не обеспечены уникальность I-ID и атомарность параллельных backlog writes

**Доказательство:** NFR требует никогда не переиспользовать I-NNN (`context/svp-roadmap-backlog-db.md:56`). Текущий allocator ищет максимум только в backlog (`scripts/mb-idea.sh:64-70`), а backlog уже документирует collision I-079 с progress (`.memory-bank/backlog.md:504-506`). Новые state/migration scripts также будут менять общий Markdown DB, но lock/atomic protocol отсутствует.

**Рекомендация:** Определить единый allocator и lock для всех backlog writers.

**Готовая правка:**

```
Добавить NFR: `All backlog writers acquire the same exclusive lock <bank>/.locks/backlog.lock before ID allocation or mutation. ID allocation scans backlog.md, progress.md, agreements.md and existing registry/index sources for the maximum I-NNN and allocates max+1 while holding the lock. Writes use a temporary file in the backlog directory, fsync/close, then atomic rename. Interrupted writes leave the original file intact. Integration Eval launches two concurrent creators and asserts distinct IDs, valid Markdown and no lost entry.`
```

#### [svp-roadmap-backlog-db] F-013 · parent-decision · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:18`

**Проблема:** Не проверена обязательная cross-platform и Bash 3.2 совместимость

**Доказательство:** Задачи требуют только Bats и shellcheck (`tasks.md:18,37,73`). Umbrella NFR-003 требует честную работу/degradation на всех клиентах (`sdd-vision-pipeline/requirements.md:127`), а новые shell contracts зависят от locking, sorting, regex и atomic replacement — типичных GNU/BSD и Bash 3.2 seam.

**Рекомендация:** Добавить portability acceptance checks, не вводя новые runtime-зависимости.

**Готовая правка:**

```
В Testing для T1-T4 добавить: `Run syntax checks under Bash 3.2; run Bats on macOS/BSD and Linux/GNU tool semantics; forbid associative arrays, mapfile/readarray, GNU-only sed -i/date/stat/flock assumptions; provide mkdir-based locking when flock is absent; missing optional tooling must emit a documented warning and preserve legacy behavior.`
```

#### [svp-sdd-core] F-001 · coverage · `.memory-bank/specs/svp-sdd-core/requirements.md:28,60-102`

**Проблема:** Scenario-гейт REQ-006 не может увидеть ни одного сценария; шесть REQ не покрыты даже неформально.

**Доказательство:** REQ-006 требует «at least one GWT scenario ... covering» каждый gated REQ (`requirements.md:28`). Сценарии записаны только как `### Scenario: ... (REQ-...)` (`requirements.md:62-102`) без обязательных `<!-- mb-scenario:N -->` и `**Covers:**`; канонический формат задан в `rules/RULES.md:586-591`. Фактический `mb-scenario-extract.py` вернул пустой вывод. Неформально отсутствуют REQ-004/006/009/011/013/014.

**Рекомендация:** Перевести существующие сценарии в машинно-разбираемый формат и добавить сценарии для шести отсутствующих gated REQ.

**Готовая правка:**

```
Для каждого существующего сценария добавить обёртку и Covers, например:
<!-- mb-scenario:1 -->
### Scenario: sdd без контекста запускает интервью
**Covers:** REQ-001
- GIVEN ...
- WHEN ...
- THEN ...
<!-- /mb-scenario:1 -->

Добавить ещё шесть блоков:
- `mb-scenario:8`, Covers REQ-004: полный v2-блок парсится в Stage/Blocked-by/Scope/Eval/Budget;
- `mb-scenario:9`, Covers REQ-006: gated REQ без GWT или Eval отклоняется;
- `mb-scenario:10`, Covers REQ-009: task/stage/spec суммы записаны и совпадают;
- `mb-scenario:11`, Covers REQ-011: auto-overflow создаёт self-interview slices и assumption;
- `mb-scenario:12`, Covers REQ-013: генератор и reviewer получают оба transcript path;
- `mb-scenario:13`, Covers REQ-014: child specs получают group и запись реестра.
```

#### [svp-sdd-core] F-002 · consistency · `.memory-bank/specs/svp-sdd-core/design.md:19; .memory-bank/specs/svp-sdd-core/tasks.md:13-14,22`

**Проблема:** Контракт legacy JSON одновременно требует новые ключи и byte-identical полный вывод.

**Доказательство:** C2 говорит: «Новые ключи ...; существующие ключи byte-identical» (`design.md:19`). Task 1 требует «легаси-снимок JSON», «легаси-вывод byte-identical» и «легаси-фикстуры byte-identical» (`tasks.md:13-14,22`). Добавление пяти ключей неизбежно меняет байты полного JSON.

**Рекомендация:** Зафиксировать byte-identity только для проекции старых ключей, а не для всего объекта.

**Готовая правка:**

```
Заменить Task 1 на:
- Контрактные pytest-фикстуры из всех текущих `specs/*/tasks.md` ДО правок: проекция pre-v2 ключей (`source/topic/item_no/kind/heading/body/role/agent/status/covers/dod_lines`) остаётся byte-identical; полный JSON дополнительно содержит v2-ключи с контрактными дефолтами.

Заменить DoD:
- [ ] Проекция pre-v2 ключей byte-identical; полный JSON содержит корректные v2-ключи и дефолты.
```

#### [svp-sdd-core] F-003 · feasibility · `.memory-bank/specs/svp-sdd-core/tasks.md:10,29,47,64,84,101; scripts/mb_work_items.py:96-102,238-240; scripts/mb-work-plan.sh:362-370`

**Проблема:** Значения Role маршрутизируют задачи не тем агентам.

**Доказательство:** Спека использует `**Role:** mb-backend` и аналогичные значения. Парсер принимает строку буквально и строит `agent = f"mb-{role}"` (`mb_work_items.py:96-102,238-240`); фактический вывод дал `role:"mb-backend", agent:"mb-mb-backend"`. Work-plan ищет pipeline-role по этой строке и затем откатывается к developer (`mb-work-plan.sh:362-370`).

**Рекомендация:** Использовать канонические role-id без префикса `mb-`.

**Готовая правка:**

```
В `tasks.md` заменить:
- `**Role:** mb-backend` → `**Role:** backend` (T1–T3);
- `**Role:** mb-architect` → `**Role:** architect` (T4);
- `**Role:** mb-developer` → `**Role:** developer` (T5–T6).
```

#### [svp-sdd-core] F-004 · cross-slice · `.memory-bank/context/svp-sdd-core.md:22-23,31; .memory-bank/specs/svp-sdd-core/tasks.md:28-34,46-55; .memory-bank/roadmap.md:91,143`

**Проблема:** T2/T3 зависят от ещё не реализованных соседних контрактов, но blocked_by этого не отражает.

**Доказательство:** S2 расширяет `mb-estimate-check.sh` из S1 (`context:22,31`), однако файл сейчас отсутствует. T2 переиспользует SHALL/MUST и scenario-гейт `sdd-openspec-parity` (`context:23`, `tasks:32`), чьи Phase-1 задачи ещё стоят отдельным параллельным лейном (`roadmap.md:143`). При этом S2 отмечен без blocker (`roadmap.md:91`), а tasks вообще не имеют Blocked-by.

**Рекомендация:** Определить cross-spec ссылку в грамматике Blocked-by и зафиксировать фактические зависимости.

**Готовая правка:**

```
Дополнить C1:
`Blocked-by` — CSV; локальная ссылка имеет вид `<task-number>`, межспековая — `<topic>#<task-number>`; неизвестная ссылка валит spec validation.

Добавить в tasks:
- T1: `**Blocked-by:** none`
- T2: `**Blocked-by:** 1, sdd-openspec-parity#1, sdd-openspec-parity#3`
- T3: `**Blocked-by:** 1, svp-interview-upgrade#3`
- T4: `**Blocked-by:** 1, 2, 3`
- T5: `**Blocked-by:** 4`
- T6: `**Blocked-by:** 4`.
```

#### [svp-sdd-core] F-005 · cross-slice · `.memory-bank/specs/svp-sdd-core/design.md:16,35,54,60; .memory-bank/specs/svp-parallel-engine/design.md:3-4,20-21,55`

**Проблема:** Scope — обязательный межслайсовый контракт — оставлен открытым до начала S3.

**Доказательство:** S2 определяет Scope как неопределённый `<glob-list>` (`design.md:16`) и прямо оставляет грамматику на будущее (`design.md:35,54,60`). S3 заблокирован S2 и должен сразу потреблять этот контракт для детерминированной diff-проверки (`svp-parallel-engine/design.md:3-4,20-21`). Значит S2 не завершает seam, который обязан опубликовать.

**Рекомендация:** Финализировать glob-диалект в S2; S3 может ревизовать реализацию, но не изобретать контракт заново.

**Готовая правка:**

```
Заменить описание Scope в C1 на:
`Scope` — CSV repo-relative POSIX glob-паттернов. Разделитель пути всегда `/`; `*` не пересекает `/`, `**` пересекает любое число сегментов; абсолютные пути, `..`, пустые элементы и negation `!` запрещены. Пути diff нормализуются относительно git root. Легаси-дефолт — `["**"]`. S3-C3 MUST реализовать ровно эту семантику.
```

#### [svp-sdd-core] F-006 · sizing · `.memory-bank/context/svp-sdd-core.md:32; .memory-bank/specs/svp-sdd-core/design.md:16; .memory-bank/specs/svp-sdd-core/tasks.md:6-112`

**Проблема:** Собственные задачи спеки не содержат Stage/Blocked-by/Scope/Budget, а оценка до 900k несовместима с шестью задачами по ≤120k.

**Доказательство:** Assumption оценивает S2 в 700–900k (`context:32`). Шесть задач при жёстком лимите 120k дают максимум 720k. При этом C1 требует v2-поля (`design:16`), но в tasks присутствует только `Eval`; Stage, Blocked-by, Scope и Budget отсутствуют во всех шести блоках.

**Рекомендация:** Вернуть статус спеки в draft, внести конкретные бюджеты и при верхней оценке разбить крупные задачи внутри этого же child-слайса.

**Готовая правка:**

```
Добавить перед задачами:
## Size gate before acceptance
The spec MUST remain `draft` until every task has an integer `Budget <= 120000`, every stage sum is `<= 400000`, and the spec estimate equals the sum of task budgets. A range estimate is not accepted.

Если подтверждается оценка выше 720000, разделить текущий T4 минимум на три задачи: (1) full-generation pipeline, (2) D-35 escalation/decomposition, (3) scaffold-only compatibility + templates. После этого добавить каждому task конкретные `Stage`, `Blocked-by`, `Scope`, `Eval ... red:` и `Budget`.
```

#### [svp-sdd-core] F-007 · contract · `.memory-bank/specs/svp-sdd-core/requirements.md:47-50; .memory-bank/specs/svp-sdd-core/design.md:16,21-25; .memory-bank/specs/svp-sdd-core/tasks.md:50,55`

**Проблема:** Контракт estimate-check не определяет резолюцию входа, значения totals, смысл exit-кодов и legacy-поведение.

**Доказательство:** C3 даёт только `--spec <topic>`, три status-поля и `exit 0/1/2` (`design:21-22`). Не сказано, что означает каждый exit, как резолвится bank/topic и где записываются per-stage/per-spec totals, требуемые REQ-009. Есть конфликт: legacy Budget default=120000 (`design:16`), но тест требует отсутствующие Budget «skip с warning» (`tasks:55`). Порог `~1M` и зона 0.9–1.1M также не превращены в детерминированные состояния.

**Рекомендация:** Опубликовать полный CLI/output/persistence контракт и единое legacy-правило.

**Готовая правка:**

```
Заменить C3 на:
### C3. `scripts/mb-estimate-check.sh --spec <topic|spec-dir> [--mb <bank>]`
- Topic резолвится в `<bank>/specs/<topic>/tasks.md`; явный spec-dir имеет приоритет.
- Читаются только явно записанные `Budget`; legacy-задачи без поля исключаются из сумм и перечисляются как `legacy_missing=<ids>` с одним stderr warning.
- stdout, по одной key=value строке: `task.<id>=<tokens>`, `stage.<id>=<tokens>`, `spec.total=<tokens>`, `task_over=<csv|none>`, `stage_over=<csv|none>`, `spec=ok|near|over`, `legacy_missing=<csv|none>`.
- `ok`: total <900000; `near`: 900000..1000000; `over`: >1000000. Near вызывает advisory escalation; over вызывает D-35 hard stop.
- exit 0 = ok/near без task/stage overflow; exit 1 = любой task/stage/spec overflow; exit 2 = usage, unresolved spec или malformed field.
- Генератор записывает `estimated_tokens.total` и `estimated_tokens.stages` во frontmatter tasks.md; значения обязаны совпадать с stdout.
```

#### [svp-sdd-core] F-008 · contract · `.memory-bank/specs/svp-sdd-core/design.md:9-11,13-31; commands/sdd.md:30-50,133-137; scripts/mb-sdd.sh:18-25`

**Проблема:** Не определён новый CLI-контракт mb-sdd.sh и граница между prompt-оркестрацией и scaffold writer.

**Доказательство:** Architecture обещает `mb-sdd.sh (+--scaffold-only)` (`design:10`), но Interfaces вообще не содержит этот интерфейс. Текущий публичный script contract — `<topic> [--force] [mb_path]`, exit 0/1/2 (`mb-sdd.sh:18-25`), а command вызывает именно его (`commands/sdd.md:46-50`). Shell-скрипт не может сам выполнить LLM-генерацию полного triple; реализатору придётся решать, менять ли default script API и кто пишет файлы.

**Рекомендация:** Сохранить прямой script API byte-identical и явно отдать full-generation prompt-слою.

**Готовая правка:**

```
Добавить C7:
### C7. `/mb sdd` и `scripts/mb-sdd.sh`
- `commands/sdd.md` owns the default full-generation pipeline and writes the final triple only after context/transcript/budget gates.
- Existing `bash scripts/mb-sdd.sh <topic> [--force] [mb_path]` remains byte-identical and scaffold-only for direct callers.
- `--scaffold-only` is an alias selecting that same existing writer from `/mb sdd`; it does not change script output or exit codes.
- `/mb sdd` without `--scaffold-only` MUST NOT call the scaffold writer before D-35 passes.
- Exit/report contract for the command: success lists three paths; cancelled/escalated generation writes no tasks.md and reports `sdd_status=blocked`; malformed context reports `sdd_status=invalid`.
```

#### [svp-sdd-core] F-009 · contract · `.memory-bank/context/svp-sdd-core.md:30; .memory-bank/specs/svp-sdd-core/requirements.md:54-58; .memory-bank/specs/svp-sdd-core/design.md:27-28`

**Проблема:** Spec-review не гарантирует другую модель и не имеет полного результата, хранения и failure-контракта.

**Доказательство:** Интервью и user story требуют ревью «другой моделью» (`requirements.md:54`), но C5 разрешает любую configured model без сравнения с generator model. JSON не задаёт enum severity/category, обязательные поля, файл результата или exit/status для APPROVED, CHANGES_REQUESTED, unavailable и malformed output (`design.md:27-28`). Parent NFR-005 требует структурного логирования (`context/sdd-vision-pipeline.md:129`).

**Рекомендация:** Определить schema, different-model guard, persistence и loud-degradation семантику.

**Готовая правка:**

```
Заменить C5 на:
- Config: `sdd.spec_review: {enabled: false, agent: <exact>, model: <exact>, thinking: low|medium|high}`.
- Before dispatch, compare reviewer model with the resolved generator model; equality is a validation error `same_model`.
- Result path: `<bank>/tmp/spec-review/<topic>.json`, written only by the orchestrator.
- Schema: `{status:"reviewed"|"skipped", verdict:"APPROVED"|"CHANGES_REQUESTED"|null, reviewer:{agent,model,thinking}, issues:[{severity:"critical"|"major"|"minor"|"nit",category,req:string|null,description}], reason:string|null}`.
- Exit 0 = APPROVED; 1 = CHANGES_REQUESTED; 2 = unavailable/malformed → status skipped, loud report, no silent acceptance.
- Interactive skipped review requires human decision; auto mode records the skip and orchestrator decision before acceptance.
```

#### [svp-sdd-core] F-010 · parent-decision · `.memory-bank/specs/svp-sdd-core/requirements.md:30; .memory-bank/specs/svp-sdd-core/design.md:30-31; .memory-bank/context/sdd-vision-pipeline.md:40`

**Проблема:** Отсутствие доказанного red понижается до warning, хотя D-05 и REQ-008 требуют обязательный red→green.

**Доказательство:** REQ-008 требует «observe it fail before implementation» (`requirements.md:30`), parent D-05 фиксирует red → implementation → green (`context/sdd-vision-pipeline.md:40`). Однако C6 говорит «absence of red phase = warning» (`design.md:31`), поэтому задача может пройти без доказательства, что eval способен поймать дефект.

**Рекомендация:** Сделать red evidence hard gate и хранить его структурно в существующем work-state.

**Готовая правка:**

```
Заменить C6 на:
- Before implement, materialize and run the exact Eval command.
- The orchestrator records in the current `<bank>/.work-state.json` or `<bank>/.work-state/<run_id>.json`: `eval:{cmd,red_exit,red_observed,red_match,green_exit}`.
- `red_observed=true` only when the exit/output matches the declared `red:` condition; an unrelated failure is not accepted.
- Missing or mismatched red is FAIL and blocks implement; only an explicit user override may continue and must be logged.
- Verify reruns the byte-identical command and requires `green_exit=0`; command drift is FAIL.
```

#### [svp-sdd-core] F-011 · eval · `.memory-bank/specs/svp-sdd-core/tasks.md:71,89,106`

**Проблема:** T4–T6 Eval проверяют слова, а не заявленные контракты.

**Доказательство:** T4 проходит от трёх строк `discuss/budget_override/...`, T5 — от любого `spec_review` плюс общей schema validation, T6 — от любых несвязанных слов `Eval` и `red` (`tasks.md:71,89,106`). Сейчас все три действительно red (rc=1), но после минимального текстового упоминания станут green без проверки порядка pipeline, D-35 stop-before-write, strict review schema или red-evidence gate. Сама спека признаёт ручные сценарии как дополнительную проверку, то есть кодовый Eval не доказывает REQ.

**Рекомендация:** Заменить широкие grep на детерминированные контрактные тесты в принятых каталогах проекта.

**Готовая правка:**

```
Заменить Eval:
- T4: `pytest tests/pytest/test_sdd_command_contract_v2.py` — проверяет упорядоченные phases 0–9, transcript input, stop-before-tasks, четыре D-35 branch, scaffold-only и отсутствие старого out-of-scope утверждения.
- T5: `bats tests/bats/test_sdd_spec_review.bats` — valid config, same-model reject, APPROVED, CHANGES_REQUESTED, unavailable→SKIPPED loud, malformed JSON.
- T6: `bats tests/bats/test_work_eval_first.bats` — exact command identity, matching red required, unrelated red rejected, missing red blocks implement, green required in verify.
Также переместить T1–T3 test paths в `tests/pytest/` и `tests/bats/`, соответствующие структуре репозитория.
```

#### [svp-sdd-core] F-012 · contract · `.memory-bank/specs/svp-sdd-core/requirements.md:48-50; .memory-bank/specs/svp-sdd-core/design.md:24-25; .memory-bank/specs/svp-interview-upgrade/design.md:50-52`

**Проблема:** REQ-014 ссылается на decomposed-spec registry, но S2 не определяет writer/path до появления S4.

**Доказательство:** REQ-014 требует регистрацию child specs (`requirements.md:50`), а C4 упоминает только `[SPEC:<group>] реестр` без файла или команды (`design.md:24-25`). Соседний S1 уже определил временный совместимый контракт: `backlog.md ## Ideas` через `mb-idea.sh` с `[SPEC:<group>]` (`svp-interview-upgrade/design.md:50-52`), но S2 его не импортирует.

**Рекомендация:** Явно переиспользовать S1-C7 и сохранить orchestrator-only запись банка.

**Готовая правка:**

```
Дополнить C4:
- До S4 единственный writer реестра — orchestrator через `scripts/mb-idea.sh "[SPEC:<group>] <child-topic>"` в `<bank>/backlog.md ## Ideas`; child agents возвращают только structured proposals.
- Каждый созданный child triple получает `group: <group>` и `parent_context: context/<umbrella>.md` во frontmatter.
- После S4 тот же `[SPEC:<group>]` импортируется мигратором; S2 не пишет альтернативный registry-файл.
- Частичный отказ после создания части children оставляет их зарегистрированными со status draft и перечисляет незаписанные children в loud report.
```

### MINOR (6)

#### [svp-brief] SVP-BRIEF-008 · consistency · `.memory-bank/context/svp-brief.md:41-44; .memory-bank/specs/svp-brief/tasks.md:32-35`

**Проблема:** Числовой контракт «одна страница» расходится между контекстом и тестом.

**Доказательство:** NFR-001 задаёт «~60–100 строк», а Task 2 требует warning только при `>120` строк без объяснения диапазона 101–120.

**Рекомендация:** Записать различие target и hard warning явно.

**Готовая правка:**

```
Заменить NFR-001 на: «Target: 60–100 строк. 101–120 строк допустимы без ошибки; >120 строк вызывает детерминированный warning `warning=oversize`, но не делает структурно валидный brief invalid».
```

#### [sdd-vision-pipeline] SVP-015 · consistency · `umbrella design.md:6,11,46; tasks.md:3-6; roadmap.md:79`

**Проблема:** Заголовки и ссылки остались на состоянии до появления D-32…D-35 и S7.

**Доказательство:** Design называет входы D-01…D-31/REQ-001…041 (`:6`) и «шесть child-спек» (`:11`), tasks header говорит T2–T7 (`tasks.md:3-5`), roadmap — T1+6 слайсов (`roadmap.md:79`). Фактически есть D-35, REQ-048, T8 и семь child-спек.

**Рекомендация:** Синхронизировать описательные метаданные с фактическим составом.

**Готовая правка:**

```
Везде заменить диапазоны на `D-01…D-35` и `REQ-001…REQ-048`; заменить `шесть child-спек`/`T1 + 6 слайсов` на `семь child-спек`/`T1 + 7 слайсов`; tasks header — `T2–T8` и порядок с S7.
```

#### [sdd-vision-pipeline] SVP-016 · consistency · `Child tasks Eval paths; .github/workflows/test.yml:47-58`

**Проблема:** Новые тесты планируются вне каталогов, запускаемых CI.

**Доказательство:** Например, `svp-interview-upgrade/tasks.md:59` использует `tests/mb-estimate-check.bats`, а `svp-sdd-core/tasks.md:16` — `tests/test_work_items_v2.py`. CI запускает bats только из `tests/bats/`, `tests/e2e/`, `hooks/tests/` и pytest из `tests/pytest/` (`.github/workflows/test.yml:47-58`).

**Рекомендация:** Следовать существующей структуре, чтобы targeted Eval входил и в regression.

**Готовая правка:**

```
Во всех child-спеках заменить `tests/mb-*.bats` на `tests/bats/test_mb_*.bats`, а `tests/test_*.py` на `tests/pytest/test_*.py`; обновить соответствующие Eval-команды и design Eval tables.
```

#### [svp-interview-upgrade] SVP-IU-009 · feasibility · `.memory-bank/specs/svp-interview-upgrade/tasks.md:60`

**Проблема:** Новые Bats-тесты запланированы вне каталогов, запускаемых стандартной suite-командой проекта.

**Доказательство:** T3 создаёт `tests/mb-estimate-check.bats` (`tasks.md:60`), а T4 условно ссылается на `tests/mb-secret-scan.bats` (`tasks.md:83`). Проектная команда запускает `bats tests/bats/ tests/e2e/ hooks/tests/*.bats` (`README.md:698`), поэтому root-level `tests/*.bats` не попадут в regression suite.

**Рекомендация:** Размещать оба теста в существующем `tests/bats/` и сделать scanner suite обязательной.

**Готовая правка:**

```
В T3 заменить путь на `tests/bats/test_mb_estimate_check.bats`. В T4 заменить путь на `tests/bats/test_mb_secret_scan.bats` и удалить условие `if scanner is delivered as a drop-in`, поскольку scanner является обязательной частью контракта T4.
```

#### [svp-interview-upgrade] SVP-IU-010 · edge-case · `.memory-bank/context/svp-interview-upgrade.md:85`

**Проблема:** Поведение при частично отвеченном batch-round есть в context, но отсутствует в requirements и T2.

**Доказательство:** `context/svp-interview-upgrade.md:85-86` требует при >4 вопросах несколько AskUserQuestion-вызовов и возвращать неотвеченные пункты в plan после частичного ответа. REQ-015/016 в `requirements.md:66-67` и T2 в `tasks.md:35-42` фиксируют batch/frontier, но не судьбу unanswered questions.

**Рекомендация:** Перенести уже принятое edge-case решение в нормативное требование и кодовый сценарий T2.

**Готовая правка:**

```
Добавить `REQ-021`: `If a batch round is only partially answered, then every unanswered question shall remain unchecked in the interview plan and return in the next frontier.` Добавить `REQ-021` в `T2 **Covers:**`, DoD и gated-сценарий: GIVEN 5 открытых вопросов и ответы только на первые 2, WHEN round сохраняется, THEN первые 2 закрыты, последние 3 остаются unchecked и формируют следующий frontier.
```

#### [svp-sdd-core] F-013 · edge-case · `.memory-bank/specs/svp-sdd-core/tasks.md:18-19,36-37,54-55; .memory-bank/context/sdd-vision-pipeline.md:127-128`

**Проблема:** В child-спеке потеряны обязательные portability/backward-compatibility проверки оболочки.

**Доказательство:** Umbrella NFR требует паритет на 8 клиентах и byte-identical legacy (`context/sdd-vision-pipeline.md:127-128`). T2/T3 меняют shell scripts, но Testing указывает только bats/shellcheck; нет Bash 3.2/macOS, Linux, locale/space-path и no-tool degradation кейсов (`tasks.md:36-37,54-55`).

**Рекомендация:** Добавить портативные негативные сценарии без расширения функционального scope.

**Готовая правка:**

```
Добавить NFR и Testing:
- `NFR-004: Modified shell entrypoints SHALL run under Bash 3.2 on macOS and current Bash on Linux; paths with spaces and non-C locale SHALL remain valid.`
- T2/T3 tests: Bash 3.2 invocation, GNU/BSD tool availability, bank path with spaces, `LC_ALL=C`, missing optional reviewer/tool → documented loud degradation, legacy corpus unchanged.
```

## Резюме по каждой спеке

### sdd-vision-pipeline — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Спека пока не исполнима. Найдены 2 critical и 11 major дефектов: неверные Role ломают dispatch, все 39 child-сценариев не распознаются SDD-инструментами, отсутствует child-покрытие REQ-022, есть ложный green Eval, неполные межслайсовые контракты и ошибки DAG.

**Coverage:** REQ всего 48; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-033, REQ-034, REQ-035, REQ-036, REQ-037, REQ-038, REQ-039, REQ-040, REQ-041, REQ-042, REQ-043, REQ-044, REQ-045, REQ-046, REQ-047, REQ-048; недетерминированные эвалы: Umbrella T1–T8: отсутствует поле **Eval:**, S1 T1/T2/T4/T5/T6: grep + ручные сценарии не проверяют поведение, S7 T1/T3/T4: grep не проверяет создание брифа и Phase-0 handoff, S4 T5: grep проверяет только слова в документации, S2 T4/T5/T6: grep не проверяет генерацию, dispatch spec-review и red→green lifecycle, S6 T2/T3/T4: наличие строк/файлов не проверяет orchestration и использование docs.path, S5 T2/T3/T4/T5: grep не проверяет ADaPT; T5 уже green до реализации, S3 T4: grep не проверяет frontier orchestration, single-writer и serialized judge.

Umbrella Covers формально даёт 48/48, а все child-задачи покрывают существующие локальные REQ. Однако `mb-scenario-extract.py` извлёк 0 сценариев из каждой из семи child-спек: текущие 39 prose-сценариев не имеют `<!-- mb-scenario:N -->` и `**Covers:**`. `mb-ears-validate.sh` прошёл для всех восьми requirements.md. Полный `mb-spec-validate.sh` не удалось запустить в read-only sandbox: его mktemp завершился Operation not permitted.

**Сильные стороны:** Umbrella `Covers` формально покрывает все 48 существующих REQ; лишних ссылок на несуществующие umbrella REQ нет.; Во всех семи child-спеках каждый локальный REQ покрыт хотя бы одной child-задачей, и ни одна child-задача не ссылается на неизвестный локальный REQ.; Все восемь requirements.md проходят текущий EARS-валидатор.; Основные существующие расширяемые файлы и скрипты фактически присутствуют; имена заявленных новых скриптов свободны.; D-34 и D-35 отражены в REQ-045…048 и отдельных child-слайсах, несмотря на устаревшие описательные диапазоны.

### svp-adapt-escalation — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие REQ→task полное, но спека пока неисполнима без догадок: один Eval уже зелёный до реализации, контракты гардов/состояния/телеметрии неполны, роли маршрутизируются неверно, а обязательные v2-поля и машиночитаемые сценарии отсутствуют.

**Coverage:** REQ всего 9; задач без REQ: —; gated REQ без GWT: REQ-006, REQ-007; недетерминированные эвалы: T4: поведенческие проверки auto/interactive оставлены ручным Scenarios §3/§4, T5: негативная проверка голого stub оставлена ручной.

REQ-001…REQ-009 покрыты задачами точно; лишних REQ в Covers нет. Семантически сценарии отсутствуют для REQ-006/007. Формально scripts/mb-scenario-extract.py извлекает 0 сценариев из всего файла, поскольку нет mb-scenario-маркеров и Covers. Текущие Eval: T1–T4 red, T5 уже green.

**Сильные стороны:** REQ→task coverage полное: 9/9 требований, все пять задач ссылаются только на существующие REQ.; Новые имена `scripts/mb-work-adapt.sh` и `tests/mb-work-adapt.bats` свободны; все заявленные расширяемые основные файлы существуют.; Архитектурное разделение «решение — скрипт, применение — оркестратор» согласуется с существующим pivot-паттерном.; Scope-гард S3 помечен как optional с явной деградацией, а hard dependency на S2 отражена в frontmatter и roadmap.; T1 задуман как настоящий Bats red→green и охватывает несколько guard-классов, cascade и JSONL.

### svp-brief — CHANGES_REQUESTED

Спека имеет полное REQ→task покрытие, но пока неисполнима без угадывания: небезопасно определена обработка секретов, отсутствует контракт основной команды, не оформлены машинно-читаемые сценарии, а ключевые Eval проверяют лишь наличие слов.

**Coverage:** REQ всего 8; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008; недетерминированные эвалы: Task 1 — grep не проверяет файловое поведение; приемка опирается на ручные сценарии, Task 3 — grep слова brief не доказывает чтение brief.md и inputs/.

Все 8 REQ покрыты существующими задачами; все 4 задачи ссылаются на существующие REQ. mb-scenario-extract.py вернул 0 сценариев: отсутствуют маркеры mb-scenario и поля Covers. Текущие Eval действительно red: T1/T3/T4 exit 1; файл T2 отсутствует. Ложных red не найдено.

**Сильные стороны:** REQ→task покрытие точное: 8/8, orphan REQ и ссылок на несуществующие REQ нет.; Все заявленные Eval сейчас действительно red; grep-эвалы не оказались ложно зелёными на текущем репозитории.; Декомпозиция на четыре задачи реалистична и не превышает лимит ≤120k на задачу.; Self-interview assumptions и родительский D-34 прослеживаются через context → requirements → tasks.; Имена создаваемых файлов свободны, а расширяемые `commands/discuss.md`, `commands/mb.md` и `references/templates.md` существуют.

### svp-docs-wiki — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Все 9 REQ формально связаны с задачами, а текущие Eval-команды действительно красные. Однако спека пока не исполнима однозначно: отсутствуют машинно распознаваемые сценарии, обязательные поля task v2 и межслайсовые зависимости; CLI/state/transaction contracts неполны; несколько Eval проверяют лишь наличие текста; не определены атомарность, path migration и честная деградация.

**Coverage:** REQ всего 9; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009; недетерминированные эвалы: —.

Точное покрытие задачами: T1→REQ-001,005,006,009; T2→REQ-001,002,003,004; T3→REQ-002,003,004; T4→REQ-007; T5→REQ-008. `mb-scenario-extract.py --validate` завершился с exit 0, но извлёк ноль сценариев: отсутствуют `<!-- mb-scenario:N -->` и `**Covers:**`. Прозаические сценарии покрывают REQ-001,002,004,005,006,007; для REQ-003,008,009 сценариев нет. Все Eval сейчас красные; уже зелёных grep-эвалов не найдено.

**Сильные стороны:** Все 9 требований имеют хотя бы одну существующую задачу; orphan REQ-ID и задачи без Covers отсутствуют.; Все заявленные Eval-команды сейчас красные; уже проходящих grep-эвалов не найдено.; Все файлы, которые спека намерена расширять, существуют; новые имена `scripts/mb-docs.py`, agent-файлы и test-файлы пока свободны.; Спека сохраняет ключевые решения интервью: SHA-state рядом с docs, bootstrap full overview, index/log/pages, host subagents вместо прямого API и pipeline-based docs.path.; Базовые идеи Karpathy-паттерна отражены корректно: исходники read-only, wiki LLM-owned, индекс однострочный, лог append-only, страницы связаны wikilinks.

### svp-interview-upgrade — CHANGES_REQUESTED

Спека имеет полное REQ→task-покрытие, но не готова к реализации: найдены 8 major-дефектов. Основные блокеры — отсутствие машиночитаемых сценариев, поведенчески слабые Eval, несовместимый контракт secret scanner, незавершённый контракт оценки размера, потеря NFR о структурной валидации артефактов, неполное наследование D-10/D-12, отсутствие group/ICE frontmatter и неопределённая семантика CLI-флагов.

**Coverage:** REQ всего 19; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-018, REQ-019; недетерминированные эвалы: T1 — grep проверяет наличие текста, функциональный сценарий оставлен ручным, T2 — grep проверяет только слова batch/self, функциональный сценарий оставлен ручным, T4 — grep проверяет текст шаблона, а scanner-тест сделан условным, T5 — grep не доказывает обновление glossary по результатам интервью, T6 — grep не проверяет допустимые комбинации и поведение флагов.

Все 19 REQ покрыты существующими задачами; каждая из 6 задач покрывает хотя бы один существующий REQ. В requirements.md описаны 6 сценариев, но отсутствуют обязательные <!-- mb-scenario:N --> и **Covers:**, поэтому сценарный экстрактор видит 0 gated-сценариев. По человеческому чтению сценарии упоминают REQ-002/003/004/007/008/009/010/012/013/018; семантически без сценария остаются REQ-001/005/006/011/014/015/016/017/019. Все заявленные Eval-команды сейчас красные; ложных уже зелёных grep-эвалов не найдено. Штатный валидатор нельзя было запустить в read-only sandbox из-за попытки создать временный файл, поэтому покрытие пересчитано независимо по исходным файлам.

**Сильные стороны:** Покрытие requirements→tasks полное и точное: 19 из 19 REQ покрыты, dangling-ссылок и задач без REQ нет.; REQ-блоки context и requirements согласованы; потерь среди 19 явно нумерованных child-требований не найдено.; Все объявленные Eval-команды сейчас действительно красные; ложных уже проходящих grep-red обнаружено не было.; T3 уже предусматривает реальный Bats Eval и не менее пяти отрицательных/граничных случаев для estimate checker.; Декомпозиция на шесть задач выглядит реалистичной для лимита ≤120k токенов на задачу; задач-монстров и микрозадач не обнаружено.; Спека явно учитывает cancel/resume, honest degradation, Bash 3.2 и запрет на запись банка не-оркестратором.

### svp-parallel-engine — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Локальное покрытие REQ→tasks полное, но спека не готова к реализации: потерян обязательный umbrella-контракт обнаружения DAG-циклов, claim-алгоритм допускает двух победителей, межслайсовые интерфейсы Scope/group не закрыты, а полноценный Pi/OpenCode dispatch противоречит текущему platform_limited состоянию. Требуются исправления двух critical и восьми major дефектов.

**Coverage:** REQ всего 12; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012; недетерминированные эвалы: Task 4.

Все 12 локальных REQ покрыты шестью задачами, и каждая задача ссылается только на существующие REQ. Однако `mb-scenario-extract.py` извлекает 0 сценариев: в requirements.md отсутствуют обязательные `<!-- mb-scenario:N -->` и `**Covers:**`. Точные shell Eval T4 и T6 сейчас возвращают exit 1; при этом отдельный conjunct `grep -q 'claims' commands/work.md` уже зелёный из-за существующего текста на commands/work.md:324. Запуск тестовых процессов ограничен read-only окружением, поэтому red-состояние новых test targets дополнительно подтверждено их отсутствием в репозитории.

**Сильные стороны:** Точное локальное покрытие полное: 12/12 REQ имеют task, все 6 tasks покрывают хотя бы один существующий REQ, лишних REQ-ссылок нет.; Спека сохраняет подтверждённые решения интервью: default N=3, judge serial, JSONL claims в tmp, отсутствие автоматизации worktree и честный sequential fallback.; Новые имена `scripts/mb-work-claims.sh`, `scripts/mb-work-scope-check.sh` и заявленные test files свободны; расширяемые `mb_work_items.py`, `mb-work-resolve.sh`, `commands/work.md` и `pipeline.default.yaml` существуют.; Разделение deterministic seams C1–C3 от prompt orchestration соответствует родительскому принципу «логика в коде, оркестратор управляет»; дефекты находятся преимущественно в недоописанных контрактах, а не в выбранной архитектурной границе.

### svp-roadmap-backlog-db — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Задачи покрывают все 12 REQ без orphan-ссылок, а их Eval сейчас действительно красные. Однако спецификация не исполнима без существенных догадок: отсутствуют машинно-извлекаемые сценарии, не определены ключевые контракты сортировки, прогресса, backlog state machine, registry и lint, а миграция не охватывает реальные legacy-статусы текущего backlog.

**Coverage:** REQ всего 12; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012; недетерминированные эвалы: —.

Все REQ покрыты задачами: T1→001/002/003/012, T2→005/006/007/008, T3→009/010/011, T4→004/012, T5→001/005. Но `mb-scenario-extract.py` не распознаёт ни одного сценария: отсутствуют `<!-- mb-scenario:N -->` и `**Covers:**`. Семантически prose-сценарии охватывают 001/002/005/007/008/010/011/012; для 003/004/006/009 нет даже prose-сценария. Все пять Eval сейчас red; Task 5 при этом недостаточно проверяет требования. Полный `mb-spec-validate.sh` не удалось запустить из-за запрета sandbox на создание временного файла; отсутствие сценариев подтверждено прямым запуском штатного extractor.

**Сильные стороны:** Точное REQ→task покрытие: все 12 требований имеют исполнителя, все пять задач ссылаются только на существующие REQ.; Все заявленные Eval сейчас red: четыре Bats-файла отсутствуют, Task 5 grep возвращает non-zero; новые script names свободны, а заявленные extension targets существуют.; Спека сохраняет решения интервью: Markdown остаётся базой данных, migration и lint разделены, rejected `ice.yaml`, `groups.md` и отдельный out-of-scope файл не возвращены в scope.; Для migration уже предусмотрены dry-run, backup и idempotence, а для roadmap — сохранение содержимого вне autosync fence.

### svp-sdd-core — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
REQ→task-трассировка полная, но спека пока не исполнима без догадок: формальные scenario-гейты отсутствуют, несколько интерфейсов недоопределены, межслайсовые зависимости не зафиксированы, а собственные задачи не соответствуют вводимому v2-формату и лимитам.

**Coverage:** REQ всего 14; задач без REQ: —; gated REQ без GWT: REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014; недетерминированные эвалы: —.

REQ→task: 14/14, неизвестных REQ-ссылок нет, все 6 задач имеют Covers. Человекочитаемые заголовки сценариев упоминают 8 REQ (001,002,003,005,007,008,010,012), но ни один сценарий не имеет <!-- mb-scenario:N --> и **Covers:**, поэтому mb-scenario-extract.py извлёк 0 записей; ещё 6 REQ не покрыты даже неформально. Все шесть Eval-команд сейчас действительно red: тестовые файлы T1–T3 отсутствуют, точные команды T4–T6 вернули rc=1. Штатный mb-spec-validate не удалось выполнить в read-only sandbox: его mktemp получил Operation not permitted; EARS-валидатор завершился с exit 0.

**Сильные стороны:** Полная и точная REQ→task-трассировка: 14/14 REQ покрыты, каждая из 6 задач ссылается только на существующие REQ.; Eval T1–T3 имеют настоящий red: заявленные test-файлы ещё отсутствуют; T4–T6 также сейчас красные, то есть already-green ложных red не найдено.; Спека сохраняет ключевые решения интервью: prompt-layer вместо Python-оркестратора, bold v2-поля, spec_review default-off, D-35 и отсутствие нового judge-агента.; Границы слайса и владельцы соседних механизмов в context обозначены явно; основные расширяемые seams существуют, кроме ожидаемого S1-артефакта `mb-estimate-check.sh`.

