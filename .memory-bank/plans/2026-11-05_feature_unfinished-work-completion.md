---
type: feature
topic: unfinished-work-completion
status: paused
depends_on: []
parallel_safe: true
linked_specs: [specs/sdd-vision-pipeline, specs/svp-interview-upgrade, specs/svp-sdd-core, specs/svp-brief, specs/svp-roadmap-backlog-db, specs/svp-contract-test-loop, specs/svp-spec-review-loop, specs/svp-docs-wiki, specs/svp-parallel-engine, specs/svp-adapt-escalation]
linked_plans: [plans/2026-07-28_fix_graph-semantic-adoption.md, plans/2026-10-05_feature_pi-native-integration.md, plans/2026-10-09_feature_codex-memory-parity.md]
goal: G-001
created: 2026-11-05
---
# Plan: feature — unfinished-work-completion (G-001 + graph-хвосты)

**Baseline commit:** 22f4c93d891bcdb12287a903f0bbd1052a1a335c (в рабочем дереве есть чужие staged/unstaged правки параллельной сессии: `scripts/mb-goal-acceptance.sh`, `tests/bats/fixtures/brief/mkbrief.py`, `install.sh`, `adapters/opencode_install_io.py` и др. — не трогать, не стейджить).

**Tier:** extra (L/XL). Исполнение: `/mb work … --workflow codex-governed` (implement=Opus, review=codex gpt-5.6-sol xhigh, judge=mb-judge/Opus — AGR-028/AGR-029); закрытие уже реализованного — `--workflow review-fix` (`verify → review → judge → fix → done`). Pi-часть — по AGR-089 (без codex/judge, только верификатор).

> **Trimmed 2026-11-19 by master-completion Stage 19.** Stages 2, 4, 5, 6, 7, 9, 12 are closed by `plans/2026-11-18_feature_master-completion.md` (marked CLOSED below). Open here: Stage 1 (owner setup — goal G-001 is parked in `goals/G-001.md`, AGR-106), Stage 3 (S1/S2 conformance + judge), Stage 8 (S9 remainder), Stage 10 (S6 docs-wiki), Stage 11 (S3 parallel-engine rebaseline), Stage 13 (umbrella + G-001 close).

## Context

**Problem.** Группа `sdd-vision-pipeline` (goal G-001, `status: paused` с 2026-07-27) и графовые стадии трёх планов не закрыты. Счётчики checklist/roadmap частично устарели: часть задач реализована и закоммичена, но галочки и судейские вердикты отсутствуют; часть спек не проходит текущий валидатор (правила REQ-049/051, CPR-D появились позже самих спек); две спеки (S3, S5) написаны до появления `/mb team`, `mb-lock.sh`, `mb-work-slots.sh` и ADaPT-lite и пересекаются с ними.

**Expected result.** Каждая задача источников закрыта с уликой (red→green через `mb-work-state.sh eval-red/eval-green`, DoD `[x]` детерминированным flip), каждая из 10 спек получила вердикт судьи GO/GO_WITH_BACKLOG, delegate-гейты umbrella T2–T10 зелёные, полная батарея зелёная, G-001 `paused → active → done`. Графовые стадии: graph-semantic-adoption Stage 5 и Stage 7 (кроме отложенного недельного замера), Pi Stage 3 и Codex Stage 2 закрыты с уликами.

План не пересказывает спеки: задачи исполняются по `specs/<topic>/tasks.md` (Scope, Eval, DoD, Testing там нормативны); здесь — порядок, параллелизм, гейты закрытия и найденные расхождения.

## Фактическое состояние (проверено 2026-11-05)

Метод: `tasks.md` (DoD-чекбоксы) сверены с git (`git log`, 681 коммит), наличием файлов Scope и прогоном Eval-команд на рабочем дереве; `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/<s>` по каждой спеке. Судейских вердиктов ни по одной спеке группы не найдено (поиск по `progress.md`, `reports/`, `specs/`, `COORDINATION.md`; последняя запись доски: «Вердикта судьи по-прежнему нет ни у одной спеки», `COORDINATION.md:2014`; после этого были judge-фиксы S2/S9 — `d023d03`, `c916983`, `88a7237` — но итоговый GO не записан).

