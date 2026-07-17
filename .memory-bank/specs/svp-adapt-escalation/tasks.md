# Tasks: svp-adapt-escalation

> Слайс S5 (ICE 294, blocked by svp-sdd-core + svp-parallel-engine — обе зависимости жёсткие).
> Eval первым (red) → реализация (green). Порядок: 1 → 2 → 3 → 4 → 5.
> Бюджеты: Stage 1 = 200000, Stage 2 = 160000 (оба ≤ 400000); каждая задача ≤ 120000.
> Ревизия 3: каждый `Eval:` несёт `output~:`-якорь настоящего провала (S2 REQ-054/055) — `bats` на
> отсутствующем файле даёт тот же exit 1, что настоящий провал, поэтому exit-only якорь запрещён.

<!-- mb-task:1 -->
## Task 1: mb-work-adapt.sh — гарды, решение, двухфазная телеметрия

**Covers:** REQ-001, REQ-002, REQ-003, REQ-007, REQ-010
**Role:** backend
**Stage:** 1
**Blocked-by:** svp-sdd-core#8, svp-parallel-engine#3, svp-roadmap-backlog-db#2
**Scope:** scripts/mb-work-adapt.sh, tests/bats/test_mb_work_adapt.bats, tests/bats/fixtures/adapt/**
**Budget:** 110000

**What to do:**
- Новый `scripts/mb-work-adapt.sh` по C1: субкоманды `decide` / `resolve` / `note-clean` /
  `replan-gate` (`verify-stub` — Task 5). **Blocked-by выровнен (R3-004 + CPR-C)**: `svp-sdd-core#8`
  (durable eval-объект `eval-red`/`eval-green` поставляет **S2 Task 8**, не Task 1);
  `svp-roadmap-backlog-db#2` (lock-helper C6 для сериализации журнала).
- `decide`: все входы и enum'ы C1.1 (алиасы `auto`/`interactive`; неизвестное значение → exit 2);
  **`--run-id <non-empty-id>` обязателен** (пустая строка → exit 2; `MB_WORK_RUN_ID`-fallback снят —
  оркестратор передаёт `RUN_ID` явным флагом, `commands/work.md:311,320`, R3-001); триггеры
  `agent_signal`/`budget_exceeded`/`scope_violation`/`eval_not_green`/`verify_loops`/
  `review_loops`/`judge_loops`/`feature_flag_unavailable`; сравнение `count >= threshold`; счётчики
  из `mb-work-state.sh status` по конвенции C2 (скрипт work-state **не править**); `{}`-состояние →
  `degraded_guards += loop_counters`, а не ноль; пороги из `escalation:` (C3) с дефолтами 3/3/2 и
  `cascade_stop: 3`; детерминированный непрозрачный `escalation_id`; решение по таблице C1.1.
  Enum `--eval-status` — ровно `green|red|absent` (границу с hard stop'ами S8 не пересекаем, X8-01);
  нормализуется из объекта `eval` (`mb-work-state.sh eval-red|eval-green`, S2 Task 8 — сам гоняет cmd).
- Журнал строго по трём схемам C1.0: `opened` на `decide` (только при `decision != none`),
  `resolved` на `resolve`, `clean` на `note-clean`; обязательные `ts`/`seq`; ключи
  `item_id`/`cycle`/`mode` совместимы с pivot-log (NFR-002); невалидная строка при чтении → exit 1
  без append. **Конкурентность — под lock'ом S4-C6 (CPR-C)**: весь путь read → validate
  (`seq`/`consecutive`) → append под `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30`
  (`_lib.sh`, владелец S4-C6), release — `trap`; `replan-gate`/summary читают snapshot под тем же
  локом. Обоснование через `PIPE_BUF`/лимит 4096 **удалено** (относится к pipe/FIFO, не к concurrent
  append в regular file, `rules/RULES.md` допускает несколько orchestrator-сессий).
- `resolve`: exit 2 на неизвестный `--id`/невалидный enum/**запрещённую комбинацию флагов по матрице
  C1.2** (SVP-AE-007: `--backlog-id` **обязателен** для `stub_continue`/`skip` и запрещён иначе;
  `--replan-kind` обязателен и только при `replan`; `--spec-topic` обязателен при `decomposition`,
  запрещён при `requirement_change`); `resolved_by` **выводится из `decision` соответствующего `opened`,
  не из режима** (R3-002: `fork_user`→`user`, `stub_continue`→`orchestrator`, `stop_run`→resolve запрещён);
  `requirements_sha256` снимается с `<spec-dir>/requirements.md`; идемпотентность и коррекция — по полному
  tuple `(resolution, replan_kind, backlog_id, spec_topic)`.
- `replan-gate` по C1.4 (**без `--run-id`**, R3-001): выбирает последнее `resolved` данного `item_id`
  по append-порядку среди всех `run_id`; сверка записанного `requirements_sha256` с текущим; коды отказа
  `requirements_unchanged` / `requirements_changed_under_decomposition` / `child_spec_missing`.
- `note-clean` (**`--run-id` обязателен**, R3-001) — событие `clean`, обнуляющее `consecutive` для
  каскад-стопа (REQ-010).

**Eval:** `bats tests/bats/test_mb_work_adapt.bats` — red: скрипта и тестов нет, ни один триггер C1.1 не считается; exit: 1; output~: not ok [0-9]+ .*adapt_decide_budget_stop_triggers

**Testing (TDD — tests BEFORE implementation):**
- bats на фикстурах `tests/bats/fixtures/adapt/**`: каждый триггер по отдельности и «двойной
  триггер» = одна эскалация с двумя токенами; граница `count == threshold` срабатывает, `count ==
  threshold - 1` — нет; нормализация budget (`ok|warn|stop|absent` — все четыре строки таблицы C1.1,
  включая обе ветки exit 1); нормализация eval-статуса (`green_exit=0` → green; non-null ≠0 → red;
  объекта нет или `green_exit=null` → absent; обязательный eval-first red триггером не является);
  `scope_status=unavailable` → `degraded_guards`, не триггер; `eval_not_green` против `max_cycles`
  из work-state; `{}`-состояние work-state → деградация; автономный режим без flag-механизма →
  `fork_user` + `feature_flag_unavailable`; каскад: 3 подряд `opened` → `stop_run`, `note-clean`
  сбрасывает; журнал: обе фазы, обязательные `ts`/`seq`, свёртка по `escalation_id`, лишний ключ /
  неизвестный `event` / неверный тип → exit 1 без append; `item_id` с `:` не ломает корреляцию
  (id не разбирается); tuple-идемпотентность: тот же tuple → no-op, смена `--spec-topic` при том же
  `replan` → корректирующая строка; `replan-gate`: три кода отказа и допуск обеих ветвей;
  exit-коды 0/1/2 по C1.6; shellcheck clean.
- bats (**R3-001 run-id**): `decide`/`note-clean` с пустым `--run-id` → exit 2; `replan-gate` **без**
  `--run-id` выбирает последнее `resolved` данного `item_id` среди всех `run_id` (replan из прошлого
  прогона допускается в новом).
- bats (**R3-002 resolved_by**): `mode=hitl` → `decision=fork_user` → `resolved_by=user`;
  `mode=autonomous` + `feature_flag_unavailable` → принудительный `fork_user` → `resolved_by=user`
  (НЕ orchestrator); `mode=autonomous` штатный → `stub_continue` → `resolved_by=orchestrator`;
  `resolve` по `stop_run`-опенеду → exit 2.
- bats (**SVP-AE-007 backlog-id матрица**): `stub_continue`/`skip` без `--backlog-id` или с неверным
  форматом → exit 2 без append; `continue`/`simplify` с `--backlog-id` → exit 2; `replan` с
  `--backlog-id` → exit 2; корректный `stub_continue --backlog-id I-NNN` → append.
- bats (**CPR-C concurrency**): два **реальных** конкурентных orchestrator-процесса пишут журнал под
  `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` → журнал валиден, оба `run_id` сохранены, `seq`
  внутри каждого корректен, ни одно `opened`/`resolved` не потеряно и не оборвано.

**DoD:**
- [ ] C1.0–C1.4 реализованы; bats green (были red); `mb-work-state.sh` не изменён
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Конфиг escalation в pipeline.yaml

**Covers:** REQ-003
**Role:** developer
**Stage:** 1
**Blocked-by:** 1
**Scope:** references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_mb_pipeline_escalation.bats
**Budget:** 40000

**What to do:**
- Секция C3 в `references/pipeline.default.yaml` (`thresholds: {verify: 3, review: 3, judge: 2}`,
  `cascade_stop: 3`) + валидация в `mb-pipeline-validate.sh`: значение — целое ≥ 1; `0`,
  отрицательное, нецелое, строка, неизвестный ключ внутри `escalation:` → fail с точным сообщением;
  отсутствие секции → дефолты (легаси-совместимость).

**Eval:** `bats tests/bats/test_mb_pipeline_escalation.bats` — red: секции `escalation:` и её валидации нет, дефолты 3/3/2 не резолвятся; exit: 1; output~: not ok [0-9]+ .*pipeline_escalation_defaults_3_3_2

**Testing (TDD — tests BEFORE implementation):**
- bats: дефолтный файл содержит 3/3/2 + cascade_stop 3 и валиден; фикстуры `verify: 0`,
  `review: -1`, `judge: 2.5`, `verify: "три"`, `unknown_key: 1` → каждая fail с сообщением;
  отсутствующая секция → pass + дефолты.

**DoD:**
- [ ] Конфиг + валидация; bats green (был red)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Envelope-контракт отчёта исполнителей

**Covers:** REQ-001
**Role:** developer
**Stage:** 1
**Blocked-by:** 2
**Scope:** commands/work.md, agents/mb-*.md, tests/bats/test_mb_work_adapt_report.bats
**Budget:** 50000

**What to do:**
- Envelope C4 (`MB_WORK_RESULT_JSON=…` последней непустой строкой отчёта) в контракт отчёта
  `commands/work.md` и во все 9 role-агентов: `agents/mb-developer.md`, `mb-backend.md`,
  `mb-frontend.md`, `mb-ios.md`, `mb-android.md`, `mb-architect.md`, `mb-devops.md`, `mb-qa.md`,
  `mb-analyst.md`.
- Правило извлечения (последняя строка с префиксом `MB_WORK_RESULT_JSON=`) и fail-loud обработка:
  нет строки / нет ключа `complexity_escalation` / битый JSON / пустой `reason` /
  `estimated_tokens` ≤ 0 / лишний ключ в envelope → halt item'а с `invalid_implementer_report`;
  `null` → сигнала нет.
- Явная фиксация X8-02: ранние блоки с другими `KEY=`-строками (S8 печатает
  `MB_CONTRACT_CHECKERS_JSON=` отдельным блоком выше) контракт не нарушают — ограничен только
  последний непустой блок, извлечение ключуется на точном префиксе.

**Eval:** `bats tests/bats/test_mb_work_adapt_report.bats` — red: envelope-контракта нет ни в work.md, ни в 9 агентах; exit: 1; output~: not ok [0-9]+ .*report_envelope_present_in_all_nine_agents

**Testing (TDD — tests BEFORE implementation):**
- bats: цикл по всем 9 файлам агентов — каждый содержит envelope и `complexity_escalation`
  (отсутствие любого → fail); `commands/work.md` содержит правило извлечения и все fail-loud ветки;
  фикстурные отчёты: валидный сигнал → распознан, `null` → нет сигнала, битый JSON / пустой reason /
  `estimated_tokens: 0` / лишний ключ / отсутствие строки → `invalid_implementer_report`;
  **фикстура S8** (блок `MB_CONTRACT_CHECKERS_JSON={"checkers":[…]}`, пустая строка, затем
  `MB_WORK_RESULT_JSON={…}`) → envelope извлечён корректно, ранний блок проигнорирован (X8-02).

**DoD:**
- [ ] Envelope во всех 9 исполнителях + work.md; bats green (был red)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Развилка в /mb work

**Covers:** REQ-004, REQ-005, REQ-006, REQ-008, REQ-010
**Role:** architect
**Stage:** 2
**Blocked-by:** 3, svp-roadmap-backlog-db#2
**Scope:** commands/work.md, tests/bats/test_mb_work_adapt_orchestration.bats
**Budget:** 100000

**What to do:**
- Врезка в 5f-цикл `commands/work.md` в порядке C1.1 §Приоритет: `фаза → mb-work-state.sh step
  <event> → adapt-check → pivot-check → on_max_cycles`; нормализация budget-статуса по таблице C1.1
  (сырой exit-код не передаётся). **`--run-id "$RUN_ID"` передаётся во ВСЕ вызовы `decide`/`resolve`/
  `note-clean`/`replan-gate`** (кроме `replan-gate`, у которого `--run-id` нет) — R3-001: локальный
  `RUN_ID` оркестратора (`commands/work.md:311,320`), `MB_WORK_RUN_ID` не экспортируется.
- Применение решения по C5: `stub_continue` (autonomous) → C6 (цепочка беклога **до** правки кода,
  маркер `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<path>`, флаг default-off) → `resolve
  --id "$eid" --resolution stub_continue --backlog-id "$id"` (**`--backlog-id` обязателен**, SVP-AE-007);
  `fork_user` → AskUserQuestion с четырьмя вариантами и их точными переходами (таблица C5: чекбокс не
  переворачивается на simplify/replan/skip; `skip` → `resolve --resolution skip --backlog-id "$id"`;
  `adapt_override`/`adapt_skip` — шаги work-state); `stop_run` → остановка до диспатча следующего item +
  рекомендация пересмотра спеки (REQ-010), `resolve` по нему **не** вызывается (R3-002); `note-clean` на
  успешном done без эскалации.
- **Обе ветви replan** (C1.2/C5): после выбора `replan` — второй вопрос о виде;
  `decomposition` → `--spec-topic <slug>` + регистрация child-спеки
  `mb-idea.sh "[SPEC:<group>] <slug>"` + интервью (self-interview в autonomous, REQ-006);
  `requirement_change` → child-спека **не** создаётся, `--spec-topic` не передаётся, item остаётся
  pending. Перед диспатчем item'а с историей `replan` — вызов `replan-gate` (C1.4), отказ = item не
  диспатчится, причина в summary.
- **Цепочка беклога C6 (фактический S4-C3)**: `mb-idea.sh` (→ `NEW`, без `--force`) → `list` для
  наблюдаемого состояния → кратчайший валидный путь до `READY` (`NEEDS-INFO`→`TRIAGED`→`READY`) с
  `annotate --brief` по шаблону перед `READY`; `DONE`/`WONTFIX` → halt стаб-пути; любой non-zero
  останавливает стаб-путь до правки кода. `PLANNED` не присваивается никогда (нет в алфавите S4-C3).
- Финальный summary прогона: каждая эскалация, каждый стаб с беклог-элементом и драйвером,
  `degraded_guards`, коррекции resolution, незакрытые skip-item'ы, отказы `replan-gate` (REQ-008).

**Eval:** `bats tests/bats/test_mb_work_adapt_orchestration.bats` — red: врезки развилки в commands/work.md нет, adapt-check не предшествует pivot-check; exit: 1; output~: not ok [0-9]+ .*orchestration_adapt_check_precedes_pivot_check

**Testing (TDD — tests BEFORE implementation):**
- bats (структурные проверки контракта врезки + прогон по фикстурному банку, без ручных сценариев):
  порядок adapt-before-pivot и step-before-adapt; все четыре варианта C5 с их переходами;
  **отдельный кейс на каждую ветвь replan**: `decomposition` регистрирует child-спеку и допускается
  гейтом при неизменённых требованиях, `requirement_change` child-спеку не создаёт и до правки
  `requirements.md` гейтом не допускается (`requirements_unchanged`); autonomous stub-путь: цепочка
  беклога исполнена до маркера, элемент доведён до `READY`, повторная эскалация с тем же заголовком
  переиспользует существующий `I-NNN` без падения на недопустимом переходе, `WONTFIX`-элемент
  останавливает стаб-путь; skip не переворачивает чекбокс и попадает в summary; каскад-стоп
  останавливает прогон до следующего item; summary перечисляет стабы, эскалации, degraded_guards и
  отказы гейта.

**DoD:**
- [ ] Развилка встроена по C5/C6; обе ветви replan разведены и гейтованы; bats green (был red); scenarios 3–10 покрыты тестами, не ручной проверкой
- [ ] Цепочка беклога исполняет фактический S4-C3 revision 4 (`annotate` поставлен, X5-01 SATISFIED; жёсткая зависимость `Blocked-by: svp-roadmap-backlog-db#2`, второй writer беклога не заводится)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Verify-гейт стабов

**Covers:** REQ-009
**Role:** qa
**Stage:** 2
**Blocked-by:** 4
**Scope:** agents/plan-verifier.md, commands/work.md, scripts/mb-work-adapt.sh, tests/bats/test_plan_verifier_stub_gate.bats
**Budget:** 60000

**What to do:**
- `mb-work-adapt.sh verify-stub --repo <root> --diff-file <path> --backlog <path>` по C1.5.
  Структурные проверки: маркер → существующий `I-NNN` в backlog.md; маркер на комментарий/
  docstring-строке; токен флага в том же файле вне строки маркера; голый
  `NotImplementedError`/`TODO`/`FIXME`/`...` без маркера → violation.
- **Поведенческое доказательство ограждённости**: драйвер из `eval=<path>` запускается дважды из
  `--repo` через **portable `mb_adapt_bounded_run 120 <driver>`** (R3-006: `timeout` → `gtimeout` →
  Bash 3.2 watchdog с TERM→KILL — стоковый macOS не несёт ни `timeout`, ни `gtimeout`; тот же приём, что
  `scripts/mb-work-codex-preflight.sh:46-65`); без `<NAME>` драйвер обязан напечатать
  `MB-ADAPT-STUB-PATH: baseline` и выйти 0, с `<NAME>=1` — `MB-ADAPT-STUB-PATH: staged` и выйти 0. Все
  timeout-исходы нормализуются в violation `stub_eval_timeout`. Коды violation: `missing_stub_eval`,
  `flag_default_on`, `flag_does_not_gate_stub`, `stub_eval_failed`, `stub_eval_timeout`; драйвер не
  найден/не исполняем → exit 2 fail-loud.
- JSON-выход со списком стабов (`file`, `backlog_id`, `flag`, `eval`) и violations; exit 0/1/2.
- `agents/plan-verifier.md` + verify-шаг `commands/work.md` вызывают `verify-stub` и трактуют exit 1
  и exit 2 как FAIL задачи (REQ-009); отчёт перечисляет валидные стабы с их беклог-элементами и
  драйверами; полнота docstring остаётся ревью-суждением и машинным фактом не объявляется.

**Eval:** `bats tests/bats/test_plan_verifier_stub_gate.bats` — red: субкоманды и гейта нет, default-on флаг проходит верификацию; exit: 1; output~: not ok [0-9]+ .*stub_gate_default_on_flag_fails

**Testing (TDD — tests BEFORE implementation):**
- bats на фикстурах: маркер + флаг + драйвер + существующий `I-NNN` → PASS; **default-on**
  (драйвер печатает `staged` без флага) → FAIL; **маркер вне doc-строки** (в исполняемом коде) →
  FAIL; **токен флага не управляет путём** (оба прогона печатают `baseline`) → FAIL; отсутствует
  `eval=` в маркере → FAIL; беклог-ID не существует в backlog.md → FAIL; голый
  `NotImplementedError`/`TODO` без маркера → FAIL; флаг только в строке маркера → FAIL; драйвер
  падает → FAIL с точным кодом; драйвер не исполняем → exit 2; два валидных стаба → оба перечислены в
  summary; usage-ошибка → exit 2; shellcheck clean.
- bats (**R3-006 portable timeout**): прогон с `PATH` **без** `timeout` и `gtimeout` и зависшим
  драйвером → `mb_adapt_bounded_run` завершает его Bash-watchdog'ом (TERM→KILL) в пределах бюджета,
  гейт даёт violation `stub_eval_timeout` (не виснет и не падает по отсутствию `timeout`); Bash 3.2.

**DoD:**
- [ ] C1.5 + гейт в верифаере; default-on и неограждённый стаб доказуемо не проходят; bats green (был red)
- [ ] Bounded-run портабелен (R3-006): без `timeout`/`gtimeout` работает Bash-watchdog, `stub_eval_timeout` наблюдаем; Scope включает `commands/work.md` (R3-005)
<!-- /mb-task:5 -->
