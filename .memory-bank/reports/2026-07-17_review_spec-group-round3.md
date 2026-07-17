# Spec review, круг 3: группа sdd-vision-pipeline (9 спек + смысловой аудит, Codex gpt-5.6-sol, effort=high)

> Дата: 2026-07-17 · Повторная валидация после закрытия 83+8 находок круга 2.
> 9 технических ревьюеров (по одному на спеку; каждому передан raw-вердикт круга 2 для фактической проверки закрытий)
> + 1 смысловой аудитор всей группы (транскрипты интервью + леджеры решений + AGR → трассировка каждой смысловой единицы в спеки).

## Сводка вердиктов (технический круг)

| Спека | Вердикт | crit | major | minor | nit | REQ | UNFIXED/PARTIAL из круга 2 |
|---|---|---|---|---|---|---|---|
| sdd-vision-pipeline (umbrella rev. 3 + S1–S8) | CHANGES_REQUESTED | 1 | 4 | 2 | 0 | 54 | 2 |
| svp-adapt-escalation | CHANGES_REQUESTED | 0 | 8 | 0 | 0 | 10 | 2 |
| svp-brief | CHANGES_REQUESTED | 0 | 8 | 1 | 0 | 10 | 0 |
| svp-contract-test-loop | CHANGES_REQUESTED | 1 | 6 | 0 | 0 | 21 | 4 |
| svp-docs-wiki | CHANGES_REQUESTED | 2 | 8 | 0 | 0 | 12 | 2 |
| svp-interview-upgrade | CHANGES_REQUESTED | 1 | 4 | 1 | 0 | 24 | 2 |
| svp-parallel-engine | CHANGES_REQUESTED | 0 | 6 | 0 | 0 | 17 | 6 |
| svp-roadmap-backlog-db | CHANGES_REQUESTED | 1 | 10 | 0 | 0 | 12 | 1 |
| svp-sdd-core — round 3 | CHANGES_REQUESTED | 1 | 6 | 1 | 1 | 22 | 1 |

Всего находок: **73** (из них 20 — не полностью закрытые находки круга 2, остальные — новые R3-*).

---

# Часть 1. Смысловой аудит группы (агент №10)

**Вердикт: INTENT_MOSTLY_PRESERVED**

Большая часть замысла сохранена. Из восьми находок круга 2 шесть исправлены полностью, INT-PLAN-CONTRACT-EVAL осознанно закрыта решением AGR-019, а D-14-ICE-SCHEMA исправлена лишь частично. Свежий проход выявил одну новую потерю: из односессионного параллельного контура без зафиксированного решения исчез Cursor.

## Трассировка смысловых единиц

- **deferred_explicitly**: 1
- **lost**: 1
- **preserved**: 46
- **weakened**: 3

Не-preserved единицы:

- **D-07** · weakened · svp-parallel-engine REQ-001/003/008/015, design C8, Task 10
  Фронтир, Scope-сериализация, выбор sequential/parallel и разделение intra-session/COORDINATION сохранены, но заявленный пользователем Cursor выпал из full-mode без осознанного решения об отказе.
- **D-14** · weakened · svp-roadmap-backlog-db REQ-001/004, design C1/C2, Tasks 1/6; frontmatter восьми child-спек
  Компоненты ICE и вычисление I×C×E восстановлены, но подтверждение пользователя не влияет на авторитетную сортировку; все child-спеки остаются ice_confirmed:false, включая явно подтверждённые значения.
- **INT-MULTI-HOST-PARALLEL** · weakened · svp-parallel-engine REQ-015, design C8, Task 10
  Claude Code, Pi и OpenCode восстановлены после круга 2, но Cursor, прямо названный пользователем, отсутствует без явного deferral или platform_limited-контракта.
- **INT-DOCS-QUERY-MVP** · deferred_explicitly · svp-docs-wiki context Out of Scope и design Decisions
  Отдельная query-команда сознательно вынесена в будущий слайс; текущий scope ограничен генерацией и lint.
- **INT3-CURSOR-INTRASESSION-PARALLEL** · lost · svp-parallel-engine REQ-015, design C8, Task 10
  Спеки называют D-07 «ровно трёххостовым», хотя первоисточник явно включал Cursor; решения об исключении или отложении Cursor нет.

## Потерянные/искажённые смыслы (lost_intents)

### [major] UNFIXED:D-14-ICE-SCHEMA

**Цитата-источник:** «ICE во frontmatter спек/планов (LLM предлагает, пользователь подтверждает); score=I×C×E — авторитетный порядок Next + pin-override»

**Что потеряно:** Компонентная схема и вычисление score восстановлены, но пользовательское подтверждение осталось декоративным: S4 прямо предписывает, что ice_confirmed не влияет на порядок, а все восемь child-спек имеют ice_confirmed:false. При этом roadmap уже использует эти оценки как авторитетный порядок. Это позволяет неподтверждённому предложению LLM управлять очередью и неверно маркирует как неподтверждённые как минимум S1 и S8, чьи ICE подтверждены в источниках.

**Где должно приземлиться:** specs/svp-roadmap-backlog-db requirements REQ-001/004, design C1/C2, Tasks 1/6; frontmatter всех child-спек; roadmap group renderer.

**Как исправить:** Сделать подтверждение частью авторитетности: неподтверждённый ICE не должен управлять финальной очередью до подтверждения либо должен считаться явно предварительным порядком. Установить ice_confirmed:true только для оценок с доказанным пользовательским подтверждением, включая S1 и S8, а остальные запросить или оставить неавторитетными.

### [major] INT3-CURSOR-INTRASESSION-PARALLEL

**Цитата-источник:** «параллель в одной сессии: оркестратор + параллельные саб-агенты (Claude Code, и через саб-агентов в Pi, OpenCode, Cursor); заложить сразу в движок»

**Что потеряно:** Cursor исчез при дистилляции D-07 и нарезке S3: текущие requirements/design/tasks объявляют полный режим только для Claude Code, Pi и OpenCode и называют это «ровно трёххостовым scope D-07». Ни rationale, ни пользовательского отказа, ни явного deferral для Cursor нет.

**Где должно приземлиться:** specs/svp-parallel-engine requirements REQ-015, design C8/NFR-001, Task 10 и dispatch contract tests.

**Как исправить:** Добавить capability-based dispatch/probe для Cursor. Если транспорт объективно отсутствует, зафиксировать отдельное подтверждённое пользователем deferral с platform_limited-поведением и backlog-ссылкой; не называть трёххостовый набор полным D-07.


**Notes:** Аудит выполнен read-only; файлы не изменялись. Все девять транскриптов и леджеров были прочитаны до спек. Проверены текущие тексты девяти triple, roadmap, AGR-017/018/019 и восемь находок круга 2. Волновые фиксы полностью закрыли D-18-FACT-FINDING, D-17-SINGLE-SEAM, D-25-STRUCTURAL-EVAL, D-32-LARGE-TARGET-UMBRELLA, AGR-018-UMBRELLA-WORDING и D-31-UMBRELLA-ORDER; INT-PLAN-CONTRACT-EVAL закрыта осознанным отказом AGR-019.

---

# Часть 2. Технические находки (severity ↓, затем спека)

### CRITICAL (7)

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-001 · edge-case · `.memory-bank/specs/sdd-vision-pipeline/design.md:51-55; .memory-bank/specs/svp-roadmap-backlog-db/design.md:405-450; .memory-bank/specs/svp-roadmap-backlog-db/tasks.md:66-84`

**Проблема:** PARTIAL: R2-007 — новый mv-reclaim всё ещё допускает двух писателей, а контракт helper не фиксирует stdout/exit-коды.

**Доказательство:** S4 задаёт `mv "$lock" "$lock.reclaim.<token>"`, затем при чужом token пытается вернуть каталог; если `$lock` уже занят, живой lock остаётся в quarantine (`design.md:433-444`). Интерливинг остаётся разрушительным: X прочитал dead D; Y удалил D; Z захватил новый lock; X переместил lock Z; W захватил освободившийся `$lock`; возврат X невозможен — Z и W одновременно считают себя владельцами. Сама спека признаёт окно (`design.md:446-450`), но ошибочно классифицирует его только как потерю доступности. При этом `mb_lock_acquire <lock_dir> <timeout> <ttl>` описан без stdout и exit-кодов (`design.md:405-410`), хотя потребители ожидают token для release.

**Рекомендация:** Заменить rename/reclaim протокол на операцию, которая может удалить только точный owner-token и никогда не перемещает свежий lock; одновременно закрыть полный CLI/function-контракт.

**Готовая правка:**

```
Заменить umbrella Interface 2 и S4-C6 следующим контрактом: `mb_lock_acquire <lock_dir> <timeout> <ttl>` при успехе печатает ровно token `PID-RANDOM` и возвращает 0; timeout возвращает 1 с пустым stdout; malformed args — 2. Внутри lock создаётся каталог `owner.<token>`. Reclaim dead token D выполняет только `rmdir "$lock/owner.$D"`; лишь победитель затем делает `rmdir "$lock"`, который проходит только для пустого каталога. Никаких `mv` и `rm -rf` в reclaim. Пустой lock без owner разрешено убрать только по TTL-fallback. `mb_lock_release <lock_dir> <token>` удаляет только `owner.<token>`, затем пустой lock; чужой token — no-op. Добавить race-тест: X/Y видят D, Y освобождает, Z захватывает свежий lock, поздний X не может удалить `owner.Z`; во всей трассе ровно один процесс находится в critical section.
```

#### [svp-contract-test-loop] R3-001 · consistency · `.memory-bank/specs/svp-contract-test-loop/design.md:62-65,139-145; tasks.md:112-123`

**Проблема:** Легаси-совместимость противоречит дефолту `layers=true`: новый валидатор сделает существующие спеки невалидными, включая саму S8.

**Доказательство:** C1 говорит: «Дефолт всех трёх — true» и «Отсутствие блока = все дефолты» (`design.md:62-65`). C3 затем требует при `contract_first=true` и gated REQ ровно одну `Layer: contract` (`design.md:139-145`). Но Task 3 одновременно требует `spec_validate_legacy_spec_without_layers_ok` и byte-identical legacy (`tasks.md:118,123`). У самой S8 блока `layers` нет (`requirements.md:1-9`), gated REQ есть, а `Layer:` встречается только у integration/e2e (`tasks.md:252,283`), поэтому после реализации T3 эта спека должна провалить собственный валидатор.

**Рекомендация:** Развести новые спеки и grandfathered legacy-спеки детерминированным признаком, сохранив quality-default для новой генерации.

**Готовая правка:**

```
Заменить REQ-012/013 и C1 следующим текстом:

`Новая генерация /mb sdd всегда записывает явный блок layers; если пользователь не менял настройки, значения берутся из pipeline.yaml:sdd.layers и равны true. Спека без блока layers считается legacy: read_spec_layers возвращает все три значения false, source="legacy", файл не мутируется. Новые layer-гейты и обязательность Quality DoD к source="legacy" не применяются; валидатор печатает layers=legacy. SpecLayers.source = Literal["spec","pipeline","legacy"].`

В REQ-015 заменить `every spec` на `every spec generated by the new SDD pipeline`. Добавить тест, что текущая S8 и одна pre-S8 fixture остаются валидными после T3.
```

#### [svp-docs-wiki] R3-001 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:99-107,179-180,234-247`

**Проблема:** Bootstrap-прогон всегда отклоняется как `stale_run`.

**Доказательство:** Стейт без истории содержит `"sha": null` (`design.md:99-107`), но plan нормализует base в литерал `bootstrap` (`:179-180`). Apply затем буквально проверяет `results.base_sha != state.sha` (`:236-237`), поэтому на первом запуске сравнивает `"bootstrap" != null` и завершается до записи. Это делает REQ-005 и Scenario 2 невозможными.

**Рекомендация:** Нормализовать ожидаемый base одинаково в plan и apply.

**Готовая правка:**

```
В C5.2 заменить stale-гард на: `expected_base = state.sha if state.sha is not null else "bootstrap"; results.base_sha != expected_base → exit 5 error=stale_run expected_base=<expected_base> actual_base=<results.base_sha>`. В T4 добавить тест первого bootstrap-apply: state.sha=null, results.base_sha="bootstrap" → apply проходит и записывает target SHA.
```

#### [svp-docs-wiki] R3-002 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:194-205,302-325,234-247`

**Проблема:** Apply не связан с авторитетным plan: LLM управляет target SHA, а `deprecate` и `degraded_sources` теряются.

**Доказательство:** Plan вычисляет `docs_path`, `deprecate` и `degraded_sources` (`design.md:194-205`). Synthesizer вместо потребления неизменяемого plan сам возвращает `run_id/base_sha/target_sha`, но не возвращает `deprecate` или `degraded_sources` (`:302-310`); оркестратор сохраняет его JSON «как есть» (`:321-325`). Apply проверяет только base SHA и затем записывает LLM-поле target SHA в state (`:236-247`). Модель может изменить target/run_id; apply продвинет state на неверный SHA. Одновременно ему неоткуда получить рассчитанный plan.deprecate, а итоговый `applied`-result не способен сообщить REQ-010 `degraded_sources`.

**Рекомендация:** Отделить детерминированный plan от недоверенного содержимого агентов и передавать apply оба артефакта.

**Готовая правка:**

```
Изменить контракт на `bash scripts/mb-docs-apply.sh --plan <bank>/tmp/docs-plan-<run_id>.json --results <bank>/tmp/docs-results-<run_id>.json`. Оркестратор сохраняет stdout `mb-docs.py plan` без изменений в `--plan`; synthesizer возвращает только `{pages,log_entry}`. Apply использует run_id/base_sha/target_sha/docs_path/deprecate/degraded_sources исключительно из plan, проверяет `run_id == "<expected_base>..<target_sha>"`, target SHA является достижимым commit и current state соответствует expected_base. Финальный stdout обязан включать `"degraded_sources":[...]`. В T4 добавить негативные тесты на подменённые run/base/target и сквозной тест deprecate.
```

#### [svp-interview-upgrade] R3-001 · parent-decision · `.memory-bank/specs/svp-interview-upgrade/requirements.md:76; .memory-bank/specs/svp-interview-upgrade/design.md:206; .memory-bank/specs/svp-interview-upgrade/tasks.md:127; rules/RULES.md:776`

**Проблема:** Политика transcript разрешает реальному секрету внутри <private> попасть в git в открытом виде.

**Доказательство:** REQ-007 разрешает снять блокировку, если контент «explicitly marked private» (`requirements.md:78`), C5 маскирует содержимое `<private>` до скана (`design.md:206-212`), а тест прямо требует `scan=clean` для ключа внутри private (`tasks.md:136`). После этого candidate атомарно переносится в git-путь (`design.md:219-223`). Но правило проекта однозначно предупреждает: `<private>` защищает только index/search, «NOT git diff» (`rules/RULES.md:784-789`). Это противоречит критерию успеха «секреты не утекают в git» (`context/svp-interview-upgrade.md:19`) и соседнему owner/consumer-контракту S7, где `<private>` не подавляет scanner finding (`svp-brief/design.md:147-170`).

**Рекомендация:** Развести index/search-редакцию и допуск к git: scanner должен проверять исходное содержимое private-блоков и блокировать credential до удаления или необратимой редакции.

**Готовая правка:**

```
Заменить REQ-007 на:
- **REQ-007** (unwanted): If the secret-scan flags content in a transcript candidate, then the system shall block publication until the flagged credential is removed or irreversibly redacted; `<private>` markers shall affect only index/search redaction and shall not suppress scanner findings.

В C5 заменить политику transcript на:
- **Политика `transcript`**: сканируется исходный текст, включая содержимое `<private>…</private>`. `<private>` и `<!-- mb-secret-ok -->` не подавляют findings; они не являются разрешением записать credential в git. Номера строк относятся к исходному файлу.

В Scenario 4 заменить THEN на:
- THEN запись блокируется до удаления или необратимой редакции credential; одна лишь пометка `<private>` блокировку не снимает.

В Task 4 заменить тест `секрет внутри <private> → scan=clean` на `секрет внутри <private> → scan=blocked`.
```

#### [svp-roadmap-backlog-db] R2-003-R3 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:219`

**Проблема:** PARTIAL: R2-003 — S3 всё ещё не реализует authoritative ordering-контракт S4

**Доказательство:** S4 трактует отсутствующий или невалидный ICE как legacy/no-ice tail без падения и берёт created спеки из context/<topic>.md (`svp-roadmap-backlog-db/design.md:80-94,140-150`). S3, напротив, читает created из requirements.md, требует ice у каждого члена и завершает missing ice с exit 2, invalid ice с exit 3 (`svp-parallel-engine/design.md:219-245`; `tasks.md:243-250`). При этом тот же Task 5 требует сравнить порядок именно на missing/invalid ICE, поэтому его собственные assertions несовместимы.

**Рекомендация:** Выровнять S3 под текущий текст владельца S4 и закрепить единый физический набор фикстур.

**Готовая правка:**

```
В S3-C5 и Task 5 заменить контракт источников и ошибок на: `created для спеки читается из context/<topic>.md; requirements.md остаётся источником group/ice/pin/blocked_by. Отсутствующий или невалидный ice не является exit 2/3: member получает ice:null, классифицируется как legacy_tail и участвует в том же порядке, что S4-C2; invalid ice дополнительно даёт stderr warning. Exit 3 остаётся только для malformed pin/created/blocked_by.` Изменить JSON-схему на `"ice":<int|null>`. В S4-C2/Task 6 и S3-C5/Task 5 назвать общий файл `tests/fixtures/svp_group_ordering.json` и потребовать byte-identical topic order для duplicate pin, missing ice, equal ICE и invalid ICE.
```

