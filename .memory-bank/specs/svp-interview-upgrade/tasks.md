# Tasks: svp-interview-upgrade

> Слайс S1 группы `sdd-vision-pipeline`. Каждая задача несёт **Eval:** — декларацию
> детерминированной bats-проверки (D-05): в work-фазе эвал материализуется ПЕРВЫМ (bats-файл
> пишется, красный прогон наблюдается), затем реализация до green.
> Red-условия описывают состояние ПОСЛЕ материализации теста (S2-C6: посторонний сбой, включая
> отсутствующий путь, red'ом не считается).
> Prompt-контракт проверяется ТОЛЬКО через `tests/bats/lib/discuss_contract.bash` (design.md C9):
> section-scoped clause-ERE + обязательная negation-мутация; голый grep/co-occurrence запрещён.
> Роли — bare (парсер сам добавляет префикс `mb-`: `scripts/mb_work_items.py:240`).
> Blocked-by-графом T2–T6 зависят только от T1 (общий seam-файл `commands/discuss.md` + харнесс C9,
> который создаёт T1; риск конфликта — см. design.md Risks); рекомендованный последовательный
> проход для одной сессии — 1 → 2 → 3 → 4 → 5 → 6, параллельность нескольких сабагентов — S3.
> Формат задач — v2 (Stage/Blocked-by/Scope/Budget, грамматика `specs/svp-sdd-core/design.md` C1),
> принят раньше S4-автоматики bootstrap-ом (см. `svp-contract-test-loop/tasks.md` для прецедента).
> Каждый `Eval:` несёт `output~:`-якорь настоящего провала (групповая норма X-05, S2-C1 + S2
> REQ-054/055): все шесть задач gated, якорь — положительный именованный префикс bats-теста,
> зафиксированный в Testing каждой задачи (`bats` на отсутствующем файле даёт exit 1 +
> `not ok 1 bats-gather-tests` — тот же код, что настоящий провал, поэтому exit-only якорь невалиден).
> Ревизия 4 (2026-07-18, круг 3): критический R3-001 — secret-scan `transcript` сканирует сырой
> текст включая `<private>` и блокирует секрет до git (T4); файловые эффекты вынесены в
> детерминированные writer-helper'ы `mb-interview-artifact-write.sh` (C11, install-plan в T1 +
> publish-transcript в T4) и `mb-glossary.sh` (C12, T5) — SVP-IU-002; строгая грамматика answer/
> rejected + `--legacy-live-fixture` (T4, SVP-IU-005); `--spec-budget` формула + error-контракты
> (T3, R3-002/003). Бюджеты: Stage 1 = 300k (T1 105→120, +writer), Stage 2 = 275k (T4=120, T5 60→90).

<!-- mb-task:1 -->
## Task 1: Interview-plan файл + возврат к белым пятнам + fast-to-code bypass + prompt-harness

**Stage:** 1
**Covers:** REQ-001, REQ-002, REQ-019, REQ-020
**Role:** developer
**Blocked-by:** none
**Scope:** commands/discuss.md, references/templates.md, scripts/mb-interview-artifact-check.sh, scripts/mb-interview-artifact-write.sh, tests/bats/lib/discuss_contract.bash, tests/bats/test_mb_interview_artifact_check.bats, tests/bats/test_mb_interview_artifact_write.bats, tests/bats/test_discuss_interview_plan.bats
**Budget:** 120000

**What to do:**
- Новый `tests/bats/lib/discuss_contract.bash` по контракту C9 design.md: `mb_section`, `mb_rule`, `assert_script_present`, `assert_clause`, `assert_clause_load_bearing`, массив `MB_DISCUSS_CLAUSES` (запись — 7 полей: `id|extractor|arg|clause-ERE|topic-anchor-ERE|negation-sed|REQ`). Это общий харнесс для T1–T6 — пишется здесь один раз. Прототип харнесса исполнен при ревизии 3 (C9 подтверждён исполнением: реальная клауза rule 6 → pass, голая клауза `question` → reject).
- В `commands/discuss.md` добавить секцию «Interview plan» (пишется до первого вопроса в `<bank>/tmp/interview-plan-<topic>.md`; структура — контракт C2 design.md: Inherited decisions / Topics ⬜ / Discovered mid-interview).
- Grilling rule 11: генерация запрещена при незакрытых темах — вернуться и дозадать (REQ-002); отмена → status: draft + план сохраняется (REQ-019).
- Grilling rule 14 (fast-to-code bypass, REQ-020): при явном выборе пользователя пропустить оставшиеся шаги интервью/декомпозиции, записав выбор и quality trade-off в context frontmatter; quality-режим остаётся дефолтом (D-11), выбор доступен в любой момент интервью.
- Шаблон interview-plan → `references/templates.md`.
- Новый `scripts/mb-interview-artifact-check.sh` по контракту C8 design.md, режим `plan` (режим `transcript` добавляет T4 в этот же файл): обязательные заголовки в порядке, только `- [ ]`/`- [x]` под Topics/Discovered, `--require-closed` считает открытые пункты, reason-коды `missing_section`/`section_out_of_order`/`bad_bullet`/`open_topics`; error-контракты (usage → stderr `error=usage`; нечитаемый → `<file>:0:unreadable`; сортировка `(line, reason-order)`, R3-003).
- Новый `scripts/mb-interview-artifact-write.sh` по контракту C11 (SVP-IU-002 — детерминированный writer файлового эффекта, не prompt): режим `install-plan` вызывает C8 `plan` и **атомарно** заменяет `<bank>/tmp/interview-plan-<topic>.md`; failed check оставляет target byte-identical; `artifact_write=installed kind=plan`, exit 0/1/2. Режим `publish-transcript` добавляет T4 в этот же файл.

