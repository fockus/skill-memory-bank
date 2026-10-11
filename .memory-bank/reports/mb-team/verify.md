STATUS: FAIL

# Проверка плана `/mb team`, этапы 1–11

- **План:** `.memory-bank/plans/2026-10-10_feature_mb-team.md`. Этап 12 не проверялся: его отложил Антон, AGR-155 в Harness.
- **Baseline commit:** f050443e9d7c70eadf78cc8f1f5b72e6b01888f8. Fallback не понадобился.
- **Где проверял:** физический путь `/Users/anton-one/Apps/skill-memory-bank`, bash 3.2.57, bats 1.13.0.
- **Тесты:** целевые тесты плана зелёные. В полном наборе 188 падений из 8608. 187 из них классифицированы, одно — непостоянный сбой нашего e2e: в 10 повторных запусках он не воспроизвёлся.
- **Нарушения RULES:** 0 настоящих. Детерминированная проверка выдала 7 CRITICAL `tdd/delta` и 8 WARNING SRP. Все 7 CRITICAL оказались ложными срабатываниями эвристики по имени файла: покрывающие тесты перечислены в разделе RULES. Все 8 WARNING относятся к файлам, которые были длиннее 300 строк уже на baseline.
- **Соблюдение соглашений:** 97 действующих соглашений, нарушено 0.
- **Подтверждено пунктов DoD:** 43 из 45. Они отмечены `- [x]` в плане.

## Вердикт по этапам

| Этап | Вердикт | DoD |
|---|---|---|
| 1 T-GUARD | PASS | 2/2 |
| 2 T-LOCK | PASS | 7/7 |
| 3 T-CFG | PASS | 6/6 |
| 4 T-COORD | PASS | 2/2 |
| 5 T-VCS | PASS | 4/4 |
| 6 T-ENGINE | PASS | 5/5 |
| 7 T-RENDER | PASS | 4/4 |
| 8 T-STATE | FAIL | 5/6: «The listed tests green» не подтверждён (дефект D1) |
| 9 T-REVIEW | PASS | 3/3 |
| 10 T-DOCS | PASS | 3/3; `drift_warnings=2`, это только исключённые `progress_chain` и `plan_vs_git` |
| 11 T-WIRE | PARTIAL | 2/3: полный набор не подтверждён (дефект D4) |

**Итог: FAIL**, но строго формальный. Код всех 11 этапов на месте и работает. Мешают два пункта DoD, и оба на уровне тестов:
- **Этап 8:** одна ложно зелёная проверка в bats. На bash ≥ 4.1 она красная, а значит, будет красной на ubuntu в CI.
- **Этап 11:** в полном прогоне один раз упал собственный e2e плана, и это падение не воспроизводится.

## Дефекты

**D1 — major.** Ложно зелёная проверка: `tests/bats/test_mb_team_cli.bats:61`, тест «team: collect appends one progress entry per newly returned track; a second run appends nothing».
- Проверка `[[ "$output" == *"mb-agree.sh question"*"ask about A"* ]]` стоит не на последней строке. Под bash 3.2 такая проверка не валит тест.
- Сама проверка неверна. `collect` печатает `question: bash ".../scripts/mb-agree.sh" question "ask about A"`: между `mb-agree.sh` и `question` стоит кавычка. Это видно на пробном запуске фикстуры.
- Доказательство: копию тестов прогнал с `[[ … ]] || false`, и получил `not ok 5 … [[ "$output" == *"mb-agree.sh question"*"ask about A"* ]] || false' failed`.
- CI `.github/workflows/test.yml` гоняет `bats tests/bats/` на `ubuntu-latest`, там bash 5. Там этот тест будет красным.
- Поведение `collect` правильное, сломан только шаблон в тесте. Подойдёт, например, `*'mb-agree.sh" question "ask about A"'*` или `*mb-agree.sh*question*"ask about A"*`.

**D2 — medium.** Ещё 21 проверка `[[ … ]]` стоит не на последней строке в тестах плана. Сейчас все они истинны: прогон с `|| false` зелёный. Но на macOS под bash 3.2 они ничего не проверяют. Список ниже, в разделе «Условия `[[ … ]]` не на последней строке».

