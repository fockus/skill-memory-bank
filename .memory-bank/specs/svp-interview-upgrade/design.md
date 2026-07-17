# Design: svp-interview-upgrade

> Слайс S1 группы `sdd-vision-pipeline`. Дизайн по D-05: контракты и Eval-декларации — здесь,
> код эвалов пишется первым шагом каждой задачи в `/mb work` (red → implement → green).
> Обязательное чтение перед планированием/ревью: `context/svp-interview-upgrade-interview.md`
> и родительский `context/sdd-vision-pipeline-interview.md` (D-29).
> Ревизия 2 (2026-07-17): закрыты находки spec-ревью SVP-IU-001…010 — сценарии на все REQ,
> Eval переведены на bats-контракты, контракты secret-scan/estimate/artifact-check зафиксированы
> полностью, восстановлены NFR-002 и родительские варианты decompose/MVP (D-10/D-12), добавлен
> REQ-020 (fast-to-code bypass, D-11, ревью SVP-012) и v2-поля задач по грамматике S2-C1.
> Ревизия 3 (2026-07-17): закрыт круг 2 (SVP-IU-002/003/005, R2-001…003) — добавлен C9
> (prompt-contract harness: section-scoped clause-ERE + negation-мутации вместо co-occurrence),
> C10 (строка глоссария в реальном writer'е `mb-context.sh`), C4 получил каноническую
> машинно-парсимую грамматику транскрипта с reason-кодами, C5 стал единым диспетчером
> `--policy transcript|brief-input` (метки паттернов, порядок находок, `scan=unsupported`),
> red-условия переписаны под eval-first (S2-C6), плюс смысловая находка D-18-FACT-FINDING
> (REQ-055/056 — параллельный fact-finding фронтира + честная деградация).

## Architecture

Слайс меняет **интервью-фазу** пайплайна. Четыре вида артефактов:

1. **Prompt-слой** — `commands/discuss.md` (основной seam): новые секции «Interview plan», «Final gate», «Size triage», «Transcript», «Glossary», «Self-interview», «Batch mode», «Fast-to-code bypass». Правки аддитивны — существующие 5 фаз и grilling rules 1–10 сохраняются, новые правила встраиваются в тот же нумерованный список (11+) и в Write & finalize.
2. **Скрипт-слой** (новый код, все — самостоятельные детерминированные CLI, без внешней зависимости на другие слайсы/спеки):
   - `scripts/mb-estimate-check.sh` — контракт C1; база, которую S2-C3 расширяет флагом `--spec`
     (тот же key=value stdout-стиль и exit 0/1/2, см. `specs/svp-sdd-core/design.md` C3).
   - `scripts/mb-secret-scan.sh` — контракт C5; канонический сканер-диспетчер (паттерны
     single-sourced из `scripts/mb-import.py`), создаётся целиком здесь; политику `transcript`
     реализует T4, политику `brief-input` — потребитель S7 в том же файле (C5 § Владение).
   - `scripts/mb-interview-artifact-check.sh` — контракт C8 (реализует NFR-002); режим `plan`
     создаётся здесь T1, режим `transcript` добавляется T4 в том же файле.
   - `scripts/mb-context.sh` — **существующий** реальный writer выдачи `/mb context`
     (`scripts/mb-context.sh:33-89`); T5 добавляет в него одну строку-указатель на глоссарий
     (контракт C10). `commands/mb.md` только маршрутизирует и выдачу не собирает — поэтому
     prompt-правкой REQ-017/018 закрыть нельзя (ревью R2-002).
3. **Шаблон-слой** — `references/templates.md`: шаблоны interview-plan файла, транскрипта, глоссария, Assumptions-блока; `templates/`-бандл банка не трогаем (glossary.md создаётся лениво при первом термине, как CONTEXT.md в domain-modeling).
4. **Тест-контракт-слой** — `tests/bats/lib/discuss_contract.bash` (новый общий bats-хелпер, C9):
   единственный допустимый способ проверять prompt-контракт. Создаётся T1, переиспользуется
   T2–T6 (DRY: пять задач проверяют один и тот же prompt-файл).

Seam-решение (D-17 applied): максимально высокий seam — CLI-контракты скриптов (bats-тестируемые) + **section-scoped clause-контракт** prompt-файла через C9 (детерминированный; LLM-исполняемый prompt не запускается в тестах — см. Risks). Новых Python-модулей нет; parser tasks.md не трогается (это S2).

## Interfaces — контракты (декларации, код в work-фазе)

### C1. `scripts/mb-estimate-check.sh <context-file> [--spec-budget 1000000]`

- **Вход**: context-файл с frontmatter:
  ```yaml
  estimated_tokens:
    total: <int>
    breakdown:
      shell_scripts:          {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
      prompt_changes:         {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
      python_modules:         {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
      test_files:             {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
      docs_pages:              {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
      external_integrations:  {count: <int>=0, unit_tokens: <int>=0, subtotal: <int>=0}
  ```
  Категории breakdown — ровно эти шесть ключей, 1:1 с рубрикой C3. Каждая: `subtotal = count *
  unit_tokens`; `total = sum(subtotal)` по всем шести.
- **`--spec-budget`** (R3-002): положительное целое, default `1000000`; `0`, отрицательное или
  нецелое → usage error, exit 2. Эффективный порог near/over = `spec_budget`.
- **Валидация входа**: отсутствует `estimated_tokens` → `estimate=missing`; отсутствует ключ
  категории, нецелое значение, `subtotal != count*unit_tokens` или `total != sum(subtotal)` →
  `estimate=malformed`.
- **Пороги** (D-13, спека ~1M; одна целочисленная формула для ЛЮБОГО budget — закрывает R3-002):
  `near_lower = floor(spec_budget * 9 / 10)`. `total < near_lower` → `estimate=ok`;
  `near_lower ≤ total ≤ spec_budget` → `estimate=near` (advisory, не блокирует);
  `total > spec_budget` → `estimate=over` (hard). При дефолтном `spec_budget=1000000`:
  `near_lower=900000`, near = `[900000, 1000000]` (обратно совместимо с ревизией 3).
- **Выход (ok/near/over)**: одна key=value строка на stdout:
  `estimate=ok|near|over spec.total=<N> spec_budget=<N>`.
- **Error-контракты — детерминированный stderr и порядок (закрывает R3-003):**
  - usage (неизвестный флаг, невалидный `--spec-budget`, лишний/отсутствующий позиционный аргумент):
    stdout ПУСТ; stderr ровно `error=usage`; exit 2.
  - нечитаемый вход: stdout ПУСТ; stderr ровно `<file>:0:unreadable`; exit 2.
  - missing estimate: stdout `estimate=missing spec.total=0 spec_budget=<N>`; stderr
    `<file>:0:estimated_tokens:missing`; exit 2.
  - malformed field: stdout `estimate=malformed spec.total=<N|0> spec_budget=<N>`; stderr
    `<file>:<line>:<field>:malformed`; exit 2. При нескольких malformed-полях находки сортируются
    по возрастанию `<line>`.
- **Exit codes**: 0 — ok/near; 1 — over; 2 — missing/malformed/unreadable/usage.
- **Легаси/scope этого слайса**: сравнивается только spec-total (REQ-011). Пер-задачные/пер-этапные
  бюджеты (`Budget:`/`Stage:` в tasks.md) добавляет `--spec <topic>`-режим в S2 (`svp-sdd-core`
  design.md C3) — этот слайс его не реализует и не резервирует имя флага.

### C2. Interview-plan файл `<bank>/tmp/interview-plan-<topic>.md`

- Секции: `## Inherited decisions (do not re-ask)` (из parent_context), `## Topics` (строки `- [ ] <тема>` / `- [x]`), `## Discovered mid-interview` (append).
- Контракт закрытия: генерация артефактов разрешена только при нуле `- [ ]` в `## Topics` + `## Discovered` (REQ-002); проверяется кодово скриптом C8 (`plan`-режим, `--require-closed`) перед генерацией — не только вручную агентом.
- Структура и обязательные заголовки валидируются C8 независимо от контракта закрытия (NFR-002).

### C3. Рубрика оценки объёма (текст в discuss.md, REQ-008)

Таблица коэффициентов — категории идентичны breakdown-ключам C1 (без этого совпадения C1 не
может валидировать оценку):

| Категория (`breakdown.*`) | ~Токенов/единица |
|---|---|
| `shell_scripts` (новый скрипт) | 15 000 |
| `prompt_changes` (правка команды/prompt) | 8 000 |
| `python_modules` (новый Python-модуль) | 25 000 |
| `test_files` (тест-файл) | 10 000 |
| `docs_pages` (docs-страница) | 5 000 |
| `external_integrations` (интеграция с внешним API) | 30 000 |

Стартовые значения; калибровка — открытый вопрос, обновляются по фактам первых спек (см. Open
questions). Запись: frontmatter `estimated_tokens` с breakdown по этим шести ключам; валидирует C1.

### C4. Транскрипт `context/<topic>-interview.md` — каноническая грамматика

Машинно-парсимая форма (валидирует C8 `transcript`-режим; реализатор не угадывает маркеры):

```markdown
# Interview transcript: <topic> (<YYYY-MM-DD>[, <free text>])

<опциональная проза и опциональные секции ## … — например «## Предыстория», «## Research digest»>

## Унаследовано[ <free text>]
<унаследованные решения — только для JIT-интервью слайса>

## Q&A

**Q<N> (<tag>).** <вопрос; ответ допускается в этом же блоке цитатой «…»>
**A<N>.** <ответ близко к дословному> → **D-NN**. Отклонено: <альтернативы>

**Финальный гейт[, круг <M>].** <вопрос «есть ли что добавить?»>
**Ответ.** <ответ пользователя>
```

Нормативные правила грамматики (каждое = один reason-код C8):

1. **Заголовок**: первая непустая строка. Проверка **двухступенчатая** — коды не пересекаются:
   (а) строка обязана совпасть с формой `^# Interview transcript: <topic> \((?<head>[^,)]+)(,[^)]*)?\)$`
   → не совпала → `missing_title` (и `bad_date` не выдаётся);
   (б) захваченный `<head>` обязан быть ISO-8601 `\d{4}-\d{2}-\d{2}` **и** календарно валидной
   датой → иначе `bad_date`.
   Без этого разделения реализация не детерминирована: прототип ревизии 3, включивший дату прямо
   в regex заголовка, на фикстуре с датой `17-07-2026` выдал `missing_title` вместо `bad_date`.
2. **`## Q&A`** — ровно одна секция → `missing_qa_section` / `duplicate_qa_section`.
3. **`## Унаследовано…`** — обязательна и обязана стоять до `## Q&A` **только** при
   `--require-inherited` (JIT-интервью, у контекста есть `parent_context`) →
   `missing_inherited` / `inherited_after_qa`. Без флага секция опциональна: корневое интервью
   ничего не наследует (`context/sdd-vision-pipeline-interview.md` её не имеет).
4. **Q-блок** = от строки `^\*\*Q<N>( \([^)]*\))?\.\*\* ` до следующей Q-строки, строки
   финального гейта или следующего `^## `. Требуется ≥1 блок (`no_questions`); номера строго
   возрастают начиная с 1 (`q_number_out_of_order`, `q_number_duplicate`); **пропуски номеров
   легальны** (снятый вопрос).
5. **Ответ в Q-блоке (строго, SVP-IU-005)**: требуется строка `^\*\*A<N>\.\*\* ` с тем же `<N>`.
   В режиме `--legacy-live-fixture` дополнительно допускается строка того же блока, совпавшая с
   `Ответ голосом \(суть\): «[^»]+»` **или** `пользователь: «[^»]+»` (у Q4/Q6/Q7 родительского
   интервью ответ голосом вписан прямо в Q-блок этими двумя формами,
   `context/sdd-vision-pipeline-interview.md:34,39,41`). Иначе → `answer_missing`. **Произвольная
   цитата `«…»` где угодно в блоке — в самом вопросе или в отклонённой альтернативе — ответом НЕ
   считается** (закрывает SVP-IU-005: раньше любая цитата пропускала Q-блок без ответа).
6. **Решение в Q-блоке**: ≥1 ссылка `\*\*([A-Za-z0-9]+-)?D-[0-9]{2,}\*\*` → иначе
   `decision_missing`.
7. **Отклонённые альтернативы (строго per-Q для новых транскриптов, SVP-IU-005)**: каждый Q-блок,
   несущий решение (`**D-NN**`), обязан содержать до следующей Q-строки / гейта / `^## ` строку
   `Отклонено: <none|text>` **или** `Rejected: <none|text>` (`none` — явная запись «альтернатив
   нет») → иначе `<file>:<line>:rejected_alternatives_missing` (раньше хватало ОДНОГО элемента на
   весь файл, и остальные решения теряли отклонённые). В режиме `--legacy-live-fixture` правило
   ослабляется до файл-уровня (≥1 элемент: inline `Отклонено:`/`Rejected:` в любом Q-блоке **либо**
   секция `## Отклонённые альтернативы…`) — как у родительского транскрипта, где отклонённые собраны
   отдельной сводной секцией (`sdd-vision-pipeline-interview.md:92`). **Честная граница**:
   «альтернативы упомянуты именно там, где решение их отклонило» (REQ-005) кодом не проверяется —
   полноту принимают ручной сценарий §8 и spec-review.
8. **Финальный гейт**: ≥1 строка `^\*\*Финальный гейт(, круг <M>)?\.\*\* ` (`missing_final_gate`),
   за каждой — строка `^\*\*Ответ\.\*\* ` в её блоке (`gate_answer_missing`). При >1 гейте каждый
   обязан нести `, круг <M>` со строго возрастающим `M` (`gate_round_missing`,
   `gate_round_out_of_order`). **Несколько гейтов легальны и обязательны по REQ-004** (дополнение
   на гейте → новая итерация → гейт повторяется до явного «нет»); гейты **чередуются** с
   Q-блоками — правило «сначала все вопросы, потом гейт» НЕ вводится (живой образец:
   `sdd-vision-pipeline-interview.md:72` — гейт круга 1 стоит до Q15 на `:75`).
9. **Регресс-гейт грамматики**: оба существующих транскрипта —
   `context/sdd-vision-pipeline-interview.md` и `context/svp-interview-upgrade-interview.md` —
   обязательные **позитивные фикстуры** T4: грамматика принята ровно в том виде, в каком D-29
   применён вручную 2026-07-17. Валидатор, отвергающий их, считается сломанным, а не строгим.

Прочее по транскрипту:

- Перед атомарной записью в git-путь: secret-scan (C5) над кандидатом; структурная валидация (C8).
- `<private>`-фрагменты сохраняются как есть в тексте — их редактирует существующий index/search-слой (REQ-006). Secret-scan (C5) сканирует их **как обычный текст** и НЕ пропускает секрет под `<private>` в git (R3-001): index/search-приватность и secret-gate — ортогональны.

> **Отклонение от `proposed_fix` ревью (SVP-IU-005) — по фактам репозитория.** Предложенные
> маркеры `### Q<N>: <question>`, `**Answer:**`, `**Decision:**`, `**Rejected alternatives:**`,
> `## Final gate` и требования «`## Унаследовано` обязательна» + «ровно один Final gate»
> отклонены: ни один из этих маркеров не встречается ни в одном живом транскрипте
> (`grep -c '^### Q[0-9]' → 0`, `grep -c '^## Final gate' → 0`), корневой транскрипт секции
> «Унаследовано» не имеет (`grep -c → 0`), а требование «ровно один Final gate» прямо
> противоречит REQ-004 и факту двух гейтов в `sdd-vision-pipeline-interview.md`
> (`grep -c '^\*\*Финальный гейт' → 2`). Существо находки — «грамматика недоопределена, нужны
> точные маркеры + негативные фикстуры на каждый обязательный элемент» — принято полностью
> (правила 1–8 + reason-коды C8 + шесть негативных фикстур T4).
>
> **Круг 3 (SVP-IU-005 PARTIAL) — ужесточено без изменения живых транскриптов.** Правило 5 теперь
> требует `**A<N>.**`, а произвольную цитату `«…»` ответом не считает; правило 7 — per-Q
> `Отклонено:/Rejected:` для каждого решения. Совместимость с двумя живыми транскриптами сохранена
> НЕ ослаблением грамматики, а явным ограниченным режимом `--legacy-live-fixture` (C8), допустимым
> ТОЛЬКО для `context/sdd-vision-pipeline-interview.md` и `context/svp-interview-upgrade-interview.md`;
> для него легализованы ровно две измеренные формы голосового ответа
> (`Ответ голосом (суть): «…»`, `пользователь: «…»`) и файл-уровень отклонённых. Новые транскрипты
> идут строгим путём (без флага). Транскрипты-протоколы не редактируются (принятое отклонение круга 2 №6).

### C5. `scripts/mb-secret-scan.sh --policy <transcript|brief-input> <file>`

**Владение (закрывает SVP-IU-003 / SVP-BRIEF-002).** S1 создаёт исполняемый файл, диспетчер
`--policy` и политику `transcript` (T4). Политику `brief-input` реализует потребитель S7
(`svp-brief`) в этом же файле: S7 `blocked_by: [svp-interview-upgrade]`, его Task 1 берёт в Scope
`scripts/mb-secret-scan.sh` + `tests/bats/test_mb_secret_scan_brief_input.bats`. Общие элементы
контракта (имя, аргументы, stdout-строки, метки, порядок находок, exit-коды) S7 **не**
переопределяет. `sdd-openspec-parity` **не владеет** этим CLI и общего сканера не создаёт: его T6 —
внутренняя проверка `mb-spec-validate.sh` над `specs/<topic>/inputs/`
(`specs/sdd-openspec-parity/tasks.md:119-136`); единственная связь — общий источник паттернов
`scripts/mb-import.py`.

- **Аргументы**: `--policy <name>` обязателен; ровно один `<file>`. Отсутствующий, неизвестный или
  ещё не реализованный `--policy`, отсутствующий/лишний `<file>`, неизвестный флаг → **usage
  error**: stdout пуст, usage-текст на stderr, exit 2. До поставки S7 `--policy brief-input` —
  именно такой usage error (stderr: `policy_not_implemented`). Неизвестная политика никогда не
  трактуется как «чисто».
- **Паттерны**: два класса, single-source из `scripts/mb-import.py` (`EMAIL_RE:39`, `APIKEY_RE:41`
  — `sk-…`, `sk-ant-…`, `Bearer <long>`, `gh[pousr]_<long>`). Вторая регулярка не заводится; тест
  проверяет паритет с `mb-import.py` (тот же риск-митигейшн, что в `sdd-openspec-parity`
  design.md:121).
- **Метки** (закрывает R2-003): `pattern` — ровно `email` или `api_key`, 1:1 с
  `EMAIL_RE`/`APIKEY_RE`. Иные значения (имя переменной, сам regex, совпавший текст) запрещены.
- **Выход**: stdout — **ровно одна** строка: `scan=clean` | `scan=blocked` | `scan=unsupported`.
  - `blocked` → на stderr по одной строке на находку: `<file>:<line>:<pattern>`; порядок —
    по возрастанию `(line, column)`; несколько находок на одной строке дают несколько строк
    stderr; **сам секрет никогда не печатается** ни в stdout, ни в stderr.
  - `unsupported` → одна строка stderr `<file>:0:<reason>`, `reason` ∈ {`unreadable`, `binary`,
    `unsupported_type`}.
- **Классификация инспектируемости — детерминированный алгоритм (закрывает X-03).** Паттерн-скан
  выполняется ТОЛЬКО над scannable-файлом; классификатор общий для обеих политик и проверяется в
  таком порядке (первое сработавшее условие определяет исход):
  1. не readable regular file (нет файла / каталог / нет прав чтения) → `scan=unsupported`, reason
     `unreadable`;
  2. содержит хотя бы один NUL-байт (`\x00`) → `scan=unsupported`, reason `binary`;
  3. известный бинарный контейнер по magic-сигнатуре в первых байтах (PDF `%PDF-`, ZIP/OOXML
     `PK\x03\x04` — DOCX/XLSX/PPTX, gzip `\x1f\x8b`, tar/7z/прочие архивы) → `scan=unsupported`,
     reason `unsupported_type`;
  4. содержимое **не** декодируется целиком как UTF-8 → `scan=unsupported`, reason `unsupported_type`;
  5. иначе (readable regular file, без NUL, не контейнер, валидный UTF-8) → **scannable** →
     паттерн-скан продолжается (`scan=clean`/`scan=blocked`).
  Всякий не-scannable исход = `scan=unsupported`, exit 2 — правило **подтверждает** действующее
  «binary → unsupported» (S7 ключует по исходу `scan=unsupported`, не по reason), а не меняет его.
- **Exit codes**: 0 — clean; 1 — blocked; 2 — unsupported **или** usage error. Два случая exit 2
  различимы по stdout: `scan=unsupported` против пустого stdout.
- **Политика `transcript`** (владеет S1; **critical R3-001 — `<private>` НЕ пропускает секрет в
  git**): сканируется **сырой текст, включая содержимое `<private>…</private>`**. `<private>` и
  `<!-- mb-secret-ok -->` **не подавляют** находки и **не являются** разрешением записать credential
  в git-tracked транскрипт — они влияют только на index/search-редакцию (REQ-006), а не на
  secret-gate (`rules/RULES.md` прямо предупреждает: `<private>` защищает index/search, «NOT git
  diff»). Номера строк в находках — строки исходного файла (маскирование не применяется, поэтому
  сдвига нет). Это выравнивает `transcript` с соседней политикой `brief-input` и owner-контрактом S7
  (`svp-brief/design.md:147-170`): под `<private>` секрет в git не попадает ни в одной политике.
  Транскрипт строже курируемых `inputs/`: pragma-байпаса секретов нет. Нечитаемый/бинарный файл →
  `scan=unsupported`, exit 2.
- **Политика `brief-input`** (контракт фиксирует S1, реализует S7): `<private>` находку **не
  подавляет** (бриф-исходники не курируются пользователем построчно, `<private>` — механизм
  index/search, а не разрешение писать секрет в git); `<!-- mb-secret-ok -->` на строке-находке
  или на строке непосредственно над ней подавляет **только** эту находку (та же семантика, что
  `sdd-openspec-parity` REQ-018); бинарный/нечитаемый/неподдерживаемый тип → `scan=unsupported`,
  exit 2 — S7 требует явного решения пользователя, без тихого копирования.
- **Запись transcript (C4) — двухфазный write**: курируемый транскрипт сначала пишется кандидатом
  в `<bank>/tmp/interview-transcript-<topic>.candidate.md`; C5 сканирует кандидата; exit 0 →
  кандидат атомарно перемещается (`mv`) в `context/<topic>-interview.md`; exit 1/2 → целевой файл
  не создаётся/не изменяется, находки/ошибка показываются пользователю для очистки или
  `<private>`-разметки (REQ-007).

> **Отклонение от `proposed_fix` ревью (SVP-IU-003/SVP-BRIEF-002) — по решению оркестратора
> волны.** Ревью предлагало имя политики `inputs`; зафиксировано `brief-input` — так требует
> кросс-слайсовый дизайн единого диспетчера, доведённый оркестратором от umbrella-фиксера
> (`--policy <transcript|brief-input>`), и так имя не путается с внутренним `inputs/`-сканом
> `sdd-openspec-parity` (другой слайс, другой механизм). Существо находки — «S1 владеет CLI,
> потребитель зовёт ровно этот контракт, ложное владение убрано» — принято полностью; выравнивание
> S7 на `--policy brief-input` заявлено в `cross_slice_requests`.

### C6. Флаги `/mb discuss`

`` /mb discuss <topic> [--batch] [--self "<brief>" [--auto]] ``

- `--batch` — frontier-раунды (REQ-015/016/022) **и** fact-finding фронтира (REQ-055/056, D-18);
  совместим с `--self` (меняет только размер фронтира вопросов на раунд, не режим ответа).
- **Fact-finding фронтира** (D-18, ревизия 3): перед тем как задать раунд, агент собирает факты
  под каждый разблокированный вопрос фронтира (тот же источник, что Phase 0: код-граф /
  semantic-search / grep, `mb-researcher` — только для внешних тем) и предъявляет рекомендацию
  REQ-015 со ссылкой на найденный факт.
  - Хост даёт диспатч сабагентов → вопросы фронтира расследуются **параллельными** сабагентами,
    по одному на вопрос (REQ-055).
  - Хост его не даёт (`platform_limited` содержит `subagents` — закрытый словарь
    `specs/adapter-parity/design.md:143-145`) → **тот же** fact-finding выполняется
    последовательно основным агентом, и деградация сообщается пользователю одной строкой
    (REQ-056). Тихо пропустить fact-finding запрещено (honest degradation, AGR-013).
  - Без `--batch` дефолт не меняется: по одному вопросу за раз, без параллельного диспатча (D-18).
- `--self "<brief>"` — self-interview (REQ-012/013): агент отвечает на вопросы сам из брифа;
  **без** `--auto` всегда требует пакетное подтверждение assumptions перед генерацией (REQ-013).
  Пустой/whitespace-only brief — usage error **до** записи любого файла (interview-plan, context,
  tmp-кандидаты), exit-код и сообщение как у прочих usage-ошибок команды.
- `--auto` — только вместе с `--self`; без `--self` — usage error до записи файлов (REQ-014).
  `--self --auto` не блокирует на assumptions, но продолжает генерацию только после успешного
  прохождения детерминированных проверок этого слайса (C1/C5/C8); ревизия assumptions предлагается
  пользователю после завершения, не до.
- Существующий `draft`-context для темы → флаги возобновляют сохранённый interview-plan (C2) вместо
  повторного старта; существующий `ready`-context → сохраняется уже принятое поведение
  edit/overwrite/cancel текущей команды (флаги не меняют этот выбор).
- Без флагов — поведение = текущее + план/гейт/триаж/транскрипт/глоссарий (quality-default, D-11),
  описанные в этом дизайне как всегда включённые non-flag-gated шаги.

### C7. Реестр декомпозированных спек (временная форма до S4)

- Запись в `backlog.md ## Ideas` через `mb-idea.sh` с префиксом заголовка `[SPEC:<group>]` — переживёт миграцию в стейт-машину S4 без потери данных (S4 распарсит префикс в поле).

### C8. `scripts/mb-interview-artifact-check.sh <plan|transcript> <file> [--require-closed] [--require-inherited] [--legacy-live-fixture]`

Реализует NFR-002 (детерминизм структурной проверки plan/transcript-артефактов кодом, не LLM).

- **Режим `plan`** (создаёт T1): валидирует `<bank>/tmp/interview-plan-<topic>.md` по контракту C2
  — обязательные заголовки `## Inherited decisions (do not re-ask)`, `## Topics`,
  `## Discovered mid-interview` присутствуют в этом порядке; строки тем — только `- [ ] …` /
  `- [x] …` (никакой другой формат буллетов под `## Topics`/`## Discovered`); с флагом
  `--require-closed` — ноль `- [ ]` в обеих секциях, иначе invalid.
  Reason-коды: `missing_section`, `section_out_of_order`, `bad_bullet`, `open_topics`.
- **Режим `transcript`** (добавляет T4 в тот же файл): валидирует `context/<topic>-interview.md`
  по грамматике C4, правила 1–8. Reason-коды: `missing_title`, `bad_date`, `missing_qa_section`,
  `duplicate_qa_section`, `missing_inherited`, `inherited_after_qa`, `no_questions`,
  `q_number_out_of_order`, `q_number_duplicate`, `answer_missing`, `decision_missing`,
  `rejected_alternatives_missing`, `missing_final_gate`, `gate_answer_missing`, `gate_round_missing`,
  `gate_round_out_of_order`, `legacy_fixture_forbidden`.
- **`--legacy-live-fixture`** (SVP-IU-005): ослабляет правила C4-5 (answer) и C4-7 (rejected) до
  legacy-семантики (см. C4). Допустим **только** для двух зафиксированных regression-фикстур —
  `context/sdd-vision-pipeline-interview.md` и `context/svp-interview-upgrade-interview.md`; для
  любого другого `<file>` → usage error `<file>:0:legacy_fixture_forbidden`, exit 2. Разрешён только
  с режимом `transcript`.
- **Флаги по режимам**: `--require-closed` допустим только с `plan`; `--require-inherited` и
  `--legacy-live-fixture` — только с `transcript`; иная комбинация → usage error, exit 2.
- **Выход**: stdout — `artifact=ok|invalid open_topics=<N>` (`open_topics` только для `plan`,
  иначе `0`); stderr на невалидность — одна строка на проблему: `<file>:<line>:<reason>`, где
  `<reason>` — ровно один из reason-кодов выше; порядок строк — по возрастанию `(line, reason-order)`,
  где `reason-order` — порядок reason-кодов в декларации режима выше (детерминизм при нескольких
  находках на одной строке, R3-003).
- **Error-контракты (R3-003):** usage → stdout ПУСТ, stderr ровно `error=usage`, exit 2; нечитаемый
  вход → stdout ПУСТ, stderr `<file>:0:unreadable`, exit 2.
- **Exit codes**: 0 — valid (и, для `plan --require-closed`, закрыт); 1 — структурно невалиден или
  (для `--require-closed`) остались открытые пункты; 2 — usage/read error.

### C9. `tests/bats/lib/discuss_contract.bash` — prompt-contract harness (создаёт T1)

Закрывает SVP-IU-002: **единственный** допустимый способ проверять prompt-контракт в этом слайсе.
Общий bats-хелпер (`load 'lib/discuss_contract'`), переиспользуемый T1–T6.

- **Clause table** — каждая нормативная клауза объявляется одной записью
  `<clause-id>|<extractor>|<extractor-arg>|<clause-ERE>|<topic-anchor-ERE>|<negation-sed>|<REQ-ID>`
  в массиве `MB_DISCUSS_CLAUSES` внутри хелпера. `<extractor>` ∈ {`mb_section`, `mb_rule`}.
  `<topic-anchor-ERE>` — то, о чём клауза (тематические слова); `<clause-ERE>` — что именно
  предписано (тема + модальность + объект). Инвариант: `clause-ERE` строго сильнее
  `topic-anchor-ERE`; проверяется механически (см. `assert_clause_load_bearing`).
- `mb_section <file> <heading-ERE>` — печатает блок от **единственного** заголовка, совпавшего с
  `^#{1,6} *<heading-ERE> *$`, до следующего заголовка того же или более высокого уровня;
  exit 1 с `section_absent` / `section_duplicated`.
- `mb_rule <file> <n>` — блок grilling-правила `<n>`: от `^<n>\. \*\*` до следующего
  `^[0-9]+\. \*\*` или следующего заголовка; exit 1 с `rule_absent`.
- `assert_clause <file> <clause-id>` — извлекает блок объявленным экстрактором и требует **ровно
  одну** строку блока, совпавшую с `<clause-ERE>`; иначе fail
  `clause=<id> req=<REQ-ID> reason=absent|ambiguous`. Проверка **скоупится блоком**, поэтому
  совпадение в другой части файла клаузу не закрывает.
- `assert_clause_load_bearing <file> <clause-id>` — **механический анти-vacuity гейт** (главный
  барьер против co-occurrence). Применяет `<negation-sed>` к копии файла и требует ОДНОВРЕМЕННО:
  1. `assert_clause` на мутанте **падает** с тем же `clause=<id>` — иначе fail
     `clause=<id> reason=vacuous` (клауза не реагирует на изменение поведения);
  2. блок мутанта **всё ещё** совпадает с `<topic-anchor-ERE>` — иначе fail
     `clause=<id> reason=mutation_removed_topic` (мутация удалила тему, а не поведение — такая
     мутация ничего не доказывает).
  Пара (1)+(2) и есть доказательство `clause-ERE ⊋ topic-anchor-ERE`: клауза обязана падать от
  ослабления нормативной части при живой теме. **Голую клаузу пройти нельзя ни при какой мутации**
  (при `clause-ERE` = `topic-anchor-ERE` условия (1) и (2) взаимоисключающи): мутация, не убравшая
  слово, оставляет клаузу выполненной → отказ `reason=vacuous`; мутация, убравшая слово, уносит
  вместе с ней тему → отказ `reason=mutation_removed_topic`. Оба исхода — отказ; проверено
  исполнением прототипа (ревизия 3): голая клауза `question` для rule 6 → exit 1
  `reason=vacuous`, поведенческая клауза rule 6 → exit 0.
- **Обязательство**: каждый prompt-Eval вызывает для **каждой** своей клаузы обе функции.
  Голый `grep -q <слово>` и co-occurrence двух независимых слов запрещены как assertion-гейт.
- **Регистрация клауз потребителями (X-01, потребитель: S7 `svp-brief`)**: функции харнеса
  файл-параметричны (`assert_clause <file> <id>`), и внешний слайс МОЖЕТ регистрировать свои клаузы
  для СВОЕГО prompt-файла, дописывая записи в `MB_DISCUSS_CLAUSES` из собственного тест-файла ПОСЛЕ
  `load 'lib/discuss_contract'` (`MB_DISCUSS_CLAUSES+=("<record>")`) — харнес при этом не
  редактируется, второй prompt-checker не заводится (что этим же контрактом и запрещено). Инварианты
  для чужих клауз те же: обе функции на каждую клаузу, анти-vacuity обязателен; коллизии
  `<clause-id>` между слайсами запрещены — потребитель префиксует id своим слайсом (`brief_*`).
- **Почему одного «ровно одного совпадения» недостаточно** (проверено исполнением прототипа
  харнесса против `commands/discuss.md` при ревизии 3): grep считает **строки**, а grilling-правила
  в `discuss.md` — однострочные абзацы, поэтому голое слово `question` внутри блока rule 6 даёт
  ровно одно совпадение и `assert_clause` его пропускает. `reason=ambiguous` ловит только
  многострочные секции; единственный надёжный барьер — anchor + negation-мутация выше.

### C10. Строка глоссария в выдаче `/mb context` (`scripts/mb-context.sh`, закрывает R2-002)

- **Реальный writer** выдачи `/mb context` — `scripts/mb-context.sh` (core-файлы `:33-51`,
  планы `:53-64`, codebase-сводка `:66-89`); `commands/mb.md` только маршрутизирует. Поэтому
  строка глоссария добавляется в скрипт — T5 обязан иметь его в Scope, prompt-правкой REQ-017
  не закрывается.
- **Поведение**: после блока core-файлов и до `--- Active plans ---` печатается **ровно одна**
  строка `Glossary: <path-relative-to-bank>` тогда и только тогда, когда `<bank>/glossary.md`
  существует как обычный файл. Symlink → skip (тот же guard, что для core-файлов, `:38-41`),
  `mb_canonical_under` guard (`:42-46`) сохраняется.
- **Указатель, не содержимое**: файл глоссария в выдачу не конкатенируется (NFR-001 —
  токен-экономия).
- **Регресс**: `glossary.md` отсутствует → выдача **байт-идентична** текущей.
- Скрипт read-only и идемпотентен: банк не создаётся и не меняется (повторный вызов не пишет
  `glossary.md`; ленивое создание — обязанность prompt-слоя при разрешении термина).

### C11. `scripts/mb-interview-artifact-write.sh` — детерминированный writer файловых эффектов (закрывает SVP-IU-002)

Design (правило Eval №4) требует ответственного детерминированного helper на КАЖДЫЙ файловый эффект,
но ревизия 3 оставила сами записи (install плана, атомарную публикацию транскрипта) prompt-слою —
C1/C5/C8 только **читают**/сканируют, а не производят атомарную запись. Проверка «target не изменён»
в тесте самого сканера не доказывает production-orchestration. Выносим объективные записи в CLI.

```
bash scripts/mb-interview-artifact-write.sh install-plan       --mb <bank> --topic <topic> --candidate <file>
bash scripts/mb-interview-artifact-write.sh publish-transcript --mb <bank> --topic <topic> --candidate <file> [--require-inherited] [--legacy-live-fixture]
```

- `install-plan` (создаёт T1): вызывает C8 `plan` над `--candidate`; при `artifact=ok` **атомарно**
  (`rename`, та же ФС `<bank>/tmp/`) заменяет `<bank>/tmp/interview-plan-<topic>.md`.
- `publish-transcript` (добавляет T4 в тот же файл): вызывает C5 `--policy transcript` **и** C8
  `transcript` (с прокинутыми `--require-inherited`/`--legacy-live-fixture`) над `--candidate`; при
  обоих success **атомарно** заменяет `<bank>/context/<topic>-interview.md`.
- **Инвариант**: любой failed scan/check оставляет target **byte-identical** (снимок до/после — часть
  fixture-теста); частичной записи нет.
- **stdout**: `artifact_write=installed kind=plan|transcript`. **Exit**: 0 — installed; 1 — контент
  отклонён (scan blocked / check invalid); 2 — usage / I/O. При exit 1/2 stdout ПУСТ, причина —
  форвардится из stderr C5/C8.
- Пишет только оркестратор (D-23); идемпотентность не требуется (перезапись целевого — суть операции).

### C12. `scripts/mb-glossary.sh` — детерминированный upsert строки глоссария (закрывает SVP-IU-002)

REQ-017 (запись термина в `glossary.md`) — файловый эффект; `mb-context.sh` (C10) только **читает**
указатель. Саму запись выносим в детерминированный helper, а не в prompt-суждение.

```
bash scripts/mb-glossary.sh upsert --mb <bank> --term-file <file> --definition-file <file>
```

- Термин/определение читаются **из файлов** (byte-safe, без потерь на квотировании); строка формата
  `<term> — <definition>` создаётся/обновляется **атомарно** (ленивое создание `glossary.md` при
  первом термине).
- **Конфликт (REQ-018-совместимо)**: тот же term с ДРУГИМ определением → stdout `glossary=conflict`,
  exit 1, файл **не меняется** (вызов вернёт конфликт, prompt-слой челленджит до записи требования).
- create / update (то же определение — `unchanged`) → stdout `glossary=created|updated|unchanged`,
  exit 0; usage / I/O → exit 2.

## Decisions

- Слайс-решения S1-D-01…07 + родительские D-04/09/10/11/12/18/22/29/31 — в context-файлах; здесь не дублируются.
- **S1-D-07** (ревизия 3, D-18-FACT-FINDING): fact-finding фронтира — параллельные сабагенты там, где хост даёт диспатч; иначе тот же fact-finding последовательно в основном агенте + явное сообщение о деградации (`platform_limited: subagents`). Дефолт без `--batch` — по одному вопросу, без параллельного диспатча. — Rejected: молчаливый пропуск fact-finding на хостах без сабагентов (нечестная деградация, AGR-013); отдельный флаг под fact-finding (D-18 связывает его с frontier-опцией, а не с новым переключателем).
- Ни один скрипт этого слайса не блокируется на завершённости соседних спек — все три CLI (C1/C5/C8) самодостаточны и создаются целиком внутри S1 (T1/T3/T4); S2/S4 расширяют их своими флагами, S7 — своей политикой `brief-input`, всё без изменения существующего вызова (Strangler Fig по факту расширения, не по факту "drop-in замены недостающей реализации").
- glossary.md — ленивое создание (первый разрешённый термин), не в `mb-init-bank.sh` (легаси-банки без миграции, D-26).

## Eval declarations (per task — код пишется в work-фазе, red → green)

Каждый Eval — путь к `tests/bats/test_*.bats` (репо-конвенция, `README.md:698`); файл создаётся
первым шагом задачи (red), затем реализация до green.

**Нормативные требования к Eval этого слайса (закрывают SVP-IU-002):**

1. **Prompt-backed Eval ОБЯЗАН** извлечь именованную секцию/правило и проверить каждую нормативную
   клаузу контракта как одну строку внутри этого же блока через C9 `assert_clause`.
2. **Каждая клауза ОБЯЗАНА** быть доказана load-bearing через C9 `assert_clause_load_bearing` со
   своей объявленной negation-мутацией.
3. **Голая проверка слова / co-occurrence двух независимых слов ЗАПРЕЩЕНА** как assertion-гейт.
4. **REQ с файловыми эффектами ОБЯЗАН** дополнительно вызывать ответственный детерминированный
   **writer**-helper на фикстурном банке и доказывать реальный target ДО/ПОСЛЕ вызова (закрывает
   SVP-IU-002): install плана и публикация транскрипта — `mb-interview-artifact-write.sh` (C11);
   запись термина — `mb-glossary.sh` (C12); C1/C5/C8/`mb-context.sh` (C10) — read/scan-часть.
   Prompt-assertion (C9) остаётся только для агентных решений, которые нельзя исполнить
   детерминированно, и writer-helper не заменяет.

**Red-условия (переписаны под eval-first S2-C6, закрывают R2-001).** Red наблюдается **после**
материализации bats-файлов — «файл теста отсутствует» больше нигде не заявляется: по S2-C6 red
принимается только при совпадении с заявленным условием, а посторонний сбой (в т.ч. отсутствующий
путь) = FAIL.

| Task | Eval (команда) | Red-условие ПОСЛЕ материализации теста |
|---|---|---|
| T1 | `bats tests/bats/test_mb_interview_artifact_check.bats && bats tests/bats/test_mb_interview_artifact_write.bats && bats tests/bats/test_discuss_interview_plan.bats` | падают `assert_script_present scripts/mb-interview-artifact-check.sh` и `.../mb-interview-artifact-write.sh` (скриптов нет; `install-plan` не производит атомарную запись — fixture target не меняется) и `mb_section`/`mb_rule` возвращают `section_absent`/`rule_absent` для секции «Interview plan», rule 11, rule 14 и шаблона C2 |
| T2 | `bats tests/bats/test_discuss_final_gate_batch.bats` | падают clause-assertions rule 12 (final gate), `--batch` + деградация, partial-answer, fact-finding + honest degradation — все с `reason=absent` |
| T3 | `bats tests/bats/test_mb_estimate_check.bats` | падает `assert_script_present scripts/mb-estimate-check.sh`; все key=value/exit-кейсы C1 не выполняются |
| T4 | `bats tests/bats/test_mb_secret_scan.bats && bats tests/bats/test_mb_interview_artifact_check.bats && bats tests/bats/test_mb_interview_artifact_write.bats && bats tests/bats/test_discuss_transcript.bats` | падает `assert_script_present scripts/mb-secret-scan.sh`; `transcript`-режим artifact-check возвращает usage error вместо `artifact=ok` на позитивных фикстурах C4-9; `publish-transcript` (C11) не публикует — fixture git-target не меняется; секрет внутри `<private>` НЕ даёт `scan=clean` (R3-001); clause-assertions шага Transcript — `reason=absent` |
| T5 | `bats tests/bats/test_discuss_glossary.bats && bats tests/bats/test_mb_glossary.bats` | падают clause-assertions rule 13 (`reason=absent`), fixture-run `mb-context.sh` на банке с `glossary.md` (строки `Glossary: …` в выдаче нет) и `assert_script_present scripts/mb-glossary.sh` (upsert/conflict не работают — C12) |
| T6 | `bats tests/bats/test_discuss_self_interview.bats` | падают clause-assertions flag-matrix `--self`/`--auto`/Assumptions (`reason=absent`) |

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| discuss.md разбухает и жжёт токены на каждом интервью | M | M | новые правила — компактные строки в существующем списке; шаблоны выносятся в templates.md (читаются точечно) |
| Prompt-слой в принципе не исполняется в bats — тесты доказывают текст/структуру, не runtime-поведение LLM-агента | M | M | **честная граница, а не отговорка**: (1) вся детерминированная бизнес-логика вынесена в реальные скрипты C1/C5/C8/C10 с полноценным bats-покрытием и fixture-run'ами; (2) остаточный prompt-контракт проверяется C9 — section-scoped clause-ERE (одна строка = одна нормативная клауза) + обязательная negation-мутация, доказывающая, что assertion ловит изменение поведения, а не соседство слов; (3) Scenarios остаются ручным приёмочным чек-листом поверх этого. Что кодом не проверяется (например «альтернативы упомянуты именно там, где решение их отклонило», C4-7) — названо явно, а не спрятано |
| Негативная мутация написана так, что assertion всё равно падает «не за то» | M | M | `assert_clause_load_bearing` требует падения с **тем же** `clause=<id>`; мутация обязана сохранять тематические слова клаузы (иначе она проверяет удаление темы, а не поведения) — правило зафиксировано в C9 |
| Конфликт правок discuss.md с параллельной сессией | L | M | COORDINATION.md checkpoint перед стартом (файл — hot spot); Scope каждой задачи честно включает `commands/discuss.md`, параллельный движок (S3) сериализует по пересечению Scope |
| Калибровка коэффициентов C3 неточна на первых спеках | M | L | стартовые значения помечены как открытый вопрос; пересматриваются по фактам первых 2-3 спек, фиксируются в notes/ |
| Грамматика C4 ужесточается позже и ломает уже написанные транскрипты | L | M | правило C4-9: оба живых транскрипта — обязательные позитивные фикстуры T4; любое ужесточение обязано сначала пройти на них |

## Open questions

- Калибровка коэффициентов рубрики C3 — стартовые значения выше, пересматриваются после 2–3 реальных спек (фиксировать факты в notes/).