**Eval:** `bats tests/bats/test_mb_interview_artifact_check.bats && bats tests/bats/test_mb_interview_artifact_write.bats && bats tests/bats/test_discuss_interview_plan.bats` — red: bats-файлы и харнесс C9 материализованы; падают `assert_script_present scripts/mb-interview-artifact-check.sh` и `.../mb-interview-artifact-write.sh` (скриптов нет; install-plan не производит запись), и `mb_section`/`mb_rule` возвращают `section_absent`/`rule_absent` для секции «Interview plan», rule 11, rule 14 и шаблона C2 в templates.md; exit: 1; output~: `not ok [0-9]+ (artifact_check|artifact_write|interview_plan): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста в `test_mb_interview_artifact_check.bats` начинается с `artifact_check: `, в `test_mb_interview_artifact_write.bats` — с `artifact_write: `, в `test_discuss_interview_plan.bats` — с `interview_plan: `. Причина: `bats` на отсутствующем файле даёт exit 1 + `not ok 1 bats-gather-tests` — тот же код, что и настоящий провал, поэтому exit-only якорь принял бы «файла нет» за red; ERE не поддерживает negative lookahead, и якорь опирается на положительный именованный префикс, которого у `bats-gather-tests` нет. Якорь покрывает первый (короткозамыкающий) конъюнкт `&&`-цепи и остаётся валидным для остальных.
- `tests/bats/test_mb_interview_artifact_check.bats` (`plan`-режим, ДО скрипта): valid plan → `artifact=ok open_topics=0`, exit 0; plan с открытыми пунктами + `--require-closed` → `artifact=invalid open_topics=<N>`, exit 1; отсутствует обязательная секция → exit 1, stderr `<file>:<line>:missing_section`; секции не в порядке → `section_out_of_order`; буллет не `- [ ]`/`- [x]` под Topics → `bad_bullet`; отсутствующий файл → exit 2; `--require-inherited` с режимом `plan` → usage error exit 2; **usage → stdout пуст + stderr `error=usage`; нечитаемый → `<file>:0:unreadable` (R3-003)**; shellcheck clean.
- `tests/bats/test_mb_interview_artifact_write.bats` (C11 `install-plan`, ДО скрипта, fixture-банк во `$BATS_TEST_TMPDIR`): валидный candidate → `artifact_write=installed kind=plan`, exit 0, **target-файл появился/заменён** (снимок до/после доказывает атомарную запись); candidate с открытыми пунктами/битой структурой → exit 1, stdout пуст, **target byte-identical** (не изменён); usage/I/O → exit 2; shellcheck clean.
- `tests/bats/test_discuss_interview_plan.bats` (ДО правок discuss.md, через харнесс C9 — `assert_clause` + `assert_clause_load_bearing` на каждую клаузу): `plan-file-path` (секция «Interview plan» предписывает запись в `tmp/interview-plan-<topic>.md` ДО первого вопроса; мутация: снять «до первого вопроса»); `rule11-block-generation` (rule 11 запрещает генерацию при незакрытых пунктах и требует вернуться и дозадать; мутация: «запрещено» → «не рекомендуется»); `rule11-cancel-draft` (отмена → `status: draft` + план сохранён; мутация: снять «сохраняется»); `rule14-record-tradeoff` (fast-to-code пишет выбор и quality trade-off во frontmatter; мутация: снять «trade-off»); `rule14-quality-default` (quality остаётся дефолтом; мутация: «дефолт» → «опция»); `template-c2-headings` (шаблон в `references/templates.md` содержит все три заголовка C2; мутация: удалить `## Discovered mid-interview`).
- Сценарий §1 (незакрытая тема блокирует генерацию) и §16 (fast-to-code bypass) — ручной приёмочный чек-лист поверх bats.