**D3 — medium, вне плана, было до него.** Падения адаптеров codex, cursor, opencode и ещё двух файлов — не сбои под нагрузкой, как написано в W11.md, а детерминированная поломка окружения.
- Команда полного набора из DoD ставит `.venv/bin` первым в PATH. В venv `python3 -m site --user-base` печатает путь, но выходит с кодом 1: пользовательский site-packages отключён.
- `setup` пяти файлов вызывает `PYTHONUSERBASE="$(python3 -m site --user-base)"` под `set -e` и падает:
  - `tests/bats/test_codex_adapter.bats:24`;
  - `test_cursor_adapter.bats:11`;
  - `test_opencode_adapter.bats:32`;
  - `test_mb_config_hosts.bats:22`;
  - `test_proportional_full_suite_once.bats:25`.
- Всего 167 тестов: 50 + 28 + 51 + 30 + 8.
- Доказательства:
  - на baseline-копии с venv в PATH `test_mb_config_hosts` красный 30 из 30, `test_codex_adapter` — 50 из 50;
  - на текущем дереве без venv в PATH из физического пути зелёные codex 50/50, cursor 28/28, opencode 51/51, config_hosts 30/30, full_suite_once 8/8;
  - пять файлов не менялись с f050443.
- **Итого:** из физического пути адаптеры codex, cursor и opencode красные только с venv в PATH.

**D4 — low; из-за него не подтверждён DoD 11.3.** В полном прогоне упал один тест `team e2e: …` из `tests/e2e/test_mb_team_e2e.bats`. Раннер удаляет журнал bats, поэтому какой именно из двух, неизвестно.
- Повторно он не падал ни разу:
  - 6 запусков подряд, из них 3 одновременно;
  - 1 запуск через `mb-test-run.sh --files`;
  - 1 отдельный запуск;
  - 1 групповой запуск `bats <tests/bats файл> tests/e2e/*.bats`, как в полном наборе с `setup_suite`: 130/130 ok.
- Причина не установлена. Падение относится к нашему тесту, так что «было до плана» его не объясняет.

**D5 — low.** Устарел комментарий о порядке разрешения в `scripts/_lib.sh:292-298`. В нём нет нового шага «cwd внутри банка».

**D6 — info.** Защита этапа 1 срабатывает, только если каталог называется `.memory-bank`. Это по плану. Каталог глобального банка (`--storage=global`) называется иначе, и запуск изнутри него по-прежнему откатывается к относительному `.memory-bank`. Мимо этого проходит только `mb-team.sh`, и только при явном `--mb`.

## Условия `[[ … ]]` не на последней строке (тесты плана)

Проверка: каждую такую строку заменил на `[[ … ]] || false` в копии дерева `/tmp/mbv-mut` и прогнал файлы заново.

| Место | Проверка | С `\|\| false` |
|---|---|---|
| `tests/bats/test_mb_lock_resource.bats:112` | `*ran*` | истинна |
| `test_mb_lock_resource.bats:128` | `!= *never*` | истинна |
| `test_mb_lock_resource.bats:146` | `*late*` | истинна |
| `test_mb_lock_resource.bats:160` | `*ran*` | истинна |
| `test_mb_lock_resource.bats:196` | `*"GiB"*` | истинна |
| `tests/bats/test_mb_coord.bats:294` | `*"BLOCKED (no ACK): 1"*` (половина DoD 4.1 «BLOCKED shown») | истинна |
| `test_mb_coord.bats:295` | `*"D3: disk short"*` | истинна |
| `tests/bats/test_mb_team_cli.bats:18` | `*"inside a Memory Bank"*` | истинна |
| `test_mb_team_cli.bats:38` | `*"brief was edited"*` | истинна |
| `test_mb_team_cli.bats:51` | `*'"actions": ["dispatch A", "dispatch B"]'*` | истинна |
| **`test_mb_team_cli.bats:61`** | `*"mb-agree.sh question"*"ask about A"*` | **ложна — дефект D1** |
| `test_mb_team_cli.bats:62` | `*"mb-idea.sh"*"idea from A"*` | истинна |
| `test_mb_team_cli.bats:80` | `*'"criterion": "login works", "checked": false'*` | истинна |
| `tests/bats/test_mb_team_commit.bats:27` | `*"foreign"*"b/y.txt"*` | истинна |
| `test_mb_team_commit.bats:28` | `*"stray.txt"*` | истинна |
| `test_mb_team_commit.bats:46` | `*"shared/z.txt"*"B"*` | истинна |
| `test_mb_team_commit.bats:56` | `*"A"*"dispatched"*` | истинна |
| `test_mb_team_commit.bats:62` | `*"BLOCKED"*` | истинна |
| `test_mb_team_commit.bats:72` | `*"--yes"*` | истинна |
| `tests/bats/test_mb_team_review.bats:44` | `*"team.review.enabled"*` | истинна |
| `test_mb_team_review.bats:149` | `*'"B": ["M-9"]'*` | истинна |
| `test_mb_team_review.bats:257` | `*"M-2"*` | истинна |

