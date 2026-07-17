---
topic: svp-brief
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-brief-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-045, REQ-046]
blocked_by: [svp-interview-upgrade]
---

# Context: svp-brief (слайс S7, ICE 448, blocked by S1)

Команда `/mb brief <topic>` — пре-discuss формализация запроса: свободный запрос + любые документы → одностраничник (1P Авито / бриф 2ГИС / Amazon PR-FAQ) в специализированной папке с исходниками, хендоф в `/mb discuss`. Родительское решение: D-34.

## Research Digest

- D-34 + формулировка пользователя — `context/sdd-vision-pipeline-interview.md` (2026-07-17).
- inputs-registry уже специфицирован в `specs/sdd-openspec-parity/requirements.md` («canonical copies of external input artifacts (PRD, JTBD…)», Sources: S-NN) — конвенция переиспользуется (D-01), но `briefs/<topic>/inputs/` НЕ заменяет её: canonical copy для spec-стадии остаётся в `specs/<topic>/inputs/` (design.md Risks, BRIEF-007).
- Phase 0 discuss (`commands/discuss.md:26-35`) — точка встраивания чтения брифа.
- Роутер `/mb` (`commands/mb.md` § Routing) — точка регистрации новой команды.
- `/mb brief` C0-контракт зафиксирован в umbrella `specs/sdd-vision-pipeline/design.md` § Interfaces #7; здесь не переопределяется, только детализируется (`design.md` C0).
- Secret-scan CLI `scripts/mb-secret-scan.sh` — **канонический диспетчер S1** (`specs/svp-interview-upgrade/design.md` § C5): S1 создаёт файл, диспетчер `--policy` и политику `transcript`; **политику `brief-input` реализует этот слайс** в том же файле, вызов — `scripts/mb-secret-scan.sh --policy brief-input <source-path>`. Общие элементы (stdout, метки `email`/`api_key`, порядок находок, exit 0/1/2, `scan=unsupported`) фиксирует S1 и S7 их не переопределяет; exit 2 у S1 уже есть — S7 его не «добавляет». `sdd-openspec-parity` этим CLI не владеет (единственная связь — общий источник паттернов `scripts/mb-import.py`). Ревизия 3, находка SVP-BRIEF-002.
- Prompt-контракт `commands/brief.md` проверяется харнессом S1-C9 (`tests/bats/lib/discuss_contract.bash`) — второй prompt-checker слайс не заводит (`design.md` C7).

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S7-A-01**: Папка — `.memory-bank/briefs/<topic>/`: `brief.md` + `inputs/` с копиями приложенных исходников (конвенция inputs-registry).
- **S7-A-02**: Секции одностраничника: Суть / Цель+Импакт / Референсы / Решение (JTBD) / Сценарии / Ограничения / UX / Критерии готовности / Приложения.
- **S7-A-03**: Лёгкие вопросы — максимум 3–5, только если непонятны суть или цель; иначе бриф генерируется без вопросов.
- **S7-A-04**: `/mb discuss` при наличии брифа топика автоматически читает его (и inputs/) в Phase 0.

## Functional Requirements (EARS)

- **REQ-001** (event-driven): When `/mb brief <topic>` runs, the system shall create `briefs/<topic>/` containing `brief.md` and an `inputs/` folder with copies of the attached source documents. <!-- S7-A-01 -->
- **REQ-002** (ubiquitous): The generated `brief.md` shall contain the sections Essence, Goal & Impact, References, Solution (JTBD), Scenarios, Constraints, UX, Done Criteria and Attachments. <!-- S7-A-02 -->
- **REQ-003** (unwanted): If the essence or the goal of the request remains unclear after analyzing the inputs and `--auto` is not selected, then the system shall ask up to five light clarifying questions before generating the brief. <!-- S7-A-03; ревизия круга 3 R3-001: исключение `--auto` внесено в саму формулировку (Scenario 7 и C0 не противоречат REQ-003 более) -->
- **REQ-004** (state-driven): While the intent is clear from the request and inputs, or `--auto` is selected, the system shall generate the brief without asking questions; when `--auto` bypasses an otherwise-unclear intent, the brief shall carry a non-empty `assumptions_note`. <!-- S7-A-03; R3-001 -->
- **REQ-005** (event-driven): When the brief is written, the system shall offer to proceed to `/mb discuss` seeded by the brief. <!-- umbrella REQ-046 -->
- **REQ-006** (event-driven): When `/mb discuss` runs for a topic with an existing brief, the system shall read `brief.md` and its inputs during Phase 0. <!-- S7-A-04 -->
- **REQ-007** (ubiquitous): The system shall validate the brief structure — required sections present — by script. <!-- D-14 determinism -->
- **REQ-008** (event-driven): When source documents are attached, the system shall list them in the Attachments section with relative links into `inputs/`. <!-- S7-A-01 -->
- **REQ-009** (unwanted): If a secret-scan finds a credential in a source before it is copied into `inputs/`, then the system shall refuse to copy that source and report the finding instead, until the secret is removed or redacted in the source itself or the offending line carries an explicit `<!-- mb-secret-ok -->` pragma. <!-- BRIEF-001 -->
- **REQ-010** (unwanted): If a source cannot be scanned because it is unreadable, binary, or of an unsupported type, then the system shall abort before any destination mutation, print `brief=blocked reason=scan_unsupported` on stdout, name every unscannable source with its reason on stderr, and require a fresh invocation after that source is removed, converted, or excluded — an unsupported source shall never be copied in MVP and no override flag shall exist. <!-- BRIEF-001, SVP-BRIEF-001 -->