#### [svp-sdd-core — round 3] F-010 · contract · `.memory-bank/specs/svp-sdd-core/design.md:240-277; .memory-bank/specs/svp-sdd-core/tasks.md:218-226`

**Проблема:** PARTIAL: F-010 — work-state API появился, но red/green всё ещё можно сфальсифицировать входными флагами.

**Доказательство:** C6 объявляет `eval-red ... --exit <n> --observed <true|false> --match <true|false>` и `eval-green ... --exit <n>` (`design.md:250-254`), хотя ниже утверждает: «red_match вычисляется кодом» (`design.md:269-275`). Helper не получает stdout/stderr или red-якоря и не запускает Eval-команду, поэтому вызов с `--observed true --match true` либо `eval-green --exit 0` может записать успех без доказательства. Task 8 повторяет доверенные флаги (`tasks.md:218-220`).

**Рекомендация:** Сделать work-state writer единственным исполнителем и судьёй Eval-команды; caller не должен передавать вычисленные verdict-поля.

**Готовая правка:**

```
Заменить C6 CLI на:
`bash scripts/mb-work-state.sh eval-red --cmd-file <path> [--expected-exit <n>] --output-re <ERE> [--run-id ID] [--mb <bank>]`
`bash scripts/mb-work-state.sh eval-green --cmd-file <path> [--run-id ID] [--mb <bank>]`

Добавить контракт:
- обе субкоманды запускают byte-identical содержимое cmd-file из git root и сами захватывают объединённый stdout+stderr и фактический exit;
- eval-red компилирует ERE, вычисляет match внутри helper и возвращает 0 только при совпадении всех объявленных якорей; mismatch/foreign failure → exit 1, usage/corrupt state/invalid ERE → exit 2;
- eval-green самостоятельно запускает сохранённую команду и возвращает 0 только при фактическом exit 0;
- флаги `--observed`, `--match` и передаваемый caller-ом фактический `--exit` удалить;
- тесты обязаны доказать, что подставить true/0 через CLI невозможно.
```

### MAJOR (60)

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-002 · contract · `.memory-bank/specs/svp-contract-test-loop/requirements.md:34-36; .memory-bank/specs/svp-contract-test-loop/design.md:152-218,379; .memory-bank/specs/svp-contract-test-loop/tasks.md:175-204`

**Проблема:** PARTIAL: R2-006 — реестр checker-команд закрыт, но формат evidence красного прогона и resume/drift-гейт по-прежнему не определены.

**Доказательство:** REQ-004 требует записать red-run (`requirements.md:34`). C3a задаёт только путь `evidence: <bank>/tmp/contract-gate/<topic>/<id>.<phase>.json` (`design.md:168`) и говорит, что runner пишет evidence (`design.md:218`), но JSON-схемы, atomic-write, проверки существования red-evidence перед verify и поведения при изменении `cmd` нет. Task 5 проверяет лишь `contract_gate_evidence_written` (`tasks.md:203`). Утверждение, что «формат записи ... зафиксирован реестром» (`design.md:379`), неверно: реестр фиксирует путь, не содержимое.

**Рекомендация:** Оставить durable registry в tasks.md согласно принятому отклонению, но определить точную схему и lifecycle отдельного evidence-файла.

**Готовая правка:**

```
Добавить в C3a: `Evidence JSON имеет закрытую схему {"version":1,"topic":"<slug>","checker_id":"<id>","phase":"red|verify","cmd":"<byte-identical registry cmd>","cmd_sha256":"<64-hex>","exit":<int>,"output_match":<bool>,"verdict":"pass|fake_red|foreign_failure|red_checker"}`. Запись — temp+atomic mv. Перед verify runner требует существующий валидный red-evidence с `verdict=pass` и byte-identical `cmd`/`cmd_sha256`; missing, malformed или drift → exit 2 без запуска verify. Verify пишет отдельный `.verify.json`. В Task 5 добавить тесты exact-schema, missing-red-evidence, malformed evidence, command drift и crash-before-mv.
```

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-003 · cross-slice · `.memory-bank/specs/sdd-vision-pipeline/design.md:35-55; .memory-bank/specs/svp-parallel-engine/tasks.md:72-83,217-245; .memory-bank/specs/svp-docs-wiki/tasks.md:149-170; .memory-bank/specs/svp-adapt-escalation/tasks.md:127-176`

**Проблема:** R3: DAG не отражает фактические hard-зависимости потребителей от S4; fallback требует править файл вне Scope.

**Доказательство:** Umbrella называет зависимость S3→S4 «мягкой» и разрешает S3 реализовать helper при его отсутствии (`design.md:55`). S3 Task 2 действительно требует править `_lib.sh`, если S4 не отгружен, но Scope содержит только claims script и тест (`parallel-engine/tasks.md:72-83`). S3 Task 5 потребляет компаратор S4-C2, но заблокирована только Task 1 (`tasks.md:217-245`). S6 Task 4 также требует fallback-реализацию `_lib.sh`, отсутствующего в Scope (`docs-wiki/tasks.md:149-170`). S5 Task 4 потребляет S4 `annotate`, но внешнего blocker нет (`adapt-escalation/tasks.md:127-176`). При допустимом топологическом порядке до S4 агент либо застрянет, либо нарушит Scope/DRY.

**Рекомендация:** Закодировать зависимости на уровне конкретных child-задач и удалить все fallback-копии чужих контрактов.

**Готовая правка:**

```
Изменить Blocked-by: S3 Task 2 → `1, svp-roadmap-backlog-db#2`; S3 Task 5 → `1, svp-roadmap-backlog-db#1`; S6 Task 4 → `1, 2, 3, 5, 6, 7, svp-roadmap-backlog-db#2`; S5 Task 4 → `3, svp-roadmap-backlog-db#2`. Удалить из S3/S6 фразы `если helper ещё не отгружен — реализовать ... в _lib.sh`. В umbrella §DAG перечислить эти task-level hard edges и удалить утверждение, что зависимость lock-helper не добавляет жёсткого ребра.
```

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-004 · edge-case · `.memory-bank/specs/svp-adapt-escalation/design.md:47-124; rules/RULES.md:698-706`

**Проблема:** R3: двухфазный escalation-журнал небезопасен при двух orchestrator-сессиях; обоснование через PIPE_BUF фактически неверно.

**Доказательство:** S5 допускает параллельные прогоны, пишущие один `<bank>/tmp/escalations.jsonl`, и утверждает, что один `write()` в O_APPEND атомарен по POSIX при длине ≤PIPE_BUF (`design.md:116-123`). PIPE_BUF гарантирует атомарность pipe/FIFO, не concurrent append в regular file. Проектные правила явно поддерживают несколько сессий в одном working tree (`rules/RULES.md:698-704`). Повреждённая строка затем делает журнал fail-loud и блокирует cascade/replan state (`design.md:101-109`).

**Рекомендация:** Сериализовать весь read-fold-append тем же общим lock-helper вместо опоры на недействительную гарантию.

**Готовая правка:**

```
Заменить C1.0 §Concurrency на: `decide`, `resolve` и `note-clean` удерживают `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` от чтения/валидации журнала через вычисление seq/consecutive до одного append; release выполняется trap. `replan-gate` и summary читают согласованный snapshot под тем же lock. Удалить утверждение про PIPE_BUF и лимит 4096 как гарантию атомарности. Добавить bats с двумя реальными конкурентными orchestrator-процессами: журнал остаётся валидным JSONL, оба run_id сохранены, seq внутри каждого run_id корректен, ни одно opened/resolved событие не потеряно.`
```

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-005 · eval · `.memory-bank/specs/svp-sdd-core/design.md:381,386; .memory-bank/specs/svp-sdd-core/tasks.md:65,197; .memory-bank/specs/svp-brief/design.md:267-270; .memory-bank/specs/svp-brief/tasks.md:42,103,191,225`

**Проблема:** R3: шесть Eval-деклараций design.md содержат невалидные для заявленного red ERE и расходятся с tasks.md.

**Доказательство:** В design-таблицах альтернативы записаны как `a\|b` внутри ERE, например `brief_validate_(diagnostics_order\|missing_section\|usage)` (`svp-brief/design.md:267`) и `(same_model\|jsonl_append)` (`svp-sdd-core/design.md:386`). В POSIX ERE экранированный `\|` означает литеральный `|`: прямой `grep -E` по настоящей строке `not ok 1 brief_validate_missing_section` возвращает 1. Исполняемые tasks.md используют правильный `a|b` (`brief/tasks.md:42`, `sdd-core/tasks.md:65,197`). D-05 объявляет design §Eval контрактом, поэтому два источника противоречат друг другу.

**Рекомендация:** Сделать design-декларации byte-identical исполняемым Eval-полям tasks.md.

**Готовая правка:**

```
В `svp-sdd-core/design.md:381,386` и `svp-brief/design.md:267-270` заменить каждое `\|` внутри `output~:` на `|`. Добавить в spec self-check сравнение извлечённых `(command, exit, output~)` из design Eval-table и соответствующего Task Eval; несовпадение должно валить spec validation.
```

#### [svp-adapt-escalation] R3-001 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:116; .memory-bank/specs/svp-adapt-escalation/design.md:129; commands/work.md:308`

**Проблема:** run_id может стать пустым, хотя контракт конкурентности и корреляции требует уникальный идентификатор каждого прогона.

**Доказательство:** C1.0 обосновывает безопасность тем, что у параллельных прогонов разные run_id (`design.md:116-123`), но `decide` делает `--run-id` необязательным с fallback `$MB_WORK_RUN_ID` (`design.md:129-145`). Текущий оркестратор создаёт локальный `RUN_ID` и передаёт его флагами (`commands/work.md:308-314`); `MB_WORK_RUN_ID` там не экспортируется. `note-clean` и `replan-gate` повторяют необязательный параметр (`design.md:293-304`).

**Рекомендация:** Убрать несуществующий implicit transport и однозначно определить область поиска replan history.

**Готовая правка:**

```
Изменить CLI: `decide ... --run-id <non-empty-id>` и `note-clean ... --run-id <non-empty-id>` — обязательны, пустая строка → exit 2. В Task 4 потребовать передачу `--run-id "$RUN_ID"` во все такие вызовы. Из `replan-gate` удалить `[--run-id]` и записать: «гейт выбирает последнее resolved-событие данного item_id по append-порядку среди всех run_id; конкурентный запуск одного item исключён claim-контрактом S3». Добавить тесты на пустой ID, два параллельных run_id и перенос replan между прогонами.
```

#### [svp-adapt-escalation] R3-002 · consistency · `.memory-bank/specs/svp-adapt-escalation/design.md:212; .memory-bank/specs/svp-adapt-escalation/design.md:251`

**Проблема:** resolved_by ложно помечает пользовательское решение как решение оркестратора в autonomous fallback.

**Доказательство:** При `mode=autonomous` и недоступном feature flag решение принудительно становится `fork_user` (`design.md:212-218`), после чего используется AskUserQuestion (`design.md:441-443`). Однако resolve выводит `resolved_by` только из mode: autonomous → orchestrator (`design.md:251-254`). Это создаёт заведомо ложную телеметрию и нарушает заявленную честность REQ-008.

**Рекомендация:** Выводить источник из фактического decision, а не из исходного режима.

**Готовая правка:**

```
Заменить правило на: «`resolved_by=user`, если соответствующий opened имеет `decision=fork_user`; `resolved_by=orchestrator`, если `decision=stub_continue`; для `decision=stop_run` вызов resolve запрещён, exit 2». Добавить Bats-кейс `autonomous + feature_flag_unavailable → fork_user → resolved_by=user`.
```

#### [svp-adapt-escalation] R3-003 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:447`

**Проблема:** Подавление повторного trigger после continue описано, но не имеет входа, состояния или алгоритма.

**Доказательство:** C5 обещает подавлять «ровно тот же набор triggers до следующей фазы item» (`design.md:447-453`). Схемы opened/resolved/clean не хранят фазу (`design.md:55-80`), а decide принимает cycle и guard statuses, но не phase (`design.md:129-150`). Не определено, где переживает подавление, как сравниваются наборы и что означает граница следующей фазы.

**Рекомендация:** Убрать необязательное неподдержанное подавление либо полностью специфицировать его. Для KISS достаточно удалить обещание.

**Готовая правка:**

```
Заменить последнюю ячейку строки `continue anyway` на: «после `continue` текущая фаза возвращается в штатный поток; любое последующее failed-event, включая тот же набор triggers, создаёт новую развилку». Удалить упоминания suppression из тестов, если они есть.
```

#### [svp-adapt-escalation] R3-004 · cross-slice · `.memory-bank/specs/svp-adapt-escalation/tasks.md:15; .memory-bank/specs/svp-adapt-escalation/design.md:164; .memory-bank/specs/svp-sdd-core/tasks.md:208`

**Проблема:** Task 1 зависит от S2-C6 eval-state API, но blocked_by указывает на задачу, которая этот API не поставляет.

**Доказательство:** S5 Task 1 объявляет `svp-sdd-core#1` (`tasks.md:15`), одновременно нормализует объект `eval` из `mb-work-state.sh eval-red|eval-green` (`design.md:164-176`). Эти субкоманды создаются только S2 Task 8 (`svp-sdd-core/tasks.md:208-226`), а не Task 1.

**Рекомендация:** Привязать потребителя к фактической producer-task.

**Готовая правка:**

