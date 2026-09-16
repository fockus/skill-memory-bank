---
type: fix
topic: i208-test-battery
status: done
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-16
---
# Plan: fix — i208-test-battery · полная батарея зелёная (I-208)

**Baseline commit:** 0c0e50a6076944cb03d40c0dd1549ad731030962

## Context

**Problem:** `I-208` (`[review S1 judge]`, HIGH) — Gate Sprint 1 `mb-work-cost-diet` требует `tests_pass: true`, но батарея красная. Замер baseline на 0c0e50a (macOS, `.venv/bin/python` 3.14, bats 1.13.0):

- **pytest** `tests/pytest`: `12 failed, 2550 passed, 26 skipped`
- **bats** `tests/bats`: 13 реальных падений + **10 тестов вообще не исполняются** (`bats warning: Executed 3356 instead of expected 3366`)

Двенадцать независимых корневых причин, каждая воспроизведена вручную:

| # | Симптом | Корень | Класс |
|---|---|---|---|
| A | `test_audit_completion.py::test_done_source_relative_init_cannot_certify_other_cwd[legacy-directory]` | `eval_declaration` (aaa1b2b) считает поверхностью декларации ЛЮБОЙ резолвнутый `tasks.md`; legacy-локатор `work/` резолвит `work/tasks.md`, где лежит stage-маркерный ПЛАН → `NOITEM` вместо `NOFILE`, `done` exit 5 | регрессия продукта (моя) |
| B | 4 bats `artifact_write` (`topic with uppercase / double dash`, ×3 `invalid topic still consumes the credential candidate`) | `valid_topic`: `case … *[!a-z0-9-]*` — диапазон `a-z` в non-C локали идёт по collation, `Foo` проходит как валидный → нет отказа → candidate с секретом остаётся на диске | баг продукта (безопасность) |
| C | `test_mb_lint_run.bats::lint/integration: real ruff dirty python → ok=false` | `mb-lint-run.sh:110` матчит `:[0-9]+:[0-9]+:` по выводу ruff; при `FORCE_COLOR` в окружении ruff красит вывод даже в файл (`bad.py\e[0m\e[36m:\e[0m1…`) → 0 findings → `ok=true` при реальной ошибке F401 | баг продукта |
| D | 3 bats `brief_docs` (router-row, ×2 router-synopsis) | `commands/mb.md` не содержит ни строки роутера на `commands/brief.md`, ни блока `### brief`; `git log -S` подтверждает: ссылки не было НИКОГДА — тесты написаны красными и не дожаты | пробел в доках (тест = спека) |
| E | 10 тестов `test_mb_interview_artifact_check_transcript.bats` не исполняются | кириллица в именах `@test` ломает мангling bats 1.13 (`bats: unknown test name $'…_Унаследовано_sections_are_rejected'`), исполнение файла обрывается. Ровно 10 таких имён во всём репозитории — и ровно эти 10 не идут | целостность батареи |
| F | 4 pytest `test_cli.py` (install/uninstall/manifest) | `_run_install_sh` (строка 471) прибивает `PATH=/usr/local/bin:/usr/bin:/bin:…` без префикса Homebrew → `python3` резолвится в системный 3.9 → `dep_python3_version=missing` → install.sh честно отказывает rc 1 | баг теста |
| G | 7 pytest `test_wiki_staleness.py` | `networkx` объявлен только в extra `codegraph`; CI ставит `.[codegraph,yaml]`, dev-окружение — нет. Без него сообществ 0, фикстура отдаёт `{}` | необъявленная dev-зависимость |
| H | 4 bats `test_test_runner_python.bats` | `teardown()` заканчивается на `[ -n "${TMPROOT:-}" ] && [ -d … ] && rm -rf …`; при `skip` в setup TMPROOT не выставлен → teardown возвращает 1 → bats метит тест `not ok` | баг теста |
| I | `test_mb_glossary.bats::concurrent upserts never lose a successful entry` (флак под нагрузкой) | в сабшелле `_concurrent_upserts` под errexit неуспешный `$SCRIPT upsert` обрывает сабшелл ДО `printf … > $RC_DIR/$i` → `cat: …/rc/1: No such file` ровно в том случае, ради которого тест написан | баг теста |
| J | `test_session_prune_reindex.bats::--apply still exits 0 and skips the trigger when no python is runnable` | тест гоняет удалённое поведение: после I-132 `mb-session-prune.sh:99-105` не спавнит python, а просто трогает `.index/.dirty`; `MB_SEMANTIC_PY` ни на что не влияет, `reindex=1` всегда | устаревший тест |
| K | `artifact_write: a signal before the claim does not delete another run's candidate` | тест паркует писателя подменой `basename` на 2-м вызове; в текущем пайплайне до 2-го вызова (`mb-interview-artifact-write.sh:384`) управление не доходит — окно «arm ↔ claim» сместилось | тест завязан на счётчик вызовов |
| L | 2 bats `test_agent_graph_routing.bats` (impact / status) | 59ffc7c перевёл `agents/plan-verifier.md` на `"$SKILL_DIR/scripts/mb-graph-query.py" impact`; тест ищет литерал `mb-graph-query.py impact` — кавычка между именем и подкомандой рвёт совпадение. Блок в файле ЕСТЬ | паттерн теста |

