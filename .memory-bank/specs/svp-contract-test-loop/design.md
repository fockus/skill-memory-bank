# Design: svp-contract-test-loop

> Слайс S8 (blocked by S2 — потребляет tasks.md v2, Eval-грамматику S2-C1 и конвейер `/mb sdd`).
> Контракты и Eval-декларации (D-05: здесь только декларации, код рождается red→green в work-фазе).
> Ревизия 2 (2026-07-17): закрыты находки круга 2 (R2-001…R2-013) и выполнено выравнивание под
> ревизию 3 владельцев контрактов (umbrella, S2) — введён машиночитаемый реестр контрактных чекеров
> и его детерминированный раннер (C3a), verify-швы исправлены на реально существующие файлы
> (`commands/verify.md` не существует), резолвер правил получил исполнимый вход для объявленных
> источников (C2), парс `layers` получил типизированный API и канонического владельца (C1),
> `fake_red` разжалован в локальный hard stop (S5 о нём не знает — проверено по его design),
> генерация получила детерминированный шов-рендерер (C8) вместо обещания «проверить промпт кодом»,
> Quality DoD привязан к реальному сборщику payload `scripts/mb-review.sh` (C6).
> Ревизия 3 (2026-07-18, круг 3): спека без блока `layers` = **легаси** (все false, `source=legacy`,
> гейты не применяются — grandfather'ит саму S8, критический R3-001); C1 — sibling-скан
> `design.md`/`tasks.md` + код `noncanonical_owner` (R2-004); C3a — двухфазный implementer-диспатч
> declare/build + crash-safe resume (R2-001), JSON-реестр с `argv` shell=false (R3-002), закрытая
> схема evidence + red-evidence gate перед verify (CPR-A/umbrella R3-002); C4 — матрица порядка слоёв
> (e2e без integration, R3-003); C5/C6 — рубрика в блоке + `mb-rules-check` evidence в Prior evidence
> (R2-012); C8 — два фрагмента `{tasks_markdown, quality_dod_markdown}`, Quality DoD не теряется при
> всех слоях false (R2-010).

## Architecture

Три независимо приземляемых куска, ни один не меняет канонический порядок стадий
(`commands/work.md:94`):

1. **Генерация слоёв** (владелец шва — S2): `/mb sdd` вызывает детерминированный рендерер
   `scripts/mb-sdd-layers-render.py` (C8), который печатает блок задач слоёв и секцию Quality DoD в
   stdout и **не пишет файлов**. Запись принятого триплета остаётся за оркестратором по S2-C3
   (candidate → гейт → атомарный перенос) — согласовано с S2 (X-06). Структурный гейт слоёв —
   `scripts/mb-spec-validate.sh` (C3/C4).
2. **Резолвер правил**: новый `scripts/mb-rules-resolve.sh` (C2) — детерминированно определяет
   источники правил и печатает JSON. Потребители: генератор Quality DoD (C5), оркестратор при
   диспатче исполнителя, ревьюера и судьи (C6).
3. **Контрактный гейт**: новый `scripts/mb-contract-gate.sh` (C3a) исполняет реестр контрактных
   чекеров. Вызывается из `commands/work.md § 5c` (per-item verify) и `commands/mb.md § verify`
   (plan-verify). **`commands/verify.md` не существует** — проверено `ls commands/`; verify-документация
   живёт ровно в этих двух файлах (закрывает R2-002).

Проверка `layers`, структуры задач и реестра чекеров — код (`mb-spec-validate.sh`,
`mb-contract-gate.sh`), не суждение LLM (NFR-003).

### Что здесь НЕ проверяется кодом (честная граница, закрывает R2-010)

Сам генератор спеки — LLM-промпт `commands/sdd.md` (S2-C7); детерминированного шва «прогнать
генерацию в тесте» не существует, и S8 его не изобретает. Поэтому:

- **Кодом проверяется** детерминированный рендерер C8 (вход → stdout, чистая функция) и
  **детерминированные артефакты ПОСЛЕ генерации**: гейты `mb-spec-validate.sh` (C3/C4), схема
  реестра (C3a), грамматики Eval (S2-C1), батарея самопроверки S2-C8.
- **Промптом остаётся** решение, какие именно чекеры объявить и как сформулировать требование.
  Это подтверждается spec-review (S2-C5) и ревьюером, а не фиктивным pytest'ом на промпт-файле.

## Interfaces

### C1. Блок `layers` (владелец — S8, потребители — `mb-spec-validate.sh`, C8-рендерер, `/mb work`)

**Канонический владелец блока — frontmatter `requirements.md`** и только он (закрывает R2-004:
триплет состоит из трёх файлов, «frontmatter спеки» — двусмысленность). `design.md`/`tasks.md`
блок `layers` не несут; найденный там блок — ошибка валидации.

```yaml
layers:
  contract_first: true
  integration_tests: true
  e2e_tests: false
  e2e_tests_reason: "библиотека без внешней поверхности"   # обязателен при false
```

- **Новая генерация `/mb sdd` всегда пишет явный блок** `layers`; если пользователь не менял
  настройки, значения берутся из `pipeline.yaml:sdd.layers` и равны `true`; явное значение в спеке
  побеждает дефолт (REQ-012).
- **Отсутствие блока = легаси-спека** (закрывает критический R3-001): `read_spec_layers` возвращает
  все три `false`, `source="legacy"`, файл не мутируется; новые layer-гейты и обязательность Quality
  DoD к легаси-спеке НЕ применяются, валидатор печатает `layers=legacy`. Прежний дефолт «нет блока =
  все `true`» делал каждую существующую спеку невалидной для нового валидатора — **включая саму S8**:
  у неё нет блока `layers`, есть gated REQ, а `Layer:` стоит только на integration/e2e-задачах, так
  что при дефолте `true` она провалила бы собственный контрактный гейт. Legacy-режим её grandfather'ит
  (S8 остаётся легаси со старым поведением; новую механику включает явный блок или конфиг).
- `<layer>_reason` обязателен при `false` **в явном блоке**; его отсутствие — ошибка валидации
  (REQ-011). К легаси-спеке (все `false` по отсутствию блока) правило `_reason` не применяется —
  причины требуются только для явно отключённого слоя.

**`sdd.layers` в `pipeline.yaml` записывается инлайн-мапой — это требование, а не стиль**
(измерено на текущем дереве 2026-07-17, не предположено): `mb-pipeline-validate.sh` читает `sdd`
через `parse_simple_mapping` (`scripts/mb-pipeline-validate.sh:319`), который берёт только строки с
`indent == 2`. Вложенный блок в PyYAML-optional fallback'е даёт `layers: None`, тогда как PyYAML —
полный словарь; инлайн-форма парсится **идентично** обеими ветками:

| Форма | PyYAML-ветка | fallback-ветка |
|---|---|---|
| `layers:` + вложенные строки (indent 4) | `{'contract_first': True, …}` | **`None`** — расхождение |
| `layers: {contract_first: true, integration_tests: true, e2e_tests: true}` | `{'contract_first': True, …}` | `{'contract_first': True, …}` |

Следствие грамматики `parse_inline_map` (split по `,`, затем по первому `:`): значения не должны
содержать `,`. Тот же урок, что S2-C5 зафиксировал для `spec_review`.

**Типизированный API парсера** (закрывает R2-004 — «Task 2 назначает `mb_work_items.py`, который
принимает только путь к tasks.md и не знает layers»):

```python
memory_bank_skill.spec_layers.read_spec_layers(requirements_path: Path, pipeline_path: Path) -> SpecLayers
```

- `SpecLayers` — frozen dataclass: `contract_first: bool`, `integration_tests: bool`,
  `e2e_tests: bool`, `reasons: dict[str, str | None]`, `source: Literal["spec", "pipeline", "legacy"]`.
  `source="legacy"` — блока нет (все три `false`); `source="pipeline"` — блок есть, но значение слоя
  унаследовано из `pipeline.yaml:sdd.layers`; `source="spec"` — блок задаёт значение явно.
- Ошибки — `SpecLayersError(code, field)`;
  `code ∈ {missing_reason, malformed_block, unknown_key, noncanonical_owner}`.
- **Канонический владелец блока — только `requirements.md`; sibling-скан обязателен** (закрывает
  R2-004: прежний API получал лишь `requirements_path`/`pipeline_path` и не мог однозначно реализовать
  запрет блока в `design.md`/`tasks.md`). `read_spec_layers` ОБЯЗАН заглянуть в
  `requirements_path.parent / "design.md"` и `/ "tasks.md"` на предме frontmatter-ключа `layers`;
  найден → `SpecLayersError("noncanonical_owner", "design.md:layers"|"tasks.md:layers")` ДО резолва
  дефолтов; отсутствующий sibling-файл игнорируется. CLI: stdout пуст, stderr
  `spec_layers_error=noncanonical_owner field=<file>:layers`, exit `1`.
- CLI: `python3 -m memory_bank_skill.spec_layers --requirements PATH --pipeline PATH --json`;
  stdout — `{"contract_first":bool,"integration_tests":bool,"e2e_tests":bool,"reasons":{…},"source":"spec|pipeline|legacy"}`;
  exit `0` ok, `1` malformed/`missing_reason`/`noncanonical_owner`, `2` usage.
- **`scripts/mb_work_items.py` не меняется** — он владеет tasks.md, а не frontmatter requirements.md
  (S2-C2 требует byte-identical проекцию его ключей; трогать его ради `layers` — лишний риск).
- Чтение только читает: sha256 файла до и после совпадает (REQ-013 / NFR-002).

**Негативный пример легаси-спеки** (в текст спеки — R3-001): сам файл
`.memory-bank/specs/svp-contract-test-loop/requirements.md` не несёт блока `layers` (см. его
frontmatter: `topic/group/ice/…`, без `layers:`). Для него `read_spec_layers` возвращает
`{contract_first:false, integration_tests:false, e2e_tests:false, source:"legacy"}`, файл не мутирует,
а `mb-spec-validate.sh` печатает `layers=legacy` и НЕ требует ни контрактной, ни integration/e2e-задачи
— поэтому существующие `**Layer:** integration`/`**Layer:** e2e` задачи Task 7/8 не считаются
violation. Тест T3 фиксирует, что эта спека и одна pre-S8 фикстура остаются валидными после T3.

### C2. `scripts/mb-rules-resolve.sh` — два режима (закрывает R2-003)

```
bash scripts/mb-rules-resolve.sh [--repo PATH] [--mb BANK] [--json]
bash scripts/mb-rules-resolve.sh --spec SPEC_DIR [--declared-source PATH]… [--repo PATH] [--mb BANK] [--json]
```

**Режим discovery** (без `--spec` и `--declared-source`): порядок поиска — собираются **все**
найденные проектные источники: `<repo>/AGENTS.md` → `<repo>/RULES.md` → `<bank>/RULES.md` →
активный профиль (`bash scripts/mb-profile.sh path` — субкоманда существует) → fallback
`<skill>/rules/RULES.md`. Fallback разрешён. Exit 0.

**Режим validation** (`--spec` и/или `--declared-source`): резолвер обязан знать, что именно
объявлено, иначе «exit 1 за отсутствующий объявленный источник» неисполним.

- **Где живёт объявление**: секция `## Quality DoD` в `<spec-dir>/design.md`, строки ровно вида
  `- [<kind>] <repo-relative path>`, где `kind ∈ {project, profile, skill}` (C5 их и генерирует —
  контур замкнут: C5 пишет, C2 читает).
- `--declared-source PATH` (повторяемый) добавляет объявленные записи явно, без чтения спеки.
- Каждый объявленный путь **обязан существовать**: иначе stdout пуст, stderr `rule_source_missing=<path>`,
  exit `1`; **fallback в этом режиме запрещён** (REQ-017 — громкий отказ, а не тихий откат).
- Malformed секция `## Quality DoD` (строка не по грамматике, неизвестный `kind`) → exit `2`.

**Общее для обоих режимов:**

- stdout JSON: `{"sources": [{"path": "…", "kind": "project|profile|skill"}], "review_rubric": ["<bullet>", …], "fallback_used": bool, "checker": "scripts/mb-rules-check.sh"}`.
  `sources` отсортирован по `path` — один вход даёт один байт-идентичный выход (NFR-003).
- `review_rubric` — пункты `pipeline.yaml:review_rubric`, отрендеренные в канонические буллеты в
  авторском порядке (R2-012: рубрика — часть критерия, доезжающего до ревьюера/судьи); отсутствует
  `review_rubric` → пустой массив. Это единственный источник рубрики в канале доставки (C6).
- **Формат буллета — `"<category>: <text>"`** (ревизия 3, решение по итогам T1; прежде не был задан,
  поэтому оставался на усмотрение реализации). Пример: `"security: No secrets in code"`,
  `"tests: Integration tests > unit tests (Testing Trophy)"`. Категория сохраняется намеренно: получатель (ревьюер,
  судья) видит этот список **в отрыве от файла**, из которого он собран, и без категории теряет
  линзу, под которой пункт написан, — «No secrets in code» под `security` и под `tests` значат разное;
  плоский текст вдобавок допускает неразличимые дубликаты. Не «чинить» обратно на голый текст.
- **`fallback_used` = «не найдено ни одного источника вида `project`»** (ревизия 3, там же). Профиль —
  слой персонализации, а не замена проектных правил, поэтому наличие профиля fallback НЕ подавляет.
  Соответствует имени теста, заданного самой спекой (`rules_resolve_fallback_only_without_project`).
- **Малформед `review_rubric` — громкий отказ, а не пустой массив** (ревизия 3): присутствующий, но
  не-mapping `review_rubric` (или категория не-список) → stderr `review_rubric_unreadable=<path>
  detail=<code>`, exit 2. Пустым массивом отвечает ТОЛЬКО отсутствующий ключ. Основание — то же
  правило REQ-017 (громкий отказ вместо тихого отката), применённое ко второй половине блока: молча
  опустевшая рубрика даёт **вердикт, вынесенный против критерия, об исчезновении которого никто не
  узнал**.
- Exit: `0` резолв успешен; `1` объявленный источник отсутствует; `2` usage/malformed.
- Без сети и без LLM. Bash 3.2-совместимо (NFR-004).

### C3. Контрактная задача (структурный контракт, потребитель — `mb-spec-validate.sh`)

Задача с полем `**Layer:** contract` и пятью шагами в `What to do`; DoD обязан содержать пункты
шагов 4 и 5 (зелёные тесты чекеров + красный прогон против продукта). Бизнес-кода не содержит.

**Предикат `has_gated_req`** (возвращает условие REQ-001, потерянное в ревизии 1 — закрывает R2-005):
`has_gated_req = true`, если `requirements.md` содержит хотя бы один EARS-критерий с нормативным
**SHALL** или **MUST**; `SHOULD`/`MAY` — не gated. Определение унаследовано от родителя без
изобретения своего (D-06: «GWT + Eval обязательны только для gated (SHALL/MUST) REQ»,
`context/sdd-vision-pipeline.md:41`).

**Легаси-короткое замыкание (закрывает R3-001)**: если `source == "legacy"` (спека без блока
`layers`, C1) — валидатор НЕ применяет ни один layer-гейт (ни контрактный, ни integration/e2e),
печатает `layers=legacy` и проверяет спеку **ровно как pre-S8** (byte-identical со старым поведением).
Таблица ниже и матрица C4 применяются ТОЛЬКО к спекам с явным блоком (`source ∈ {spec, pipeline}`).
Так grandfather'ится существующий корпус (включая саму S8): найденные `Layer:`-задачи в легаси-спеке
violation НЕ дают.

**Гейт валидатора** (для `source ∈ {spec, pipeline}`; ровно эта таблица — она же таблица кейсов тестов T3):

| `contract_first` | `has_gated_req` | Требование валидатора |
|---|---|---|
| `true` | `true` | ровно одна задача `Layer: contract`, **перед всеми** implementation-задачами; иначе violation |
| `true` | `false` | контрактная задача **не требуется**; валидатор печатает `contract_layer=not_applicable` |
| `false` | любой | задача `Layer: contract` отсутствует; найденная → violation |

**Позиция — «перед всеми implementation-задачами», а не «первая в списке»** (директива umbrella к
формулировке REQ-001): спека вправе нести не-implementation задачи (например, исследовательскую)
до контрактной. Implementation-задача = задача без поля `**Layer:**`. Гейт: индекс контрактной
задачи < минимального индекса implementation-задачи.

### C3a. Реестр контрактных чекеров и раннер (закрывает R2-001)

Без машиночитаемого реестра стадия `verify` не знает, что запускать, — REQ-021 неисполним.
Реестр durable и живёт **в самой спеке** (D-27 «MD как база данных»), а не в эфемерном
`<bank>/.work-state.json`, который стирается `mb-work-state.sh clear` и не переживает сессию.

**Место**: fenced-блок внутри тела контрактной задачи в `tasks.md`. Это **тело задачи**, а не новое
`**Field:**` — грамматику полей tasks.md v2 владеет S2-C1, и S8 её не расширяет; `mb_work_items.py`
кладёт весь блок в `body` (`scripts/mb_work_items.py:235`) и fenced-блок ему безразличен.

**Схема — закрытый JSON, парсится stdlib `json` (закрывает R3-002)**: прежний «произвольный YAML» с
`cmd: <точная команда>` не задавал parser, экранирование `:`/`#`/кавычек/многострочности, способ
исполнения (shell vs argv) и подстановку `<phase>`, поэтому «invalid registry → exit 2» был
непроверяем. Реестр — fenced-блок ```json Contract-checkers```:

````markdown
```json Contract-checkers
{"checkers": [
  {"id": "<slug>",                              // [a-z0-9_]+, уникален внутри спеки
   "covers": ["REQ-NNN", "…"],                  // ≥1 gated REQ этой спеки
   "path": "<repo-relative путь к реализации чекера>",
   "argv": ["bash", "tests/checker.sh"],        // непустой массив строк, shell=false из корня репо
   "evidence": "tmp/contract-gate/<topic>/<id>.{phase}.json",  // bank-relative, {phase} → red|verify
   "output_ere": "<ERE — сигнатура вывода НАСТОЯЩЕГО провала>"}
]}
```
````

- `mb-contract-gate.sh` парсит блок Python-stdlib `json` (Bash 3.2 делегирует разбор `python3`, новой
  зависимости нет); **неизвестный/отсутствующий ключ — schema error, exit 2**.
- `argv` — непустой массив строк, исполняется **`shell=false` из корня репо**; кому нужен shell-синтаксис,
  явно пишет `["bash","-lc","…"]`. Так снимается вся неоднозначность экранирования старого `cmd:`.
- `output_ere` — та же семантика red-якоря, что S2-C1 (`ERE`, обязан совпасть с объединённым
  stdout+stderr настоящего провала). Второго источника правды о якорях не вводится.
- `evidence` — **bank-relative**, обязан матчить `tmp/contract-gate/<topic>/…` (umbrella NFR-005:
  структурный лог в `<bank>/tmp/`), джойнится под канонический `--mb`; `{phase}` заменяется ТОЛЬКО на
  `red|verify`. Абсолютный путь, `..`, symlink-escape, невалидный ERE, неверный тип `path`/`argv` →
  **exit 2 до запуска любого чекера**.
- Каждый gated REQ спеки обязан быть покрыт хотя бы одним `covers` (иначе — violation T3).

**Закрытая схема evidence красного/verify прогона (CPR-A, umbrella R3-002)** — раннер пишет по каждому
чекеру ровно этот объект (temp-файл + атомарный `mv`):

```json
{"version": 1, "topic": "<slug>", "checker_id": "<id>", "phase": "red|verify",
 "cmd": "<канонический JSON argv>", "cmd_sha256": "<64-hex sha256(cmd)>",
 "exit": <int>, "output_match": <bool>,
 "verdict": "pass|fake_red|foreign_failure|red_checker"}
```

- `cmd` — канонический JSON сериализованного `argv` (`json.dumps(argv, separators=(',',':'))`);
  `cmd_sha256` — sha256 этой строки. Так byte-identity команды проверяема без потерь на квотировании.
- Запись — во временный файл под `<bank>/tmp/contract-gate/<topic>/`, затем `mv` на объявленный
  `evidence`-путь (атомарность: недописанный evidence не виден потребителю). `verify` пишет **отдельный**
  `<id>.verify.json`, не перетирая red-evidence.

**Жизненный цикл реестра — контрактная задача = один чекбокс, но ДВА implementer-диспатча**
(закрывает R2-001: прежняя проза требовала объявить чекеры, записать реестр, затем в той же задаче
писать чекеры — но текущий `/mb work` делает один implementer-dispatch на item, `commands/work.md`,
и второго/resume-протокола не было). D-23: банк пишет только оркестратор.

1. `/mb sdd` генерирует контрактную задачу **без** реестра — плейсхолдеров не бывает, а команд
   чекеров на этапе генерации ещё физически не существует (D-05).
2. **Dispatch A (declare)** — исполнитель НЕ пишет product/checker-файлы, объявляет чекеры и
   возвращает `MB_CONTRACT_CHECKERS_JSON={"checkers":[{…}]}` **перед** штатным `MB_WORK_RESULT_JSON=`
   и завершается.
3. Оркестратор валидирует JSON по схеме выше, **сам** пишет fenced-блок в тело контрактной задачи (та
   же природа записи, что переворот чекбокса — post-acceptance правка tasks.md; гейт S2-C3 не
   перезапускается, реестр не добавляет полей `Budget`) и фиксирует в work-state шаг
   `contract_declared` (`mb-work-state.sh step contract_declared` — существующий writer, S2-C6).
4. **Dispatch B (build)** — исполнитель получает **замороженный** реестр, пишет ТОЛЬКО юнит-тесты
   чекеров и реализации чекеров (файлы репо, не банк), затем завершается штатным envelope.
5. После B оркестратор требует **зелёные юнит-тесты чекеров** и запускает `mb-contract-gate.sh red`
   — вердикт даёт exit-код раннера, а не самоотчёт агента.
6. **Crash-safe resume**: валидный реестр в tasks.md **И** шаг `contract_declared` в work-state →
   Dispatch A пропускается, идём в B; отсутствие любого из них → A повторяется. До успешного `red`-гейта
   диспатч бизнес-реализации **запрещён**.

**Совместимость с S5-C4** (envelope-контракт отчёта исполнителя): S5 требует, чтобы **последний
непустой блок отчёта был ровно одной строкой** `MB_WORK_RESULT_JSON={…}`
(`svp-adapt-escalation/design.md:210-214`). Поэтому `MB_CONTRACT_CHECKERS_JSON=` печатается
**раньше**, отдельным блоком, отделённым пустой строкой; последним непустым блоком остаётся
S5-envelope. Контракт S5 не ослабляется и не переопределяется.

**Раннер** (потребитель — `commands/work.md § 5c`, `commands/mb.md § verify`):

```
bash scripts/mb-contract-gate.sh red    --spec SPEC_DIR [--mb BANK] [--json]
bash scripts/mb-contract-gate.sh verify --spec SPEC_DIR [--mb BANK] [--json]
```

- Читает реестр из контрактной задачи `<spec-dir>/tasks.md`; исполняет `argv` каждого чекера
  **`shell=false` из корня репо** (byte-identical); по каждому пишет evidence закрытой схемы (temp+`mv`).
- `red` (шаг 5 контрактной задачи) — каждый чекер обязан упасть **по заявленной причине**:
  `exit != 0` **и** совпадение `output_ere` с stdout+stderr. Вердикты (пишутся в evidence):
  - все совпали → `verdict=pass`, exit `0`;
  - чекер **зелёный до реализации** → `verdict=fake_red`, exit `1` (REQ-005);
  - чекер упал, но `output_ere` не совпал → `verdict=foreign_failure`, exit `1` — посторонний сбой не
    принимается за red (тот же урок, что S2-C6: `bats <missing>` даёт exit 1, как настоящий провал).
- **`verify` precondition — red-evidence gate (CPR-A, umbrella R3-002)**: до запуска verify-чекеров
  раннер требует по каждому чекеру **существующий валидный** red-evidence с `verdict=pass` и
  **byte-identical `cmd`/`cmd_sha256`** относительно текущего реестра. Отсутствие evidence, malformed
  evidence или дрейф `cmd`/`cmd_sha256` (реестр изменили после red) → **exit 2 БЕЗ запуска verify**
  (нельзя верифицировать против команды, чей red никогда не наблюдали).
- `verify` (стадия verify, после gate) — каждый чекер обязан вернуть `0`; любой иной exit → exit `1`,
  верификация FAIL (REQ-021); пишет отдельный `<id>.verify.json`.
- Exit: `0` гейт пройден; `1` контрактный провал; `2` usage / отсутствующий-невалидный реестр /
  проваленный red-evidence gate.
- stdout — один JSON: `{"phase":"red|verify","checkers":[{"id":…,"exit":…,"match":bool,"verdict":…}],"verdict":"pass|fake_red|foreign_failure|red_checker"}`;
  stderr — диагностика. Evidence пишется по объявленным `evidence`-путям.

### C4. Тестовые слои (структурный контракт)

`**Layer:** integration` и `**Layer:** e2e` — по одной задаче. **Слои отключаются независимо**, поэтому
порядок задан матрицей, а не жёсткой цепочкой (закрывает R3-003: при `integration=false, e2e=true` не
было объекта, «после которого» ставить e2e):

| `integration_tests` | `e2e_tests` | Порядок задач |
|---|---|---|
| `true` | `true` | все implementation → integration → e2e |
| `true` | `false` | все implementation → integration |
| `false` | `true` | все implementation → e2e (после всех implementation; integration-задачи нет) |
| `false` | `false` | нет тест-слоёв |

REQ-008: e2e идёт после всех implementation-задач и, **когда integration-задача есть**, после неё.
DoD каждой задачи перечисляет `test_id` покрываемых сценариев в формате `mb-scenario-extract.py`
(REQ-009) — источник id уже существует, новый формат не вводится.

**Правило отображения `test_id` → имя теста** (делает C4 исполнимым и снимает разнобой):
имя тест-функции = `test_` + `test_id`, где `-` заменён на `_`.
Пример: `REQ-001__contract_task_comes_first` → `test_REQ_001__contract_task_comes_first`.
Сокращения, многоточия и «номера сценариев» в DoD запрещены — только полные `test_id` (REQ-009).

### C5. Quality DoD (секция спеки)

`## Quality DoD` в `design.md` генерируемой спеки. Формат — ровно тот, что читает C2 (контур
замкнут):

```markdown
## Quality DoD

Rule sources (resolved by `scripts/mb-rules-resolve.sh`, referenced — never copied):
- [project] AGENTS.md
- [skill] rules/RULES.md

Review rubric (from `pipeline.yaml:review_rubric`):
- <rubric bullet 1>
- <rubric bullet 2>

Checker: `bash scripts/mb-rules-check.sh --files <touched-files-csv> --out json` — no violations
on this item's touched files.
```

- **Три части статического блока (R2-012)**: (1) отсортированные ссылки на источники правил;
  (2) `pipeline.yaml:review_rubric`, отрендеренный каноническими буллетами; (3) команда чекера. Ровно
  этот блок байт-идентичен для исполнителя/ревьюера/судьи. Прежде блок нёс только пути + команду, и
  оркестрированный ревьюер (который файлы не открывает) фактически не видел ни рубрики, ни результата
  чекера — ссылка оставалась непотребляемой.
- Строки `- [<kind>] <path>` отсортированы по `path` (детерминизм, NFR-003).
- Текст правил не копируется — только пути (REQ-015).
- Чекер — существующий `scripts/mb-rules-check.sh` с его реальным интерфейсом
  (`--files <csv> [--diff-files <csv>] [--out json|human|both] [--profile <path>]`, проверено по
  `scripts/mb-rules-check.sh:4-5`); нового линтера правил не появляется (REQ-018).
- `<touched-files-csv>` — **параметр документируемой команды**, а не плейсхолдер: csv подставляет
  вызывающая сторона на своей стадии. Благодаря этому блок не несёт per-item данных и потому
  байт-идентичен для всех трёх получателей (C6).

### C6. Доставка Quality DoD исполнителю, ревьюеру и судье (закрывает R2-012)

**Проверено по репозиторию, а не предположено:** оркестрированный ревьюер **не читает файлы** —
`scripts/mb-review.sh --emit-payload` собирает ему один самодостаточный payload из пяти секций, и
`agents/mb-reviewer.md:36-40` прямо запрещает открывать файлы. `mb-review.sh` **не читает**
`review_rubric` из `pipeline.yaml`. Значит «рубрика доедет сама» — ложное допущение: канал рубрики
существует как критерий (`agents/mb-engineering-core.md:119` — «If a `pipeline.yaml:review_rubric`
is provided, walk it»), но доставляется только тем, что попало в промпт/payload.

**Контракт доставки** — один канонический **статический** блок (байт-идентичен трём получателям) +
динамическая evidence чекера (per-item, вне блока):

1. `bash scripts/mb-rules-resolve.sh --spec <spec-dir> --json` формирует канонический JSON (источники
   + `review_rubric` + чекер).
2. Оркестратор рендерит из него **ровно один** markdown-блок `## Quality DoD` по формату C5
   (сортированные строки источников + буллеты рубрики + строка чекера).
3. Тот же **байтовый** блок доставляется:
   - исполнителю — в промпт `commands/work.md § 5a`;
   - ревьюеру — через `bash scripts/mb-review.sh --emit-payload --quality-dod <path>`: payload
     получает секцию `## Quality DoD` (шестая секция фиксированного порядка). Это и есть
     материализация существующего канала рубрики для ревьюера, который не читает файлы;
   - судье — в промпт `commands/work.md § 5e`.
4. **Детерминированная evidence чекера в Prior evidence (R2-012)**: перед диспатчем ревьюера И судьи
   оркестратор **один раз** запускает `bash scripts/mb-rules-check.sh --files <touched> --out json`
   на изменённых файлах item'а; канонический JSON-результат добавляется в секцию **Prior evidence**
   payload'а (вне статического блока `## Quality DoD`, поэтому его sha256 остаётся общим у трёх
   получателей). Так ревьюер видит и рубрику (в блоке), и результат детерминированного чекера
   (в Prior evidence), не открывая ни одного файла.

   **Гейт диспатча смотрит на `severity: CRITICAL` в JSON, а не на код выхода чекера**
   (ревизия 4, 2026-07-27). Прежняя формулировка — «ненулевой код блокирует диспатч» — описывала
   гейт, который на этом проекте не срабатывает ни при каких входах: `mb-rules-check.sh` выставляет
   `EXIT_CODE=1` **только** при активном профиле `strictness: block`
   (`scripts/mb_rules_check_baseline.sh:113-119`), а профиль проекта — `warn`, поэтому три CRITICAL
   дают exit 0 (измерено, не предположено). Реализация: `mb-review.sh --rules-check-json <path>`
   отказывает с exit 1 и **не печатает payload**, если в JSON есть хотя бы одно CRITICAL;
   нечитаемый JSON — тоже отказ (нечитаемая evidence не является evidence).

   **Гейт намеренно НЕ наследует `strictness`, и это не баг.** `strictness` отвечает на вопрос
   «насколько громко чекер репортит», а шаг 4 — на другой: «звать ли ревьюера». `strictness: warn`
   означает «не вали мою работу из-за стиля», а не «зови дорогую модель на код, который не проходит
   базовые правила». Наследование сделало бы решение о запуске ревью побочным эффектом настройки
   отчётности. Не «чините» это обратно на код выхода — гейт станет декоративным.

   Во всём остальном `strictness` остаётся в силе без изменений: severity в отчёте, вердикт
   `mb-rules-check.sh` и его код выхода ведут себя ровно как раньше; шаг 4 ничего в чекере не
   переопределяет и читает его вывод, а не меняет его поведение.