**DoD:**
- [x] Харнесс C9 (включая анти-vacuity гейт: negation-мутация ломает клаузу, `topic-anchor` выживает); секция, rule 11, rule 14 (fast-to-code) в discuss.md; шаблон в templates.md; `mb-interview-artifact-check.sh` (режим `plan`); `mb-interview-artifact-write.sh install-plan` (атомарная запись, byte-identity при отказе — доказано fixture-тестом)
- [x] Каждая клауза несёт и `assert_clause`, и `assert_clause_load_bearing` (ни одной co-occurrence-проверки)
- [x] Self-тест харнесса: голая клауза (`clause-ERE` = `topic-anchor-ERE`) отвергается — `reason=vacuous` либо `mutation_removed_topic`; поведенческая клауза проходит
- [x] Eval green (был red по заявленному условию)
- [x] Сценарии §1, §7, §15, §16 отрабатывают на тестовом топике
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Финальный гейт + batch-режим + fact-finding фронтира + partial-answer

**Stage:** 1
**Covers:** REQ-003, REQ-004, REQ-015, REQ-016, REQ-022, REQ-055, REQ-056
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/discuss.md, tests/bats/test_discuss_final_gate_batch.bats
**Budget:** 85000

**What to do:**
- Grilling rule 12: финальный гейт «есть ли что добавить?» после закрытия плана; непустой ответ → реоткрытие итерации + леджер (REQ-004); только явное «нет» → генерация. Правило отдельное от существующего rule 8 (Final confirmation gate — подтверждение сводки решений); rule 12 не заменяет и не переписывает rule 8.
- Секция «Batch mode» + флаг `--batch`: frontier-раунды (все разблокированные вопросы одним нумерованным раундом, рекомендация на каждый; AskUserQuestion до 4/вызов, несколько вызовов на раунд; деградация в нумерованный текст без интерактивного тула — REQ-016). Явно указать, что `--batch` переопределяет rule 6 («One question per turn») и только его.
- **Fact-finding фронтира** (REQ-055/056, D-18, контракт C6 design.md): перед раундом каждый разблокированный вопрос фронтира расследуется — источники те же, что Phase 0 (код-граф / semantic-search / grep; `mb-researcher` только для внешних тем); рекомендация REQ-015 обязана цитировать найденный факт (`file:line`/URL). Хост с диспатчем сабагентов → параллельные сабагенты, по одному на вопрос (REQ-055). Хост без него (`platform_limited` содержит `subagents`) → тот же fact-finding последовательно основным агентом + одна строка о деградации пользователю (REQ-056); тихий пропуск запрещён (AGR-013). Без `--batch` дефолт не меняется — по одному вопросу, без параллельного диспатча (D-18).
- Partial-answer (REQ-022): при частичном ответе на раунд неотвеченные вопросы остаются `- [x]` в interview-plan и формируют следующий фронтир; отвеченные закрываются `- [x]`.