| Источник | Задача | Статус | Улика |
|---|---|---|---|
| umbrella `sdd-vision-pipeline` | T1 MIT (REQ-038) | done | DoD 3/3 `[x]`; `51ed1d4`; Eval `test_mattpocock_attribution.bats` — **не проверено** (не перезапускался) |
| umbrella | T2 (S1), T4 (S2), T3 (S4), T8 (S7), T9 (S8), T10 (S9) | partial | delegate-гейты красные: валидатор child-спеки rc=1 (кроме S2) и/или open_dod>0; DoD «/mb work завершён» без judge |
| umbrella | T5 (S6), T6 (S5), T7 (S3) | not started | child open_dod 7/7/36 |
| S1 `svp-interview-upgrade` | T1–T6 | done (без judge) | DoD 6/6; `2439ce4`, `622cec8`, `001df0a`; validate rc=1: `REQ-051 no **Seams:** block`; Eval-ы **не перезапускались** |
| S2 `svp-sdd-core` | T1–T9 | done (без итогового judge) | DoD 9/9; validate rc=0; `requirements.md` `status: draft` (`d023d03`, C7 ждёт разрешения ревью); Eval-ы **не перезапускались** |
| S7 `svp-brief` | T2, T3 | done | `dbfa870`; сейчас 33/33 и 5/5 |
| S7 | T1, T4 | partial: реализовано, не отмечено | `cd551f0`, `59ffc7c`; guard `*/../*` в `scripts/mb-brief.sh:146`; `test_mb_secret_scan_brief_input` 22/22, `test_mb_brief_command` 54/54, `test_mb_brief_docs` 7/7 зелёные на рабочем дереве; validate rc=1 (Seams; REQ-049 у T3) |
| S4 `svp-roadmap-backlog-db` | T1, T2, T6 | done (без judge) | DoD `[x]`; `ae4425b`, `769cf62`, `a7b1e66`, `020ada5`; Eval-ы **не перезапускались** |
| S4 | T3, T4, T5, T7, T8, T9 | not started | нет `mb-backlog-migrate.sh`, `mb-bank-lint.sh`, тест-файлов Scope; `--tree` → exit 2 (`mb-backlog-state.sh:14`); нет `mb_next_backlog_id` в `_lib.sh` |
| S8 `svp-contract-test-loop` | T1–T3 | done | `908b0e7`, `0b4fcce`, `c36a6eb`, `1265e76` |
| S8 | T4–T8 | partial: реализовано, не отмечено, без judge | `a4f0ba0` T4, `2d6d372` T5, `2d88b5b` T6, `85a0538` T7, `cbd4d3d` T8, codex-круг `c791eab`; сейчас 31/34/14/8/9 тестов зелёные; validate rc=1: 8× CPR-D + Seams; патч `commands/mb.md` для T5 не применён (`2d6d372`: «commands/mb.md НЕ ТРОНУТ») — **не проверено**, нужен ли он ещё |
| S9 `svp-spec-review-loop` | T1, T2 | done | `9896d0c`; сейчас 16/16 и 34/34 |
| S9 | T3, T4, T5 | not started | нет `mb-sdd-review-prompt.sh`, `spec-review-rubric.md`, `mb-work-spec-gate.sh`, трёх тест-файлов; validate rc=1: REQ-014..017 orphan, 5× CPR-D, Seams, REQ-049 у T4 |
| S6 `svp-docs-wiki` | T1–T7 | not started | ни одного файла Scope; validate rc=1 (Seams, REQ-049 у T5) |
| S3 `svp-parallel-engine` | T1–T10 | not started | нет `--frontier`, `mb-work-claims.sh`, `mb-work-scope-check.sh`, `mb_parallel_scheduler.py`, `mb-work-dispatch.sh`; пересечение с `mb-lock.sh`, `mb-work-slots.sh`, `/mb team` (`952d490`, `bd1805a`) |
| S5 `svp-adapt-escalation` | T1–T3 | partial (иначе, чем в Scope) | ADaPT-lite `190251c`: `scripts/mb_work_adapt.py`, `adapt:` в `references/pipeline.default.yaml:286`, `references/adapt.md` § Lite slice покрывает REQ-001, часть REQ-002, REQ-003, REQ-005, REQ-006-lite (AGR-080/082); файлов Scope (`mb-work-adapt.sh`, `escalation:`) нет; покрытие по задачам **не проверено** поатомно |
| S5 | T4, T5 | not started | stubs (REQ-004), журнал (REQ-007/008), cascade (REQ-010) остаются в спеке |
| graph-semantic-adoption | Stage 5 | not started | `hooks/mb-context-slim-pre-agent.sh` (78 строк) без графа |
| graph-semantic-adoption | Stage 7 | partial | сделано: `mb-tooling-core` в compose у `mb-developer`/`plan-verifier`/`mb-reviewer` (`8d21698`), graph-first в `agents/mb-engineering-core.md:22`; нет: compose у `mb-judge`/`mb-reviewer-logic`, push-блок `## Graph`, строка `Graph:` в отчётах, per-agent ключ nudge, `graph_share` в `mb-cost-report.py`, `tests/pytest/test_graph_dispatch_docs.py`, демо, недельный замер |
| pi-native-integration | Stage 3 | done с уликой, локальный тест красный | `b1bbbbf`, `reports/pi-native-integration/stage3-2026-10-08.md`; `test_pi_native_embeddings.py` 8/8; `test_pi_native_graph.py` **15/15 FAIL**: `Cannot find module 'jiti'` — фикстура `tests/fixtures/pi_native_graph_host.mjs:12` берёт Pi из `npm root -g` (`~/.hermes/node`), а рабочий Pi стоит под nvm; открытый пункт «verify/review/judge» заменён AGR-089 (верификатор на уровне плана); checklist 0/5 устарел (в плане Stages 1–4 `done`) |
| codex-memory-parity | Stage 2 | done с уликой, не отмечено | `f050443`; `test_graph_query_precision.py` + `test_codegraph_invocations.py` 18/18 (`PYTHONPATH=.`) |

Итого по спекам (done / partial / not started): umbrella 1/6/3 · S1 6/0/0 · S2 9/0/0 · S7 2/2/0 · S4 3/0/6 · S8 3/5/0 · S9 2/0/3 · S6 0/0/7 · S3 0/0/10 · S5 0/3/2. «Done» у S1/S2/S4/S7/S8/S9 — без судейского вердикта.

> **2026-11-19 (AGR-106):** goal G-001 is parked in `.memory-bank/goals/G-001.md` so the pre-commit flow gate stops running the full suite on every commit. Stages that read or edit `.memory-bank/goal.md` (1, 13) must move it back first.

## Сквозные находки, влияющие на порядок

