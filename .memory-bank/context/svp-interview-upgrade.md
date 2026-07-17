---
topic: svp-interview-upgrade
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview_transcript: context/svp-interview-upgrade-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-004, REQ-010, REQ-011, REQ-012, REQ-013, REQ-014, REQ-015, REQ-033, REQ-034, REQ-040, REQ-054]
---

# Context: svp-interview-upgrade (слайс S1 группы sdd-vision-pipeline)

Апгрейд `/mb discuss`: план интервью с проверкой закрытия, финальный гейт «есть что добавить», размерный триаж с декомпозицией в группы, глоссарий, курируемый транскрипт для планировщика/ревьювера, batch-режим, self-interview с assumptions. Родительские решения — `context/sdd-vision-pipeline.md` (D-01…D-31); здесь только слайс-специфика (S1-D-01…06).

## Purpose & Users

- **Кто**: пользователь, брифующий агента через `/mb discuss` (интерактивно, batch или self-interview); downstream — sdd-планировщик и spec-ревьювер, читающие транскрипт.
- **Проблема**: интервью теряет намеченные темы при уходе в сторону; пользователю негде дополнить в конце; большая тема не распознаётся вовремя; терминология дрейфует; леджер решений — недостаточный контекст для планировщика/ревьювера.
- **Успех**: ни одного белого пятна из плана интервью не потеряно; генерация только после явного «нет» на финальном гейте; тема >~1M токенов надёжно триггерит предложение декомпозиции; транскрипт воспроизводит ход обсуждения дословно и безопасно (секреты не утекают в git).

## Research Digest

- `commands/discuss.md:37-54` — grilling rules 1–10: точка врезки правил плана/гейта/триажа.
- `commands/discuss.md:95-101` — Write & finalize: точка врезки транскрипта и глоссария.
- `context/sdd-vision-pipeline-interview.md` — живой образец транскрипта (D-29 применён вручную 2026-07-17).
- `.memory-bank/session/*.md` — session capture уже пишет сырые логи; транскрипт — другой артефакт: курируемый, по-топиковый.
- `<private>`-механизм существует (исключение из index.json, редакция в `/mb search`) — CLAUDE.md § Personalization.
- Secret-scan для `specs/<topic>/inputs/` специфицирован отдельно в `specs/sdd-openspec-parity/requirements.md` (+ `<!-- mb-secret-ok -->` прагма) — это внутренняя проверка `mb-spec-validate.sh` (`specs/sdd-openspec-parity/tasks.md:119-136`), не общий CLI; ревью spec-group (SVP-IU-003) установило, что общего секрет-скан-CLI пока не существует. Этот слайс создаёт и **владеет** первым общим `scripts/mb-secret-scan.sh` — диспетчер `--policy <transcript|brief-input>`, паттерны single-sourced из `scripts/mb-import.py` (`EMAIL_RE:39`/`APIKEY_RE:41`); S1 реализует политику `transcript` (без прагма-байпаса), потребитель S7 (`svp-brief`, `blocked_by: [svp-interview-upgrade]`) реализует в том же файле политику `brief-input` по зафиксированному здесь контракту (design.md C5).
- `platform_limited` — закрытый словарь манифеста (`specs/adapter-parity/design.md:143-145`: `statusline`, `subagents`, `lifecycle-hooks`, `session-memory`, `update-notify`, `role-routing`); `subagents` = у хоста нет примитива диспатча вообще → сигнал для деградации fact-finding (REQ-056).
- `glossary.md` в банке отсутствует; шаблона в `references/templates.md` нет — создаётся с нуля.
- AskUserQuestion — до 4 вопросов/вызов (batch-раунды ложатся на Claude Code); хосты без него → нумерованный текст (паттерн honest degradation, AGR-013).
- Бюджеты D-13: задача ≤120k · этап ≤400k · спека ~1M — пороги для скрипт-сравнения оценки.

## Decision Log