**Eval:** `bats tests/bats/test_discuss_final_gate_batch.bats` — red: bats-файл материализован; падают clause-assertions rule 12 (final gate), `--batch`+деградация, partial-answer, fact-finding и honest degradation — все с `clause=<id> reason=absent` (секции «Batch mode»/rule 12 в `commands/discuss.md` нет); exit: 1; output~: `not ok [0-9]+ final_gate_batch: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `final_gate_batch: ` (обоснование — то же, что в T1: `bats` на отсутствующем файле даёт `not ok 1 bats-gather-tests` с тем же exit 1, поэтому якорь обязан быть положительным и именованным).
- `tests/bats/test_discuss_final_gate_batch.bats` (ДО правок, через харнесс C9 — `assert_clause` + `assert_clause_load_bearing` на каждую клаузу): `rule12-gate-after-close` (гейт задаётся после закрытия плана и ДО генерации; мутация: «до генерации» → «после генерации»); `rule12-reopen-on-addition` (непустой ответ → новая итерация + запись в леджер; мутация: снять «леджер»); `rule12-explicit-no` (только явное «нет» разрешает генерацию; мутация: «только явное нет» → «отсутствие ответа»); `batch-frontier-round` (`--batch` задаёт весь фронтир одним нумерованным раундом с рекомендацией на каждый вопрос; мутация: снять «рекомендация на каждый»); `batch-tool-limit` (лимит 4 вопроса на вызов AskUserQuestion, несколько вызовов на раунд; мутация: снять «несколько вызовов»); `batch-degradation` (хост без интерактивного тула → нумерованный plain-text; мутация: «деградирует» → «раунд пропускается»); `batch-overrides-rule6` (`--batch` переопределяет rule 6 и только его; мутация: снять ссылку на rule 6); `partial-answer-keeps-open` (неотвеченные остаются `- [x]` в плане и входят в следующий фронтир; мутация: снять «следующий фронтир»); `factfind-parallel` (хост с диспатчем → параллельные fact-finding сабагенты, по одному на вопрос фронтира; мутация: «параллельные сабагенты» → «основной агент»); `factfind-cites` (рекомендация цитирует найденный факт `file:line`/URL; мутация: снять требование цитаты); `factfind-degrade-sequential` (`platform_limited: subagents` → тот же fact-finding последовательно, не пропуск; мутация: «последовательно» → «пропускается»); `factfind-degrade-announced` (деградация сообщается пользователю; мутация: снять «сообщает»); `factfind-default-off` (без `--batch` — по одному вопросу, без параллельного диспатча; мутация: снять «без `--batch`»).
- Сценарии §2, §12, §13, §18, §19, §20 — ручной приёмочный чек-лист поверх bats (реальный параллельный диспатч и деградация на чужом хосте в bats не воспроизводятся — честная граница, design.md Risks).

**DoD:**
- [x] Правило 12 + секция Batch mode (с деградацией) + fact-finding (параллельный + честная последовательная деградация) + partial-answer правило в discuss.md
- [x] Каждая клауза несёт и `assert_clause`, и `assert_clause_load_bearing`
- [x] Eval green (был red по заявленному условию)
- [x] Сценарии §2, §12, §13, §18, §19, §20 отрабатывают
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Размерный триаж — рубрика + mb-estimate-check.sh + декомпозиция + реестр

**Stage:** 1
**Covers:** REQ-008, REQ-009, REQ-010, REQ-011, REQ-021
**Role:** backend
**Blocked-by:** 1
**Scope:** commands/discuss.md, scripts/mb-estimate-check.sh, tests/bats/test_mb_estimate_check.bats
**Budget:** 95000

**What to do:**
- Секция «Size triage» в discuss.md: после Phase 1 — оценка по рубрике C3 (таблица шести коэффициентов в тексте команды, ключи 1:1 с breakdown-схемой C1), запись `estimated_tokens` c breakdown во frontmatter; >~1M → рекомендация разбиения на **именованные** grouped specs с явным упоминанием, что каждая принятая ветка получит своё интервью (REQ-009), право отказа; согласие → отложенные спеки в реестр через `mb-idea.sh` с префиксом `[SPEC:<group>]` (контракт C7), интервью продолжается по выбранной.
- Ветка интервью, разросшаяся до размера отдельной спеки (REQ-021): предложить выбор — отложить как child-спеку либо упростить до MVP в текущей теме — до продолжения этой секции.
- Новый `scripts/mb-estimate-check.sh` по контракту C1 (шесть категорий breakdown, пороги ok/near/over из D-13, key=value вывод, exit 0/1/2, `--spec-budget`).

**Eval:** `bats tests/bats/test_mb_estimate_check.bats` — red: bats-файл материализован; падает `assert_script_present scripts/mb-estimate-check.sh` (скрипта нет), все key=value/exit-кейсы C1 и clause-assertions секции «Size triage» — с `reason=absent`; exit: 1; output~: `not ok [0-9]+ estimate_check: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `estimate_check: ` (обоснование — то же, что в T1).
- `tests/bats/test_mb_estimate_check.bats` (ДО скрипта): `estimate=ok` под 900k (exit 0); `estimate=near` в 900k–1M (exit 0, advisory); `estimate=over` над 1M (exit 1); stdout — ровно одна key=value строка формата C1; shellcheck clean.
- **`--spec-budget` boundary-матрица (R3-002, `near_lower = floor(spec_budget*9/10)`)**: `--spec-budget 500000` → 449999→ok, 450000→near, 500000→near, 500001→over; `--spec-budget 0`/отрицательное/нецелое → usage error exit 2.
- **Error-контракты (R3-003)**: usage (неизвестный флаг/невалидный budget) → stdout пуст + stderr `error=usage`, exit 2; нечитаемый вход → stdout пуст + stderr `<file>:0:unreadable`, exit 2; `estimate=missing` без frontmatter → stdout `estimate=missing spec.total=0 spec_budget=<N>` + stderr `<file>:0:estimated_tokens:missing`, exit 2; `estimate=malformed` (рассинхрон `subtotal`/`total`, отсутствующий ключ категории) → stdout `estimate=malformed …` + stderr `<file>:<line>:<field>:malformed`, exit 2; несколько malformed-полей — по возрастанию `<line>`.
- Discuss.md clause-assertions (через харнесс C9, `assert_clause` + `assert_clause_load_bearing`): `triage-six-categories` (секция Size triage перечисляет все шесть категорий рубрики теми же именами, что breakdown-схема C1 — по одной клаузе на категорию либо одна клауза на строку таблицы; мутация: переименовать `shell_scripts` → `scripts`); `triage-child-interview` (текст explicit требует «своё интервью» для каждого принятого child; мутация: снять «каждая»); `triage-decline` (право отказа от рекомендации; мутация: снять «может отказаться»); `triage-registry` (реестр через `mb-idea.sh` с префиксом `[SPEC:<group>]`; мутация: снять префикс); `triage-defer-or-mvp` (для spec-sized ветки explicit предложены оба варианта — defer / MVP; мутация: удалить вариант MVP).
- Сценарии §3, §10, §17 — ручной приёмочный чек-лист поверх bats.

