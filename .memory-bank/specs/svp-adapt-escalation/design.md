# Design: svp-adapt-escalation

> Слайс S5. Зависимости **жёсткие**: S2 (`svp-sdd-core` — tasks.md v2 Eval/Budget/Scope-грамматика,
> C1) и S3 (`svp-parallel-engine` — Scope-вердикт `mb-work-scope-check.sh`, S3-C3). Контракты и
> Eval-декларации (D-05); код — в work-фазе.
> Ревизия 2 (2026-07-17): закрыты находки spec-ревью SVP-AE-001…013 — C1 получил полный набор
> входов и точные enum'ы, телеметрия переписана на двухфазный append-only контракт умбреллы
> (§Interfaces 3), контракт отчёта имплементера стал машинно-парсируемым envelope с fail-loud,
> stub/беклог/verify стали machine-verifiable, незаконная деградация «stub без флага» удалена,
> добавлен REQ-010 (каскад-стоп), Eval'ы переведены на поведенческие bats-тесты.
> Ревизия 3 (2026-07-17): закрыты PARTIAL-находки круга 2 — C1.0 фиксирует полные схемы трёх типов
> записей журнала по стилю умбреллы §Interfaces 5 (SVP-AE-007); `replan` разделён на
> `decomposition`/`requirement_change` с детерминированным критерием различения и гейтом C1.4
> (SVP-AE-008); verify-гейт стаба получил поведенческое доказательство flag-off/flag-on и больше не
> принимает default-on (SVP-AE-009A); создание беклог-элемента приведено к фактическому контракту
> S4-C3 ревизии 3 (SVP-AE-009B); зафиксирована граница с локальными hard stop'ами S8 (R2-001, X8-01)
> и совместимость C4 с ранними `KEY=`-блоками (X8-02); каждый Eval получил `output~:`-якорь
> настоящего провала (S2 REQ-054/055, умбрелла §Interfaces 1).

## Architecture

По образцу pivot-механики: **решение — скрипт, применение — оркестратор**.
1. **Скрипт** `scripts/mb-work-adapt.sh` — детект гардов + решение развилки (что предлагать),
   двухфазный JSONL-лог, гейт допуска после `replan`, verify-гейт стабов. Читает: пороги из
   pipeline.yaml (C3), счётчики циклов и `max_cycles` из `mb-work-state.sh status` (C2),
   нормализованные вердикты гардов от оркестратора (C1). Скрипт **ничего не мутирует** кроме
   `<bank>/tmp/escalations.jsonl`.
2. **Prompt** `commands/work.md` — врезка ADaPT-развилки в 5f-цикл (порядок — см. C1 §Приоритет),
   нормализация вердиктов гардов, применение решения (C5), контракт отчёта имплементера (C4).
3. **Конфиг** `escalation:` в `references/pipeline.default.yaml` (C3).
4. **Role-агенты** `agents/mb-*.md` — envelope C4 в контракте отчёта.

Разделение записи (D-23): банк пишет **только оркестратор** — беклог через существующие writer'ы S4
(`mb-idea.sh` + `mb-backlog-state.sh`, цепочка C6), чекбоксы/`progress.md` через существующие пути.
`mb-work-adapt.sh` не пишет беклог, не трогает `tasks.md` и не заводит второй мутатор беклога в
обход lock'а S4-C6.

## Interfaces

### C1. `scripts/mb-work-adapt.sh` — решение и телеметрия

Пять субкоманд (`decide` / `resolve` / `note-clean` / `replan-gate` / `verify-stub`). Телеметрия —
**двухфазная append-only** (умбрелла `sdd-vision-pipeline/design.md` §Interfaces 3 — потребляется
как есть, здесь не переопределяется): `opened` без resolution в момент эскалации, `resolved` после
решения, свёртка по `escalation_id`, последнее событие побеждает.

#### C1.0 Формат журнала `<bank>/tmp/escalations.jsonl` (закрывает SVP-AE-007)

Стиль записи — **умбрелла §Interfaces 5** (append-only JSONL, ровно одна строка на событие,
обязательный `ts`, явный счётчик попыток, последняя валидная строка = действующее состояние);
второй стиль журнала в группе не вводится. Файл не git-tracked (аналитика, не проектная память —
как `tmp/pivot-log.jsonl`). Ключи `ts`/`item_id`/`cycle`/`mode` совпадают с pivot-log
(NFR-002; фактический writer-образец — `scripts/mb-work-pivot.sh:125-145`).

Ровно один JSON-объект на строку; допустимы **ровно три** схемы, порядок ключей — как ниже:

- **`opened`** (писатель — `decide`, C1.1):

```json
{"ts":"<ISO-8601-UTC>","event":"opened","escalation_id":"<id>","seq":<int≥1>,"run_id":"<id>",
 "item_id":"<key>","cycle":<int≥0>,"mode":"autonomous|hitl",
 "decision":"stub_continue|fork_user|stop_run","triggers":["<token>"],
 "degraded_guards":["<token>"],"consecutive":<int≥1>}
```

- **`resolved`** (писатель — `resolve`, C1.2):

```json
{"ts":"<ISO-8601-UTC>","event":"resolved","escalation_id":"<id>","seq":<int≥1>,"run_id":"<id>",
 "item_id":"<key>","cycle":<int≥0>,"mode":"autonomous|hitl",
 "resolution":"continue|simplify|replan|skip|stub_continue",
 "replan_kind":null|"decomposition"|"requirement_change","backlog_id":null|"I-NNN",
 "spec_topic":null|"<slug>","requirements_sha256":null|"<64-hex>","resolved_by":"user|orchestrator"}
```

- **`clean`** (писатель — `note-clean`, C1.3):

```json
{"ts":"<ISO-8601-UTC>","event":"clean","run_id":"<id>","item_id":"<key>","cycle":<int≥0>}
```

**Правила полей:**

- `ts` — UTC ISO-8601, той же функцией, что pivot-log (`datetime.now(timezone.utc).isoformat()`).
- `seq` — явный счётчик попыток (роль `attempt` умбреллы §5): порядковый номер эскалации для тройки
  `(run_id, item_id, cycle)`, с 1. У `clean` счётчика нет — это не попытка, а закрытие item'а.
- `escalation_id` = `<run_id>:<item_id>:<cycle>:<seq>` — **непрозрачный токен**: сравнивается
  побайтово и НИКОГДА не разбирается обратно на компоненты (`item_id` вида `<topic>#<n>` и `run_id`
  могут содержать `:`; обратный разбор был бы round-trip-дрейфом). Все компоненты доступны
  отдельными полями, поэтому разбор и не нужен: `resolve` копирует `run_id`/`item_id`/`cycle`/
  `mode`/`seq` из соответствующего события `opened`, а не из строки id.
- `triggers` / `degraded_guards` — дедуплицированы и отсортированы в порядке таблицы триггеров C1.1
  (стабильный, не лексикографический). Пустой список допустим только у `degraded_guards`:
  `opened` без единого триггера не существует (`decision=none` в журнал не пишется).