- **S1-D-01**: Оценка объёма темы — LLM по фиксированной рубрике (затрагиваемые модули/файлы/новые скрипты/тесты → токены по таблице коэффициентов), с разбивкой пишется в frontmatter (`estimated_tokens`); скрипт детерминированно валидирует наличие/формат и сравнивает с порогами D-13. — Rejected: чистая LLM-оценка (непроверяемо), формула по числу REQ (REQ разновесны; доступна слишком поздно для раннего триажа).
- **S1-D-02**: Приватность транскрипта — `<private>`-механизм переиспользуется + при записи прогоняется новый `mb-secret-scan.sh --policy transcript` (владеет этот слайс, T4; паттерны single-sourced из `mb-import.py`, без прагма-байпаса — строже, чем `inputs/`-политика `sdd-openspec-parity`); находка блокирует запись до очистки. — Rejected: транскрипт вне git (ломает D-29 — ревьювер в другой сессии не увидит), запись как есть (утечка в git-историю), ожидание реализации `sdd-openspec-parity` (там нет общего CLI — spec-review SVP-IU-003).
- **S1-D-03**: Interview-plan файл — `<bank>/tmp/interview-plan-<topic>.md` (эфемерный; долговечный артефакт — транскрипт); шаблон включает секцию «Унаследованные решения — не переспрашивать» (для JIT-интервью слайсов) и темы ⬜/✅; отмена интервью → `status: draft` + план сохраняется для резюма.
- **S1-D-04**: Self-interview assumptions — блок `## Assumptions (self-answered)` в контексте; интерактив: пакет на подтверждение перед генерацией; `--auto`: не блокирует, ревизия предлагается после завершения.
- **S1-D-05**: Batch-режим — флаг `--batch`; Claude Code: раунды через AskUserQuestion (до 4 вопросов/вызов); хосты без него: нумерованный plain-text (honest degradation).
- **S1-D-06**: Глоссарий — один `.memory-bank/glossary.md`, строка = «термин — определение»; обновление inline при разрешении термина; конфликтные употребления челленджатся до записи требования. Строка-указатель в выдаче `/mb context` добавляется в реальный writer `scripts/mb-context.sh` (design.md C10), а не в prompt — `commands/mb.md` выдачу не собирает (spec-review R2-002).
- **S1-D-07** (ревизия 3, spec-review D-18-FACT-FINDING): fact-finding фронтира — вторая половина D-18, потерянная в ревизиях 1–2. Под `--batch` каждый разблокированный вопрос фронтира расследуется до раунда, рекомендация REQ-015 цитирует найденный факт; хост с диспатчем сабагентов → параллельные сабагенты по одному на вопрос (REQ-055); хост без него (`platform_limited: subagents`) → тот же fact-finding последовательно основным агентом + явное сообщение о деградации (REQ-056). Дефолт без `--batch` не меняется — по одному вопросу, без параллельного диспатча (D-18). — Rejected: молчаливый пропуск fact-finding на хостах без сабагентов (нечестная деградация, AGR-013), отдельный флаг под fact-finding (D-18 связывает его с frontier-опцией, а не с новым переключателем), параллельный диспатч по умолчанию (ломает «дефолт — по одному вопросу»).
- **S1-D-02-R4** (ревизия 4, круг 3, critical R3-001): уточнение S1-D-02 — `<private>` и secret-scan **ортогональны**. `<private>` влияет ТОЛЬКО на index/search-редакцию (REQ-006); secret-scan `transcript` сканирует **сырой** текст включая содержимое `<private>` и **блокирует** секрет до git-tracked файла (rules/RULES.md caveat: `<private>` не защищает git diff). Пометить строку `<private>` — НЕ способ протащить credential в git; разблокировка только удалением/необратимой редакцией. Выравнено с owner-контрактом S7 `brief-input` (`svp-brief/design.md:147-170`). — Rejected: маскирование `<private>` до скана (ревизия 3 — оставляла plaintext-секрет в git-tracked транскрипте).

## Functional Requirements (EARS)

REQ-неймспейс слайс-локальный; мапинг на umbrella — в комментариях.

