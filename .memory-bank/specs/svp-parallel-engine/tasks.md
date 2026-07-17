# Tasks: svp-parallel-engine

> Слайс S3 (ICE 252, blocked by svp-sdd-core). Eval первым (red) → реализация (green).
> Поля v2 — грамматика `svp-sdd-core/design.md` C1 (`Stage`/`Blocked-by`/`Scope`/`Eval`/`Budget`).
> Ревизия 3 (2026-07-17): задачи 7–10 добавлены закрытием находок круга 2 — producer поверхности
> изменений (R2-003), исполнимый выбор режима (R2-002), scheduler-сейм (SVP-PE-009), host-dispatch
> адаптер + ре-базлайн honesty-слоя (SVP-PE-008). ID существующих задач не перенумерованы.
> DAG: Stage 1 — T1 (фронтир); Stage 2 — T2, T3, T5, T8 (Scope попарно дизъюнктны → параллельны);
> Stage 3 — T7 (producer поверх enum C3); Stage 4 — T9 (scheduler) + T10 (host-адаптер);
> Stage 5 — T4 (провязка промпта поверх сеймов); Stage 6 — T6 (parity + honesty).
> Бюджеты: задача ≤120000, Stage ≤400000. Суммы: S1 120000 · S2 380000 · S3 70000 · S4 210000 ·
> S5 120000 · S6 90000; spec.total = 990000 (≤ ~1M, D-13).
> Якоря `output~:` — измеренные сигнатуры настоящего провала (design § Eval declarations):
> `bats <missing>` даёт `not ok 1 bats-gather-tests`, поэтому ни один якорь не матчится отсутствием
> файла.

<!-- mb-task:1 -->
## Task 1: Frontier API в парсере

**Covers:** REQ-003, REQ-013
**Role:** backend
**Stage:** 1
**Blocked-by:** none
**Scope:** scripts/mb_work_items.py, tests/pytest/test_work_items_frontier.py
**Budget:** 120000

**What to do:**
- `mb_work_items.py --frontier` по C1: blockers done ∧ claim free ∧ Scope-дизъюнктность;
  детерминированный порядок `(stage, item_no)`.
- Грамматики `Blocked-by`/`Scope` **потребляются как есть** из `svp-sdd-core/design.md` C1 —
  этот слайс их не ревизует и не сужает.
- **Пересечение Scope — алгоритм S2-C1 целиком** (SVP-PE-006): символьный DP без обращения к ФС;
  кандидат отбирается только если дизъюнктен и с running-claim'ами, и с уже отобранными
  кандидатами этого же фронтира.
- TTL/время — явные входы (R2-001): `--ttl <seconds>` (дефолт 7200), `--now <unix-seconds>`;
  активный claim ⟺ `last_event.op == "claim" && (now - ts) <= ttl` — правило идентично C2.
- Fail-fast на цикле DAG (REQ-013, runtime-рубеж умбрелла REQ-022): весь граф `Blocked-by`
  проверяется ДО любой фильтрации, claim и диспатча; exit 1 + полный упорядоченный путь в stderr.
- Без `--frontier` stdout/exit-коды остаются byte-identical текущему JSONL (контракт S2-C2).

**Eval:** `pytest tests/pytest/test_work_items_frontier.py` — red: `--frontier` не реализован, тест цикла падает; exit: 1; output~: `FAILED .*test_work_items_frontier\.py::test_frontier_aborts_on_cycle_before_any_claim`

**Testing (TDD — tests BEFORE implementation):**
- pytest: блокеры done/не-done; занятые и stale claims; пустой фронтир с блокерами (exit 0, пустой
  stdout); детерминированный порядок `(stage, item_no)`.
- pytest (контрактная таблица пересечений S2-C1, обязательна целиком): `src/**` vs `src/a.py` —
  конфликт; `src/*` vs `src/a.py` — конфликт; `src/*` vs `src/a/b.py` — дизъюнктны; `scripts/*.sh`
  vs `scripts/mb-x.sh` — конфликт; `scripts/*.sh` vs `scripts/mb-x.py` — дизъюнктны; `docs/**` vs
  `src/**` — дизъюнктны; `**` vs что угодно — конфликт.
- pytest (**restricted-glob malformed**, грамматика владельца S2-C1 revision 4 / S2-X-01): пять
  негативных кейсов `src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`, `src/a,b.py` — все пять
  отклоняются как malformed (**exit 2**); валидные `scripts/*.sh`, `dir/**`, точный путь — приняты.
  Термин «POSIX glob» не используется: грамматика — restricted glob (литералы + `*` в сегменте +
  сегмент `**`).
- pytest (два кандидата одного фронтира, SVP-PE-006): T3 `scripts/*` и T5 `scripts/*, commands/*`
  оба свободны → отбирается только T3, T5 сериализуется.
- pytest (TTL, R2-001): `--ttl 1` и `--ttl 7200`; граница `age == ttl` → claim активен;
  детерминированный `--now`; невалидный `--ttl`/`--now` → exit 2.
- pytest (REQ-013): self-cycle `A → A` и `A → B → C → A` — exit 1, stdout пуст, stderr содержит
  полный путь (`A -> B -> C -> A`), claims-файл не изменён.
- pytest: malformed вход → exit 2; нерезолвящаяся межспековая ссылка → exit 3.
- pytest-регрессия: вызов без `--frontier` byte-identical текущему выводу.