5. **`pipeline.yaml` и `references/pipeline.default.yaml` при этом не мутируются**: рантайм-правка
   конфига создала бы второй источник правды о правилах. `review_rubric` остаётся статической
   рубрикой проекта; Quality DoD — резолвленный per-spec блок, доставляемый той же сборкой промпта.
   Новых каналов не вводится (S8-D-09, AGR-018).
6. Отсутствующий объявленный источник (C2 exit 1) валит диспатч громко (REQ-017).

Проверяемость: sha256 **статического** блока, доставленного трём получателям, совпадает; payload
ревьюера/судьи несёт буллеты рубрики и JSON-результат `mb-rules-check.sh` в Prior evidence (Eval T6).

### C7. `fake_red` — локальный hard stop (потребитель — `/mb work`; закрывает R2-006)

**Проверено по S5**: `scripts/mb-work-adapt.sh decide` принимает только
`--eval-status green|red|absent` (`svp-adapt-escalation/design.md:44`), знает лишь envelope
`complexity_escalation` (`:208-222`), и его триггер `eval_not_green` срабатывает **только** при
`steps.count("eval_fail") >= max_cycles` (`:86`). Значение `fake_red` в S5 отсутствует. Прежнее
утверждение S8 «совместим с сигналом эскалации S5» было ложным и, что хуже, маршрутизация через
S5 отсрочила бы немедленный отказ REQ-005 до исчерпания циклов — то есть **ослабила бы hard stop**.

