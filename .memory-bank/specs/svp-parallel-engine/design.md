# Design: svp-parallel-engine

> Слайс S3 (blocked by S2 — потребляет tasks.md v2 Stage/Blocked-by/Scope/Eval/Budget и грамматики
> Blocked-by/Scope, зафиксированные в `svp-sdd-core/design.md` C1). Контракты и Eval-декларации
> (D-05); код — в work-фазе.
> Ревизия 3 (2026-07-17): закрыты находки круга 2 codex-ревью.
> • **SVP-PE-009** — решения оркестрации вынесены из промпта в детерминированный scheduler-CLI (C7);
>   `commands/work.md` только исполняет его actions.
> • **SVP-PE-008 + AGR-020** — ревизия 2 ошибочно сузила full mode до Claude Code вопреки D-07;
>   восстановлен полный intra-session scope через host-dispatch-адаптер (C8) на **четырёх** хостах
>   (Claude Code, Pi, OpenCode, **Cursor** — AGR-020 отменил сужение D-07 до трёх хостов); role +
>   agent-name передаются раздельно (OpenCode/Pi role-routing реально провязывается, resolver — в
>   Scope Task 10); `platform_limited` ключуется на фактическом резолве маршрута (`--probe`), а не на
>   списке хостов.
> • **SVP-PE-004** — C2 получил полный исполнимый контракт (stdout-грамматика на каждый исход,
>   lock-recovery через liveness-протокол S4-C6, bounded retry с точными числами).
> • **SVP-PE-006** — алгоритм пересечения двух Scope-списков потребляется из S2-C1 целиком
>   (символьный DP), собственное сужение грамматики удалено; кандидаты одного фронтира проверяются
>   попарно, а не только против running.
> • **SVP-PE-001** — граница рубежей зафиксирована явно: spec-время — S2 (REQ-052), runtime — S3.
> • **R2-001** TTL стал единым явным входом C1 и C2 · **R2-002** C4 стал исполнимым контрактом ·
>   **R2-003** назначен producer поверхности изменений (C6) с `unavailable`-семантикой ·
>   **R2-004** C5 потребляет компаратор S4-C2 целиком, roadmap больше не резервная БД зависимостей ·
>   **R2-005** ACK за чужую сессию не генерируется · **R2-006** «6 спек» → 8 child-слайсов.

## Architecture

Четыре слоя, граница между ними — исполнимая:

1. **Детерминированные сеймы (скрипты)** — вся логика решений:
   `mb_work_items.py --frontier` (C1: DAG + claims + Scope-дизъюнктность, fail-fast на цикле) ·
   `scripts/mb-work-claims.sh` (C2: claim/release/release-stale/list) ·
   `scripts/mb-work-scope-check.sh` (C3: diff vs Scope) ·
   `scripts/mb-work-state.sh configure-mode` (C4: режимы прогона) ·
   `scripts/mb-work-resolve.sh --group --json` (C5: члены группы) ·
   `scripts/mb-work-diff.sh --scope-paths` (C6: поверхность изменений) ·
   `scripts/mb_parallel_scheduler.py` (C7: планировщик — единственный источник решений) ·
   `scripts/mb-work-dispatch.sh` (C8: маршрут диспатча под активный хост).
2. **Prompt** `commands/work.md` — **исполнитель, а не решатель** (REQ-014): вызывает C7 `next`,
   исполняет напечатанные actions (`dispatch|wait|judge|escalate|done`), возвращает результат через
   C7 `complete|fail`. Никаких собственных эвристик выбора задач, слотов и очередей.
3. **Конфиг** `parallel:` в `pipeline.default.yaml` (`{default: sequential, max_agents: 3,
   claim_ttl_seconds: 7200}`) + валидация в `mb-pipeline-validate.sh`.
4. **Honesty-слой** — манифесты `adapters/pi.sh`/`adapters/opencode.sh`/`adapters/cursor.sh` +
   негативные тесты (`tests/bats/test_platform_limited_honesty.bats`) переводятся на фактическое
   состояние role-routing после C8 (см. Decisions, «Ре-базлайн honesty-слоя»); Cursor-декларация
   остаётся genuine, пока транспорта Cursor нет (AGR-020).

### Рубежи DAG-цикла (закрывает SVP-PE-001)

Умбрелла REQ-022 требует отклонять цикл **на двух рубежах**
(`sdd-vision-pipeline/design.md` § DAG слайсов, строка про REQ-022):

| Рубеж | Владелец | Контракт | Когда срабатывает |
|---|---|---|---|
| Spec-валидация (до принятия спеки) | **S2** | `svp-sdd-core` REQ-052 + `mb-spec-validate.sh` | `/mb sdd`, `/mb verify`, CI |
| Runtime-построение фронтира | **S3 (этот слайс)** | REQ-013 + C1 | каждый `--frontier` до claim/dispatch |

S3 **не** берёт на себя spec-время: `mb-spec-validate.sh` не входит в Scope ни одной задачи этого
слайса. REQ-013 — вторая линия обороны для случаев, до которых spec-валидация не доезжает
(легаси-спеки, ручная правка `tasks.md` после принятия, межспековые рёбра `<topic>#<n>`, чей граф
целиком виден только в runtime). `covers_umbrella` сохраняет REQ-022 именно потому, что рубежа два,
и этот — один из них.

## Interfaces

### C1. `mb_work_items.py <tasks-or-plan-path> [--frontier --claims <p> --running-scopes <p> --ttl <s> --now <unix>]`

- **Без `--frontier`**: поведение byte-identical текущему CLI (один JSON-объект на строку, та же
  схема, те же exit-коды) — этот слайс не меняет проекцию по умолчанию (заморозка — контракт S2-C2).
- **С `--frontier`**: тот же v2 tasks.md (`Stage`/`Blocked-by`/`Scope`/`Eval`/`Budget`, грамматика
  S2-C1) фильтруется/сортируется до диспатчибельного фронтира:
  - **Fail-fast на цикле DAG (REQ-013)**: до любой фильтрации весь граф `Blocked-by` (локальный +
    резолвленный межспековый) проверяется на циклы; цикл прерывает работу **до** любого решения о
    claim/диспатче.
  - **Blockers done** — `Blocked-by` (локальная `<n>` или межспековая `<topic>#<n>`) резолвится в
    статус `done`; межспековая ссылка резолвится по `tasks.md` соседней спеки в том же банке.
  - **Claim free** — у задачи нет активного claim в `--claims <jsonl-path>` (тот же JSONL, который
    мутирует C2). **Активность считается ровно тем же правилом, что в C2** (R2-001):
    `last_event(task_id).op == "claim" && (now - ts) <= ttl`. Граница `age == ttl` → **активен**
    (не stale) — в C1 и C2 идентично.
  - **Scope-дизъюнктность** — см. правило отбора ниже.
  - **Детерминированный порядок**: по возрастанию `(stage, item_no)`.