- **REQ-001** (event-driven): When an interview starts, the system shall write an interview plan file to `<bank>/tmp/interview-plan-<topic>.md` listing the topics to close and the inherited decisions not to re-ask. <!-- umbrella REQ-012, S1-D-03 -->
- **REQ-002** (unwanted): If any interview plan item remains unclosed before artifact generation, then the system shall return to it and ask the missing questions before generating. <!-- umbrella REQ-013 -->
- **REQ-003** (event-driven): When the interview plan has no remaining open topics, the system shall ask the user a final "anything to add?" question before generating artifacts. <!-- umbrella REQ-010 -->
- **REQ-004** (unwanted): If the user adds new material at the final gate, then the system shall reopen the discussion iteration and update the decision ledger before generation. <!-- umbrella REQ-011 -->
- **REQ-005** (event-driven): When the interview completes, the system shall save a curated transcript to `context/<topic>-interview.md` preserving the user's answers near-verbatim, including rejected alternatives. <!-- umbrella REQ-034, D-29 -->
- **REQ-006** (ubiquitous): The transcript shall honor `<private>` markers — private fragments excluded from the index and redacted in search output. <!-- S1-D-02 -->
- **REQ-007** (unwanted): If the secret-scan flags content in a transcript being written, then the system shall block the write until the content is cleaned or explicitly marked private. <!-- S1-D-02 -->
- **REQ-008** (event-driven): When Phase 1 of the interview completes, the system shall estimate the topic size in tokens using the fixed rubric and record the estimate with its breakdown in the context frontmatter. <!-- S1-D-01 -->
- **REQ-009** (unwanted): If the estimated size exceeds the spec budget (~1M tokens), then the system shall recommend decomposition into named grouped specs — stating that each accepted child receives its own follow-up interview — and let the user decline the recommendation. <!-- umbrella REQ-014 -->
- **REQ-010** (event-driven): When the user accepts decomposition, the system shall register the deferred specs in the decomposed-spec registry with the group name and continue the interview on the selected spec. <!-- umbrella REQ-015/041 -->
- **REQ-011** (ubiquitous): The system shall validate the presence and format of the size estimate by script and compare it against the configured budgets. <!-- S1-D-01, D-13 -->
- **REQ-012** (optional): Where self-interview mode is requested with a brief, the system shall answer the interview questions itself and record every self-answered decision in an Assumptions block. <!-- umbrella REQ-004 -->
- **REQ-013** (state-driven): While in interactive self-interview, the system shall present the assumptions batch for user confirmation before generation. <!-- S1-D-04 -->
- **REQ-014** (state-driven): While in auto mode, the system shall record assumptions without blocking and shall offer their review after completion. <!-- S1-D-04 -->
- **REQ-015** (optional): Where batch mode is requested, the system shall ask the whole current frontier of unblocked questions in one numbered round with a recommendation per question. <!-- umbrella REQ-040 -->
- **REQ-016** (unwanted): If the host lacks an interactive question tool, then the system shall degrade the batch round to numbered plain text. <!-- S1-D-05 -->
- **REQ-017** (event-driven): When a term is resolved during the interview, the system shall update `glossary.md` inline. <!-- umbrella REQ-033, S1-D-06 -->
- **REQ-018** (unwanted): If a later statement conflicts with an existing glossary term, then the system shall challenge the conflict before recording the requirement. <!-- S1-D-06 -->
- **REQ-019** (event-driven): When an interview is cancelled mid-way, the system shall keep the context file at status draft and preserve the interview plan file for resume. <!-- S1-D-03 -->
- **REQ-020** (optional): Where the user explicitly selects fast-to-code mode, the system shall allow bypassing the remaining interview and decomposition steps after recording the choice and its quality trade-off in the context frontmatter, with quality mode remaining the default. <!-- umbrella REQ-054, D-11 -->
- **REQ-021** (unwanted): If an interview branch is estimated at spec size, then the system shall offer either deferring it as a child spec or simplifying it to an MVP inside the current topic before continuing. <!-- umbrella D-12 -->
- **REQ-022** (unwanted): If a batch round is only partially answered, then every unanswered question shall remain unchecked in the interview plan and return in the next frontier. <!-- S1-D-05 -->
- **REQ-055** (optional): Where batch mode is requested on a host providing subagent dispatch, the system shall fact-find the frontier questions in parallel subagents before asking the round and shall ground each per-question recommendation in a cited finding. <!-- umbrella REQ-040, D-18, S1-D-07 -->
- **REQ-056** (unwanted): If the host lacks subagent dispatch, then the system shall run the same frontier fact-finding sequentially in the main agent and shall report the degradation to the user. <!-- D-18, S1-D-07, AGR-013 -->

## Non-Functional Requirements

- **NFR-001**: Токен-экономия — план интервью компактный (строки-темы, не проза); транскрипт курируемый, не сырой дамп сессии.
- **NFR-002**: Детерминизм — наличие/формат оценки объёма, плана и транскрипта проверяются скриптом, не LLM. Реализуется тремя самостоятельными CLI: `mb-estimate-check.sh` (design.md C1), `mb-secret-scan.sh` (C5), `mb-interview-artifact-check.sh plan|transcript` (C8) — все три с bats-покрытием, ни один не зависит от кода другой спеки. Остаточный prompt-контракт (то, что LLM исполняет, а не скрипт) проверяется харнессом C9: section-scoped clause-ERE + обязательная negation-мутация; голый grep/co-occurrence запрещён как assertion-гейт (spec-review SVP-IU-002).
- **NFR-003**: Кросс-платформенность — batch и финальный гейт работают на всех 8 клиентах (текстовая деградация, AGR-013).