Поэтому:

- `fake_red` — **локальный немедленный hard stop контрактной задачи**: item остаётся open, чекбокс
  не переворачивается, стадия `implement` бизнес-кода не диспатчится (REQ-005).
- Вердикт выдаёт **раннер** `mb-contract-gate.sh red` (exit 1 + `verdict=fake_red`), а не самоотчёт
  исполнителя — доказательство, а не заявление.
- `fake_red` **не** преобразуется в `complexity_escalation` и **не** проходит через развилки
  `continue`/`stub_continue` S5. При последующих ручных попытках S5 видит только свой штатный
  `eval_status=red` по своему существующему контракту — новый сигнал не изобретается и enum S5 не
  расширяется.
- `foreign_failure` (чекер упал не по заявленной причине) — тот же локальный hard stop.
- **Ненаблюдаемое требование** (REQ-006) — тоже локальный hard stop класса «дефект спеки», а не
  `complexity_escalation`: envelope S5 описывает **сложность** задачи, а не дефект спеки, и
  использовать его тут значило бы соврать в семантике. Требование переформулируется или явно
  помечается как проверяемое только LLM-ревью.

## Decisions

S8-D-01…11 — в `context/svp-contract-test-loop.md`, подтверждены пользователем как **AGR-018**.
Ключевое: контракт-ферст = отдельная задача перед всеми implementation-задачами; чекер тестируется
на фикстурах обеими половинами; red против продукта обязателен; слои отключаются во frontmatter
requirements.md; Quality DoD = ссылки + существующий чекер; порядок стадий не меняется.