**Expected result:** `tests/pytest` и `tests/bats` зелёные целиком, число исполненных bats-тестов равно `bats --count` (3366), каждая правка продукта закрыта TDD-тестом, виденным красным (AGR-027), `I-208` → DONE.

**Related files:**
- продукт: `scripts/mb-work-state-lib.sh::eval_declaration`, `scripts/mb-interview-artifact-write.sh::valid_topic`, `scripts/mb-lint-run.sh::run_python`, `commands/mb.md`
- тесты: `tests/bats/test_mb_interview_artifact_check_transcript.bats`, `tests/bats/test_test_runner_python.bats`, `tests/bats/test_mb_glossary.bats`, `tests/bats/test_session_prune_reindex.bats`, `tests/bats/test_mb_interview_artifact_write.bats`, `tests/bats/test_agent_graph_routing.bats`, `tests/pytest/test_cli.py`
- сборка: `pyproject.toml` (`[project.optional-dependencies] dev`)
- `CHANGELOG.md` § Unreleased → Fixed

**Не в объёме:** `I-192` (`go test` без таймаута — отдельный слайс; `mb-test-run.sh` в этом плане не запускается), `I-209` и прочие находки ревью, `tests/e2e/` и `hooks/tests/` (отдельные наборы, в I-208 не заявлены).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: E — десять тестов, которые не исполнялись, начинают исполняться

**Role:** qa

**What to do:**
- `tests/bats/test_mb_interview_artifact_check_transcript.bats`: перевести на ASCII ИМЕНА десяти `@test` (номера 20, 21, 24, 26, 27, 28, 34, 36, 44, 49) — кириллические слова в имени заменить английскими (`Унаследовано` → `inherited`, `Отклонено` → `rejected`, `Ответ` → `answer`, `круг` → `round`, `Финальный гейт` → `final gate`). Тела тестов, фикстуры и утверждения НЕ трогать: кириллица там — предмет проверки и обязана остаться дословно.
- Стрелки `→` и тире `—` в именах не трогать: они не-ASCII, но демонстрируемо работают (74/74 в `test_lib.bats`, 33/33 в `test_mb_brief_validate.bats`).
- Новый охранный тест делает ловушку ненаписуемой: ни одно имя `@test` в `tests/bats/`, `tests/e2e/`, `hooks/tests/` не содержит кириллических букв.

**Testing (TDD — красный прогон обязателен):**
- `tests/bats/test_bats_test_names.bats` (новый): `bats_test_names: no @test name carries cyrillic letters` — обходит `tests/bats/*.bats tests/e2e/*.bats hooks/tests/*.bats`, вытаскивает имена `sed -nE 's/^@test "(.*)" \{.*/\1/p'`, падает со списком файл+имя при совпадении `[А-Яа-яЁё]`. До переименования красный (10 имён), после — зелёный.
- Доказательство исполняемости: `bats --count tests/bats/test_mb_interview_artifact_check_transcript.bats` == число строк `^(ok|not ok) ` в прогоне того же файла. До правки 51 против 41.