## Constraints

- Session capture (`session/*.md`) не изменяется — транскрипт отдельный артефакт.
- `scripts/mb-secret-scan.sh` создаётся и владеется этим слайсом (T4); паттерны single-sourced из `scripts/mb-import.py`, не дублируются вторым regex-набором (design.md C5).
- Поведение `/mb discuss` без новых флагов меняется только добавлением плана/гейта/триажа/транскрипта (quality-default, D-11); существующие 5 фаз и grilling rules сохраняются.
- Rubric-коэффициенты — в тексте команды (правится без кода); пороги — из D-13; категории рубрики 1:1 с ключами `estimated_tokens.breakdown` (design.md C1/C3).

## Edge Cases & Failure Modes

- Интервью прервано после записи плана → `status: draft`, план в tmp сохранён; резюм читает его и продолжает с незакрытых тем (REQ-019).
- JIT-интервью слайса → секция «Унаследованные решения» предзаполняется из parent_context — вопросы не повторяются (S1-D-03).
- Секрет в голосовом ответе пользователя → secret-scan блокирует запись транскрипта; пользователю предлагается очистка или `<private>` (REQ-007).
- Оценка объёма на грани (~0.9–1.1M) → рекомендация с оговоркой о погрешности; решение за пользователем (REQ-009 допускает отказ).
- Batch-раунд из >4 вопросов в Claude Code → несколько AskUserQuestion-вызовов подряд в одном раунде.
- Пользователь отвечает на batch частично → неотвеченные возвращаются в план как открытые темы (REQ-022).
- `--batch` на хосте без диспатча сабагентов (`platform_limited: subagents`) → fact-finding не пропускается, а выполняется последовательно основным агентом; деградация сообщается одной строкой (REQ-056).
- Fact-finding по вопросу не нашёл фактов → рекомендация REQ-015 явно помечается как догадка (существующее правило Phase 0: «A recommendation without a citation is a guess — say so explicitly», `commands/discuss.md:35`).
- Ветка обсуждения внутри текущей темы разрастается до размера отдельной спеки до завершения секции → предложены defer-as-child-spec / simplify-to-MVP, интервью продолжается по выбору (REQ-021).
- Пользователь выбирает fast-to-code в любой момент → оставшиеся шаги плана/гейта/триажа пропускаются, выбор и trade-off зафиксированы в frontmatter, quality остаётся дефолтом следующих интервью (REQ-020).

## Out of Scope

- Полная tasks.md v2 инфраструктура (парсер `mb_work_items.py`, `mb-spec-validate.sh` v2-гейты, бюджет-суммирование по Stage/спеке, Eval-first врезка в `/mb work`) — слайс S2 (`svp-sdd-core` C1/C2/C6). Этот слайс лишь **потребляет** поля `Stage:`/`Blocked-by:`/`Scope:`/`Budget:` в своём tasks.md текстом (bootstrap раньше S4-автоматики, прецедент — `svp-contract-test-loop/tasks.md`); текущий `mb_work_items.py` их не парсит (легаси-проекция работает как раньше, byte-identical).
- `mb-estimate-check.sh --spec <topic>` (пер-задачные/пер-этапные бюджеты из tasks.md) — слайс S2 (C3), этот слайс реализует только контекст-уровневый режим (C1).
- Автоматика Group-рендера в роадмепе и реестр декомпозированных спек как код — слайс S4 (здесь только запись в реестр в текущем формате backlog.md).
- Изменения /mb work — слайсы S3/S5.

## Open Questions

- Значения коэффициентов рубрики оценки (токенов на модуль/скрипт/тест) — подобрать при планировании, откалибровать по фактам первых спек (blocked on: план слайса).

Резолвировано ревизией 2 (spec-review SVP-IU-004/005): формат `estimated_tokens.breakdown` (шесть категорий,
count/unit_tokens/subtotal), CLI-контракты `mb-estimate-check.sh`/`mb-secret-scan.sh`/
`mb-interview-artifact-check.sh` и точная структура interview-plan файла зафиксированы в
`design.md` C1/C5/C8 — больше не открытые вопросы.
