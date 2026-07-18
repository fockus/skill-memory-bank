# Tasks: svp-brief

> Слайс S7 (ICE 448, blocked by S1 `svp-interview-upgrade` — Task 1 потребляет диспетчер secret-scan
> S1-C5 и реализует в нём политику `brief-input`, `design.md` § C5). Eval материализуется первым
> (red), затем реализация (green) — D-05.
> Ревизия 3 (2026-07-17): порядок исправлен на **2 → 1 → 3 → 4** (валидатор C1 нужен Task 1 до
> публикации — R2-002); Task 1 получил политику `brief-input` в Scope (SVP-BRIEF-002) и
> candidate-порядок «генерация → helper» (R2-001); Task 4 сменил grep-эвал на структурный bats
> (R2-003); все `Eval:`-строки несут якоря S2-C1 (`output~:` обязателен — все четыре задачи gated).
> Внешние блокеры Task 1: `svp-interview-upgrade#4` создаёт `scripts/mb-secret-scan.sh` и диспетчер
> `--policy` (до этого `--policy brief-input` — usage error `policy_not_implemented`, S1-C5);
> `svp-interview-upgrade#1` создаёт харнесс C9 `tests/bats/lib/discuss_contract.bash`, которым
> проверяются клаузы `commands/brief.md` (design C7).
> Red-условия описывают состояние **после** материализации теста: `bats <missing>` даёт exit 1 +
> `not ok 1 bats-gather-tests` — тот же код, что настоящий провал, поэтому red доказывает якорь
> `output~:` по имени теста, а не exit (S2-C1/C6, umbrella Interface 1).
> Prompt-клаузы проверяются ТОЛЬКО через харнесс S1-C9 (`design.md` C7): `assert_clause` +
> `assert_clause_load_bearing`; голый `grep -q <слово>` запрещён как assertion-гейт.
> Имена bats-тестов — ASCII, несут токены из якорей `output~:`. Роли — bare (парсер добавляет `mb-` сам).
> Бюджеты: Stage 1 = 175000, Stage 2 = 110000; итого 285000 (≤ 1000000 spec / ≤ 400000 stage / ≤ 120000 task).

<!-- mb-task:2 -->
## Task 2: mb-brief-validate.sh