- **TTL и время — явные входы обоих потребителей** (закрывает R2-001): `--ttl <seconds>` (дефолт
  `7200`) и `--now <unix-seconds>` (дефолт — системное время). Task 4 читает
  `pipeline.yaml: parallel.claim_ttl_seconds` **один раз** и передаёт одно и то же значение в C1 и
  в C2; расхождение двух TTL структурно невозможно, потому что источник один, а оба потребителя
  принимают его явным флагом. `--ttl`/`--now` вне `^[0-9]+$` или `--ttl 0` → exit 2.
- **Отбор кандидатов по Scope** (закрывает SVP-PE-006): кандидаты обходятся в детерминированном
  порядке `(stage, item_no)`; кандидат попадает во фронтир, только если его `Scope` дизъюнктен
  **(а)** с каждым активным running-claim из `--running-scopes <json-file>` (JSON-массив
  `{task_id, scope: [...]}`) **и (б)** с каждым кандидатом, уже отобранным в этот же фронтир.
  Пересечение — не ошибка, а сериализация (задача просто не входит в этот фронтир).
- **Грамматика элемента — restricted glob S2-C1, не полный POSIX** (S2-C1 revision 4, S2-X-01):
  литералы + `*` внутри сегмента (не пересекает `/`) + сегмент `**`; запрещённые метасимволы
  `?`/`[`/`]`/`{`/`}`/escape/запятая-в-элементе → malformed, парсер даёт **exit 2** (та же пятёрка
  `src/?.py`/`src/[ab].py`/`src/{a,b}.py`/`src/\*.py`/`src/a,b.py`, что T1 owner-парсера).
- **Семантика пересечения — S2-C1 целиком, без сужения**: два Scope-списка конфликтуют ⟺ хотя бы
  одна пара паттернов имеет непустое пересечение языков; считается символьно, без обращения к ФС
  (`**` — DP по сегментам; внутри сегмента — DP по символам, `*` = любая подстрока без `/`, литералы
  пересекаются только при равенстве). Контрактная таблица кейсов — в `svp-sdd-core/design.md` C1;
  тесты Task 1 обязаны прогнать её целиком, включая пять malformed-кейсов.
- **stdout**: с `--frontier` — один JSON-объект на строку, та же схема WorkItem плюс v2-ключи
  (`stage, blocked_by, scope, eval, budget`); пустой фронтир валиден и печатает пусто.
- **Exit-коды** (только режим `--frontier`; exit-коды режима по умолчанию не меняются): `0` —
  успех (фронтир вычислен, возможно пуст); `1` — цикл в графе Blocked-by, stderr печатает полный
  упорядоченный путь (`A -> B -> C -> A`); `2` — malformed вход (битый JSON в
  `--claims`/`--running-scopes`, невалидный `--ttl`/`--now`, отсутствующие v2-поля на gated-задаче);
  `3` — нерезолвящаяся межспековая ссылка `Blocked-by`.

### C2. `scripts/mb-work-claims.sh <claim|release|release-stale|list> --mb <bank> [--task <id>] [--session <id>] [--ttl <s>] [--now <unix>]`

**Состояние**: append-only JSONL `<bank>/tmp/work-claims.jsonl`; строка — одно событие
`{"task_id","session_id","ts":<unix>,"op":"claim|release|release_stale"}` (схема — умбрелла
Interface 2, потребляется как есть). Активный владелец `task_id` — последнее событие для этого id.