```
В S5 Task 1 заменить `svp-sdd-core#1` на `svp-sdd-core#8`: `**Blocked-by:** svp-sdd-core#8, svp-parallel-engine#3`. В cross-slice contract table записать: «S2 Task 8 поставляет durable eval object C6; S5 Task 1 потребляет его без fallback».
```

#### [svp-adapt-escalation] R3-005 · feasibility · `.memory-bank/specs/svp-adapt-escalation/tasks.md:186`

**Проблема:** Scope Task 5 запрещает файл, который сама задача обязана изменить.

**Доказательство:** Task 5 Scope содержит только `agents/plan-verifier.md`, `scripts/mb-work-adapt.sh` и Bats-файл (`tasks.md:186`). Но What to do требует изменить verify-шаг `commands/work.md` (`tasks.md:200-202`). При активном S3 Scope-гард закономерно выдаст violation на корректную реализацию задачи.

**Рекомендация:** Синхронизировать Scope с заявленной поверхностью изменений.

**Готовая правка:**

```
Заменить строку Scope на: `**Scope:** agents/plan-verifier.md, commands/work.md, scripts/mb-work-adapt.sh, tests/bats/test_plan_verifier_stub_gate.bats`.
```

#### [svp-adapt-escalation] R3-006 · edge-case · `.memory-bank/specs/svp-adapt-escalation/design.md:343; scripts/mb-work-codex-preflight.sh:46`

**Проблема:** verify-stub напрямую зависит от GNU timeout и не исполним на стандартном macOS.

**Доказательство:** C1.5 и Task 5 требуют запускать driver через `timeout 120` (`design.md:343-344`, `tasks.md:194-198`). Репозиторий уже документирует, что macOS по умолчанию не содержит ни timeout, ни gtimeout, и использует pure-Bash watchdog (`scripts/mb-work-codex-preflight.sh:46-65`). Это противоречит обязательной macOS/Linux и Bash 3.2 переносимости.

**Рекомендация:** Специфицировать portable bounded-run внутри разрешённого Scope Task 5.

**Готовая правка:**

```
Заменить `timeout 120` на контракт: «`mb-work-adapt.sh` вызывает локальный `mb_adapt_bounded_run 120 <driver>`: сначала `timeout`, затем `gtimeout`, иначе Bash 3.2 watchdog с TERM→KILL; все timeout-исходы нормализуются в violation `stub_eval_timeout`». В Testing добавить запуск с PATH без timeout/gtimeout и зависающим driver; ожидается bounded completion и `stub_eval_timeout`.
```

#### [svp-adapt-escalation] SVP-AE-007 · contract · `.memory-bank/specs/svp-adapt-escalation/design.md:97; .memory-bank/specs/svp-adapt-escalation/design.md:245; .memory-bank/specs/svp-adapt-escalation/tasks.md:141`

**Проблема:** PARTIAL: SVP-AE-007 — закрытые JSONL-схемы добавлены, но обязательность backlog_id для skip/stub_continue не определена.

**Доказательство:** Design говорит лишь: «backlog_id — non-null только при resolution ∈ {skip, stub_continue}» (`design.md:98-99`), а CLI оставляет `--backlog-id` необязательным (`design.md:245-248`). Task 4 вызывает `resolve --resolution stub_continue` без `--backlog-id` (`tasks.md:141-143`). Такая реализация может записать stub_continue с null и потерять связь стаба с беклогом, несмотря на REQ-008/009.

**Рекомендация:** Зафиксировать полную матрицу обязательных и запрещённых полей resolution и передавать созданный I-NNN в resolve.

**Готовая правка:**

```
Добавить в C1.2: «Для `resolution=stub_continue|skip` флаг `--backlog-id <I-NNN>` обязателен; отсутствие или неверный формат → exit 2 без append. Для `continue|simplify|replan` `--backlog-id` запрещён. Для `replan` обязательны `--spec` и `--replan-kind`; остальные conditional-поля проверяются по таблице C1.2». В Task 4 заменить вызов на `resolve --id "$escalation_id" --resolution stub_continue --backlog-id "$id"` и добавить Bats-кейсы на каждую разрешённую/запрещённую комбинацию.
```

#### [svp-adapt-escalation] SVP-AE-009B · cross-slice · `.memory-bank/context/svp-adapt-escalation.md:35; .memory-bank/specs/svp-adapt-escalation/design.md:480; .memory-bank/specs/svp-adapt-escalation/design.md:519; .memory-bank/specs/svp-roadmap-backlog-db/design.md:234; .memory-bank/specs/svp-adapt-escalation/tasks.md:133`

**Проблема:** PARTIAL: SVP-AE-009B — потребитель использует annotate, но всё ещё описывает его как отсутствующий и не объявляет фактическую зависимость от владельца.

**Доказательство:** S5 утверждает, что в S4 «писателя … нет» (`context/svp-adapt-escalation.md:35`, `design.md:519-522`, `design.md:587-592`, `design.md:632`). Текущий owner уже определяет `annotate` как единственный writer с полным контрактом (`svp-roadmap-backlog-db/design.md:234-242`), реализуемый S4 Task 2 (`tasks.md:63-75`). При этом S5 Task 4 требует annotate, но имеет только `Blocked-by: 3` (`svp-adapt-escalation/tasks.md:133-155`).

**Рекомендация:** Выровнять S5 под текущий текст владельца и выразить hard dependency во всех уровнях planning chain.

**Готовая правка:**

```
Удалить из context/design/Risks/Cross-slice requests утверждения, что `annotate` отсутствует или ожидает X5-01. Записать: «S4-C3 revision 3 предоставляет `mb-backlog-state.sh annotate`; S5 потребляет контракт без переопределения». В requirements frontmatter установить `blocked_by: [svp-sdd-core, svp-parallel-engine, svp-roadmap-backlog-db]`; в Task 4 — `**Blocked-by:** 3, svp-roadmap-backlog-db#2`; в umbrella Task 6 добавить dependency на umbrella Task 3.
```

#### [svp-brief] R3-001 · consistency · `.memory-bank/specs/svp-brief/requirements.md:42-43,119-125; .memory-bank/specs/svp-brief/design.md:58-61; .memory-bank/specs/svp-brief/tasks.md:148-156`

**Проблема:** Режим `--auto` прямо противоречит REQ-003.

**Доказательство:** REQ-003 без исключений требует: «If … remains unclear … shall ask up to five … questions» (`requirements.md:42`). Scenario 7 при том же неясном intent требует не задавать вопросы (`:123-125`), а C0 говорит, что `--auto` «пропускает гейт … REQ-003» (`design.md:58`). Task 1 одновременно маркирует эту ветку как покрывающую REQ-003/004 (`tasks.md:154-156`).

**Рекомендация:** Добавить исключение `--auto` в нормативные формулировки REQ-003/004 и синхронно обновить context.

**Готовая правка:**

```
В requirements.md и context/svp-brief.md заменить REQ-003/004 на: «- **REQ-003** (unwanted): If the essence or goal remains unclear after analyzing the inputs and `--auto` is not selected, then the system shall ask up to five light clarifying questions before generating the brief.\n- **REQ-004** (state-driven): While the intent is clear from the request and inputs, or `--auto` is selected, the system shall generate the brief without asking questions; when `--auto` bypasses unclear intent, the brief shall carry a non-empty `assumptions_note`.»
```

#### [svp-brief] R3-002 · eval · `.memory-bank/specs/svp-brief/tasks.md:14-16,42,103,191,225; .memory-bank/specs/svp-sdd-core/design.md:85-104`

**Проблема:** Все четыре `output~`-якоря принимают foreign failure за настоящий red.

**Доказательство:** Task 2 прямо объявляет red как отсутствие production-скрипта: «`mb-brief-validate.sh` не существует» (`tasks.md:42`). Остальные якоря тоже матчят только `not ok N <test-name>`. Фактическая ERE-проверка показала совпадение всех четырёх якорей со строками вида `not ok 2 brief_create_publishes_atomically / scripts/mb-brief.sh: No such file or directory`. Это нарушает owner-контракт: отсутствующий target не считается red, а `output~` должен описывать, «что именно упало» (`svp-sdd-core/design.md:92-104`).

**Рекомендация:** Матчить семантический marker assertion mismatch, а setup/ENOENT классифицировать отдельно.

**Готовая правка:**

```
Для каждого Bats-файла добавить setup guard: отсутствие test target печатает `eval_setup_error=target_missing path=<path>` и не считается red. Поведенческие assertions должны печатать `contract_mismatch=<case>`. Заменить якоря на: T2 `output~: contract_mismatch=brief_validate_(diagnostics_order|missing_section|usage)`; T1 `output~: contract_mismatch=(brief_input_policy_pragma|brief_create_publishes_atomically|brief_secret_hard_block)|clause=brief-questions-unclear .*reason=absent`; T3 `output~: clause=discuss-phase0-(brief-manifest|absent-parity) .*reason=absent`; T4 `output~: contract_mismatch=(mb_router_brief_row|mb_router_brief_synopsis|pipeline_docs_brief_stage)`. Ни один якорь не должен совпадать с `eval_setup_error`, `command not found`, `No such file` или `bats-gather-tests`.
```

#### [svp-brief] R3-003 · edge-case · `.memory-bank/specs/svp-brief/design.md:62-68,182-210; commands/mb.md:1050-1054; .memory-bank/specs/svp-brief/tasks.md:119-143`

**Проблема:** Atomic publish не определён для свежего банка, частичного каталога и конкурентных запусков.

**Доказательство:** Инициализация банка создаёт только `experiments,plans/done,notes,reports,codebase` (`commands/mb.md:1050-1054`); `briefs/` и `tmp/` не гарантированы. C6 проверяет только существование `briefs/<topic>/brief.md` (`design.md:188`), затем делает `mv staging briefs/<topic>/` (`:202-206`). Если `briefs/<topic>/` уже существует пустым или появился в гонке, стандартный `mv` вложит staging внутрь него вместо отказа. Тесты покрывают только уже существующий `brief.md`, но не пустой каталог, fresh-bank или два параллельных create (`tasks.md:120-143`).

**Рекомендация:** Зафиксировать bootstrap корней, блокировку topic и exists-гейт для любого объекта по destination path.

**Готовая правка:**

```
В C6 перед exists-гейтом добавить: «Helper создаёт `<bank>/tmp/` и `<bank>/briefs/`, если они отсутствуют. Перед проверкой destination он захватывает owner-token `mkdir`-lock `<bank>/tmp/.brief-<topic>.lock`; под lock повторно проверяет путь. Если `briefs/<topic>` существует как файл, каталог или symlink, результат — `brief=blocked reason=exists`, exit 1. Одиночный `mv` выполняется под тем же lock; lock снимается после publish/отказа. Два конкурентных create дают ровно один `created` и один `exists`; вложенный staging-каталог недопустим.» В Task 1 добавить Bats-кейсы `brief_first_publish_creates_roots`, `brief_empty_topic_dir_blocks`, `brief_concurrent_create_one_wins`.
```

#### [svp-brief] R3-004 · contract · `.memory-bank/specs/svp-brief/design.md:76-85,106-114,197-199; .memory-bank/specs/svp-brief/tasks.md:97-101,139-140`

**Проблема:** C6 обязан парсить Attachments, но грамматика ссылок не определена.

**Доказательство:** C2 требует равенство множества «ссылок секции Attachments» и frontmatter/argv (`design.md:113-114`), однако C1 определяет только наличие заголовка, а Task 1 говорит лишь «со ссылками `inputs/<basename>`» (`tasks.md:97-98`). Не определены Markdown-форма, пустое значение, порядок, escaping и имена с пробелами/`#`/`)`. Разные реализации неизбежно распарсят разные множества.

**Рекомендация:** Установить каноническую построчную грамматику Attachments и проверить специальные basename.

**Готовая правка:**

```
Добавить в C2: «При непустом inputs тело `## Attachments` содержит ровно по одной строке `- [<basename>](inputs/<encoded-basename>)` в порядке аргументов `--input`; `<encoded-basename>` — UTF-8 percent-encoding по RFC 3986, safe-набор `A-Z a-z 0-9 -._~`. При пустом inputs тело содержит ровно `- None`. Другие непустые строки запрещены. C6 декодирует destinations, отклоняет malformed/duplicate links и сравнивает полученное множество с frontmatter и argv.» Добавить тесты для пустого списка и basename с пробелом, `#` и `)`.
```

#### [svp-brief] R3-005 · cross-slice · `.memory-bank/specs/svp-interview-upgrade/design.md:192-218; .memory-bank/specs/svp-brief/requirements.md:66-71,93-98; .memory-bank/specs/svp-brief/tasks.md:115-118,126-128`

**Проблема:** Owner-контракт secret-scan не определяет, какие типы сканируемы, хотя S7 обещает clean PDF.

**Доказательство:** S1 перечисляет reason `unsupported_type`, но не задаёт алгоритм классификации или extractor (`svp-interview-upgrade/design.md:192-218`). S7 позитивный сценарий публикует `PRD.pdf` после clean scan (`requirements.md:66-71`), а тесты проверяют только binary/unreadable (`tasks.md:115-118,126-128`). Реализатор должен угадать, является ли PDF scannable и как искать секреты внутри него.

**Рекомендация:** Владелец S1 должен зафиксировать inspectability contract; S7 затем выравнивает сценарии и тесты под него.

**Готовая правка:**

```
В S1-C5 добавить: «В MVP сканируемым считается readable regular file без NUL-байтов, строго декодируемый как UTF-8, независимо от suffix. NUL → `binary`; ошибка UTF-8 decode → `unsupported_type`; внешние extractors не вызываются. PDF и иные бинарные контейнеры в MVP дают `scan=unsupported`.» В S7 Scenario 1 и связанных тестах заменить `PRD.pdf` на `PRD.md`; в context/svp-brief.md удалить утверждение о сканируемом PDF. Добавить consumer-тесты для UTF-8 файла с неизвестным suffix, NUL-файла и non-UTF-8 файла.
```

#### [svp-brief] R3-006 · contract · `.memory-bank/specs/svp-brief/requirements.md:60-61; .memory-bank/specs/svp-brief/design.md:143-162,200-201; .memory-bank/specs/svp-brief/tasks.md:115-128`

**Проблема:** Не определён агрегированный исход при нескольких secret-scan результатах.

**Доказательство:** REQ-010 требует назвать «every unscannable source» (`requirements.md:61`), а C5 обещает сканировать каждый input (`design.md:143-146`). Таблица отображает только один scanner result (`:154-159`): нет порядка diagnostics и приоритета для набора clean + blocked + unsupported + usage. Тесты используют по одному проблемному источнику (`tasks.md:115-128`).

**Рекомендация:** Определить полный scan-all алгоритм, приоритет итогового reason и порядок stderr.

**Готовая правка:**

```
После таблицы C5 добавить: «C6 запускает scanner для всех inputs и буферизует результаты. Diagnostics выводятся в argv-порядке источников, внутри источника — в порядке scanner. Приоритет итогов: (1) любой usage result → stdout пуст, `error=scan_usage path=<p>` для каждого такого источника, exit 2; (2) иначе любой unsupported → `brief=blocked reason=scan_unsupported`, exit 1; (3) иначе любой blocked → `brief=blocked reason=secret`, exit 1; (4) иначе publish продолжается. При итогах 2/3 stderr содержит diagnostics всех non-clean источников, поэтому ни secret, ни unscannable source не скрывается.» Добавить тесты с двумя unsupported и со смешанными blocked+unsupported inputs.
```

#### [svp-brief] R3-007 · contract · `.memory-bank/specs/svp-brief/design.md:184-210; .memory-bank/specs/svp-brief/tasks.md:85-94`

**Проблема:** Правило `candidate=<path>` невозможно выполнить для части usage-ошибок.

**Доказательство:** Шаг 1 допускает отсутствие `--candidate` и невалидный candidate как usage error (`design.md:184-187`), но шаг 9 требует при «отказе на любом шаге» сохранить и назвать candidate (`:207-210`). При отсутствующем флаге пути нет; при несуществующем пути сохранять нечего. Не определён и порядок candidate-строки относительно scanner/validator diagnostics.

**Рекомендация:** Ограничить candidate-диагностику отказами после успешной проверки candidate и зафиксировать stderr order.

**Готовая правка:**

```
Заменить C6 шаг 9 на: «Ошибки usage/I-O шага 1 печатают только соответствующие `error=...` строки и не печатают `candidate=`. После того как candidate принят как readable regular file, любой отказ шагов 2–8 сохраняет его; после всех основных stderr diagnostics последней печатается ровно одна строка `candidate=<path>`. На success candidate удаляется после `mv`.» Синхронно уточнить Task 1 и добавить проверки отсутствующего, несуществующего и валидного-с-поздним-отказом candidate.
```

#### [svp-brief] R3-008 · eval · `.memory-bank/specs/svp-brief/design.md:42-61,180,233-249; .memory-bank/specs/svp-brief/tasks.md:95-164`

**Проблема:** Task 1 может стать green, даже если `/mb brief` игнорирует request-source контракт.

**Доказательство:** C0 подробно задаёт XOR `--request`/`--request-file`, empty и regular-file/path ошибки (`design.md:42-52`), а helper эти флаги намеренно не принимает (`:180`). Значит контракт должен обеспечить prompt-файл. Но список C7-клауз Task 1 проверяет вопросы, auto, candidate, publish, attachments и handoff (`tasks.md:148-164`) — ни одной проверки request XOR, empty request или request-file guard нет.

**Рекомендация:** Добавить load-bearing prompt clauses и негативные cases для всех request-source веток.

**Готовая правка:**

```
В Task 1/C7 добавить клаузы: `brief-request-source-xor` — одновременно `--request` и `--request-file` дают `error=usage`, а без флагов используется только текст после command invocation; `brief-request-inline-nonempty` — whitespace-only даёт `error=request_empty`; `brief-request-file-guard` — missing/symlink/directory/`..` даёт `error=request_unreadable`, whitespace-only file даёт `error=request_empty`, всё до записи candidate. Для каждой вызвать `assert_clause` и `assert_clause_load_bearing`, добавить соответствующие Bats-кейсы и semantic markers в Task 1 `output~`.
```

#### [svp-contract-test-loop] R2-001-PARTIAL · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:179-197`

**Проблема:** PARTIAL: R2-001 — реестр появился, но не определён исполнимый переход между proposal и написанием чекеров внутри одной задачи.

**Доказательство:** Lifecycle требует: исполнитель возвращает `MB_CONTRACT_CHECKERS_JSON` (`design.md:184-185`), оркестратор пишет реестр (`:186-188`), затем исполнитель пишет тесты и чекеры (`:189`), после чего оркестратор запускает red (`:190-191`). Однако proposal является частью финального отчёта перед `MB_WORK_RESULT_JSON` (`:193-197`). Текущий `/mb work` делает один implementer-dispatch на item (`commands/work.md:328-353`); второго dispatch/resume-протокола спека не задаёт.

**Рекомендация:** Зафиксировать двухфазное исполнение одной контрактной задачи и crash-safe resume.

**Готовая правка:**

```
Добавить в C3a:

`Contract task = один checkbox, но два implementer dispatch. Dispatch A (declare) не пишет product/checker files, возвращает MB_CONTRACT_CHECKERS_JSON перед штатным MB_WORK_RESULT_JSON и завершается. Оркестратор валидирует proposal, записывает fenced registry и фиксирует work-state step contract_declared. Dispatch B (build) получает замороженный registry, пишет только checker tests и checker implementations, затем завершается штатным envelope. После B оркестратор требует green unit tests checker-ов и запускает mb-contract-gate.sh red. При resume валидный registry + step contract_declared пропускают Dispatch A; отсутствие любого из них повторяет A. До успешного red-гейта business implementation dispatch запрещён.`
```

#### [svp-contract-test-loop] R2-004-PARTIAL · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:50-52,84-96; tasks.md:71-76`

**Проблема:** PARTIAL: R2-004 — typed API не может однозначно реализовать заявленный запрет `layers` в design.md/tasks.md.

**Доказательство:** C1 объявляет блок `layers` в design.md/tasks.md ошибкой (`design.md:50-52`), но API получает только `requirements_path` и `pipeline_path` (`:84-86`), а enum ошибок не содержит ошибки noncanonical owner (`:88-93`). При этом Task 2 требует `test_layers_block_outside_requirements_rejected` (`tasks.md:76`). Реализатор вынужден угадывать, надо ли неявно сканировать sibling-файлы и какой code/exit возвращать.

**Рекомендация:** Сделать sibling-проверку и её ошибку частью публичного контракта.

**Готовая правка:**

```
После сигнатуры C1 добавить:

`read_spec_layers MUST inspect requirements_path.parent / "design.md" and / "tasks.md" for a frontmatter key named layers. If found, it raises SpecLayersError("noncanonical_owner", "design.md:layers"|"tasks.md:layers") before resolving defaults. Missing sibling files are ignored. Add noncanonical_owner to the closed error-code enum. CLI behavior: stdout empty, stderr spec_layers_error=noncanonical_owner field=<file>:layers, exit 1.`
```