1. **Валидатор.** 9 из 10 спек падают `--require-scenarios` (только S2 зелёная) — delegate-гейты T2–T10 не пройдут без «conformance»-правок спек: блок `**Seams:**` (REQ-051) в 8 child-спеках, REQ-049 (S7 T3, S4 T5, S6 T5, S5 T3/T4 — после AGR-036 часть может уйти сама, перепроверить), CPR-D (S8 ×8, S9 ×5), orphans S9 REQ-014..017. Conformance — часть стадии своей спеки.
2. **Корпусный гейт.** `tests/pytest/test_spec_corpus_battery.py` `KNOWN_FAILING` падает, если спека из списка стала зелёной. Файл общий для всех треков → правит **только оркестратор** при закрытии стадии (AGR-032), не исполнители.
3. **`commands/work.md` = 400 строк** при зонном контракте 400 (`tests/pytest/test_s2_file_size_contract.py:43`, AGR-035). В него пишут S9 T5, graph Stage 7, S3 T4, S5 T3–T5 → нужна предварительная разгрузка (Stage 2) и строгая сериализация файла.
4. **Pre-commit хук** (`.git/hooks/pre-commit`) гейтит каждый коммит полным `mb-flow-verify.sh` при существующем `goal.md` независимо от `status:`; чек `tests` — вся батарея (минуты, установки адаптеров). Активная цель с неотмеченной acceptance делает каждый коммит красным (прецеденты обхода — AGR-092/095).
5. **S3/S5 устарели относительно кода** (п. таблицы выше) — перед реализацией нужен delta-ребейзлайн спек, иначе вторые реализации lock/slots/ADaPT (DRY).
6. Локальный `pytest` без editable-установки: модули `memory_bank_skill` импортируются только с `PYTHONPATH=.` — все команды ниже его задают.

## Открытые решения владельца (до Stage 3)

> **Решено 2026-11-05 (AGR-098):** владелец принял рекомендованные варианты Q1-A, Q2 (worktree-ретро-red), Q3-A, Q4 (waiver после 11a/12a).

- **Q1 — коммиты и G-001.** (A, рекомендовано) G-001 остаётся `paused` на волнах 1–6; коммиты — scoped, по одному на волну, хук гоняет батарею (после посадки чужой staged-правки `mb-goal-acceptance.sh` paused-цель даёт `acceptance ok=null`); `paused → active` в Stage 13, `active → done` после зелёного `mb-flow-verify`. (B) `active` сразу + `MB_FLOW_CLOSURE=off` на каждый коммит по отдельному разрешению.
- **Q2 — ретро-red.** Для задач, уже реализованных до прогона eval-red (S7 T1/T4, S8 T4–T8): red снимается в `git worktree` на `<impl-commit>~1` с наложенным тест-файлом из HEAD через `MB_REPO_ROOT=<worktree> bash scripts/mb-work-state.sh eval-red …` (прецедент `85a0538`), green — на HEAD. Если владелец не принимает — закрывать с `eval_gate=unverified` и уликой-логом, без подделки.
- **Q3 — umbrella в валидаторе.** Umbrella не проходит `--require-scenarios` (53 REQ без GWT): (A, рекомендовано) остаётся в `KNOWN_FAILING` с обновлённой причиной «REQ покрыты child-спеками через delegate-гейты»; (B) дописать сценарии.
- **Q4 — S3/S5 ребейзлайн.** Задачи, уже покрытые `mb-lock.sh`/`mb-work-slots.sh`/ADaPT-lite, закрываются waiver-ом с ссылкой на коммит или переписываются под существующий код — решение по итогам Stage 11a/12a.

Решения фиксируются `mb-agree.sh add`.

## Waves

| Wave | Стадии (параллельно внутри волны) | Нужно до старта | Подагенты (пик) |
|---|---|---|---|
| 1 | 1 (оркестратор) · 2 · 5 | — | 2 |
| 2 | 3 · 4 · 6 | Stage 1 (Q1–Q2) | 3 исполнителя/фиксера + judge по очереди ≤4 |
| 3 | 7 · 8 · 10 | Stage 2 (для 8), Stage 3/4 закрыты | 3 + judge ≤4 |
| 4 | 9 · 11a · (10 продолжение) | Stage 6, 8 (work.md, agents/mb-judge.md) | 3 |
| 5 | 11b · 12a · (7 хвост T5) | 11a принят (Q4) | 3 |
| 6 | 12b | 11b T3 (scope-check), 7 T2 уже есть | 1–2 |
| 7 | 13 | все | 1 + full suite |

Сериализация общих файлов (нельзя в одной волне у двух треков): `commands/work.md` — 2 → 8(T5) → 9 → 11b(T4) → 12b(T3–T5); `references/templates.md` — 4(S8 T4 уже в коде) → 8(T3) → 7(T5); `commands/mb.md` — 4(S8 T5-патч, если нужен) → 7(T5) → 10(T4); `references/pipeline.default.yaml` + `scripts/mb-pipeline-validate.sh` — 10(T6) → 11b(T4) → 12b(T2); `agents/mb-judge.md`, `agents/mb-reviewer*.md` — 9 → 12b(T3); `commands/sdd.md` — только 8(T4); `scripts/_lib.sh` — только 7(T9); `tests/pytest/test_spec_corpus_battery.py`, `checklist.md`, `roadmap.md`, `status.md`, `progress.md`, `goal.md` — только оркестратор. Порядок приоритета внутри DAG — AGR-029 (T1→S1→S7→S4→S2→S8→S9→S6→S3→S5); при конфликте за слот побеждает более ранний по AGR-029.

`mb-work-plan.sh --target unfinished-work-completion --dry-run` пересчитывает волны из строк `**Files:**`.

## Общие правила стадий (TDD и проверки)

- Каждая спековая задача: Eval из `tasks.md` материализуется первым → `bash scripts/mb-work-state.sh eval-red --run-id <id> --cmd-file <cmd> --output-re '<output~:-якорь>'` наблюдает red → реализация → `eval-green` → `mb-work-state.sh done` (flip DoD; руками чекбоксы не ставить). Новых тестов с >5 моками нет; интеграционные — на реальных скриптах репо.
- Целевые прогоны во время работы: `bats <файлы Eval>`, `PYTHONPATH=. python3 -m pytest -q <файлы>`, `bash scripts/mb-test-run.sh --files <изменённые> --out human`; shellcheck/ruff только по изменённым файлам (`shellcheck -x --source-path=SCRIPTDIR <file>`, `ruff check <file>`). Полная батарея — один раз, в Stage 13 (и хуком при коммите волны — см. Q1).
- Закрытие спеки: `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/<s>` rc=0; `bash scripts/mb-sdd-self-check.sh` в фазе `--phase done` → `ready` (AGR-037); judge GO/GO_WITH_BACKLOG записан (`reports/svp-judge/<spec>.json` + строка в `progress.md`; если Stage 8 T2-журнал применим — также `mb-sdd-review-result.sh record --kind judge`); backlog-находки судьи → `backlog.md` до done; оркестратор удаляет спеку из `KNOWN_FAILING`.
- Покрытие изменённых модулей: `PYTHONPATH=. python3 -m pytest --cov=<модули> --cov-report=term-missing <тесты>` — core ≥95%, infra ≥70%, не ниже baseline; для bash — фактическое число bats-кейсов на каждую ветку C-контракта.
- Edge cases, общие для всех: путь банка с пробелами; Bash 3.2 (macOS) и Linux; зелёный только в рабочем дереве с чужим WIP ≠ зелёный на HEAD — финальную проверку стадии делать на чистом клоне/worktree HEAD (урок `dbfa870`).