**DoD:**
- [x] `bats tests/bats/test_mb_interview_artifact_check_transcript.bats` печатает 51 результат, 0 `not ok`, без `bats warning: Executed … instead of expected …`
- [x] Новый `test_bats_test_names.bats` зелёный; его красный прогон на неисправленном файле зафиксирован в отчёте
- [x] Ни один ассерт/фикстура внутри тел тестов не изменён (диф по файлу затрагивает только строки `^@test `)

**Edge cases:** имя с `##` мангбится в `-23-23` — после ASCII-фикации остаётся валидным идентификатором; охранный тест не должен падать на файлах без `@test`.

<!-- mb-stage:2 -->
### Stage 2: A — stage-маркерный план по пути `tasks.md` снова не поверхность декларации

**Role:** backend

**What to do:**
- `scripts/mb-work-state-lib.sh::eval_declaration`: ветка «распарсилось, но `task`-элементов нет» перестаёт выдавать `NOITEM` только по имени файла. `NOITEM` в ней остаётся, когда элементов НЕТ ВООБЩЕ (пустой / без маркеров `tasks.md` — это и есть находка I-196); если элементы есть, но они `stage`, файл является планом, и управление уходит на `NOFILE` — поведение 85e39bb.
- Ветка «парсер бросил исключение» не меняется: содержимое там непрочитано, имя файла — единственный доступный признак, `NOITEM` для `tasks.md` сохраняется (смешанные маркеры → `ValueError`).
- Комментарий контракта привести в соответствие: `tasks.md` без ЕДИНОГО элемента либо непарсимый — поверхность декларации, fail closed; `tasks.md` со stage-маркерами — план.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка.

**Testing (TDD — красный прогон обязателен):**
- `tests/pytest/test_audit_completion.py::test_done_source_relative_init_cannot_certify_other_cwd[legacy-directory]` — существующий, сейчас КРАСНЫЙ (`[work-state] done: task #1 not found in the declared source`), после правки зелёный. Это и есть красный прогон.
- `tests/bats/test_mb_work_state_plan_source.bats`: три теста I-196 (пустой `tasks.md`, искалеченные маркеры, смешанные маркеры → `done` rc 5) остаются зелёными — иначе правка откатила I-196.
- Новый `tests/bats/test_mb_work_state_plan_source.bats::a stage-marker plan resolved at tasks.md is a plan, not a task surface` — `work/tasks.md` с одним stage-маркером первой стадии, `done` rc 0 и `decl.verdict == NOFILE`. Красный до правки (rc 5).

**DoD:**
- [x] `test_audit_completion.py` зелёный целиком (все параметры locator)
- [x] `bats tests/bats/test_mb_work_state_plan_source.bats` — 6/6 зелёных, включая три теста I-196
- [x] `scripts/mb-work-state-lib.sh` ≤ 400 строк (зонный контракт AGR-035 сюда не распространяется, но файл уже 381 — рост контролируем)
- [x] `shellcheck -S error scripts/mb-work-state-lib.sh` чист

**Edge cases:** `tasks.md` с `task`-элементами, но без запрошенного номера — `NOITEM` как и раньше; план без маркеров вообще по пути НЕ `tasks.md` — `NOFILE`.

<!-- mb-stage:3 -->
### Stage 3: B — валидация topic перестаёт зависеть от локали

**Role:** backend

**What to do:**
- `scripts/mb-interview-artifact-write.sh::valid_topic`: заменить зависимый от collation диапазон `*[!a-z0-9-]*` на явное перечисление допустимых ASCII-символов, чтобы `Foo`, `TOPIC`, `Ä` отвергались в любой локали. Правила `-*|*-|*--*` не меняются.
- `scripts/mb-brief.sh:98` — тот же класс (`grep -qE '^[a-z0-9][a-z0-9-]*$'`, диапазоны ERE тоже идут по collation). Привести к локале-независимой проверке. Это корень, а не симптом: одна и та же ловушка в двух валидаторах слага.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка.