#### [svp-contract-test-loop] R2-010-PARTIAL · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:343-356; tasks.md:137-156`

**Проблема:** PARTIAL: R2-010 — renderer смешивает fragments двух файлов в одном stdout и при выключенных слоях теряет обязательный Quality DoD.

**Доказательство:** C8 печатает одним stdout и task-блок, и секцию `## Quality DoD` (`design.md:349-350`), после чего весь вывод вставляется в один `candidate` (`:354-355`); destination для design.md не определён. Одновременно все layers=false требуют пустой stdout (`:351-352`, `tasks.md:155`), хотя REQ-015 требует Quality DoD в каждой новой спеке (`requirements.md:66`). Task 4 даже одновременно требует empty-output и наличие Quality DoD (`tasks.md:155-156`).

**Рекомендация:** Вернуть два типизированных fragment в одном детерминированном envelope и всегда рендерить Quality DoD.

**Готовая правка:**

```
Заменить C8 output-контракт на:

`With --json, stdout is exactly {"tasks_markdown":"<string>","quality_dod_markdown":"<string>"}. commands/sdd.md inserts tasks_markdown only into tasks.candidate.md and quality_dod_markdown only into design.candidate.md before the S2 gates. When all three layers are false, tasks_markdown is empty but quality_dod_markdown remains non-empty. Unknown/missing JSON fields are exit 1.`

Заменить тест `test_all_layers_false_renders_empty` на два ассерта: `tasks_markdown == ""` и `quality_dod_markdown` содержит ровно одну секцию `## Quality DoD`.
```

#### [svp-contract-test-loop] R2-012-PARTIAL · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:231-282; agents/mb-reviewer.md:36-39,52-64`

**Проблема:** PARTIAL: R2-012 — Quality DoD доезжает до reviewer payload, но остаётся непотребляемой ссылкой без критериев или результата checker-а.

**Доказательство:** C5 содержит только пути к rule sources и команду checker-а (`design.md:236-254`). C6 передаёт этот блок reviewer-у (`:270-275`). Но orchestrated reviewer обязан считать payload самодостаточным и не открывать файлы (`agents/mb-reviewer.md:36-39,54-55`), а его prior evidence содержит только test status (`:62-64`). Значит project-specific rule source по пути и результат `mb-rules-check.sh` reviewer фактически не видит, хотя REQ-019 требует передать разрешённый Quality DoD через rubric channel.

**Рекомендация:** Сохранить ссылки вместо копии правил, но материализовать существующую rubric и deterministic checker evidence в payload до model dispatch.

**Готовая правка:**

```
Дополнить C5/C6:

`Canonical Quality DoD contains: (1) sorted rule-source references; (2) the existing pipeline.yaml:review_rubric rendered as canonical bullets; (3) the checker command. The static Quality DoD block is byte-identical for implementer/reviewer/judge. Before reviewer and judge dispatch, the orchestrator runs mb-rules-check.sh on the item's touched files once; non-zero blocks dispatch, and the canonical JSON result is appended to Prior evidence, outside the static Quality DoD block. The orchestrated reviewer never needs disk access.`

В T6 добавить проверки наличия rubric bullets и rules-check JSON evidence в reviewer/judge payload.
```

#### [svp-contract-test-loop] R3-002 · contract · `.memory-bank/specs/svp-contract-test-loop/design.md:162-176,199-218`

**Проблема:** Реестр чекеров не имеет однозначной parse/execute/path grammar для Bash 3.2 реализации.

**Доказательство:** Реестр объявлен произвольным YAML (`design.md:162-170`) с `cmd: <точная команда>` и псевдопутём `evidence: <bank>/...`. Раннер должен исполнять cmd «byte-identical» (`:206-207`), но не указано: каким parser-ом читать YAML без новой зависимости, как экранировать `:`, `#`, кавычки и многострочные команды, через shell или argv исполнять cmd, является ли `<bank>` literal token и как подставляется `<phase>`. Exit 2 за invalid registry (`:216`) поэтому не имеет полной проверяемой схемы.

**Рекомендация:** Использовать закрытую JSON-схему со stdlib parser, argv-выполнением и bank-relative evidence path.

**Готовая правка:**

```
Заменить fenced registry на:

```json Contract-checkers
{"checkers":[{"id":"slug","covers":["REQ-NNN"],"path":"repo/relative/checker","argv":["bash","tests/checker.sh"],"evidence":"tmp/contract-gate/<topic>/<id>.{phase}.json","output_ere":"<ERE>"}]}
```

`mb-contract-gate.sh parses this with Python stdlib json; unknown/missing keys are schema errors. argv is a non-empty array of strings and runs with shell=false from repo root; callers needing shell syntax use ["bash","-lc","..."] explicitly. evidence is bank-relative, must match tmp/contract-gate/<topic>/..., is joined under canonical --mb, and {phase} is replaced only with red|verify. Absolute paths, .., symlink escape, invalid ERE or path/argv type produce exit 2 before any checker runs.`
```

#### [svp-contract-test-loop] R3-003 · edge-case · `.memory-bank/specs/svp-contract-test-loop/requirements.md:44-45,55-58; design.md:220-229`

**Проблема:** Не определено допустимое состояние `integration_tests:false` + `e2e_tests:true`.

**Доказательство:** Каждый слой можно отключить отдельно (`requirements.md:55-58`). Но REQ-008 требует при e2e=true поставить e2e «after the integration-test task» (`requirements.md:45`), а C4 фиксирует порядок `implementation → integration → e2e` (`design.md:222-224`). Если integration-задача отключена, объекта, после которого надо поставить e2e, нет; validator matrix и тесты этой комбинации не содержат.

**Рекомендация:** Явно определить e2e-only порядок, не вводя зависимости между независимо отключаемыми слоями.

**Готовая правка:**

```
Заменить REQ-008 на:

`While a spec declares e2e_tests: true, the system shall generate one dedicated e2e-test task after all implementation tasks and, when an integration task exists, after that integration task.`

В C4 добавить matrix-row `integration=false, e2e=true → implementation → e2e`, а в T3 Testing — `spec_validate_e2e_without_integration_ok` и отрицательный кейс e2e перед implementation.
```

#### [svp-docs-wiki] F-008 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:289-319; .memory-bank/specs/svp-docs-wiki/tasks.md:108-123`

**Проблема:** PARTIAL: F-008 — schema названа writer-ready, но всё ещё не совпадает с writer API и не содержит данных для `index.md`.

**Доказательство:** Design утверждает, что объект страницы совпадает с writer API «байт-в-байт» (`design.md:289-292`) и включает `title`, `source_files`, `wikilinks` (`:297-309`). Фактический контракт T3 задаёт `write_page(slug, body)` (`tasks.md:109-114`): `title` и `wikilinks` не потребляются. Кроме того, `index.md` требует `Title` и `one-line` (`design.md:154-155`), но schema вообще не содержит однострочного summary и не определяет алгоритм его извлечения.

**Рекомендация:** Сделать page-schema и writer API действительно идентичными и определить источник index summary.

**Готовая правка:**

```
В C6 заменить page schema на `{slug,title,summary,body_markdown,source_files,wikilinks}`, где `summary` — непустая строка 1–200 символов без CR/LF, а `body_markdown` — тело ниже H1. В C4/T3 задать `write_page(page)` как единственный API: он рендерит `# <title>`, затем `<summary>`, затем body; сохраняет `source_files` для state и сверяет `wikilinks` со ссылками в body. `regenerate_index()` читает H1 и первую summary-строку каждой страницы. Обновить C6 exact-schema и T3/T5 tests этим перечнем ключей.
```

#### [svp-docs-wiki] F-010 · contract · `.memory-bank/specs/svp-docs-wiki/design.md:234-247,399-428`

**Проблема:** PARTIAL: F-010 — manifest сделал leakage наблюдаемым, но его собственный жизненный цикл внутренне противоречив.

**Доказательство:** Manifest объявляет `writes` как каждый фактически записанный прогоном путь (`design.md:416`), однако сам manifest записывается во временный путь до lint (`:407-414`), а разрешённое множество не включает этот temp-файл (`:418-420`). State также включён в allowlist, но фактически пишется только после lint (`:244-247`), поэтому на момент проверки не может честно входить в список уже выполненных writes. Имплементер вынужден либо скрыть реальные control-writes, либо получить ложный `source_leakage`.

**Рекомендация:** Разделить durable wiki writes, control writes и заранее подготовленную финализацию state.

**Готовая правка:**

```
Заменить manifest на `{run_id,durable_writes_completed:[pages/log/index],control_writes:[lock,manifest,state_temp],pending_state_path,sources}`. Lint отдельно проверяет: durable paths находятся под docs_path; control paths принадлежат точным разрешённым шаблонам; pending_state_path равен `<docs-path>/.mb-docs-state.json`; source hashes неизменны. Apply до lint создаёт state temp под docs_path, а после зелёного lint разрешён только один `os.replace(state_temp,pending_state_path)` и release lock. Добавить T7/T4 тест, что manifest и state-temp не дают ложный leakage, но любой иной control-write даёт `source_leakage`.
```

#### [svp-docs-wiki] R3-003 · cross-slice · `.memory-bank/specs/svp-docs-wiki/requirements.md:6; .memory-bank/specs/svp-docs-wiki/tasks.md:146-170; .memory-bank/specs/svp-roadmap-backlog-db/tasks.md:57-70`

**Проблема:** Потребление lock-контракта S4 не отражено в DAG, а fallback требует out-of-Scope правку.

**Доказательство:** S4 Task 2 владеет `scripts/_lib.sh` и создаёт `mb_lock_acquire/mb_lock_release` (`svp-roadmap-backlog-db/tasks.md:57-70`). S6 T4 вызывает эти функции и при их отсутствии требует реализовать их (`svp-docs-wiki/tasks.md:167-170`), но Scope T4 не включает `scripts/_lib.sh` (`:150`), а blocked_by содержит только локальные задачи (`:149`). Frontmatter всей S6 блокируется только S2 (`requirements.md:6`). При DAG-исполнении S6 может стартовать до завершения S4; fallback немедленно нарушит Scope-контракт S2-C1.

**Рекомендация:** Сделать зависимость от владельца lock-контракта жёсткой и удалить дублирующий fallback.

**Готовая правка:**

```
В requirements.md записать `blocked_by: [svp-sdd-core, svp-roadmap-backlog-db]`. В T4 записать `**Blocked-by:** 1, 2, 3, 5, 6, 7, svp-roadmap-backlog-db#2`. Удалить фразу `если helper ещё не отгружен — реализовать...`; заменить на `отсутствие mb_lock_acquire/mb_lock_release после закрытого svp-roadmap-backlog-db#2 — contract violation, работа T4 не начинается`. Синхронно добавить ребро S4→S6 в umbrella design/tasks.
```

#### [svp-docs-wiki] R3-004 · parent-decision · `.memory-bank/context/sdd-vision-pipeline.md:40-41; .memory-bank/specs/svp-docs-wiki/requirements.md:44; .memory-bank/specs/svp-docs-wiki/design.md:34-48; .memory-bank/specs/svp-docs-wiki/tasks.md:186-188,229-251`

**Проблема:** REQ-004 остаётся LLM/reviewer-only вопреки D-05/D-06.

**Доказательство:** Parent D-05 требует кодовый red→green для gated требований (`context/sdd-vision-pipeline.md:40-41`). REQ-004 — SHALL (`requirements.md:44`), но design прямо оставляет формулировку противоречия prompt/reviewer-слою (`design.md:45-46`). T4 получает уже готовый `body_markdown` с `## Contradictions` и проверяет лишь сохранение (`tasks.md:186-188`); T5 проверяет текст prompt-файлов (`:246-251`). Ни один Eval не получает старый claim + новый source fact и не доказывает, что система сформировала структурно проверяемый contradiction result.

**Рекомендация:** Отделить семантическое обнаружение от кодово проверяемого контракта результата.

**Готовая правка:**

```
Заменить REQ-004 на кодово наблюдаемую формулировку: `When the synthesizer reports a contradiction between an existing claim and new evidence, the system shall validate a structured contradiction record and render it explicitly on the affected page instead of silently overwriting the claim.` В C6 добавить `contradictions:[{slug,old_claim,new_claim,old_evidence,new_evidence}]`; apply валидирует пути evidence и детерминированно рендерит `## Contradictions`. Модельное качество обнаружения записать отдельным non-gated SHOULD/Quality DoD. T4 Eval должен подать contradiction record и проверить рендер; malformed/missing evidence → exit 5 без записей.
```

#### [svp-docs-wiki] R3-005 · eval · `.memory-bank/specs/svp-docs-wiki/requirements.md:43,113-120; .memory-bank/specs/svp-docs-wiki/tasks.md:129-137,181-213,315-345`

**Проблема:** REQ-003 покрыт метаданными, но положительное требование cross-page wikilinks не проверяется кодом.

**Доказательство:** REQ-003 требует, чтобы страницы cross-reference друг друга (`requirements.md:43`), а Scenario 6 ожидает связанные страницы (`:113-120`). T3 проверяет сохранение contradictions/deprecation, но не наличие wikilink (`tasks.md:129-137`); T4 не перечисляет Scenario 6 среди тестов (`:181-213`); T7 ловит только битую ссылку, если она уже существует (`:315-345`). Wiki без единой ссылки пройдёт все заявленные Eval.

**Рекомендация:** Добавить детерминированный положительный lint и сквозной тест Scenario 6.

**Готовая правка:**

```
В C8/T7 добавить код `missing_cross_reference`: если в wiki больше одной non-deprecated page и нет ни одной разрешающейся ссылки `[[other-slug]]` между разными страницами, lint печатает `error=missing_cross_reference` и exit 1. Добавить T4 Covers `REQ-003, REQ-009` и production-CLI тест Scenario 6: две страницы с взаимными wikilinks сохраняются, lint green, хеши graph/wiki/source неизменны.
```

#### [svp-docs-wiki] R3-006 · consistency · `.memory-bank/specs/svp-docs-wiki/requirements.md:68-75; .memory-bank/specs/svp-docs-wiki/design.md:156-166`

**Проблема:** Scenario 1 задаёт log-строку, которая нарушает нормативную грамматику C4.

**Доказательство:** Scenario 1 ожидает `## [2026-07-17] ingest | 14 files, 3 pages updated` (`requirements.md:72-75`). C4 требует обязательный `run=<run_id>` сразу после `|` (`design.md:156-166`), а lint обязан отклонять запись без него. Материализация Scenario 1 буквально создаст тест, конфликтующий с T3/T7.

**Рекомендация:** Синхронизировать GWT-пример с единственной грамматикой C4.

**Готовая правка:**

```
В Scenario 1 заменить THEN на: `log.md получил строку ## [2026-07-17] ingest | run=abc123..<target-40-hex> 14 files, 3 pages updated`; стейт указывает на тот же `<target-40-hex>`. В Scenario 2 также явно потребовать bootstrap-строку `## [<date>] bootstrap | run=bootstrap..<target-40-hex> <description>`.
```

#### [svp-docs-wiki] R3-007 · edge-case · `.memory-bank/specs/svp-docs-wiki/design.md:163-166,274-286,302-319`

**Проблема:** Свободный многострочный `log_entry.description` может навсегда сломать replay одного run_id.

**Доказательство:** C4 называет description свободным текстом (`design.md:163-166`), а C6 ограничивает его только типом string (`:302-319`). Если LLM вернёт CR/LF или строку, начинающуюся `## [`, log записывается, lint падает, state не продвигается. При повторе `log_append` видит тот же run_id и делает no-op (`:274-286`), поэтому исправленный результат агента уже не способен починить invalid log entry.

**Рекомендация:** Валидировать log_entry полностью до первой записи.

**Готовая правка:**

```
В C6/C5.2 добавить: `log_entry.description` — непустая single-line строка без CR/LF, `run=`, NUL и префикса `## [`; `op` — только `ingest|bootstrap`. Нарушение относится к `invalid_agent_result`, exit 5, и происходит на шаге validation до pages/log writes. Добавить T4 test: multiline description → zero writes; повтор с валидным description затем проходит.
```

#### [svp-docs-wiki] R3-008 · edge-case · `.memory-bank/specs/svp-docs-wiki/design.md:104-106,191-193,297-310`

**Проблема:** Пустой `source_files` вакуозно депрекейтит страницу.

**Доказательство:** Page-schema разрешает `source_files: []`, потому что cardinality не задана (`design.md:297-310`). Deprecation определяется условием «каждый файл source_files присутствует в deleted_files» (`:191-193`). Для пустого массива обычная реализация через `all()` истинна, поэтому страница без provenance будет помечена deprecated даже при пустом deleted_files.

**Рекомендация:** Задать cardinality и явную ветку легаси-пустого provenance.

**Готовая правка:**

```
В C2/C6 записать: для новой или обновлённой non-deprecated страницы `source_files` — непустой уникальный массив repo-relative путей; пустой массив в agent result → `invalid_agent_result`, exit 5. Для легаси-state с пустым массивом deprecate-гард обязан вернуть false и добавить `degraded_sources:["page_provenance:<slug>"]`; страница сохраняется активной. В T2/T4 добавить оба теста.
```

#### [svp-interview-upgrade] R3-002 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:64; .memory-bank/specs/svp-interview-upgrade/tasks.md:104`

**Проблема:** Формула порога near при пользовательском --spec-budget не определена.