## Stages

<!-- mb-stage:1 -->
### Stage 1: Подготовка исполнения и решения владельца

**Role:** orchestrator · **Size:** S · **Blocked-by:** —
**Files:** `.memory-bank/goal.md`, `.memory-bank/agreements.md` (через `mb-agree.sh`), `.memory-bank/orchestrator-console.md`, `.memory-bank/COORDINATION.md`

**What to do:** прочитать `mb-coord.sh active` (действует legacy FREEZE: без rebase/reset/checkout/stash); получить ответы Q1–Q4 и записать AGR; добавить этот план в `linked_plans` G-001 (статус по Q1); `bash scripts/mb-workflow.sh --workflow codex-governed --json` и `--workflow review-fix --json` — убедиться в составе шагов; `bash scripts/mb-work-codex-preflight.sh --json --mb .memory-bank` — codex доступен; записать STATUS на доску со списком файлов волны 1.

**DoD:** AGR по Q1–Q4 записаны (`mb-agree.sh list` показывает); `goal.md` ссылается на план; preflight `available:true` или зафиксирован degraded-режим ревью; доска содержит STATUS волны 1.

<!-- mb-stage:2 -->
### Stage 2: Разгрузка `commands/work.md` под зонный лимит 400 — CLOSED by master-completion Stage 4 (work.md room, 377 lines)

**Role:** developer · **Size:** S · **Blocked-by:** —
**Files:** `commands/work.md`, `references/work-reference.md`, тесты, которые пиннят перенесённые куски (найти `bash scripts/mb-graph.sh tests commands/work.md` + `grep -rl "commands/work.md" tests/`)

**What to do:** вынести ≥40 строк справочного текста (таблицы флагов/детали, не исполняемые шаги) из `commands/work.md` в `references/work-reference.md` со ссылкой; исполняемые шаги и клаузы, которые тестируются извлечением из `commands/work.md`, не переносить.

**TDD:** сначала прогнать все doc-тесты, читающие `commands/work.md` (baseline зелёный, список зафиксировать); после переноса — те же зелёные, `test_s2_file_size_contract.py` зелёный.

**DoD:** `wc -l commands/work.md` ≤ 360; все baseline doc-тесты зелёные; ни одна клауза, которую извлекает тест, не переехала; `bash scripts/mb-test-run.sh --files commands/work.md,references/work-reference.md --out human` — tests_pass.

**Edge cases:** тест вырезает bash-блок между заголовками (прецедент `c791eab`) — заголовки не переименовывать.

<!-- mb-stage:3 -->
### Stage 3: Закрытие S1 и S2 — conformance и судья

**Role:** architect (conformance) + judge · **Size:** M · **Blocked-by:** 1
**Executes:** umbrella T2 (S1), T4 (S2); `svp-interview-upgrade` T1–T6 (judge), `svp-sdd-core` T1–T9 (judge, C7 status)
**Files:** `.memory-bank/specs/svp-interview-upgrade/design.md`, `.memory-bank/specs/svp-sdd-core/{requirements,design}.md`

**What to do:** S1 — добавить ровно один блок `**Seams:**` вне фенсов (REQ-051, по образцу S2 `d023d03`); перепрогнать Eval всех 6 задач S1 и 9 задач S2 на HEAD; `/mb work svp-interview-upgrade --workflow review-fix` и `/mb work svp-sdd-core --workflow review-fix` — codex-ревью диффа спеки от `8bac761` до HEAD и judge; S2 — `status: draft → ready` только через C7 (`--phase done` батарея + разрешение ревью).

**TDD:** red-гейт для conformance — текущий `mb-spec-validate.sh --require-scenarios` S1 rc=1 (наблюдено 2026-11-05); green — rc=0. Regression: `test_s2_spec_status_honesty.py` зелёный после смены статуса.

**DoD:** validate S1 и S2 rc=0; umbrella T2 и T4 Eval зелёные; judge GO/GO_WITH_BACKLOG по обеим спекам записан; S1/S2 удалены из `KNOWN_FAILING` (оркестратор), `test_spec_corpus_battery.py` зелёный; umbrella T2/T4 DoD флипнуты `mb-work-state.sh done`.