## Non-Functional Requirements

- **NFR-001**: Target 60–100 строк. 101–120 строк допустимы без ошибки; >120 строк вызывает
  детерминированный `warning=oversize`, но не делает структурно валидный brief invalid. <!-- BRIEF-008 -->
- **NFR-002**: Детерминизм — структура brief.md проверяется скриптом.

## Constraints

- Не дублировать inputs-registry sdd-openspec-parity — та же конвенция хранения исходников (D-01);
  `briefs/<topic>/inputs/` canonical только для brief-стадии, spec-стадия сохраняет свою canonical
  copy в `specs/<topic>/inputs/` без изменений (BRIEF-007).
- Бриф не заменяет discuss: never пропускать интервью на его основании автоматически.
- Secret-scan (C5) выполняется до любой мутации `briefs/<topic>/`; `<private>` не считается способом
  разблокировать git-запись — он защищает только `index.json`/`mb-search` (rules/RULES.md, caveat
  `<private>`), не git diff/commit (BRIEF-001).

## Edge Cases & Failure Modes

- Запрос без документов — бриф из одного промта (inputs/ пустая, тело Attachments ровно `- None`).
- **Инспектируемость типов — контракт S1-C5, не S7** (ревизия круга 3, R3-005): по действующему
  S1-C5 бинарный/нечитаемый/неподдерживаемый тип → `scan=unsupported`, exit 2, поэтому бинарный
  контейнер (PDF/DOCX) в MVP НЕ копируется тихо — он даёт `brief=blocked reason=scan_unsupported`.
  Сканируемым остаётся читаемый UTF-8-текст; Scenario 1 использует `PRD.md`, а не `PRD.pdf`. Точную
  формулировку «readable regular file без NUL, декодируемый как UTF-8» запрошено зафиксировать у S1-C5
  (cross-slice X-03); прежнее «бинарные PDF, которые сканер прочитает, копируются» — снято как
  противоречие владельцу.
- Файл, который сканер не может прочитать (нечитаемый/неподдерживаемый тип, exit 2) — `/mb brief`
  громко прерывается (`brief=blocked reason=scan_unsupported`, exit 1) до любой мутации destination;
  override-флага нет в MVP: допустимые продолжения — удалить/конвертировать/исключить источник и
  вызвать команду заново (REQ-010, SVP-BRIEF-001).
- Повторный `/mb brief <topic>` — `brief=blocked reason=exists`, exit 1, без единой записи. **Флага
  `--update` нет**: update/версионирование — вне MVP; повторная формализация — на новом топике либо
  после ручного удаления каталога пользователем (BRIEF-003, R2-001).
- Секрет в исходнике — до создания `briefs/<topic>/` каждый источник проходит secret-scan
  (`scripts/mb-secret-scan.sh --policy brief-input`, C5; владелец CLI — S1); находка (exit 1) даёт
  `brief=blocked reason=secret` и блокирует копирование до удаления/редакции секрета в самом
  источнике или прагмы `<!-- mb-secret-ok -->` на строке-находке; `<private>` НЕ разблокирует
  git-запись (REQ-009, BRIEF-001).
- Готовый текст брифа пишется prompt-слоем в кандидата `<bank>/tmp/brief-<topic>.candidate.md` и
  публикуется только helper'ом `scripts/mb-brief.sh create --candidate …`; при отказе кандидат
  сохраняется (чинить нужно источник, а не бриф), destination не создаётся (design C6, R2-001).

## Out of Scope

- Автогенерация PRD/tech-req из брифа; экспорт во внешние трекеры; глубокое интервью (S1).

## Open Questions

- Нужен ли отдельный флаг `--no-analyze` для брифа из готового документа без LLM-анализа (не путать
  с `--request-file` из C0, который лишь меняет источник текста запроса — анализ всё равно
  выполняется) — blocked on: первый реальный прогон.