**Доказательство:** C1 фиксирует near как 900000…1000000 и одновременно называет `--spec-budget` эффективным переопределяемым порогом (`design.md:64-69`). Task 3 требует, чтобы custom budget «сдвигает пороги» (`tasks.md:104`), но не задаёт, как вычисляется нижняя граница near. При `--spec-budget 500000` реализация может оставить 900000, применить 90%, вычесть 100000 или выбрать другую формулу.

**Рекомендация:** Зафиксировать одну целочисленную формулу и её boundary cases.

**Готовая правка:**

```
Заменить раздел C1 «Пороги» на:
- `spec_budget` — положительное целое, default `1000000`; иное значение → usage error, exit 2.
- `near_lower = floor(spec_budget * 9 / 10)`.
- `total < near_lower` → `estimate=ok`; `near_lower <= total <= spec_budget` → `estimate=near`; `total > spec_budget` → `estimate=over`.

В T3 добавить параметризованные cases для `--spec-budget 500000`: 449999→ok, 450000→near, 500000→near, 500001→over; 0, отрицательное и нецелое значение→exit 2.
```

#### [svp-interview-upgrade] R3-003 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:61; .memory-bank/specs/svp-interview-upgrade/design.md:66; .memory-bank/specs/svp-interview-upgrade/design.md:268; .memory-bank/specs/svp-interview-upgrade/design.md:286`

**Проблема:** Error-контракты C1 и C8 не задают детерминированный stderr для usage/read/malformed и порядок ошибок на одной строке.

**Доказательство:** C1 говорит лишь, что stderr «называет файл и конкретное поле» (`design.md:61-63`), а usage error объединён с missing/malformed по exit 2 без формата (`design.md:66-69`). C8 задаёт stderr только для validation problems, тогда как usage/read error имеет лишь exit 2 (`design.md:286-290`). Сортировка определена только по line; порядок нескольких reason-кодов на одной строке отсутствует. Автор реализации и автор тестов вынуждены независимо придумать протокол.

**Рекомендация:** Дополнить оба CLI точным форматом usage/read/malformed и полным ключом сортировки.

**Готовая правка:**

```
Добавить в C1:
- usage: stdout пуст; stderr ровно `error=usage`; exit 2.
- unreadable input: stdout пуст; stderr ровно `<file>:0:unreadable`; exit 2.
- missing estimate: stdout `estimate=missing spec.total=0 spec_budget=<N>`; stderr `<file>:0:estimated_tokens:missing`; exit 2.
- malformed field: stdout `estimate=malformed spec.total=<N|0> spec_budget=<N>`; stderr `<file>:<line>:<field>:malformed`; exit 2.

Добавить в C8:
- usage: stdout пуст; stderr `error=usage`; exit 2.
- unreadable input: stdout пуст; stderr `<file>:0:unreadable`; exit 2.
- validation findings сортируются по `(line, reason-order)`, где `reason-order` равен порядку reason-кодов в декларации режима.
```

#### [svp-interview-upgrade] SVP-IU-002 · eval · `.memory-bank/specs/svp-interview-upgrade/design.md:369; .memory-bank/specs/svp-interview-upgrade/tasks.md:31; .memory-bank/specs/svp-interview-upgrade/tasks.md:125; .memory-bank/specs/svp-interview-upgrade/tasks.md:158`

**Проблема:** PARTIAL: prompt-harness стал load-bearing, но файловые эффекты T1/T4/T5 всё ещё не проверяются ответственным детерминированным writer-helper.

**Доказательство:** Design сам требует: «REQ с файловыми эффектами ОБЯЗАН дополнительно вызывать ответственный детерминированный helper» (`design.md:376-378`). Однако T1 проверяет только C8 над уже созданным plan (`tasks.md:37,43-44`); T4 описывает atomic mv в prompt, хотя C5 принимает только policy и input-файл и не знает target (`design.md:175-223`, `tasks.md:125-138`); T5 оставляет ленивое создание glossary обязанностью prompt-слоя, а mb-context.sh остаётся read-only (`design.md:341-355`, `tasks.md:158-168`). Проверка «target не изменён» в тесте самого scanner не доказывает production orchestration.

**Рекомендация:** Вынести объективные записи в CLI helpers и проверять их на fixture-bank; C9 оставить только для агентных решений, которые невозможно исполнить детерминированно.

**Готовая правка:**

```
Добавить в design.md:

### C11. `scripts/mb-interview-artifact-write.sh <install-plan|publish-transcript> --mb <bank> --topic <topic> --candidate <file> [--require-inherited]`
- `install-plan` вызывает C8 `plan`, затем атомарно заменяет `<bank>/tmp/interview-plan-<topic>.md`.
- `publish-transcript` вызывает C5 `--policy transcript` и C8 `transcript`, затем атомарно заменяет `<bank>/context/<topic>-interview.md`.
- Любой failed scan/check оставляет target byte-identical.
- stdout: `artifact_write=installed kind=plan|transcript`; exit 0 — installed, 1 — content rejected, 2 — usage/I/O; при exit 1/2 stdout пуст.

### C12. `scripts/mb-glossary.sh upsert --mb <bank> --term-file <file> --definition-file <file>`
- Атомарно создаёт/обновляет одну строку `термин — определение`.
- Другая definition существующего term возвращает stdout `glossary=conflict`, exit 1 и не меняет файл; create/update/unchanged возвращают соответствующий status и exit 0; usage/I/O — exit 2.

Добавить C11 в Scope и fixture-tests T1/T4, C12 — в Scope и fixture-tests T5. В Eval T1/T4/T5 требовать проверку реального target до/после вызова helper.
```

#### [svp-interview-upgrade] SVP-IU-005 · contract · `.memory-bank/specs/svp-interview-upgrade/design.md:132; .memory-bank/specs/svp-interview-upgrade/design.md:136; .memory-bank/specs/svp-interview-upgrade/design.md:142; .memory-bank/specs/svp-interview-upgrade/tasks.md:137`

**Проблема:** PARTIAL: C4 получил маркеры и reason-коды, но answer и rejected-alternatives всё ещё определяются неоднозначно и слабее REQ-005.

**Доказательство:** Ответом считается любая цитата `«…»` где угодно внутри Q-блока (`design.md:136-139`), включая цитату в самом вопросе или отклонённой альтернативе; такой блок пройдёт без ответа. Для rejected alternatives достаточно одного inline-маркера или одной секции на весь файл (`design.md:142-146`), поэтому остальные решения могут потерять отклонённые варианты. T4 содержит только глобальную негативную фикстуру «файл без inline rejected или section» (`tasks.md:137`). Design прямо оставляет связь альтернатив с решением ручному review, несмотря на заявленный детерминированный C8.

**Рекомендация:** Для новых transcript ввести строгую per-Q грамматику, сохранив исторические транскрипты отдельным явно ограниченным legacy-режимом.

**Готовая правка:**

```
В C4 заменить правила 5 и 7 на:
5. **Ответ в Q-блоке**: требуется `**A<N>.** <text>` с тем же N. В `--legacy-live-fixture` также допустима строка того же блока, совпадающая с `Ответ голосом \(суть\): «[^»]+»` или `пользователь: «[^»]+»`; произвольная цитата ответом не считается.
7. **Отклонённые альтернативы**: каждый новый Q-блок с decision обязан содержать строку `Отклонено: none|<text>` либо `Rejected: none|<text>` до следующего Q/гейта. Отсутствие даёт `<file>:<line>:rejected_alternatives_missing`.

Добавить в C8:
- `--legacy-live-fixture` разрешён только для двух зафиксированных regression fixtures `context/sdd-vision-pipeline-interview.md` и `context/svp-interview-upgrade-interview.md`; для других путей — usage error `legacy_fixture_forbidden`, exit 2.

В T4 добавить негативные фикстуры: цитата только в вопросе → `answer_missing`; один из двух Q-блоков без `Отклонено:` → `rejected_alternatives_missing`.
```

#### [svp-parallel-engine] R2-002 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:181-213; .memory-bank/specs/svp-parallel-engine/tasks.md:363-393`

**Проблема:** PARTIAL: R2-002 — контракт precedence упоминает interactive answer, но интерфейс не позволяет его передать.

**Доказательство:** C4 задаёт precedence `CLI → state → interactive answer → config default` и источник `answer` (`design.md:195-205`), однако сигнатура содержит только итоговые `--execution`, `--intervention` и `--default-*` (`design.md:184-191`). Отдельных аргументов для ответов пользователя нет. Task 8 проверяет precedence, но также не задаёт способ представить answer (`tasks.md:379-393`).

**Рекомендация:** Добавить отдельные аргументы для ответов AskUserQuestion и формально определить их валидацию.

**Готовая правка:**

```
Сигнатуру C4 заменить на: `mb-work-mode-resolve.sh [--execution sequential|parallel] [--intervention hitl|autonomous] [--state-file <path>] [--answer-execution sequential|parallel] [--answer-intervention hitl|autonomous] [--default-execution sequential|parallel] [--default-intervention hitl|autonomous]`. `--answer-*` представляют только ответы текущего интерактивного запроса; пара должна присутствовать целиком либо отсутствовать, иначе exit 2. Precedence применяется независимо к каждой оси: explicit CLI → сохранённый state → соответствующий `--answer-*` → `--default-*`. В Task 8 добавить тесты answer-over-default, state-over-answer, CLI-over-state и неполной answer-пары.
```

#### [svp-parallel-engine] R2-003 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:159-179,248-264,321-324; .memory-bank/specs/svp-parallel-engine/requirements.md:200-207; .memory-bank/specs/svp-adapt-escalation/design.md:194-205,557-560; .memory-bank/specs/svp-adapt-escalation/tasks.md:45-52`

**Проблема:** PARTIAL: R2-003 — collector появился, но передача `unavailable` в scope-check не определена и противоречит текущему контракту владельца S5.

**Доказательство:** C6 при невозможности получить diff печатает status JSON и exit 3 (`svp-parallel-engine/design.md:258-263`), тогда как C3 принимает только `--diff-file` со списком путей (`design.md:162-177`); способ передать unavailable отсутствует. C3 и Scenario 15 требуют escalation для unavailable (`requirements.md:200-207`). При этом текущий S5-C1 запускает ADaPT только для `scope_status == violation` (`svp-adapt-escalation/design.md:194-205`), а unavailable переводит в `degraded_guards` без trigger (`design.md:557-560`; `tasks.md:45-52`). Утверждение S3, что S5 обрабатывает unavailable (`svp-parallel-engine/design.md:321-324`), неверно относительно владельца контракта.

**Рекомендация:** Зафиксировать C6→C3 handoff и выполнять обязательную unavailable-escalation непосредственно в S3, не меняя контракт владельца S5.

**Готовая правка:**

```
Расширить C3: `mb-work-scope-check.sh --allowed-file <path> [--diff-file <path>] --collector-status ok|unavailable [--collector-reason <string>]`. При `ok` обязателен `--diff-file`; при `unavailable` он запрещён, output равен `{"task_id":"<id>","scope_status":"unavailable","outside":[],"reason":"<collector-reason>"}`, exit 3. В C7 указать: C6 exit 0 сохраняет stdout в diff-file и вызывает C3 с `--collector-status ok`; C6 exit 3 вызывает C3 с `--collector-status unavailable`, затем scheduler напрямую выдаёт единственный `escalate` action с `reason:"scope_unavailable"` и не вызывает S5. Только `scope_status:"violation"` передаётся в S5-C1.
```

#### [svp-parallel-engine] R2-004 · cross-slice · `.memory-bank/specs/svp-parallel-engine/design.md:226-245; .memory-bank/specs/svp-parallel-engine/tasks.md:242-250; .memory-bank/specs/svp-roadmap-backlog-db/design.md:118-144,600-609`

**Проблема:** PARTIAL: R2-004 — roadmap-файл больше не парсится локально, но S3 всё ещё меняет семантику обязательного S4-C2 comparator.

**Доказательство:** S4 требует от S3 использовать полный comparator и общую fixture-таблицу, включая missing ice и invalid ice (`svp-roadmap-backlog-db/design.md:600-609`). В контракте владельца missing/invalid ice переводится в legacy tail; invalid ice не активирует priority, но не делает comparator недоступным (`design.md:118-144`). S3 вместо этого требует exit 2 при отсутствии ice и exit 3 при malformed ice (`svp-parallel-engine/design.md:238-244`; `tasks.md:247-250`). Это нарушает правило «потребитель выравнивается под текущий текст владельца».

**Рекомендация:** Удалить локальную fail-fast семантику ice и использовать результаты S4-C2 byte-for-byte.

**Готовая правка:**

```
В C5 заменить degradation-блок на: «S3 вызывает S4-C2 comparator без переинтерпретации его полей. Missing `**ICE:**` и malformed ICE являются legacy-tail случаями согласно S4-C2 и не меняют exit code. Exit 2 используется только когда сам S4-C2 helper отсутствует или недоступен; exit 3 — только при невалидном JSON/нарушении схемы результата helper. Fixtures и ожидаемый порядок копируются byte-for-byte из S4-C2». В Task 5 заменить ожидания `missing ice → exit 2` и `invalid ice → exit 3` на ожидаемый legacy-tail порядок из общей S4 fixture-таблицы.
```

#### [svp-parallel-engine] SVP-PE-004 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:109-126,147-154; .memory-bank/specs/svp-parallel-engine/tasks.md:73-83`

**Проблема:** PARTIAL: SVP-PE-004 — контракт чтения claims всё ещё противоречив, а fallback-изменение `_lib.sh` отсутствует в Scope задачи.

**Доказательство:** C2 требует: «partial tail … reread under lock» (`design.md:124-126`), но ниже утверждает: «list … lock not taken» (`design.md:147-148`). Task 2 ограничивает Scope файлами claims-скрипта и его теста (`tasks.md:73-74`), хотя DoD требует при отсутствии S4-C6 реализовать совместимый helper в `scripts/_lib.sh` (`tasks.md:82-83`). Реализатор вынужден угадывать, берёт ли `list` lock, и не может легально выполнить fallback в заявленном Scope.

**Рекомендация:** Зафиксировать единый алгоритм восстановления partial tail и разрешить условную правку `_lib.sh` в Scope Task 2.

**Готовая правка:**

```
В C2 заменить оба конфликтующих фрагмента на: «`list` сначала читает snapshot без lock. Если только последняя непустая строка является partial JSONL tail, команда вызывает S4-C6 `mb_lock_acquire` с теми же timeout/stale-параметрами, перечитывает весь файл ровно один раз под lock и освобождает lock. Если tail остаётся partial либо повреждена не последняя строка, команда печатает диагностический JSON в stderr и завершает работу с exit 2. Обычный успешный `list` lock не берёт». В Task 2 Scope добавить: «`scripts/_lib.sh` — conditional: только если S4-C6 helper ещё отсутствует на момент исполнения».
```

#### [svp-parallel-engine] SVP-PE-008 · feasibility · `.memory-bank/specs/svp-parallel-engine/design.md:295-317; .memory-bank/specs/svp-parallel-engine/tasks.md:452-485; scripts/mb-subinvoke-resolve.sh:26-38,178-193,294-302; adapters/opencode.sh:626-635`

**Проблема:** PARTIAL: SVP-PE-008 — full mode восстановлен в требованиях, но заявленный role-scoped маршрут Pi/OpenCode фактически не существует.

**Доказательство:** C8 требует для обоих hosts вызов `mb-subinvoke-resolve.sh --agent <host> --role <role>` (`design.md:303-307`). Текущий resolver прямо документирует, что `--role` применяется только к Pi и игнорируется другими hosts (`scripts/mb-subinvoke-resolve.sh:26-38`); OpenCode всегда получает обычный `opencode run` без agent selection (`scripts/mb-subinvoke-resolve.sh:294-302`). Pi ищет `agents/$ROLE.md` (`scripts/mb-subinvoke-resolve.sh:178-193`), тогда как WorkItem выдаёт semantic role `backend`, а существует `agents/mb-backend.md`, не `agents/backend.md`. Task 10 не включает resolver в Scope, поэтому не может исправить маршрут. `adapters/opencode.sh:626-635` также фиксирует отсутствие role-routing.

**Рекомендация:** Передавать одновременно semantic role и конкретное имя агента из WorkItem, а Task 10 должна расширить resolver и определить полный runtime-контракт dispatch.

**Готовая правка:**

```
В C7 добавить в `dispatch` action поля `role:"backend"` и `agent:"mb-backend"`. Сигнатуру C8 заменить на `mb-work-dispatch.sh --host claude|pi|opencode --role <semantic-role> --agent-name <mb-agent> --prompt-file <path> [--probe]`. Для Pi resolver вызывается с `--role "$agent_name"`. Для OpenCode расширить ветку resolver так, чтобы она возвращала `opencode run --agent "$agent_name" …`; отсутствие этой возможности даёт `status:"unavailable"`, exit 1, без unscoped fallback. Обычный dispatch должен вернуть JSON `{"host":"<host>","agent":"<agent>","status":"ok|failed|delegate_native","exit_code":<int>,"report":"<string>"}`; exit 0 означает успешный child/delegate descriptor, exit 3 — child failure. В Task 10 Scope добавить `scripts/mb-subinvoke-resolve.sh` и его существующие resolver-тесты; добавить проверки, что Pi использует `agents/mb-backend.md`, а OpenCode-команда содержит `--agent mb-backend`.
```

