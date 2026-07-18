# Tasks: svp-docs-wiki

> Слайс S6 (ICE 336). Eval первым (red) → реализация (green).
> Ревизия 3 (2026-07-17): T4 переведён на детерминированный шов `docs_run.py` (`plan`/`apply`) и
> получил полный Scope всех правимых файлов (R2-001/R2-002); T4 покрывает REQ-007 сквозной
> проверкой артефактов и REQ-012; порядок Stage 2 — `6 → 4` (T4 потребляет конфиг T6, R2-003);
> каждый `Eval:` несёт `output~:`-якорь настоящего провала (umbrella Interface 1, S2-X-05).
> Ревизия 4 (2026-07-18, круг 3): T4 — `apply --plan --results` (авторитетный план, R3-002), bootstrap
> не `stale_run` (R3-001), рендер `contradictions[]` (R3-004), manifest durable/control/pending (F-010),
> `Blocked-by` += `svp-roadmap-backlog-db#2`, fallback-фраза удалена (R3-003/CPR-B); T3 — `write_page(page)`
> + `summary` + `stamp_contradictions` (F-008/R3-004); T5 — схема синтезатора без SHA-полей + `summary`
> + `contradictions[]` + single-line `description` (R3-002/R3-004/R3-007/R3-008); T7 —
> `missing_cross_reference` (R3-005).
> Порядок: 1 → 2 → 3 → 5 → 7 (Stage 1, основание) → 6 → 4 (Stage 2, интеграция).
> Роли — bare (парсер добавляет `mb-` сам). Бюджеты: Stage 1 = 400k, Stage 2 = 190k; итого 590k < 900k.

<!-- mb-task:1 -->
## Task 1: docs_state.py — версионированный стейт, atomic store, docs.path