**Границы (AGR-019)**: contract/eval-механика этого слайса распространяется только на путь
SDD/tasks/`/mb work`. `/mb plan` остаётся ручным режимом — ни одна задача S8 его не трогает.

## Eval declarations (red → green в work-фазе)

Грамматика и семантика якорей — S2-C1 (потребляются как есть, ревизия 3):
`**Eval:** <command> — red: <проза>[; exit: <n>][; output~: <ERE>]`. Все 8 задач покрывают gated
(SHALL) REQ, поэтому `output~:` обязателен на каждой (S2 REQ-055 / umbrella Interface 1).

Red-условие описывает поведение **после материализации** eval-кода (D-05: тест — первый шаг
задачи). «Файла теста нет» red-условием не является ни в одной строке ниже — это ровно дефект,
который ревью нашло у ревизии 1 (R2-009). Измерено на этом дереве 2026-07-17:
`bats <missing>` → exit 1 + `not ok 1 bats-gather-tests` (тот же код, что у настоящего провала —
exit-only якорь обманулся бы); `pytest <missing>` → exit 4 + `no tests collected`. Якоря ниже
именуют **конкретный тест**, поэтому ни один из этих случаев их не матчит.

| Task | Eval | Red-условие ПОСЛЕ материализации + якорь |
|---|---|---|
| T1 | `bats tests/bats/test_mb_rules_resolve.bats` | `mb-rules-resolve.sh` не реализован: проектный источник не побеждает fallback → `exit: 1`; `output~: not ok [0-9]+ rules_resolve_project_source_wins` |
| T2 | `pytest tests/pytest/test_spec_layers.py` | модуль `spec_layers` не реализован: спека без блока не читается как легаси → `exit: 1`; `output~: FAILED tests/pytest/test_spec_layers\.py::test_missing_block_is_legacy` |
| T3 | `bats tests/bats/test_mb_spec_validate_layers.bats` | гейты слоёв не добавлены: фикстура без контрактной задачи проходит зелёной → `exit: 1`; `output~: not ok [0-9]+ spec_validate_missing_contract_task_fails` |
| T4 | `pytest tests/pytest/test_sdd_layers_render.py` | рендерер C8 не существует: порядок contract → impl → integration → e2e не рендерится → `exit: 1`; `output~: FAILED tests/pytest/test_sdd_layers_render\.py::test_task_order_contract_impl_integration_e2e` |
| T5 | `bats tests/bats/test_mb_contract_gate.bats` | `mb-contract-gate.sh` не существует: зелёный-до-реализации чекер не даёт `fake_red` → `exit: 1`; `output~: not ok [0-9]+ contract_gate_fake_red_fails` |
| T6 | `pytest tests/pytest/test_quality_dod_delivery.py` | доставки нет: три payload не несут байт-идентичный блок → `exit: 1`; `output~: FAILED tests/pytest/test_quality_dod_delivery\.py::test_three_payloads_share_one_sha256` |
| T7 | `pytest tests/pytest/test_integration_contract_test_loop.py` | связка не собрана: спека со слоями не проходит валидатор → `exit: 1`; `output~: FAILED tests/pytest/test_integration_contract_test_loop\.py::test_REQ_001__contract_task_comes_first` |
| T8 | `pytest tests/pytest/test_e2e_contract_test_loop.py` | сквозной путь не собран: verify не гоняет чекеры → `exit: 1`; `output~: FAILED tests/pytest/test_e2e_contract_test_loop\.py::test_REQ_020__verify_runs_the_contract_checkers` |