**Testing (TDD — красный прогон обязателен):**
- Существующие красные: `artifact_write: topic with uppercase / double dash → exit 2`, `an invalid topic still consumes the credential candidate`, `a candidate-SHAPED name is still consumed on an invalid topic`, `an INVALID topic still consumes the candidate it was handed`.
- Новый тест на локаль-независимость в `tests/bats/test_mb_interview_artifact_write.bats`: под `LC_ALL=en_US.UTF-8` и под `LC_ALL=C` topic `Foo` даёт `exit 2` + `stderr = error=topic`. Красный до правки под UTF-8.
- Новый тест в наборе `mb-brief`: `--topic Foo` отвергается под обеими локалями.

**DoD:**
- [x] `bats tests/bats/test_mb_interview_artifact_write.bats` — 0 `not ok`, кроме теста K (Stage 7), если он ещё не чинен
- [x] Тесты валидации topic зелёные и под `LC_ALL=C`, и под `LC_ALL=en_US.UTF-8`
- [x] `shellcheck -S error` чист на обоих изменённых скриптах
- [x] Ни один валидный kebab-case topic не потерян: `a`, `a-b`, `a1-b2`, `x9` принимаются

**Edge cases:** пустой topic; `--` внутри; ведущий/замыкающий дефис; не-ASCII буква (`café`); topic длиной 1.

<!-- mb-stage:4 -->
### Stage 4: C — линтер перестаёт считать раскрашенный вывод ruff чистым

**Role:** devops

**What to do:**
- `scripts/mb-lint-run.sh::run_python`: сделать вывод ruff машиночитаемым независимо от окружения. Предпочтительно — гасить раскраску у дочернего процесса (`NO_COLOR=1`, сброс `FORCE_COLOR`/`CLICOLOR_FORCE`) И снимать ANSI-escape с прочитанных строк перед матчингом, чтобы проверка не зависела от того, уважает ли конкретная версия ruff переменную.
- То же применить к `run_shell`, если shellcheck там парсится по такому же шаблону: одна ловушка — одна правка.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка.

**Testing (TDD — красный прогон обязателен):**
- Существующий красный: `lint/integration: real ruff dirty python → ok=false`.
- Новый: `lint: a colorized ruff run still yields ok=false` — стаб `ruff`, печатающий ANSI-раскрашенную диагностику; ожидается `ok=false` и findings ≥ 1. Красный до правки при любом значении `FORCE_COLOR`.
- Регресс: `lint/integration: real ruff clean python → ok=true` остаётся зелёным.

**DoD:**
- [x] `bats tests/bats/test_mb_lint_run.bats` — 0 `not ok` и при `FORCE_COLOR=3`, и без него
- [x] `ok=false` воспроизводится на реальном `ruff` в этом окружении
- [x] `shellcheck -S error scripts/mb-lint-run.sh` чист

**Edge cases:** ruff не в PATH (`ok=null`, поведение не меняется); вывод без диагностик; строка с двоеточиями внутри текста сообщения.

<!-- mb-stage:5 -->
### Stage 5: D — `commands/mb.md` получает строку роутера и блок `### brief`

**Role:** analyst

**What to do:**
- `commands/mb.md`: добавить в таблицу `### Routing` ровно одну строку для `brief <topic>`, диспатчащую на `commands/brief.md`, и блок `### brief` с синопсисом C0: `/mb brief <topic>`, флаги `--request`, `--request-file`, `--input` (помеченный как повторяемый — `[--input <path>]…`), `--auto`. Флаг `--update` не упоминать (это проверяют зелёные сейчас тесты 922/923).
- Содержание синопсиса взять из `commands/brief.md`, не выдумывать; расхождение между роутером и командным файлом — тот же класс дефекта, что чинится.

**Testing (TDD — красный прогон обязателен):**
- Существующие красные: `brief_docs: router-row`, `brief_docs: router-synopsis — the ### brief block carries the C0 synopsis`, `brief_docs: router-synopsis — the block marks --input as repeatable`.

**DoD:**
- [x] `bats tests/bats/test_mb_brief_docs.bats` — 0 `not ok` (все 7)
- [x] Ровно ОДНА строка роутера ведёт на `commands/brief.md` (тест считает `-eq 1`)
- [x] Синопсис в `commands/mb.md` не противоречит `commands/brief.md` — сверка флагов вручную, расхождения нет