**DoD:**
- [x] Секция триажа + рубрика (6 категорий) + decompose/MVP-выбор в discuss.md; скрипт по C1
- [x] Каждая клауза несёт и `assert_clause`, и `assert_clause_load_bearing`
- [x] bats green (был red по заявленному условию), shellcheck clean
- [x] Сценарии §3, §10, §17 отрабатывают (оценка 2.4M → именованные child-спеки с обещанием интервью → реестр; spec-sized ветка → defer/MVP выбор)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Транскрипт интервью + secret-scan диспетчер + приватность

**Stage:** 2
**Covers:** REQ-005, REQ-006, REQ-007
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/discuss.md, references/templates.md, scripts/mb-secret-scan.sh, scripts/mb-interview-artifact-check.sh, scripts/mb-interview-artifact-write.sh, tests/bats/test_mb_secret_scan.bats, tests/bats/test_mb_interview_artifact_check.bats, tests/bats/test_mb_interview_artifact_write.bats, tests/bats/test_discuss_transcript.bats
**Budget:** 120000

**What to do:**
- Шаг «Transcript» в Write & finalize discuss.md: курируемый транскрипт сначала пишется кандидатом в `<bank>/tmp/interview-transcript-<topic>.candidate.md` по **грамматике C4** (заголовок с topic+ISO-датой → опц. `## Унаследовано` → `## Q&A` с блоками `**Q<N> …**`/`**A<N>.**`, дословными ответами, ссылками `**D-NN**` и per-Q `Отклонено:/Rejected:` → `**Финальный гейт[, круг M].**` + `**Ответ.**`); публикация в git-путь — через writer C11 (не prompt-`mv`); frontmatter контекста получает `interview_transcript:`.
- Новый `scripts/mb-secret-scan.sh --policy <transcript|brief-input> <file>` по контракту C5: диспетчер политик + политика `transcript` (владение S1); паттерны single-sourced из `scripts/mb-import.py` (`EMAIL_RE:39`/`APIKEY_RE:41`); метки `email`/`api_key`; находки по возрастанию `(line, column)`; сам секрет не печатается; **`<private>` НЕ подавляет находку — сканируется сырой текст включая содержимое `<private>` (critical R3-001: `<private>` защищает index/search, НЕ git diff)**; pragma `<!-- mb-secret-ok -->` политикой `transcript` **не** признаётся; `--policy brief-input` до поставки S7 → usage error exit 2 (`policy_not_implemented`), тихим «чисто» не становится; exit 0 → публикация; exit 1/2 → целевой файл не создаётся/не меняется, находки/ошибка показываются пользователю (REQ-007).
- Расширить `scripts/mb-interview-artifact-check.sh` (T1) режимом `transcript` по контракту C8: грамматика C4 (правила 1–8, строгие answer/rejected) + флаги `--require-inherited`/`--legacy-live-fixture` + reason-коды (`rejected_alternatives_missing`, `legacy_fixture_forbidden`).
- Расширить `scripts/mb-interview-artifact-write.sh` (T1) режимом `publish-transcript` по контракту C11: вызывает C5 `--policy transcript` + C8 `transcript`, при обоих success **атомарно** заменяет `<bank>/context/<topic>-interview.md`; failed scan/check → target byte-identical, stdout пуст (SVP-IU-002 — атомарная публикация как детерминированный seam, не prompt-`mv`).
- `<private>`-фрагменты остаются как есть в тексте — существующий index/search-слой их обрабатывает (REQ-006 — добавить проверку, что transcript-файлы попадают под этот слой).
- Шаблон транскрипта → `references/templates.md` (ровно грамматика C4).