### C8. `scripts/mb-sdd-layers-render.py` — детерминированный шов генерации (закрывает R2-010)

```
python3 scripts/mb-sdd-layers-render.py --requirements PATH --pipeline PATH --rules-json PATH --json
```

- **Два типизированных фрагмента в одном JSON-envelope (закрывает R2-010)**: с `--json` stdout — ровно
  `{"tasks_markdown": "<string>", "quality_dod_markdown": "<string>"}`. Прежде рендерер печатал task-блок
  и `## Quality DoD` одним stdout, вставлявшимся в **один** candidate, и destination для `design.md` был
  не определён; к тому же «все слои false → stdout пуст» терял обязательный Quality DoD (REQ-015).
- `commands/sdd.md` вставляет `tasks_markdown` ТОЛЬКО в `tasks.candidate.md`, а `quality_dod_markdown`
  ТОЛЬКО в staged `design.md` (`<bank>/tmp/sdd/<topic>/design.md`) — перед гейтами S2-C3.
  **Ревизия 4 (2026-07-27):** здесь стояло `design.candidate.md` — файла с таким именем не существует
  и никогда не существовало. Шипнутый пайплайн S2 кладёт в стейджинг `design.md` (`commands/sdd.md`
  шаг 3), а `.candidate`-суффикс несёт только tasks (шаг 4). Формулировка C8 писалась до приземления
  S2; приведена к коду по решению оркестратора.