**Lock — потребляется, не изобретается** (закрывает SVP-PE-004 lock-recovery, умбрелла Interface 2 +
S4-C6): мутации берут `mb_lock_acquire "<bank>/tmp/.work-claims.lock" 5 30` из `scripts/_lib.sh`
(владелец S4-C6) и снимают через `mb_lock_release "<lock>" "$token"`; `trap` — на EXIT/INT/TERM.
**Пятая реализация лока в репо не пишется, и fallback-ветки «если S4-C6 ещё не отгружён» больше нет**
(умбрелла R3-003 + S4 § Cross-slice requests #4): helper C6 обязан существовать ДО Task 2 — это
**жёсткое task-level ребро** `svp-parallel-engine#2 → svp-roadmap-backlog-db#2`, зафиксированное в
`Blocked-by:` Task 2; Scope Task 2 `_lib.sh` не включает. S4 (ICE 432) идёт раньше S3 (252), поэтому
ребро согласуется с порядком.

- **Bounded retry — точные числа**: `timeout = 5` итераций по `sleep 1` (потолок ожидания 5 с) →
  не взят ⇒ exit 3. `ttl = 30` — **исключительно** для owner-less окна (лок есть, ни одного `owner.*`
  внутри нет — окно между `mkdir "<lock>"` и созданием маркера `owner.<token>`), никогда не общий
  путь reclaim.
- **Recovery осиротевшего лока — по liveness, механизм владельца S4-C6 дословно** (owner-marker +
  targeted `rmdir`, closes CPR-G/umbrella R3-001): победитель атомарного `mkdir "<lock>"` создаёт
  РОВНО один маркер `<lock>/owner.<token>`, `<token> = PID-RANDOM`. При доказанно мёртвом владельце
  `D` (`kill -0` провален) reclaim = `rmdir "<lock>/owner.<D>"` (удаляет ТОЛЬКО маркер мёртвого токена;
  `ENOENT` = уже реклеймлено другим — безвредно) → `rmdir "<lock>"` (проходит ТОЛЬКО на пустом; `ENOTEMPTY`
  = внутри уже появился свежий `owner.<Z>` живого владельца → **отступить**, ничего не тронув) → повтор
  `mkdir` наравне с контендерами. **Никаких `mv`/`rm -rf` в reclaim**: `mv`-реклейм ревизии 3 отменён
  владельцем — он всё ещё допускал двух писателей (умбрелла R3-001). PID-reuse (PID парсится и жив) →
  **консервативный НЕ-reclaim** (громкий timeout, ноль записей: потеря доступности, не корректности).
  Это закрывает crash/SIGKILL, на котором `trap` не исполняется.
- **Согласованное чтение `list`** (закрывает SVP-PE-004 list-контракт, умбрелла Interface 2): `list`
  сначала читает snapshot **без лока**. Если единственная аномалия — оборванная (partial JSONL)
  **последняя непустая** строка (след конкурентного append), команда берёт `mb_lock_acquire` с теми же
  timeout/stale-параметрами, перечитывает файл **ровно один раз** под локом и освобождает лок. Если
  после перечитывания хвост всё ещё partial **или** повреждена не-хвостовая строка → диагностический
  JSON в stderr, **exit 2**. Обычный успешный `list` лок **не берёт** — противоречие ревизии 3 (одна
  строка «перечитать под локом», другая «лок не берётся») снято: лок берётся ТОЛЬКО для перечитывания
  оборванного хвоста.

**Машинный вывод — ровно один JSON-объект на мутацию** (закрывает SVP-PE-004 stdout + SVP-PE-009
claim handoff):

```
{"op":"<op>","task_id":"<id>","session_id":"<id>","status":"<status>","claim_token":"<session_id|null>","released":["<id>",…]}
```

- **`claim_token`** (закрывает SVP-PE-009): равен `session_id` **только** при `status=claimed`
  (успешный `claim`); во всех остальных статусах (`occupied`/`released`/`not_owner`/`released_stale`/
  `not_stale`) — `null`. Scheduler C7 берёт `claim_token` из результата `claim` и кладёт его в
  `dispatch`-action (claim записан ДО диспатча by construction, C7).

| Вызов | Условие | `status` | exit |
|---|---|---|---|
| `claim --task --session` | нет события / последнее `release`\|`release_stale` / stale `claim` | `claimed` | 0 |
| `claim --task --session` | активный не-stale `claim` (любой сессии) | `occupied` | 1 |
| `release --task --session` | последнее событие — `claim` той же `session_id` | `released` | 0 |
| `release --task --session` | чужая сессия / нет активного claim | `not_owner` | 1 |
| `release-stale --task` | последнее событие — `claim` старше TTL | `released_stale` | 0 |
| `release-stale --task` | claim активен / не claimed | `not_stale` | 1 |
| `release-stale` (без `--task`) | bulk: по одному событию на каждую stale-задачу | `released_stale` | 0 (идемпотентно, в т.ч. на пустом) |

- `released` — C-сортированный список снятых `task_id`; непуст только у `release-stale`
  (для bulk — все снятые; у одиночного — ровно один). Для `claim`/`release` — `[]`.
  У bulk-вызова `task_id` = `""`, каждая задача снимается своей lock-защищённой мутацией.
- `list [--task <id>]` — C-сортированный JSONL активных (не-stale) claim'ов, по объекту на строку;
  обычный успешный `list` **лок не берёт** (read-only snapshot); оборванный хвост → однократный reread
  под локом (см. «Согласованное чтение `list`» выше); пустой список печатает пусто, exit 0.
- **TTL/время**: `--ttl <seconds>` (дефолт — константа скрипта `DEFAULT_CLAIM_TTL_SECONDS=7200`,
  S3-A-01) и `--now <unix-seconds>` для детерминированных тестов; правило staleness идентично C1.
- **Обязательность аргументов**: `--session` обязателен для `claim`/`release`; `--task` обязателен
  для `claim`/`release`, опционален для `release-stale`/`list`. Нарушение → exit 2.
- **Exit-коды**: `0` успех/list · `1` допустимый отказ state-machine (`occupied`/`not_owner`/
  `not_stale`) · `2` usage / невалидный `--ttl`/`--now` / порча состояния · `3` lock-timeout.
- **Гарантия от гонки**: read-validate-append целиком внутри лока, поэтому два конкурентных `claim`
  одного `task_id` никогда оба не увидят «владельца нет» — второй перечитывает свежее событие и
  проигрывает (`occupied`, exit 1). Доказывается настоящим конкурентным race-тестом (Task 2).

### C3. `scripts/mb-work-scope-check.sh --task <id> --scope-json <json-array> --collector-status <ok|unavailable> [--diff-file <path>] [--collector-reason <string>]`

- По образцу `mb-work-protected-check.sh` — детерминированная сверка поверхности изменений с Scope.
- `--scope-json`: JSON-массив `Scope`-элементов задачи в **грамматике S2-C1, потребляемой целиком**
  (закрывает SVP-PE-006/S2-R2-001). Грамматика владельца — **restricted glob**, а НЕ полный POSIX-glob
  (S2-C1 revision 4, `svp-sdd-core/design.md` C1): разрешены ТОЛЬКО литеральные символы пути, `*`
  внутри одного сегмента (ноль и более символов, никогда не пересекает `/`; допустим в любой части
  сегмента — `scripts/*.sh` валиден) и целый сегмент `**` (ноль и более сегментов). Строка без
  метасимволов = точный путь; `dir/**` — лишь частный случай рекурсивного префикса, а не единственная
  допустимая форма. **Запрещённые метасимволы** `?` `[` `]` `{` `}` backslash-escape `\` и запятая
  внутри элемента (`,` — только CSV-разделитель) — malformed: `src/?.py`, `src/[ab].py`, `src/{a,b}.py`,
  `src/\*.py`, `src/a,b.py` → **exit 2** (та же пятёрка негативных кейсов, что T1 парсера S2). Абсолютные
  пути, `..`, пустые элементы и negation `!` → exit 2. **Никаких дополнительных ограничений формы сверх
  S2-C1 потребитель не вводит** — прежняя формулировка «либо точный файл, либо directory-префикс с
  суффиксом `/**`» была запрещённым сужением и удалена (S2-C1 нормативно запрещает и сужать, и расширять
  грамматику; термин «POSIX glob» ревизии 2 заменён на **restricted glob** синхронно с владельцем,
  S2-X-01).
- **`--collector-status` — обязательный вход handoff C6→C3** (закрывает R2-003): `ok` требует `--diff-file`
  (newline-separated repo-relative пути — выход C6 `--scope-paths`; `--collector-reason` запрещён),
  пути нормализуются относительно git root — зеркалит S2-C1. `unavailable` **запрещает** `--diff-file`,
  требует `--collector-reason <code>` (∈ `no_git|not_a_repo|read_error|baseline_unreachable`) и даёт
  вывод `{"task_id":"<id>","scope_status":"unavailable","outside":[],"reason":"<collector-reason>"}`,
  exit 3. Так поверхность изменений либо собрана и сверена, либо честно объявлена несобранной — пустой
  diff за «изменений нет» из неуспешного сбора не выдаётся.
- stdout (при `--collector-status ok`): один JSON-объект
  `{"task_id":"…","scope_status":"ok|violation","outside":[…]}`.
- **Enum согласован с потребителями без преобразования** (закрывает R2-003): `violation` скармливается
  S5-C1 через `--scope-status`; `unavailable` **не** маршрутизируется в S5 (владелец S5-C1 запускает
  ADaPT только на `scope_status == violation`), а обрабатывается напрямую scheduler'ом C7 (см. C6/C7).
- Exit: `0` ok · `1` violation · `2` usage/malformed вход/запрещённая комбинация флагов · `3`
  unavailable (`--collector-status unavailable`).
- **Пустой `outside` при `scope_status=ok` допустим только после успешного сбора C6** (`--collector-status
  ok` + непустой валидный `--diff-file`). Пустой diff-file из неуспешного сбора невозможен: C6 в этом
  случае даёт exit 3, а оркестратор вызывает C3 с `--collector-status unavailable`, а не с пустым diff.

### C4. `scripts/mb-work-state.sh configure-mode --mb <bank> [--run-id <id>] [--execution …] [--intervention …] [--answer-execution …] [--answer-intervention …] [--target-kind group|single] [--size-status ok|near|over|unknown] [--default-execution …] [--default-intervention …]`

Исполнимый контракт выбора режима (закрывает R2-002; REQ-002/умбрелла REQ-043). Флаги и состояние
следуют конвенциям существующего скрипта (`--mb`/`--run-id`, а не `--state <path>`).

- **Когда вопрос обязателен**: `--target-kind group` — **всегда**; `single` — только когда target
  «большой». **Критерий «большого» задан родителем, а не выдуман здесь**: умбрелла REQ-043 —
  «size estimate exceeds the spec budget under the same deterministic size rubric as REQ-016».
  Исполнимо это ровно один способом: `bash scripts/mb-estimate-check.sh --spec <topic>` (S2-C3)
  печатает `spec=ok|near|over`; **large ⟺ `spec=over`** (> 1 000 000 токенов — та же граница, что
  D-35 держит hard stop'ом). `near` (900k–1M) — advisory, вопрос не запускает.
  Оркестратор передаёт результат как `--size-status`; недоступный/неразрешимый чекер (exit 2,
  план-target без спековой оценки) → `--size-status unknown` ⇒ **не large**, вопрос не задаётся,
  один громкий stderr-note. Порог `item-count >= 3` из proposed_fix ревью **отклонён**: он
  противоречит REQ-043 (см. Decisions).
- **Почему `--size-status` — вход, а не собственный вызов чекера** (проверено на репо:
  `scripts/mb-estimate-check.sh` сегодня **не существует** — базовый скрипт создаёт S1-C1,
  режим `--spec` добавляет S2-C3): C4 принимает уже вычисленный статус, поэтому Task 8 не
  блокируется чужими слайсами, а `unknown` даёт честную деградацию, если чекера ещё нет. Вызов
  чекера принадлежит оркестратору (Task 4). В DAG группы S1 (ICE 504) и S2 (400) идут раньше
  S3 (252), и S3 уже `blocked_by: [svp-sdd-core]`, поэтому к моменту Task 4 чекер существует;
  `unknown` остаётся страховкой, а не основным путём.
- **Precedence (первый хит побеждает, применяется НЕЗАВИСИМО к каждой оси — закрывает R2-002)**:
  `explicit CLI` (`--execution`/`--intervention`) → `сохранённый state` → `интерактивный ответ`
  (`--answer-execution`/`--answer-intervention`) → `pipeline default` (`--default-*`). Отдельные
  аргументы для ответа обязательны, потому что без них C4 не мог принять ответ AskUserQuestion, хотя
  precedence его называл (дефект ревизии 3). `--answer-*` представляют ответы **только текущего**
  интерактивного запроса и допустимы лишь для group/large; пара `--answer-execution` +
  `--answer-intervention` присутствует **целиком либо отсутствует**, неполная пара → exit 2.
- **Enum**: `--execution sequential|parallel`; `--intervention hitl|autonomous` — **канонические
  значения, на которые ссылается S5-C1** (`auto`→`autonomous`, `interactive`→`hitl` — алиасы;
  иное → exit 2).
- **stdout**: `{"execution":"…","intervention":"…","source":"cli|state|answer|config"}`.
- **Exit**: `0` успех · `2` невалидный вход, либо обязательный ответ не получен (group/large без
  явного CLI и без ответа) — молчаливый дефолт в этом случае запрещён.
- **Неизменность**: state хранит оба режима и `source`; после первого успешного выбора они
  неизменны в пределах прогона (повторный `configure-mode` возвращает сохранённое со
  `source=state`, кроме явного CLI-override).

### C5. `scripts/mb-work-resolve.sh --group <slug> --json --mb <bank>` (group execution)

- Дефолтная single-target резолюция остаётся **byte-identical** — контракт добавляет только новый,
  явно опциональный режим (регрессия обязательна: `mb-work-plan.sh` не трогается).
- **Frontmatter — единственный авторитет порядка** (закрывает R2-004). Источники member-полей —
  **по владельцу S4-C2 (S4 § Cross-slice requests #2)**: `group`/`ice`/`pin`/`blocked_by` — из
  `specs/<topic>/requirements.md` (схема S4-C1); **`created` — из `context/<topic>.md` frontmatter**
  (не из `requirements.md` — прежнее чтение `created` из requirements.md было расхождением источников,
  устранено). Двух источников `created` быть не должно.
  **`roadmap.md` не парсится этим контрактом вообще**: S4-C2 объявляет Group-секции роадмепа
  *рендером* frontmatter'а внутри autosync-fence и прямо запрещает обратный парсинг (round-trip
  drift); ручные `## Group:`-заголовки вне fences никогда не данные (S4-A-02). Прежняя «деградация
  до roadmap-таблицы» была изобретением ревизии 2 — S3-A-05 и REQ-009 требуют деградации до
  **упорядоченного списка спек**, а не до второй БД зависимостей.
- **Порядок — компаратор S4-C2 целиком, без собственного варианта** (директива владельца S4):
  раундовый Kahn по `blocked_by`; на каждом раунде frontier делится на `prioritized` (есть валидный
  `ice` ИЛИ `pin`) и `legacy_tail` (ни `ice`, ни `pin` — сюда же попадают **отсутствующий и
  невалидный** `ice`, т.е. `ice=null`); `prioritized` сортируется тотальным компаратором
  **`pin` ↑ → `score` ↓ → `created` ↑ → `topic` ↑ → `rel` ↑**; `legacy_tail` сохраняет исходный
  порядок скана и печатается после `prioritized`. **Общий физический файл фикстур —
  `tests/fixtures/svp_group_ordering.json`** (именуется дословно и в S4-C2/Task 6, и здесь/Task 5) с
  четырьмя каноническими кейсами (duplicate pin / missing ice / равный ice / invalid ice); порядок
  topic'ов **byte-identical** у roadmap-рендера (S4) и resolver'а (S3) — обязателен.
- **stdout**: один JSON-объект
  `{"group":"<slug>","degraded":<bool>,"reason":"<code|null>","members":[{"topic","tasks_path","ice":<int|null>,"pin":<int|null>,"created":"<YYYY-MM-DD|null>","blocked_by":[…]}]}`.
  Поле `ice` — **вычисленный score (int)** из компонент `{impact, confidence, ease}` (умбрелла
  Interface 4 / S4-C1, score = произведение), либо **`null`** при отсутствующем/невалидном `ice`
  (такой член — `legacy_tail`, S4-C2 § Cross-slice #2). `pin` и `created` включены обязательно — без
  них компаратор S4-C2 невоспроизводим у второго потребителя.
- **Деградация — ровно одна ступень**: у всех членов есть `group`, но у кого-то нет `blocked_by` ⇒
  рёбра зависимостей не выдумываются: печатается ICE-упорядоченный список (компаратор S4-C2, `ice=null`
  в `legacy_tail`) с `"degraded":true,"reason":"blocked_by_unavailable"` (exit 0). Это и есть «ordered
  spec list» REQ-009/S3-A-05.
- **Exit** (выровнено под S4-C2, закрывает R2-004): `0` успех (в т.ч. degraded) — сюда же
  **отсутствующий и невалидный `ice`**: член получает `ice=null` и уходит в `legacy_tail`, невалидный
  `ice` дополнительно даёт stderr-warning, но exit не меняется (missing/invalid ice больше НЕ exit 2/3) ·
  `2` неизвестная группа/член **или** отсутствующий `group` у члена — stderr печатает C-сортированный
  список недостающих полей · `3` malformed метаданные **`pin`/`created`/`blocked_by`** (битый `ice` в
  exit 3 более не входит — он legacy-tail) · `4` цикл в `blocked_by` группы — stderr печатает полный
  путь цикла (тот же fail-fast, что C1, уровнем выше).
- Потребитель — C7 (scheduler); `--group --json` больше никем не вызывается.

### C6. `scripts/mb-work-diff.sh --scope-paths --run-id <id> [--baseline <ref>] [--mb <path>]`

Назначенный **production producer** поверхности изменений (закрывает R2-003). Сегодня такого
producer'а нет: `mb-work-diff.sh` fail-safe по контракту (`exit 0` всегда, `scripts/mb-work-diff.sh:29-35`),
использует `git diff` без untracked (`:111-127`) и при отсутствии git печатает пустой stdout
(`:89-99`) — то есть недоступный git сегодня неотличим от «изменений нет». Для Scope-гарда это тихий
обход, поэтому новый режим **не наследует fail-safe**.

- Печатает **C-сортированное объединение без дубликатов**: modified · staged · deleted ·
  rename (обе стороны — source и destination) · untracked. Пути — repo-relative от git root.
- **`--scope-paths` — единственный режим с fail-fast**: нет git-бинаря / не work tree / ошибка
  чтения индекса ⇒ **exit 3** + stdout `{"status":"unavailable","reason":"<code>"}`
  (`reason` ∈ `no_git|not_a_repo|read_error|baseline_unreachable`). Пустой список никогда не
  выдаётся за «изменений нет», если сбор не удался.
- Успешный сбор с нулём путей ⇒ exit 0, пустой stdout (легальный «изменений нет»).
- **Режимы без `--scope-paths` остаются byte-identical** (включая fail-safe exit 0) — существующие
  потребители verify/judge не меняются; регрессионный тест обязателен.

### C7. `scripts/mb_parallel_scheduler.py <init|next|complete|fail> --run-id <id> [--source <path>] [--group <slug>] [--max-agents <n>] [--execution …] [--intervention …] [--task <id>] [--mb <path>]`

Планировщик — **единственный источник решений** (закрывает SVP-PE-009; REQ-014). Оркестрация
перестаёт быть прозой в промпте: `commands/work.md` вызывает `next` и исполняет напечатанное.

- **Состояние — машинно-проверяемая схема** (закрывает SVP-PE-009): файл
  `<bank>/tmp/parallel-runs/<run-id>.json` (пишет только оркестратор, D-23; запись — temp-file +
  atomic `rename`, никогда не in-place):

  ```json
  {"run_id":"<uuid>","source":"plan|spec|group","execution":"sequential|parallel",
   "intervention":"hitl|autonomous","max_agents":<int>,
   "tasks":{"<task_id>":{"status":"pending|claimed|running|awaiting_judge|done|failed|escalated",
     "role":"<semantic-role>","agent":"<mb-agent>","prompt_file":"<path>","claim_token":"<token|null>"}},
   "active_judge":"<task_id|null>","problems":[]}
  ```

- `init` — фиксирует source/группу (через C5), режимы (через C4), `max_agents`; exit 2 при
  невалидном входе.
- `next` — печатает **один JSON-объект**: `{"run_id":"…","actions":[…]}`, `actions` C-сортированы по
  `(kind, task_id)`. Batch может содержать **только** `dispatch`; `wait`/`judge`/`escalate`/`done`
  выдаются **по одному**. Схема каждого action (закрывает SVP-PE-009):
  - `dispatch` — `{"kind":"dispatch","task_id","role":"<semantic-role>","agent":"<mb-agent>","prompt_file":"<path>","claim_token":"<token>"}`
    (`role` — семантическая роль WorkItem, напр. `backend`; `agent` — конкретное имя, напр. `mb-backend`;
    оба нужны host-адаптеру C8, SVP-PE-008);
  - `wait` — `{"kind":"wait","task_id":null,"reason":"slots_full|blocked|awaiting_ack","blocked_by":[…]}`
    (фронтир непуст, но слоты заняты / все блокированы / ожидается ACK, REQ-017);
  - `judge` — `{"kind":"judge","task_id"}`; **не более одного `judge` одновременно** в пределах
    прогона (REQ-011) — сериализация обеспечивается здесь, а не дисциплиной промпта;
  - `escalate` — `{"kind":"escalate","task_id","reason":"scope_violation|scope_unavailable|dispatch_failed|task_failed"}`
    (вход S5-C1 **только** при `reason=scope_violation`; `scope_unavailable` — прямой escalate
    scheduler'а без вызова S5, см. ниже);
  - `done` — `{"kind":"done","task_id":null}` — работы не осталось.
- **Обязательный порядок внутри `next`** (иначе dispatch не выдаётся): C1 (фронтир) → Scope-отбор →
  C2 `claim` → только потом `dispatch`-action с уже полученным `claim_token` (= `claim_token` из
  результата C2, SVP-PE-009). Claim, таким образом, записан **до** диспатча by construction.
- **`max_agents`**: число `dispatch`-действий за один `next` ≤ (max_agents − активные claim'ы);
  `--max-agents 0`/нечисло → exit 2.
- `complete --task <id>` / `fail --task <id>` — принимают отчёт исполнителя (stdin JSON, строгая
  схема): `complete` → `{"dispatch_exit":0,"report":"<string>"}`; `fail` →
  `{"dispatch_exit":<nonzero-int>,"reason":"<nonempty-string>","report":"<string>"}`. Затем scheduler
  собирает поверхность изменений (C6) и вызывает scope-check (C3) по handoff:
  - C6 exit 0 → stdout в diff-file → `mb-work-scope-check.sh … --collector-status ok --diff-file <p>`;
  - C6 exit 3 → `mb-work-scope-check.sh … --collector-status unavailable --collector-reason <code>`.
  По вердикту C3: `scope_status=ok` → release claim (C2), задача `done`; `scope_status=violation` →
  единственный `escalate` с `reason=scope_violation` **в S5-C1**; `scope_status=unavailable` (C3 exit 3)
  → scheduler **напрямую** выдаёт единственный `escalate` с `reason=scope_unavailable` и **S5 не
  вызывает** (закрывает R2-003: владелец S5-C1 запускает ADaPT только на `violation`; unavailable
  эскалируется здесь, REQ-016).
- **Exit**: `0` успех · `1` допустимый отказ (например, `fail` по задаче без активного claim) ·
  `2` невалидный вход/состояние/битый stdin · `3` lock-timeout нижележащего C2.
- **Тестируемость**: `dispatch` и `judge` исполняются внешними fake'ами в тестах (Task 9 гоняет
  настоящий CLI с fake dispatcher/judge), поэтому параллельность, claim-before-dispatch и
  сериализация judge проверяются на **production-коде**, а не на модели.

### C8. `scripts/mb-work-dispatch.sh --host claude-code|pi|opencode|cursor --role <semantic-role> --agent-name <mb-agent> --prompt-file <path> [--probe]`

Host-dispatch-адаптер (закрывает SVP-PE-008; REQ-015/REQ-008). Восстанавливает **полный** intra-session
full mode D-07 на **четырёх** хостах — Claude Code, Pi, OpenCode и **Cursor** (у Cursor есть саб-агенты,
AGR-020: сужение D-07 до трёх хостов отменено), вместо сужения ревизии 2 до Claude Code.

- **Роль и имя агента передаются ОБА** (закрывает SVP-PE-008): WorkItem даёт семантическую роль
  (`backend`), а файл агента называется `mb-backend.md`, поэтому `--role <semantic-role>` (для трассы) и
  `--agent-name <mb-agent>` (конкретный агент) — раздельные входы; резолвер вызывается **именем агента**,
  а не голой семантической ролью.
- **Определение хоста**: `--host`, иначе `$MB_AGENT`, иначе `claude-code` (кодовый дефолт репо).
- **Маршруты**:
  - `claude-code` → нативный `Task`-инструмент (диспатч исполняет промпт-слой; адаптер печатает
    `{"route":"native-task",…}`, `available:true`);
  - `pi` → `bash scripts/mb-subinvoke-resolve.sh --agent pi --role "<mb-agent>"` — резолверу передаётся
    **имя агента** `<mb-agent>` (напр. `mb-backend`), потому что он ищет `agents/$ROLE.md`
    (`scripts/mb-subinvoke-resolve.sh:191`), а файла `agents/backend.md` нет — есть `agents/mb-backend.md`
    (SVP-PE-008: голая семантическая роль резолвилась бы в отсутствующий файл);
  - `opencode` → `bash scripts/mb-subinvoke-resolve.sh --agent opencode --agent-name "<mb-agent>"` —
    **резолвер расширяется Task 10**, чтобы ветка OpenCode возвращала `opencode run --agent "<mb-agent>" …`;
    сегодня она отдаёт unscoped `opencode run` без выбора агента (`scripts/mb-subinvoke-resolve.sh:294-302`),
    поэтому role-routing OpenCode «фактически не существует» до этой правки (SVP-PE-008). Отсутствие
    возможности → `status:"unavailable"`, exit 1, **без unscoped fallback**;
  - `cursor` → per-role sub-invoke Cursor (у Cursor есть саб-агенты, AGR-020/D-07). **Если транспортного
    факта Cursor в репо ещё нет** (сегодня в `scripts/mb-subinvoke-resolve.sh` и `scripts/mb-agent-caps.sh`
    ветки `cursor` нет), Cursor-арм резолвится в `available:false reason=route_absent` → **честная
    деградация `platform_limited`** как исполняемый fallback; при этом **замысел «полный режим» на Cursor
    зафиксирован требованием** (REQ-015) — Cursor-арм добавляется всюду, где перечислены Pi/OpenCode-армы
    (маршруты, `--probe`, honesty-слой), и wiring его sub-invoke-шаблона входит в Scope Task 10 наравне с
    OpenCode;
  - промпт доставляется на всех non-native маршрутах **исключительно** через `MB_FANOUT_PROMPT` (security
    seam того же скрипта: `scripts/mb-subinvoke-resolve.sh:10-18`) — никакой интерполяции промпта в шелл-код;
  - иной/неизвестный хост (в т.ч. `codex`) → маршрута нет.
- **Один промпт на диспатч**: `mb-engineering-core` + host tooling + role + work item — тот же payload на
  всех маршрутах.
- **Вывод обычного диспатча** — JSON `{"host":"<host>","agent":"<mb-agent>","status":"ok|failed|delegate_native","exit_code":<int>,"report":"<string>"}`;
  exit 0 = успешный child/`delegate_native` дескриптор, exit 3 = child failure.
- **`--probe`** — dispatch contract test: печатает
  `{"host":"…","route":"…","available":true|false,"reason":"<code|null>"}`, exit 0 при `available`,
  exit 1 иначе. **Full mode разрешается хосту только при `available:true`** — не по списку имён.
- **`platform_limited` — следствие probe, а не хардкода** (REQ-008): `available:false` ⇒ sequential +
  ровно одно предупреждение. Codex попадает сюда всегда (нет subagents — уже задекларировано
  honesty-слоем); Pi/OpenCode/Cursor — только когда opt-in расширение/маршрут не резолвится (AGR-013:
  отказ от расширения = byte-identical install; AGR-020: Cursor до появления транспорта деградирует
  честно, но остаётся в scope полного режима), а не потому, что «это не Claude Code».

## Decisions

S3-A-01…05 + D-07/08/23/24/32/33 — в context. Порядок внутри work-петли (владелец — C7):
C1 фронтир → Scope-отбор → C2 claim → C8 dispatch → report → C6 сбор поверхности → C3 scope-check →
(**S5-C1 только при `scope_status=violation`; `unavailable` → прямой `escalate` scheduler'а C7 без
вызова S5**, R2-003) → verify → judge (сериализован C7) → оркестратор пишет банк → C2 release.

- **Scope-грамматика потребляется, не ревизуется** (SVP-PE-006): C1/C3 реализуют ровно семантику
  `svp-sdd-core/design.md` C1 — включая **алгоритм пересечения двух списков** и его контрактную
  таблицу. Собственное сужение формы элемента, стоявшее в ревизии 2 C3, удалено: S2-C1 нормативно
  запрещает потребителю сужать грамматику.
- **TTL — про claim, liveness — про lock; это разные объекты** (R2-001 + умбрелла Interface 2):
  staleness **claim'а** считается по TTL (умбрелла REQ-023 «shall release stale claims by TTL» +
  REQ-005) — иначе и нельзя: `--session <id>` это run-id (uuid из `mb-work-state.sh new-run-id`), по
  нему `kill -0` невозможен в принципе. Reclaim **лока** считается по liveness владельца, потому что
  его токен — `PID-RANDOM` и PID проверяем. Единственный TTL внутри лока (`30`) — узкий fallback для
  нечитаемого `owner`-файла, к claim-TTL (`7200`) отношения не имеет. Оба числа названы явно, чтобы
  их нельзя было спутать.
- **Направление TTL-зависимости** (SVP-PE-003): дефолт claim-TTL — константа скрипта C2
  (`DEFAULT_CLAIM_TTL_SECONDS=7200`), а не значение из `pipeline.yaml`; Task 2 не блокируется
  Task 4. Конфиг-override читает Task 4 **один раз** и передаёт одно значение обоим потребителям
  (C1 `--ttl`, C2 `--ttl`).
- **Критерий «большого target» взят у родителя, а не изобретён** (R2-002): умбрелла REQ-043 привязывает
  его к «the same deterministic size rubric as REQ-016» ⇒ `spec=over` по S2-C3. Число `item-count >= 3`
  из proposed_fix ревью отклонено как противоречащее REQ-043: количество задач не является размерной
  рубрикой REQ-016 (та измеряет токены: task ≤120k / stage ≤400k / spec ~1M). `<3 задач фронтира`
  остаётся лишь **рекомендацией** внутри вопроса, не триггером вопроса.
- **Group execution — один оркестраторный прогон** (SVP-PE-010): group-target — один прогон,
  которым владеет C7, а не N независимых `/mb work`. Члены исполняются конкурентно в текущем
  worktree только после доказанной C1 попарной Scope-дизъюнктности; пересечение сериализует.
  Независимые пользовательские inter-plan-сессии остаются worktree-based по действующему правилу
  `commands/work.md` («Worktree rule»); оркестратор никогда не создаёт и не переключает worktree
  (S3-A-04).
- **ACK принадлежит принимающей стороне** (R2-005): `references/coordination.md:49` определяет ACK
  как подтверждение прочтения получателем, а `rules/RULES.md` требует ACK на freeze/handover.
  Оркестратор физически не может достоверно подтвердить чтение за ещё не ответившую сессию, поэтому
  он пишет STATUS/FREEZE/QUESTION с `awaiting_ack=true` и **никогда** не эмитит ACK от чужого имени.
  Pending-freeze имеет статус `awaiting_ack`; истечение ожидания даёт детерминированный
  `wait`/`escalate` (C7), но не синтетический ACK.
- **Full mode — по факту резолва маршрута, а не по имени хоста** (SVP-PE-008 + AGR-020): D-07 называет
  Claude Code / Pi / OpenCode, а AGR-020 добавляет **Cursor** четвёртым (у Cursor есть саб-агенты) —
  scope полного режима теперь **четырёххостовый**, «ровно трёххостовый scope» отменён. Ревизия 2 сузила
  full mode до Claude Code, сославшись на отсутствие провязки. Проверка репо (2026-07-18): примитив
  `mb-subinvoke-resolve.sh` есть для `claude-code|codex|pi|opencode`, но `--role` применяется **только к
  Pi** и ищет `agents/$ROLE.md` (`scripts/mb-subinvoke-resolve.sh:26-38,178-193`), а ветка OpenCode
  отдаёт unscoped `opencode run` без выбора агента (`:294-302`) — то есть заявленный role-routing
  OpenCode фактически отсутствует, а Pi резолвил бы `agents/backend.md` вместо `agents/mb-backend.md`.
  `adapters/pi.sh:328-340` фиксирует backlog I-121/I-122. Недостающее звено — ровно `/mb work`
  role-routing: C8 передаёт role + **имя агента** и **расширяет resolver** (Task 10 Scope) под Pi/OpenCode,
  закрывая I-121/I-122. Cursor-арм добавляется всюду; при отсутствии транспортного факта Cursor сегодня —
  честная деградация `platform_limited`, но замысел полного режима зафиксирован REQ-015 (AGR-020).
- **Ре-базлайн honesty-слоя — обязательная часть C8** (следствие SVP-PE-008 + AGR-020): сегодня
  `adapters/pi.sh` и `adapters/opencode.sh` декларируют `role-routing` в `platform_limited`, а
  `tests/bats/test_platform_limited_honesty.bats:450-451` доказывает это структурно
  (`! grep -Eq -- '--agent (pi|opencode) --role' commands/work.md`). После C8 это утверждение
  становится **ложным** для Pi/OpenCode, а мета-тест (REQ-017 adapter-parity) требует, чтобы каждый
  заявленный лимит имел genuine негативное доказательство. Поэтому Task 6 обязан: снять `role-routing`
  из `platform_limited` в `adapters/pi.sh`/`adapters/opencode.sh` там, где маршрут резолвится, заменить
  негативное утверждение позитивным dispatch-контракт-тестом (`--probe`), и вычистить соответствующие
  пары из `TESTED_PAIRS` (`:469-472`) — оставив `statusline` и codex-лимиты нетронутыми. **Cursor
  (`adapters/cursor.sh`, AGR-020)**: пока транспортного факта Cursor нет, его `platform_limited` остаётся
  genuine (probe `available:false`) и НЕ снимается; когда Cursor-транспорт появится, его декларация
  ре-базлайнится тем же правилом. Оставить старую декларацию зелёной там, где лимита больше нет, было бы
  дишонести в обратную сторону.

## Eval declarations (red → green в work-фазе)

Якоря `output~:` — **сигнатуры настоящего провала**, измеренные на этом дереве 2026-07-17
(S2-C1/REQ-055): `bats <missing>` → `not ok 1 bats-gather-tests` (exit 1) — тот же exit, что у
настоящего провала, поэтому exit-only якорь обманывается; настоящий провал bats → `not ok N <имя
теста>`. `pytest <missing>` → `ERROR: file or directory not found` (exit 4); настоящий провал pytest
→ `FAILED <nodeid>` (exit 1). Каждый якорь ниже подобран так, что **текущий вывод им не матчится**,
а вывод настоящего провала — матчится.

Строки `**Eval:**` ниже байт-в-байт совпадают с `tasks.md` (CPR-D).

- **T1** — red-условие: `--frontier` не реализован → падает тест цикла:
  **Eval:** `pytest tests/pytest/test_work_items_frontier.py` — red: `--frontier` не реализован, тест цикла падает; exit: 1; output~: `FAILED .*test_work_items_frontier\.py::test_frontier_aborts_on_cycle_before_any_claim`
- **T2** — red-условие: скрипта нет → падает race-тест:
  **Eval:** `bats tests/bats/test_mb_work_claims.bats` — red: скрипта нет, race-тест падает; exit: 1; output~: `not ok [0-9]+ .*concurrent claim`
- **T3** — red-условие: скрипта нет → падает violation-тест:
  **Eval:** `bats tests/bats/test_mb_work_scope_check.bats` — red: скрипта нет, violation-тест падает; exit: 1; output~: `not ok [0-9]+ .*out-of-scope path`
- **T4** — red-условие: оркестрации нет → падает тест «prompt только исполняет actions»:
  **Eval:** `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml && bats tests/bats/test_mb_work_parallel_orchestration.bats` — red: оркестрации нет, тест исполнения actions падает (валидатор конфига зелёный сам по себе — red даёт bats); exit: 1; output~: `not ok [0-9]+ .*orchestrator executes scheduler actions`
- **T5** — red-условие: `--group` нет → падает тест компаратора S4-C2:
  **Eval:** `bats tests/bats/test_mb_work_resolve_group.bats` — red: `--group`-режима нет, тест компаратора падает; exit: 1; output~: `not ok [0-9]+ .*S4-C2 comparator`
- **T6** — red-условие: деградации нет → падает probe-тест codex:
  **Eval:** `bats tests/bats/test_mb_work_parallel_parity.bats tests/bats/test_platform_limited_honesty.bats` — red: parity-теста нет, тест деградации codex падает; exit: 1; output~: `not ok [0-9]+ .*codex degrades`
- **T7** — red-условие: `--scope-paths` нет → падает untracked-тест:
  **Eval:** `bats tests/bats/test_mb_work_diff_scope_paths.bats` — red: `--scope-paths` не реализован, untracked-тест падает; exit: 1; output~: `not ok [0-9]+ .*untracked`
- **T8** — red-условие: `configure-mode` нет → падает precedence-тест:
  **Eval:** `bats tests/bats/test_mb_work_state_configure_mode.bats` — red: `configure-mode` не реализован, precedence-тест падает; exit: 1; output~: `not ok [0-9]+ .*precedence`
- **T9** — red-условие: scheduler'а нет → падает claim-before-dispatch:
  **Eval:** `pytest tests/pytest/test_parallel_scheduler.py` — red: scheduler'а нет, claim-before-dispatch падает; exit: 1; output~: `FAILED .*test_parallel_scheduler\.py::test_claim_recorded_before_dispatch`
- **T10** — red-условие: адаптера нет → падает probe-тест pi:
  **Eval:** `bats tests/bats/test_mb_work_dispatch.bats tests/bats/test_mb_subinvoke_resolve.bats` — red: адаптера нет, probe-тест pi падает; exit: 1; output~: `not ok [0-9]+ .*pi role route probe`

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Гонки git-состояния (урок T3 adapter-parity) | M | H | Scope-дизъюнктность обязательна; orchestrator-only банк; scoped git add; никаких stash в оркестрации |
| Claim-гонка двух сессий | M | M | read-validate-append целиком под локом S4-C6 (C2); проигравший (`occupied`) берёт следующую задачу |
| Осиротевший лок после SIGKILL запирает все мутации | M | H | liveness-reclaim (`kill -0`) + атомарный mv; PID-reuse → консервативный не-reclaim (потеря доступности, не корректности) |
| DAG-цикл (задачи или группы) не пойман до диспатча | L | H | два рубежа: S2 на spec-валидации (REQ-052), C1/C5 в runtime с печатью полного пути |
| Тихий обход Scope-гарда пустым diff'ом | M | H | C6 fail-fast (exit 3 + `unavailable`), enum доезжает до S5 без схлопывания в `ok` |
| Оркестрация «на честном слове» промпта | M | H | все решения в C7; промпт только исполняет actions; тесты гоняют настоящий CLI с fake dispatcher/judge |
| Ре-базлайн honesty-слоя сломает adapter-parity-тесты | M | M | Task 6 переводит негативное утверждение в позитивный probe-тест в том же коммите; мета-тест vocabulary остаётся согласованным |
| Group без S4-frontmatter | M | L | одна честная ступень: ICE-список с `degraded:true`; рёбра не выдумываются |

## Open questions

- TTL-калибровка по фактическим длительностям задач (после первых governed-прогонов).