**Edge cases:** таблица роутинга обрывается по `^---` — новая строка обязана попасть ВНУТРЬ блока; экранирование `|` внутри ячейки.

<!-- mb-stage:6 -->
### Stage 6: F + G + H + I — харнес перестаёт врать о собственном окружении

**Role:** qa

**What to do:**
- **F** `tests/pytest/test_cli.py::_run_install_sh` (и парный `_run_uninstall_sh`, если он делает то же): перестать прибивать `PATH` литералом — наследовать реальный `PATH` процесса. Изоляция, ради которой писался хелпер, — это подменённый `HOME`, а не урезанный `PATH`; урезанный `PATH` на Apple Silicon подсовывает системный python 3.9 и ломает тест на честном отказе install.sh.
- **G** `pyproject.toml`: добавить `networkx>=3.0` в extra `dev`. CI уже ставит `.[codegraph,yaml]` и потому зелёный; dev-окружение — нет. Объявление зависимости, а не `skipif`: прецедент в `.github/workflows/test.yml` (комментарий про shellcheck) — ставить инструмент, а не гасить проверку.
- **H** `tests/bats/test_test_runner_python.bats::teardown`: сделать teardown skip-безопасным — его последняя команда не должна возвращать ненулевой код, когда `TMPROOT` не выставлен (setup вышел по `skip`).
- **I** `tests/bats/test_mb_glossary.bats::_concurrent_upserts`: сабшелл обязан записать rc ВСЕГДА. Неуспешный вызов не должен обрывать сабшелл под errexit — снять errexit в сабшелле либо взять rc формой, которая errexit не триггерит.

**Testing (TDD — красный прогон обязателен):**
- F: 4 существующих красных теста `test_cli.py` становятся зелёными; красный прогон — текущий baseline.
- G: 7 существующих красных `test_wiki_staleness.py` зеленеют после `pip install -e ".[dev]"` в чистом venv; проверить, что `networkx` реально подтягивается из `dev`, а не из ранее установленного пакета.
- H: новый негативный прогон — временно заставить setup уйти в `skip` и убедиться, что тест печатается как `ok … # skip`, а не `not ok`.
- I: новый тест `mb_glossary: a failing racer still records its rc` — гарантированно неуспешный upsert в сабшелле, файл rc существует и содержит ненулевое значение. Красный до правки (файла нет).

**DoD:**
- [x] `tests/pytest/test_cli.py` — 0 failed
- [x] `tests/pytest/test_wiki_staleness.py` — 0 failed в venv, собранном как `pip install -e ".[dev]"`
- [x] `bats tests/bats/test_test_runner_python.bats` — 4 результата, ни одного `not ok` (при отсутствующем `pytest` — 4 × `ok … # skip`)
- [x] `bats tests/bats/test_mb_glossary.bats` — 0 `not ok` в трёх последовательных прогонах (тест I был флаком)
- [x] `networkx` появился ровно в одном месте `pyproject.toml` (extra `dev`), extra `codegraph` не тронут

**Edge cases:** `PATH` отсутствует в окружении pytest; venv без `pytest` на PATH; гонка из 12 писателей на медленной машине.

<!-- mb-stage:7 -->
### Stage 7: J + K + L — три теста, проверяющие не то, что есть

**Role:** qa