- `tasks_markdown` несёт контрактную + integration + e2e-задачи по значению `layers` (отключённый слой
  → задача не рендерится); `quality_dod_markdown` — ровно одна секция `## Quality DoD` по формату C5.
- **Все три слоя `false` → `tasks_markdown == ""`, но `quality_dod_markdown` НЕПУСТ** (одна секция
  `## Quality DoD`): скорость отключает задачи, но не критерий правил (REQ-015). Неизвестные/отсутствующие
  ключи JSON → exit 1.
- Exit: `0` отрендерено; `1` невалидные `layers` / нерезолвимое отображение сценариев / битый JSON-контракт;
  `2` usage.
- **Запись принятого триплета — оркестратор** (S2-X-06); задачи S8 файлы спеки не пишут.

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Контрактная задача выродится в формальность (чекер = `grep слово`) | H | H | `output_ere`-якорь реестра (семантика S2-C1 red-anchor) обязан совпасть с настоящим провалом (C3a); `fake_red`/`foreign_failure` шага 5 ловят тривиальные и посторонние чекеры; ревьюер получает Quality DoD + рубрику + rules-check evidence (C6) |
| Три обязательные задачи раздувают маленькие спеки | M | M | контрактная задача не требуется при `has_gated_req=false` (C3, таблица); слои отключаются одним промптом (C1) |
| Дублирование с quality-track (evidence) | M | M | S8 создаёт тесты и порядок, quality-track доказывает свежесть; граница зафиксирована в контексте, REQ не пересекаются |
| Расхождение дефолтов pipeline ↔ спека | M | L | приоритет зафиксирован в C1 и проверяется T2; инлайн-мапа `sdd.layers` снимает расхождение PyYAML ↔ fallback (измерено) |
| Резолвер правил станет вторым источником правды о правилах | L | M | C2 только указывает пути, исполняет существующий `mb-rules-check.sh` (REQ-018); pipeline не мутируется (C6) |
| Реестр чекеров разойдётся с реальными чекерами | M | H | реестр (JSON, `argv`) пишет оркестратор из structured proposal, исполняет раннер byte-identical shell=false (C3a); дрейф `cmd`/`cmd_sha256` после red ловит red-evidence gate перед verify (exit 2, CPR-A); расхождение `argv` ↔ реальности даёт `foreign_failure`, а не тихий зелёный |

