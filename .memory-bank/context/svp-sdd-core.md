---
topic: svp-sdd-core
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-sdd-core-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-001, REQ-002, REQ-003, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-016, REQ-022, REQ-035, REQ-039, REQ-047, REQ-048]
---

# Context: svp-sdd-core (слайс S2, ICE 400)

Ядро вижена: `/mb sdd` как единый конвейер (интервью при отсутствии context → полная генерация requirements/design/tasks с планом внутри), формат tasks.md v2 (Stage/Blocked-by/Scope/Eval/Budget), §Contract+seams в design, eval-first исполнение в work, размерная эскалация на генерации (D-35), spec-review другой моделью. Родительские решения: D-02/03/05/06/13/17/25/26/29/30/35.

## Research Digest

- `commands/sdd.md:137` — «does not auto-generate content» — целевая точка замены.
- `scripts/mb-sdd.sh`, `scripts/mb_work_items.py` — скаффолд и парсер задач (расширяются backward-compatible).
- `commands/work.md:339-460` — implement→verify→review→judge петля: точка врезки eval-first шага (материализация Eval, red→green).
- `scripts/mb-spec-validate.sh` — точка добавления проверок v2-полей и Eval-гейтов (REQ-008 umbrella: Eval:none на gated → fail).
- S1 контракты C1 (mb-estimate-check.sh) и C2 (interview-plan) — S2 переиспользует C1 для spec-triple оценки.
- `specs/sdd-openspec-parity/requirements.md` — scenario-гейты/SHOULD-MAY модалы уже там (D-01, не дублировать).
- Паттерн spec-review: `agents/codex-reviewer`-подход (health-check, SKIPPED loudly) + review-контракт JSON из `commands/work.md:411-435`.

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S2-A-01**: Конвейер реализуется в `commands/sdd.md` (prompt-оркестрация) + расширение `mb-sdd.sh`; без переписывания на Python.
- **S2-A-02**: tasks.md v2 — новые bold-поля (`Stage:`, `Blocked-by:`, `Scope:`, `Eval:`, `Budget:`) внутри существующих `<!-- mb-task:N -->` блоков; маркеры не меняются; `mb_work_items.py` расширяется backward-compatible (легаси без полей → дефолты в JSON).
- **S2-A-03**: `sdd.spec_review` в pipeline.yaml: `{enabled: false, agent, model, thinking}`; вердикт — строгий JSON (APPROVED/CHANGES_REQUESTED + issues); судья — человек, в auto — оркестратор.
- **S2-A-04**: Бюджет-валидация spec-triple — расширение `mb-estimate-check.sh` (из S1), не отдельный скрипт.
- **S2-A-05**: Оценка самого S2 ~700–900k — в бюджете, слайс не разбивается.
- **S2-A-06**: Размерная эскалация D-35 реализуется в sdd-конвейере (варианты: разбить сейчас / MVP-урезка / umbrella+JIT / override во frontmatter; auto — self-interview слайсы).

## Functional Requirements (EARS)

- **REQ-001** (event-driven): When `/mb sdd <topic>` runs without an existing `context/<topic>.md`, the system shall run the discuss interview — or self-interview in auto mode — before generating the spec triple. <!-- D-02 -->
- **REQ-002** (event-driven): When `/mb sdd` generates the spec triple, the system shall produce fully populated `requirements.md` (user stories + EARS), `design.md` and `tasks.md` — not scaffolds. <!-- D-03 -->
- **REQ-003** (ubiquitous): The generated `design.md` shall contain a Contract section with interface declarations, agreed test seams and per-task Eval declarations without implementation code. <!-- D-05, D-17 -->
- **REQ-004** (ubiquitous): The tasks.md v2 format shall support `Stage:`, `Blocked-by:`, `Scope:`, `Eval:` and `Budget:` fields inside existing `<!-- mb-task:N -->` blocks. <!-- D-03, S2-A-02 -->
- **REQ-005** (ubiquitous): The task parser shall parse legacy tasks.md files unchanged and emit default values for absent v2 fields. <!-- D-26 -->
- **REQ-006** (state-driven): While a requirement carries a SHALL or MUST modal, the generated spec shall include at least one GWT scenario and one Eval declaration covering it. <!-- D-06 -->
- **REQ-007** (unwanted): If a task covering a gated requirement declares `Eval: none`, then spec validation shall fail. <!-- D-25 -->
- **REQ-008** (event-driven): When `/mb work` starts a task carrying an Eval declaration, the system shall materialize the eval into executable code first, observe it fail before implementation and pass after. <!-- D-05 -->
- **REQ-009** (event-driven): When the spec triple is generated, the system shall record the size estimate per task, per stage and per spec against the budgets task ≤120k / stage ≤400k / spec ~1M. <!-- D-13 -->
- **REQ-010** (unwanted): If the spec-level estimate exceeds the budget at generation time, then the system shall stop before writing tasks.md and escalate with the options: decompose now into grouped specs with their own interviews, cut to MVP with the remainder in the backlog registry, generate a thin umbrella with JIT slices, or record an explicit `budget_override: user` in the frontmatter. <!-- D-35 -->
- **REQ-011** (state-driven): While in auto mode, on a generation-time budget excess the system shall decompose into self-interviewed slices by default and record the choice as an assumption. <!-- D-35 -->
- **REQ-012** (optional): Where pipeline.yaml enables `sdd.spec_review`, the system shall dispatch the configured model to review the generated spec before acceptance, with the human — or the orchestrator in auto mode — as the judge. <!-- D-30 -->
- **REQ-013** (event-driven): When the spec generator or spec reviewer starts, the system shall read the interview transcript(s) of the topic as mandatory input context. <!-- D-29 -->
- **REQ-014** (event-driven): When decomposition happens at sdd time, the system shall assign the child specs to the group and register them in the decomposed-spec registry. <!-- D-31 -->

