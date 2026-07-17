---
topic: svp-adapt-escalation
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-adapt-escalation-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-030, REQ-031, REQ-032]
blocked_by: [svp-sdd-core, svp-parallel-engine, svp-roadmap-backlog-db]
---

# Context: svp-adapt-escalation (слайс S5, ICE 294, blocked by S2 + S3)

ADaPT-репланирование в `/mb work` (arXiv 2311.05772): сигнал complexity_escalation от агента + детерминированные гарды → развилка: autonomous — stub за флагом + беклог + продолжить; HITL — выбор из четырёх вариантов. Проблемы никогда не замалчиваются (D-33). Родительские решения: D-16, D-25, D-33, D-35.

Зависимости **жёсткие** (ревью SVP-008/AE-005 + ревизия круга 3): S2 `svp-sdd-core` (tasks.md v2 — Eval/Budget/Scope; durable eval-объект `eval-red`/`eval-green` — **S2 Task 8**, Task 1 blocked_by `svp-sdd-core#8`, R3-004), S3 `svp-parallel-engine` (Scope-вердикт `mb-work-scope-check.sh`, S3-C3, enum `ok|violation`) и **S4 `svp-roadmap-backlog-db`** (`annotate` для READY-гейта беклога, C6/X5-01; lock-helper C6 для сериализации журнала эскалаций, CPR-C). Scope-гард REQ-002 без S3 нереализуем — слайс не стартует до S3; частичного режима и «изящной деградации без S3/S4» нет.

**Ревизия круга 3 (2026-07-18)** закрыла PARTIAL/major-находки: SVP-AE-007 (полная матрица обязательности `--backlog-id`/replan-полей в C1.2), SVP-AE-009B (`annotate` поставлен S4-C3 revision 4, X5-01 SATISFIED, жёсткая зависимость объявлена), R3-001 (`--run-id` обязателен в `decide`/`note-clean`; `replan-gate` без `--run-id` выбирает последнее `resolved` по `item_id` среди всех run_id — `MB_WORK_RUN_ID` оркестратором не экспортируется), R3-002 (`resolved_by` выводится из `decision` опенеда, а не из режима — autonomous-fallback к `fork_user` = `resolved_by=user`), R3-003 (обещание подавления повторного триггера удалено — KISS), R3-005 (Scope Task 5 включает `commands/work.md`), R3-006 (portable `mb_adapt_bounded_run`: `timeout`→`gtimeout`→Bash-watchdog, стоковый macOS без GNU coreutils), CPR-C (журнал под `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30`, обоснование через PIPE_BUF/4096 удалено).

## Research Digest

- `commands/work.md:566-599` + `scripts/mb-work-pivot.sh` — существующий pivot (стагнация ревью-циклов): образец решения-скрипта + JSONL-телеметрии (`tmp/pivot-log.jsonl`), НО не покрывает «scope больше ожидаемого».
- `scripts/mb-work-budget.sh` — токен-бюджеты уже трекаются — готовый гард №1. НО exit 1 двусмыслен (WARN, «нет бюджета» и stale run_id — один код; exit 2 = STOP): гард потребляет **нормализованный** статус `ok|warn|stop|absent`, нормализация по паре (exit, stderr-маркер) — design C1.1.
- Scope-сверка diff — контракт S3-C3 (`mb-work-scope-check.sh`, вердикт `ok|violation`) — гард №2, **жёсткая зависимость**, не опция.
- Eval red→green — контракт C6 S2 — гард №3 (eval не зеленеет за max_cycles).
- `mb-work-severity-gate.sh`, `mb-work-state.sh` — счётчики циклов verify/review/judge — гард №4. Сегодня в work-state ОДИН общий `cycle`; раздельные durable-счётчики достигаются аддитивной конвенцией поверх существующего `step <name>`/`status` (зарезервированные имена `eval_fail`/`verify_fail`/`review_cycle`/`judge_cycle`, design C2) — сам скрипт не правится.
- Правило stubs: «staged stubs behind a feature flag with a docstring» — разрешённое исключение no-placeholders (CLAUDE.md CRITICAL RULES).
- Формулировка пользователя про вайбкодеров и 4 варианта — транскрипт родителя (Q11).

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S5-A-01**: Стартовые пороги циклов: verify 3 / review 3 / judge 2; конфигурируются в pipeline.yaml (`escalation.thresholds`); калибровка по телеметрии pivot-log.
- **S5-A-02**: Сигнал — JSON-блок `complexity_escalation: {reason, estimated_tokens}` в структурном отчёте имплементера.
- **S5-A-03**: Stub — за feature-флагом с docstring (разрешённое исключение no-placeholders) + READY-элемент в беклог (тип по D-15). Детерминированный маркер `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<path>` + default-off флаг; беклог пишет ТОЛЬКО оркестратор (D-23) — design C6.
  - Ревизия 3: цепочка приведена к **фактическому** S4-C3 ревизии 3 — `mb-idea.sh` рождает запись в `NEW` с `**Type:** IDEA` (типы реестра — только `SPEC`/`IDEA`, поэтому `[ADAPT]` остаётся префиксом заголовка, а не типом); далее `list` (наблюдаемое состояние) → кратчайший валидный путь `NEEDS-INFO`→`TRIAGED`→`READY` вызовами `mb-backlog-state.sh transition`. Ветка «до S4» удалена: роадмеп ставит S4 (432) перед S5 (294). `PLANNED` не присваивается никогда (нет в алфавите S4-C3; S4-C7 запретил явно).
  - **READY-гейт S4 требует `**Brief:**` в теле записи; writer этого блока `annotate` ПОСТАВЛЕН владельцем S4-C3 revision 4** (`mb-backlog-state.sh annotate <I-NNN> --brief <TEXT> [--parent <I-NNN|none>]`, единственный writer `**Brief:**`/`**Parent:**` под lock C6, X5-01 **SATISFIED**, ревизия круга 3). S5 потребляет его как есть — жёсткая зависимость `blocked_by: svp-roadmap-backlog-db` (frontmatter) и `Blocked-by: svp-roadmap-backlog-db#2` (Task 4); своего второго writer'а беклога S5 не заводит: это была бы пятая мутация в обход lock'а S4-C6. Brief собирается фиксированным шаблоном с `shall` (черновик ревью «When … is off, existing behavior remains…» READY-гейт НЕ проходит — в нём нет ни одного глагола `should|shall|must|когда|если`), сырой `<reason>` в него не подставляется (регулярно содержит путь файла → `contains file path`).
  - Ограждённость стаба доказывается **поведением**, а не разметкой: драйвер `eval=<path>` печатает `MB-ADAPT-STUB-PATH: baseline` без флага и `… staged` при `<NAME>=1`; default-on и флаг-пустышка детектируются механически (design C1.5).