Таких условий нет в остальных файлах плана: `test_mb_resolve_nested_bank`, `test_mb_vcs`, `test_mb_team_checkpoint`, `test_mb_workflow_lenses`, `test_mb_work_severity_medium`, `tests/e2e/test_mb_team_e2e.bats`, `tests/bats/lib/team_fixture.bash`, а также в новом блоке `test_install_uninstall.bats`. В старых тестах того же файла (строки 687, 706, 809, 810) они есть, но это вне плана.

## Чем подтверждены пункты DoD

**Этап 1:**
- `bats test_mb_resolve_nested_bank test_lib test_mb_storage_resolver` — 110/110.
- На baseline-копии новый файл красный: 3 из 4 (`not ok 1-3`), а `ok 4` — защита от регрессии.
- `shellcheck -x scripts/_lib.sh` чистый.

**Этап 2:**
- bats 14/14: весь файл 55,7 с под нагрузкой полного набора, FIFO-тест (10 прогонов) отдельно 28,7 с. Пункты DoD по тестам:
  - тест 2 — TERM/KILL ожидающего;
  - тест 3 — мёртвый тикет;
  - тест 5 — SIGKILL обёртки;
  - тест 4 — живой держатель, run/acquire/break, плюс 75;
  - тест 7 — break и запись на доске;
  - тест 8 — 77;
  - тест 11 — 76 и убитый дочерний процесс;
  - тест 12 — maint с чужим токеном.
- pytest 12 passed: схема C4 и разбор `df -Pk` для macOS, Linux и пути с пробелами.
- shellcheck и ruff чистые. Строк: 224, 297 и 133 в `mb_lock_resource.py`.
- Прочие `test_mb_lock*` (corruption, helper, r4_safety, ttl_reclaim) — 42/42.

**Этап 3:**
- pytest — 205 passed. Покрытие пунктов:
  - матрица 13 ключей × 5 слоёв с provenance;
  - 14 ошибочных `team:` с exit 2 и именем поля, совпадают с PyYAML и без него;
  - вложенная inline-карта.
- `resource build` даёт ровно C3 из examples §2. Фикстура совпадает с examples §1 байт в байт по содержанию.
- Валидатор без `team:` сверен вручную: baseline и текущий дают одинаковый вывод и код на трёх конфигах (ok, bad version, unknown key) с двумя интерпретаторами.
- Существующие тесты валидатора только дополнены, ни одна строка не удалена.
- ruff чистый. Новые файлы по 239, 164, 214 и 115 строк.

**Этап 4:**
- bats 18/18; старые случаи не менялись — в диффе нет удалённых строк.
- pytest docs — 3 passed; shellcheck чистый.
- В таблице `references/coordination.md:73-74` есть BLOCKED и COMMIT.

**Этап 5:**
- bats 19/19. Тест реального `arc` выполнился, а не пропущен.
- Хеши через `hashlib`, `scripts/mb-team-checkpoint.sh:32,60,82`.
- shellcheck чистый. Пробы arc приложены в D.md.