**Eval:** `bats tests/bats/test_mb_secret_scan.bats && bats tests/bats/test_mb_interview_artifact_check.bats && bats tests/bats/test_mb_interview_artifact_write.bats && bats tests/bats/test_discuss_transcript.bats` — red: bats-файлы материализованы; падает `assert_script_present scripts/mb-secret-scan.sh` (скрипта нет); `mb-interview-artifact-check.sh transcript` отвечает usage error вместо `artifact=ok` на позитивных фикстурах C4-9; `publish-transcript` (C11) не публикует; clause-assertions шага Transcript — `clause=<id> reason=absent`; exit: 1; output~: `not ok [0-9]+ (secret_scan|artifact_check|artifact_write|transcript): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста в `test_mb_secret_scan.bats` начинается с `secret_scan: `, в `test_mb_interview_artifact_check.bats` — с `artifact_check: ` (тот же префикс, что задан в T1: файл расширяется, не заменяется), в `test_mb_interview_artifact_write.bats` — с `artifact_write: `, в `test_discuss_transcript.bats` — с `transcript: `. Якорь покрывает первый (короткозамыкающий) конъюнкт `&&`-цепи и остаётся валидным для остальных.
- `tests/bats/test_mb_secret_scan.bats` (ДО скрипта): чистый файл → stdout ровно `scan=clean`, exit 0; файл с `sk-…`-ключом → `scan=blocked` + stderr `<file>:<line>:api_key`, exit 1; файл с email → `<file>:<line>:email`; email+api_key в одном файле → две stderr-строки по возрастанию `(line, column)`; две находки на одной строке → две отдельные строки в порядке колонок; сам секрет отсутствует и в stdout, и в stderr (grep по значению ключа не находит); **секрет внутри `<private>...</private>` → `scan=blocked` (critical R3-001: сырой текст сканируется, `<private>` находку НЕ подавляет; номера строк — исходные)**; секрет с `<!-- mb-secret-ok -->` рядом → всё равно `scan=blocked` (политика `transcript` прагму не признаёт); **классификация инспектируемости (X-03), детерминированный порядок**: нет файла/каталог/нет прав → `scan=unsupported` reason `unreadable`; файл с NUL-байтом → reason `binary`; известный контейнер по magic-сигнатуре (PDF `%PDF-`, OOXML/ZIP `PK\x03\x04`, gzip `\x1f\x8b`) → reason `unsupported_type`; невалидный UTF-8 (не контейнер) → reason `unsupported_type`; readable regular UTF-8 без NUL → **scannable** (скан продолжается, не `unsupported`); все не-scannable → `scan=unsupported` exit 2 (подтверждает S7 «binary → unsupported», не меняет); `--policy brief-input` → usage error, stdout пуст, stderr `policy_not_implemented`, exit 2; неизвестная политика / отсутствующий `--policy` / два файла → usage error exit 2; паритет паттернов с `mb-import.py` (тот же набор классов); shellcheck clean.
- `tests/bats/test_mb_interview_artifact_check.bats` (расширение, `transcript`-режим, ДО кода): **позитивные фикстуры C4-9** — реальные `context/sdd-vision-pipeline-interview.md` (без `## Унаследовано`, два финальных гейта с `, круг 1|2`, голосовые ответы-цитаты в Q4/Q6/Q7, отклонённые сводной секцией — прогон с `--legacy-live-fixture`) и `context/svp-interview-upgrade-interview.md` (с `## Унаследовано`, один гейт, `**A<N>.**`+per-Q `Отклонено:`, `--require-inherited --legacy-live-fixture`) → оба `artifact=ok`, exit 0; **негативные фикстуры, по одной на обязательный элемент грамматики**, каждая exit 1 с детерминированным reason-кодом: заголовок не той формы → `missing_title` (без `bad_date`); дата `17-07-2026`/`2026-02-31` → `bad_date` (двухступенчатая C4-1); нет `## Q&A` → `missing_qa_section`; два `## Q&A` → `duplicate_qa_section`; `--require-inherited` без секции → `missing_inherited`; `## Унаследовано` после `## Q&A` → `inherited_after_qa`; ноль Q-блоков → `no_questions`; Q2 перед Q1 → `q_number_out_of_order`; два Q3 → `q_number_duplicate`; **строгий режим (без флага): Q-блок без `**A<N>.**` → `answer_missing`; Q-блок, где `«…»` только в ВОПРОСЕ/отклонённой альтернативе → `answer_missing` (SVP-IU-005); один из двух Q-блоков с решением без `Отклонено:/Rejected:` → `rejected_alternatives_missing` (SVP-IU-005)**; Q-блок без `**D-NN**` → `decision_missing`; нет финального гейта → `missing_final_gate`; гейт без `**Ответ.**` → `gate_answer_missing`; два гейта без `, круг N` → `gate_round_missing`; круг 2 перед кругом 1 → `gate_round_out_of_order`; **`--legacy-live-fixture` на любом файле кроме двух зафиксированных → `<file>:0:legacy_fixture_forbidden` exit 2 (SVP-IU-005)**; `--require-closed` с режимом `transcript` → usage error exit 2; usage → stderr `error=usage`, нечитаемый → `<file>:0:unreadable` (R3-003).
- `tests/bats/test_mb_interview_artifact_write.bats` (C11 `publish-transcript`, ДО кода, fixture-банк): чистый candidate → `artifact_write=installed kind=transcript` exit 0 + **git-target `context/<topic>-interview.md` появился/заменён** (снимок до/после); candidate с секретом (в т.ч. под `<private>`) → exit 1, stdout пуст, **git-target byte-identical/не создан** (R3-001 — секрет в git не попал); candidate с битой грамматикой → exit 1, target byte-identical; usage/I/O → exit 2; shellcheck clean.
- `tests/bats/test_discuss_transcript.bats` (через харнесс C9, `assert_clause` + `assert_clause_load_bearing`): `transcript-candidate-first` (шаг Transcript пишет кандидата в `tmp/` ДО git-пути; мутация: снять «до»); `transcript-scan-gate` (secret-scan вызывается над кандидатом до публикации; мутация: «до» → «после»); `transcript-private-not-clean` (секрет под `<private>` блокирует публикацию, `<private>` не разблокирует git-запись; мутация: снять «включая `<private>`»); `transcript-block-on-finding` (находка → целевой файл не создаётся, пользователю предложены удаление/необратимая редакция; мутация: снять «не создаётся»); `transcript-frontmatter` (контекст получает `interview_transcript:`; мутация: снять поле); `template-c4-grammar` (шаблон в templates.md несёт все маркеры грамматики C4; мутация: удалить `**Финальный гейт`).
- Сценарии §4, §8, §9 — ручной приёмочный чек-лист поверх bats.