#### [svp-parallel-engine] SVP-PE-009 · contract · `.memory-bank/specs/svp-parallel-engine/design.md:128-145,266-293; .memory-bank/specs/svp-parallel-engine/tasks.md:414-441`

**Проблема:** PARTIAL: SVP-PE-009 — scheduler добавлен, но его state machine, action schemas и claim handoff остаются неполными.

**Доказательство:** C7 требует action `dispatch … claim_token` (`design.md:277-279`), но C2 mutation-result не содержит `claim_token` (`design.md:128-145`). `complete|fail` принимает `--report-json -` без схемы (`design.md:272-273`). Для `wait`, `judge`, `escalate` и `done` не определены обязательные поля и допустимые reason; mixed actions лишь сортируются по `(kind, task_id)` (`design.md:281-285`), поэтому неясны терминальность и приоритет. Путь state указан, но формат state-файла и атомарность записи не заданы.

**Рекомендация:** Определить полный машинно-проверяемый JSON-контракт состояния, результатов claims, командных отчётов и каждого action.

**Готовая правка:**

```
В C2 добавить к mutation-result поле `claim_token`, равное `session_id` при успешном `claim` и `null` во всех остальных статусах. В C7 определить state: `{"run_id":"<uuid>","source":"plan|spec|group","execution":"sequential|parallel","intervention":"hitl|autonomous","max_agents":<int>,"tasks":{"<task_id>":{"status":"pending|claimed|running|awaiting_judge|done|failed|escalated","role":"<role>","agent":"<agent>","prompt_file":"<path>","claim_token":"<token|null>"}},"active_judge":"<task_id|null>","problems":[]}`; запись только orchestrator через temp-file + atomic rename. Определить actions: `dispatch {kind,task_id,role,agent,prompt_file,claim_token}`; `wait {kind,task_id:null,reason:"slots_full|blocked|awaiting_ack",blocked_by:[...]}`; `judge {kind,task_id}`; `escalate {kind,task_id,reason:"scope_violation|scope_unavailable|dispatch_failed|task_failed"}`; `done {kind,task_id:null}`. `wait|judge|escalate|done` выдаются по одному; batch может содержать только `dispatch`. Для `complete` stdin: `{"dispatch_exit":0,"report":"<string>"}`; для `fail`: `{"dispatch_exit":<nonzero-int>,"reason":"<nonempty-string>","report":"<string>"}`.
```

#### [svp-roadmap-backlog-db] R3-001 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:405`

**Проблема:** Lock-helper и allocator не имеют полного stdout/exit-контракта и границ критической секции

**Доказательство:** C6 объявляет `mb_lock_acquire <lock_dir> <timeout> <ttl>` и release с обязательным token (`design.md:405-410`), но не говорит, как acquire возвращает token и какие exit-коды имеют обе функции. Для `mb_next_backlog_id` описан алгоритм, но не определено, возвращает он `076` или `I-076` (`design.md:484-505`). Одновременно lock требуется только «до аллокации/мутации» (`design.md:507-510`), хотя idempotency и similarity читают backlog раньше (`design.md:270-297`), что допускает TOCTOU и две записи одного title. Прецедент `_lock_acquire` фактически возвращает token через stdout (`scripts/mb-agree.sh:117-125`), но реализатор не должен восстанавливать публичный контракт по чужому private-коду.

**Рекомендация:** Зафиксировать I/O helper-функций и обязать writers держать lock на всём read-decide-write пути.

**Готовая правка:**

```
Добавить в C6: `mb_lock_acquire <lock_dir> <timeout> <ttl> prints exactly <PID>-<RANDOM> plus newline to stdout and exits 0 on acquisition; on timeout it prints code=lock_timeout lock=<JSON-string> to stderr, leaves stdout empty and returns 1. mb_lock_release <lock_dir> <token> leaves stdout empty; it returns 0 only after releasing the matching owner or when the lock is already absent, and returns 1 on owner mismatch without deleting anything. mb_next_backlog_id <bank> prints exactly I-NNN plus newline and exits 0; every fatal scan/overflow error leaves stdout empty and exits 1.` Затем добавить: `mb-idea.sh acquires backlog.lock before title-idempotency lookup and similarity lookup, rechecks both under the lock, calls the allocator and holds the lock through rename. mb-backlog-migrate.sh --apply acquires the lock before reading the source or creating its backup and holds it through backup+rename.` В T9 добавить конкурентный тест: два одинаковых title дают один блок и один общий ID.
```

#### [svp-roadmap-backlog-db] R3-002 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:213`

**Проблема:** Общий transition-примитив нельзя однозначно реализовать или безопасно переиспользовать в promote

**Доказательство:** C3 требует одну общую функцию, которая валидирует переход и атомарно переписывает статус (`design.md:213-225`), но не задаёт её имя, файл, аргументы, lock ownership или результат. C7 одновременно требует, чтобы promote уже держал lock и записал статус вместе с `**Plan:**` одной atomic-записью (`design.md:525-529`). Примитив, который сам берёт lock или сразу пишет только статус, соответственно дедлочит promote либо нарушает его atomic-write контракт.

**Рекомендация:** Определить один locked transform API, поддерживающий добавление Plan в ту же запись.

**Готовая правка:**

```
Добавить в C3: `scripts/_lib.sh exports mb_backlog_transition_locked <backlog_path> <I-NNN> <NEW_STATE> [--reason TEXT] [--plan REL]. Precondition: caller already owns <bank>/.locks/backlog.lock; the function never acquires or releases it. It validates the C3 edge and READY/WONTFIX gates, renders the status plus optional Reason/Plan change into one temp file, then performs one mv. It leaves stdout empty and returns 0 success, 1 domain rejection, 2 malformed/not-found. mb-backlog-state.sh owns lock acquisition and prints the public success line after return 0; mb-idea-promote.sh calls the same function with --plan while holding the existing lock.` Отразить имя и precondition дословно в Task 2 и Task 9.
```

#### [svp-roadmap-backlog-db] R3-003 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:381`

**Проблема:** Lint-матрица не покрывает поля, которые REQ-004 обещает валидировать, и не имеет кода для WONTFIX без Reason

**Доказательство:** REQ-004 прямо требует проверять confirmation marker, pin и group (`requirements.md:56`), C1 задаёт `ice_confirmed: true|false`, positive pin и slug (`design.md:51-60`), а C5 содержит только `ice_unconfirmed`, `duplicate_pin` и `orphan_group`; malformed marker/pin/group/blocked_by не имеют результата (`design.md:381-403`). Кроме того, C4 утверждает, что требование Reason применяется к v2 WONTFIX и лишь legacy grandfathered (`design.md:325-331`), но среди 10 lint-кодов нет `wontfix_without_reason`. Task 4 одновременно упоминает это требование без исполняемого кода (`tasks.md:255-267`).

**Рекомендация:** Дополнить C5 исчерпывающими кодами и отдельными тест-кейсами.

**Готовая правка:**

```
Заменить `Коды (10)` на `Коды (15)` и добавить error-строки: `invalid_ice_confirmed — поле присутствует и не равно literal true|false`; `invalid_pin — поле присутствует и не является base-10 integer >0`; `invalid_group — поле присутствует и не соответствует [a-z0-9][a-z0-9-]*`; `invalid_blocked_by — поле присутствует и не является flow-list уникальных slug по той же грамматике`; `wontfix_without_reason — v2 WONTFIX не содержит непустой **Reason:**`. Обновить Task 4 What to do/Testing/DoD с 10 на 15 и потребовать отдельную отрицательную фикстуру для каждого нового кода; legacy grandfathered WONTFIX должен оставаться без этой ошибки.
```

#### [svp-roadmap-backlog-db] R3-004 · consistency · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:94`

**Проблема:** Task 3 может стартовать до writer-upgrade, необходимого её собственному concurrency Eval

**Доказательство:** Task 3 заблокирована только Task 2 (`tasks.md:94`), но её Testing требует параллельный `mb-backlog-migrate.sh --apply` + `mb-idea.sh` под общим lock (`tasks.md:111`). Перевод `mb-idea.sh` на этот lock принадлежит Task 9 (`tasks.md:191-202`), которая находится в том же Stage 2 и также blocked only by 2. Следовательно DAG разрешает запуск T3 раньше или параллельно T9, когда обязательный test seam ещё отсутствует.

**Рекомендация:** Добавить реальную зависимость writer-upgrade перед миграционным race-тестом.

**Готовая правка:**

```
В Task 3 заменить `**Blocked-by:** 2` на `**Blocked-by:** 2, 9`. В преамбуле tasks.md заменить Stage 2 порядок на `{6, 7, 9} → 3`, сохранив ту же сумму бюджета Stage 2. Добавить в Task 3 Testing: `precondition: test_mb_backlog_id_alloc.bats is green before the migrate-vs-idea race case runs`.
```

#### [svp-roadmap-backlog-db] R3-005 · parent-decision · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:63`

**Проблема:** Task 2 требует запрещённую незавершённую заглушку list --tree

**Доказательство:** Task 2 предписывает `list [--tree]` с формулировкой «tree-часть — заглушка, полная реализация в Task 7» (`tasks.md:63`). Правила проекта запрещают placeholder-код без feature flag и полноценного staged-stub контракта (`rules/RULES.md:10-16`). Здесь ни flag, ни допустимый complete stub не определены.

**Рекомендация:** Не публиковать частичную ветку CLI в Task 2; завершить flat list, а флаг добавить в Task 7.

**Готовая правка:**

```
В Task 2 заменить соответствующий фрагмент на: ``list [--mb PATH]` полностью реализует flat-режим C3: depth=0, numeric I-ID order и точную JSON title-грамматику. Опция `--tree` в Task 2 ещё не объявляется; до Task 7 неизвестная опция завершается exit 2 без мутации.` В Task 7 добавить: `расширить уже полный flat CLI опциональным --tree без изменения flat output`. Добавить flat-list case в test_mb_backlog_state.bats.
```

#### [svp-roadmap-backlog-db] R3-006 · consistency · `.memory-bank/specs/svp-roadmap-backlog-db/requirements.md:45`

**Проблема:** REQ-006 разрешает parent=spec, а design/tasks поддерживают только I-NNN|none

**Доказательство:** Context и requirements обещают `parent: <I-NNN|spec>` (`context/svp-roadmap-backlog-db.md:47`; `requirements.md:45`). Публичный annotate CLI и каноническое поле принимают только `<I-NNN|none>` (`design.md:203-204,234-262`; `tasks.md:162-165`). Ни формат spec-parent, ни его разрешение в tree не определены.

**Рекомендация:** Привести живое требование к уже согласованному C3-контракту, не добавляя новый тип parent.

**Готовая правка:**

```
В context.md и requirements.md заменить REQ-006 на: `Where a backlog item declares **Parent:** <I-NNN|none>, the system shall treat an I-NNN parent as a subtask relationship and render the hierarchy in listings; an absent field or none denotes a root.` Сценарий 9 оставить без изменений.
```

#### [svp-roadmap-backlog-db] R3-007 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:170`

**Проблема:** Group renderer не задаёт порядок самих групп и их позицию внутри autosync fence

**Доказательство:** C2 фиксирует формат и сортировку членов, но говорит лишь «для каждой группы ## Group: <name> внутри fences» (`design.md:170-188`). Не определено, где Group-блок расположен относительно Now/Next/Linked Specs и как сортируются несколько group slug. Два корректных реализатора получат разный roadmap output, а byte-level regression/Eval не сможет выбрать канонический.

**Рекомендация:** Зафиксировать полную грамматику generated Group-блока.

**Готовая правка:**

```
Добавить в C2: `Generated Group sections are emitted after ## Linked Specs (active) and before the closing <!-- /mb-roadmap-auto --> fence. Group slugs are ordered by bytewise C locale ascending. Each heading is exactly ## Group: <slug>; one blank line separates groups. Member ordering remains C2. Manual content outside the fence is untouched.` В Task 6 Testing добавить фикстуру с двумя группами, обратным порядком файлов и assert точного порядка/позиции.
```

#### [svp-roadmap-backlog-db] R3-008 · edge-case · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:527`

**Проблема:** Promote не определяет восстановление после частичного отказа между созданием плана и записью backlog

**Доказательство:** C7 выполняет сначала `mb-plan.sh`, затем меняет backlog (`design.md:527-529`). Гарантия «ни плана, ни мутации» дана только для отказа предварительной валидации. Если plan создан, а atomic backlog write или последующий sync падает, остаётся orphan plan; повторный promote может создать дубль. Это прямо не покрыто Task 9 Testing (`tasks.md:199-204`).

**Рекомендация:** Определить громкий, идемпотентно восстанавливаемый partial-failure исход.

**Готовая правка:**

```
После C7 step 5 добавить: `If plan creation succeeds but backlog update or sync fails, exit 1 and print code=promote_partial plan=<repo-relative-path> backlog_updated=<true|false> to stderr. A retry for the same I-NNN MUST detect that exact existing plan, MUST NOT create a second plan, and MUST finish the missing backlog link/state or sync step idempotently. No failure may be reported as success.` В Task 9 Testing добавить fault-injection после plan creation и после backlog rename; в обоих случаях повторный вызов оставляет ровно один plan и один Plan link.
```

#### [svp-roadmap-backlog-db] R3-009 · eval · `.memory-bank/specs/svp-roadmap-backlog-db/tasks.md:75`

**Проблема:** Eval не проверяет заявленный запрет создания parent-цикла через annotate

**Доказательство:** C3 обещает, что annotate с циклом вернёт exit 1 без записи (`design.md:234-242`). Task 2 Testing проверяет существующего/несуществующего parent, но не цикл (`tasks.md:72-79`). Task 7 проверяет лишь чтение уже повреждённого цикла через list (`tasks.md:169-172`). Реализация, которая разрешает annotate создать цикл, пройдёт оба Eval.

**Рекомендация:** Добавить negative mutation-test на цикл в Task 2.

**Готовая правка:**

```
В Task 2 Testing после parent-кейсов добавить: `I-061 already has Parent I-060; annotate I-060 --brief <valid> --parent I-061 returns exit 1 with code=parent_cycle, leaves both item blocks byte-identical and emits no success stdout.` Добавить этот case в `test_mb_backlog_state.bats` под обязательным префиксом `backlog_state: `.
```

#### [svp-roadmap-backlog-db] R3-010 · contract · `.memory-bank/specs/svp-roadmap-backlog-db/design.md:349`

**Проблема:** Typed SPEC writer не определяет грамматику group/topic и поведение malformed [SPEC:...]

**Доказательство:** C4 распознаёт «точный префикс `[SPEC:<group>] <child-topic>`», но не задаёт допустимые символы, пустые значения или exit для `[SPEC:]`, `[SPEC:g]`, `[SPEC:g] a b`, незакрытой скобки и заголовка, случайно начинающегося с `[SPEC:` (`design.md:349-357`). Task 8 повторяет это без негативных кейсов (`tasks.md:224-235`). Ошибка способна записать структурно невалидный registry item до последующего lint.

**Рекомендация:** Зафиксировать grammar и fail-before-allocation для malformed registry prefix.

**Готовая правка:**