## Non-Functional Requirements

- **NFR-001**: Токен-экономия — генерация не пишет код эвалов (декларации only, D-05); spec_review off по умолчанию.
- **NFR-002**: Детерминизм — v2-поля, Eval-гейты и бюджеты проверяет mb-spec-validate/estimate-check, не LLM.
- **NFR-003**: Обратная совместимость — легаси-спеки валидны без изменений; поведение старого `/mb sdd`-скаффолда доступно как `--scaffold-only`.
- **NFR-004**: Изменённые shell-входы работают под Bash 3.2 (macOS) и текущим Bash (Linux); пути с пробелами и не-C локаль остаются валидными. <!-- ревью 2026-07-17, F-013 -->

## Revision 2 (2026-07-17, spec-ревью группы)

Закрыты F-001…F-013: грамматики Scope/Blocked-by зафиксированы в design C1 (open question снят —
S3/S5/S8 потребляют готовый контракт); red в eval-first обязателен (FAIL, не warning); добавлены
REQ-015 + батарея самопроверки генерации (C8) — каждый артефакт прогоняется через реального
потребителя (validate, scenario-паритет, роль-резолюция, red-прогон эвалов) до `status: ready`;
T4 разбит на три задачи (конвейер / D-35+реестр / scaffold-совместимость), все задачи несут
v2-поля и бюджеты (Stage-суммы ≤ 400k).

## Revision 3 (2026-07-17, круг 2 spec-ревью группы + смысловой аудит)

Закрыты F-007/F-009/F-010 и R2-001…003:

- **F-007 (critical, порядок стадий)**: бюджетный гейт не мог сработать «до записи tasks.md», потому
  что бюджеты живут в самих задачах, а C3 читал только принятый файл. Введён **candidate**:
  оркестратор пишет `<bank>/tmp/sdd/<topic>/tasks.candidate.md`, C3 получает режим `--tasks-file`
  (взаимоисключающий с `--spec`; принятый tasks.md на оценку не влияет), и только после гейта
  candidate атомарно переносится в `specs/<topic>/tasks.md`. Путь выбран не произвольно:
  `mb_work_items.py::_derive_topic` берёт `path.parent.name`, а `<bank>/tmp` лежит на одной ФС с
  `<bank>/specs` (атомарный `rename`). Новый REQ-053 фиксирует byte-identity принятого файла при
  blocked/cancel.
- **F-009 (spec-review)**: у exit-кодов 0/1/2 не было исполнителя, а `<topic>.json` противоречил
  umbrella NFR-005. Появился `scripts/mb-sdd-review-result.sh` (`check` — same_model до диспатча;
  `record` — валидация схемы + append-only JSONL `<topic>.jsonl` с `ts`/`attempt`). Конфиг —
  инлайн-мапа: проверено, что `parse_simple_mapping`/`parse_inline_map` и PyYAML дают идентичный
  результат, а вложенный блок в fallback'е вернул бы `None`.
- **F-010 (eval в work-state)**: `mb-work-state.sh` не имеет ни поля `eval`, ни подходящей
  субкоманды. Добавлены `eval-red`/`eval-green` в тот же авторитетный writer (прямое редактирование
  JSON запрещено), Scope T8 расширен скриптом и вторым bats-файлом, добавлена регрессия старых
  субкоманд.
- **R2-002 (фальшивый red)**: D-05 откладывает eval-код до `/mb work`, поэтому «команда красная,
  потому что файла нет» — не доказательство. C8 п.4 переписан в **preflight**: структурная часть в
  валидаторе; поведенческая — исполняются только эвалы с существующими target (уже-зелёный или
  несовпавший red → `invalid`), остальные → `pending_materialization`. Behavioral red остаётся
  обязательным гейтом C6. Чтобы `red_match` считался кодом, C1 получил red-якоря (`exit:` /
  `output~:`, ≥1 обязателен на gated) — иначе «посторонний сбой не принимается» остаётся прозой.
- **R2-001 / R2-003**: C1 нормативно запрещает потребителям сужать Scope-грамматику (правка на
  стороне S3 — cross-slice request X-01); устаревшие open questions вычищены.