## Cross-slice requests (правки в чужих спеках — здесь не делаются)

| # | Адресат | Запрос | Основание |
|---|---|---|---|
| X8-01 | `svp-adapt-escalation` (S5) | Информационно: `fake_red`/`foreign_failure`/`unobservable_requirement` — **локальные** hard stop'ы S8, в ADaPT не маршрутизируются; enum `--eval-status` расширять **не нужно**. Просьба не добавлять `fake_red` в S5-C1 | R2-006 |
| X8-02 | `svp-adapt-escalation` (S5) | C4-envelope: подтвердить, что строка `MB_CONTRACT_CHECKERS_JSON=` **перед** финальным блоком (через пустую строку) контракт не нарушает — последним непустым блоком остаётся `MB_WORK_RESULT_JSON=` | R2-001 × S5-C4 |
| X8-03 | `svp-sdd-core` (S2) | Информационно: S8 не расширяет грамматику полей tasks.md v2 — реестр чекеров живёт fenced-блоком в **теле** контрактной задачи, `mb_work_items.py` не меняется | R2-001, S2-C1/C2 |

## Open questions

— (закрыты ревизией 2: формат записи красного прогона зафиксирован реестром C3a — `evidence` под
`<bank>/tmp/contract-gate/<topic>/`, второго источника правды с quality-track не возникает, т.к.
S8 пишет прогон, а quality-track доказывает свежесть; вопрос «`Layer: contract` или позиция» решён
в пользу явного `Layer: contract` + гейта позиции «перед всеми implementation-задачами», C3).
Ревизия 3 закрыла формат evidence до **закрытой схемы** `{version, topic, checker_id, phase, cmd,
cmd_sha256, exit, output_match, verdict}` (temp+`mv`) и red-evidence gate перед verify (CPR-A).