```
Добавить в C4: `A typed registration matches exactly ^\[SPEC:([a-z0-9][a-z0-9-]*)\] ([a-z0-9][a-z0-9-]*)$. Any title beginning with literal [SPEC: but not matching this grammar is a usage error: exit 2, empty stdout, backlog byte-identical and no I-NNN allocation. Titles not beginning with [SPEC: remain ordinary IDEA titles.` В Task 8 Testing добавить valid slug и malformed cases: empty group, empty topic, whitespace topic, uppercase, missing ], each proving no mutation/allocation.
```

#### [svp-sdd-core — round 3] R3-001 · eval · `.memory-bank/specs/svp-sdd-core/requirements.md:90-92; .memory-bank/specs/svp-sdd-core/design.md:305-335; .memory-bank/specs/svp-sdd-core/tasks.md:109-123,212-226`

**Проблема:** REQ-054 формально приписан T8, но behavioral preflight реализуется T4 только как prompt-текст и не имеет детерминированного production seam.

**Доказательство:** REQ-054 определяет generation-time Eval preflight (`requirements.md:91`). Task 4 фактически обещает эту логику (`tasks.md:116`), но не указывает REQ-054 в Covers и имеет Scope только `commands/sdd.md` и pytest текстового контракта (`tasks.md:109-123`). Task 8 указывает REQ-054 в Covers (`tasks.md:212`), но реализует work-time state, не generation preflight. Design назначает поведенческую часть «оркестратору» (`design.md:318-327`) без имени скрипта, CLI, stdout и exit-кодов.

**Рекомендация:** Выделить C8 в детерминированный helper и исправить семантическую трассируемость REQ-054.

**Готовая правка:**

```
Добавить интерфейс:
`bash scripts/mb-sdd-self-check.sh --spec <topic|spec-dir> [--mb <bank>]`
- выполняет C8.1–C8.5;
- stdout: `self_check=ready|invalid`, затем `eval.<task-id>=ready|pending_materialization|invalid` в порядке task-id;
- exit 0 = нет invalid, 1 = structural/behavioral violation, 2 = usage/malformed input;
- missing target → pending_materialization; existing target + green или несовпавший output~ → invalid; missing tool никогда не считается red.

Добавить новую Task 9, Stage 1, Budget 90000, Scope `scripts/mb-sdd-self-check.sh, tests/bats/test_mb_sdd_self_check.bats`, Covers `REQ-054`; сделать T4 Blocked-by `1,2,3,9`. Удалить REQ-054 из Covers T8. Обновить budgets: Stage 1 = 400000, total = 940000.
```

#### [svp-sdd-core — round 3] R3-002 · eval · `.memory-bank/specs/svp-sdd-core/tasks.md:132-150; .memory-bank/specs/svp-sdd-core/design.md:28-45`

**Проблема:** Eval T5 проверяет prompt-контракт, но не может доказать атомарный publish/discard и byte-identity принятого файла.

**Доказательство:** Вся production Scope T5 — `commands/sdd.md, references/templates.md` (`tasks.md:138`); исполняемого candidate lifecycle helper нет. При этом DoD требует атомарный `mv`, удаление candidate и byte-identical сохранение final (`tasks.md:142-154`). `pytest test_sdd_escalation_d35.py` может проверить текст prompt-файла, но не реальное поведение системы на файловой системе.

**Рекомендация:** Перенести механический candidate lifecycle из prompt-суждения в shell helper, оставив commands/sdd.md только orchestration.

**Готовая правка:**

```
Добавить C4a:
`bash scripts/mb-sdd-candidate.sh publish --topic <topic> --candidate <path> --estimate-file <path> [--override user] [--mb <bank>]`
`bash scripts/mb-sdd-candidate.sh discard --topic <topic> --candidate <path> [--mb <bank>]`
- helper проверяет canonical candidate path, разбирает key=value verdict C3 и выполняет same-filesystem rename;
- любой отказ оставляет существующий final byte-identical;
- publish запрещён при malformed verdict и при task/stage overflow;
- stdout: `candidate=published|discarded|blocked reason=<code>`; exit 0 success, 1 domain block, 2 usage/malformed.

Добавить helper и `tests/bats/test_mb_sdd_candidate.bats` в Scope/Eval T5; pytest prompt-контракта оставить дополнительным, не основным Eval.
```

#### [svp-sdd-core — round 3] R3-003 · parent-decision · `.memory-bank/specs/svp-sdd-core/requirements.md:70-73; .memory-bank/specs/svp-sdd-core/design.md:42-45,138-145; .memory-bank/specs/svp-sdd-core/tasks.md:142-149; .memory-bank/context/sdd-vision-pipeline.md:48,69`

**Проблема:** `budget_override: user` сформулирован как обход любого overflow и может пропустить задачи >120k или Stage >400k.

**Доказательство:** Parent D-13 фиксирует task ≤120k и stage ≤400k (`context/sdd-vision-pipeline.md:48`), а D-35 разрешает override одной большой спеки (`:69`). Child REQ-010 говорит именно о spec-level excess (`requirements.md:71`). Но publish разрешён при нормальном verdict «ИЛИ при явном budget_override» (`design.md:42-43`), а T5 обещает перенос «при over» без отделения task/stage (`tasks.md:142,149`). C3 возвращает exit 1 для любого task/stage/spec overflow (`design.md:142-143`).

**Рекомендация:** Разрешить override только для `spec=over`; task и stage caps должны оставаться hard limits.

**Готовая правка:**

```
Заменить publish-правило на:
«`budget_override: user` снимает только `spec=over`. Если `task_over != none` или `stage_over != none`, candidate всегда блокируется и удаляется; override не применяется. `spec=near` остаётся advisory. `spec=over` при пустых task_over/stage_over допускается только с явным override.»

В T3/T5 Testing добавить четыре отдельные матрицы: spec-only over + override → publish; task over + override → blocked; stage over + override → blocked; combined overflow + override → blocked.
```

#### [svp-sdd-core — round 3] R3-004 · contract · `.memory-bank/specs/svp-sdd-core/design.md:64-84; .memory-bank/specs/svp-parallel-engine/design.md:90-94,162-168`

**Проблема:** C1 обещает «любой POSIX glob», но определяет алгоритм только для `*` и `**`; семантика `?`, `[]`, escape и brace остаётся неопределённой.

**Доказательство:** S2 разрешает «repo-relative POSIX glob-паттерны» и запрещает потребителям любые дополнительные ограничения (`design.md:64-74`). Алгоритм пересечения определяет только `**`, `*` и равенство литералов (`:75-80`). POSIX-glob метасимволы `?` и bracket expressions не классифицированы как допустимые, запрещённые или литеральные. S3 повторяет обещание потребить контракт целиком (`svp-parallel-engine/design.md:90-94,162-168`), поэтому две реализации могут расходиться.

**Рекомендация:** Зафиксировать минимальную restricted-glob грамматику вместо неоднозначного обещания полного POSIX glob.

**Готовая правка:**

```
В C1 заменить термин `POSIX glob` на `restricted repo-relative glob` и добавить:
«Разрешены только литеральные символы пути, `*` внутри сегмента и сегмент `**`. Метасимволы `?`, `[`, `]`, `{`, `}`, backslash-escape и запятая внутри элемента запрещены и дают malformed/exit 2. CSV не имеет quoting/escaping. Потребители обязаны реализовать ровно эту restricted grammar.»

Добавить контрактные тесты invalid: `src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\\*.py`, `src/a,b.py`; синхронно заменить термин в S3 C1/C3.
```

#### [svp-sdd-core — round 3] R3-005 · coverage · `.memory-bank/specs/sdd-vision-pipeline/requirements.md:83; .memory-bank/specs/sdd-vision-pipeline/design.md:44; .memory-bank/specs/svp-sdd-core/requirements.md:7,62; .memory-bank/specs/svp-parallel-engine/requirements.md:47`

**Проблема:** Spec-validation половина umbrella REQ-022 реализуется S2, но формальная `covers_umbrella` трассировка указывает REQ-022 только на runtime-слайс S3.

**Доказательство:** Umbrella REQ-022 требует именно падение spec validation (`sdd-vision-pipeline/requirements.md:83`), а umbrella design назначает два рубежа: S2 spec-time и S3 runtime (`design.md:44`). S2 local REQ-052 реализует spec-time цикл-гейт (`svp-sdd-core/requirements.md:62`), но REQ-022 отсутствует в его `covers_umbrella` (`:7`). S3 local REQ-013 покрывает только abort frontier resolution (`svp-parallel-engine/requirements.md:47`). Это не оспаривает принятое решение оставить REQ-022 в S3: нужны оба владельца.

**Рекомендация:** Добавить S2 как второго формального делегата umbrella REQ-022, сохранив S3 runtime coverage.

**Готовая правка:**

```
Добавить `REQ-022` в `covers_umbrella` файлов `.memory-bank/context/svp-sdd-core.md` и `.memory-bank/specs/svp-sdd-core/requirements.md`; добавить `REQ-022` в Covers umbrella Task 4 и в строку S2 таблицы umbrella design. Запись S3/Task 7 оставить без изменений, поскольку она закрывает второй runtime-рубеж.
```

#### [svp-sdd-core — round 3] R3-006 · contract · `.memory-bank/specs/svp-sdd-core/requirements.md:82; .memory-bank/specs/svp-sdd-core/design.md:24,221-238,292-335`

**Проблема:** Спека не определяет acceptance-state после APPROVED, CHANGES_REQUESTED или SKIPPED и называет tasks.md «принятым» до C8 и spec-review.

**Доказательство:** Architecture делает атомарный перенос на шаге 7, затем запускает C8 на «принятом триплете» и лишь потом spec_review (`design.md:24,307-308`). REQ-012 требует review «before acceptance» (`requirements.md:82`). C5 задаёт журнал и exit-коды (`design.md:221-238`), но не определяет, кто меняет `status`, что происходит при CHANGES_REQUESTED, повторяются ли C3/C8 после правок и когда draft становится ready. C7 перечисляет blocked/invalid отчёты, но не переходы draft→ready (`:292-303`).

**Рекомендация:** Зафиксировать status state machine и считать publish в specs/ публикацией draft, а не acceptance.

**Готовая правка:**

```
Добавить в C5/C7:
- все новые/перегенерированные артефакты публикуются с `requirements.md: status: draft`;
- C8 failure или CHANGES_REQUESTED оставляет status draft;
- исправления после CHANGES_REQUESTED проходят новый candidate → C3 → publish draft → C8 → review cycle;
- status меняется на ready только после C8=0 и: review disabled, либо APPROVED, либо явного решения human/orchestrator принять SKIPPED/отклонённые issues; решение записывается в JSONL;
- helper/оркестратор никогда не называют draft-файл accepted;
- T7 проверяет переходы disabled→ready, APPROVED→ready, CHANGES_REQUESTED→draft, SKIPPED без решения→draft.
```

### MINOR (5)

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-006 · consistency · `.memory-bank/specs/svp-brief/design.md:287-292; .memory-bank/specs/svp-interview-upgrade/tasks.md:39,71,100,132,163,194; .memory-bank/specs/svp-adapt-escalation/design.md:515-522,598-603,632; .memory-bank/specs/svp-roadmap-backlog-db/design.md:203-240`

**Проблема:** R3: после волновых фиксов в Cross-slice requests остались уже выполненные запросы, всё ещё помеченные как блокеры.

**Доказательство:** S7 X-02 утверждает, что в S1 rev.3 нет output~-якорей (`svp-brief/design.md:292`), но все шесть S1 Eval уже содержат их (`svp-interview-upgrade/tasks.md:39,71,100,132,163,194`). S5 X5-01 и risk утверждают, что S4 не имеет `annotate` и Task 4 заблокирована (`adapt-escalation/design.md:519-522,602,632`), хотя S4-C3 уже специфицирует `annotate` (`roadmap-backlog-db/design.md:203-240`).

**Рекомендация:** Не оставлять выполненные cross-slice запросы в статусе active.

**Готовая правка:**

```
Заменить S7 X-02 на `SATISFIED — S1 tasks.md:39/71/100/132/163/194 содержат output~-якоря; действий нет`. Заменить S5 X5-01 на `SATISFIED — annotate определён S4-C3 и S4 Task 2`; удалить risk-строку `X5-01 не принят S4` и формулировку, что writer отсутствует.
```

#### [sdd-vision-pipeline (umbrella rev. 3 + S1–S8)] R3-007 · consistency · `.memory-bank/specs/sdd-vision-pipeline/design.md:74; .memory-bank/specs/svp-sdd-core/tasks.md:1-17; .memory-bank/roadmap.md:97; .memory-bank/specs/sdd-vision-pipeline/tasks.md:1-12`

**Проблема:** R3: количественные утверждения umbrella/roadmap не соответствуют текущим задачам.

**Доказательство:** Umbrella risk считает S2 равным 760k (`design.md:74`), тогда как frontmatter и суммы S2 равны 850k (`svp-sdd-core/tasks.md:1-17`). Roadmap утверждает, что `57 child + 9 umbrella` имеют все v2-поля (`roadmap.md:97`), но umbrella tasks прямо объявлены legacy и не имеют Stage/Scope/Budget (`sdd-vision-pipeline/tasks.md:1-12`).

**Рекомендация:** Исправить только фактические числа/классификацию, не менять scope umbrella.

**Готовая правка:**

```
В umbrella design заменить `сейчас 760k` на `сейчас 850k`. В roadmap заменить `57 задач child + 9 umbrella с v2-полями` на `57 child-задач с полным v2-набором; 9 umbrella-задач — bootstrap legacy/meta-формат с явными Blocked-by и Eval`.
```

#### [svp-brief] R3-009 · consistency · `.memory-bank/specs/svp-brief/design.md:272,287-292; .memory-bank/specs/svp-interview-upgrade/design.md:328-334; .memory-bank/specs/svp-interview-upgrade/tasks.md:39,71,100,132,163,194`

**Проблема:** Cross-slice requests X-01/X-02 и счётчик manual scenarios устарели после волновых фиксов.

**Доказательство:** S7 всё ещё просит S1 разрешить внешние клаузы и добавить `output~` (`design.md:291-292`), хотя S1 уже явно разрешает регистрацию (`svp-interview-upgrade/design.md:328-334`) и все шесть его Eval имеют `output~` (`tasks.md:39,71,100,132,163,194`). Кроме того, S7 пишет «сценарии §1–6» (`design.md:272`), хотя добавлен Scenario 7.

**Рекомендация:** Удалить исполненные запросы из активной таблицы и исправить счётчик сценариев.

**Готовая правка:**

```
Заменить строки X-01/X-02 на одну ненормативную запись: «X-01/X-02 — fulfilled in S1 revision 3; no remaining cross-slice action.» В `design.md:272` заменить `§1–6` на `§1–7`.
```

#### [svp-interview-upgrade] R3-004 · consistency · `.memory-bank/specs/svp-interview-upgrade/requirements.md:4; .memory-bank/context/svp-interview-upgrade-interview.md:7; .memory-bank/roadmap.md:83`

**Проблема:** Frontmatter помечает ICE как неподтверждённый, хотя транскрипт и roadmap утверждают обратное.

**Доказательство:** `ice_confirmed: false` записано в requirements (`requirements.md:5`). Исторический transcript говорит: «ICE слайса 8×9×7=504 подтверждён пользователем» (`context/svp-interview-upgrade-interview.md:7`), а roadmap описывает числа как подтверждаемые пользователем и уже ставит S1 первым (`roadmap.md:83-88`).

**Рекомендация:** Синхронизировать живой frontmatter с зафиксированным решением.

**Готовая правка:**

```
В `.memory-bank/specs/svp-interview-upgrade/requirements.md` заменить `ice_confirmed: false` на `ice_confirmed: true`.
```

#### [svp-sdd-core — round 3] R3-007 · consistency · `.memory-bank/specs/svp-sdd-core/requirements.md:124-129,159-165; .memory-bank/specs/svp-sdd-core/design.md:85-105`

**Проблема:** Сценарии 4 и 8 используют Eval-декларации, запрещённые собственным C1/REQ-055.

**Доказательство:** Scenario 4 задаёт `Eval: bats tests/x.bats` без `red:` и `output~:` (`requirements.md:127`); Scenario 8 объявляет `red: файла нет` и также не имеет output-якоря (`:163`). C1 требует red-прозу всегда, output~ для gated и прямо говорит: «Файла теста нет — не red-условие ни при каких обстоятельствах» (`design.md:89-105`). Оба сценария покрывают SHALL-требования и входят в исполняемый test-plan.

**Рекомендация:** Исправить примеры, не ослабляя C1.

**Готовая правка:**

```
В Scenario 4 заменить GIVEN на:
`- GIVEN задача с \`Eval: bats tests/x.bats — red: contract assertion fails; exit: 1; output~: not ok [0-9]+ red_to_green_contract\``

В Scenario 8 заменить Eval-фрагмент на:
`Eval: pytest tests/pytest/test_x.py — red: v2 fields are absent; exit: 1; output~: FAILED tests/pytest/test_x\\.py::test_v2_fields_parsed`
и дополнить THEN ключами `exit=1, output_re=<ERE>`.
```

### NIT (1)

#### [svp-sdd-core — round 3] R3-008 · clarity · `.memory-bank/specs/svp-sdd-core/design.md:16-18,366-369; .memory-bank/context/svp-sdd-core.md:104-106; .memory-bank/specs/svp-sdd-core/requirements.md:90-92`

**Проблема:** Namespace-примечания говорят `REQ-049…054`, хотя текущая ревизия содержит также REQ-055.

**Доказательство:** Design дважды ограничивает новый диапазон `REQ-049…054` (`design.md:16,366`), context повторяет его (`context/svp-sdd-core.md:104`), но requirements определяет REQ-055 (`requirements.md:92`).

**Рекомендация:** Синхронизировать документальный диапазон с текущим набором ID.

**Готовая правка:**

```
Во всех namespace/revision примечаниях S2 заменить `REQ-049…054` на `REQ-049…055`; смысл и номера требований не менять.
```

# Часть 3. Резюме по каждой спеке

### sdd-vision-pipeline (umbrella rev. 3 + S1–S8) — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Круг 3: 10 из 12 находок raw-ревью круга 2 закрыты полностью; R2-006 и R2-007 закрыты частично. Найдены 1 critical, 4 major и 2 minor дефекта. Главный блокер — reclaim-протокол общего lock допускает двух одновременных писателей.

**Coverage:** REQ всего 54; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Umbrella-покрытие точное: S1=11, S2=13, S3=10, S4=7, S5=3, S6=2, S7=2, S8=5, прямая T1=1; дублей и неизвестных ID нет. Все локальные child REQ покрыты задачами. Парсер прочитал 57 child-задач и 9 umbrella-задач. Извлечено 112 child-сценариев; каждый child REQ имеет сценарий, REQ-038 имеет umbrella-сценарий. EARS прошёл 9/9. Все 66 task Eval содержат компилируемый output~-ERE, и ни один не совпал с текущим missing-target/инфраструктурным выводом. Полный mb-spec-validate.sh не смог завершиться только из-за read-only sandbox: mktemp получил Operation not permitted; его read-only проверки воспроизведены отдельно.

**Сильные стороны:** Полное однозначное umbrella-покрытие 54/54: каждый REQ принадлежит ровно одному child-слайсу либо прямой T1.; Все 57 child-задач покрывают существующие локальные REQ; orphan tasks и orphan REQ отсутствуют.; Все child REQ имеют GWT-сценарии; суммарно извлечено 112 сценариев, parser/EARS проверки зелёные.; Все task/stage бюджеты укладываются в D-13: task ≤120k, stage ≤400k; максимальная спека S3 = 990k.; SVP-008, R2-001…005 и R2-008…011 закрыты; принятые отклонения AGR-019, claims-TTL, tasks.md registry, substituted fallback и исторические transcripts соблюдены.; Грамматики Blocked-by/Scope, claims-TTL против lock-liveness, opened/resolved escalation и group ICE frontmatter в основном синхронизированы между владельцами и потребителями.

### svp-adapt-escalation — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие полное, sizing корректен, однако спека пока не исполнима без догадок: 8 major-дефектов в runtime-контрактах, blocked_by, Scope и portability. Из находок круга 2 полностью закрыты SVP-AE-008, SVP-AE-009A и R2-001; SVP-AE-007 и SVP-AE-009B закрыты частично.

**Coverage:** REQ всего 10; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

REQ-001…REQ-010 покрыты задачами; все 5 задач ссылаются только на существующие REQ. Извлечено 10 сценариев, каждый REQ имеет сценарий. EARS validator: exit 0; scenario validator: exit 0; task parser: exit 0. mb-spec-validate для target и umbrella не завершился из-за запрета read-only sandbox на mktemp, а не из-за диагностированного дефекта спеки. Все 5 Eval-target файлов отсутствуют; их output~-якоря и реализуемые feature-маркеры в текущем коде не найдены, то есть готового ложного green не обнаружено. Непосредственный Bats red-прогон невозможен без материализации тестов и writable BATS_TMPDIR.

**Сильные стороны:** Точное покрытие: 10/10 REQ имеют задачи и сценарии; orphan REQ и orphan task отсутствуют.; SVP-AE-008 закрыт: две ветви replan разведены по обязательному replan_kind и механическому requirements_sha256 gate.; SVP-AE-009A закрыт в пределах принятого отклонения: default-on и пустой flag path проверяются двумя каноническими driver-прогонами без differential полного pytest-вывода.; R2-001 закрыт согласованно обеими сторонами: fake_red/foreign_failure/unobservable_requirement остаются локальными hard stop S8.; Все задачи укладываются в 120k, обе стадии — в 400k; раздробления или объединения не требуется.; Eval используют кодовые Bats-проверки и именованные output~-якоря; совпадений якорей или уже реализованных feature-маркеров в текущем репозитории не найдено.

### svp-brief — CHANGES_REQUESTED

Покрытие полное, а все 8 находок круга 2 закрыты по существу. Однако свежий аудит выявил 8 major-дефектов: противоречие режима `--auto`, ложноположительные red-якоря, неполный atomic-publish контракт, неопределённый формат Attachments, неописанную классификацию и агрегацию результатов secret-scan, противоречивую диагностику candidate и отсутствие eval-покрытия request-флагов. Спека пока не исполнима без догадок.

**Coverage:** REQ всего 10; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: Task 2 — `output~` совпадает с TAP-именем теста даже при `scripts/mb-brief-validate.sh: command not found`., Task 1 — якорь по имени теста принимает отсутствие `mb-brief.sh`/`commands/brief.md` за заявленный red., Task 3 — якорь по имени теста не отличает отсутствующую клаузу от foreign/setup failure внутри того же теста., Task 4 — якорь по имени теста не отличает структурный mismatch от ошибки чтения/отсутствия файла..

Точное покрытие: 10 REQ, 4 задачи; все Covers валидны. Семь сценариев покрывают 10/10 REQ. `mb-ears-validate.sh`, `mb-scenario-extract.py --validate`, извлечение 7 JSONL-сценариев и `mb_work_items.py` для 4 задач завершились с exit 0. `mb-spec-validate.sh` и Bats были запущены, но read-only sandbox запретил `mktemp`/BATS_TMPDIR; это ограничение среды, не дефект спеки. Проверка круга 2: SVP-BRIEF-001/002/003/004/006 и R2-001/002/003 полностью закрыты; ранее закрытые SVP-BRIEF-005/007/008 не регрессировали.

**Сильные стороны:** REQ→task покрытие полное и точное: 10/10; orphan REQ и ссылки на несуществующие REQ отсутствуют.; Scenario-layer валиден: 7/7 блоков извлекаются, каждый gated REQ имеет сценарий.; Находки круга 2 действительно закрыты: ownership scanner согласован с S1, candidate-channel определён, валидатор исполняется раньше helper, request/update/diagnostics контракты детализированы, docs Eval стал структурным.; Размеры соответствуют родительским лимитам: задачи 50k–115k, этапы 175k/110k, всего 285k.; Расширяемые файлы существуют; новые имена `mb-brief*.sh`, `commands/brief.md` и test-файлов свободны. Внешние зависимости корректно отражены в `blocked_by`.

### svp-contract-test-loop — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Повторный аудит выявил 1 critical и 6 major дефектов. Из 13 findings круга 2 восемь закрыты полностью (R2-002/003/005/006/007/008/009/011), четыре закрыты частично (R2-001/004/010/012), R2-013 не поднят согласно принятому отклонению о неизменяемых исторических транскриптах. Coverage полное, но спека пока не исполнима без догадок.

**Coverage:** REQ всего 21; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Точно найдено 21 REQ, 8 задач и 12 сценариев; orphan-ссылок нет. `mb-ears-validate.sh`, `mb-scenario-extract.py --validate`, извлечение 12 сценариев и `mb_work_items.py` прошли. `mb-spec-validate.sh` для child и umbrella не смог создать mktemp в read-only sandbox (`Operation not permitted`), поэтому coverage дополнительно пересчитано независимым read-only парсером. Все восемь Eval-target отсутствуют, как допускает S2 `pending_materialization`; текущие foreign failures не совпали с `output~`. Отдельная проверка показала, что все 8 якорей совпадают с заявленными именованными failure-сигнатурами и не совпадают с missing-target формами. Бюджеты: задачи ≤120k; Stage totals 180k/220k/190k/200k; spec total 790k.

**Сильные стороны:** Полное и точное покрытие: 21/21 REQ имеют task Covers; 8/8 задач ссылаются только на существующие REQ.; Все 21 REQ покрыты 12 валидно извлекаемыми сценариями с уникальными стабильными test_id.; Все 8 Eval имеют детерминированные команды и именованные `output~`-якоря, не совпадающие с missing-target signatures.; DAG задач сериализует shared writers: `{1,2} → 3 → 4 → 5 → 6 → 7 → 8`; межслайсовый blocker S2 и umbrella Task 9 исправлены.; Размеры соблюдены: ни одна задача не превышает 120k, ни один Stage — 400k, общий бюджет 790k.; Реальные extension points существуют; новые имена scripts/modules/tests свободны; несуществующий `commands/verify.md` больше не используется.; Принятые отклонения AGR-018/019 и граница с S5 `fake_red` соблюдены.

### svp-docs-wiki (revision 3, round-3 re-review) — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Покрытие полное и структурные проверки проходят, но спека пока неисполнима как есть: найдены 2 critical и 8 major-дефектов. Bootstrap всегда попадает в stale_run, а apply доверяет LLM-повтору run/base/target и теряет авторитетные deprecate/degraded_sources из plan. Две находки круга 2 закрыты лишь частично.

**Coverage:** REQ всего 12; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: T4/T5 — REQ-004 проверяется предзаполненным `body_markdown` и текстом prompt-файла; обнаружение противоречия из входных фактов остаётся LLM/reviewer-only., T3/T5/T7 — REQ-003 не имеет кодовой проверки положительного факта наличия cross-page wikilinks; проверяется только сохранение текста и отсутствие битых ссылок..

Точное task coverage: T1→REQ-006; T2→REQ-001/005/009/010/012; T3→REQ-002/003/012; T4→REQ-001/002/007/011/012; T5→REQ-002/004; T6→REQ-007; T7→REQ-008. Все 12 REQ покрыты 11 сценариями. `mb-ears-validate.sh` и `mb-scenario-extract.py --validate` завершились с exit 0; extractor выдал 11 сценариев; `mb_work_items.py` выдал 7 задач. Полный `mb-spec-validate.sh` и Eval-runner'ы не смогли создать temp-файлы в read-only sandbox (`mktemp: Operation not permitted`, pytest/Bats: no writable temp); все Eval-targets фактически отсутствуют, а их `output~:` не совпадает с наблюдавшимися инфраструктурными ошибками. Закрытие round 2: F-004 full; F-005 full; F-006 full; F-007 full; F-008 partial; F-010 partial; R2-001 full; R2-002 full; R2-003 full; R2-004 full.

**Сильные стороны:** Все 12 REQ имеют task coverage и scenario coverage; orphan REQ и ссылки на несуществующие REQ отсутствуют.; EARS, scenario extraction/validation и task parser проходят; извлекаются 11 сценариев и 7 задач.; Round-2 исправления действительно добавили production seam `plan/apply`, liveness-lock контракт S4, filesystem state scan и исполнимый capability resolver.; Заявленные новые module/script/agent/test имена пока свободны; существующие extension points `_io.atomic_write`, `mb-agent-caps.sh`, pipeline validator и MkDocs `docs_dir` фактически существуют.

### svp-interview-upgrade — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
CHANGES_REQUESTED: покрытие REQ полное, но спека пока небезопасна и не полностью исполнима. Из 6 находок круга 2 четыре закрыты полностью (R2-001, SVP-IU-003, R2-002, R2-003), две закрыты частично (SVP-IU-002, SVP-IU-005). Свежий проход обнаружил critical-регрессию приватности: API-ключ внутри <private> пропускается в git в открытом виде. Также недоопределены пользовательский budget-порог и error-контракты CLI.

**Coverage:** REQ всего 24; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: Task 1: создание и сохранение interview-plan проверяется prompt-контрактом и валидатором уже готовой фикстуры, но не исполняемым writer-путём., Task 4: последовательность candidate → scan/check → atomic mv существует только в prompt; C5 не принимает target и не может доказать неизменность целевого файла., Task 5: фактическая запись/конфликт glossary.md проверяются только prompt-клаузами; mb-context.sh проверяет лишь чтение указателя..

Точно найдены 24 локальных REQ: REQ-001…REQ-022, REQ-055, REQ-056. Все покрыты одной из 6 задач и хотя бы одним из 20 сценариев; orphan REQ и ссылки на несуществующие REQ отсутствуют. mb-scenario-extract.py --validate, прямое извлечение 20 сценариев, mb_work_items.py и EARS-validator завершились с exit 0. Полный mb-spec-validate.sh --require-scenarios и Bats Eval были запущены, но sandbox запрещает создание временных файлов (mktemp/BATS_TMPDIR not writable); их output~ якоря не приняли этот инфраструктурный сбой за целевой red.

**Сильные стороны:** Coverage точное и полное: 24/24 REQ покрыты задачами и сценариями; 6/6 задач ссылаются только на существующие REQ.; R2-001 закрыт: red теперь объявляется после материализации теста, а output~ использует положительные Bats-префиксы и не принимает `bats-gather-tests`/missing-file за целевой red.; SVP-IU-003 закрыт: S1 владеет base scanner/transcript policy, S7 явно blocked_by S1 и расширяет тот же CLI политикой brief-input.; R2-002 и R2-003 закрыты: mb-context.sh включён в Scope T5; scanner фиксирует labels email/api_key, сортировку `(line,column)` и запрет вывода секрета.; Все задачи имеют Budget не выше 120000; декомпозиция не содержит очевидной задачи-монстра или микрозадач-пыли.

### svp-parallel-engine — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE] Круг 3: из 11 находок круга 2 полностью закрыты 5, ещё 6 закрыты лишь частично. Покрытие REQ полное, однако остаются major-дефекты в контрактах claims-lock, выбора режима, scheduler state/actions, передачи unavailable, ICE-порядка и role-scoped dispatch для Pi/OpenCode.

**Coverage:** REQ всего 17; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Все REQ-001…REQ-017 покрыты задачами; все 10 задач ссылаются только на существующие REQ. Извлечено 16 уникальных сценариев, каждый REQ покрыт хотя бы одним сценарием. EARS validation и scenario extraction прошли; tasks parser извлёк 10 задач. Все Eval-target файлы и новые имена скриптов свободны, ложного green в текущем репозитории не обнаружено. Полный spec-validate и pytest/bats red-run были ограничены read-only sandbox: валидаторы не смогли создать временные файлы, однако output~-якоря не совпали с инфраструктурными ошибками sandbox/tool-not-found. Полностью закрыты SVP-PE-001, SVP-PE-006, R2-001, R2-005 и R2-006.

**Сильные стороны:** Точная traceability замкнута: 17/17 REQ покрыты задачами, orphan-ссылок и задач без REQ нет.; Все 17 требований покрыты 16 детерминированно извлекаемыми сценариями; EARS и parser задач проходят.; Размеры декомпозиции укладываются в лимиты: каждая задача ≤120k, каждый stage ≤400k токенов.; Волновые фиксы полностью закрыли spec-time gate, символическую Scope-грамматику, TTL claims, запрет self-ACK и число групповых child-спек.; Eval-target файлы и создаваемые имена скриптов свободны; output~-якоря не приняли инфраструктурные ошибки sandbox за ожидаемый red.

### svp-roadmap-backlog-db — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Круг 3: большинство находок круга 2 закрыто полностью, но R2-003 закрыта лишь частично — текущий S3-потребитель всё ещё не способен воспроизвести порядок S4 для missing/invalid ICE и читает created из другого источника. Свежий аудит обнаружил дополнительные контрактные дыры в helper API, transition-примитиве, lint-матрице и task DAG. Спека пока требует исправлений до разработки.

**Coverage:** REQ всего 12; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: —.

Точное покрытие: REQ-001→T1/T5; REQ-002→T6/T5; REQ-003→T6/T5; REQ-004→T4; REQ-005→T2/T9/T5; REQ-006→T7/T5; REQ-007→T2/T5; REQ-008→T8/T5; REQ-009→T3/T8/T5; REQ-010→T3; REQ-011→T3/T9; REQ-012→T6/T4. Извлечено 15 сценариев, test_id уникальны; mb-scenario-extract.py --validate прошёл. mb_work_items.py распарсил 9 задач. Полный mb-spec-validate не смог создать mktemp из-за read-only sandbox. Все Eval-target файлы отсутствуют; их output~-якоря не совпадают с ошибкой отсутствующего файла/непригодного BATS_TMPDIR и синтетически совпадают с заявленными именованными Bats-провалами.

**Сильные стороны:** Все 12 REQ покрыты задачами и gated-сценариями; все 9 задач ссылаются на существующие REQ.; F-003/F-005/F-008/F-010/F-012/F-013 и R2-001/R2-002/R2-004/R2-005/R2-006 круга 2 закрыты по их исходному предмету.; Все новые script/test имена свободны, а заявленные extension targets существуют в репозитории.; Eval-якоря больше не принимают отсутствие test-файла или инфраструктурную Bats-ошибку за настоящий red.

### svp-sdd-core — round 3 re-review — CHANGES_REQUESTED

[MEMORY BANK: ACTIVE]
Круг 3: F-007, F-009, R2-001, R2-002 и R2-003 закрыты по исходному предмету; F-010 закрыт частично. Формальная трассируемость полная: 22/22 REQ покрыты задачами и сценариями. Найдены 1 critical, 6 major, 1 minor и 1 nit: центральный red→green-гейт допускает подставные результаты, C8 и candidate lifecycle не имеют детерминированных production seams, override снимает не только spec-cap, Scope-грамматика неоднозначна, а acceptance-state spec-review не определён.

**Coverage:** REQ всего 22; REQ без задачи: —; gated REQ без GWT: —; недетерминированные эвалы: T4 — behavioral C8 preflight описан в prompt, но в Scope нет исполняемого helper; pytest проверяет только текст prompt-контракта., T5 — Eval может проверить только текст commands/sdd.md: production-код атомарного publish/discard отсутствует в Scope., T8 — eval-red/eval-green принимают заявленные caller-ом match/exit вместо самостоятельного запуска и проверки команды..

Точное покрытие: REQ-001→T4; 002→T4,T6; 003→T4; 004→T1; 005→T1,T6; 006→T2; 007→T2; 008→T8; 009→T3; 010→T5; 011→T5; 012→T7; 013→T4; 014→T5; 015→T2,T4; 049→T2,T6; 050→T2; 051→T2,T6; 052→T2; 053→T5; 054→T8; 055→T2. Извлечено 21/21 scenario-блоков, покрывающих все 22 REQ; mb_work_items.py извлёк 8/8 задач; EARS validator exit 0. Полный mb-spec-validate и симуляции pytest/bats не завершились: read-only sandbox запрещает mktemp даже в системном TMPDIR. Все восемь основных Eval-target файлов сейчас отсутствуют; по исправленному C8 это pending_materialization, а не observed red. Закрытие R2: F-007 closed; F-009 closed по helper/JSONL; F-010 partial; R2-001/002/003 closed.

**Сильные стороны:** Формальная трассируемость внутри child triple полная: 22/22 REQ имеют задачи и сценарии; нет orphan REQ или пустых Covers.; Candidate-режим C3 и JSONL spec-review helper предметно закрывают основные F-007/F-009 круга 2.; S3 теперь потребляет Scope-пересечение S2-C1 без прежнего сужения; R2-001 закрыт.; Generation preflight честно различает pending_materialization и observed red; отсутствие test target больше не выдаётся за доказанный red.; Текущая декомпозиция соблюдает записанные бюджеты: task max 120k, stages 310k/320k/220k, total 850k.