**Этап 6:**
- bats 68/68: lenses 8, severity_medium 12, `test_mb_work_command_doc` 48. Golden-сравнение с f050443 в тестах 7–8 и 12/18.
- pytest step_models и light — 18 passed. shellcheck и ruff чистые.

**Этап 7:**
- pytest 12 passed:
  - golden для brief, A (large, direct, с ревью) и C (small, direct);
  - абсолютные пути и `--mb`;
  - `unfilled` — 6 подсказок в brief, 0 в промптах;
  - `mb-work-plan.sh --dry-run` даёт 1 этап.
- ruff чистый; 244 строки.

**Этап 8:**
- pytest 39 passed. В нём `next` по deps, glob, max_parallel, blocked, unfilled и четырём условиям `stop_success`, параметризованным поломкой каждого; гонка двух процессов `track set` — 8 раундов каждый, `fix_cycle` = 8.
- bats cli и commit — 14/14. Проверено:
  - collect идемпотентен — проверки `grep -c` стоят до последней строки, но это `[`, а не `[[`;
  - commit: shim git без push, `stray.txt` остаётся в индексе, запись COMMIT;
  - status показывает held, queued и BLOCKED.
- shellcheck и ruff чистые; самый длинный файл — 292 строки.
- Пункт 6 не отмечен из-за D1.

**Этап 9:**
- bats 16/16 — gate 0/1/2, owner, unowned, external, ingest.
- `stop_human review-cycles` в `next` — `tests/pytest/test_mb_team_state.py:107-115`.
- shellcheck и ruff чистые.

**Этап 10:**
- `commands/team.md` — 266 строк. Блоки bash запускаются из `project with spaces` (`test_mb_team_command.py:102`).
- pytest doc_counts, command_descriptions, team_command, skill_guide — 162 passed.
- `mb-drift.sh .` → `drift_warnings=2`: это `plan_vs_git=warn` и `progress_chain=critical`, оба исключены по заданию. Остальные проверки ok, `plan_status` и `index_sync` тоже.

**Этап 11:**
- e2e 2/2 в пути с пробелами (`team_fixture.bash`: `proj with space`).
- `tests/e2e/test_install_uninstall.bats` — 57/57 за 32 мин 22 с. В нём:
  - `ok 15 install: ships the /mb team bundle; uninstall removes it`, во временном HOME;
  - aliases test тоже ok из физического пути.

## Вывод тестов

```
bats test_mb_resolve_nested_bank test_lib test_mb_storage_resolver      1..110, 0 not ok
baseline copy: bats test_mb_resolve_nested_bank                         not ok 1,2,3; ok 4
bats test_mb_lock_resource                                              1..14, 0 not ok (55.7 s)
bats -f 'ticket order' test_mb_lock_resource                            ok (28.7 s)
bats test_mb_lock_{corruption,helper,r4_safety,ttl_reclaim}             1..42, 0 not ok
pytest test_mb_lock_queue                                               12 passed
pytest test_mb_team_pipeline test_mb_team_config test_pipeline_default_yaml test_mb_pipeline_validate   205 passed
bats test_mb_coord                                                      1..18, 0 not ok
pytest test_mb_coord_docs                                               3 passed
bats test_mb_vcs test_mb_team_checkpoint                                1..19, 0 not ok
bats test_mb_workflow_lenses test_mb_work_severity_medium test_mb_work_command_doc   1..68, 0 not ok
pytest test_mb_work_step_models test_mb_work_light                      18 passed
pytest test_mb_team_render                                              12 passed
pytest test_mb_team_state                                               39 passed
bats test_mb_team_cli test_mb_team_commit                               1..14, 0 not ok
bats test_mb_team_review                                                1..16, 0 not ok
pytest test_doc_counts test_command_descriptions test_mb_team_command test_skill_guide_compliance   162 passed
bats tests/e2e/test_mb_team_e2e.bats                                    1..2, 0 not ok (+6 repeats, runner, group run 130/130)
bats tests/e2e/test_install_uninstall.bats                              1..57, 0 not ok (32m22s)
shellcheck -x (_lib.sh mb-lock.sh mb-coord.sh mb_vcs.sh mb-team-checkpoint.sh arc-shim mb-workflow.sh
  mb-work-plan.sh mb-work-review-parse.sh mb-work-severity-gate.sh mb-team.sh mb-team-review.sh + new bats)   clean
ruff check (all new/changed .py of the plan)                            No issues found
[[ ]] mutation run (|| false) on 5 files                                only test_mb_team_cli.bats #5 turns red
```