**DoD:**
- [x] Transcript-шаг (двухфазная запись через `tmp/` кандидата) + secret-scan-гейт (сырой текст, `<private>` не подавляет — R3-001) + artifact-check `transcript`-режим + publish-transcript writer (C11) в discuss.md; шаблон C4 в templates.md
- [x] Секрет под `<private>` в candidate → `scan=blocked`, в git-target не попадает (доказано fixture-тестом до/после); оба живых транскрипта проходят `artifact=ok` под `--legacy-live-fixture` (регресс-гейт C4-9); строгие answer/rejected имеют негативные фикстуры (SVP-IU-005); каждый обязательный элемент грамматики — свою негативную фикстуру
- [x] Eval green (был red по заявленному условию), shellcheck clean
- [x] Сценарии §4, §8, §9 отрабатывают (ключ блокирует запись; приватный фрагмент — нет; целевой файл не создаётся при блокировке)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Глоссарий

**Stage:** 2
**Covers:** REQ-017, REQ-018
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/discuss.md, references/templates.md, scripts/mb-context.sh, scripts/mb-glossary.sh, tests/bats/test_discuss_glossary.bats, tests/bats/test_mb_glossary.bats
**Budget:** 90000

**What to do:**
- Grilling rule 13: разрешённый термин → немедленная запись в `.memory-bank/glossary.md` **через `mb-glossary.sh upsert`** (не prompt-`echo`); конфликт позднего употребления с глоссарием → челлендж до записи требования (REQ-018).
- Новый `scripts/mb-glossary.sh upsert` по контракту C12 (SVP-IU-002 — детерминированный writer файлового эффекта REQ-017): term/definition из файлов; строка `<term> — <definition>` создаётся/обновляется **атомарно** (ленивое создание `glossary.md`); тот же term с другим определением → `glossary=conflict` exit 1 без изменения файла (REQ-018-совместимо); create/update/unchanged → exit 0; usage/I/O → exit 2.
- Шаблон глоссария → `references/templates.md`.
- `scripts/mb-context.sh` по контракту C10 design.md — **реальный writer выдачи `/mb context`** (`scripts/mb-context.sh:33-89`): ровно одна строка `Glossary: <path>` после блока core-файлов и до `--- Active plans ---`, только если `<bank>/glossary.md` существует обычным файлом (symlink → skip, `mb_canonical_under` guard сохраняется); содержимое файла в выдачу не конкатенируется; скрипт остаётся read-only.