- **Смысловой аудит**: REQ-049 (структурный Eval обязателен для docs/config-задач — вторая половина
  D-25, которая раньше отсутствовала), REQ-050 (waiver — явное исключение с причиной, non-gated
  only, перечисляется в выводе), REQ-051 + C9 (один seam по умолчанию, rationale при ≥2 —
  синхронно с umbrella REQ-009), REQ-052 (цикл `Blocked-by` валит spec-валидацию — запрос ревью S3).
- Бюджеты подняты под добавленную работу: Stage 1 = 310k, Stage 2 = 320k, Stage 3 = 220k, итого
  850k (`spec=ok`, < 900k). T2 = 120k — на потолке задачи; риск и реакция (дет-гард D-16/ADaPT)
  названы в design §Risks.
- **Namespace**: локальные REQ-049…055 выданы `mb-req-next-id.sh --spec svp-sdd-core` и НЕ равны
  umbrella REQ-049…055 (те принадлежат S8/S1) — нумерация per-spec-local, traceability ключует по
  `(spec, req_id)`.

## Revision 4 (2026-07-18, круг 3 codex-ревью)

Закрыты 9 находок (1 critical, 6 major, 1 minor, 1 nit):

- **F-010 (critical)**: red/green work-state больше не подменяется флагами. `eval-red`/`eval-green`
  (C6) сами запускают byte-identical `--cmd-file`, сами захватывают exit+output и судят red/green;
  caller-флаги `--exit`/`--observed`/`--match` удалены; тест обязан доказать невозможность подмены.
- **R3-001 (major)**: поведенческий Eval-preflight (REQ-054) вынесен из prompt-текста T4 в
  детерминированный `mb-sdd-self-check.sh` (C8a, новая **Task 9**, Stage 1, 90k). REQ-054 снят с T8
  (там work-time state) и трассируется на Task 9; T4 `Blocked-by 1,2,3,9` и вызывает helper.
- **R3-002/R3-003 (major)**: candidate lifecycle вынесен в `mb-sdd-candidate.sh` (C4a, Scope T5);
  `budget_override: user` сужен — снимает ТОЛЬКО `spec=over`, при task/stage-overflow всегда blocked
  (hard-лимиты D-13 нерушимы). Четыре override-матрицы в Testing T5.
- **R3-004 (major)**: C1 — «любой POSIX glob» заменён на **restricted glob** (литералы + `*` в
  сегменте + сегмент `**`); `?`/`[]`/`{}`/escape/запятая-в-элементе → malformed exit 2; пять
  негативных кейсов в T1/T2; синхронный запрос S3 (X-01).
- **R3-005 (major)**: REQ-022 (цикл → spec-валидация) добавлен в `covers_umbrella` (спека + ledger)
  как spec-time рубеж; S3 сохраняет runtime рубеж; umbrella-сторона — X-04.
- **R3-006 (major)**: status state machine draft→ready (C7): публикация в `specs/` = draft, ready
  только при C8=pass И (review off | APPROVED | явное решение по SKIPPED/issues); тестируется в T7.
- **R3-007 (minor)**: примеры Eval в Scenario 4/8 приведены к якорям C1 (`output~:` + `exit:`),
  «red: файла нет» убрано.
- **R3-008 (nit)**: namespace-диапазон 049…055 везде.
- Бюджеты: Stage 1 = 400k (добавлен T9), Stage 2 = 330k (T5 110→120k), Stage 3 = 220k; итого 950k
  (`spec=near`, advisory — <1M, не блокирует).

## Constraints

- REQ-ID/mb-task не перенумеровываются; scenario-гейты и модалы SHOULD/MAY — собственность sdd-openspec-parity (D-01).
- Судья spec-review — человек/оркестратор; нового judge-агента не заводить (D-30).
- `mb_work_items.py` — единственный парсер задач (не форкать).

## Edge Cases & Failure Modes

- Контекст есть, но status: draft — конвейер предлагает дорезюмить интервью, не генерирует по черновику молча.
- Блокер-цикл в сгенерированном tasks.md — self-check конвейера до записи (граф-проверка), затем spec-validate как вторая линия.
- Оценка на грани бюджета (0.9–1.1M) — эскалация с пометкой погрешности.
- spec_review модель недоступна — SKIPPED loudly, человек решает (паттерн codex-reviewer).
- Легаси-спека прогоняется новым validate — ноль новых ошибок (негативные тесты).

## Out of Scope

- Runtime параллель/claims (S3); ADaPT-гарды исполнения (S5); интервью-механика (S1); рендер групп (S4).

## Open Questions

— (закрыты ревизией 2: legacy-флаг — `--scaffold-only` по C7; Scope — POSIX-glob грамматика C1,
потребляется S3/S5/S8 без ревизии. Ревизия 3 добавила в C1 семантику пересечения Scope-списков и
red-якоря Eval; точка записи tasks.md закрыта candidate-порядком.)