Полный набор: `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json`, из физического пути, с 20:03 до 22:21, 8309 с.
Результат: `stack=bats+python, tests_total=8608, tests_failed=188, tests_pass=false`.

| Падения | Сколько | Класс | Доказательство |
|---|---|---|---|
| test_codex_adapter, test_cursor_adapter, test_opencode_adapter, test_mb_config_hosts, test_proportional_full_suite_once | 167 | окружение: venv в PATH, было до плана (D3) | baseline с venv: 30/30 и 50/50 not ok; текущее дерево без venv: 0 not ok |
| test_mb_flow_closure_guard_budget (6), _cache (4) | 10 | правки сессии done-gates (`hooks/mb-flow-closure-guard.sh` требует `mb-goal-state.sh`) | baseline 0 not ok; текущее дерево красное и отдельно |
| hooks/tests/recall-disclosure: per-chunk, id ×2, id-collision | 4 | было до плана | на baseline те же 4 not ok |
| hooks/tests/spawn-discipline «pi adapter marks the index dirty» | 1 | было до плана | на baseline тот же not ok 5 |
| test_audit_command_contracts::test_done_global_bank_supplies_gate_configuration | 1 | done-gates (`commands/done.md`) | `IndexError`: раздела `## 0. Mandatory done-gates` нет |
| test_skill_naming_v2::test_no_v1_plan_md[*.py] | 1 | done-gates | единственный нарушитель — `tests/pytest/test_mb_done_scope.py` |
| recall-disclosure «fusion:» | 1 | непостоянный сбой, не связан с планом | отдельно 18 тестов, 4 известных not ok, fusion — ok |
| test_audit_install_roundtrip (pi settings, identical reinstall) | 2 | непостоянный сбой, не связан с планом | отдельно passed |
| test_mb_team_e2e «team e2e: …» | 1 | непостоянный сбой нашего теста (D4) | 10 повторов зелёные |

Зависания `test_bats_test_names.bats` из физического пути не было. `test_metrics.bats` и тест алиасов прошли.

## RULES

- **SRP, WARNING.** Восемь файлов длиннее 300 строк были такими уже на baseline:
  - `_lib.sh`;
  - `mb_pipeline_minimal_yaml.py`, 398 → 400;
  - `mb_pipeline_validate_core.py`, 353 → 358;
  - `mb-coord.sh`, 368 → 457;
  - `mb-workflow.sh`, 382 → 411;
  - `mb-work-plan.sh`, 382 → 395;
  - `mb-work-review-parse.sh`;
  - `mb-work-severity-gate.sh`.

  Зонный контракт 400 строк (`test_s2_file_size_contract`) в полном наборе зелёный. Все новые файлы короче 300 строк.
- **`tdd/delta`: 7 CRITICAL, все ложные.** Эвристика сопоставляет тест с файлом по основе имени, а покрытие у этих модулей есть:
  - `mb_team_status.py` — `test_mb_team_state.py` (`decide`) и `test_mb_team_cli.bats`;
  - `mb_team_ops.py` — `test_mb_team_commit.bats` и `test_mb_team_cli.bats`;
  - `mb_team_review_core.py` и `mb_team_review_external.py` — `test_mb_team_review.bats`;
  - `mb_team_vocab.py` — `test_mb_team_pipeline.py::test_prompt_phrases` и `test_ambiguous_prompt_*`;
  - `mb_pipeline_validate_team.py` и `mb_pipeline_minimal_yaml.py` — `test_mb_team_config.py`, включая проверки без PyYAML.