**Stage:** 1
**Covers:** REQ-006
**Role:** backend
**Blocked-by:** none
**Scope:** memory_bank_skill/docs_state.py, scripts/mb-docs.py, tests/pytest/test_mb_docs_state.py, tests/fixtures/docs-repo/**
**Budget:** 70000

**What to do:**
- `memory_bank_skill/docs_state.py` по C2/C3: чтение/запись `<docs-path>/.mb-docs-state.json`
  (схема `{version, sha, updated_at, pages}`, без `last_run`). Модульный API — `load_state()`,
  `write_state(full_state)`, `resolve_docs_path()`; `write_state` пишет **полный** объект атомарно
  через `memory_bank_skill._io.atomic_write`. Единственный вызывающий `write_state` — `apply` (T4);
  сам модуль прогон не оркестрирует и CLI-подкоманды записи не имеет (C1: `set-sha` как отдельная
  подкоманда снята — это был источник противоречия F-004).
- Резолюция `docs.path`: `--docs-path` > `pipeline.yaml: docs.path` > `docs/`; repo-relative,
  без `..`, без выхода за корень через symlink → иначе exit 2 `error=invalid_docs_path`.
- Обнаружение переноса (C3) — **filesystem-scan, не git-index**: детерминированный C-сортированный
  обход корня репо по имени `.mb-docs-state.json` с исключением `.git/**`, резолвленного
  `docs.path` и путей, чей realpath выходит за корень; видит tracked, untracked и ignored одинаково;
  исполняется только на bootstrap-ветке. Один найден → exit 2 `error=path_mismatch old_path=<p>
  new_path=<resolved>`; несколько → exit 2 `error=ambiguous_state candidates=<sorted-csv>`.
- `scripts/mb-docs.py`: тонкий argparse-скелет (`--repo-root`/`--mb-path`/`--docs-path` + read-only
  подкоманды), в этой задаче подключена только `state` (`packs` — T2, `lint` — T7, `plan` — T4).

**Eval:** `pytest tests/pytest/test_mb_docs_state.py` — red: `memory_bank_skill/docs_state.py` нет, тесты первыми; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_state'|FAILED tests/pytest/test_mb_docs_state\.py::)`

**Testing (TDD — tests BEFORE implementation):**
- pytest на фикстурном git-репо (`tests/fixtures/docs-repo/`); тестовый модуль импортирует
  `memory_bank_skill.docs_state` на верхнем уровне (это и есть объявленная red-сигнатура):
  bootstrap-пустой стейт (`sha=null`); round-trip `write_state` → `load_state` (включая
  `pages.<slug>.source_files`); atomic-запись не оставляет `.tmp`-файлов при успехе и откатывает
  их при смоделированном сбое записи; precedence CLI > pipeline.yaml > дефолт; `invalid_docs_path`
  (`..`, абсолютный путь, symlink наружу).
- `path_mismatch` — **два отдельных теста**: старый стейт git-tracked и старый стейт untracked
  (F-006: обнаружение обязано не зависеть от git-index); плюс ignored-случай через `.gitignore`.
- `ambiguous_state` (несколько кандидатов, `candidates` C-сортирован); кандидат внутри `.git/**`
  игнорируется; symlink наружу не следуется.

**DoD:**
- [ ] C2/C3 реализованы; `state` в `mb-docs.py`; `path_mismatch` детектируется для tracked и untracked; pytest green (был red)
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: docs_ingest.py — diff-паки, bootstrap, деградация источников

**Stage:** 1
**Covers:** REQ-001, REQ-005, REQ-009, REQ-010, REQ-012
**Role:** backend
**Blocked-by:** 1
**Scope:** memory_bank_skill/docs_ingest.py, scripts/mb-docs.py, tests/pytest/test_mb_docs_ingest.py, tests/fixtures/docs-repo/**
**Budget:** 100000

**What to do:**
- `memory_bank_skill/docs_ingest.py` по C10: `packs --since <sha|none>` → JSONL паков
  (`pack_id, mode, community, files, symbols, wiki_refs, excerpts, deleted_files, degraded_sources`);
  лимиты на пак ≤ 12 файлов / ≤ 40 строк excerpt / ≤ 10 символов / ≤ 5 decision-wiki-ссылок
  (детерминированное усечение, не LLM-решение).
- `deleted_files` — repo-relative пути из `git diff --diff-filter=D base..target` (вход для
  `deprecate`-логики C5.1, REQ-012).
- `--since none` (или отсутствующий стейт) → `mode=bootstrap`, полный обзор репо (REQ-005).
- Недостижимый `--since <sha>` → ничего на stdout, stderr `error=unreachable_sha
  suggestion=merge-base|bootstrap`, exit 4 — без тихого полного переобхода.
- Батчирование большого диффа — по модулям graph-коммьюнити (реюз `codegraph_analytics`,
  детерминированно).
- Чтение `graph.json` и `<bank>/codebase/wiki/` строго read-only (REQ-009); отсутствие/нечитаемость
  любого из них → продолжение из git diff + excerpt'ов, `degraded_sources` в выводе (REQ-010), файлы
  не создаются и не изменяются.
- Подключить `packs` в `scripts/mb-docs.py`.

**Eval:** `pytest tests/pytest/test_mb_docs_ingest.py` — red: `memory_bank_skill/docs_ingest.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_ingest'|FAILED tests/pytest/test_mb_docs_ingest\.py::)`

**Testing (TDD — tests BEFORE implementation):**
- pytest на `tests/fixtures/docs-repo/` (импорт `memory_bank_skill.docs_ingest` на верхнем уровне):
  bootstrap без стейта; delta от валидной SHA; недостижимая SHA → exit 4 + подсказка; батч
  гигантского диффа режется по коммьюнити; лимиты пака соблюдены на синтетическом большом паке.
- `deleted_files` заполняется ровно удалёнными путями диапазона; переименование (`R`) не попадает в
  `deleted_files` как удаление.
- `graph.json`/`<bank>/codebase/wiki/` отсутствуют → `degraded_sources` содержит оба, ни один файл
  источника не создан; ни один тест не открывает источники на запись.

**DoD:**
- [ ] C10 + REQ-001/005/009/010/012 (`deleted_files`) реализованы; `packs` в `mb-docs.py`; pytest green (был red)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: docs_store.py — атомарная запись pages/index/log + deprecation-штамп

**Stage:** 1
**Covers:** REQ-002, REQ-003, REQ-012
**Role:** backend
**Blocked-by:** 1
**Scope:** memory_bank_skill/docs_store.py, tests/pytest/test_mb_docs_store.py, tests/fixtures/wiki-ok/**, tests/fixtures/wiki-broken/**
**Budget:** 80000

**What to do:**
- `memory_bank_skill/docs_store.py` по C4 — **модульный API, вызываемый только из `apply` (T4)**;
  собственных CLI-подкоманд не заводит (C1): `write_page(page)` — `page` = writer-ready dict C6
  (`{slug, title, summary, body_markdown, source_files, wikilinks}`); slug-валидация `^[a-z0-9-]+$`,
  иначе `ValueError` → `apply` отдаёт exit 5; рендерит layout C4 (H1 `# <title>`, управляемый
  summary-блок `<!-- mb-docs:summary -->…`, тело), atomic-запись `pages/<slug>.md`; `title`, `summary`
  и `wikilinks` **потребляются** (F-008: прежняя сигнатура `write_page(slug, body)` их игнорировала);
  `log_append(op, description, run_id)` (append-only `## [YYYY-MM-DD] <op> | run=<run_id> <desc>`,
  создаёт файл+заголовок при первом вызове); `regenerate_index()` (полная регенерация `index.md` из
  содержимого `pages/` — `Title` из H1, `one-line` из summary-блока, категория = префикс slug до
  первого `-`).
- **Идемпотентность журнала (C5.4)**: `log_append` под локом читает `log.md` и при найденной строке
  с `run=<run_id>` возвращает `{"appended": false}`, ничего не записав. Префикс `run=<run_id>`
  формирует код, не LLM.
- **Deprecation-штамп (C5.3, REQ-012)**: `stamp_deprecated(slug, deleted_files, target_sha)` —
  replace-or-insert управляемого блока `<!-- mb-docs:status -->…<!-- /mb-docs:status -->` сразу
  после H1; идемпотентно (повтор заменяет тот же блок, не стопкой); страница не удаляется, прежнее
  тело сохраняется.
- **Рендер противоречий (C5.5, REQ-004/R3-004)**: `stamp_contradictions(slug, records)` —
  replace-or-insert управляемого блока `<!-- mb-docs:contradictions -->## Contradictions…<!--
  /mb-docs:contradictions -->` сразу после summary; каждая запись рендерится как `superseded`/`current`
  с evidence-путями; идемпотентно. `## Contradictions` больше НЕ приходит внутри `body_markdown` —
  его пишет код из структурной записи (валидацию evidence-путей делает `apply`, T4).
- Ни один writer не открывает `graph.json`/`<bank>/codebase/wiki/`/исходники проекта на запись
  (REQ-003 — источники immutable).

**Eval:** `pytest tests/pytest/test_mb_docs_store.py` — red: `memory_bank_skill/docs_store.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_store'|FAILED tests/pytest/test_mb_docs_store\.py::)`

**Testing (TDD — tests BEFORE implementation):**
- pytest (импорт `memory_bank_skill.docs_store` на верхнем уровне): невалидный slug отклонён;
  `write_page(page)` рендерит H1 из `title`, summary-блок из `summary`, тело из `body_markdown`
  (**title/summary/wikilinks фактически потребляются** — F-008); atomic-запись page/log/index (нет
  `.tmp` при успехе, откат при смоделированном сбое); `log_append` создаёт файл+заголовок на первом
  вызове и только append-ит дальше; строка матчит грамматику C4 включая `run=`; **повторный
  `log_append` с тем же `run_id` → `{"appended": false}` и файл побайтно не изменился**;
  `regenerate_index` детерминированно регенерируется из фикстуры `pages/` (`Title` из H1, `one-line`
  из summary-блока).
- `stamp_deprecated`: блок вставлен после H1, содержит все `deleted_files` и target SHA; повторный
  вызов не дублирует блок (идемпотентность); тело страницы ниже блока не изменилось; файл существует.
- `stamp_contradictions` (R3-004): управляемый блок `## Contradictions` вставлен после summary,
  содержит `superseded`/`current` + evidence-пути; повторный вызов не дублирует блок; тело ниже цело.

**DoD:**
- [ ] C4 + C5.3/C5.4/C5.5-части реализованы; `write_page(page)` потребляет title/summary/wikilinks (F-008); идемпотентность `log_append` по `run_id` доказана тестом; pytest green (был red)
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: docs_run.py — шов прогона (plan/apply) + команда /mb docs

**Stage:** 2
**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-007, REQ-009, REQ-011, REQ-012
**Role:** developer
**Blocked-by:** 1, 2, 3, 5, 6, 7, svp-roadmap-backlog-db#2
**Scope:** memory_bank_skill/docs_run.py, scripts/mb-docs.py, scripts/mb-docs-apply.sh, commands/mb.md, tests/pytest/test_mb_docs_run.py, tests/fixtures/docs-repo/**
**Budget:** 120000

**What to do:**
- `memory_bank_skill/docs_run.py` — детерминированный шов прогона (C5), **вся** run-логика здесь,
  не в прозе промпта:
  - `plan` (C5.1, read-only): резолв `docs.path` (T1) → `dirty_worktree` (exit 2) → `target_sha=HEAD`,
    `base_sha=state.sha|bootstrap`, `run_id="<base>..<target>"` → пустой дифф → `{"result":"noop"}`,
    exit 0 → **резолв транспорта (C7) до паков**, ненулевой caps → exit 6 → паки (T2) +
    `deprecate`-список (слаг попадает, когда ВСЕ его `state.pages[slug].source_files` есть в
    `deleted_files`) → печать одного JSON-объекта схемы C5.1.
  - `apply --plan <plan> --results <results>` (C5.2, единственный writer): авторитетные поля
    (`run_id`/`base_sha`/`target_sha`/`docs_path`/`deprecate`/`degraded_sources`) — ТОЛЬКО из `--plan`
    (R3-002) → валидация плана (`run_id == <base>..<target>`, `target_sha` достижим → иначе exit 5
    `invalid_plan`) → **`expected_base = state.sha|bootstrap`** (R3-001: первый bootstrap не `stale_run`),
    `plan.base_sha != expected_base` → exit 5 `stale_run` → валидация результатов по C6 (посторонний
    ключ / пустой `source_files` / multiline `description` / битый evidence-путь → exit 5
    `invalid_agent_result`) → **pages → log → index → state-temp → lint → os.replace(state-temp→state)**,
    каждый durable-файл атомарно, финальный стейт только после зелёного lint (F-010) → печать
    `{"run_id","sha","pages","degraded_sources","result":"applied"}` (degraded_sources из плана, REQ-010).
  - **Рендер противоречий (C5.5, REQ-004)**: для каждой записи `results.contradictions` — валидация
    evidence-путей + детерминированная вставка управляемого блока `## Contradictions` на страницу;
    `## Contradictions` НЕ приходит внутри `body_markdown`.
  - Манифест (C8): `{run_id, durable_writes_completed[], control_writes[], pending_state_path,
    sources{path: sha256}}`; пишется во временный файл и передаётся `lint --manifest`; красный lint →
    exit 5, финальный стейт не появляется (F-010).
- `scripts/mb-docs-apply.sh` — bash-обёртка write-пути: `mb_lock_acquire "<docs-path>/.mb-docs.lock"
  5 30` из `scripts/_lib.sh` (владелец — S4-C6; helper обязан существовать до T4 — жёсткое ребро
  `Blocked-by: … svp-roadmap-backlog-db#2`; **отсутствие `mb_lock_acquire`/`mb_lock_release` после
  закрытого `svp-roadmap-backlog-db#2` — contract violation, T4 не стартует**, fallback-реализация в
  `_lib.sh` запрещена как нарушение Scope, R3-003/CPR-B), `trap 'mb_lock_release …' EXIT INT TERM`,
  timeout → exit 7 `error=locked`; затем `python3 -m memory_bank_skill.docs_run apply --plan … --results …`
  **своим ребёнком** (владелец лока обязан жить всю критическую секцию — C5.2) с пробросом exit-кода.
- `scripts/mb-docs.py`: подключить `plan`; финальная сборка тонкого read-only диспатчера
  (`state`/`packs`/`plan`/`lint`) из модулей T1/T2/T7.
- Блок `### docs` + строка Routing в `commands/mb.md`: **только** диспатч — `mb-docs.py plan`
  (`--dry-run` = стоп здесь; stdout плана сохраняется в `<bank>/tmp/docs-plan-<run_id>.json` как есть) →
  Haiku `mb-docs-author` по паку → Sonnet `mb-docs-synthesizer` → запись их JSON в
  `<bank>/tmp/docs-results-<run_id>.json` (D-23) → `bash scripts/mb-docs-apply.sh --plan
  <bank>/tmp/docs-plan-<run_id>.json --results <bank>/tmp/docs-results-<run_id>.json`. Никакой
  run-логики в промпте.

**Eval:** `pytest tests/pytest/test_mb_docs_run.py` — red: `memory_bank_skill/docs_run.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_run'|FAILED tests/pytest/test_mb_docs_run\.py::)`

**Testing (TDD — tests BEFORE implementation):**
- Все тесты гоняют **production-CLI** (`scripts/mb-docs.py plan`, `bash scripts/mb-docs-apply.sh`)
  на `tests/fixtures/docs-repo/` с фикстурным файлом результатов агентов и `MB_CAPS_FIXTURE` —
  модель прогона не пересобирается (LLM-часть — вне кода, см. design § «Что здесь НЕ проверяется
  кодом»).
- Инкремент (Scenario 1): только затронутые страницы, index+log обновлены (журнальная строка несёт
  обязательный `run=<run_id>` — R3-006), SHA продвинут.
- **Первый bootstrap-apply (Scenario 2, R3-001)**: `state.sha=null`, `plan.base_sha="bootstrap"` →
  `apply` НЕ падает в `stale_run`, записывает target SHA + bootstrap-строку журнала
  `## [<date>] bootstrap | run=bootstrap..<target> …`.
- **План-авторитет (R3-002)**: `apply --plan … --results …` берёт SHA/`deprecate`/`degraded_sources`
  из плана; результаты с посторонним ключом `run_id`/`base_sha`/`target_sha` → exit 5
  `invalid_agent_result` (модель не может продвинуть стейт на подменённый SHA); план с
  `run_id ≠ <base>..<target>` или недостижимым `target_sha` → exit 5 `invalid_plan`; `degraded_sources`
  плана присутствует в финальном `applied`-выводе (REQ-010).
- **Противоречие (Scenario 3, REQ-004/R3-004)**: `results.contradictions` несёт запись со
  структурными полями → `apply` валидирует evidence-пути и рендерит управляемый `## Contradictions`
  детерминированно; malformed/несуществующий evidence-путь → exit 5, ноль записей; молчаливой замены
  прежнего факта нет (он остаётся как `superseded`).
- **Cross-reference (Scenario 6, R3-005)**: две страницы с взаимными `[[slug]]` → после `apply` lint
  green; вики без единой межстраничной ссылки при > 1 non-deprecated странице → lint
  `error=missing_cross_reference`; хеши graph/wiki/source неизменны.
- **Порядок записи pages→log→index→state-temp→lint→state**: смоделированный сбой после pages
  оставляет `state.sha` прежним; повторный прогон переигрывает тот же диапазон; финальный стейт
  появляется ТОЛЬКО после зелёного lint (F-010).
- **Crash после записи журнала (F-005)**: сбой между шагами 7 и 10 → повторный `apply` с тем же `run_id`
  → в `log.md` **ровно одна** строка этого `run_id` (идемпотентность C5.4), SHA продвинут один раз.
- **Живой лок (F-005)**: параллельный `mb-docs-apply.sh` при удерживаемом локе живого владельца →
  exit 7 `error=locked`, ноль записей — **включая лок старше 1ч** (TTL не является сигналом
  reclaim'а: живой владелец не вытесняется, S4-C6 ревизии 4); мёртвый владелец (`kill -9` держателя) →
  следующий прогон реклеймит лок (targeted `rmdir owner.<D>`) и проходит.
- `stale_run`: `plan.base_sha`, не равный текущему `expected_base` → exit 5, ноль записей.
- **Multiline `description` (R3-007)**: `log_entry.description` с CR/LF или префиксом `## [` → exit 5
  `invalid_agent_result` на шаге валидации ДО любой записи; повтор с валидным `description` затем проходит.
- **Пустой `source_files` (R3-008)**: страница результатов с `source_files: []` → exit 5
  `invalid_agent_result`; легаси-стейт с пустым `source_files` + удаление файлов → страница НЕ
  депрекейтится, `degraded_sources` несёт `page_provenance:<slug>`.
- Dirty worktree → exit 2; пустой diff → no-op без изменения файлов; `plan` не пишет ничего
  (снимок дерева до/после побайтно равен).
- **REQ-011 / Scenario 9**: `MB_CAPS_FIXTURE` без транспорта → `plan` exit 6, stderr
  `result=platform_limited platform_limited=subagent-dispatch role=docs_author`, ноль записанных
  файлов; незарегистрированная роль (caps exit 1) → тот же exit 6 с `hint=`.
- **REQ-007 / Scenario 5 (сквозная, R2-003)**: pipeline `docs.path: project-wiki/`; снимок `docs/**`
  до прогона; полный прогон → `project-wiki/{index.md,log.md,pages/<slug>.md,.mb-docs-state.json}`
  существуют и стейт указывает на target SHA; манифест не содержит путей вне `project-wiki/`;
  `docs/**` побайтно идентичен снимку.
- **REQ-012 / Scenario 10**: стейт со страницей `parser-core` (`source_files: ["src/parser.py"]`) +
  дифф, удаляющий `src/parser.py` → `plan.deprecate` содержит слаг; после `apply` страница
  существует, несёт `Status: deprecated`, удалённый путь и target SHA, прежнее тело цело.
  Частичное удаление источников страницы → в `deprecate` НЕ попадает.
- `commands/mb.md` — структурная проверка (граница честности): блок `### docs` вызывает
  `mb-docs.py plan` и `mb-docs-apply.sh --plan … --results …`, и не содержит собственной run-логики
  (нет вызовов writer'ов в обход `apply`).

**DoD:**
- [ ] C5/C6/C7 реализованы в `docs_run.py` + обёртке; `apply --plan --results` привязан к плану (R3-002); bootstrap не `stale_run` (R3-001); `plan` в `mb-docs.py`; блок `### docs` только диспатчит; сценарии 1/2/3/5/6/9/10 отрабатывают кодом; pytest green (был red)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Сабагенты-авторы — контракты вывода

**Stage:** 1
**Covers:** REQ-002, REQ-004
**Role:** developer
**Blocked-by:** none
**Scope:** agents/mb-docs-author.md, agents/mb-docs-synthesizer.md, tests/pytest/test_mb_docs_agents.py
**Budget:** 60000

**What to do:**
- `agents/mb-docs-author.md` (Haiku, одна страница из пака за вызов): возвращает ровно один JSON
  по C6 (`{"page": {slug, title, summary, body_markdown, source_files, wikilinks}}`), без другого
  текста; `summary` — непустая строка 1–200 символов без CR/LF (F-008); `source_files` — **непустой
  уникальный** массив repo-relative путей (R3-008); без wikilinks на несуществующие/непереданные
  пакой страницы; запрет правок кода/источников.
- `agents/mb-docs-synthesizer.md` (Sonnet, кросс-страничный проход): возвращает ровно один JSON по
  C6 — `{pages[], contradictions[], log_entry{op, description}}` (**без `run_id`/`base_sha`/`target_sha`**
  — их источник авторитетный план, R3-002), где `pages[]` — **финальные** writer-ready страницы (те же
  имена полей, что у автора, включая `summary`); найденные противоречия возвращаются **структурным
  массивом** `contradictions[{slug, old_claim, new_claim, old_evidence, new_evidence}]` (REQ-004/R3-004)
  — код валидирует evidence-пути и рендерит `## Contradictions`, модель НЕ рендерит его в `body_markdown`.
  Поля `index_entries` больше нет; `log_entry` несёт только `op ∈ {ingest,bootstrap}` + **single-line
  `description` без CR/LF, `## [`, `run=`, NUL** (R3-007) — `run=`-префикс и SHA добавляет код.
- Оба агента: tool list **без** Write/Edit — единственный writer — `apply` (D-23); никакого
  report-delivery/SendMessage контракта (в отличие от `mb-wiki-*`, у этих агентов вывод — тело
  ответа, не файл/сообщение).

**Eval:** `pytest tests/pytest/test_mb_docs_agents.py` — red: `agents/mb-docs-author.md` и `agents/mb-docs-synthesizer.md` нет; exit: 1; output~: `FAILED tests/pytest/test_mb_docs_agents\.py::`

**Testing (TDD — tests BEFORE implementation):**
- pytest на статическом содержимом `.md`-файлов агентов (тест читает файлы, поэтому red — обычный
  `FAILED`, не ImportError): заявлен корректный tier (Haiku/Sonnet); выходная JSON-схема описана
  дословно по C6 в промпте; **имена полей страницы совпадают с writer API байт-в-байт** (перечень
  ключей сверяется со схемой C6 как со списком-эталоном, а не глазами) — включая `summary` (F-008);
  **синтезатор НЕ объявляет `run_id`/`base_sha`/`target_sha`** (R3-002) и несёт структурный
  `contradictions[]` (R3-004); отсутствуют Write/Edit в объявленных tools; явный запрет прямой записи
  в банк/источники сформулирован текстом.

**DoD:**
- [ ] Оба агента с точными output-контрактами C6 (включая `summary`, `contradictions[]`, без SHA-полей у синтезатора), без write-инструментов; схемы совместимы с `apply` по именам полей; pytest green (был red)
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: docs.path + роли docs_author/docs_synthesizer в pipeline.yaml + dogfood override

**Stage:** 2
**Covers:** REQ-007
**Role:** developer
**Blocked-by:** 1, svp-sdd-core#7
**Scope:** references/pipeline.default.yaml, scripts/mb-pipeline-validate.sh, tests/bats/test_mb_docs_pipeline.bats
**Budget:** 70000

**What to do:**
- Секция `docs: {path: docs/}` в `references/pipeline.default.yaml` (C9).
- **Роли** в том же файле (C9, без них C7 не резолвит транспорт — `mb-agent-caps.sh` отклоняет роль
  без `model`, `:241-244`): `docs_author: {agent: mb-docs-author, model: haiku}`,
  `docs_synthesizer: {agent: mb-docs-synthesizer, model: sonnet}`.
- `mb-pipeline-validate.sh`: `docs` — опциональный top-level ключ; если присутствует — маппинг с
  ровно одним обязательным строковым ключом `path` (repo-relative, не абсолютный, без `..`);
  отсутствие ключа — не ошибка (легаси); неверный тип/лишние ключи — структурная ошибка (закрывает
  прежний молчаливый green на произвольном `docs:`, F-009).
- Для этого репозитория: override `.memory-bank/pipeline.yaml` — `docs.path: project-wiki/` (вне
  `mkdocs docs_dir`, AGR-010) **и обе роли** (резолвер пайплайна — file-substitution, а не merge:
  `mb-agent-caps.sh:120-137` — при наличии проектного файла дефолт игнорируется целиком, поэтому без
  этой записи догфуд-прогон дал бы exit 6). Фиксируется здесь, применяется отдельно оркестратором в
  work-фазе (банк пишет только оркестратор, D-23).
- Использует resolver из `docs_state.py` (T1) для bats-проверки реального разрешения пути, а не
  только наличия YAML-ключа.

**Eval:** `bats tests/bats/test_mb_docs_pipeline.bats` — red: `docs.path`/роли/валидатор не расширены; exit: 1; output~: `not ok [0-9]+ docs\.path: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста начинается с
  `docs.path: `. Причина: `bats` на отсутствующем файле даёт exit 1 + `not ok 1 bats-gather-tests`,
  то есть exit-only якорь принял бы «файла нет» за red; ERE не поддерживает negative lookahead,
  поэтому якорь опирается на положительный именованный префикс, которого у `bats-gather-tests` нет.
- bats: дефолт `docs/` при отсутствии `docs:`; project override резолвится; неверный тип `path`
  (число/список) → структурная ошибка; абсолютный путь → ошибка; `..` → ошибка; symlink escape →
  ошибка; `mb-pipeline-validate.sh` принимает валидный `docs:` и отвергает произвольный/битый.
- Роли: `bash scripts/mb-agent-caps.sh resolve --role docs_author --mb <fixture-bank>` под
  `MB_CAPS_FIXTURE` → exit 0 + `transport=`/`model=`; то же для `docs_synthesizer`; бэнк-фикстура
  **без** этих ролей → exit 1 (это и есть вход REQ-011, потребляемый T4).
- Сквозной Scenario 5 (occupied docs directory) исполняется кодом в T4 (`Blocked-by: … 6`) —
  здесь проверяется только резолв конфига.

**DoD:**
- [ ] Конфиг + роли + валидатор + dogfood-override зафиксированы; `caps resolve` для обеих ролей зелёный на фикстуре; bats green (был red)
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: docs_lint.py — структурный lint вики + проверка манифеста

**Stage:** 1
**Covers:** REQ-008
**Role:** backend
**Blocked-by:** 1, 3
**Scope:** memory_bank_skill/docs_lint.py, scripts/mb-docs.py, tests/bats/test_mb_docs_lint.bats, tests/fixtures/wiki-ok/**, tests/fixtures/wiki-broken/**, tests/fixtures/docs-manifest/**
**Budget:** 90000

**What to do:**
- `memory_bank_skill/docs_lint.py` по C8. **Структурные коды** (вычислимы из дерева вики):
  `missing_index`, `missing_log`, `invalid_log_entry` (грамматика C4 включая обязательный
  `run=<run_id>`), `orphan_page`, `missing_index_entry`, `invalid_index_entry`, `broken_wikilink`,
  **`missing_cross_reference`** (> 1 non-deprecated страницы, но ни одной резолвящейся `[[other-slug]]`
  между разными страницами — положительная проверка REQ-003, R3-005) — каждое нарушение печатает
  `error=<code> path=<...>`; переиспользует парсинг формата index/log/wikilink из `docs_store.py` (T3)
  вместо дублирования регулярок (DRY).
- **`source_leakage` — из явного входа** (C8, F-010): флаг `--manifest <path>`; манифест
  `{run_id, durable_writes_completed[], control_writes[], pending_state_path, sources{path: sha256}}`
  пишет `apply` (T4) и всегда его передаёт.
  - `durable_writes_completed` вне docs-path или вне шаблонов `pages/**`/`log.md`/`index.md` →
    `error=source_leakage path=<p> reason=write_outside_docs_path`;
  - `control_writes` вне разрешённых шаблонов (`.mb-docs.lock/**`, temp-манифест,
    `.mb-docs-state.json.tmp`) → тот же `write_outside_docs_path`; **честные лок и temp-стейт этого же
    прогона leakage НЕ дают** (регресс на противоречие F-010);
  - `pending_state_path ≠ <docs-path>/.mb-docs-state.json` → `reason=bad_pending_state`;
  - `sources` перехешируются и сверяются с записанными до прогона → расхождение →
    `error=source_leakage path=<p> reason=source_mutated` (REQ-003/009 в проде, не только в тесте).
  - `--manifest` не передан → структурные проверки идут, manifest-проверки пропускаются с ГРОМКОЙ
    строкой `note=manifest_absent source_leakage=unchecked` (тихого пропуска нет).
- `lint` — внутренняя подкоманда, не публичный флаг (C8, закрытое решение — F-011); подключить в
  `scripts/mb-docs.py`. Отсутствие `--docs-path` — **не** ошибка (C3 precedence/default); exit 2
  только на явно переданный невалидный `--docs-path`, нечитаемый манифест или нечитаемый стейт.
- Фикстуры — первыми, до реализации: `tests/fixtures/wiki-ok/` (валидная вики со взаимными
  wikilinks), `tests/fixtures/wiki-broken/` (по одному нарушению каждого структурного типа, включая
  вики > 1 страницы без единой межстраничной ссылки для `missing_cross_reference`),
  `tests/fixtures/docs-manifest/` (манифесты: чистый с честными control-writes; с durable-write вне
  docs-path; с посторонним control-write; с `pending_state_path ≠ …`; с изменённым источником;
  нечитаемый).

**Eval:** `bats tests/bats/test_mb_docs_lint.bats` — red: `memory_bank_skill/docs_lint.py` нет; exit: 1; output~: `not ok [0-9]+ docs lint: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста начинается с
  `docs lint: ` (обоснование — то же, что в T6: `bats` на отсутствующем файле даёт `not ok 1
  bats-gather-tests` с тем же exit 1, поэтому якорь обязан быть положительным и именованным).
- bats на фикстурах: `wiki-ok` + чистый манифест → exit 0, пустой вывод; `wiki-broken` → exit 1,
  отдельная проверка на КАЖДЫЙ структурный код (не «любой ненулевой») — по одному `error=<code>`
  на строку, **включая `missing_cross_reference`** (R3-005: вики > 1 non-deprecated страницы без
  межстраничных ссылок → нарушение; одна страница или вики со взаимными `[[slug]]` → чисто).
- `source_leakage`: манифест с `durable_writes_completed` вне docs-path → exit 1 + `error=source_leakage
  reason=write_outside_docs_path`; посторонний `control_write` → тот же код; `pending_state_path ≠
  <docs-path>/.mb-docs-state.json` → `reason=bad_pending_state`; манифест с изменённым `sources`-хешем
  → exit 1 + `reason=source_mutated`; манифест с честными control-writes (`.mb-docs.lock/**`,
  temp-манифест, `.mb-docs-state.json.tmp`) → **exit 0** (легитимны, регресс-тест на противоречие F-010).
- `--manifest` не передан → структурные коды работают, на stdout ровно одна строка
  `note=manifest_absent source_leakage=unchecked`.
- malformed: нечитаемый манифест → exit 2; нечитаемый `.mb-docs-state.json` → exit 2; **отсутствие
  `--docs-path` → НЕ ошибка** (резолвится по C3; регресс-тест на противоречие ревизии 2).

**DoD:**
- [ ] 8 структурных кодов (включая `missing_cross_reference`, R3-005) + `source_leakage` из манифеста нового формата (durable/control/pending-state, F-010) реализованы; `lint` в `mb-docs.py`; честные control-writes не дают ложный `source_leakage`; bats green (был red)
<!-- /mb-task:7 -->