- `resolved_by` — источник решения (честность REQ-008), выводится из **`decision` соответствующего
  `opened`, а не из режима** (R3-002): `decision=fork_user` → `user` (выбор на AskUserQuestion, в т.ч.
  autonomous-fallback при `feature_flag_unavailable`); `decision=stub_continue` → `orchestrator`; при
  `decision=stop_run` события `resolved` не бывает (resolve запрещён, C1.2).
- `requirements_sha256` — non-null **только** при `resolution=replan` (C1.2); иначе `null`.
- `replan_kind` / `spec_topic` — non-null только при `resolution=replan` (C1.2); `backlog_id` —
  non-null **и обязателен** при `resolution` ∈ {`skip`, `stub_continue`} (SVP-AE-007), иначе `null`
  и запрещён.

**Валидация при чтении** (каждая субкоманда читает журнал до записи): неизвестный `event`,
отсутствующий или лишний ключ, неверный тип значения, значение вне enum → строка невалидна → **exit
1 без append**, точная диагностика в stderr (`code=invalid_log_line line=<n>`).

*Почему fail-loud, а не деградация pivot-log* («telemetry must never wedge the loop»,
`scripts/mb-work-pivot.sh:44-47`): для pivot телеметрия — побочная аналитика, для ADaPT журнал —
**durable-состояние гарда**: из него считается `consecutive` (REQ-010) и корреляция `resolve`.
Тихо потерянная или угаданная строка ослабила бы каскад-стоп и молча проглотила бы эскалацию —
прямое нарушение REQ-008/D-33. Расхождение с pivot-log осознанное и относится только к этому файлу.

**Свёртка** (читатель — summary REQ-008 и `consecutive` C1.1): группировка по `escalation_id`;
последнее валидное `resolved` побеждает (коррекции C1.2); `opened` без `resolved` = открытая
эскалация — для `decision=stop_run` это норма (прогон остановлен), для остальных попадает в summary
как незакрытая.

**Конкурентность — сериализация общим lock-helper'ом S4-C6 (закрывает CPR-C / умбрелла R3-004)**:
`rules/RULES.md` явно допускает несколько orchestrator-сессий в одном working tree, поэтому
`<bank>/tmp/escalations.jsonl` пишется конкурентно, а гарантия атомарности `write()` при длине ≤
`PIPE_BUF` относится к pipe/FIFO, **НЕ** к concurrent append в regular file — прежнее обоснование через
`PIPE_BUF`/лимит 4096 удалено. Поэтому **весь путь read → validate (вычисление `seq`/`consecutive` по
`escalation_id`/`run_id`) → один append** выполняется под
`mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` (Interface 2, S4-C6), release — через `trap`;
`replan-gate` и summary читают согласованный snapshot **под тем же локом**. Лок потребляется из
`scripts/_lib.sh` (владелец S4-C6), пятая реализация не пишется — это **жёсткое ребро**
`Blocked-by: svp-roadmap-backlog-db#2` у Task 1. `seq`/`consecutive` считаются в пределах `run_id`
(параллельные прогоны с разными `run_id` не мешают друг другу по счётчикам), но их конкурентные append
сериализуются локом, поэтому оборванных хвостовых строк не возникает.

#### C1.1 `decide`

```
mb-work-adapt.sh decide --mb <bank> --item-id <key> --cycle <n> --mode <autonomous|hitl>
  --run-id <non-empty-id>
  [--signal-json <path|->]
  [--budget-status <ok|warn|stop|absent>]
  [--scope-status <ok|violation|unavailable>]
  [--eval-status <green|red|absent>]
  [--flag-mechanism <available|unavailable>]
```