- **S5-A-04**: Лог эскалаций — `<bank>/tmp/escalations.jsonl`, не git-tracked, как pivot-log; ключи `ts`/`item_id`/`cycle`/`mode` совместимы с pivot-log. Запись **двухфазная append-only** (контракт умбреллы §Interfaces 3): `opened` (без resolution) в момент эскалации, `resolved` после решения, свёртка по `escalation_id`, последнее событие побеждает — design C1.
  - Ревизия 3: полные схемы трёх типов записей (`opened`/`resolved`/`clean`) зафиксированы в design C1.0 по **стилю умбреллы §Interfaces 5** (append-only, одна строка на событие, обязательные `ts` + явный счётчик `seq`, последняя валидная строка = действующее состояние). Второго стиля журнала в группе не заводится. Невалидная строка → exit 1 без append (в отличие от pivot-log, где телеметрия деградирует молча): здесь журнал — durable-состояние гарда REQ-010 и корреляции `resolve`, тихая потеря строки ослабила бы каскад-стоп и проглотила бы эскалацию (REQ-008/D-33). `escalation_id` непрозрачен и обратно не разбирается (`item_id` может содержать `:`).

## Functional Requirements (EARS)

- **REQ-001** (event-driven): When an implementer report contains a `complexity_escalation` block, the system shall trigger the ADaPT fork. <!-- D-16, S5-A-02 -->
- **REQ-002** (event-driven): When a deterministic guard fires — task token budget exceeded, declared-scope violation, eval not green after max cycles, or a verify/review/judge loop threshold exceeded — the system shall trigger the ADaPT fork. <!-- D-16 -->
- **REQ-003** (ubiquitous): The loop thresholds shall default to verify 3, review 3, judge 2 and shall be configurable via pipeline.yaml. <!-- S5-A-01 -->
- **REQ-004** (state-driven): While in autonomous mode, on an ADaPT trigger the system shall implement a stub behind a feature flag with a docstring, register a backlog item for the deferred work and continue execution. <!-- D-16, S5-A-03 -->
- **REQ-005** (state-driven): While in HITL mode, on an ADaPT trigger the system shall offer the choices: continue anyway, simplify, replan via decomposition or requirement change, or skip the step. <!-- D-16 -->
- **REQ-006** (event-driven): When the replan choice is decomposition, the system shall route the deferred work into a new spec through the decomposed-spec registry with its own interview (or self-interview in autonomous mode). <!-- D-16, D-10 -->
- **REQ-007** (ubiquitous): The system shall log every escalation as an `opened` JSONL record at trigger time and its resolution as a matching `resolved` JSONL record, correlated by `escalation_id`. <!-- S5-A-04, умбрелла §Interfaces 3 -->
- **REQ-008** (ubiquitous): The system shall report every escalation and stub to the user in the run summary — an escalation shall never be silently swallowed. <!-- D-33 -->
- **REQ-009** (unwanted): If a stub is created without a feature flag or without a backlog item, then verification shall fail for that task. <!-- S5-A-03, no-placeholders -->
- **REQ-010** (unwanted): If `cascade_stop` consecutive ADaPT escalations occur within one run, then the system shall stop before dispatching the next item and report a recommendation to revise the whole spec. <!-- D-35, ревью AE-013 -->

