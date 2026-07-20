# Design: svp-brief

> Слайс S7 (blocked by S1 `svp-interview-upgrade` — Task 1 потребляет канонический диспетчер
> secret-scan S1-C5 и реализует в нём политику `brief-input`). По D-05: контракты и Eval-декларации
> здесь, код эвалов — первым шагом задач в work-фазе.
> Читать перед планированием/ревью: `context/svp-brief-interview.md` + родительский транскрипт (D-29).
> Ревизия 3 (2026-07-17): закрыт круг 2 (R2-001…003, SVP-BRIEF-001/002/003/004/006) — C6 получил
> candidate-канал (prompt владеет текстом, helper — валидацией/staging/атомарной публикацией), C5
> выровнен на канонический диспетчер S1 (`--policy brief-input`; владелец CLI — S1, не
> `sdd-openspec-parity`), `--update` убран из MVP, диагностика C1 упорядочена и агрегирована,
> prompt-контракт проверяется клауза-ассертами C7 (харнесс S1-C9), Eval-строки несут red-якоря
> S2-C1 (`output~:` на каждой gated-задаче), порядок задач исправлен на `2 → 1 → 3 → 4`.
> Ревизия 2 (2026-07-17): закрыт круг 1 (BRIEF-001…008).

## Architecture

Три слоя. **Prompt** — новая команда `commands/brief.md` (анализ входа → лёгкие вопросы →
генерация полного текста брифа → вызов helper'а → хендоф) + правка Phase 0 в `commands/discuss.md`
(чтение брифа через детерминированный манифест). **Скрипт** — `scripts/mb-brief.sh` (валидация
кандидата, secret-scan гейт, staging, атомарная публикация — C6) и `scripts/mb-brief-validate.sh`
(структурная валидация, C1). **Сканер** — политика `brief-input` в `scripts/mb-secret-scan.sh`:
файл и диспетчер `--policy` создаёт S1, политику реализует этот слайс в том же файле (C5, так
распределил владение сам S1-C5). Хранение: `briefs/<topic>/` (S7-A-01).

Разделение труда (Strangler Fig, тот же паттерн, что в соседних слайсах): prompt-слой владеет
суждением (анализ сути/цели, лёгкие вопросы, текст всех девяти секций) и **полностью формирует
кандидата до вызова скрипта**; скрипт-слой владеет детерминированной мутацией файловой системы
(валидация кандидата, сканирование источников, staging, атомарная публикация, коллизии) — поэтому
файловая часть тестируется bats без LLM (BRIEF-006), а нормативные клаузы prompt-слоя проверяются
клауза-ассертами C7. Двухфазная запись через кандидата в `<bank>/tmp/` — тот же приём, которым
S1-C5 защищает транскрипт (единый групповой паттерн, а не местное изобретение).

## Interfaces

### C0. `/mb brief <topic> [--request <text> | --request-file <path>] [--input <path>]… [--auto]`

Это umbrella-контракт (`specs/sdd-vision-pipeline/design.md` § Interfaces #7) — декларируется здесь
дословно, не переопределяется, и детализируется до полноты, нужной для реализации/тестов. Все
детерминированные исходы C0 — это исходы helper'а C6: prompt-слой их не переписывает, не подавляет
и ничего не публикует в `briefs/` в обход helper'а.

- `<topic>` MUST match `[a-z0-9][a-z0-9-]*`; любое другое значение — usage-ошибка (`error=usage`,
  exit 2) до какой-либо записи.
- Ровно один источник текста запроса: `--request <text>` (инлайн) XOR `--request-file <path>` XOR
  текущее пользовательское сообщение/промт, когда ни один флаг не передан; одновременная передача
  `--request` и `--request-file` — usage-ошибка (`error=usage`, exit 2).
- `--request <text>` MUST содержать хотя бы один непробельный символ; иначе `error=request_empty`,
  exit 2 до какой-либо записи (BRIEF-003).
- `--request-file <path>` MUST указывать на существующий читаемый regular file (не symlink, не
  directory, без `..`), содержимое — хотя бы один непробельный символ; нарушение →
  `error=request_unreadable path=<p>` либо `error=request_empty path=<p>`, exit 2 до какой-либо
  записи (BRIEF-003).
- `--input <path>` повторяемый; каждый `<path>` MUST быть существующим читаемым regular file (не
  directory, не symlink, без `..`/path traversal). Совпадающие basename между несколькими
  `--input` — usage-ошибка `error=basename_collision basename=<b>`, обнаруживается до создания
  каталога. Отсутствующий/нечитаемый `--input` — `error=input_unreadable path=<p>`, exit 2;
  `briefs/<topic>/` не создаётся (никакого частичного результата).
- `--auto`: пропускает гейт лёгких вопросов (нормативное **исключение `--auto`** в REQ-003/004 — оно
  зафиксировано в самих формулировках требований, а не только здесь) и продолжает на best-effort
  инференсе; frontmatter брифа MUST нести непустой скалярный `assumptions_note`. **Без `--auto` этот
  ключ MUST отсутствовать.** Правило проверяется кодово (C6 получает тот же флаг), а не доверием к
  prompt-слою (BRIEF-003).
- Secret-scan (C5) и структурная валидация (C1) выполняются ДО создания `briefs/<topic>/`: каталог
  либо появляется целиком (`brief.md` + `inputs/` с уже просканированными копиями), либо не
  появляется вовсе (C6: staging + одиночный `mv`).
- Если `briefs/<topic>` уже существует (как файл, каталог или symlink — проверка под publish-мьютексом
  C6): stdout `brief=blocked reason=exists`, exit 1, ни один файл не создаётся и не меняется.
  **Update/версионирование — вне MVP, флага `--update` нет**
  (BRIEF-003, R2-001): повторная формализация делается на новом `<topic>` либо после ручного
  удаления каталога пользователем.

### C1. `scripts/mb-brief-validate.sh <brief.md>`

- Принимает ровно один существующий читаемый regular file; любой другой вызов (0/≥2 аргумента,
  файла нет, путь — директория, неизвестный флаг) → stdout пуст, stderr ровно `error=usage`,
  exit 2. Существующий, но нечитаемый файл → stdout пуст, stderr ровно `error=io path=<path>`,
  exit 2 (SVP-BRIEF-004).
- Требует ровно по одному H2-заголовку (`## `) на каждую обязательную секцию, точное написание,
  регистр важен, без алиасов и дублей. **Канонический порядок девяти секций** (в файле порядок не
  enforced, но диагностика печатается именно в нём): `Essence`, `Goal & Impact`, `References`,
  `Solution (JTBD)`, `Scenarios`, `Constraints`, `UX`, `Done Criteria`, `Attachments`.
- Frontmatter (YAML) — **закрытый набор ключей**: обязательные `topic` (строка), `created` (ISO
  `YYYY-MM-DD`), `status: ready|draft`, `inputs` (YAML-список относительных `inputs/...`-путей,
  допустим `[]`); опциональный `assumptions_note` (если ключ присутствует — непустой скаляр).
  Отсутствие обязательного ключа, неверный тип/формат, дубль ключа или любой ключ вне набора →
  нарушение класса `frontmatter_invalid`.
- `Essence` и `Goal & Impact` MUST содержать хотя бы одну непустую, не-комментарную строку.
- stdout: ровно одна строка — `brief=ok` (все проверки содержимого прошли) или `brief=invalid`
  (≥1 нарушение содержимого).
- stderr — детерминированный поток диагностик строго в этом порядке (закрывает SVP-BRIEF-004;
  разные корректные реализации обязаны давать байт-идентичный поток):
  1. **не более одной** агрегатной строки
     `error=frontmatter_invalid section=frontmatter fields=<f1,f2,…>` — все нарушения frontmatter
     схлопываются в неё, `fields` перечисляет затронутые ключи в порядке набора выше
     (`topic,created,status,inputs,assumptions_note`, затем неизвестные ключи в порядке появления
     в файле);
  2. секционные диагностики в каноническом порядке девяти секций; внутри одной секции
     `missing_section` либо `duplicate_section` печатается перед `empty_essence`/`empty_goal`;
     формат строки — `error=<code> section=<name>`; коды: `missing_section`, `duplicate_section`,
     `empty_essence`, `empty_goal`;
  3. последней строкой (если применимо) — `warning=oversize lines=<N> limit=120`.
- Exit: `0` = valid (возможен вместе с `warning=oversize`); `1` = ≥1 нарушение содержимого
  (`brief=invalid` + `error=...`-строки); `2` = usage/I-O ошибка (строка `brief=` не печатается).
- Лимит строк (NFR-001): считается по всему файлу. Target 60–100; 101–120 проходят без
  предупреждения; **>120** → строка `warning=oversize lines=<N> limit=120`; сам по себе warning не
  меняет exit (остаётся `0`, если по остальным проверкам файл валиден).

### C2. Структура `briefs/<topic>/` (bank-relative)

- `brief.md` — девять секций C1; frontmatter: `topic`, `created`, `status: ready|draft`,
  `inputs: [..]`, опционально `assumptions_note` (только под `--auto`).
- `inputs/*` — копии источников, прошедших `--policy brief-input` со `scan=clean` (C5). Источник со
  `scan=blocked`/`scan=unsupported` в `inputs/` не попадает никогда: при любом таком источнике
  каталог не публикуется вовсе (C6, шаг 6).
- **Каноническая грамматика секции `## Attachments`** (закрывает R3-004 — без неё разные реализации
  распарсили бы разные множества ссылок): при непустом inputs тело секции содержит **ровно по одной**
  строке `- [<basename>](inputs/<encoded-basename>)` на каждый `--input`, в порядке аргументов
  командной строки; `<encoded-basename>` — percent-encoding UTF-8 по RFC 3986 с safe-набором
  `A-Z a-z 0-9 - . _ ~` (пробел → `%20`, `#` → `%23`, `)` → `%29` и т.д.). При пустом inputs тело
  содержит **ровно** строку `- None`. Любая другая непустая строка в теле секции запрещена. C6
  декодирует destination каждой ссылки, отклоняет malformed или дублирующиеся ссылки
  (`error=inputs_mismatch … where=attachments`) и сравнивает полученное множество с frontmatter и argv.
- Инвариант, который проверяет C6 (шаг 5): множество `inputs`-путей frontmatter = множество
  **декодированных** ссылок секции Attachments = `{ inputs/<basename> | <basename> — basename каждого
  переданного --input }`.

### C3. Хендоф

- Финальная строка вывода `/mb brief` — предложение `/mb discuss <topic>` (REQ-005). Это нормативная
  клауза prompt-слоя: доказывается клауза-ассертами C7, а не grep'ом по слову.
- discuss Phase 0 читает бриф через детерминированный манифест `scripts/mb-brief.sh context` (C6),
  не ad-hoc парсингом: `brief=absent` → Phase 0 не меняется (best-effort, legacy-паритет);
  `brief=present` → `brief_path`/`input_path` из манифеста становятся первыми источниками Research
  digest.

### C4. Роутер и документация

- Строка в таблице `commands/mb.md` § Routing: `brief <topic>` → dispatch `commands/brief.md`.
- Блок `### brief` в `commands/mb.md` несёт синопсис C0 дословно.
- `README.md` и `CLAUDE.md` описывают стадию в session-pipeline: `brief → discuss → sdd → work`.

### C5. Secret-scan гейт для `inputs/` (диспетчер S1-C5, политика `brief-input`)

**Владение (закрывает SVP-BRIEF-002).** Исполняемый файл `scripts/mb-secret-scan.sh`, диспетчер
`--policy` и политику `transcript` создаёт S1 (`specs/svp-interview-upgrade/design.md` § C5,
Task 4). Политику **`brief-input` реализует этот слайс** в том же файле — так распределил владение
сам S1-C5. `sdd-openspec-parity` этим CLI **не владеет** и общего сканера не создаёт (его T6 —
внутренняя проверка `mb-spec-validate.sh` над `specs/<topic>/inputs/`); единственная связь — общий
источник паттернов `scripts/mb-import.py`. Общие элементы контракта (имя, аргументы, stdout-строки
`scan=clean|scan=blocked|scan=unsupported`, метки `email`/`api_key`, порядок находок по
`(line, column)`, exit-коды 0/1/2) зафиксированы в S1-C5 и здесь **не переопределяются**; S7 не
«добавляет отсутствующий exit 2» — exit 2 у S1 уже есть.

- **Вызов**: до создания `briefs/<topic>/` и до записи любого файла под ним C6 вызывает
  `scripts/mb-secret-scan.sh --policy brief-input <source-path>` ровно по одному разу на каждый
  переданный `--input`, в порядке их появления в командной строке. Все сканы завершаются ДО того,
  как под `briefs/<topic>/` создан хоть один файл (атомарность — реализует BRIEF-001).
- **Семантика политики `brief-input`** зафиксирована S1-C5 и потребляется как есть: `<private>`
  находку **не** подавляет; бинарный/нечитаемый/неподдерживаемого типа файл →
  `scan=unsupported`, exit 2. Специфика S7 поверх этого — ровно две вещи: скан применяется к файлам
  брифа **до копирования** в `inputs/`, и исходы сканера отображаются в исходы `/mb brief` (ниже).
- **Правило прагмы `<!-- mb-secret-ok -->` — ровно два случая, и только они** (ревизия 4, уточнение
  по итогам реализации T1). Прежняя формулировка «на строке-находке **или на строке непосредственно
  над ней**» противоречила соседнему «подавляет **только эту** находку»: прагма, написанная инлайн,
  по построению является и «строкой над» следующей строкой, поэтому одна пометка гасила находки на
  **двух** строках. Действующее правило:
  1. прагма **одна на строке** (`strip()` строки равен прагме — ведущие/хвостовые пробелы
     игнорируются) подавляет находки на строке **под** ней. Это escape-hatch для находки, которую
     нельзя пометить инлайн (например, внутри code fence);
  2. прагма, написанная **инлайн** (на строке есть что-то ещё), подавляет находки **только на своей
     строке** и на следующую строку **не** распространяется.

  Обоснование выбора узкого чтения: прагма гасит находки **secret-scan**, поэтому из двух ошибок
  избыточное подавление приводит к утечке credential'а, а недостаточное — лишь к необходимости
  написать вторую прагму. Когда два чтения расходятся в эту сторону, побеждает более узкое.
  Оба случая закреплены тестами `brief_scan: pragma — an INLINE pragma shields ONLY its own line`,
  `… a pragma ALONE on its line shields the line below`, `… a pragma with prose beside it does NOT
  shield below` и `… trailing whitespace still counts as alone on the line`.
- **Инспектируемость типов принадлежит S1-C5 (закрывает R3-005 на стороне потребителя).** Какой
  источник сканируем, а какой даёт `scan=unsupported`, решает владелец сканера S1-C5, а не S7: по его
  текущему контракту **бинарный/нечитаемый/неподдерживаемого типа файл → `scan=unsupported`, exit 2**.
  Следствие для S7: бинарный контейнер (`.pdf`, `.docx` и т.п.) в MVP даёт `scan=unsupported`, поэтому
  ни один сценарий/тест S7 не обещает «clean PDF» — Scenario 1 использует читаемый UTF-8 текст
  (`PRD.md`). S7 сам логику классификации типов не изобретает и `extractor`'ы не вызывает. Точная
  формализация «сканируемым считается readable regular file без NUL, декодируемый как UTF-8» —
  cross-slice request к S1-C5 (§ Cross-slice requests X-03), чтобы enum `reason` из S1-C5 имел
  исполнимое правило классификации; до его принятия S7 выравнивается на действующее «binary →
  unsupported».
- **Отображение исходов сканера в C6/C0** (закрывает SVP-BRIEF-001):

  | Сканер | Исход `/mb brief` |
  |---|---|
  | exit 0, stdout `scan=clean` | источник допускается к копированию |
  | exit 1, stdout `scan=blocked` | stdout `brief=blocked reason=secret`, **exit 1**; stderr сканера (`<file>:<line>:<pattern>`) форвардится дословно; ни один файл не скопирован |
  | exit 2, stdout `scan=unsupported` | stdout `brief=blocked reason=scan_unsupported`, **exit 1**; stderr сканера (`<file>:0:<reason>`) форвардится дословно; ни один файл не скопирован |
  | exit 2, stdout пуст (usage error сканера) | stdout пуст, stderr `error=scan_usage path=<p>`, **exit 2** — регрессия контракта; «чисто» из неё не выводится |

  Два случая exit 2 различимы по stdout сканера — ровно так, как это зафиксировал S1-C5; тихое
  копирование запрещено в обоих.
- **Агрегация нескольких источников (закрывает R3-006).** REQ-010 требует назвать «every unscannable
  source», а C5 сканирует **каждый** `--input`, поэтому исход `/mb brief` определяется по НАБОРУ
  результатов, а не по первому. C6 (шаг 6) запускает сканер по всем `--input`, буферизует результаты и
  выводит диагностику в **argv-порядке источников**, внутри одного источника — в порядке сканера
  (по возрастанию `(line, column)`). Приоритет итога (первый сработавший класс побеждает):
  1. **любой** источник дал `scan=usage` (exit 2, пустой stdout сканера) → stdout пуст, на stderr по
     строке `error=scan_usage path=<p>` на каждый такой источник, **exit 2** (регрессия контракта);
  2. иначе **любой** источник дал `scan=unsupported` → stdout `brief=blocked reason=scan_unsupported`,
     **exit 1**;
  3. иначе **любой** источник дал `scan=blocked` → stdout `brief=blocked reason=secret`, **exit 1**;
  4. иначе (все `scan=clean`) публикация продолжается.

  При итогах 2/3 stderr несёт диагностику **всех** non-clean источников (форвард сканера дословно),
  поэтому ни секрет, ни неинспектируемый источник не скрываются, даже если их несколько. Ни один
  источник в `inputs/` при итогах 1–3 не копируется (атомарность C6).
- **Override-флага нет в MVP** (закрывает SVP-BRIEF-001). Допустимые продолжения по
  заблокированному или неинспектируемому источнику — только: удалить/отредактировать секрет в самом
  источнике; пометить строку-находку `<!-- mb-secret-ok -->`; конвертировать источник в сканируемый
  формат; исключить его из `--input`. После этого команда вызывается заново. Небезопасная копия по
  подтверждению не поддерживается ни для `scan=blocked`, ни для `scan=unsupported`.
- `<private>…</private>` ортогонален сканеру: он влияет только на `index.json`/`mb-search`-редакцию
  (rules/RULES.md, caveat `<private>`) и НЕ считается способом разблокировать git-запись — находку
  сканера он не снимает.

### C6. `scripts/mb-brief.sh create|context` (детерминированный helper; закрывает R2-001/BRIEF-006)

#### `create --mb <bank> --topic <topic> --candidate <path> [--input <path>]… [--auto]`

**Канал готового текста (закрывает R2-001).** Prompt-слой сначала завершает анализ, лёгкие вопросы
и генерацию, затем пишет **полный** бриф (frontmatter + девять секций + Attachments) в кандидата
`<bank>/tmp/brief-<topic>.candidate.md` и передаёт его путь флагом `--candidate`. Helper шаблон не
заполняет и текст не генерирует — он владеет валидацией, сканированием, staging'ом и атомарной
публикацией. Флагов `--request`/`--request-file` у helper'а нет: это вход prompt-слоя.

Детерминированный порядок шагов; любой отказ наступает **до единой записи** в `briefs/`:

1. **Usage**: `--mb` и `--topic` обязательны; `<topic>` — по паттерну C0; ровно один `--candidate`,
   существующий читаемый regular file; каждый `--input` — существующий читаемый regular file (не
   symlink/directory, без `..`); совпадающие basename → `error=basename_collision basename=<b>`.
   Любое нарушение → stdout пуст, `error=<code>` на stderr, exit 2.
2. **Bootstrap корней + exists-гейт под publish-мьютексом**: helper создаёт `<bank>/tmp/` и
   `<bank>/briefs/`, если их нет — свежий банк их не гарантирует (`/mb init` создаёт только
   `experiments,plans/done,notes,reports,codebase`, `commands/mb.md`). Затем берётся owner-token
   `mkdir`-мьютекс публикации `<bank>/tmp/.brief-<topic>.lock` (**узкий same-command mutex**, а не
   общий work-claims-лок: S7 по порядку исполнения группы идёт ДО S4, поэтому helper `mb_lock_acquire`
   S4-C6 к его старту ещё не отгружен — берётся минимальный атомарный `mkdir`-мьютекс, тот же примитив,
   пятая копия общего лока не пишется; снимается `trap`'ом на EXIT/INT/TERM). Под мьютексом destination
   проверяется повторно: если `briefs/<topic>` существует как файл, каталог **или** symlink → stdout
   `brief=blocked reason=exists`, stderr `error=exists path=briefs/<topic>`, exit 1, ноль записей.
   Два конкурентных create сериализуются на мьютексе ⇒ ровно один `created` и ровно один `exists`;
   вложенного staging-каталога не возникает.
3. **Валидация кандидата**: вызов `scripts/mb-brief-validate.sh <candidate>` (C1, задача 2 — уже
   реализована к этому моменту, см. tasks.md Blocked-by). Не-ноль → stdout
   `brief=blocked reason=invalid`, stderr C1 форвардится дословно, exit 1.
4. **Сверка `--auto`**: с `--auto` frontmatter кандидата MUST нести непустой `assumptions_note`,
   иначе `brief=blocked reason=invalid` + stderr `error=assumptions_note_missing`; без `--auto`
   ключ MUST отсутствовать, иначе `brief=blocked reason=invalid` + stderr
   `error=assumptions_note_unexpected`.
5. **Сверка inputs**: инвариант C2. Нарушение → stdout `brief=blocked reason=invalid`, stderr —
   по строке `error=inputs_mismatch path=<p> where=<frontmatter|attachments|argv>` на каждый
   расходящийся путь в порядке `LC_ALL=C`, exit 1.
6. **Secret-scan**: C5 по каждому `--input`, все сканы до любой записи; отображение исходов —
   таблица C5.
7. **Staging**: `<bank>/tmp/brief-<topic>.staging.<pid>-<rand>/` — копия кандидата как `brief.md`
   + копии источников в `inputs/<basename>`.
8. **Публикация** (под тем же publish-мьютексом): одиночный `mv` staging-каталога в `briefs/<topic>/`.
   Поскольку под мьютексом destination гарантированно не существует ни как файл, ни как каталог, ни как
   symlink (шаг 2), `mv` — атомарный `rename(2)` (`tmp/` и `briefs/` — внутри одного банка, одна ФС), а
   **не** вложение staging внутрь уже существующего каталога. Успех → stdout ровно
   `brief=created path=briefs/<topic>/brief.md`, exit 0; мьютекс снимается, кандидат удаляется **после**
   успешного `mv`.
9. **Отказ на шагах** (закрывает R3-007 — правило `candidate=` исполнимо для всех классов отказа):
   - **Usage/I-O ошибки шага 1** (нет `--candidate`, кандидат — не существующий читаемый regular
     file, битые `--mb`/`--topic`/`--input`, `error=basename_collision`) печатают только
     соответствующие `error=…`-строки и **не** печатают `candidate=`: сохранять нечего — путь либо не
     передан, либо не указывает на читаемый файл. stdout при этом пуст, exit 2 (usage) — как и при
     любой usage-ошибке.
   - **После того как кандидат принят** как существующий читаемый regular file (шаг 1 пройден
     полностью), любой отказ шагов 2–8 (exists / валидация C1 / сверка `--auto` / сверка inputs /
     secret-scan) удаляет staging-каталог, `briefs/<topic>/` не создаётся и не меняется, **кандидат
     сохраняется** по своему пути; после всех основных stderr-диагностик **последней** строкой
     печатается ровно одна `candidate=<path>` — пользователь чинит источник/секрет и повторяет вызов
     без повторной LLM-генерации.
   - На success кандидат удаляется **после** успешного `mv` (шаг 8).

> **Отклонение от буквы `proposed_fix` R2-001 (существо находки принято полностью).** Ревью
> предлагало удалять кандидата при любой ошибке. Отклонено: отказы `reason=secret` и
> `reason=scan_unsupported` чинятся **в источнике**, а не в брифе, а `reason=exists` — сменой
> топика; удаление кандидата заставило бы заново прогонять весь LLM-анализ ради ошибки, лежащей
> вне брифа, и прямо противоречило бы «fresh invocation after the source is removed, converted, or
> excluded» из SVP-BRIEF-001. Сохранение кандидата совпадает с уже принятым в группе поведением
> S1-C5 (при exit 1/2 целевой файл не создаётся, кандидат остаётся пользователю на очистку).
> Существо находки — «prompt владеет текстом, helper получает готового кандидата и владеет
> валидацией/staging/атомарной публикацией, destination при отказе не мутируется» — принято.

#### `context --mb <bank> --topic <topic>`

- Брифа нет → stdout ровно одна строка `brief=absent`, exit 0.
- Бриф есть → stdout: первая строка `brief=present`; затем ровно одна строка
  `brief_path=briefs/<topic>/brief.md`; затем по строке
  `input_path=briefs/<topic>/inputs/<name>` на каждый файл `inputs/` в порядке `LC_ALL=C`; exit 0.
  **Тело `brief.md` не печатается** — это манифест путей; читать файлы — задача вызывающего
  (discuss Phase 0 читает их сам). Пути — bank-relative POSIX.
- Usage-ошибка (нет `--mb`/`--topic`, лишний аргумент, `<topic>` не по паттерну) → stdout пуст,
  stderr `error=usage`, exit 2.

### C7. Проверка prompt-контракта (переиспользует харнесс S1-C9)

Нормативные клаузы prompt-слоя (REQ-003/004/005, порядок «кандидат → helper» и **контракт источника
запроса C0**) кодом не исполнимы, но обязаны доказываться детерминированно (закрывает SVP-BRIEF-006).
S7 **не заводит второй prompt-checker**: bats-тесты слайса загружают харнесс S1-C9
(`tests/bats/lib/discuss_contract.bash`, `load 'lib/discuss_contract'`) — его функции файл-параметричны
(`mb_section <file> <heading-ERE>`, `assert_clause <file> <clause-id>`,
`assert_clause_load_bearing <file> <clause-id>`), поэтому применимы и к `commands/brief.md`, и к
`commands/discuss.md`.

**Контракт источника запроса C0 — нагруженные клаузы (закрывает R3-008).** Флагов
`--request`/`--request-file` у helper'а C6 нет — XOR, `request_empty` и guard `--request-file`
(existing readable regular file, не symlink/directory, без `..`) владеет prompt-слой, поэтому они
обязаны быть **load-bearing** prompt-клаузами C7, а не остаться прозой C0. Три клаузы (обе функции на
каждую): `brief-request-source-xor` (одновременно `--request` и `--request-file` → `error=usage`; без
флагов используется только текст пользовательского сообщения после инвокации), `brief-request-inline-nonempty`
(whitespace-only `--request` → `error=request_empty`), `brief-request-file-guard` (missing / symlink /
directory / `..`-путь → `error=request_unreadable path=<p>`; whitespace-only файл → `error=request_empty
path=<p>` — всё до записи кандидата). Без них Task 1 может позеленеть, игнорируя ветки источника запроса
(REQ-001, C0).

- Клаузы S7 объявляются записями того же 7-полевого формата
  `<clause-id>|<extractor>|<extractor-arg>|<clause-ERE>|<topic-anchor-ERE>|<negation-sed>|<REQ-ID>`
  и регистрируются **из тест-файлов S7** (`MB_DISCUSS_CLAUSES+=( … )` после `load`); сам харнесс —
  файл S1 — этим слайсом не редактируется (запрос на явное благословение механизма — X-01).
- Обязательство то же, что в S1-C9: на каждую клаузу вызываются **обе** функции — `assert_clause`
  (ровно одно совпадение внутри блока) и `assert_clause_load_bearing` (negation-мутация обязана
  уронить клаузу при живой теме). Голый `grep -q <слово>` и co-occurrence двух слов запрещены как
  assertion-гейт.

## Decisions

Assumptions S7-A-01…04 (подтверждены 2026-07-17) + D-34 — в context-файлах; не дублируются.
Решения по находкам BRIEF-001…008 (ревизия 2) и R2-001…003 / SVP-BRIEF-001…006 (ревизия 3)
зафиксированы прямо в контрактах выше, в Eval declarations и Risks — паритет с остальными
исправленными слайсами группы (отдельного лога решений слайсы не ведут).

## Eval declarations (red → green в work-фазе)

Грамматика и якоря — S2-C1 (`specs/svp-sdd-core/design.md` § C1): `output~:` обязателен на каждой
задаче, покрывающей gated REQ; red-условие описывает состояние **после** материализации теста.
Отсутствующий bats-файл red'ом не считается: измерено — `bats <missing>` даёт `exit 1` +
`not ok 1 bats-gather-tests`, тот же exit, что и настоящий провал, поэтому exit-only якорь запрещён.
Якорь привязан к **положительному именованному префиксу теста** `<family>: ` (групповая конвенция
X-05, ровно как S2-T5 `candidate_publish:`/S2-T9 `self_check:`): каждый bats-тест файла начинается с
общего family-префикса (см. Testing задач), поэтому `not ok 1 bats-gather-tests` префикс не содержит
и якорю не матчится, а любой настоящий провал именованного кейса — матчится. Семантические
`contract_mismatch=`/`eval_setup_error=`-маркеры из ревью НЕ вводятся: они противоречат S2-C6 (eval-red
обязан НАБЛЮДАТЬ заявленный red ДО implement, а по D-05 продакшн-скрипт в этот момент отсутствует —
setup-guard, классифицирующий «продакшн отсутствует» как не-red, сделал бы red непронаблюдаемым и
заблокировал бы implement) и разошлись бы с якорями S1/S2/S3/S5.

**Byte-identity design↔tasks (закрывает CPR-D).** Строки `**Eval:**` ниже — **byte-identical**
соответствующим `**Eval:**`-строкам одноимённых задач в `tasks.md`; единственный источник истины
якоря — задача. Список НАМЕРЕННО не оформлен markdown-таблицей: пайп-таблица вынудила бы
экранировать `|` как `\|`, а `\|` в POSIX ERE матчит **литерал** `|`, а не альтернативу — такой
`output~:`-якорь никогда не сматчил бы настоящий провал (ровно расхождение CPR-D). Байт-идентичность
`design.md ↔ tasks.md` по каждому task проверяет батарея C8 S2 (`mb-sdd-self-check.sh` +
структурный чек `mb-spec-validate.sh`).

- **T2** — `scripts/mb-brief-validate.sh` (C1): ok / missing-section / duplicate-section /
  empty-essence / empty-goal / frontmatter-invalid / комбинированная фикстура с порядком диагностик /
  oversize-warning / usage / io:
  **Eval:** `bats tests/bats/test_mb_brief_validate.bats` — red: bats-файл материализован, `scripts/mb-brief-validate.sh` не существует, каждый именованный кейс `brief_validate: …` падает; exit: 1; output~: `not ok [0-9]+ brief_validate: `
- **T1** — политика `brief-input` + helper create/context + клаузы C7 `commands/brief.md`
  (families `brief_scan` в `test_mb_secret_scan_brief_input.bats`, `brief_cmd` в `test_mb_brief_command.bats`):
  **Eval:** `bats tests/bats/test_mb_secret_scan_brief_input.bats tests/bats/test_mb_brief_command.bats` — red: оба bats-файла материализованы; `--policy brief-input` отвечает usage-ошибкой `policy_not_implemented` (поведение S1-C5 до поставки S7), `scripts/mb-brief.sh` и `commands/brief.md` не существуют, клауза-ассерты дают `clause=<id> reason=absent`; exit: 1; output~: `not ok [0-9]+ (brief_scan|brief_cmd): `
- **T3** — интеграция discuss Phase 0 (family `brief_handoff`):
  **Eval:** `bats tests/bats/test_brief_discuss_handoff.bats` — red: bats-файл материализован, helper C6 из Task 1 уже отвечает манифестом, но клауз Phase 0 в `commands/discuss.md` нет — клауза-ассерты дают `clause=<id> reason=absent`; exit: 1; output~: `not ok [0-9]+ brief_handoff: `
- **T4** — routing-строка + блок `### brief` + стадия в README.md/CLAUDE.md (family `brief_docs`):
  **Eval:** `bats tests/bats/test_mb_brief_docs.bats` — red: bats-файл материализован, в таблице § Routing `commands/mb.md` нет строки с dispatch на `commands/brief.md`, блока `### brief` нет, README.md/CLAUDE.md не содержат стадию; exit: 1; output~: `not ok [0-9]+ brief_docs: `

Ручные сценарии §1–7 остаются supplemental smoke-проверкой (не единственным доказательством DoD) —
основной гейт всех четырёх задач поведенческий/структурный bats (BRIEF-006, R2-003).

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Бриф разрастается в PRD | M | M | NFR-001 (target 60–100 строк, warning >120) + C1 считает строки |
| Секрет в inputs/ уходит в git | M | H | C5 secret-scan ДО любой мутации destination; `<private>` не разблокирует git-запись (Scenario 3, REQ-009) |
| Неинспектируемый файл копируется тихо | M | H | C5: `scan=unsupported` → `brief=blocked reason=scan_unsupported`, exit 1, override-флага нет в MVP (REQ-010, Scenario 4) |
| Кандидат и destination расходятся (LLM дописывает бриф после публикации) | M | H | C6: единственный путь публикации — helper; prompt в `briefs/` не пишет (клауза C7 `brief-helper-publish`); при отказе destination не создаётся, кандидат остаётся в `tmp/` |
| Дублирование с inputs-registry S-NN | L | M | `briefs/<topic>/inputs/` canonical только для brief-стадии (Phase 0 читает как внешние источники); при создании spec конвенция sdd-openspec-parity не меняется — SDD копирует выбранные источники в `specs/<topic>/inputs/`, присваивает S-NN и валидирует `inputs/...`-пути; прямые ссылки `## Sources` на `briefs/.../inputs` НЕ заменяют обязательную canonical copy (см. `specs/sdd-openspec-parity/design.md` § Sources registry) |
| grep-эвалы проверяли наличие текста, не поведение | M | M | закрыто: все четыре Eval — bats с якорями `output~:`; prompt-клаузы — только через C7 (`assert_clause` + `assert_clause_load_bearing`), голый grep запрещён (BRIEF-006, R2-003) |
| S7 разъезжается с диспетчером S1 | M | H | C5 потребляет S1-C5 дословно (общие элементы не переопределяются); Task 1 `Blocked-by: svp-interview-upgrade#4`; расхождение ловит `test_mb_secret_scan_brief_input.bats` (паритет паттернов и меток) |

## Cross-slice requests (правки в чужих спеках — не делаются здесь)

| # | Адресат | Запрос | Статус / Основание |
|---|---|---|---|
| X-01 | `svp-interview-upgrade` (S1) | Регистрация внешних клауз в `MB_DISCUSS_CLAUSES` из тест-файла потребителя, без правки харнесса | **SATISFIED** — S1 revision 3 §C9 явно разрешает потребителю (назван `svp-brief`) дописывать `MB_DISCUSS_CLAUSES+=("<record>")` после `load` (`svp-interview-upgrade/design.md` §C9); дальнейших правок S1 не требуется |
| X-02 | `svp-interview-upgrade` (S1) | `**Eval:**`-строки tasks.md несут `output~:`-якоря S2-C1 на gated | **SATISFIED** — все шесть Eval S1 revision 3 несут `output~:`-якоря (`svp-interview-upgrade/tasks.md`); действий больше не остаётся |
| X-03 | `svp-interview-upgrade` (S1), контракт C5 | Зафиксировать **исполнимое правило инспектируемости**: «сканируемым в MVP считается readable regular file без NUL-байтов, строго декодируемый как UTF-8; NUL → `binary`; ошибка UTF-8-декода → `unsupported_type`; внешние extractor'ы не вызываются; бинарный контейнер (PDF/DOCX) → `scan=unsupported`». Сейчас S1-C5 перечисляет reason'ы `unreadable|binary|unsupported_type`, но не задаёт алгоритм классификации — потребитель вынужден гадать, PDF ли scannable. До принятия S7 выравнивается на действующее «binary → unsupported» (Scenario 1 = `PRD.md`) | R3-005, S1-C5 § reason enum |

## Open questions

- `--from-file`/`--no-analyze` без LLM-анализа (не путать с `--request-file` из C0, который лишь
  меняет источник текста запроса, но анализ всё равно выполняется) — решить после первого прогона
  (context Open Questions).