**Входы (точные enum'ы, дефолты, источник):**

| Вход | Значения | Дефолт | Источник |
|---|---|---|---|
| `--mode` | `autonomous` \| `hitl` — канонические (enum S3-C4); `auto` → alias `autonomous`, `interactive` → alias `hitl`; иное → exit 2 | — (обязателен) | ответ на стартовый вопрос S3-C4, зафиксированный в `mb-work-state.sh` |
| `--item-id` | непустая строка, тот же ключ, что `item_id` pivot-log | — (обязателен) | оркестратор |
| `--cycle` | целое ≥ 0 | — (обязателен) | `mb-work-state.sh status` → `cycle` |
| `--run-id` | непустая строка — **обязателен** (пустая → exit 2; закрывает R3-001) | — (обязателен) | оркестратор передаёт локальный `RUN_ID` явным флагом (`commands/work.md:311,320`) — `MB_WORK_RUN_ID` там НЕ экспортируется, поэтому implicit-fallback снят |
| `--signal-json` | путь к отчёту имплементера или `-` (stdin); парсится по C4 | нет сигнала | отчёт исполнителя |
| `--budget-status` | `ok` \| `warn` \| `stop` \| `absent` — **нормализованный** статус, не сырой exit-код | `absent` | нормализация `mb-work-budget.sh check` (таблица ниже) |
| `--scope-status` | `ok` \| `violation` \| `unavailable` (enum S3-C3) | `unavailable` | `mb-work-scope-check.sh` → `.scope_status`; недоступен diff → `unavailable` |
| `--eval-status` | `green` \| `red` \| `absent` | `absent` | объект `eval` из `mb-work-state.sh status` (S2-C6, таблица ниже) |
| `--flag-mechanism` | `available` \| `unavailable` | `available` | оркестратор (есть ли в стеке проекта механизм feature-флагов) |

**Нормализация budget-гарда** (разрешает двусмысленность exit 1 в `scripts/mb-work-budget.sh`:
exit 1 = и WARN, и «нет бюджета», и stale run_id). Оркестратор обязан нормализовать по паре
(exit-код, stderr-маркер) — сырой exit-код на вход C1 не подаётся:

| exit | stderr-маркер | нормализованный статус | эффект |
|---|---|---|---|
| 0 | — | `ok` | нет триггера |
| 2 | `[budget] STOP:` | `stop` | **триггер** `budget_exceeded` |
| 1 | `[budget] WARN:` | `warn` | нет триггера; `degraded_guards` не пополняется (гард жив) |
| 1 | `[budget] no active budget` | `absent` | нет триггера; `degraded_guards += budget` |
| 1 | `[budget] run_id mismatch` | `absent` | нет триггера; `degraded_guards += budget` |

**Нормализация eval-гарда** (потребляет S2-C6 ревизии 3 — авторитетный writer `mb-work-state.sh
eval-red|eval-green` кладёт в состояние объект `eval: {cmd, red_exit, red_observed, red_match,
green_exit}`; сырой объект на вход C1 не подаётся):

| Состояние `eval` в work-state | `--eval-status` | Почему |
|---|---|---|
| `green_exit == 0` | `green` | verify подтвердил зелёный прогон |
| `green_exit` non-null и `!= 0` | `red` | eval не позеленел после implement — материал для `eval_not_green` |
| объекта `eval` нет, либо `green_exit == null` | `absent` | green-попытки ещё не было |

**Обязательный eval-first red (`red_observed=true`) триггером НЕ является** и в `eval_not_green` не
участвует: это требуемый TDD-красный до implement (S2-C6), а не отказ. Гард считает только
**неудавшиеся green-прогоны** (шаг `eval_fail`, C2).

**Граница с контрактными hard stop'ами S8 (закрывает R2-001; согласовано X8-01)**: вердикты
`fake_red`, `foreign_failure` и `unobservable_requirement` — **локальные немедленные hard stop'ы
S8**, которые обрабатываются **до** этого конвейера и мостов к нему не требуют. Их выдаёт раннер
`mb-contract-gate.sh red` (`svp-contract-test-loop/design.md` § C7), он же останавливает контрактную
задачу: item остаётся open, стадия implement бизнес-кода не диспатчится. В ADaPT они **не
маршрутизируются**: enum `--eval-status` остаётся ровно `green|red|absent`, значения `fake_red`
здесь нет и не будет, `complexity_escalation` из них не синтезируется. Причина — в самом S8-C7:
маршрутизация через ADaPT отсрочила бы немедленный отказ до исчерпания `max_cycles`, то есть
**ослабила бы** hard stop. При последующих штатных попытках S5 видит только свой обычный
`eval_status=red` по таблице выше. Мост не нужен ни с одной стороны — граница зафиксирована обеими.

**Счётчики циклов** (C2) читаются из `mb-work-state.sh status --mb <bank> [--run-id <id>]`; флагов
для них нет — источник durable и единственный. `status`, вернувший `{}` (fail-safe при битом
состоянии) → счётчики недоступны: `degraded_guards += loop_counters`, соответствующие триггеры
**не** срабатывают (нулём не притворяемся).

**Триггеры** (порядок в `triggers[]` — как в таблице, стабилен):

| Токен | Условие |
|---|---|
| `agent_signal` | `complexity_escalation` в отчёте — валидный непустой блок (C4) |
| `budget_exceeded` | `budget_status == stop` |
| `scope_violation` | `scope_status == violation` |
| `eval_not_green` | `eval_status == red` **и** `steps.count("eval_fail") >= work-state.max_cycles` |
| `verify_loops` | `steps.count("verify_fail") >= escalation.thresholds.verify` |
| `review_loops` | `steps.count("review_cycle") >= escalation.thresholds.review` |
| `judge_loops` | `steps.count("judge_cycle") >= escalation.thresholds.judge` |
| `feature_flag_unavailable` | `mode == autonomous` ∧ `flag_mechanism == unavailable` ∧ есть хотя бы один другой триггер |

Сравнение с порогом — **`count >= threshold`** (не `>`). Несколько триггеров одного вызова — **одна**
эскалация с несколькими токенами в `triggers[]` (edge-case «двойной триггер»).

**Решение:**

| Условие | `decision` |
|---|---|
| `triggers` пуст | `none` — JSONL не пишется, exit 0 |
| `consecutive >= escalation.cascade_stop` | `stop_run` (REQ-010) |
| `mode == hitl` | `fork_user` |
| `mode == autonomous` ∧ `feature_flag_unavailable` ∈ triggers | `fork_user` (REQ-004/009: голый stub запрещён) |
| `mode == autonomous` | `stub_continue` |

`consecutive` — число событий `opened` в `<bank>/tmp/escalations.jsonl` с текущим `run_id` после
последнего события `clean` (C1.3); текущая эскалация входит в счёт.

**Выход** (stdout, ровно один JSON-объект) + запись **ровно одного** события `opened` (схема C1.0)
при `decision != none`:

```json
{"escalation_id":"<run_id>:<item_id>:<cycle>:<seq>","decision":"none|stub_continue|fork_user|stop_run",
 "triggers":["..."],"degraded_guards":["..."],"consecutive":<int>}
```

`escalation_id` детерминирован (без random/uuid) и непрозрачен (C1.0): `seq` — порядковый номер
эскалации для той же тройки `(run_id, item_id, cycle)` в журнале, начиная с 1. При `decision=none`
журнал не пишется и `escalation_id` не выделяется (поле — пустая строка).

**Приоритет в 5f-цикле** (закрепляется врезкой Task 4): adapt-check выполняется **после** фиксации
неуспешного события фазы (шаг `verify_fail`/`review_cycle`/`judge_cycle`/`eval_fail` уже записан в
work-state) и **до** pivot-проверки и **до** существующей политики `on_max_cycles`. Порядок:
`фаза → mb-work-state.sh step <event> → adapt-check → pivot-check → on_max_cycles`. Политика 5f
после решения ADaPT **не меняется**: `decision=none` возвращает управление в существующий поток без
изменений.

#### C1.2 `resolve`

```
mb-work-adapt.sh resolve --mb <bank> --id <escalation_id>
  --resolution <continue|simplify|replan|skip|stub_continue>
  [--replan-kind <decomposition|requirement_change>] [--spec-topic <slug>]
  [--spec <spec-dir>] [--backlog-id <I-NNN>]
```

- Append-ит **ровно одно** событие `resolved` (схема C1.0) для `escalation_id`.
- Неизвестный `--id` (нет события `opened`) или значение вне enum → **exit 2**.
- **Обязательность/запрет полей по `resolution` (закрывает SVP-AE-007)** — полная матрица, нарушение
  любой ячейки → **exit 2 без append**:

  | `--resolution` | `--backlog-id` | `--replan-kind` | `--spec-topic` | `--spec` |
  |---|---|---|---|---|
  | `stub_continue` \| `skip` | **обязателен** (`I-NNN`; отсутствие/неверный формат → exit 2) | запрещён | запрещён | запрещён |
  | `continue` \| `simplify` | запрещён | запрещён | запрещён | запрещён |
  | `replan` + `decomposition` | запрещён | обязателен | обязателен | обязателен |
  | `replan` + `requirement_change` | запрещён | обязателен | **запрещён** | обязателен |

  Без `--backlog-id` для `stub_continue`/`skip` запись `resolved` несла бы `backlog_id=null` и потеряла
  бы связь стаба/пропуска с беклогом (REQ-008/009), поэтому флаг обязателен.
- **`resolved_by` выводится из фактического решения `opened`, а НЕ из режима (закрывает R3-002)**:
  `resolved_by=user`, если соответствующий `opened` несёт `decision=fork_user` (сюда входит и
  autonomous + `feature_flag_unavailable` → принудительный `fork_user`, где выбор делает пользователь
  через AskUserQuestion); `resolved_by=orchestrator`, если `decision=stub_continue`; для
  `decision=stop_run` вызов `resolve` **запрещён** → exit 2. Так автономный fallback к `fork_user` не
  помечается ложно как решение оркестратора (честность REQ-008).

**`replan` — две разные развилки (закрывает SVP-AE-008).** Родительское D-16 перечисляет
«перепланировать (декомпозиция **или** смена требований)» как два исхода, и они ведут в разные
места, поэтому вид перепланирования — **обязательная часть resolution payload**, а не комментарий:

| | `--replan-kind decomposition` | `--replan-kind requirement_change` |
|---|---|---|
| Смысл | цель та же, **требования не меняются** — план дробится (D-10) | цель не достигается текущими требованиями — нужна их правка (эскалация к спеке/пользователю) |
| `--spec-topic` | **обязателен** | **запрещён** (exit 2) — child-спека не создаётся |
| Артефакт | child-спека `<slug>`: регистрация в реестре decomposed-spec существующим writer'ом `bash scripts/mb-idea.sh "[SPEC:<group>] <slug>" MED <bank>` (S2-C7 / S4-C4) + своё интервью (self-interview в autonomous), REQ-006 | артефактов не создаётся; правка `requirements.md` текущей спеки выполняется пользователем (hitl) или JIT-слайсом (AGR-001) вне прогона |
| Item | остаётся `pending`, чекбокс не переворачивается | остаётся `pending`, чекбокс не переворачивается |
| Допуск к новому прогону | гейт C1.4 | гейт C1.4 |

- `--replan-kind` обязателен **только** при `--resolution replan`; при любой другой resolution он
  запрещён → exit 2. `--spec` (каталог текущей спеки) обязателен при `replan`: из него берётся
  `requirements_sha256` (ниже); отсутствие/нечитаемость → exit 2.
- **Детерминированный критерий различения — что именно сравнивается**: `sha256` файла
  `<spec-dir>/requirements.md`, снятый в момент `resolve` и записанный в событие `resolved` полем
  `requirements_sha256`. Декомпозиция по определению требования **не меняет**, смена требований —
  **меняет**; поэтому один и тот же снимок разводит ветви механически, а не на глаз. Проверку
  исполняет гейт C1.4 при следующем прогоне item'а. Ни `Scope`, ни `DoD`, ни `tasks.md` в хэш не
  входят: `tasks.md` мутирует от переворота чекбоксов соседних задач, и хэш по нему давал бы
  ложный «требования изменились» после любой посторонней правки (сравнение обязано быть
  чувствительным ровно к тому, что оно различает). Правка Scope/DoD — путь `simplify` (C5).

**Идемпотентность и коррекция** — по **полному tuple** `(resolution, replan_kind, backlog_id,
spec_topic)`:

- полностью совпадающий tuple → no-op, exit 0, новая строка не пишется;
- изменение **любого** поля tuple → append корректирующего `resolved` (append-only, свёртка
  «последнее побеждает» — умбрелла §Interfaces 3). Сравнение по одной лишь `resolution` было бы
  дефектом: исправление `--spec-topic` при том же `replan` молча потерялось бы.
- Каждая коррекция обязана быть перечислена в финальном summary прогона (REQ-008) — молчаливой
  замены нет.

#### C1.3 `note-clean`

```
mb-work-adapt.sh note-clean --mb <bank> --item-id <key> --run-id <non-empty-id>
```

- Append-ит событие `clean` — item закрылся без эскалации; обнуляет `consecutive` для C1.1
  (REQ-010: «успешное завершение item без эскалации сбрасывает счёт»). Вызывается оркестратором на
  успешном `done` item'а. Exit 0.

#### C1.4 `replan-gate` — допуск item'а к новому прогону после `replan`

```
mb-work-adapt.sh replan-gate --mb <bank> --item-id <key> --spec <spec-dir>
```

Делает обещание C1.2 «новый прогон только после…» исполнимым, а не прозаическим. **`--run-id` у гейта
нет (закрывает R3-001)**: гейт выбирает **последнее валидное `resolved`-событие данного `item_id` по
append-порядку среди ВСЕХ `run_id`** (replan мог быть записан в прошлом прогоне с другим `run_id`, а
допуск проверяется в новом); конкурентный запуск одного `item_id` исключён claim-контрактом S3.
Сравнивает записанный `requirements_sha256` с `sha256(<spec-dir>/requirements.md)` **сейчас**:

| Последняя resolution | Условие допуска | Отказ (exit 1, stderr `code=…`) |
|---|---|---|
| `replan` + `decomposition` | хэш **совпал** (требования не менялись — план дробился) **и** существует `<bank>/specs/<spec-topic>/requirements.md` | `code=requirements_changed_under_decomposition` (заявлена декомпозиция, а требования правились — вид перепланирования указан неверно) \| `code=child_spec_missing spec_topic=<slug>` |
| `replan` + `requirement_change` | хэш **различается** (требования действительно правились) | `code=requirements_unchanged` — правки не было, item к прогону не допускается |
| любая другая / нет `resolved` | допуск (гейт не вмешивается) | — |

- Exit: `0` допуск; `1` отказ (item остаётся `pending`, диспатч не выполняется, причина — в
  summary REQ-008); `2` usage / нечитаемая спека / битый журнал.
- Вызывается оркестратором **до** диспатча item'а, у которого есть `resolved` с `replan`
  (врезка Task 4). Для item'ов без такой истории — no-op с exit 0.

#### C1.5 `verify-stub`

```
mb-work-adapt.sh verify-stub --repo <root> --diff-file <path> --backlog <path>
```

- `--repo` — корень репозитория, из которого исполняются драйверы (обязателен); `--diff-file` —
  newline-separated repo-relative пути изменённых файлов (та же поверхность, что S3-C3:
  modified/staged/deleted/renamed/untracked); `--backlog` — путь к `backlog.md`.
- **Структурные проверки** по каждому изменённому файлу (C6):
  1. каждый маркер `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<path>` ссылается на `I-NNN`,
     существующий в `--backlog`; иначе — violation `unknown_backlog_id`;
  2. маркер стоит на **комментарий/docstring-строке**: строка обязана матчиться
     `^[[:space:]]*("""|'''|///|//|/\*|\*|#|--|;)?[[:space:]]*MB-ADAPT-STUB `; иначе — violation
     `marker_not_in_docstring` (маркер в исполняемом коде за docstring не считается);
  3. токен `<NAME>` встречается в том же файле **вне строки маркера**; иначе — violation
     `flag_token_unused`;
  4. голый placeholder (`NotImplementedError`, `TODO`, `FIXME`, одиночный `...`-стаб) без маркера
     `MB-ADAPT-STUB` в том же файле — violation `bare_placeholder` (REQ-009).
- **Поведенческое доказательство ограждённости** (закрывает SVP-AE-009A) — структурных признаков
  недостаточно: `flag=FOO` при `FOO=1` по умолчанию и неиспользуемое упоминание токена проходят
  проверки 1–3, оставаясь **неограждённым продакшн-кодом**. Поэтому каждый маркер обязан нести
  `eval=<repo-relative путь к исполняемому драйверу>`, и гейт запускает его **дважды** из `--repo`
  через **portable bounded-run `mb_adapt_bounded_run 120 <driver>`** (закрывает R3-006: стоковый
  macOS не несёт ни GNU `timeout`, ни `gtimeout`, поэтому хелпер пробует `timeout`, затем `gtimeout`,
  иначе — Bash 3.2 watchdog с TERM→KILL; тот же приём, что `scripts/mb-work-codex-preflight.sh:46-65`;
  все timeout-исходы нормализуются в violation `stub_eval_timeout`):

  | Прогон | Env | Требование | Что доказано |
  |---|---|---|---|
  | 1 | `<NAME>` **не установлен** | exit 0 **и** stdout содержит ровно `MB-ADAPT-STUB-PATH: baseline` | флаг **default-off**: без него живёт прежний путь |
  | 2 | `<NAME>=1` | exit 0 **и** stdout содержит ровно `MB-ADAPT-STUB-PATH: staged` | флаг **включает** stub-реализацию |

  Оба токена канонические и печатает их драйвер. Почему именно так, а не «команда вернула 0»:
  сравнение exit-кодов не отличило бы флаг-пустышку от работающего флага, а сравнение полного
  вывода двух прогонов ложно зеленело бы на таймингах раннеров (`pytest` печатает длительность —
  вывод различается всегда). Два канонических токена детерминированы, стек-агностичны и
  недостижимы без реального ветвления по флагу.
- **Исходы драйвера**: отсутствующий `eval=` в маркере → violation `missing_stub_eval`; прогон 1,
  напечатавший `staged` → violation `flag_default_on`; неверный/отсутствующий токен → violation
  `flag_does_not_gate_stub`; non-zero exit → violation `stub_eval_failed`; таймаут → violation
  `stub_eval_timeout`. Драйвер не найден или не исполняем → **exit 2 fail-loud** (это дефект
  оснастки, а не нарушение автора стаба — тихо зеленеть нельзя).
- **Честная граница**: машинно доказаны ровно default-off, реальное ветвление по флагу и
  расположение маркера на doc-строке. **Полнота** docstring (что делает / что заменяет / когда —
  `rules/RULES.md` § Staged stubs) машиной не проверяется и таковой не объявляется: это предмет
  ревью/верифаера (C7). Заявлять «docstring проверен кодом» было бы ложью в семантике.
- stdout: JSON
  `{"stubs":[{"file","backlog_id","flag","eval"}],"violations":[{"file","line","reason"}]}` —
  список валидных стабов идёт в summary (REQ-008).
- Exit: `0` чисто; `1` есть violations; `2` usage / нечитаемый вход / неисполнимый драйвер.

#### C1.6 Exit-коды (все субкоманды)

`0` — валидное решение/запись/допуск; `2` — usage / невалидный вход (неизвестный enum, неизвестный
`--id`, отсутствие обязательного флага, запрещённая комбинация флагов, неисполнимый драйвер);
`1` — внутренняя ошибка разбора (битый JSON конфига/сигнала, невалидная строка журнала C1.0), плюс
`1` = violations у `verify-stub` и отказ допуска у `replan-gate`.

### C2. Счётчики циклов — расширение записи work-state (без правки скрипта)

`scripts/mb-work-state.sh` **не редактируется** этим слайсом: контракт достигается аддитивной
конвенцией поверх существующего API (`step <name>` append-ит имя в `steps[]`, `status` печатает
всё состояние JSON'ом). Состояние per-(run, item) — счётчики естественно обнуляются на новом item.

**Зарезервированные имена шагов** (durable-счётчики, вместо сегодняшнего общего `cycle`):

| Шаг | Кто пишет | Смысл |
|---|---|---|
| `eval_fail` | оркестратор после **неудавшегося green-прогона** — `mb-work-state.sh eval-green` вернул `green_exit != 0` (S2-C6) | счётчик для `eval_not_green` (порог — `max_cycles` из того же состояния). Обязательный eval-first red (`eval-red`, `red_observed=true`) шаг **не пишет**: это требуемый TDD-красный, а не отказ |
| `verify_fail` | оркестратор после FAIL verify | счётчик для `verify_loops` |
| `review_cycle` | оркестратор после цикла ревью | счётчик для `review_loops` |
| `judge_cycle` | оркестратор после цикла судьи | счётчик для `judge_loops` |
| `adapt_skip` | оркестратор при resolution `skip` (C5) | item пропущен, чекбокс не переворачивается |
| `adapt_override` | оркестратор при resolution `continue` (C5) | override зафиксирован, verify-отчёт несёт пометку |

Счётчик = число вхождений имени в `steps[]`. Существующий общий `cycle` остаётся как есть
(используется `on_max_cycles`) — ADaPT его **читает, но не мутирует**.

### C3. Конфиг `escalation:` (`references/pipeline.default.yaml`)

```yaml
escalation:
  thresholds: { verify: 3, review: 3, judge: 2 }   # REQ-003
  cascade_stop: 3                                   # REQ-010
```

- Валидация `mb-pipeline-validate.sh`: каждое значение — целое ≥ 1; `0`, отрицательные, нецелые,
  строки и неизвестные ключи внутри `escalation:` → fail с точным сообщением.
- Секция отсутствует → дефолты `3/3/2` + `cascade_stop: 3` (легаси-совместимость, D-26).

### C4. Контракт отчёта имплементера (envelope)

**Последний непустой блок** отчёта любого исполнителя обязан быть ровно одной строкой:

```
MB_WORK_RESULT_JSON={"status":"DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT","complexity_escalation":null|{"reason":"<non-empty>","estimated_tokens":<positive-int>}}
```

- **Извлечение**: оркестратор берёт последнюю строку отчёта, начинающуюся с `MB_WORK_RESULT_JSON=`,
  и парсит остаток как JSON. Markdown-STATUS остаётся человекочитаемым слоем — envelope его не
  заменяет, а завершает.
- **Ранние `KEY=`-блоки других слайсов контракт НЕ ломают (подтверждение X8-02)**. Грамматика
  ограничивает только **последний непустой блок** и ключуется на **точном префиксе**
  `MB_WORK_RESULT_JSON=`; строки с любым другим ключом выше по отчёту игнорируются извлечением, а
  «последним непустым» остаётся envelope. Конкретно проверено против S8: `MB_CONTRACT_CHECKERS_JSON=`
  печатается отдельным блоком **раньше**, отделённым пустой строкой
  (`svp-contract-test-loop/design.md` § C3a) — совместимо, C4 ослаблять или переформулировать не
  требуется. Фикстура ровно этого отчёта — обязательный тест-кейс Task 3.
- `complexity_escalation: null` → сигнала нет (валидный отчёт).
- **Набор ключей envelope закрыт**: ровно `status` и `complexity_escalation`. Лишний ключ →
  `invalid_implementer_report` (тот же fail-loud), а не молчаливое игнорирование: догадками отчёт не
  интерпретируется, а расширение контракта проходит явной ревизией, не тихим ключом. Подтверждено
  X8-01: `contract_task` в envelope не приходит — вердикты S8 останавливаются локально (C1.1
  §Граница), поэтому опциональных полей под них не заводится.
- **Fail-loud** (никогда silent ignore): отсутствие строки `MB_WORK_RESULT_JSON=`, отсутствие ключа
  `complexity_escalation`, битый JSON, пустой `reason` или `estimated_tokens` ≤ 0 → halt текущего
  item с `invalid_implementer_report` в summary; отчёт не интерпретируется догадками.
- **Файлы контракта** (все исполнители): `agents/mb-developer.md`, `agents/mb-backend.md`,
  `agents/mb-frontend.md`, `agents/mb-ios.md`, `agents/mb-android.md`, `agents/mb-architect.md`,
  `agents/mb-devops.md`, `agents/mb-qa.md`, `agents/mb-analyst.md` + контракт отчёта в
  `commands/work.md`.

### C5. Развилка — семантика четырёх вариантов (prompt-контракт)

`decision=fork_user` → AskUserQuestion с четырьмя вариантами. Для каждого — точный переход
(чекбокс переворачивается **только** после успешного `done`, `commands/work.md` «Worktree rule»-блок
статусов не ослабляется):

| Вариант | `resolve --resolution` | work-state | Чекбокс | Беклог | Повторный триггер |
|---|---|---|---|---|---|
| continue anyway | `continue` | шаг `adapt_override` | обычный путь (переворот только на успешном done) | нет | после `continue` текущая фаза возвращается в штатный поток; **любое** последующее failed-событие, включая тот же набор `triggers`, создаёт **новую** развилку (подавление повторного триггера удалено — R3-003: у обещания не было ни входа `phase`, ни хранимого состояния, ни алгоритма сравнения наборов; KISS) |
| simplify | `simplify` | item остаётся `pending`, прогон останавливается | не переворачивается | нет | требует утверждённой правки Scope/DoD в спеке до нового прогона |
| replan → **декомпозиция** | `replan --replan-kind decomposition --spec-topic <slug> --spec <dir>` | item остаётся `pending`, текущий прогон завершается | не переворачивается | child-спека `<slug>` в реестре decomposed-spec (`mb-idea.sh "[SPEC:<group>] <slug>"`) + своё интервью (self-interview в autonomous), REQ-006 | новый прогон допускается гейтом C1.4: требования **не** менялись, child-спека существует |
| replan → **смена требований** | `replan --replan-kind requirement_change --spec <dir>` (`--spec-topic` запрещён) | item остаётся `pending`, текущий прогон завершается | не переворачивается | нет — child-спека не создаётся | новый прогон допускается гейтом C1.4 **только** после фактической правки `requirements.md` (hitl — пользователем, autonomous — JIT-слайсом по AGR-001); без правки — отказ `requirements_unchanged` |
| skip | `skip` | шаг `adapt_skip`, переход к следующему item | не переворачивается | элемент через C6 | item перечислен как незакрытый в итоговом summary (REQ-008) |

AskUserQuestion показывает **четыре** варианта (REQ-005 — «replan» остаётся одним пунктом развилки);
вид перепланирования уточняется вторым вопросом сразу после выбора `replan` и становится
обязательным `--replan-kind` в payload (C1.2). Четыре пункта — контракт пользователя, а
`replan_kind` — контракт машины; они не конкурируют.

`decision=stub_continue` (autonomous) → C6. `decision=stop_run` (каскад, REQ-010) → прогон
останавливается **до диспатча следующего item**, summary несёт рекомендацию пересмотреть спеку
целиком (D-35-путь).

### C6. Stub-протокол и беклог (детерминированный)

- **Маркер**: docstring стаба содержит строку
  `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<repo-relative-path>`.
- **Флаг**: `<NAME>` — именованный feature-флаг, **default-off**, существующий или созданный в этой
  же задаче; токен обязан встречаться в файле вне строки маркера (C1.5, проверка 3).
- **Драйвер `eval=`**: исполняемый файл репо (по конвенции — под `tests/`), печатающий
  `MB-ADAPT-STUB-PATH: baseline` при выключенном `<NAME>` и `MB-ADAPT-STUB-PATH: staged` при
  `<NAME>=1`; пишется исполнителем в той же задаче и является **доказательством** ограждённости
  (C1.5). Путь, а не shell-строка — чтобы контракт не зависел от квотирования.
- **Стаб** = полная реализация Protocol/интерфейса + docstring (что делает, что заменяет, когда) за
  флагом — единственное легальное исключение no-placeholders (`rules/RULES.md` § Staged stubs).
  Голый `NotImplementedError`/`TODO` — запрещён без исключений.
- **Порядок**: беклог-элемент создаётся **до** правки кода (маркер обязан ссылаться на
  существующий `I-NNN`, иначе C1.5 = violation).

**Создание беклог-элемента — точная последовательность против фактического S4-C3 ревизии 3**
(закрывает SVP-AE-009B). Пишет **ТОЛЬКО оркестратор** (D-23); ни `mb-work-adapt.sh`, ни исполнитель
беклог не трогают. Ветка «до S4» **удалена**: порядок исполнения группы ставит S4 (ICE 432) перед
S5 (294) (`roadmap.md` § Group, умбрелла § Порядок исполнения), поэтому API S4 существует к старту
слайса. Жёсткого ребра `blocked_by` это не добавляет — тот же паттерн мягкой зависимости, что
S3 → S4 (умбрелла §Interfaces 2).

Целевое состояние — `READY` (S5-A-03; `READY` — единственное предсостояние `IN-PROGRESS` по D-15,
то есть единственное, из которого отложенную работу можно взять в план через `mb-idea-promote.sh`).
`PLANNED` не используется **никогда** — его нет в алфавите S4-C3, и S4-C7 прямо запретил его
автоматическое присвоение.

1. **Создание** — существующий позиционный контракт (S4-C4 «production writer»):
   `id=$(bash scripts/mb-idea.sh "[ADAPT] <spec-topic>#<task-id>: <reason>" HIGH <bank>)` → stdout
   ровно `I-NNN`; запись рождается в состоянии `NEW` с метастрокой `**Type:** IDEA`. `[ADAPT]` —
   префикс **заголовка** (греп-конвенция), а не тип реестра: типы S4 — только `SPEC`/`IDEA`.
   `--force` **не передаётся**: similarity-гейт S4-C3 сверяет заголовок с `## Out of scope`, и его
   отказ (exit 1, `similar_out_of_scope=<I-NNN>`) — правильное поведение, а не помеха: если
   отложенную работу уже признали вне области, тихо застабить её было бы худшим из исходов.
2. **Текущее состояние** — `bash scripts/mb-backlog-state.sh list --mb <bank>` → строка
   `item=<id> state=<STATE> …` (машинная грамматика S4-C3). Шаг обязателен из-за идемпотентности
   `mb-idea.sh` по заголовку: повторная эскалация с тем же заголовком вернёт **существующий**
   `I-NNN` в его текущем состоянии, и слепая цепочка переходов упала бы на недопустимом ребре.
3. **Переходы** — кратчайший валидный путь от наблюдаемого состояния к `READY` по машине S4-C3
   (`NEW→NEEDS-INFO`, `NEEDS-INFO→TRIAGED`, `TRIAGED→READY`), каждым отдельным вызовом
   `bash scripts/mb-backlog-state.sh transition "$id" <STATE> --mb <bank>`:

   | Наблюдаемое состояние | Действия |
   |---|---|
   | `NEW` | `NEEDS-INFO` → annotate (п.4) → `TRIAGED` → `READY` |
   | `NEEDS-INFO` | annotate (п.4) → `TRIAGED` → `READY` |
   | `TRIAGED` | annotate (п.4) → `READY` |
   | `READY` \| `IN-PROGRESS` | цель достигнута — переходов нет (элемент переиспользуется) |
   | `DONE` \| `WONTFIX` | **halt стаб-пути**: терминальное состояние (рёбер из него нет), `WONTFIX` вдобавок означает «признано вне области» |

4. **Brief перед `READY`** — READY-гейт S4-C3 блокирующий: требует блок `**Brief:**` в теле записи,
   behavioral (обязан содержать `should|shall|must|когда|если`) и **без путей файлов** (`\S+/\S+\.\w+`)
   и **без номеров строк** (`:\d+`). Записывается атомарно API S4:
   `bash scripts/mb-backlog-state.sh annotate "$id" --brief "<BRIEF>" [--parent <I-NNN|none>] --mb <bank>`
   (**поставлен владельцем S4-C3 revision 4** — единственный writer блоков `**Brief:**`/`**Parent:**`,
   валидирует brief ТОЙ ЖЕ функцией, что READY-гейт, под lock C6 и atomic-записью, stdout
   `item=<id> annotated`; закрывает SVP-AE-009B/X5-01. S5 потребляет контракт **как есть**, не
   переопределяет его и своего второго writer'а беклога не заводит — это была бы пятая реализация
   мутации в обход lock'а S4-C6).
   `<BRIEF>` — **фиксированный шаблон**, в который подставляются только машинно-ограниченные
   значения, поэтому гейт проходится детерминированно:

   ```
   While <NAME> is off, the existing behavior shall remain unchanged; when <NAME> is on, <capability> shall be available.
   ```

   `<NAME>` — токен флага `[A-Z][A-Z0-9_]*` (структурно без `/` и `:<цифры>`); `<capability>` —
   короткая поведенческая фраза, ограниченная `[A-Za-z0-9 ,-]+`. **Сырой `<reason>` в brief не
   подставляется**: он свободный текст и регулярно содержит путь файла (`scripts/mb-x.sh …`), что
   уронило бы READY-гейт по `contains file path`. Шаблон несёт `shall` — обязательный
   глагол-паттерн; проверено против фактических правил S4-C3, а не предположено.
5. **Любой non-zero на шагах 1–4 останавливает стаб-путь ДО правки кода** и попадает в summary
   (REQ-008): маркер обязан ссылаться на существующий `I-NNN`, поэтому «сначала код, потом беклог»
   недопустимо ни при каком исходе.

### C7. Verify-гейт стаба

- `agents/plan-verifier.md` + verify-шаг `commands/work.md` вызывают
  `mb-work-adapt.sh verify-stub --repo <root> …` (C1.5) и трактуют exit 1 как **FAIL задачи**
  (REQ-009): голый stub, отсутствующий флаг, несуществующий `I-NNN`, маркер вне doc-строки,
  **default-on флаг** и **флаг, не управляющий путём**, не проходят. Exit 2 (драйвер не
  исполняется) — тоже FAIL задачи, но с иной причиной: дефект оснастки, чинится, а не обходится.
- Гейт **default-off by construction**: он не читает никакой конфиг «включённости» и не имеет режима
  «принять на слово». Единственное принимаемое доказательство — два прогона драйвера с
  каноническими токенами (C1.5); нет драйвера — нет прохождения.
- Отчёт верифаера перечисляет валидные стабы с их беклог-элементами и драйверами (вход для summary
  REQ-008), а полноту docstring оценивает как ревью-суждение, не как машинный факт (C1.5 §Честная
  граница).

## Decisions

S5-A-01…04 + D-16/33/35 — в context. Плюс зафиксировано ревизией 2:

- **Зависимость от S3 — жёсткая** (закрывает SVP-AE-005 / SVP-008): scope-гард REQ-002 потребляет
  вердикт S3-C3 (`ok|violation`) напрямую и единым enum'ом; формулировки «гард опционален» /
  «деградирует без S3» удалены. `unavailable` — только транзиентный случай (diff недоступен), а не
  режим жизни без S3: попадает в `degraded_guards` и в summary.
- **Телеметрия — двухфазная, контракт умбреллы** (закрывает SVP-AE-007): `decide` печатает
  `escalation_id` и пишет `opened` без resolution; `resolve` пишет `resolved`. Ключи
  `item_id`/`cycle`/`mode` совпадают с pivot-log (NFR-002).
- **Счётчики — существующий API work-state** (закрывает SVP-AE-004): раздельные durable-счётчики
  достигаются зарезервированными именами шагов (C2), скрипт `mb-work-state.sh` не редактируется.
- **Порядок**: adapt-check ДО pivot-check (разные классы триггеров, приоритет размеру) и ДО
  `on_max_cycles`; общие счётчики читаются, не мутируются.

Зафиксировано ревизией 3:

- **Схема журнала — стиль умбреллы §Interfaces 5** (закрывает SVP-AE-007): три закрытые схемы
  (`opened`/`resolved`/`clean`), обязательные `ts` + явный счётчик `seq`, последняя валидная строка
  побеждает. Второго стиля журнала в группе не заводится; невалидная строка — fail-loud, потому что
  журнал здесь durable-состояние гарда REQ-010, а не побочная аналитика (обоснование — C1.0).
- **`replan` — два разных исхода** (закрывает SVP-AE-008): `--replan-kind` обязателен для replan;
  различаются механически по `sha256(requirements.md)` (декомпозиция требований не меняет, смена
  требований — меняет), исполняются гейтом C1.4. Идемпотентность сравнивает полный tuple
  `(resolution, replan_kind, backlog_id, spec_topic)` — сравнение по одной `resolution` теряло бы
  коррекцию `--spec-topic`.
- **Стаб доказывается поведением, а не разметкой** (закрывает SVP-AE-009A): структурные проверки
  1–3 пропускают default-on флаг и неиспользуемый токен, поэтому обязателен драйвер `eval=` с
  каноническими токенами `baseline`/`staged`. Отклонено предложение ревью держать `**Stub Eval:**`
  строкой беклога: это потребовало бы второго writer'а тела беклога (S4) и парсинга свободного
  текста, тогда как маркер уже несёт структурные поля, а путь к драйверу не страдает от
  квотирования. Отклонён и differential по полному выводу двух прогонов — тайминги раннеров делают
  его ложно-зелёным всегда.
- **Беклог — фактический API S4-C3 revision 4** (закрывает SVP-AE-009B): `mb-idea.sh` (→ `NEW`,
  `**Type:** IDEA`) → `list` (состояние) → кратчайший валидный путь до `READY` + `annotate` для
  `**Brief:**`. Ветка «до S4» удалена (роадмеп ставит S4 раньше S5). **`annotate` поставлен владельцем
  S4-C3 revision 4 (X5-01 SATISFIED)** — зависимость жёсткая, объявлена во frontmatter `blocked_by` и
  в `Blocked-by` Task 4; шаблон brief проверен против фактических правил
  READY-гейта: черновик ревью («When … is off, existing behavior remains…») их **не проходит** —
  в нём нет ни одного глагола `should|shall|must|когда|если`.
- **Граница с S8 зафиксирована обеими сторонами** (закрывает R2-001): `fake_red`/`foreign_failure`/
  `unobservable_requirement` — локальные hard stop'ы S8 перед этим конвейером; enum `--eval-status`
  не расширяется, envelope C4 не получает опциональных полей (X8-01). Совместимость C4 с ранним
  блоком `MB_CONTRACT_CHECKERS_JSON=` подтверждена без ослабления грамматики (X8-02).

## Cross-slice requests (правки в чужих спеках — здесь не делаются)

| # | Адресат | Запрос | Основание |
|---|---|---|---|
| X5-01 | `svp-roadmap-backlog-db` (S4), контракт C3 | **SATISFIED (S4-C3 revision 4)**: `mb-backlog-state.sh annotate <I-NNN> --brief <TEXT> [--parent <I-NNN\|none>] [--mb PATH]` поставлен владельцем — единственный writer блоков `**Brief:**`/`**Parent:**`, валидирует brief **той же** функцией, что READY-гейт (behavioral + без путей и номеров строк), под lock C6 и atomic-записью; stdout `item=<id> annotated`; exit 1 domain / 2 usage. S5 потребляет контракт **как есть**; зависимость жёсткая: frontmatter `blocked_by: [svp-sdd-core, svp-parallel-engine, svp-roadmap-backlog-db]`, Task 4 `Blocked-by: 3, svp-roadmap-backlog-db#2`. Дальнейших правок S4 не требуется — своего второго writer'а S5 не заводит (была бы пятая мутация в обход lock'а S4-C6) | SVP-AE-009B; S4-C3 § annotate |
| X5-02 | `svp-contract-test-loop` (S8) | Информационно, ответ на X8-01/X8-02: граница принята дословно — `fake_red`/`foreign_failure`/`unobservable_requirement` в ADaPT не маршрутизируются, enum `--eval-status` остаётся `green\|red\|absent`, опциональных полей под `contract_task` в envelope C4 не заводится (C1.1 §Граница). C4 подтверждён совместимым с ранним блоком `MB_CONTRACT_CHECKERS_JSON=`: грамматика ограничивает только последний непустой блок, извлечение ключуется на точном префиксе `MB_WORK_RESULT_JSON=` — правок в S8 не требуется, фикстура этого отчёта добавлена в Task 3 | X8-01, X8-02, R2-001 |

## Eval declarations (red → green в work-фазе)

Все Eval — поведенческие (bats на фикстурах), не word-grep; каждый красный в текущем репозитории
(файлов тестов ещё нет).

**Red-якоря обязательны** (S2 REQ-054/055, умбрелла §Interfaces 1): каждая задача покрывает gated
(SHALL) REQ, поэтому каждый `Eval:` несёт `output~:`-ERE **сигнатуры настоящего провала**, а не
отсутствия файла. Измерено на этом дереве 2026-07-17: `bats <несуществующий файл>` → exit 1 +
`not ok 1 bats-gather-tests`, то есть **тот же exit**, что у настоящего провала теста — exit-only
якорь принял бы «файла нет» за заявленный red. Настоящий провал печатает `not ok <n> <имя теста>`,
поэтому якорь привязан к имени конкретного теста: строка `bats-gather-tests` его не матчит.

| Task | Eval | Red-условие | Якорь настоящего провала |
|---|---|---|---|
| T1 | `bats tests/bats/test_mb_work_adapt.bats` (каждый триггер C1.1; нормализация budget и eval-статуса; enum-алиасы и exit 2; счётчики из work-state и `{}`-деградация; схемы журнала C1.0; идемпотентность/коррекция `resolve` по tuple; `replan-gate`; каскад и `note-clean`) | скрипта и тестов нет | `exit: 1`; `output~: not ok [0-9]+ .*adapt_decide_budget_stop_triggers` |
| T2 | `bats tests/bats/test_mb_pipeline_escalation.bats` (дефолты 3/3/2 + cascade 3; zero/negative/non-int/unknown key → fail) | конфига и валидации нет | `exit: 1`; `output~: not ok [0-9]+ .*pipeline_escalation_defaults_3_3_2` |
| T3 | `bats tests/bats/test_mb_work_adapt_report.bats` (envelope C4 во всех 9 role-агентах + work.md; `null` = нет сигнала; битый JSON/пустой reason/≤0 оценка/лишний ключ → `invalid_implementer_report`; ранний `MB_CONTRACT_CHECKERS_JSON=`-блок S8 парсится корректно) | контракта envelope нет | `exit: 1`; `output~: not ok [0-9]+ .*report_envelope_present_in_all_nine_agents` |
| T4 | `bats tests/bats/test_mb_work_adapt_orchestration.bats` (порядок adapt-before-pivot; 4 варианта C5 + обе ветви replan; autonomous stub-путь и цепочка беклога S4-C3; реестр декомпозиции; skip без переворота чекбокса; каскад-стоп REQ-010; полный summary) | врезки развилки нет | `exit: 1`; `output~: not ok [0-9]+ .*orchestration_adapt_check_precedes_pivot_check` |
| T5 | `bats tests/bats/test_plan_verifier_stub_gate.bats` (маркер+флаг+драйвер+существующий I-NNN → PASS; default-on → FAIL; маркер вне doc-строки → FAIL; флаг не управляет путём → FAIL; голый NotImplemented/TODO → FAIL; два валидных стаба → оба в summary) | verify-гейта нет | `exit: 1`; `output~: not ok [0-9]+ .*stub_gate_default_on_flag_fails` |

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Ложные срабатывания гардов душат прогресс | M | M | пороги в конфиге (C3) + телеметрия для калибровки; `continue anyway` всегда доступен |
| Конфликт с pivot-логикой | M | M | явный порядок C1.1 §Приоритет: adapt-check ДО pivot-check; общие счётчики читаются, не мутируются |
| Стабы копятся и не разгребаются | M | M | REQ-008: каждый стаб в финальном отчёте; C1.5 не пускает стаб без беклог-ID; элементы доводятся до `READY` (C6), то есть готовы к `mb-idea-promote.sh`, а не оседают в `NEW` |
| Драйвер `eval=` выродится в формальность (печатает токены, не вызывая seam) | M | M | тот же класс риска, что у чекеров S8: два прогона обязаны дать **разные** канонические токены, что без ветвления по флагу недостижимо; полнота seam — предмет ревью (C7) и не объявляется машинно доказанной |
| Оркестратор забыл записать шаг-счётчик → гард молчит | M | H | T4 проверяет порядок «шаг → adapt-check»; `{}`-состояние даёт `degraded_guards`, а не тихий ноль |

## Open questions

- Калибровка порогов — по первым governed-прогонам (телеметрия C1).