**Stage:** 1
**Covers:** REQ-007
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb-brief-validate.sh, tests/bats/test_mb_brief_validate.bats, tests/bats/fixtures/brief/**
**Budget:** 60000

**What to do:**
- `scripts/mb-brief-validate.sh` по контракту C1: ровно 9 обязательных H2-секций (точное написание,
  без дублей); frontmatter — закрытый набор ключей (`topic`/`created`/`status`/`inputs` обязательны,
  `assumptions_note` опционален и непуст, любой другой ключ → нарушение); непустые Essence/Goal &
  Impact; stdout — ровно одна строка `brief=ok|brief=invalid`; stderr — детерминированный порядок
  диагностик (агрегатный `error=frontmatter_invalid section=frontmatter fields=<…>` → секционные
  `error=<code> section=<name>` в каноническом порядке девяти секций → `warning=oversize` последней);
  exit 0/1/2; `error=usage` и `error=io path=<path>` — ровно по одной строке, без stdout (NFR-001,
  SVP-BRIEF-004).

**Eval:** `bats tests/bats/test_mb_brief_validate.bats` — red: bats-файл материализован, `scripts/mb-brief-validate.sh` не существует, каждый именованный кейс `brief_validate: …` падает; exit: 1; output~: `not ok [0-9]+ brief_validate: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь, X-05)**: каждый bats-тест в `test_mb_brief_validate.bats`
  начинается с положительного family-префикса `brief_validate: ` (ровно как S2-T5 `candidate_publish:`),
  поэтому `bats <missing>` → `not ok 1 bats-gather-tests` якорю не матчится, а любой настоящий провал
  именованного кейса — матчится.
- `tests/bats/test_mb_brief_validate.bats` ДО скрипта, имена ASCII: `brief_validate: ok`
  (валидная фикстура → stdout ровно `brief=ok`, stderr пуст, exit 0); `brief_validate: missing-section`
  (нет `## UX` → `brief=invalid` + `error=missing_section section=UX`, exit 1 — Scenario 6);
  `brief_validate: duplicate-section`; `brief_validate: empty-essence`; `brief_validate: empty-goal`;
  `brief_validate: frontmatter-invalid` (несколько битых полей → **ровно одна** агрегатная строка с
  `fields=` в порядке набора C1); `brief_validate: frontmatter-unknown-key`;
  `brief_validate: assumptions-note-empty` (ключ есть, значение пустое → `frontmatter_invalid`);
  **`brief_validate: diagnostics-order`** — фикстура с одновременными нарушениями frontmatter,
  missing_section, duplicate_section и empty_essence: тест сверяет **полный** stdout и **полный**
  stderr построчно (агрегат → секции в каноническом порядке → внутри секции missing/duplicate перед
  empty_*), а не наличие подстрок; `brief_validate: oversize-warning` (>120 строк при валидной
  структуре → `brief=ok` + `warning=oversize lines=<N> limit=120` последней строкой, exit 0);
  `brief_validate: oversize-within-limit` (101–120 строк → без warning); `brief_validate: usage`
  (0/2 аргумента, несуществующий путь, директория → stdout пуст, stderr ровно `error=usage`, exit 2);
  `brief_validate: io` (существующий нечитаемый файл → stdout пуст, stderr ровно `error=io path=<p>`,
  exit 2).
- shellcheck clean; portability — Bash 3.2 (macOS) и Linux, путь банка с пробелами.

**DoD:**
- [ ] `scripts/mb-brief-validate.sh` реализован по C1 (закрытый frontmatter, порядок диагностик, exit 0/1/2, oversize-warning)
- [ ] `brief_validate: diagnostics-order` сверяет полный stdout+stderr комбинированной фикстуры построчно
- [ ] bats green (был red по заявленному якорю); shellcheck clean
<!-- /mb-task:2 -->

<!-- mb-task:1 -->
## Task 1: Политика brief-input + helper mb-brief.sh + команда /mb brief + шаблон

**Stage:** 1
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-005, REQ-008, REQ-009, REQ-010
**Role:** developer
**Blocked-by:** 2, svp-interview-upgrade#1, svp-interview-upgrade#4
**Scope:** commands/brief.md, scripts/mb-brief.sh, scripts/mb-secret-scan.sh, references/templates.md, tests/bats/test_mb_brief_command.bats, tests/bats/test_mb_secret_scan_brief_input.bats, tests/bats/fixtures/brief/**
**Budget:** 115000

**What to do:**
- Реализовать политику `brief-input` в созданном S1 `scripts/mb-secret-scan.sh` (диспетчер и общий
  контракт — S1-C5, здесь **не** переопределяются): `<private>` находку не подавляет;
  `<!-- mb-secret-ok -->` на строке-находке или строке непосредственно над ней подавляет только эту
  находку; бинарный/нечитаемый/неподдерживаемый тип → `scan=unsupported`, exit 2; паттерны и метки
  (`email`/`api_key`) — те же, single-source из `scripts/mb-import.py`.
- `scripts/mb-brief.sh create|context` по C6. `create --mb <bank> --topic <topic> --candidate <path>
  [--input <path>]… [--auto]` строго в порядке шагов C6: usage-проверки (topic-паттерн, кандидат —
  существующий читаемый regular file, `--input` regular-file/symlink/`..`, `error=basename_collision`)
  → **bootstrap корней `<bank>/tmp/`+`<bank>/briefs/` и exists-гейт под publish-мьютексом**
  `<bank>/tmp/.brief-<topic>.lock` (проверка `briefs/<topic>` как файл/каталог/symlink →
  `brief=blocked reason=exists`; мьютекс снимается `trap`'ом) → **вызов уже реализованного
  `scripts/mb-brief-validate.sh` (Task 2) над кандидатом** → сверка `--auto`/`assumptions_note` →
  сверка инварианта inputs (C2, каноническая грамматика Attachments — percent-encoded ссылки/`- None`)
  → **secret-scan C5 по всем `--input` с агрегацией R3-006** (приоритет usage→unsupported→blocked→clean,
  диагностика всех non-clean источников) → staging в `<bank>/tmp/` → одиночный атомарный `mv` в
  `briefs/<topic>/` под тем же мьютексом (destination гарантированно не существует ⇒ не вложение) →
  stdout `brief=created path=briefs/<topic>/brief.md`, exit 0. **Правило отказа (R3-007):**
  usage/I-O-ошибки шага 1 печатают только `error=…` и **не** печатают `candidate=`; отказы шагов 2–8
  после принятия кандидата сохраняют его, удаляют staging и печатают `candidate=<path>` **последней**
  строкой stderr; на success кандидат удаляется после `mv`.
  `context --mb <bank> --topic <topic>` — манифест `brief=absent` | `brief=present` + `brief_path=` +
  `input_path=` в порядке `LC_ALL=C`, тело брифа не печатается.
- `commands/brief.md` (prompt-слой) в порядке R2-001: анализ запроса+вложений → лёгкие вопросы
  (≤5, только суть/цель — REQ-003/004; под `--auto` гейт пропускается и во frontmatter пишется
  непустой `assumptions_note`) → **генерация полного текста брифа (все девять секций + Attachments
  со ссылками `inputs/<basename>`, REQ-002/008) в кандидата `<bank>/tmp/brief-<topic>.candidate.md`**
  → вызов `scripts/mb-brief.sh create --candidate …` (единственный путь публикации; прямая запись в
  `briefs/` запрещена) → финальная строка `/mb discuss <topic>` (REQ-005).
- Шаблон одностраничника (9 секций + frontmatter C1) → `references/templates.md`.

**Eval:** `bats tests/bats/test_mb_secret_scan_brief_input.bats tests/bats/test_mb_brief_command.bats` — red: оба bats-файла материализованы; `--policy brief-input` отвечает usage-ошибкой `policy_not_implemented` (поведение S1-C5 до поставки S7), `scripts/mb-brief.sh` и `commands/brief.md` не существуют, клауза-ассерты дают `clause=<id> reason=absent`; exit: 1; output~: `not ok [0-9]+ (brief_scan|brief_cmd): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь, X-05)**: каждый тест в `test_mb_secret_scan_brief_input.bats`
  начинается с family-префикса `brief_scan: `, каждый тест в `test_mb_brief_command.bats` — с
  `brief_cmd: ` (положительные именованные префиксы; `bats-gather-tests` их не содержит).
- `tests/bats/test_mb_secret_scan_brief_input.bats` ДО политики (общие элементы S1-C5 проверяются
  как контракт потребителя, не переопределяются): `brief_scan: clean` (чистый файл → stdout ровно
  `scan=clean`, exit 0); `brief_scan: blocked` (`sk-…` → `scan=blocked` + stderr
  `<file>:<line>:api_key`, exit 1); `brief_scan: private-does-not-suppress` (секрет внутри
  `<private>…</private>` → всё равно `scan=blocked` — в отличие от политики `transcript`);
  **`brief_scan: pragma`** (`<!-- mb-secret-ok -->` на строке-находке и на строке над ней →
  подавляется **только** эта находка; вторая находка в файле остаётся `scan=blocked`);
  `brief_scan: finding-order` (email+api_key и две находки на одной строке → stderr по
  возрастанию `(line, column)`); `brief_scan: secret-never-printed` (grep по значению ключа
  не находит его ни в stdout, ни в stderr); `brief_scan: unsupported` (бинарный/нечитаемый →
  stdout `scan=unsupported`, stderr `<file>:0:binary|unreadable`, exit 2);
  `brief_scan: pattern-parity` (набор классов совпадает с `scripts/mb-import.py`
  `EMAIL_RE`/`APIKEY_RE`); shellcheck clean.
- `tests/bats/test_mb_brief_command.bats` ДО helper'а и команды. Файловая половина (C6, без LLM):
  **`brief_cmd: create-publishes-atomically`** (валидный кандидат + чистый input → stdout ровно
  `brief=created path=briefs/<topic>/brief.md`, exit 0, `briefs/<topic>/{brief.md,inputs/PRD.md}`
  на месте, кандидат удалён, `tmp/` без staging-остатков; Scenario 1); `brief_cmd: no-input`
  (промт-only бриф, `inputs: []`, тело Attachments ровно `- None`);
  **`brief_cmd: first-publish-creates-roots`** (свежий банк без `briefs/`/`tmp/` → helper создаёт
  корни и публикует, exit 0; R3-003); **`brief_cmd: empty-topic-dir-blocks`** (пустой каталог
  `briefs/<topic>/` уже существует → `brief=blocked reason=exists`, exit 1, staging **не** вложен
  внутрь него; R3-003); **`brief_cmd: concurrent-create-one-wins`** (два настоящих конкурентных
  процесса create одного топика под publish-мьютексом → ровно один `created` exit 0 и ровно один
  `exists` exit 1; R3-003); **`brief_cmd: secret-hard-block`** (input с секретом → stdout
  `brief=blocked reason=secret`, stderr сканера форварднут, exit 1, `briefs/<topic>/` **не существует**,
  кандидат сохранён и назван `candidate=<path>` последней строкой; Scenario 3);
  `brief_cmd: scan-unsupported-aborts` (нечитаемый input → `brief=blocked reason=scan_unsupported`,
  exit 1, destination не создан, override-флага нет; Scenario 4);
  **`brief_cmd: two-unsupported-both-named`** (два нечитаемых input → `brief=blocked reason=scan_unsupported`,
  exit 1, **оба** источника названы на stderr; R3-006); **`brief_cmd: mixed-blocked-unsupported`**
  (один blocked + один unsupported → приоритет `unsupported` по таблице C5, stderr несёт диагностику
  обоих non-clean источников в argv-порядке; R3-006); `brief_cmd: scan-usage-is-not-clean`
  (сканер вернул exit 2 с пустым stdout → `error=scan_usage path=<p>`, exit 2, копирования нет);
  `brief_cmd: basename-collision` (два `--input` с одним basename → stdout пуст,
  `error=basename_collision basename=<b>`, exit 2, каталог не создан);
  `brief_cmd: input-unreadable` (`error=input_unreadable path=<p>`, exit 2);
  `brief_cmd: exists-blocks-without-overwrite` (существующий топик → `brief=blocked reason=exists`,
  exit 1, mtime и содержимое `brief.md` не изменились; флага `--update` нет — неизвестный флаг
  даёт `error=usage`, exit 2); `brief_cmd: invalid-candidate-blocked` (кандидат без `## UX` →
  `brief=blocked reason=invalid` + дословно форварднутая диагностика C1, exit 1 — доказывает, что
  helper реально вызывает `scripts/mb-brief-validate.sh` Task 2 до публикации, R2-002);
  `brief_cmd: auto-requires-assumptions-note` (с `--auto` без ключа → `brief=blocked reason=invalid` +
  `error=assumptions_note_missing`; Scenario 7); `brief_cmd: no-auto-rejects-assumptions-note` (без
  `--auto` с ключом → `error=assumptions_note_unexpected`);
  **`brief_cmd: attachments-encoded-basename`** (input с basename, содержащим пробел/`#`/`)` →
  ссылка Attachments percent-encoded по RFC 3986; C6 декодирует и сверяет множество; неканоничная/
  дублирующая ссылка → `error=inputs_mismatch … where=attachments`, exit 1; R3-004);
  `brief_cmd: inputs-mismatch` (frontmatter/Attachments/argv расходятся →
  `error=inputs_mismatch path=<p> where=<…>`, exit 1);
  **`brief_cmd: candidate-flag-missing-no-line`** (нет `--candidate` → usage `error=…`, exit 2, **ни одной**
  `candidate=`-строки; R3-007); **`brief_cmd: candidate-path-nonexistent-no-line`** (несуществующий
  `--candidate` → usage error, exit 2, без `candidate=`; R3-007); **`brief_cmd: candidate-saved-on-late-failure`**
  (валидный принятый кандидат, отказ на secret-scan → `candidate=<path>` **последней** строкой stderr; R3-007);
  `brief_cmd: context-absent` (stdout ровно `brief=absent`, exit 0); `brief_cmd: context-manifest`
  (`brief=present` + `brief_path=` + `input_path=` в порядке `LC_ALL=C`, тело брифа не печатается);
  `brief_cmd: context-usage` (exit 2). shellcheck clean.
- `tests/bats/test_mb_brief_command.bats`, prompt-половина — клаузы C7 через харнесс S1-C9
  (`load 'lib/discuss_contract'` + регистрация записей в `MB_DISCUSS_CLAUSES`), на каждую клаузу
  **обе** функции (`assert_clause commands/brief.md <id>` + `assert_clause_load_bearing …`), что
  закрывает REQ-003/REQ-004 кодово-верифицируемо (SVP-BRIEF-006). Имена тестов несут family-префикс
  `brief_cmd: `, id клаузы регистрируется с префиксом `brief-` (коллизии id между слайсами запрещены):
  **`brief_cmd: clause-questions-unclear`** — клауза `brief-questions-unclear` (REQ-003): секция «Light
  questions» предписывает задать **не более пяти** вопросов **только** когда суть или цель не
  извлекаются из запроса и вложений, **и `--auto` не выбран**, и **до** генерации; мутация: «не более
  пяти» → «сколько потребуется» (тема «вопрос» в блоке остаётся живой);
  `brief_cmd: clause-questions-skipped-when-clear` — клауза `brief-questions-skipped-when-clear`
  (REQ-004): при ясных сути и цели ветка вопросов пропускается и бриф генерируется сразу; мутация:
  «пропускается» → «выполняется»; `brief_cmd: clause-auto-skips-questions` — клауза
  `brief-auto-skips-questions` (REQ-003/004): `--auto` пропускает гейт вопросов **всегда** и требует
  непустой `assumptions_note`; мутация: снять «всегда»;
  **`brief_cmd: clause-request-source-xor`** — клауза `brief-request-source-xor` (REQ-001, C0/R3-008):
  одновременная передача `--request` и `--request-file` даёт `error=usage`, а без обоих флагов
  используется **только** текст пользовательского сообщения после инвокации; мутация: снять «только»/XOR;
  **`brief_cmd: clause-request-inline-nonempty`** — клауза `brief-request-inline-nonempty` (REQ-001,
  C0/R3-008): whitespace-only `--request` даёт `error=request_empty` до записи кандидата; мутация: снять
  «непробельный»; **`brief_cmd: clause-request-file-guard`** — клауза `brief-request-file-guard` (REQ-001,
  C0/R3-008): `--request-file` missing/symlink/directory/`..` → `error=request_unreadable path=<p>`,
  whitespace-only файл → `error=request_empty path=<p>`, всё до записи кандидата; мутация: снять
  guard-условие; `brief_cmd: clause-candidate-before-helper` — клауза `brief-candidate-before-helper`
  (REQ-001): полный текст пишется в кандидата `tmp/` **до** вызова helper'а; мутация: «до» → «после»;
  `brief_cmd: clause-helper-publish` — клауза `brief-helper-publish` (REQ-001): публикация только через
  `scripts/mb-brief.sh create`, прямая запись в `briefs/` запрещена; мутация: снять «только»;
  `brief_cmd: clause-attachments-links` — клауза `brief-attachments-links` (REQ-008): Attachments
  перечисляет каждый скопированный источник относительной ссылкой `inputs/<basename>`; мутация: снять
  «относительной ссылкой»; `brief_cmd: clause-handoff-line` — клауза `brief-handoff-line` (REQ-005):
  финальная строка вывода — ровно `/mb discuss <topic>`; мутация: «финальная строка» → «где-нибудь в
  выводе».
- Сценарии §1–4 и §7 (requirements.md) — supplemental ручной smoke, не единственное доказательство.

**DoD:**
- [ ] Политика `brief-input` в `scripts/mb-secret-scan.sh` реализует S1-C5 без переопределения общих элементов; `test_mb_secret_scan_brief_input.bats` green
- [ ] `scripts/mb-brief.sh create|context` реализован по C6: bootstrap корней + exists-гейт под publish-мьютексом (файл/каталог/symlink) → валидация C1 (Task 2) → сверки `--auto`/inputs (грамматика Attachments) → scan-all C5 с агрегацией R3-006 → staging → одиночный атомарный `mv`; правило `candidate=` R3-007 (usage-ошибки без строки, поздний отказ — с ней последней); два конкурентных create → один `created`, один `exists`
- [ ] `commands/brief.md` + шаблон в `references/templates.md` по C0/C2; каждая клауза C7 (включая request-source XOR/empty/file-guard R3-008) проходит `assert_clause` **и** `assert_clause_load_bearing`
- [ ] Eval green (был red по заявленному якорю `output~:`); shellcheck clean; сценарии §1–4, §7 отрабатывают вручную как smoke
<!-- /mb-task:1 -->

<!-- mb-task:3 -->
## Task 3: Интеграция с discuss Phase 0

**Stage:** 2
**Covers:** REQ-006
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/discuss.md, tests/bats/test_brief_discuss_handoff.bats
**Budget:** 60000

**What to do:**
- В `commands/discuss.md` Phase 0: вызвать `scripts/mb-brief.sh context --mb <bank> --topic <topic>`
  (C3/C6); `brief=absent` → поведение прежнее (legacy Phase 0 без изменений); `brief=present` →
  `brief_path`/`input_path` из манифеста читаются как первые источники Research digest
  (best-effort). Bank-relative пути манифеста — единственный источник, ad-hoc парсинг `briefs/`
  в промпте запрещён.

**Eval:** `bats tests/bats/test_brief_discuss_handoff.bats` — red: bats-файл материализован, helper C6 из Task 1 уже отвечает манифестом, но клауз Phase 0 в `commands/discuss.md` нет — клауза-ассерты дают `clause=<id> reason=absent`; exit: 1; output~: `not ok [0-9]+ brief_handoff: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь, X-05)**: каждый тест в `test_brief_discuss_handoff.bats`
  начинается с family-префикса `brief_handoff: ` (положительный именованный префикс).
- `tests/bats/test_brief_discuss_handoff.bats` ДО правки, клаузы C7 через харнесс S1-C9 (обе
  функции на каждую клаузу): **`brief_handoff: phase0-reads-brief`** — клауза
  `discuss-phase0-brief-manifest` (REQ-006): Phase 0 получает источники брифа **из манифеста**
  `scripts/mb-brief.sh context` и ставит их первыми в Research digest; мутация: «первыми» →
  «в числе прочих»; **`brief_handoff: legacy-parity`** — клауза `discuss-phase0-absent-parity`
  (REQ-006): при `brief=absent` Phase 0 выполняется без изменений; мутация: снять «без изменений».
- `brief_handoff: manifest-contract` — детерминированная сверка: на фикстурном банке с
  `briefs/<topic>/{brief.md,inputs/a.md,inputs/b.md}` вывод `scripts/mb-brief.sh context` содержит
  `brief_path` первым и `input_path` в порядке `LC_ALL=C` (тот примитив, который цитирует клауза).
- Сценарий §5 (requirements.md) — supplemental ручной smoke.

**DoD:**
- [ ] Phase 0 читает бриф через манифест C6; `brief=absent` не меняет legacy-поведение
- [ ] Обе клаузы проходят `assert_clause` **и** `assert_clause_load_bearing`; Eval green (был red по заявленному якорю)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Роутинг и документация

**Stage:** 2
**Covers:** REQ-001
**Role:** developer
**Blocked-by:** 1
**Scope:** commands/mb.md, README.md, CLAUDE.md, tests/bats/test_mb_brief_docs.bats
**Budget:** 50000

**What to do:**
- Строка `brief <topic>` в таблице § Routing `commands/mb.md` с dispatch на `commands/brief.md` +
  блок `### brief` с дословным синопсисом C0 (C4).
- Стадия в session-pipeline README.md и CLAUDE.md: `brief → discuss → sdd → work`.

**Eval:** `bats tests/bats/test_mb_brief_docs.bats` — red: bats-файл материализован, в таблице § Routing `commands/mb.md` нет строки с dispatch на `commands/brief.md`, блока `### brief` нет, README.md/CLAUDE.md не содержат стадию; exit: 1; output~: `not ok [0-9]+ brief_docs: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (red-якорь, X-05)**: каждый тест в `test_mb_brief_docs.bats` начинается с
  family-префикса `brief_docs: ` (положительный именованный префикс).
- `tests/bats/test_mb_brief_docs.bats` ДО правки (структурные ассерты целых строк/секций, не
  изолированных слов — R2-003): **`brief_docs: router-row`** — в таблице § Routing `commands/mb.md`
  есть **ровно одна** строка, целиком совпавшая с `^\| *brief <topic> *\|.*commands/brief\.md.*\|$`
  (комментарий или строка без dispatch тест не проходит); **`brief_docs: router-synopsis`** — блок
  `### brief` извлекается `mb_section commands/mb.md 'brief'` (харнесс S1-C9) и содержит синопсис C0
  целиком: `/mb brief <topic>` + `--request`/`--request-file` + повторяемый `--input` + `--auto`;
  **`brief_docs: pipeline-stage`** — и `README.md`, и `CLAUDE.md` содержат стадию
  `brief → discuss → sdd → work` (проверяются оба файла отдельными ассертами; отсутствие любого →
  fail); `brief_docs: no-update-flag` — ни `commands/mb.md`, ни `commands/brief.md` не упоминают
  `--update` (флага нет в MVP, BRIEF-003).
- shellcheck clean.

**DoD:**
- [ ] Routing-строка с dispatch + блок `### brief` с синопсисом C0 в `commands/mb.md`
- [ ] `brief → discuss → sdd → work` в README.md и CLAUDE.md
- [ ] Eval green (был red по заявленному якорю); все три ассерта проверяют целые строки/секции, а не наличие слова `brief`
<!-- /mb-task:4 -->