- **Направление слоёв (DIP):** нарушений нет.
- **`stack.python.type-hints`:** 33 WARNING в новых модулях, только в параметрах функций. Ruff-профиль проекта этого не требует.

## Соблюдение соглашений

- **AGR-097** — соблюдено:
  - пресет standard: direct + TDD + plan-verifier без ревью трека (`test_bundled_presets_follow_agr_097`);
  - снятие мёртвого замка головой очереди с записью STATUS (`test_mb_lock_resource.bats`, тест 5);
  - необязательный `medium` с лимитом 0 в team `clean_when`, старые гейты без изменений (`test_mb_work_severity_medium.bats`, тесты 14 и 18);
  - `work: orchestrated|light` (`test_mode_work_variant_default_and_light_shorthand`, `mb_work_light.py`).
- **AGR-085** — соблюдено. Тексты в репозитории на английском. Кириллица есть только в данных словаря фраз (`scripts/mb_team_vocab.py`, его тест, таблица в `commands/team.md`) и в фразах-триггерах description. Так задумано в design §4.
- **AGR-030 и AGR-035** — соблюдено: `test_s2_file_size_contract` в полном наборе зелёный.
- **AGR-061** — соблюдено: во frontmatter `commands/team.md` нет `disable-model-invocation`.
- **AGR-070** — соблюдено. Тесты поведенческие, через настоящие CLI. Моки только на внешних границах: PATH-shim git и arc.
- **AGR-071** — соблюдено. CHANGELOG получил две строки, README — счётчик и строку. `commands/team.md` требует сам план.
- **AGR-094** — соблюдено. В `commands/work.md` одно предложение, движок общий.
- **AGR-032, AGR-033, AGR-073** — неприменимо к коду: это правила процесса и коммита. Коммитов не было.
- **Остальные** (AGR-001…AGR-096, кроме перечисленных выше) — неприменимо: дифф плана их не затрагивает.

## Отступления (info)

- **Файлы вне строк Files.** Вне перечня планы появились:
  - `mb_lock_resource.py`, `mb_team_vocab.py`, `mb_team_tracks.py`, `mb_team_review{,_core,_external}.py`, `mb_work_light.py`;
  - `tests/bats/lib/team_fixture.bash`;
  - правки пяти `agents/mb-reviewer-*.md`.

  Всё это поставляется: проверено в install-тесте.
- **Этап 2:**
  - записи на доску проверяются через настоящий `mb-coord.sh`, а не PATH-shim;
  - `mb_pid_alive` и `mb_lock_acquire` не переиспользованы, тикеты сделаны через `link(2)`.
- **Этап 6:** гейт без ключа `medium` засчитывает medium в minor. Это прочтение «старые конфиги не меняются» (E.md, п. 2).
- **Грамматика id трека:** в C1 `^[A-Za-z][A-Za-z0-9_-]{0,15}$`, в `mb-coord.sh` `[A-Za-z0-9][A-Za-z0-9_-]{0,31}`. Вторая шире, поэтому id команды всегда допустим для доски.
- **Id на доске не привязаны к команде.** Открытый BLOCKED `A:` старой команды останавливает трек `A` новой (F.md, п. 5).

## Gate

Не выполнен. Из 45 пунктов DoD этапов 1–11 подтверждены 43. Не подтверждены:
- 8.6 — дефект D1;
- 11.3 — дефект D4.

Этап 12 и `/mb verify` вне этой проверки.

## Рекомендации

1. Исправить шаблон в `tests/bats/test_mb_team_cli.bats:61` (D1). После этого отметить DoD 8.6.
2. Перенести 21 проверку `[[ … ]]` из списка выше на `[ … ]`, `grep -q` или `[[ … ]] || false`, чтобы на macOS они тоже что-то проверяли (D2).
3. Повторить полный набор, чтобы закрыть DoD 11.3. Если e2e снова зелёный, сбой можно записать в непостоянные. Для самой команды — отдельная задача вне плана: в пяти `setup` писать `python3 -m site --user-base || true`, либо запускать полный набор без venv в PATH (D3).
4. Обновить комментарий о порядке разрешения в `_lib.sh:292-298` (D5).
