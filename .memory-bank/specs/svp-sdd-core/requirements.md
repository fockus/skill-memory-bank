---
topic: svp-sdd-core
group: sdd-vision-pipeline
ice: {impact: 10, confidence: 8, ease: 5}
ice_confirmed: false
blocked_by: []
covers_umbrella: [REQ-001, REQ-002, REQ-003, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-016, REQ-022, REQ-035, REQ-039, REQ-047, REQ-048]
status: draft
---

# Requirements: svp-sdd-core

> Spec triple — see also: design.md, tasks.md.
> Слайс S2 группы `sdd-vision-pipeline` (ICE 400, self-interview). Контекст: `context/svp-sdd-core.md`;
> транскрипты: `context/svp-sdd-core-interview.md` + родительский.
>
> Ревизия 3 (2026-07-17): закрыты находки круга 2 (F-007/009/010, R2-001…003) + назначенные
> смысловые (D-25-STRUCTURAL-EVAL, D-17-SINGLE-SEAM). Ключевое: REQ-015 разводит generation-preflight
> и behavioral red (D-05 не нарушается — отсутствие ещё не написанного eval-кода больше не выдаётся
> за red); добавлены REQ-049 (обязательный структурный Eval для docs/config-задач), REQ-050 (waiver —
> явное исключение с причиной, не замена), REQ-051 (один seam, D-17/umbrella REQ-009), REQ-052 (цикл
> Blocked-by валит spec-валидацию — запрос ревью S3, SVP-PE-001). Новые ID выданы
> `scripts/mb-req-next-id.sh --spec svp-sdd-core` (нумерация per-spec-local, D-26 — существующие
> REQ-001…015 не тронуты).
> Ревизия 4 (2026-07-18, круг 3): F-010 закрыт реальным швом (`eval-red`/`eval-green` сами гоняют
> команду — судья не подменяем флагом); REQ-054 (generation preflight) вынесен в детерминированный
> `mb-sdd-self-check.sh` (Task 9, снят с T8, R3-001); candidate lifecycle → `mb-sdd-candidate.sh`
> с сужением override до `spec=over` (R3-002/003); C1 — restricted-glob грамматика (R3-004); REQ-022
> добавлен в `covers_umbrella` как spec-time рубеж (R3-005); status state machine draft→ready (R3-006);
> примеры Eval в Scenario 4/8 приведены к якорям C1 (R3-007); диапазон namespace 049…055 (R3-008).
> Текст REQ-001…055 не менялся — правки в трассировке, задачах, design и сценариях.
> Ревизия 5 (2026-07-19, круг 2 ревью S2, AGR-026): скорректирована **модель доверия eval-пруфа**.
> Ревизия 4 читалась как обещание неподделываемого verdict-а («судья не подменяем»); фактически
> ключ подписи лежит в чекауте, поэтому агент, способный править `.work-state.json`, способен и
> пересчитать подпись. Нормативная формулировка: неподменяемость гарантируется **на CLI-поверхности**
> (флаги `--observed/--match/--exit` удалены, verdict выводится только из наблюдаемого прогона), а
> целостность записанного пруфа — **checksum-уровня**, против случайной/ручной правки. Полная
> неподделываемость требует ключа у оркестратора (сабагент отдаёт `rc`+output, оркестратор проверяет
> и подписывает); там, где оркестратора нет (headless, `/mb drive`), гейт честно деградирует в
> checksum-режим с явной пометкой в state и в выводе — по прецеденту AGR-013. Детали и границы —
> design.md §«Модель доверия eval-пруфа». Рукопожатие с оркестратором в этой ревизии не реализуется.
> Ревизия 6 (2026-07-27, вердикт судьи NO_GO по кругу 4): закрыты три блокера в самом триплете.
> (B1) `status: ready` во frontmatter был **ложным утверждением**, а не преждевременным: батарея C8
> на этой спеке выходила 1, а REQ-015 — приёмочный критерий этой же спеки — требует держать её в
> draft, пока не пройдёт каждая проверка. Строка стояла с создания спеки (`8bac761`) и ни разу не
> пересматривалась; выставлена в `draft`, гейт не ослаблен. (B2) design.md не объявлял ни одного
> незафенсенного блока `**Seams:**` — единственное вхождение было внутри ```-шаблона C9, то есть
> спека показывала форму и не объявляла собственный шов; объявлен реальный блок (§C9). (B3) tasks.md
> предписывал отвергнутый порядок «шаг 7 публикует / C8 на опубликованном draft» — задачи 4 и 5
> приведены к порядку design rev 5 и `commands/sdd.md`: staged C8 (7) → review (8) → промоушен (9).
> REQ-049 на задаче 4 чинится расширением валидатора (AGR-036), а не подменой Eval на `grep`.
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Конвейер sdd — от брифа/контекста до полной спеки

**User Story:** As a user, I want one `/mb sdd` command to take the topic from interview (run if missing) to a fully generated spec with the plan inside, so that `/mb plan` is needed only when I don't want a spec.

#### Acceptance Criteria

- **REQ-001** (event-driven): When `/mb sdd <topic>` runs without an existing `context/<topic>.md`, the system shall run the discuss interview — or self-interview in auto mode — before generating the spec triple. <!-- D-02 -->
- **REQ-002** (event-driven): When `/mb sdd` generates the spec triple, the system shall produce fully populated `requirements.md` (user stories + EARS), `design.md` and `tasks.md` — not scaffolds. <!-- D-03 -->
- **REQ-013** (event-driven): When the spec generator or spec reviewer starts, the system shall read the interview transcript(s) of the topic as mandatory input context. <!-- D-29 -->

### Requirement 2: Контракт-ферст и eval-first

**User Story:** As a user, I want contracts, seams and eval declarations fixed at spec time and materialized red→green at work time, so that code verifies code and tokens are spent on eval code only when work starts.

#### Acceptance Criteria

- **REQ-003** (ubiquitous): The generated `design.md` shall contain a Contract section with interface declarations, agreed test seams and per-task Eval declarations without implementation code. <!-- D-05, D-17 -->
- **REQ-051** (state-driven): While the design phase agrees the test seams, the generated `design.md` shall record a single seam by default and shall record a brief rationale line whenever more than one seam is agreed. <!-- D-17, umbrella REQ-009, аудит D-17-SINGLE-SEAM -->
- **REQ-006** (state-driven): While a requirement carries a SHALL or MUST modal, the generated spec shall include at least one GWT scenario and one Eval declaration covering it. <!-- D-06 -->
- **REQ-007** (unwanted): If a task covering a gated requirement declares `Eval: none`, then spec validation shall fail. <!-- D-25 -->
- **REQ-049** (state-driven): While a task has no runtime surface — documentation or configuration only — the generated spec shall declare a structural Eval whose red is observable before implementation: file presence, section presence or linter exit. <!-- D-25, аудит D-25-STRUCTURAL-EVAL -->
- **REQ-050** (unwanted): If a task declares an Eval waiver instead of a structural Eval, then spec validation shall require a non-empty reason, shall fail when the task covers a gated requirement, and shall list every accepted waiver in its output. <!-- D-25, аудит D-25-STRUCTURAL-EVAL -->
- **REQ-008** (event-driven): When `/mb work` starts a task carrying an Eval declaration, the system shall materialize the eval into executable code first, observe it fail before implementation and pass after. <!-- D-05 -->

### Requirement 3: tasks.md v2 и совместимость

**User Story:** As an engine consumer, I want v2 fields (Stage/Blocked-by/Scope/Eval/Budget) inside the existing task blocks with legacy files parsing unchanged, so that S3/S5 build on the format without breaking old banks.

#### Acceptance Criteria

- **REQ-004** (ubiquitous): The tasks.md v2 format shall support `Stage:`, `Blocked-by:`, `Scope:`, `Eval:` and `Budget:` fields inside existing `<!-- mb-task:N -->` blocks. <!-- S2-A-02 -->
- **REQ-005** (ubiquitous): The task parser shall parse legacy tasks.md files unchanged and emit default values for absent v2 fields. <!-- D-26 -->
- **REQ-052** (unwanted): If the `Blocked-by` graph of a tasks.md contains a cycle, then spec validation shall exit non-zero before the spec is accepted and shall print the complete ordered cycle path. <!-- D-24, ревью S3 SVP-PE-001 -->

### Requirement 4: Бюджеты и размерная эскалация на генерации

**User Story:** As a user, I want oversized specs caught at generation time with clear options, so that no spec enters the roadmap bigger than an agent can execute.

#### Acceptance Criteria

- **REQ-009** (event-driven): When the spec triple is generated, the system shall record the size estimate per task, per stage and per spec against the budgets task ≤120k / stage ≤400k / spec ~1M, measuring the candidate tasks.md that is about to be accepted rather than any previously accepted tasks.md. <!-- D-13, ревью F-007 -->
- **REQ-010** (unwanted): If the spec-level estimate exceeds the budget at generation time, then the system shall stop before writing `specs/<topic>/tasks.md` and escalate with the options: decompose now into grouped specs with their own interviews, cut to MVP with the remainder in the backlog registry, generate a thin umbrella with JIT slices, or record an explicit `budget_override: user` in the frontmatter. <!-- D-35 -->
- **REQ-053** (event-driven): When the generation-time budget gate blocks or the generation is cancelled, the system shall leave any previously accepted `specs/<topic>/tasks.md` byte-identical and shall discard the candidate. <!-- D-35, ревью F-007 -->
- **REQ-011** (state-driven): While in auto mode, on a generation-time budget excess the system shall decompose into self-interviewed slices by default and record the choice as an assumption. <!-- D-35 -->
- **REQ-014** (event-driven): When decomposition happens at sdd time, the system shall assign the child specs to the group and register them in the decomposed-spec registry. <!-- D-31 -->

### Requirement 5: Spec-review другой моделью

**User Story:** As a quality-focused user, I want the generated spec reviewed by a different model configured in the pipeline with me as the judge, so that spec defects are caught before any code exists.

#### Acceptance Criteria

- **REQ-012** (optional): Where pipeline.yaml enables `sdd.spec_review`, the system shall dispatch the configured model to review the generated spec before acceptance, with the human — or the orchestrator in auto mode — as the judge. <!-- D-30 -->

### Requirement 6: Самопроверка генерации через реальных потребителей

**User Story:** As a spec author, I want every generated artifact run through its real consumer before the spec is called ready, so that a validator-green spec can never hide unparseable scenarios, misrouted roles or fake-red evals — the exact failure of the 2026-07-17 group review.

#### Acceptance Criteria

- **REQ-015** (event-driven): When spec generation completes, the system shall run the generation self-check battery — structural validation, scenario-extraction parity against scenario headings, task parsing with role resolution against the roles table, and an Eval preflight — and shall keep the spec in draft status until every check passes. <!-- S2-A-07, review 2026-07-17 -->
- **REQ-054** (state-driven): While the Eval preflight runs, the system shall execute only those Eval commands whose targets already exist — requiring the declared red anchor and rejecting an already-green command — and shall record `eval_status: pending_materialization` for evals whose code is not yet materialized, never counting a missing target or missing tool as an observed red. <!-- D-05, ревью R2-002/R2-009 -->
- **REQ-055** (state-driven): While a task covers a gated requirement, its Eval declaration shall carry an output-matching red anchor, so that a missing target can never be mistaken for the declared red by exit code alone. <!-- C1, измерено 2026-07-17: bats на отсутствующем файле даёт exit 1 -->
- **REQ-056** (state-driven): While the self-check battery runs, the system shall require the outcome its declared phase demands — an observable declared red in the generation phase and an actual green in the done phase — and shall name that phase on its verdict line. <!-- AGR-037; измерено 2026-07-27: реализованная спека давала eval.1…9=invalid при зелёных прогонах, поэтому `ready` был достижим только у ненаписанного кода -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: sdd without context runs the interview
**Covers:** REQ-001

- GIVEN топик без context/<topic>.md
- WHEN `/mb sdd <topic>` вызван интерактивно
- THEN сначала идёт discuss-интервью (план, гейт, триаж — S1), затем генерация; в `--auto` — self-interview с assumptions
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Full generation instead of scaffold
**Covers:** REQ-002, REQ-003

- GIVEN EARS-валидный контекст с 12 REQ
- WHEN конвейер генерирует триплет
- THEN requirements = stories+EARS, design содержит §Contract с seams и Eval-декларациями, tasks.md — исполняемые задачи с v2-полями; ни одного `<!-- hint -->`-плейсхолдера
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Eval none on a gated requirement fails
**Covers:** REQ-007

- GIVEN задача покрывает SHALL-требование и объявляет `Eval: none`
- WHEN mb-spec-validate запускается
- THEN валидация падает с указанием задачи и требования
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Red to green in work
**Covers:** REQ-008

- GIVEN задача с `Eval: bats tests/x.bats — red: contract assertion fails; exit: 1; output~: not ok [0-9]+ red_to_green_contract` (якорь C1 обязателен — «файла нет» red'ом не считается)
- WHEN `/mb work` стартует задачу
- THEN сначала пишется tests/x.bats и наблюдается заявленный red (helper `eval-red` сам гоняет команду и матчит `output~:`); реализация; green; verify через `eval-green` перезапускает команду детерминированно и требует факт. exit 0
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Budget excess at generation time
**Covers:** REQ-010

- GIVEN candidate-tasks.md в `<bank>/tmp/sdd/<topic>/tasks.candidate.md` с оценкой 1.6M токенов
- WHEN конвейер прогоняет бюджетный гейт по candidate
- THEN `specs/<topic>/tasks.md` не создан; пользователю предложены 4 варианта (разбить/MVP/umbrella+JIT/override); выбор фиксируется
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Legacy spec unharmed
**Covers:** REQ-005

- GIVEN tasks.md без v2-полей (например, adapter-parity)
- WHEN mb_work_items.py парсит его
- THEN JSON идентичен прежнему + v2-ключи с дефолтами; mb-spec-validate даёт ноль новых ошибок
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Spec review unavailable is loud
**Covers:** REQ-012

- GIVEN sdd.spec_review.enabled=true, но модель недоступна
- WHEN конвейер доходит до ревью
- THEN шаг помечается SKIPPED loudly, решение остаётся за человеком — никогда молча
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Full v2 task block parses
**Covers:** REQ-004

- GIVEN задача с полями Stage: 2, Blocked-by: 1, svp-interview-upgrade#3, Scope: scripts/*.sh, Eval: pytest tests/pytest/test_x.py — red: v2 fields are absent; exit: 1; output~: FAILED tests/pytest/test_x\.py::test_v2_fields_parsed, Budget: 100000
- WHEN mb_work_items.py парсит блок
- THEN JSON содержит stage=2, blocked_by=["1","svp-interview-upgrade#3"], scope=["scripts/*.sh"], eval{cmd,red,exit,output_re}, budget=100000
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Gated requirement without scenario or eval rejected
**Covers:** REQ-006

- GIVEN спека, где SHALL-требование не имеет ни одного GWT-сценария или ни одной Eval-декларации
- WHEN спека проходит валидацию конвейера
- THEN валидация падает и называет конкретное требование и недостающий слой
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Size sums recorded and consistent
**Covers:** REQ-009

- GIVEN сгенерированный tasks.md с Budget у каждой задачи
- WHEN генерация завершена
- THEN frontmatter tasks.md содержит estimated_tokens.total и estimated_tokens.stages, совпадающие с выводом mb-estimate-check.sh
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Auto overflow decomposes into slices
**Covers:** REQ-011

- GIVEN режим --auto и оценка спеки выше бюджета
- WHEN конвейер достигает гейта D-35
- THEN спека декомпозируется в self-interview слайсы по умолчанию, выбор записан как assumption в контексте
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: Transcripts reach generator and reviewer
**Covers:** REQ-013

- GIVEN топик с interview_transcript в frontmatter контекста
- WHEN стартует генератор или spec-ревьюер
- THEN оба получают путь(и) транскрипта в обязательном входном контексте; отсутствие файла — громкая ошибка
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Child specs join the group and registry
**Covers:** REQ-014

- GIVEN декомпозиция на sdd-этапе породила два child-топика
- WHEN child-триплеты записаны
- THEN каждый несёт group и parent_context во frontmatter, а оркестратор добавил `[SPEC:<group>]`-записи в реестр через mb-idea.sh
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Battery catches a markerless scenario section
**Covers:** REQ-015

- GIVEN сгенерированная спека с заголовками `### Scenario:` без `<!-- mb-scenario:N -->`-маркеров
- WHEN выполняется батарея самопроверки
- THEN проверка паритета извлечения падает (0 извлечено при N заголовков), спека остаётся draft
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Docs task without runtime surface gets a structural eval
**Covers:** REQ-049