**DoD:**
- [ ] C1 реализован (`--frontier`, `--claims`, `--running-scopes`, `--ttl`, `--now`); pytest green (были red)
- [ ] Контрактная таблица пересечений S2-C1 прогнана целиком, включая пары кандидатов фронтира
- [ ] REQ-013: цикл валит фронтир до claim/диспатча с печатью полного пути цикла
- [ ] Дефолтный режим byte-identical (регрессионный тест зелёный)
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Claims-слой

**Covers:** REQ-004, REQ-005
**Role:** backend
**Stage:** 2
**Blocked-by:** 1, svp-roadmap-backlog-db#2
**Scope:** scripts/mb-work-claims.sh, tests/bats/test_mb_work_claims.bats
**Budget:** 110000

**What to do:**
- Новый `scripts/mb-work-claims.sh` по C2: `claim|release|release-stale|list`, append-only
  JSONL-события `{task_id, session_id, ts, op}` в `<bank>/tmp/work-claims.jsonl`; мутация несёт
  `claim_token` (= `session_id` при `status=claimed`, иначе `null`, SVP-PE-009).
- **Лок потребляется, не изобретается** (умбрелла Interface 2 + S4-C6):
  `mb_lock_acquire "<bank>/tmp/.work-claims.lock" 5 30` / `mb_lock_release` из `scripts/_lib.sh`;
  bounded retry — 5 итераций по `sleep 1` → exit 3; `ttl=30` — только для owner-less окна (лок есть,
  ни одного `owner.*`). **Fallback-ветки «если S4-C6 ещё не отгружён» больше нет** (umbrella R3-003 /
  S4 § Cross-slice #4): helper обязан существовать ДО Task 2 — жёсткое ребро
  `Blocked-by: svp-roadmap-backlog-db#2`; Scope Task 2 `_lib.sh` НЕ включает, пятую копию лока не писать.
- Reclaim по liveness (`kill -0`) через **owner-marker + targeted `rmdir`** (механизм владельца S4-C6
  revision 4, CPR-G): `rmdir "<lock>/owner.<D>"` мёртвого токена → `rmdir "<lock>"` только на пустом
  (`ENOTEMPTY` = свежий `owner.<Z>` живого → отступить); **никаких `mv`/`rm -rf`** (`mv`-reclaim
  отменён владельцем — допускал двух писателей). PID-reuse → консервативный не-reclaim. `trap` снимает
  лок на EXIT/INT/TERM.
- Ровно один JSON-объект на мутацию со `status` из таблицы C2; `list` — C-сортированный JSONL,
  без лока; оборванная хвостовая строка retryable, а не exit 2.
- TTL: константа `DEFAULT_CLAIM_TTL_SECONDS=7200` + флаги `--ttl`/`--now`. **Эта задача не зависит
  от `pipeline.yaml`** — конфиг-override подключает Task 4.
- Exit-коды: 0 успех/list; 1 `occupied`/`not_owner`/`not_stale`; 2 usage/битое состояние;
  3 lock-timeout.

**Eval:** `bats tests/bats/test_mb_work_claims.bats` — red: скрипта нет, race-тест падает; exit: 1; output~: `not ok [0-9]+ .*concurrent claim`

**Testing (TDD — tests BEFORE implementation):**
- bats: happy path claim → list → release; каждый исход таблицы C2 печатает свой `status` и свой
  exit (`claimed`/`occupied`/`released`/`not_owner`/`released_stale`/`not_stale`); успешный `claim`
  несёт `claim_token=session_id`, все прочие статусы — `claim_token=null` (SVP-PE-009).
- bats: release-stale одиночный (`--task`) и bulk (без `--task`, идемпотентен, exit 0 на пустом,
  `released` C-сортирован); `--session` отсутствует → exit 2.
- bats (гонка): два **настоящих конкурентных процесса** `claim` одного `task_id` → ровно один
  exit 0, ровно один активный владелец (не последовательная симуляция).
- bats (recovery, SVP-PE-004): владелец лока убит `SIGKILL` → следующий вызов реклеймит по liveness
  через `rmdir owner.<D>`+`rmdir <lock>` и проходит; живой владелец → `exit 3` без сноса лока; отставший
  reclaim'ер после того, как свежий владелец `owner.<Z>` уже захватил лок, получает `ENOENT`+`ENOTEMPTY`
  и не сносит живой лок; owner-less лок старше 30 с → снимается TTL-fallback'ом.
- bats: удерживаемый лок → exit 3 в пределах 5 с; оборванная хвостовая строка → `list` retry, не
  exit 2; порча не-хвостовой строки → exit 2.
- shellcheck clean.

**DoD:**
- [ ] C2 реализован (lock через S4-C6, схема событий, stdout-грамматика, exit-коды); bats green (были red)
- [ ] Race-тест доказывает ровно одного победителя на конкурентных процессах
- [ ] SIGKILL-владелец реклеймится по liveness; живой владелец никогда не реклеймится
- [ ] TTL работает от константы скрипта без `pipeline.yaml` (Task 2 не блокируется Task 4)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Scope-чек диффа

**Covers:** REQ-006
**Role:** backend
**Stage:** 2
**Blocked-by:** 1
**Scope:** scripts/mb-work-scope-check.sh, tests/bats/test_mb_work_scope_check.bats
**Budget:** 90000

**What to do:**
- Новый `scripts/mb-work-scope-check.sh` по C3 (по образцу `mb-work-protected-check.sh`):
  `--task <id> --scope-json <json-array> --collector-status <ok|unavailable> [--diff-file <path>]
  [--collector-reason <string>]`.
- Семантика путей — **restricted glob S2-C1 целиком, без сужения** (S2-C1 revision 4 / S2-X-01, НЕ
  полный POSIX-glob): литералы + `*` внутри сегмента (не пересекает `/`; `scripts/*.sh` валиден) +
  сегмент `**`; запрещённые метасимволы `?`/`[`/`]`/`{`/`}`/escape/запятая-в-элементе → malformed
  exit 2 (пять кейсов `src/?.py`/`src/[ab].py`/`src/{a,b}.py`/`src/\*.py`/`src/a,b.py`); абсолютные/
  `..`/negation/пустые → exit 2. Пути нормализуются от git root.
- **Handoff C6→C3** (R2-003): `--collector-status ok` требует `--diff-file` (и запрещает
  `--collector-reason`); `--collector-status unavailable` **запрещает** `--diff-file`, требует
  `--collector-reason <code>` (`no_git|not_a_repo|read_error|baseline_unreachable`), выдаёт
  `scope_status=unavailable`, exit 3.
- stdout (при ok): `{"task_id", "scope_status": "ok|violation", "outside": [...]}`; exit 0/1; вердикт
  `violation` потребляет S5-C1 через `--scope-status`. `unavailable` **не** маршрутизируется в S5 —
  его эскалирует scheduler C7 напрямую (`reason=scope_unavailable`).

**Eval:** `bats tests/bats/test_mb_work_scope_check.bats` — red: скрипта нет, violation-тест падает; exit: 1; output~: `not ok [0-9]+ .*out-of-scope path`

**Testing (TDD — tests BEFORE implementation):**
- bats: `--collector-status ok --diff-file` — ok (всё внутри Scope) → exit 0; violation → exit 1 +
  `outside` перечисляет ровно внешние пути; успешно собранный пустой diff → ok.
- bats (restricted-glob семантика S2-C1): `*` не матчит через `/`; `**` матчит; `scripts/*.sh` матчит
  `scripts/mb-x.sh` и не матчит `scripts/mb-x.py`; точный файл vs directory-префикс.
- bats (**restricted-glob malformed**, S2-X-01): `src/?.py`, `src/[ab].py`, `src/{a,b}.py`, `src/\*.py`,
  `src/a,b.py` → exit 2 (та же пятёрка, что T1); `dir/**`/точный путь — приняты.
- bats (R2-003 handoff): `--collector-status unavailable --collector-reason no_git` (без `--diff-file`)
  → `scope_status=unavailable`, exit 3; `--collector-status ok` без `--diff-file` → exit 2;
  `--collector-status unavailable` **с** `--diff-file` → exit 2; пустой успешный список ≠ unavailable.
- bats: запрещённый паттерн (абсолютный, `..`, negation, пустой) → exit 2; битый JSON → exit 2.
- shellcheck clean.

**DoD:**
- [ ] C3 реализован (`--collector-status` handoff); bats green (были red)
- [ ] Грамматика restricted glob S2-C1 не сужена и не расширена (тест `scripts/*.sh` зелёный, пять malformed → exit 2)
- [ ] Вердикт машинно-читаем: `violation` совместим с S5-C1 (`--scope-status`), `unavailable` эскалирует scheduler C7 напрямую (не S5)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Провязка оркестрации в work.md + конфиг

**Covers:** REQ-001, REQ-002, REQ-007, REQ-010, REQ-011, REQ-012, REQ-017
**Role:** architect
**Stage:** 5
**Blocked-by:** 9, 10
**Scope:** commands/work.md, references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_mb_work_parallel_orchestration.bats
**Budget:** 120000

**What to do:**
- `parallel:`-секция в `references/pipeline.default.yaml` (`{default: sequential, max_agents: 3,
  claim_ttl_seconds: 7200}`) + её валидация в `mb-pipeline-validate.sh`. `claim_ttl_seconds`
  читается **один раз** и передаётся одним значением в C1 (`--ttl`) и C2 (`--ttl`) — R2-001.
- `commands/work.md` становится **исполнителем C7** (REQ-014): вызов `mb_parallel_scheduler.py
  next` → исполнение напечатанных actions (`dispatch` через C8, `wait`, `judge`, `escalate`,
  `done`) → возврат результата через `complete|fail`. Никаких собственных решений о выборе задач,
  слотах и очереди judge — они принадлежат C7.
- Стартовые вопросы C4 через `mb-work-state.sh configure-mode`; выбор фиксируется в state.
  Размерный статус для `--size-status` оркестратор вычисляет сам: `mb-estimate-check.sh --spec
  <topic>` (S2-C3; `spec=over` ⇒ large по умбрелла REQ-043). Чекер недоступен/не разрешает
  target (план) → `--size-status unknown` + громкий stderr-note, а не молчаливое «не large».
- Оркестратор — единственный писатель банка (REQ-007): отчёты task-агентов применяет он.
- Multi-session (REQ-012/REQ-017): генерация записей `COORDINATION.md` STATUS/FREEZE/QUESTION с
  `awaiting_ack=true`; **ACK за другую сессию не генерируется никогда**; работа остаётся
  заблокированной, пока принимающая сессия сама не допишет ACK.
- Автономный режим: прерывание только на эскалациях + полный отчёт всех проблем (REQ-010).
- **Обновление текста «Worktree rule»**: group-target — один оркестраторный прогон; члены могут
  исполняться конкурентно в текущем worktree только при доказанной C1 попарной
  Scope-дизъюнктности; независимые пользовательские inter-plan-сессии остаются worktree-only;
  оркестратор никогда не создаёт/не переключает worktree.

**Eval:** `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml && bats tests/bats/test_mb_work_parallel_orchestration.bats` — red: оркестрации нет, тест исполнения actions падает (валидатор конфига зелёный сам по себе — red даёт bats); exit: 1; output~: `not ok [0-9]+ .*orchestrator executes scheduler actions`

**Testing (TDD — tests BEFORE implementation):**
- bats (настоящий C7 + fake dispatcher/judge, детерминированно):
  - оркестратор исполняет ровно те actions, что напечатал scheduler, и не выдумывает своих
    (REQ-014/REQ-001);
  - `max_agents=2` никогда не даёт больше двух одновременных воркеров (REQ-001);
  - judge-конкурентность строго 1 (REQ-011);
  - task-агент не пишет `.memory-bank/**`, оркестратор применяет ровно одну запись (REQ-007);
  - multi-session → записи `COORDINATION.md` содержат STATUS/FREEZE/QUESTION с `awaiting_ack=true`
    и **ноль ACK**; попытка самому себе ACK отвергается; до внешнего ACK — `wait` (REQ-012/REQ-017);
  - HITL останавливается на проблеме; автономный идёт до эскалации и печатает полный отчёт всех
    проблем (REQ-002/REQ-010);
  - стартовые вопросы заданы на group/large target и выбор сохранён в state (REQ-002).
- `mb-pipeline-validate.sh` принимает валидную `parallel:`-секцию и отвергает `max_agents: 0` и
  нечисловой `claim_ttl_seconds`.

**DoD:**
- [ ] Провязка + конфиг реализованы; Eval green (был red)
- [ ] Промпт не принимает решений: тест доказывает исполнение ровно actions C7
- [ ] Ни одной ACK-записи от имени другой сессии (REQ-017)
- [ ] «Worktree rule» в `commands/work.md` согласовано с group-execution
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Group-target

**Covers:** REQ-009
**Role:** backend
**Stage:** 2
**Blocked-by:** 1, svp-roadmap-backlog-db#1
**Scope:** scripts/mb-work-resolve.sh, tests/bats/test_mb_work_resolve_group.bats, tests/fixtures/svp_group_ordering.json
**Budget:** 100000

**What to do:**
- `mb-work-resolve.sh --group <slug> --json --mb <bank>` по C5 — **новый опциональный режим**;
  дефолтная single-path резолюция остаётся byte-identical (`mb-work-plan.sh` не трогается).
- **Источники member-полей по владельцу S4-C2** (S4 § Cross-slice #2, R2-004): `group`/`ice`/`pin`/
  `blocked_by` — из `specs/<topic>/requirements.md`; **`created` — из `context/<topic>.md`** (не из
  requirements.md — прежнее чтение оттуда было расхождением источников). `roadmap.md` не парсится вообще
  (рендер frontmatter'а внутри fences, обратный парсинг запрещён владельцем).
- **Компаратор S4-C2 потребляется целиком**: раундовый Kahn по `blocked_by`; `prioritized`
  сортируется `pin` ↑ → `score` ↓ → `created` ↑ → `topic` ↑ → `rel` ↑; `legacy_tail` (ни `ice`, ни
  `pin` — включая **отсутствующий и невалидный** `ice`, т.е. `ice=null`) сохраняет исходный порядок
  скана и идёт после `prioritized`. Собственный «ICE↓/topic↑» не изобретается.
- stdout: `{"group","degraded","reason","members":[{"topic","tasks_path","ice","pin","created","blocked_by"}]}`;
  `ice` — **score (int)** из компонент `{impact, confidence, ease}` (S4-C1) **или `null`** при
  отсутствующем/невалидном `ice`.
- Деградация — одна ступень: есть `group` у всех, но у кого-то нет `blocked_by` ⇒ ICE-упорядоченный
  список (компаратор S4-C2, `ice=null` в `legacy_tail`) с `"degraded":true,"reason":"blocked_by_unavailable"`,
  рёбра не выдумываются.
- Exit **выровнен под S4-C2** (R2-004): 0 успех (в т.ч. degraded, **в т.ч. отсутствующий/невалидный
  `ice` → `ice=null` legacy_tail**; невалидный — плюс stderr-warning); 2 неизвестная группа/член или
  отсутствующий `group` (stderr — C-сортированный список недостающих полей); 3 malformed
  **`pin`/`created`/`blocked_by`** (битый `ice` в exit 3 НЕ входит); 4 цикл `blocked_by` группы с
  печатью полного пути.

**Eval:** `bats tests/bats/test_mb_work_resolve_group.bats` — red: `--group`-режима нет, тест компаратора падает; exit: 1; output~: `not ok [0-9]+ .*S4-C2 comparator`

**Testing (TDD — tests BEFORE implementation):**
- bats (**общий физический файл фикстур `tests/fixtures/svp_group_ordering.json`** — контрактный вход
  обоих потребителей, byte-identical порядок с S4-C2/Task 6): четыре кейса duplicate pin / missing ice /
  равный ice / invalid ice → порядок topic'ов **byte-identical** порядку roadmap-рендера S4-C2.
- bats: компаратор целиком — `pin` ↑ бьёт `score` ↓; равный `score` → `created` ↑ → `topic` ↑;
  `legacy_tail` (в т.ч. `ice=null`) идёт после `prioritized` в порядке скана.
- bats: `ice` в JSON — int-score из компонент **или `null`**; `pin`/`created` присутствуют в member-JSON;
  `created` читается из `context/<topic>.md` (не из requirements.md).
- bats (**R2-004 exit-выравнивание**): отсутствующий `ice` → `ice=null` legacy_tail, exit 0; невалидный
  `ice` → `ice=null` legacy_tail + stderr-warning, exit 0 (НЕ exit 2/3); деградация
  `blocked_by_unavailable` → `degraded:true`, exit 0; отсутствующий `group` → exit 2 + C-сортированный
  список полей; malformed `pin`/`created`/`blocked_by` → exit 3; цикл группы → exit 4 + путь.
- bats: roadmap.md с ЛЮБЫМ содержимым не влияет на результат (не читается).
- bats-регрессия: `mb-work-resolve.sh [target]` без `--group` — stdout byte-identical текущему.
- shellcheck clean.

**DoD:**
- [ ] C5 реализован (`--group --json`, `created` из context, `ice:<int|null>`); bats green (были red)
- [ ] Порядок byte-identical roadmap-рендеру S4-C2 на общем `tests/fixtures/svp_group_ordering.json`; missing/invalid ice → exit 0 legacy_tail (не 2/3)
- [ ] `roadmap.md` не является источником зависимостей (тест «содержимое не влияет» зелёный)
- [ ] Single-target регрессия byte-identical (`mb-work-plan.sh` не сломан)
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Parity-тесты + ре-базлайн honesty-слоя

**Covers:** REQ-008
**Role:** qa
**Stage:** 6
**Blocked-by:** 4, 10
**Scope:** adapters/pi.sh, adapters/opencode.sh, adapters/cursor.sh, tests/bats/test_platform_limited_honesty.bats, tests/bats/test_mb_work_parallel_parity.bats
**Budget:** 90000

**What to do:**
- Негативные parity-тесты по образцу `tests/bats/test_platform_limited_honesty.bats`: хост без
  резолвящегося маршрута (C8 `--probe` → `available:false`) → sequential + **однократное**
  `platform_limited`-предупреждение; никакой тихой параллели.
- **Ре-базлайн honesty-слоя (обязательная часть SVP-PE-008)**: после C8 `/mb work` действительно
  роутит по ролям на pi/opencode, поэтому декларация `role-routing` в `platform_limited`
  становится ложной. Снять `role-routing` из `platform_limited` в `adapters/pi.sh` и
  `adapters/opencode.sh` там, где маршрут резолвится; заменить структурное негативное утверждение
  `! grep -Eq -- '--agent (pi|opencode) --role' commands/work.md` на **позитивный** dispatch-
  контракт-тест (C8 `--probe` на pi/opencode); вычистить соответствующие пары из `TESTED_PAIRS`.
- **Cursor (`adapters/cursor.sh`, AGR-020)**: Cursor входит в scope полного режима (REQ-015), но пока
  транспортного факта Cursor нет — его `platform_limited` остаётся **genuine** (`--probe` →
  `available:false reason=route_absent`) и НЕ снимается; negative-тест Cursor сохраняется. Когда
  Cursor-транспорт появится, декларация ре-базлайнится тем же правилом, что pi/opencode.
- **Не трогать** `statusline`-лимиты и codex-лимиты (`subagents`/`lifecycle-hooks`/
  `session-memory`) — они остаются genuine; мета-тест closed-vocabulary обязан остаться зелёным.
- Codex остаётся под REQ-008 всегда (нет subagents) — negative-тест сохраняется.

**Eval:** `bats tests/bats/test_mb_work_parallel_parity.bats` — red: parity-теста нет, тест деградации codex падает; exit: 1; output~: `not ok [0-9]+ .*codex degrades`

**Testing (TDD — tests BEFORE implementation):**
- bats: codex (`--probe` → `available:false`) + `pipeline default=parallel` → sequential,
  предупреждение ровно одно, ноль параллельных диспатчей.
- bats (positive, **честная граница детерминизма**): pi/opencode с резолвящимся маршрутом —
  параллельный диспатч проверяется **по-настоящему**: fake-бинарь `pi`/`opencode` на `PATH`
  логирует вызовы с временными метками, тест доказывает ≤ `max_agents` одновременных процессов и
  отсутствие `platform_limited`. Для claude-code нативный `Task` из bats **невызываем в принципе**
  (его исполняет промпт-слой), поэтому positive-тест claude-code проверяет ровно то, что
  детерминированно проверяемо: `--probe` → `route=native-task`, `available:true` и корректный
  payload. Утверждения «claude-code реально параллелит» в этом тесте нет — оно доказывается
  тестом Task 4 на настоящем C7 с fake dispatcher'ом.
- bats (negative): pi/opencode со снятым opt-in расширением → маршрут не резолвится → sequential +
  `platform_limited` (AGR-013: отказ = byte-identical install).
- bats-регрессия: `bats tests/bats/test_platform_limited_honesty.bats` зелёный **после**
  ре-базлайна: мета-тест vocabulary согласован, ни один заявленный лимит не остался без genuine
  негативного доказательства, ни один снятый лимит не остался задекларированным.

**DoD:**
- [ ] Parity-тесты; Eval green (был red)
- [ ] Заявленный `platform_limited` совпадает с фактическим резолвом маршрута на всех 8 клиентах; Cursor-декларация genuine до появления транспорта (AGR-020)
- [ ] `test_platform_limited_honesty.bats` зелёный после ре-базлайна; мета-тест не сломан
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Producer поверхности изменений

**Covers:** REQ-016
**Role:** backend
**Stage:** 3
**Blocked-by:** 3
**Scope:** scripts/mb-work-diff.sh, tests/bats/test_mb_work_diff_scope_paths.bats
**Budget:** 70000

**What to do:**
- Новый режим `mb-work-diff.sh --scope-paths --run-id <id>` по C6 — назначенный production
  producer входа Scope-гарда (R2-003; сегодня producer'а нет).
- Печатает C-сортированное объединение без дубликатов: modified, staged, deleted, обе стороны
  rename, **untracked** (сегодняшний `git diff` их теряет).
- **Fail-fast вместо fail-safe только в этом режиме**: нет git / не work tree / ошибка чтения /
  недостижимый baseline → **exit 3** + `{"status":"unavailable","reason":"<code>"}`
  (`no_git|not_a_repo|read_error|baseline_unreachable`). Пустой список никогда не выдаётся за
  успешный «изменений нет» при неудавшемся сборе.
- Успешный сбор с нулём путей → exit 0, пустой stdout.
- Режимы без `--scope-paths` остаются **byte-identical**, включая нынешний fail-safe exit 0
  (`scripts/mb-work-diff.sh:29-35`) — существующие потребители verify/judge не меняются.

**Eval:** `bats tests/bats/test_mb_work_diff_scope_paths.bats` — red: `--scope-paths` не реализован, untracked-тест падает; exit: 1; output~: `not ok [0-9]+ .*untracked`

**Testing (TDD — tests BEFORE implementation):**
- bats (поверхность): untracked-файл попадает в вывод; rename → обе стороны; deleted → попадает;
  staged и unstaged объединяются без дубликатов; порядок C-сортирован.
- bats (unavailable, R2-003): `PATH` без git → exit 3 + `reason=no_git`; каталог вне репозитория →
  exit 3 + `reason=not_a_repo`; недостижимый baseline → exit 3 + `reason=baseline_unreachable`;
  ни один из этих случаев не печатает пустой список с exit 0.
- bats: чистое дерево → exit 0 + пустой stdout (легальный «изменений нет»).
- bats-регрессия: вызовы без `--scope-paths` byte-identical текущим (включая fail-safe exit 0 при
  отсутствии git).
- shellcheck clean.

**DoD:**
- [ ] C6 реализован; bats green (были red)
- [ ] Недоступный git — exit 3 + `unavailable`, а не пустой успешный diff
- [ ] Untracked/rename/deleted учтены; режимы без флага byte-identical
<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: Исполнимый выбор режима

**Covers:** REQ-002
**Role:** backend
**Stage:** 2
**Blocked-by:** none
**Scope:** scripts/mb-work-state.sh, tests/bats/test_mb_work_state_configure_mode.bats
**Budget:** 80000

**What to do:**
- Новая субкоманда `mb-work-state.sh configure-mode` по C4 (R2-002) — флаги в конвенциях
  существующего скрипта (`--mb`/`--run-id`, не `--state <path>`). **Отдельные аргументы ответа
  `--answer-execution`/`--answer-intervention`** (R2-002): без них C4 не мог принять ответ
  AskUserQuestion, хотя precedence его называл; пара присутствует целиком либо отсутствует, неполная →
  exit 2; допустимы лишь для group/large.
- Критерий «большого target» — **родительский, не выдуманный**: умбрелла REQ-043 ⇒ рубрика REQ-016
  ⇒ `mb-estimate-check.sh --spec` печатает `spec=over` (>1M). Оркестратор передаёт `--size-status
  ok|near|over|unknown`; `over` ⇒ large; `near` — advisory, вопрос не запускает; `unknown`
  (недоступный чекер, план-target) ⇒ не large + один громкий stderr-note.
- **Эта задача чекер НЕ вызывает** и потому не блокируется им: `scripts/mb-estimate-check.sh`
  сегодня не существует (создаёт S1-C1, `--spec` добавляет S2-C3). C4 принимает готовый
  `--size-status`; вызов чекера — за Task 4.
- `--target-kind group` ⇒ вопрос обязателен всегда.
- Precedence (первый хит, **независимо по каждой оси**): explicit CLI (`--execution`/`--intervention`)
  → сохранённый state → интерактивный ответ (`--answer-execution`/`--answer-intervention`, только
  group/large) → pipeline default (`--default-*`).
- Enum: `execution sequential|parallel`, `intervention hitl|autonomous` (алиасы `auto`→
  `autonomous`, `interactive`→`hitl`); иное → exit 2. **Это канонический enum, на который
  ссылается S5-C1.**
- stdout: `{"execution","intervention","source":"cli|state|answer|config"}`; exit 0 успех, 2
  невалидный вход или необходимый ответ не получен (молчаливый дефолт запрещён).
- После первого успешного выбора режимы и `source` в state неизменны (кроме явного CLI-override).

**Eval:** `bats tests/bats/test_mb_work_state_configure_mode.bats` — red: `configure-mode` не реализован, precedence-тест падает; exit: 1; output~: `not ok [0-9]+ .*precedence`

**Testing (TDD — tests BEFORE implementation):**
- bats (precedence-матрица, R2-002): CLI бьёт state; state бьёт `--answer-*`; `--answer-*` бьёт
  `--default-*`; `--default-*` — последний; поле `source` (`cli|state|answer|config`) соответствует
  победителю в каждой из четырёх комбинаций; precedence считается **независимо по каждой оси**
  (execution/intervention); **неполная пара `--answer-*`** (одна ось задана, другая нет) → exit 2.
- bats (порог, REQ-043): `--size-status over` + `single` → вопрос обязателен; `near` → не
  спрашивает; `ok` → не спрашивает; `unknown` → не спрашивает + stderr-note;
  `--target-kind group` → спрашивает при любом `--size-status`.
- bats: group/large без CLI и без ответа → exit 2 (никакого молчаливого дефолта).
- bats (enum): `auto`→`autonomous`, `interactive`→`hitl`; `--execution parallel-ish` → exit 2.
- bats: повторный `configure-mode` возвращает сохранённое со `source=state`.
- bats-регрессия: `init|step|cycle|status|done|clear` byte-identical текущим.
- shellcheck clean.

**DoD:**
- [ ] C4 реализован; bats green (были red)
- [ ] Порог «большого» = `spec=over` по S2-C3 (родительский REQ-043), не item-count
- [ ] Precedence-матрица покрыта тестами; `source` всегда честен
- [ ] Существующие субкоманды byte-identical
<!-- /mb-task:8 -->

<!-- mb-task:9 -->
## Task 9: Scheduler — единственный источник решений

**Covers:** REQ-011, REQ-014
**Role:** backend
**Stage:** 4
**Blocked-by:** 1, 2, 3, 5, 7, 8
**Scope:** scripts/mb_parallel_scheduler.py, tests/pytest/test_parallel_scheduler.py
**Budget:** 120000

**What to do:**
- Новый `scripts/mb_parallel_scheduler.py` по C7 (SVP-PE-009): `init|next|complete|fail`,
  состояние `<bank>/tmp/parallel-runs/<run-id>.json` по **машинной схеме C7** (`tasks.<id>` несёт
  `status/role/agent/prompt_file/claim_token`, плюс `active_judge`/`problems`); запись — temp-file +
  atomic `rename`, никогда in-place.
- `next` печатает один JSON-объект `{"run_id","actions":[…]}`; actions C-сортированы по
  `(kind, task_id)`; batch содержит **только** `dispatch`, а `wait/judge/escalate/done` — по одному.
  Схемы action по C7: `dispatch{kind,task_id,role,agent,prompt_file,claim_token}` (role + **имя агента**
  оба, SVP-PE-008); `wait{kind,task_id:null,reason:"slots_full|blocked|awaiting_ack",blocked_by[]}`;
  `judge{kind,task_id}`; `escalate{kind,task_id,reason:"scope_violation|scope_unavailable|dispatch_failed|task_failed"}`;
  `done{kind,task_id:null}`.
- **Обязательный порядок**: C1 (фронтир) → Scope-отбор → C2 `claim` → только затем `dispatch` с
  `claim_token` из результата C2. Claim записан до диспатча by construction.
- Не более `max_agents` одновременных dispatch; **не более одного `judge`** за раз (REQ-011) —
  сериализация живёт здесь, а не в дисциплине промпта.
- `complete|fail --task <id>`: строгая stdin-схема (`complete{dispatch_exit:0,report}` /
  `fail{dispatch_exit:<nonzero>,reason,report}`); собирает поверхность C6, вызывает C3 по handoff
  (**C6 exit 0 → `--collector-status ok --diff-file`; C6 exit 3 → `--collector-status unavailable
  --collector-reason`**), затем по вердикту C3: `ok` → release claim (C2) + `done`; `violation` →
  `escalate reason=scope_violation` **в S5-C1**; `unavailable` → scheduler **напрямую** `escalate
  reason=scope_unavailable` **без вызова S5** (R2-003). Двигает прогон.
- Exit: 0 успех; 1 допустимый отказ; 2 невалидный вход/состояние/битый stdin; 3 lock-timeout C2.

**Eval:** `pytest tests/pytest/test_parallel_scheduler.py` — red: scheduler'а нет, claim-before-dispatch падает; exit: 1; output~: `FAILED .*test_parallel_scheduler\.py::test_claim_recorded_before_dispatch`

**Testing (TDD — tests BEFORE implementation):**
- pytest (настоящий CLI + fake dispatcher/judge — не модель): claim записан в JSONL **до** выдачи
  `dispatch`-action; `dispatch` несёт `task_id`/`role`/**`agent`**/`prompt_file`/`claim_token` (role +
  имя агента оба, SVP-PE-008); state-файл соответствует схеме C7 и пишется atomic-rename'ом.
- pytest: `--max-agents 2` → не более двух `dispatch` за `next` и не более двух активных claim'ов;
  `--max-agents 0` → exit 2; batch содержит только `dispatch`, одиночные `wait/judge/escalate/done`.
- pytest (REQ-011): две задачи доходят до judge → `next` выдаёт ровно один `judge`-action, второй
  получает `wait{reason:"slots_full"}`.
- pytest: пересекающиеся по Scope кандидаты → один `dispatch` + `wait`, а не два dispatch.
- pytest: пустой фронтир с незакрытыми блокерами → `wait{reason:"blocked",blocked_by:[…]}`; всё
  закрыто → `done`.
- pytest (**R2-003 handoff**): C3 `violation` → `escalate reason=scope_violation` (маршрут в S5-C1);
  C3 `unavailable` (C6 exit 3) → `escalate reason=scope_unavailable` **напрямую scheduler'ом, S5 не
  вызывается**; строгая stdin-схема `complete`/`fail` (битый stdin → exit 2); `fail` по задаче без
  активного claim → exit 1.
- pytest: actions детерминированы и C-сортированы при повторном `next` на том же состоянии.

**DoD:**
- [ ] C7 реализован; pytest green (были red)
- [ ] claim-before-dispatch и сериализация judge доказаны на production-CLI (не на модели)
- [ ] `max_agents` соблюдён; actions детерминированы
<!-- /mb-task:9 -->

<!-- mb-task:10 -->
## Task 10: Host-dispatch адаптер

**Covers:** REQ-008, REQ-015
**Role:** backend
**Stage:** 4
**Blocked-by:** 1
**Scope:** scripts/mb-work-dispatch.sh, scripts/mb-subinvoke-resolve.sh, tests/bats/test_mb_work_dispatch.bats, tests/bats/test_mb_subinvoke_resolve.bats
**Budget:** 90000

**What to do:**
- Новый `scripts/mb-work-dispatch.sh` по C8 (SVP-PE-008 + AGR-020; восстанавливает полный full mode
  D-07 на **четырёх** хостах — Claude Code, Pi, OpenCode, **Cursor** — который ревизия 2 ошибочно
  сузила до Claude Code; AGR-020 отменил сужение D-07 до трёх хостов).
- Сигнатура: `--host claude-code|pi|opencode|cursor --role <semantic-role> --agent-name <mb-agent>
  --prompt-file <path> [--probe]`. Хост: `--host`, иначе `$MB_AGENT`, иначе `claude-code`. **role и
  agent-name передаются раздельно** (SVP-PE-008): WorkItem даёт семантическую роль `backend`, файл —
  `agents/mb-backend.md`, поэтому резолвер зовётся именем агента, а не голой ролью.
- Маршруты: `claude-code` → нативный `Task` (`route=native-task`); `pi` →
  `mb-subinvoke-resolve.sh --agent pi --role "<mb-agent>"` (резолвер ищет `agents/$ROLE.md`, поэтому
  передаётся `mb-backend`, а не `backend`); `opencode` → **расширить ветку резолвера**, чтобы она
  возвращала `opencode run --agent "<mb-agent>" …` (сегодня unscoped `opencode run` без выбора агента,
  `scripts/mb-subinvoke-resolve.sh:294-302` — role-routing OpenCode фактически отсутствует), отсутствие →
  `status:"unavailable"`, exit 1, без unscoped fallback; `cursor` → per-role sub-invoke Cursor
  (AGR-020), а до появления транспортного факта Cursor — `available:false reason=route_absent`
  (честная деградация `platform_limited`, замысел полного режима фиксируется REQ-015). Промпт — **только**
  через `MB_FANOUT_PROMPT` (security seam) на всех non-native маршрутах.
- Один payload на всех маршрутах: `mb-engineering-core` + host tooling + role + work item.
- Обычный диспатч → JSON `{"host","agent","status":"ok|failed|delegate_native","exit_code","report"}`
  (exit 0 = ok/delegate, exit 3 = child failure).
- `--probe` → `{"host","route","available","reason"}`, exit 0/1. **Full mode разрешается хосту только
  при `available:true`** — не по списку имён; `available:false` ⇒ REQ-008 (sequential + одно предупреждение).
- Закрывает backlog I-121/I-122 (`adapters/pi.sh:328-340` называет отсутствующее звено — routing wiring
  в `/mb work` — прямо этим слайсом).

**Eval:** `bats tests/bats/test_mb_work_dispatch.bats` — red: адаптера нет, probe-тест pi падает; exit: 1; output~: `not ok [0-9]+ .*pi role route probe`

**Testing (TDD — tests BEFORE implementation):**
- bats (probe): pi с резолвящимся агентом → `available:true`, exit 0; pi с недоступным расширением/
  нерезолвящимся агентом → `available:false` + `reason`, exit 1; opencode — то же (после расширения
  резолвера); cursor — `available:false reason=route_absent` пока нет транспорта; codex →
  `available:false` всегда; неизвестный хост → `available:false`.
- bats (маршрут, SVP-PE-008): `claude-code` → `route=native-task`; **Pi зовёт `agents/mb-backend.md`**
  (`--role mb-backend`), а не `agents/backend.md`; **OpenCode-команда содержит `--agent mb-backend`**;
  Cursor-арм присутствует в таблице маршрутов и `--probe`.
- bats (resolver, extended): проверки, что Pi резолвит `agents/mb-backend.md`, а OpenCode-ветка
  возвращает `opencode run --agent mb-backend …` (в `test_mb_subinvoke_resolve.bats`).
- bats (security): промпт не появляется в командной строке — доставляется через `MB_FANOUT_PROMPT`;
  промпт с шелл-метасимволами не интерполируется.
- bats: определение хоста — `--host` бьёт `$MB_AGENT`; без обоих → `claude-code`.
- shellcheck clean.

**DoD:**
- [ ] C8 реализован (четыре хоста, role + agent-name раздельно); bats green (были red)
- [ ] Full mode на claude-code/pi/opencode/cursor при резолвящемся маршруте (D-07 + AGR-020); OpenCode-резолвер расширен, Pi зовёт `agents/mb-backend.md`
- [ ] `platform_limited` следует из probe, а не из списка имён хостов; Cursor деградирует честно до появления транспорта
- [ ] Промпт не интерполируется в шелл-код (security seam соблюдён)
<!-- /mb-task:10 -->