**What to do:**
- **J** `tests/bats/test_session_prune_reindex.bats`: тест `--apply still exits 0 and skips the trigger when no python is runnable` описывает поведение, удалённое в I-132 (спавн python заменён на пометку `.index/.dirty`). Переписать на действующий контракт fail-open: когда пометку поставить НЕЛЬЗЯ (каталог индекса недоступен на запись), вывод несёт `reindex=0`, а код возврата остаётся 0. Комментарий теста привести в соответствие — он сейчас объясняет несуществующий guard.
- **K** `tests/bats/test_mb_interview_artifact_write.bats::a signal before the claim does not delete another run's candidate`: парковка завязана на 2-й вызов `basename`; до него управление не доходит. Определить фактическое окно «scrub armed ↔ claim» в `scripts/mb-interview-artifact-write.sh` и перепарковать тест на признак, который этому окну принадлежит, а не на порядковый номер вызова утилиты. Если окно исчезло как таковое — зафиксировать это явно (тест переписывается под действующий инвариант, а не удаляется молча).
- **L** `tests/bats/test_agent_graph_routing.bats`: два теста ищут литералы `mb-graph-query.py impact` / `mb-graph-query.py status`, а `agents/plan-verifier.md` после 59ffc7c пишет путь переменной — `"$SKILL_DIR/scripts/mb-graph-query.py" impact`. Ослабить паттерн ровно настолько, чтобы он допускал закрывающую кавычку и не требовал одного стиля записи пути; сама проверка (роль ссылается на команду) обязана остаться. `agents/plan-verifier.md` НЕ править: `$SKILL_DIR`/`$BANK` там сознательно лучше захардкоженного `~/.claude/...`.

**Testing (TDD — красный прогон обязателен):**
- J: переписанный тест красный против кода, который игнорирует недоступный каталог индекса, зелёный против текущего; плюс сохранившиеся `reindex=1` / dry-run тесты остаются зелёными.
- K: после перепарковки тест обязан быть виден красным против кода без обработчика сигнала (мутация: снять trap) — иначе он ничего не доказывает.
- L: ослабленный паттерн обязан оставаться красным на файле роли, где ссылки на команду НЕТ (мутация: временно убрать строку из `agents/mb-qa.md`).

**DoD:**
- [x] `bats tests/bats/test_session_prune_reindex.bats` — 3/3 зелёных
- [x] `bats tests/bats/test_agent_graph_routing.bats` — 0 `not ok`; мутация (удаление строки в `agents/mb-qa.md`) делает тест красным
- [x] `bats tests/bats/test_mb_interview_artifact_write.bats` — 0 `not ok`; для теста K зафиксирован красный прогон против мутации
- [x] `agents/plan-verifier.md` байт-идентичен baseline

**Edge cases:** каталог индекса существует, но принадлежит другому пользователю; роль-файл со ссылкой в комментарии, а не в инструкции.

<!-- mb-stage:8 -->
### Stage 8: закрытие — батарея зелёная целиком, реестры обновлены

**Role:** qa

**What to do:**
- Полный прогон `pytest tests/pytest` и `bats tests/bats/` на итоговом дереве. `mb-test-run.sh` НЕ запускать (I-192 — вне объёма).
- Сверить число исполненных bats-тестов с `bats --count tests/bats/` — расхождение равно нулю.
- `backlog.md`: `I-208` → `DONE` со ссылкой на коммит и строкой доказательства (числа прогонов до/после).
- `CHANGELOG.md`: сверить, что записи стадий 2–4 на месте и не дублируются.
- `progress.md`: запись о закрытии через `mb-work-progress-append.sh`.

**Testing:**
- Итоговый прогон — сам по себе доказательство; его вывод (счётчики) попадает в отчёт дословно.

**DoD:**
- [x] `pytest tests/pytest -q` → `0 failed`
- [x] `bats tests/bats/` → 0 `not ok`, без `bats warning`
- [x] Исполнено ровно `bats --count tests/bats/` тестов
- [x] `I-208` в `backlog.md` помечен DONE с run-id и числами
- [x] `scripts/mb-drift.sh .` не даёт НОВЫХ находок относительно baseline

**Edge cases:** новые падения, вскрытые стадией 1 (десять тестов начали исполняться) — пробный прогон показал 51/51 зелёных, но проверить заново на итоговом дереве.

---

## Risks

| Риск | Вероятность | Митигация |
|---|---|---|
| Правка `valid_topic` отвергает валидный topic, ломая соседние тесты | средняя | DoD стадии 3 требует явной проверки набора валидных слагов; полный прогон файла артефакт-райтера |
| Stage 2 откатывает I-196 | низкая | три bats-теста I-196 включены в DoD как обязательные зелёные |
| Наследование `PATH` в `_run_install_sh` делает тест зависимым от машины | средняя | это ровно то, что тест и должен проверять — установку в реальном окружении; `HOME` остаётся изолированным |
| Тест K окажется непочиняемым без правки продукта | средняя | DoD допускает переписывание под действующий инвариант с явной фиксацией; молчаливое удаление запрещено |
| Флак I воспроизводится только под нагрузкой | высокая | DoD требует трёх последовательных зелёных прогонов файла |