- GIVEN задача правит только `docs/*.md` и не имеет runtime-поверхности
- WHEN конвейер генерирует её блок задачи
- THEN блок несёт структурный Eval (наличие файла / наличие секции / exit линтера) с red-якорем, наблюдаемым до реализации; `Eval: none` в таком блоке не появляется
<!-- /mb-scenario:15 -->

<!-- mb-scenario:16 -->
### Scenario: Waiver is an explicit exception, never a silent substitute
**Covers:** REQ-050

- GIVEN две задачи с waiver: одна non-gated с причиной, вторая покрывает SHALL-требование
- WHEN mb-spec-validate запускается
- THEN gated-waiver отклонён с указанием задачи и требования; non-gated waiver принят и перечислен в выводе; waiver с пустой причиной отклонён
<!-- /mb-scenario:16 -->

<!-- mb-scenario:17 -->
### Scenario: Multiple seams demand a rationale
**Covers:** REQ-051

- GIVEN design.md, где §Contract объявляет два seam-элемента
- WHEN mb-spec-validate проверяет seam-блок
- THEN отсутствие строки `**Seam rationale:**` валит валидацию; с непустым rationale — проходит; один seam проходит без rationale
<!-- /mb-scenario:17 -->

<!-- mb-scenario:18 -->
### Scenario: Blocked-by cycle fails validation with the path
**Covers:** REQ-052