**Eval:** `bats tests/bats/test_discuss_glossary.bats && bats tests/bats/test_mb_glossary.bats` — red: bats-файлы материализованы; падают clause-assertions rule 13 (`clause=<id> reason=absent` — правила в `commands/discuss.md` нет), fixture-run `mb-context.sh` на банке с `glossary.md` (строки `Glossary: …` в выдаче нет) и `assert_script_present scripts/mb-glossary.sh` (upsert/conflict не работают); exit: 1; output~: `not ok [0-9]+ (glossary|mb_glossary): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста в `test_discuss_glossary.bats` начинается с `glossary: `, в `test_mb_glossary.bats` — с `mb_glossary: ` (обоснование — то же, что в T1). Якорь покрывает первый конъюнкт `&&`-цепи и остаётся валидным для второго.
- `tests/bats/test_discuss_glossary.bats`, часть 1 — **файловое поведение реального writer'а** (fixture-банки во `$BATS_TEST_TMPDIR`, вызов `bash scripts/mb-context.sh <fixture-bank>`): банк БЕЗ `glossary.md` → выдача **байт-идентична** зафиксированному до-правочному прогону (регресс-фикстура) и ни одной строки `Glossary:`; банк С `glossary.md` → ровно одна строка `Glossary: glossary.md`, стоит после блока core-файлов и до `--- Active plans ---`, содержимое глоссария в выдачу не попало; `glossary.md` как symlink → строка не печатается (skip-guard); повторный вызов не создаёт и не меняет ни одного файла в банке (сравнение `find`-снимка до/после).
- `tests/bats/test_mb_glossary.bats` (C12, ДО скрипта, fixture-банк): первый термин → `glossary=created` exit 0 + `glossary.md` создан со строкой `<term> — <def>`; тот же term+то же определение → `glossary=unchanged` exit 0, файл не менялся; тот же term+другое определение → `glossary=conflict` exit 1, **файл byte-identical** (REQ-018); другой term → `glossary=updated`/append; usage/I/O → exit 2; shellcheck clean.
- `tests/bats/test_discuss_glossary.bats`, часть 2 — **prompt-контракт** (через харнесс C9, `assert_clause` + `assert_clause_load_bearing`): `rule13-write-immediate` (rule 13 требует немедленной записи термина через `mb-glossary.sh` при разрешении; мутация: «немедленно» → «в конце интервью»); `rule13-lazy-create` (ленивое создание файла на первом термине; мутация: снять «создаётся»); `rule13-line-format` (строка «термин — определение»; мутация: снять формат); `rule13-challenge-conflict` (конфликтующее употребление челленджится ДО записи требования; мутация: «до записи требования» → «после записи требования»); `template-glossary` (шаблон глоссария в templates.md с форматом «термин — определение»; мутация: удалить формат-строку).
- Сценарий §5, §14 — ручной приёмочный чек-лист поверх bats.

**DoD:**
- [x] Правило 13 в discuss.md; шаблон; строка `Glossary:` в `scripts/mb-context.sh` по C10; `mb-glossary.sh upsert` (C12) — атомарная запись, conflict без изменения файла (доказано fixture-тестом)
- [x] Банк без глоссария → выдача `/mb context` байт-идентична; банк с глоссарием → ровно одна строка-указатель
- [x] Каждая клауза несёт и `assert_clause`, и `assert_clause_load_bearing`
- [x] Eval green (был red по заявленному условию), shellcheck clean
- [x] Сценарии §5, §14 отрабатывают
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Self-interview + assumptions + флаги C6

**Stage:** 2
**Covers:** REQ-012, REQ-013, REQ-014
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/discuss.md, tests/bats/test_discuss_self_interview.bats
**Budget:** 65000

**What to do:**
- Флаги `--self "<brief>"` и `--auto` в discuss.md (контракт C6): агент сам отвечает на вопросы интервью из брифа; каждое self-answered решение → `## Assumptions (self-answered)` в context-файле; интерактив — пакет assumptions на подтверждение ДО генерации (REQ-013); `--auto` — без блокировки, ревизия предлагается после (REQ-014).
- Валидация комбинаций флагов (C6): `--auto` без `--self` → usage error до записи файлов; пустой/whitespace-only brief → usage error до записи файлов; `--batch` совместим с `--self` (меняет только размер фронтира); существующий `draft`-context → возобновление сохранённого interview-plan; существующий `ready`-context → сохраняется текущий выбор edit/overwrite/cancel.
- Дефолт без флагов не меняется (quality-default: живое интервью).

**Eval:** `bats tests/bats/test_discuss_self_interview.bats` — red: bats-файл материализован; падают clause-assertions flag-matrix `--self`/`--auto`/Assumptions-блока (`clause=<id> reason=absent` — секции «Self-interview» в `commands/discuss.md` нет); exit: 1; output~: `not ok [0-9]+ self_interview: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `self_interview: ` (обоснование — то же, что в T1).
- `tests/bats/test_discuss_self_interview.bats` (через харнесс C9, `assert_clause` + `assert_clause_load_bearing` на каждую клаузу): `self-answers-from-brief` (`--self "<brief>"` — агент отвечает сам из брифа; мутация: снять «из брифа»); `self-assumptions-block` (каждое self-answered решение пишется в `## Assumptions (self-answered)`; мутация: «каждое» → «важные»); `self-batch-confirm` (интерактивный self-interview требует пакетного подтверждения assumptions ДО генерации; мутация: «до генерации» → «после генерации»); `auto-non-blocking` (`--auto` не блокирует и предлагает ревизию ПОСЛЕ завершения; мутация: снять «после»); `auto-requires-self` (`--auto` без `--self` → usage error ДО записи файлов; мутация: снять «до записи файлов»); `empty-brief-usage-error` (пустой/whitespace-only brief → usage error до записи файлов; мутация: снять «whitespace-only»); `batch-self-compatible` (`--batch` совместим с `--self`, меняет только размер фронтира; мутация: «только размер фронтира» → «режим ответа»); `draft-resume` (`draft`-context → возобновление сохранённого interview-plan; мутация: «возобновляет» → «начинает заново»); `ready-context-choice` (`ready`-context → сохраняется текущий выбор edit/overwrite/cancel; мутация: удалить `cancel`).
- Сценарий §6, §11 — ручной приёмочный чек-лист поверх bats.

**DoD:**
- [x] Флаги + Assumptions-блок + матрица допустимых/ошибочных комбинаций (C6) в discuss.md
- [x] Каждая клауза несёт и `assert_clause`, и `assert_clause_load_bearing`
- [x] Eval green (был red по заявленному условию)
- [x] Сценарии §6, §11 отрабатывают
<!-- /mb-task:6 -->