## Non-Functional Requirements

- **NFR-001**: Нулевые лишние LLM-вызовы — гарды детерминированные (скрипты); LLM участвует только в самом решении развилки.
- **NFR-002**: Телеметрия совместима по формату с pivot-log (общие ключи `item_id`/`cycle`/`mode`; единый анализ later).

## Constraints

- Pivot-механика (стагнация) не заменяется — ADaPT дополняет её (другой триггер-класс); max_cycles-политика 5f не меняется. Порядок: `фаза → step-счётчик → adapt-check → pivot-check → on_max_cycles`.
- Правило no-placeholders: stub легален только за флагом с docstring + беклог-запись (REQ-009); нет флага — нет стаба (эскалация, не warning).
- Банк пишет только оркестратор (D-23): `mb-work-adapt.sh` пишет исключительно `tmp/escalations.jsonl`; беклог — `mb-idea.sh` руками оркестратора; `mb-work-state.sh` не редактируется (аддитивная конвенция шагов).
- Enum'ы потребляются из соседних слайсов, не переопределяются: режим `autonomous|hitl` (S3-C4, алиасы `auto`/`interactive`), Scope-вердикт `ok|violation` (S3-C3), двухфазная телеметрия (умбрелла §Interfaces 3).

## Edge Cases & Failure Modes

- Эскалация на первой же задаче спеки — вероятно, кривая оценка всей спеки: развилка предлагает и пересмотр спеки (вариант replan), не только задачи.
- Два исхода `replan` (D-16 «декомпозиция ИЛИ смена требований») различаются **механически**: `sha256(requirements.md)`, снятый в момент `resolve`, сверяется гейтом `replan-gate` при следующем прогоне. Декомпозиция требования не меняет (хэш совпал) и обязана предъявить child-спеку; смена требований обязана предъявить расхождение хэша, иначе item к прогону не допускается (`requirements_unchanged`). В хэш входит только `requirements.md`: `tasks.md` мутирует от переворота чекбоксов соседних задач и давал бы ложный «требования изменились».
- Контрактные вердикты S8 (`fake_red`/`foreign_failure`/`unobservable_requirement`) — **локальные hard stop'ы S8 перед этим конвейером**, в ADaPT не маршрутизируются: enum `--eval-status` остаётся `green|red|absent` (X8-01). Маршрутизация через ADaPT отсрочила бы немедленный отказ до исчерпания `max_cycles`, то есть ослабила бы hard stop.
- Повторная эскалация с тем же заголовком беклога: `mb-idea.sh` идемпотентен по заголовку и вернёт существующий `I-NNN` в его текущем состоянии — поэтому цепочка переходов строится от наблюдаемого состояния (`list`), а не вслепую; `DONE`/`WONTFIX` останавливают стаб-путь (терминальные состояния; `WONTFIX` = признано вне области).
- Двойной триггер (сигнал + гард одновременно) — одна развилка, оба триггера в логе (одна эскалация, несколько токенов в `triggers[]`).
- Autonomous-режим без доступного механизма feature flag — stub **НЕ создаётся**; решение принудительно меняется на `fork_user` с trigger `feature_flag_unavailable`, прогон останавливается и сообщает проблему. NotImplemented/TODO и продолжение с warning **запрещены** (REQ-004/009, `rules/RULES.md` § Staged stubs: без feature-флага это не стаб, а продакшн-код).
- Пользователь выбирает «идти дальше несмотря ни на что» — выбор логируется событием `resolved` (`continue`), шаг `adapt_override` в work-state, verify-отчёт несёт пометку override.
- Каскад эскалаций (`cascade_stop` = 3 подряд) — **стоп прогона до диспатча следующего item** с рекомендацией пересмотреть спеку целиком (родительский D-35-путь) — REQ-010. Успешное завершение item без эскалации (событие `clean`) сбрасывает счёт; двойной триггер одной развилки считается одной эскалацией.
- Гард недоступен (нет бюджета / diff не собирается / битое work-state) — попадает в `degraded_guards` и в summary; молчаливого «ноль = порог не достигнут» нет.
- Отчёт имплементера без envelope `MB_WORK_RESULT_JSON=` или с битым JSON — halt item'а с `invalid_implementer_report`; догадками отчёт не интерпретируется.

## Out of Scope

- Изменение pivot-порогов; параллельная оркестрация (S3); формат tasks.md v2 (S2 — зависимость).

## Open Questions

- Точные значения порогов после калибровки телеметрией (первые 2–3 governed-прогона).