- GIVEN tasks.md, где задача 2 блокируется 3, а 3 — 2 (и вторая фикстура — self-cycle 1 → 1)
- WHEN mb-spec-validate запускается до принятия спеки
- THEN exit non-zero и напечатан полный упорядоченный путь цикла (`2 -> 3 -> 2`)
<!-- /mb-scenario:18 -->

<!-- mb-scenario:19 -->
### Scenario: Blocked gate leaves the accepted tasks.md untouched
**Covers:** REQ-053

- GIVEN спека с уже принятым `specs/<topic>/tasks.md` и новым candidate, который валит бюджетный гейт
- WHEN гейт возвращает over и пользователь не выбирает override
- THEN принятый tasks.md остаётся byte-identical, candidate удалён, отчёт — `sdd_status=blocked`
<!-- /mb-scenario:19 -->

<!-- mb-scenario:20 -->
### Scenario: Preflight separates pending materialization from fake red
**Covers:** REQ-054

- GIVEN три задачи: у первой target-файл Eval отсутствует, у второй существует и команда уже зелёная, у третьей существует и падает с заявленным red-якорем
- WHEN выполняется Eval-preflight батареи
- THEN первая → `pending_materialization` (не observed red), вторая → `invalid` и блокирует ready, третья → `ready`
<!-- /mb-scenario:20 -->

<!-- mb-scenario:21 -->
### Scenario: Exit-only anchor is rejected on a gated bats eval
**Covers:** REQ-055

- GIVEN gated-задача с `Eval: bats tests/bats/test_x.bats — red: ...; exit: 1` без `output~:`
- WHEN mb-spec-validate проверяет Eval-декларации
- THEN валидация падает: `bats` на отсутствующем файле возвращает тот же exit 1, что и настоящий провал, поэтому exit-only якорь не отличает посторонний сбой от заявленного red
<!-- /mb-scenario:21 -->

<!-- mb-scenario:22 -->
### Scenario: The same green eval passes done and fails generation
**Covers:** REQ-056

- GIVEN реализованная задача, чей Eval сейчас зелёный (target существует, команда даёт exit 0)
- WHEN батарея выполняется дважды — `--phase done` и `--phase generation`
- THEN в done → `eval.N=ready` и `self_check=ready phase=done`; в generation → `eval.N=invalid` с `reason=already_green`; обе строки вердикта несут свою фазу, поэтому один и тот же `invalid` нельзя прочитать, не зная, чего от прогона требовали
<!-- /mb-scenario:22 -->