## Gate

- Все восемь стадий закрыты, каждая — с зафиксированным красным прогоном нового/существующего теста до правки (AGR-027).
- `tests/pytest` и `tests/bats` зелёные целиком; число исполненных bats-тестов равно `bats --count`.
- Правки продукта (стадии 2–4) сопровождены строкой в `CHANGELOG.md`.
- `agents/plan-verifier.md`, тела тестов стадии 1 и extra `codegraph` — байт-идентичны baseline.

<!-- mb-stage:9 -->
### Stage 9: M — `mb-test-run.sh` перестаёт терять python-тесты (исполняется ДО Stage 8)

**Role:** devops

**What to do:**
- Найдено при исполнении Stage 6 и подтверждено оркестратором: `scripts/mb-test-run.sh::run_python` (строки 103-152) ловит итоговую строку pytest регэкспом, заякоренным на `^` с цифрой. При `FORCE_COLOR` в окружении pytest красит вывод даже при записи в файл, строка начинается с escape-последовательности, совпадения нет → `summary` пуст → `TESTS_TOTAL=0`, `TESTS_PASS=null`. Воспроизведение: фикстура из двух проходящих тестов даёт `{"stack":"python","tests_pass":null,"tests_total":0,…}` вместо `tests_total=2, tests_pass=true`.
- Это тот же класс, что чинит Stage 4 в `mb-lint-run.sh`, но цена выше: `tests_pass` — ровно то поле, которым Gate Sprint 1 меряет «батарея зелёная». Инструмент, которым проверяют гейт, сам сообщает «тестов нет» о зелёном наборе.
- Применить то же двухслойное лечение: гасить раскраску у дочернего процесса (`NO_COLOR=1`, снять `FORCE_COLOR`/`CLICOLOR_FORCE`) И снимать ANSI с прочитанных строк перед матчингом.
- Проверить остальные парсеры вывода в том же файле (bats, go) — если они якорятся так же, ловушка одна и её надо закрыть целиком. Go-путь НЕ запускать и его таймаут НЕ трогать: это I-192, вне объёма.
- `CHANGELOG.md` § Unreleased → Fixed: одна строка.

**Testing (TDD — красный прогон обязателен):**
- Новый тест в `tests/bats/test_test_runner_python.bats`: фикстура из двух проходящих тестов, прогон `mb-test-run.sh --out json` под `FORCE_COLOR=3` даёт `tests_total=2`, `tests_pass=true`. Красный до правки (`tests_total=0`, `tests_pass=null`) — зафиксировать дословно.
- Второй тест: один проходящий + один падающий под `FORCE_COLOR=3` даёт `tests_pass=false`, `tests_failed=1` и непустой `failures[0].name` без ANSI-байтов.
- Оба прогона повторить без `FORCE_COLOR` — обязаны быть зелёными.
- Два существующих теста файла, которые сейчас зелёные ТОЛЬКО потому, что скипаются (pytest не в PATH), обязаны стать зелёными по существу, когда pytest в PATH есть.

**DoD:**
- [x] `PATH=<repo>/.venv/bin:$PATH bats tests/bats/test_test_runner_python.bats` — 0 `not ok`, тесты исполняются, а не скипаются
- [x] `bats tests/bats/test_test_runner_python.bats` без pytest в PATH — 0 `not ok` (законные скипы)
- [x] Ручное воспроизведение даёт `tests_total=2, tests_pass=true` и под `FORCE_COLOR=3`, и без
- [x] В `failures[].name`/`error_head` нет ANSI-байтов
- [x] `shellcheck -S error scripts/mb-test-run.sh` чист
- [x] Go-путь и его таймаут не изменены (диф их не касается)

**Edge cases:** пустой каталог тестов (`tests_total=0`, `tests_pass=null` — законно); pytest, возвращающий код 5 «no tests collected»; итоговая строка с `warnings`/`skipped` в середине.