**Edge cases:** NO_GO судьи → фикс-цикл ≤2 (`max_cycles`), затем `judge_decides`; блок Seams внутри ```-фенса не считается (`mb_spec_validate_v2.py:229`).

<!-- mb-stage:4 -->
### Stage 4: Закрытие S7 T1/T4 и S8 T4–T8 (реализовано, не отмечено) — CLOSED by master-completion Stage 16 (S7/S8 closed, AGR-103 shortcut)

**Role:** qa + judge · **Size:** M · **Blocked-by:** 1
**Executes:** `svp-brief` T1, T4 (+ judge всей спеки); `svp-contract-test-loop` T4–T8 (+ judge всей спеки); umbrella T8, T9
**Files:** `.memory-bank/specs/svp-brief/{design,tasks}.md`, `.memory-bank/specs/svp-contract-test-loop/{design,tasks}.md`, `commands/mb.md` (только если патч S8 T5 ещё нужен — сверить с текущим текстом), `.memory-bank/specs/svp-brief/` Eval задачи 3

**What to do:** ретро-red по Q2 для S7 T1 (`5d933fa~1`), T4 (`5d933fa~1` или коммит патча mb.md — определить `git log -- tests/bats/test_mb_brief_docs.bats`), S8 T4 (`a4f0ba0~1`), T5 (`2d6d372~1`), T6 (`2d88b5b~1`), T7 (`85a0538~1`), T8 (`cbd4d3d~1`); eval-green на HEAD; conformance: S7 — Seams + REQ-049 для T3 (Eval структурный по AGR-036 или перевод Scope); S8 — 8 CPR-D деклараций в `design.md` §Eval byte-identical `tasks.md` + Seams; `/mb work svp-brief --range 1,4 --workflow review-fix` и `/mb work svp-contract-test-loop --range 4-8 --workflow review-fix`.

**TDD:** red каждой задачи наблюдается в worktree по `output~:`-якорю задачи; green на HEAD: `bats tests/bats/test_mb_secret_scan_brief_input.bats tests/bats/test_mb_brief_command.bats tests/bats/test_mb_brief_docs.bats`, `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_sdd_layers_render.py tests/pytest/test_quality_dod_delivery.py tests/pytest/test_integration_contract_test_loop.py tests/pytest/test_e2e_contract_test_loop.py`, `bats tests/bats/test_mb_contract_gate.bats`.

**DoD:** open_dod S7 = 0 и S8 = 0; validate обеих rc=0; judge GO/GO_WITH_BACKLOG по S7 и S8; umbrella T8/T9 Eval зелёные; обе спеки удалены из `KNOWN_FAILING`; DoD «внешних моков ≤5» S8 T7 подтверждён подсчётом (в `85a0538` — 0).

**Edge cases:** red в worktree может упасть по чужой причине (exit 127, отсутствующий модуль) — принимать только red с совпавшим якорем; если якорь недостижим на `~1`, Q2-вариант `unverified` с логом.

<!-- mb-stage:5 -->
### Stage 5: Закрытие графовых стадий Pi Stage 3 и Codex Stage 2 — CLOSED by master-completion Stage 1 + Stage 6 (Pi Stage 3 fixture, Codex Stage 2)

**Role:** debugger · **Size:** S · **Blocked-by:** —
**Executes:** `plans/2026-10-05_feature_pi-native-integration.md` Stage 3; `plans/2026-10-09_feature_codex-memory-parity.md` Stage 2
**Files:** `tests/fixtures/pi_native_graph_host.mjs`, `tests/pytest/test_pi_native_graph.py`

**What to do:** Pi — тест зависит от Pi-пакета из `npm root -g`; когда `PI_PACKAGE_ROOT` не задан и пакет/`jiti` не резолвится, тест должен пропускаться с явной причиной (`pytest.skip("pi package with jiti not found: <path>")`), а при наличии — резолвить пакет рядом с бинарём `pi` из `PATH`; затем зелёный прогон с `PI_PACKAGE_ROOT=<nvm>/lib/node_modules/@earendil-works/pi-coding-agent`. Открытый пункт DoD «verify/review/judge» закрывается по AGR-089 верификатором на уровне плана Pi (ссылка в отчёте). Codex — Stage 2 закрывается по уликам плана («Current verification evidence», Graph) и прогону.

**TDD:** red — текущий прогон 15/15 FAIL `Cannot find module 'jiti'` (наблюдено); green — 15 passed с `PI_PACKAGE_ROOT`, 15 skipped с причиной без него (не FAIL, не silent pass).

**DoD:** `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_pi_native_graph.py tests/pytest/test_pi_native_embeddings.py` зелёный в обоих режимах; `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_graph_query_precision.py tests/pytest/test_codegraph_invocations.py` 18 passed; чек-боксы Stage 3 (Pi) и Stage 2 (Codex) в `checklist.md` отмечены оркестратором с хешами `b1bbbbf`/`f050443` в `progress.md`.

**Edge cases:** skip не должен маскировать реальный провал при найденном пакете.

<!-- mb-stage:6 -->
### Stage 6: graph-semantic-adoption Stage 5 — статус графа в диспатче — CLOSED by master-completion Stage 6 (graph status on dispatch)

**Role:** developer · **Size:** S · **Blocked-by:** —
**Executes:** `plans/2026-07-28_fix_graph-semantic-adoption.md` Stage 5 (DoD и тесты — там)
**Files:** `hooks/mb-context-slim-pre-agent.sh`, `tests/bats/test_mb_context_slim_pre_agent.bats` (имя сверить с существующими: `ls tests/bats hooks/tests | grep slim`)

**What to do:** по тексту Stage 5: ≤3 строк `code graph: fresh|stale (<age>)` + `mb-graph.sh who-calls <Symbol>`; статус из метаданных/кэша, пропуск при >200 мс; нет графа — инжект без изменений.

**TDD:** bats-кейсы Stage 5 красные до правки: `code graph: fresh` при свежем графе; без графа — вывод байт-идентичен; `wc -l` добавки ≤3; время хука на фикстуре.

**DoD:** DoD Stage 5 плана-источника; shellcheck чистый; ручная проверка в verify перехваченного промпта.

<!-- mb-stage:7 -->
### Stage 7: S4 `svp-roadmap-backlog-db` — остаток — CLOSED by master-completion Stage 17 (S4 remainder)

**Role:** backend · **Size:** L · **Blocked-by:** 3 (S2 закрыта), 4 (общий `templates.md`)
**Executes:** `svp-roadmap-backlog-db` T9, T7 → T3 → T8 → T4 → T5 (порядок по `Blocked-by` задач); conformance; umbrella T3
**Files:** `scripts/_lib.sh`, `scripts/mb-idea.sh`, `scripts/mb-idea-promote.sh`, `scripts/mb-backlog-state.sh`, `scripts/mb-backlog-migrate.sh`, `scripts/mb-bank-lint.sh`, `commands/mb.md` (T5), `references/templates.md` (T5, после Stage 8 T3), `CLAUDE.md` (T5), тест-файлы Scope задач, `.memory-bank/specs/svp-roadmap-backlog-db/design.md`

**What to do:** `/mb work svp-roadmap-backlog-db --range 3-9 --workflow codex-governed`; внутри трека T9 и T7 параллельны (непересекающиеся файлы), остальное последовательно; conformance — Seams, REQ-049 T5.

**TDD:** Eval каждой задачи red по якорю до реализации (T9: `test_mb_backlog_id_alloc.bats` + `test_mb_idea_promote_v2.bats`; T7: `test_mb_backlog_state_hierarchy.bats`; T3: `test_mb_backlog_migrate.bats`; T8: `test_mb_backlog_out_of_scope.bats`; T4: `test_mb_bank_lint.bats`; T5: `test_mb_roadmap_backlog_docs.bats`).

**DoD:** open_dod S4 = 0; validate rc=0; judge GO/GO_WITH_BACKLOG; umbrella T3 Eval зелёный; коллизия I-079 воспроизведена тестом T9; регрессия `test_mb_roadmap_sync_ice.bats`, `test_mb_roadmap_sync_group.bats`, `test_mb_backlog_state.bats`, `test_mb_lock_helper.bats` зелёная; `mb-roadmap-sync.sh` на этом банке не меняет § Group (кроме прогресса).

**Edge cases:** мигратор на живом `backlog.md` (168 KB) — только на копии в тесте; позиционные вызовы `mb-idea.sh` byte-identical.

<!-- mb-stage:8 -->
### Stage 8: S9 `svp-spec-review-loop` — остаток

**Role:** backend/developer · **Size:** M · **Blocked-by:** 2 (work.md), 3 (S2 — владелец формата журнала, I-157)
**Executes:** `svp-spec-review-loop` T3 → T4, T5 (T5 после T3 не требуется по Blocked-by — только 2); conformance; umbrella T10
**Files:** `scripts/mb-sdd-review-prompt.sh`, `references/spec-review-rubric.md`, `references/templates.md`, `tests/bats/fixtures/spec-review/**`, `commands/sdd.md`, `scripts/mb-work-spec-gate.sh`, `commands/work.md`, тест-файлы Scope, `.memory-bank/specs/svp-spec-review-loop/{design,tasks}.md`

**What to do:** `/mb work svp-spec-review-loop --range 3-5 --workflow codex-governed`; conformance — назначить Covers для REQ-014..017 (или привести требования к задачам), 5 CPR-D деклараций, Seams, REQ-049 T4.

**TDD:** red по якорям: `test_spec_review_prompt.bats`, `test_sdd_review_loop.bats`, `test_work_spec_gate.bats` (`work_spec_gate_*`); регрессия `test_spec_judge_config.bats`, `test_spec_judge_journal.bats`, `test_sdd_decide.bats`, `test_sdd_spec_review_r4.bats`.

**DoD:** open_dod S9 = 0; validate rc=0; judge GO/GO_WITH_BACKLOG; umbrella T10 Eval зелёный; `commands/work.md` ≤ 400 и `test_s2_file_size_contract.py` зелёный; `mb-sdd-review-result.sh` ≤ 400 (AGR-035).

**Edge cases:** гейт молчит при `enabled: false` и без журнала (plan-таргеты не затронуты); legacy-строки `{"status":"decided"}` без `kind` (`4e385a4`) — громкий `status_unreadable`, не тихий пропуск.

<!-- mb-stage:9 -->
### Stage 9: graph-semantic-adoption Stage 7 — граф в каждом диспатче + замер — CLOSED by master-completion Stages 5, 7, 22 (graph in every dispatch, demo, test mapping)

**Role:** developer · **Size:** M · **Blocked-by:** 6, 8 (общий `commands/work.md`)
**Executes:** `plans/2026-07-28_fix_graph-semantic-adoption.md` Stage 7 — только недостающее (см. таблицу состояния)
**Files:** `commands/work.md` (§5c/§5d/§5e), `agents/mb-judge.md`, `agents/mb-reviewer-logic.md` (`compose:`), `agents/plan-verifier.md`, `agents/mb-engineering-core.md`, `hooks/mb-graph-nudge.sh`, `scripts/mb-cost-report.py`, `tests/pytest/test_graph_dispatch_docs.py`, `tests/bats/test_mb_graph_nudge.bats`, `tests/pytest/test_mb_cost_report.py`, `CHANGELOG.md`

**What to do:** по тексту Stage 7; не дублировать уже сделанный compose `mb-tooling-core` у developer/verifier/reviewer; push-блок `## Graph` ≤40 строк, fail-open.

**TDD:** red-первыми — doc-pytest `test_graph_dispatch_docs.py`, bats `marker is per session+agent` / `subagent gets its own first nudge` / `off-switch`, pytest `test_graph_and_grep_calls_counted_per_role`, `test_graph_share_zero_when_no_lookups`.

**DoD:** первые два пункта DoD Stage 7 источника (демо-item с `graph_share` implementer ≥0.5, verifier ≥1 запрос; тесты, shellcheck, ruff, CHANGELOG); `commands/work.md` ≤ 400. **Третий пункт (замер через 7 дней) — отложенный:** напоминание в `orchestrator-console.md`/backlog с датой, Stage 7 источника остаётся открытой до замера (AGR-049); G-001 от него не зависит.

<!-- mb-stage:10 -->
### Stage 10: S6 `svp-docs-wiki`

**Role:** backend/developer · **Size:** L · **Blocked-by:** 3 (S2), задачный блокер `svp-roadmap-backlog-db#2` уже done
**Executes:** `svp-docs-wiki` T1, T5 (параллельно) → T3 → T7, T2 → T6 → T4; conformance; umbrella T5
**Files:** `memory_bank_skill/docs_{state,ingest,store,run,lint}.py`, `scripts/mb-docs.py`, `scripts/mb-docs-apply.sh`, `agents/mb-docs-author.md`, `agents/mb-docs-synthesizer.md`, `references/pipeline.default.yaml` + `scripts/mb-pipeline-validate.sh` (T6), `commands/mb.md` (T4, после Stage 7 T5), фикстуры `tests/fixtures/{docs-repo,wiki-ok,wiki-broken,docs-manifest}/**`, тест-файлы Scope, `.memory-bank/specs/svp-docs-wiki/design.md`

**What to do:** `/mb work svp-docs-wiki --workflow codex-governed`; conformance — Seams, REQ-049 T5 (`test_mb_docs_agents.py` целится в doc-файлы → по AGR-036 может стать структурным; проверить после написания теста). Не пересекаться с существующим `/mb wiki` (`scripts/mb-wiki.py`, `memory_bank_skill/wiki_store.py`) — разные команды и каталоги.

**TDD:** Eval каждой задачи red до реализации (pytest/bats из Scope); интеграционные — на фикстурном git-репо, без моков кроме LLM-агентов.

**DoD:** open_dod S6 = 0; validate rc=0; judge GO/GO_WITH_BACKLOG; umbrella T5 Eval зелёный; покрытие новых `memory_bank_skill/docs_*.py` ≥95%; `/mb docs` на фикстурном репо генерирует и обновляет вики (DoD umbrella T5).

<!-- mb-stage:11 -->
### Stage 11: S3 `svp-parallel-engine` — ребейзлайн (11a) и реализация (11b)

**Role:** architect (11a), backend (11b) · **Size:** XL · **Blocked-by:** 11a — 3; 11b — 11a принят (Q4), 9 (work.md), 10 T6 (pipeline.default.yaml)
**Executes:** `svp-parallel-engine` T1–T10; umbrella T7
**Files:** 11a — `.memory-bank/specs/svp-parallel-engine/{requirements,design,tasks}.md`; 11b — Scope задач: `scripts/mb_work_items.py`, `scripts/mb-work-claims.sh`, `scripts/mb-work-scope-check.sh`, `scripts/mb-work-resolve.sh`, `tests/fixtures/svp_group_ordering.json`, `scripts/mb-work-diff.sh`, `scripts/mb-work-state.sh`, `scripts/mb_parallel_scheduler.py`, `scripts/mb-work-dispatch.sh`, `scripts/mb-subinvoke-resolve.sh`, `commands/work.md`, `references/pipeline.default.yaml`, `scripts/mb-pipeline-validate.sh`, `adapters/{pi,opencode,cursor}.sh`, тест-файлы Scope

**What to do:** 11a — delta-review спеки против `scripts/mb-lock.sh`, `scripts/mb-work-slots.sh` (MB_WORK_PARALLEL), `/mb team` (`specs/mb-team`, `specs/team-completion`), `mb_lock_acquire` (S4-C6): для каждой задачи — «строить», «переиспользовать существующее (Scope меняется)» или «waiver со ссылкой на коммит»; ревью дельты через S9-петлю (`commands/sdd.md` шаг 9, если Stage 8 закрыт) или codex вручную; validate rc=0 (Seams). 11b — `/mb work svp-parallel-engine --workflow codex-governed` по порядку `Blocked-by`: T1, T8 → T3, T5, T2 → T7, T10 → T9 → T4 → T6.

**TDD:** red по якорям Eval каждой задачи; race-тест T2 — на конкурентных процессах (ровно один победитель); byte-identical регрессии дефолтных режимов (T1, T5, T7, T8).

**DoD:** решение Q4 записано AGR; open_dod S3 = 0; validate rc=0; judge GO/GO_WITH_BACKLOG; umbrella T7 Eval зелёный («параллельный прогон на фикстурной спеке без конфликтов записи»); `test_platform_limited_honesty.bats` зелёный; ни одной второй реализации lock/slots (проверка ревьюером по `mb-graph.sh impact mb_lock_acquire`).

**Edge cases:** git недоступен → exit 3 `unavailable` (T7); Cursor честно деградирует (AGR-020); промпт не интерполируется в шелл (T10).

<!-- mb-stage:12 -->
### Stage 12: S5 `svp-adapt-escalation` — ребейзлайн на ADaPT-lite (12a) и остаток (12b) — CLOSED by master-completion Stage 18 (S5 rebased on ADaPT-lite, AGR-107)

**Role:** architect (12a), backend/qa (12b) · **Size:** L · **Blocked-by:** 12a — 3; 12b — 12a принят (Q4), 11b T3 (`mb-work-scope-check.sh`), 7 (S4), 11b T4 (work.md)
**Executes:** `svp-adapt-escalation` T1–T5; umbrella T6
**Files:** 12a — `.memory-bank/specs/svp-adapt-escalation/{requirements,design,tasks}.md`, `references/adapt.md` (§ Lite slice); 12b — Scope после ребейзлайна (ожидаемо `scripts/mb_work_adapt.py` вместо `scripts/mb-work-adapt.sh`, `adapt:` вместо `escalation:` в `references/pipeline.default.yaml`, `commands/work.md`, `agents/mb-*.md`, `agents/plan-verifier.md`, тест-файлы)

**What to do:** 12a — сопоставить REQ-001…010 с ADaPT-lite (`190251c`, AGR-080/082); покрытые части задач T1–T3 — waiver/перенос Scope на существующие файлы; непокрытое (scope-гард REQ-002, stubs REQ-004, журнал REQ-007/008, cascade REQ-010) — оставить задачами; Seams, REQ-049 T3/T4. 12b — `/mb work svp-adapt-escalation --workflow codex-governed`.

**TDD:** для покрытого ADaPT-lite — существующие тесты (`grep -rl mb_work_adapt tests/`) как green-улика + ретро-red по Q2 на `190251c~1`; для нового — red по якорям Eval.

**DoD:** AGR по Q4; open_dod S5 = 0; validate rc=0; judge GO/GO_WITH_BACKLOG; umbrella T6 Eval зелёный (эскалации логируются JSONL); `adapt.verify_fail_cycles: 3` по умолчанию не изменён (AGR-082); журнал эскалаций пишется под `mb_lock_acquire` (umbrella design:77).

<!-- mb-stage:13 -->
### Stage 13: Umbrella и закрытие G-001

**Role:** orchestrator + judge + verifier · **Size:** M · **Blocked-by:** 3, 4, 7, 8, 10, 11, 12 (Stages 5, 6, 9 — для плана, не для G-001)
**Executes:** umbrella T2–T10 (delegate-гейты), judge umbrella; acceptance G-001
**Files:** `.memory-bank/specs/sdd-vision-pipeline/{requirements,tasks}.md`, `tests/pytest/test_spec_corpus_battery.py`, `.memory-bank/goal.md`, `roadmap.md`, `status.md`, `checklist.md`, `progress.md`, `backlog.md`, `traceability.md`

**What to do:** `goal.md` `status: paused → active` (Q1-A); прогнать Eval umbrella T2–T10 и флипнуть DoD через `mb-work-state.sh`; umbrella по Q3; `/mb work sdd-vision-pipeline --workflow review-fix` — judge umbrella; полный прогон; актуализировать roadmap § Group (`bash scripts/mb-roadmap-sync.sh .memory-bank`), status, checklist, progress (append); `goal.md` acceptance — каждый пункт `[x]` с ссылкой на улику; `bash scripts/mb-flow-verify.sh .memory-bank` exit 0 → `status: done`; scoped-коммит.

**Verification:**
```bash
bats tests/bats/ && bats tests/e2e/ && bats hooks/tests/*.bats
PYTHONPATH=. python3 -m pytest hooks/tests/ tests/pytest/ -o python_files='*_test.py test_*.py' --cov --cov-report=term-missing --cov-fail-under=85
shellcheck -x --source-path=SCRIPTDIR scripts/*.sh && shellcheck hooks/*.sh && shellcheck -x --severity=error hooks/lib/*.sh adapters/*.sh install.sh
ruff check scripts/ hooks/lib/ memory_bank_skill/ settings/ tests/pytest/
for s in svp-interview-upgrade svp-sdd-core svp-brief svp-roadmap-backlog-db svp-contract-test-loop svp-spec-review-loop svp-docs-wiki svp-parallel-engine svp-adapt-escalation; do bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/$s || echo "RED $s"; done
bash scripts/mb-flow-verify.sh .memory-bank
```
Полный bats идёт долго (установки адаптеров — минуты каждая): запускать фоном один раз, падения триажить против чистого HEAD (worktree) — предсуществующие падения записываются с уликой, не перекрашиваются.

**DoD:** все 9 child-спек: open_dod 0, validate rc=0, judge GO/GO_WITH_BACKLOG записан; umbrella 10/10 задач закрыты, judge umbrella GO/GO_WITH_BACKLOG; полная батарея и shellcheck error-gate зелёные (или предсуществующие падения доказаны на HEAD и вынесены в backlog с согласия владельца); `mb-flow-verify` exit 0; G-001 `status: done`, все 5 пунктов acceptance `[x]`; roadmap § Group progress=100%.

## Risks and mitigation

| Risk | Probability | Mitigation |
|---|---|---|
| Хук pre-commit гоняет всю батарею на каждый коммит | H | Коммит один на волну; Q1; без `MB_FLOW_CLOSURE=off` без явного разрешения на конкретный коммит |
| Два трека правят один файл (`work.md`, `templates.md`, `mb.md`, `pipeline.default.yaml`) | H | Сериализация из § Waves; AGR-032; файлы доски/корпуса — только оркестратор |
| Ретро-red недостижим на `~1` | M | Q2: честный `unverified` с логом вместо фиктивного red |
| S3/S5 дублируют существующий код | M | Ребейзлайн 11a/12a с решением владельца до кода |
| Зелёный держится на чужом WIP рабочего дерева | M | Финальная проверка стадии на чистом worktree HEAD |
| Codex-ревью недоступно/висит | M | preflight; degraded-режим с NOTE в progress (work.md §5d) |
| Полная батарея красная по окружению (как Pi `jiti`) | M | Stage 5-подход: явный skip с причиной, триаж против HEAD |

## Gate

G-001 `status: done`: 10/10 спек группы с judge GO/GO_WITH_BACKLOG и зелёными delegate-гейтами, полная батарея и shellcheck error-gate зелёные, `mb-flow-verify.sh` exit 0; плюс graph-semantic-adoption Stage 5 закрыта, Stage 7 закрыта кроме отложенного недельного замера, Pi Stage 3 и Codex Stage 2 отмечены с уликами.

## Follow-ups (вне scope, не исполняются этим планом)

- Pre-commit хук гейтит по наличию `goal.md`, игнорируя `status:` (в отличие от `hooks/mb-flow-closure-guard.sh:187`) — расхождение предикатов.
- `checklist.md` для pi-native-integration показывает 0/5, а план — Stages 1–4 `done`; рассинхрон счётчиков других стадий Pi.
- `KNOWN_FAILING` в `test_spec_corpus_battery.py` содержит устаревшие причины (S1 «6 CPR-D drifts» — фактически только Seams).
- `.pi/extensions/memory-bank-graph-rag.ts` в корне репо не отслеживается и не игнорируется.
- Локальный `pytest` требует `PYTHONPATH=.` (нет editable-установки в pyenv 3.13.4).
- `scripts/mb-spec-validate.sh` ровно 400 строк — следующая правка валидатора уронит зонный контракт.
