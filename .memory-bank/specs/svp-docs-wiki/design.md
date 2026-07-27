# Design: svp-docs-wiki

> Слайс S6. Контракты и Eval-декларации (D-05); код — в work-фазе. Читать транскрипты (D-29).
> Ревизия 3 (2026-07-17): закрыт круг 2 spec-ревью. Введён детерминированный шов прогона
> (`plan`/`apply`, R2-002); `apply` назначен ЕДИНСТВЕННЫМ writer'ом (F-004/F-008); lock потребляется
> из S4-C6 по протоколу umbrella Interface 2 и держится живым процессом (F-005); повтор после краха
> идемпотентен по `run_id`; `path_mismatch` детектируется без git-index (F-006); транспорт
> резолвится реальным `mb-agent-caps.sh` (F-007); `source_leakage` вычисляется из манифеста —
> явного входа линтера (F-010); REQ-012 (deprecated-страницы) возвращён из контекста (R2-004);
> Eval'ы несут `output~:`-якоря настоящего провала (umbrella Interface 1 / S2-X-05).
> Ревизия 4 (2026-07-18, круг 3): bootstrap больше не `stale_run` (R3-001); `apply --plan --results`
> привязан к авторитетному плану, SHA/deprecate/degraded_sources не подменяются LLM (R3-002); page
> schema несёт `summary` (F-008); manifest lifecycle разведён на durable/control/pending-state (F-010);
> REQ-004 — кодовый рендер `contradictions[]` (R3-004); положительный `missing_cross_reference` (R3-005);
> `log_entry.description` валидируется до записи (R3-007); пустой `source_files` не депрекейтит (R3-008);
> lock выровнен на S4-C6 ревизии 4 (owner-marker + targeted `rmdir`), жёсткая зависимость от
> `svp-roadmap-backlog-db#2`, fallback удалён (R3-003/CPR-B).

## Architecture

Паттерн `/mb wiki` (детерминированная подготовка Python + LLM-сабагенты через хост, без API-ключа),
но над **кодом проекта → docs/**:

1. **Детерминированные модули** `memory_bank_skill/`:
   - `docs_state.py` — версионированный run-стейт (C2), atomic store, resolution/migration `docs.path` (C3).
   - `docs_ingest.py` — git diff от последней SHA, bootstrap-режим, батчирование по graph-коммьюнити,
     чтение `graph.json` + `<bank>/codebase/wiki/` как read-only источников фактов (REQ-009),
     честная деградация при их отсутствии (REQ-010, C7), список удалённых файлов (REQ-012, C10).
   - `docs_store.py` — атомарная запись `pages/<slug>.md`, `index.md`, `log.md`, deprecation-штамп (C4).
   - `docs_lint.py` — структурный lint вики + проверка манифеста (REQ-008, C8).
   - `docs_run.py` — **шов прогона** (C5): state machine `plan`/`apply`, вызываемая CLI'ем.
2. **CLI** — `scripts/mb-docs.py` (тонкий argparse-диспатчер read-only субкоманд) +
   `scripts/mb-docs-apply.sh` (bash-обёртка write-пути: держит lock и запускает писателя), C1.
3. **Prompt** `commands/mb.md § docs` (+ строка в Routing) — только диспатч сабагентов между
   `plan` и `apply` (C5, шаг 2): паки → Haiku `mb-docs-author` (по странице) → Sonnet
   `mb-docs-synthesizer` (кросс-страничные связи, противоречия) → сохранение их JSON в
   `<bank>/tmp/docs-results-<run_id>.json` → `mb-docs-apply.sh --results <файл>`.
4. **Конфиг** `docs.path` + роли `docs_author`/`docs_synthesizer` в
   `references/pipeline.default.yaml` (C9); в этом репозитории — dogfood override вне дерева MkDocs.

### Что здесь НЕ проверяется кодом (честная граница, закрывает R2-002/R2-003)

Генерация текста страниц — LLM-слой. Детерминированного шва «прогнать сабагента в тесте» не
существует, и S6 его не изобретает (образец — S3-C7 и S8 § «Что здесь НЕ проверяется кодом»).

- **Кодом проверяется** всё детерминированное: резолвер `docs.path` (C3), паки (C10), шов прогона
  `plan`/`apply` (C5) — порядок записи, lock, run_id-идемпотентность, `stale_run`, deprecation-штамп,
  **рендер противоречий из структурной записи (C5.5, REQ-004)**, platform_limited, манифест, — writer
  API (C4), линтер (C8, включая положительный `missing_cross_reference`), резолвер конфига (C9) и
  **детерминированные артефакты ПОСЛЕ прогона** (пути, структура, метаданные, хеши источников).
  Тесты гоняют **production-CLI** с фикстурным планом + файлом результатов агентов и фикстурой
  `MB_CAPS_FIXTURE` — не модель прогона.
- **Промптом остаётся** качество текста страницы, **семантическое обнаружение** противоречия (какой
  факт устарел — синтезатор наполняет структурную запись `contradictions[]`) и выбор wikilinks. Это
  подтверждается ревьюером и spec-review (S2-C5), а не фиктивным pytest'ом на промпт-файле. **Валидация
  и рендер** структурной записи противоречия — уже код (C5.5), поэтому REQ-004 наблюдаем на CLI.
  Тест на `commands/mb.md` проверяет ровно одно: что блок `### docs` вызывает `plan` → `apply`
  именно этим контрактом (структурная проверка текста, а не поведения LLM).

## Interfaces

### C1. CLI-контракт

```
python3 scripts/mb-docs.py [--repo-root PATH] [--mb-path PATH] [--docs-path PATH] <subcommand> [args]
bash    scripts/mb-docs-apply.sh --plan PATH --results PATH [--repo-root PATH] [--mb-path PATH] [--docs-path PATH]
```

**`apply` связан с авторитетным `plan` (закрывает R3-002).** `--plan` — сохранённый оркестратором
**без изменений** stdout `mb-docs.py plan` (детерминированный, read-only артефакт C5.1); `--results` —
JSON синтезатора, несущий **только** содержимое агентов (`pages`, `contradictions`, `log_entry`).
Все идентификаторы прогона (`run_id`, `base_sha`, `target_sha`), `docs_path`, `deprecate` и
`degraded_sources` берутся ИСКЛЮЧИТЕЛЬНО из `--plan`; LLM-диспатч физически не может их подменить,
т.к. в схеме `--results` этих полей нет (C6).

**Read-only субкоманды** `mb-docs.py` (ни одна не пишет в вики — диспатчер тонкий, каждая делегирует
в модуль из Architecture):

| Subcommand | Args | stdout | Модуль |
|---|---|---|---|
| `state` | — | один JSON объект — схема C2; отсутствующий стейт печатает bootstrap-пустой `{"version":1,"sha":null,"updated_at":null,"pages":{}}`, exit 0 (не ошибка — REQ-005) | `docs_state.py` |
| `packs --since <sha\|none>` | `--since` обязателен | JSONL, один пак на строку — схема C10 | `docs_ingest.py` |
| `plan [--json]` | — | один JSON объект — план диспатча, схема C5.1 | `docs_run.py` |
| `lint [--manifest PATH]` | — | по одной строке `error=<code> ...` на нарушение; пусто при отсутствии нарушений | `docs_lint.py` |

**Write-путь — ровно один**: `scripts/mb-docs-apply.sh` (C5.2). Отдельных `write-page`/`log-append`/
`index`/`set-sha` субкоманд **нет** — они были источником противоречия ревизии 2 (F-004: стейт
объявлял `pages.<slug>.source_files`, а `set-sha` принимал только SHA и не мог их записать).
Функции `docs_store.py`/`docs_state.py` остаются модульным API (тестируются pytest'ом напрямую),
но наружу их дёргает только `apply` — «единственный writer» стал свойством конструкции, а не
дисциплины промпта.

**Exit-коды** (общие для `mb-docs.py` и `mb-docs-apply.sh`):

| Exit | Значение |
|---|---|
| `0` | успех / no-op |
| `2` | usage / схема / containment CLI-аргументов: `invalid_docs_path`, `path_mismatch`, `ambiguous_state`, malformed `--since <sha>`, `dirty_worktree` |
| `3` | git недоступен или каталог не git-репозиторий |
| `4` | недостижимый base SHA (`plan`/`packs`) |
| `5` | I/O или validation failure (`apply`): `invalid_agent_result` (**включая malformed slug**, пустой `source_files`, multiline `description`, невалидный evidence-путь противоречия — см. ниже), `invalid_plan` (план сам-несогласован: `run_id ≠ <base_sha>..<target_sha>` или `target_sha` — не достижимый 40-hex commit), `stale_run`, красный lint |
| `6` | `platform_limited` — транспорт диспатча не резолвится (C7) |
| `7` | lock-timeout (`error=locked`) — живой владелец не отдал лок за timeout (C5.2) |

`lint` — отдельное правило: `0` чисто, `1` есть нарушения, `2` usage/схема.

**Malformed slug — ровно один код, 5** (ревизия 2 противоречила себе: C1 относила его к exit 2, а T3
требовала exit 5 — это и был предмет F-004). Разрешено конструкцией: после снятия `write-page`
подкоманды slug больше не приходит CLI-аргументом — он приходит **только** внутри файла результатов
агентов, то есть невалидный slug есть частный случай `invalid_agent_result` → exit 5. Никакой
CLI-поверхности, способной принять slug, не осталось, поэтому exit 2 для slug недостижим по
построению, а не по договорённости.

### C2. Стейт `<docs-path>/.mb-docs-state.json`

```json
{
  "version": 1,
  "sha": null,
  "updated_at": null,
  "pages": {
    "<slug>": {"source_files": ["<repo-relative>", "..."], "updated_at": "<RFC3339>"}
  }
}
```

Поле `last_run` из ревизии 1 удалено — единственная метка времени последнего прогона это top-level
`updated_at`.

**Единственный writer стейта — `apply`** (закрывает F-004). Он пишет **полный** объект целиком,
атомарно (`memory_bank_skill._io.atomic_write` — temp+`os.replace`), ровно один раз, **последним
шагом** прогона (C5.2, шаг 8). `pages.<slug>` собирается из провалидированных результатов агентов:
`source_files` — из поля `source_files` страницы (C6), `updated_at` — время записи. Ни одна другая
команда стейт не изменяет; `state`/`plan`/`packs`/`lint` — read-only.

**У метаданных есть потребитель** (иначе они были бы мёртвым полем): `plan` читает
`state.pages[slug].source_files`, чтобы сопоставить удалённые файлы диффа со страницами и выдать
`deprecate`-действия (C5.1, REQ-012). Недостижимый `sha`, переданный в `packs --since`, не читает и
не трогает этот файл — обрабатывается в `docs_ingest.py` (C10).

**Кардинальность `source_files` (закрывает R3-008 — вакуумный deprecate):** у новой или
обновлённой non-deprecated страницы `source_files` обязан быть **непустым уникальным** массивом
repo-relative путей — это гарантирует C6 (пустой массив в результатах агентов → `invalid_agent_result`,
exit 5). Легаси-стейт, попавший в файл до этого правила с пустым `source_files`, не роняет прогон: его
обрабатывает deprecate-гард C5.1 (пустой массив НЕ депрекейтит страницу — вакуумная истина `all([])`
исключена явно), а `plan` помечает страницу `degraded_sources: ["page_provenance:<slug>"]`.

### C3. `docs.path` — resolution precedence и обнаружение переноса

Порядок разрешения: `--docs-path` (CLI) > `pipeline.yaml: docs.path` (проектный override) >
дефолт `docs/`. Резолвленный путь обязан быть repo-relative, не содержать `..`, и после `realpath`
оставаться внутри корня репозитория (без выхода через symlink) — нарушение: exit 2
`error=invalid_docs_path`.

**Обнаружение переноса не зависит от git-index** (закрывает F-006). Перед bootstrap-прогоном (в
резолвленном `docs.path` нет `.mb-docs-state.json`) резолвер выполняет **детерминированный
filesystem-scan** корня репозитория по имени `.mb-docs-state.json`, C-сортированный по
repo-relative пути:

- исключаются: `.git/**`, сам резолвленный `docs.path`, и любой путь, чей `realpath` выходит за
  корень репо (symlink наружу не следуется);
- scan видит **tracked, untracked и ignored** файлы одинаково — прежняя формулировка «среди
  git-tracked файлов» молча пропускала валидный untracked-стейт (после bootstrap до первого commit
  либо при ignored/generated вики) и давала второй bootstrap вместо требуемого предупреждения;
- ровно один кандидат → exit 2 `error=path_mismatch old_path=<p> new_path=<resolved>` — стейт не
  переехал сам (S6-A-01 требует явного предупреждения, а не тихого второго bootstrap);
- больше одного → exit 2 `error=ambiguous_state candidates=<sorted-csv>`;
- ни одного → обычный bootstrap (REQ-005).

Scan исполняется **только на bootstrap-ветке** (стейта по резолвленному пути нет) — на обычном
инкременте его нет, поэтому стоимость обхода платится один раз за жизнь вики.

Автоматический перенос стейта не реализуется в этом слайсе — пользователь переносит файл вручную
или указывает старый `--docs-path`.

### C4. Формат вики (Karpathy layers)

- `index.md`: `- [Title](pages/slug.md) — one-line` по категориям (категория = префикс slug до
  первого `-`); регенерируется целиком из `pages/` каждым прогоном (`apply`, шаг 6). **`Title`
  читается из H1 страницы, `one-line` — из управляемого summary-блока страницы** (см. layout ниже) —
  источник `one-line` детерминирован, а не «первая попавшаяся строка» (закрывает F-008: index не имел
  определённого источника однострочника).
- `log.md`: append-only, грамматика строки **зафиксирована точно** (её же проверяет lint
  `invalid_log_entry` и по ней же ключуется идемпотентность):

  ```
  ## [YYYY-MM-DD] <op> | run=<run_id> <description>
  ```

  `op ∈ {ingest, bootstrap}`; `run_id` — C5 (`<base>..<target>`, `base ∈ {40-hex, bootstrap}`,
  `target` — 40-hex). `description` — свободный текст от синтезатора. Файл создаётся с заголовком
  при первом append. **Префикс `run=<run_id>` пишет код, а не LLM** — иначе модель могла бы сломать
  ключ идемпотентности.
- `pages/<slug>.md` — **точный layout** (writer рендерит его целиком, регенерация index читает из
  него, закрывает F-008):

  ```
  # <title>

  <!-- mb-docs:summary -->
  <summary>
  <!-- /mb-docs:summary -->

  [<!-- mb-docs:status -->…<!-- /mb-docs:status --> — опциональный deprecation-штамп C5.3]
  [<!-- mb-docs:contradictions -->…<!-- /mb-docs:contradictions --> — опц. рендер противоречий C5.5]

  <body_markdown>
  ```

  `title` → H1; `summary` — управляемый summary-блок (непустая строка 1–200 символов без CR/LF, C6);
  `body_markdown` — тело ниже (факты с wikilinks `[[slug]]`). `regenerate_index()` берёт `Title` из
  H1 и `one-line` из summary-блока. Управляемые блоки status/contradictions — replace-or-insert,
  идемпотентны. **`## Contradictions` больше НЕ приходит внутри `body_markdown`** — его рендерит код
  из структурной записи (C5.5, REQ-004), а не модель прозой.
- Источники (`graph.json`, `<bank>/codebase/wiki/`, код проекта) остаются read-only — ни один
  writer этого слайса не открывает их на запись (REQ-003/009); это проверяется не только ревью, но
  и манифестом (C8).

### C5. Шов прогона: `plan` (read-only) → диспатч (LLM) → `apply` (единственный writer)

Закрывает R2-002: вся детерминированная логика прогона живёт в вызываемом `docs_run.py`, а не в
прозе промпта, поэтому порядок записи, lock, crash-replay, `dirty_worktree` и `platform_limited`
проверяются на **production-коде**. Промпт делает ровно один недетерминированный шаг — диспатч.

`run_id = "<base_sha>..<target_sha>"`, где `base_sha = state.sha` или литерал `bootstrap`;
фиксируется в `plan` и переносится в `apply` внутри файла результатов.

#### C5.1. `python3 scripts/mb-docs.py plan [--json]` — read-only, ничего не пишет

Порядок (первый провал завершает; ни один шаг не пишет в вики — `plan` физически read-only):

1. Резолвит `docs.path` (C3) — включая scan переноса на bootstrap-ветке.
2. Грязный tracked worktree (незакоммиченные изменения tracked-файлов) — exit 2 `error=dirty_worktree`.
3. `target_sha = HEAD` (один раз); `base_sha = state.sha` или `bootstrap`.
4. Пустой дифф — печатает `{"result":"noop","run_id":"<id>"}`, exit 0 (Edge case из context.md).
5. **Резолв транспорта до всего остального дорогого** — C7; провал → exit 6, ноль записей.
6. Строит паки (C10) и `deprecate`-список: слаг попадает туда, когда `state.pages[slug].source_files`
   **непуст** И **каждый** его файл присутствует в `deleted_files` диффа (REQ-012). Частичное
   удаление источников — обычное обновление страницы, не deprecation. **Пустой `source_files`
   (легаси-стейт без provenance) НЕ депрекейтит страницу** (вакуумная истина `all([]) == true`
   исключена явно, R3-008): слаг не попадает в `deprecate`, а `plan` добавляет
   `page_provenance:<slug>` в `degraded_sources`.
7. Печатает **ровно один JSON-объект**:

```json
{"run_id": "string", "base_sha": "string", "target_sha": "string", "mode": "bootstrap|delta",
 "docs_path": "string",
 "dispatch": {"author": {"transport": "string", "model": "string", "thinking": "string",
                        "substituted": true, "packs": ["<pack_id>"]},
              "synthesizer": {"transport": "string", "model": "string", "thinking": "string",
                              "substituted": false}},
 "deprecate": [{"slug": "string", "deleted_files": ["string"]}],
 "degraded_sources": ["graph", "wiki", "page_provenance:<slug>"]}
```

`deprecate` и `degraded_sources` — **авторитетные поля плана** (R3-002): `apply` берёт их отсюда, а
не из результатов агентов, и переносит `degraded_sources` в финальный `applied`-вывод (REQ-010).
`degraded_sources` несёт `graph`/`wiki` (отсутствие источников, C7) и `page_provenance:<slug>`
(легаси-страница с пустым `source_files`, R3-008).

`/mb docs --dry-run` = остановка после `plan` с показом этого объекта (ничего не записано by
construction, а не по дисциплине промпта).

#### C5.2. `bash scripts/mb-docs-apply.sh --plan PATH --results PATH` — единственный writer

**Почему write-путь — bash-обёртка вокруг Python-писателя, а не Python напрямую** (существенно,
закрывает F-005). Токен лока S4-C6 — `$$-RANDOM` **вызывающей оболочки** (`mb-agree.sh:120`,
наследуется helper'ом), а reclaim ключуется на `kill -0` этого PID. Если бы `docs_run.py` вызывал
`mb_lock_acquire` через `bash -c` из Python, владельцем стал бы эфемерный bash, умирающий сразу
после захвата → любой контендер увидел бы мёртвого владельца и мгновенно реклеймил бы **живой**
лок, то есть взаимное исключение сломалось бы полностью. Поэтому владельцем обязан быть процесс,
живущий всю критическую секцию: обёртка держит лок и запускает писателя **своим ребёнком**. Это тот
же приём, что у S3 (лок берёт bash `mb-work-claims.sh`, Python-планировщик C7 вызывает его как CLI).
Пятая реализация лока в репо не пишется (DRY, umbrella Interface 2 § «Мягкая зависимость S3→S4»).

Обёртка:

1. `token=$(mb_lock_acquire "<docs-path>/.mb-docs.lock" 5 30)` из `scripts/_lib.sh` (владелец —
   S4-C6 ревизии 4; протокол — umbrella Interface 2: захват — атомарный `mkdir "<lock>"`, победитель
   создаёт РОВНО один маркер владельца — подкаталог `<lock>/owner.<token>`, `token = <PID>-<RANDOM>`
   печатается в stdout; reclaim ключуется на liveness (`kill -0` по PID), при мёртвом владельце `D` —
   `rmdir "<lock>/owner.<D>"` именно мёртвого токена, затем `rmdir "<lock>"` только на пустом каталоге
   (НЕ `mv`, НЕ `rm -rf`); TTL — только для owner-less окна; PID-reuse → консервативный НЕ-reclaim).
   Таймаут захвата (helper exit 1) → exit 7 `error=locked`.
   **Никаких «лок освобождается смертью процесса»**: `mkdir`-каталог переживает SIGKILL, поэтому
   восстановление идёт исключительно через liveness-reclaim S4-C6 — формулировка ревизии 2 была
   фактически неверной. `trap 'mb_lock_release "$lock" "$token"' EXIT INT TERM`.
2. `python3 -m memory_bank_skill.docs_run apply --plan <plan-path> --results <results-path> …` — шаги
   3–10 ниже; exit-код ребёнка пробрасывается наружу.

Шаги `docs_run.py apply` (порядок фиксирован и определяет crash-recovery):

3. **Валидирует `--plan` сам-на-согласованность** (R3-002): `run_id == "<base_sha>..<target_sha>"`,
   `target_sha` — 40-hex достижимый commit; нарушение → exit 5 `error=invalid_plan`. Все авторитетные
   поля (`run_id`, `base_sha`, `target_sha`, `docs_path`, `deprecate`, `degraded_sources`) далее
   берутся ТОЛЬКО из плана.
4. Перечитывает стейт под локом. Вычисляет `expected_base = state.sha`, если он не null, иначе литерал
   `bootstrap` (та же нормализация, что в `plan`, шаг 3 — иначе первый bootstrap-прогон, где
   `state.sha=null` и `plan.base_sha=bootstrap`, ложно упал бы в `stale_run`, R3-001).
   `plan.base_sha != expected_base` → exit 5 `error=stale_run expected_base=<expected_base>
   actual_base=<plan.base_sha>` (чужой прогон продвинул SHA — план устарел, нужен новый `plan`).
   Повторно проверяет `dirty_worktree`.
5. Валидирует `--results` по схеме C6 (только `pages`/`contradictions`/`log_entry`; посторонний ключ,
   пустой `source_files`, multiline `description`, невалидный evidence-путь противоречия) → провал:
   exit 5 `error=invalid_agent_result` (страница не пишется частично). run/base/target в результатах
   **отсутствуют по схеме**, поэтому подменить SHA через LLM нельзя.
6. **pages** — каждая страница атомарно (temp+rename): H1/summary/тело (C4), deprecation-штамп из
   `plan.deprecate` (C5.3), рендер противоречий из `results.contradictions` (C5.5).
7. **log** — `docs_store.log_append`, идемпотентный по `run_id` (C5.4); префикс `run=<run_id>` из плана.
8. **index** — полная регенерация из `pages/`.
9. **state-temp + lint** (порядок закрывает F-010): `apply` пишет стейт во **временный** файл
   `<docs-path>/.mb-docs-state.json.tmp` (control-write, ещё НЕ финальный стейт), затем запускает
   `docs_lint.py` с манифестом прогона (C8), где `pending_state_path` = финальный путь стейта.
   Обязательный шаг верификации, не опция. Красный lint → exit 5, финальный стейт **не** появляется,
   следующий прогон переигрывает тот же диапазон.
10. **финализация стейта** — после зелёного lint ровно один `os.replace(state_temp, pending_state_path)`
    и release lock. Печатает `{"run_id":"…","sha":"<plan.target_sha>","pages":<n>,
    "degraded_sources":[…],"result":"applied"}` — `sha` и `degraded_sources` из плана (REQ-010).

Прогон в целом **не является одной FS-транзакцией** — каждый файл атомарен по отдельности;
восстановимость даёт порядок + lock + идемпотентность, а не транзакция.

**Лок держится только на критической секции `apply`, а не через LLM-диспатч** — и это осознанно.
Держать его между `plan` и `apply` нельзя: между ними нет живого процесса-владельца (на claude-code
диспатч исполняет промпт-слой), а лок с мёртвым владельцем немедленно реклеймится. Безопасность
даёт не длинный лок, а два свойства: (а) конкурентные `apply` сериализуются локом; (б) второй,
устаревший `apply` детектируется по `stale_run` (шаг 3) и не пишет ничего. Конкурентные `plan`
безвредны — они read-only.

#### C5.3. Deprecation-штамп (REQ-012) — детерминированный, не LLM

Для каждого слага из `plan.deprecate` `apply` вставляет **replace-or-insert** управляемый блок
сразу после H1 страницы (идемпотентно — повтор заменяет тот же блок, не стопкой):

```
<!-- mb-docs:status -->
Status: deprecated
Deleted sources (as of <target_sha>): <path>, <path>
<!-- /mb-docs:status -->
```

Страница **не удаляется** и прежнее тело сохраняется (история знаний — решение из context.md
§ Edge cases). Штамп пишет код: удаление файла — факт диффа, а не суждение модели.

#### C5.5. Рендер противоречий (REQ-004) — детерминированный код, не проза LLM (закрывает R3-004)

Обнаружение противоречия (какой факт устарел) — работа синтезатора (LLM); но **рендер и валидация**
структурной записи — код, поэтому REQ-004 наблюдаем на production-CLI (D-05/D-06: gated SHALL требует
кодового red→green, а не reviewer-only). Синтезатор возвращает массив `contradictions` (C6):

```json
{"slug": "string", "old_claim": "string", "new_claim": "string",
 "old_evidence": "<repo-relative path>", "new_evidence": "<repo-relative path>"}
```

`apply` для каждой записи: **валидирует** `slug` (существующая/создаваемая страница) и оба
`*_evidence` (repo-relative, существующий путь в дереве репо; отсутствующий/абсолютный/`..`-путь →
`invalid_agent_result`, exit 5, ноль записей), затем **детерминированно** вставляет replace-or-insert
управляемый блок сразу после summary страницы `<slug>`:

```
<!-- mb-docs:contradictions -->
## Contradictions
- superseded: <old_claim> (<old_evidence>)
- current: <new_claim> (<new_evidence>)
<!-- /mb-docs:contradictions -->
```

Идемпотентно (повтор заменяет тот же блок). Молчаливой перезаписи прежнего факта нет — старое
утверждение остаётся видимым как `superseded`. **Семантическое качество обнаружения** (что именно
модель сочла противоречием) — non-gated ответственность промпта синтезатора, подтверждается
ревьюером и spec-review (S2-C5), а не pytest'ом (§ «Что здесь НЕ проверяется кодом»).

#### C5.4. Идемпотентность повтора после краха (закрывает F-005)

`log.md` — append-only (C4), поэтому наивная переигровка после краха между шагами 7 и 10 создала бы
**вторую** запись того же прогона. Ключ идемпотентности — `run_id`:

- `log_append` под локом читает `log.md` и, найдя строку с `run=<run_id>`, возвращает
  `{"appended":false}` и не пишет ничего;
- `run_id` детерминирован (`<base>..<target>`), поэтому повтор до финализации стейта даёт тот же ключ;
- страницы и `index.md` идемпотентны по построению (полная перезапись тем же/обновлённым
  содержимым); стейт финализируется один раз последним шагом (`os.replace` из temp).

Итог: любой сбой до шага 10 оставляет `state.sha` прежним, следующий прогон переигрывает тот же (или
расширенный, если HEAD ушёл вперёд) диапазон — апдейт не теряется, дубликата в журнале не возникает.
Если HEAD ушёл вперёд, `run_id` другой и новая запись в журнале **правомерна** (это другой диапазон).

### C6. Суб-агентные output-контракты (writer-ready, закрывает F-008)

**Имена полей общие с writer API байт-в-байт** — объект страницы у автора и элемент `pages[]` у
синтезатора идентичны по схеме, и ровно этот объект потребляет `apply`.

`agents/mb-docs-author.md` (Haiku, одна страница из пака за вызов) возвращает **ровно** один JSON
без другого текста:

```json
{"page": {"slug": "string", "title": "string", "summary": "string", "body_markdown": "string",
          "source_files": ["string"], "wikilinks": ["string"]}}
```

`agents/mb-docs-synthesizer.md` (Sonnet, кросс-страничный проход) возвращает **ровно** один JSON —
это и есть файл результатов для `apply` (несёт **только** содержимое агентов; идентификаторы прогона
приходят из плана, R3-002):

```json
{"pages": [{"slug": "string", "title": "string", "summary": "string", "body_markdown": "string",
            "source_files": ["string"], "wikilinks": ["string"]}],
 "contradictions": [{"slug": "string", "old_claim": "string", "new_claim": "string",
                     "old_evidence": "string", "new_evidence": "string"}],
 "log_entry": {"op": "ingest|bootstrap", "description": "string"}}
```

- **`run_id`/`base_sha`/`target_sha` ревизии 3 удалены из схемы результатов** (закрывает R3-002):
  их авторитетный источник — план, `apply` берёт SHA только оттуда; посторонний ключ в результатах →
  `invalid_agent_result`. Так модель не может продвинуть стейт на подменённый SHA.
- `summary` — непустая строка **1–200 символов без CR/LF** (источник `one-line` для `index.md`, C4);
  нарушение → `invalid_agent_result` (exit 5).
- `source_files` — **непустой уникальный** массив repo-relative путей у любой non-deprecated страницы
  (закрывает R3-008: пустой массив вакуумно депрекейтил бы страницу); пустой → `invalid_agent_result`.
- `contradictions` — структурные записи (C5.5, REQ-004); `apply` валидирует evidence-пути и рендерит
  их детерминированным кодом. `## Contradictions` **не** приходит внутри `body_markdown`.
- `index_entries` ревизии 2 **удалено** — `index.md` регенерируется детерминированно из `pages/` (C4).
- `log_entry` — `op ∈ {ingest, bootstrap}` + `description`; **`description` — непустая single-line
  строка без CR/LF, без токена `run=`, без NUL и без префикса `## [`** (закрывает R3-007: свободный
  многострочный текст мог навсегда сломать replay журнала); нарушение → `invalid_agent_result`,
  exit 5, на **шаге валидации до любой записи** (C5.2, шаг 5). Префикс `run=<run_id>` добавляет `apply`.

**Явный шаг переноса результатов в конечную вики** (F-008: кто, куда, какой командой): оркестратор
`commands/mb.md § docs` записывает stdout `mb-docs.py plan` **как есть** в
`<bank>/tmp/docs-plan-<run_id>.json` и JSON синтезатора **как есть** в
`<bank>/tmp/docs-results-<run_id>.json` (банк пишет только оркестратор — D-23) и вызывает
`bash scripts/mb-docs-apply.sh --plan <bank>/tmp/docs-plan-<run_id>.json --results
<bank>/tmp/docs-results-<run_id>.json`. Других путей попадания текста агентов в вики нет.

Обоим агентам запрещены file-write инструменты (Write/Edit отсутствуют в их tool list) — writer
единственный (паттерн D-23). Malformed JSON от агента — `invalid_agent_result`, exit 5, ноль записей.

### C7. Честная деградация (REQ-010/011, паттерн AGR-013/NFR-003)

- **Отсутствующий/нечитаемый `graph.json` или `<bank>/codebase/wiki/`**: `docs_ingest.py` продолжает
  строить паки из git diff + исходных excerpt'ов, добавляет `"degraded_sources": ["graph"|"wiki"]`
  в JSON-вывод `packs` и в план (C5.1); ни один из источников не создаётся и не изменяется
  (REQ-009 остаётся в силе).
- **Транспорт диспатча — исполнимый контракт** (закрывает F-007). `plan`, шаг 5, до паков и до
  любого дорогого шага, вызывает **существующий** резолвер:

  ```
  bash scripts/mb-agent-caps.sh resolve --role docs_author     --mb <bank>
  bash scripts/mb-agent-caps.sh resolve --role docs_synthesizer --mb <bank>
  ```

  и принимает только stdout-блок `transport=` / `model=` / `thinking=` / `substituted=`
  (`scripts/mb-agent-caps.sh:16-20`). Реакция на exit — точная:

  | caps exit | Значение (`mb-agent-caps.sh:29-33`) | Реакция `/mb docs` |
  |---|---|---|
  | `0` | резолвлено | продолжаем; поля переносятся в `plan.dispatch.<role>` |
  | `1` | argument error — в т.ч. «роль без `model` в pipeline» (`:241-244`) | exit 6 `platform_limited` |
  | `2` | pipeline.yaml нечитаем/не парсится | exit 6 `platform_limited` |
  | `3` | нет транспорта+модели и `dispatch.on_none_available == error` (`:275-281`) | exit 6 `platform_limited` |

  Любой ненулевой код → завершение **до** любой записи (в `plan` это тривиально верно — он
  read-only), stderr:
  `result=platform_limited platform_limited=subagent-dispatch role=<role> caps_exit=<n>`
  плюс actionable-подсказка: `hint=add roles.<role>.model to <resolved pipeline path>`.
  Стейт не тронут, writers не вызываются.

- **`substituted=true` не является platform_limited** — и это осознанное расхождение с proposed_fix
  ревью (там предлагалось валить прогон при «модели другого tier»). Измерено:
  `mb-agent-caps.sh:275-277` возвращает `substituted=true` + **exit 0**, когда контрактный транспорт
  недоступен и `dispatch.on_none_available != error` (дефолт — `fallback`). То есть подстановка
  tier'а — **сконфигурированный пользователем легитимный исход**, а не отсутствие транспорта;
  валить его означало бы ломать `/mb docs` на всех хостах без Haiku вопреки явной настройке.
  Честный ответ: `substituted` переносится в `plan.dispatch.<role>.substituted` (виден в
  `--dry-run`), NFR-001 фиксирует, что экономия при подстановке теряется. Проекту, которому нужна
  строгость, **уже** доступен существующий рычаг `dispatch.on_none_available: error` → caps exit 3 →
  наш exit 6; изобретать второй классификатор tier'ов (и угадывать таксономию произвольных
  `model_map`-id вроде `opencode/claude-haiku-4`) слайс не будет.

- **Измеренное ограничение резолва** (`scripts/mb-agent-caps.sh:120-137`): `resolve_pipeline_path`
  — это **подстановка файла, а не слияние**: при наличии `<bank>/pipeline.yaml` дефолт
  `references/pipeline.default.yaml` игнорируется целиком. Следствие, которое обязан знать
  имплементер: регистрации ролей в дефолте **недостаточно** для проектов, у которых уже есть
  собственный `pipeline.yaml` (а он есть у всех после `/mb config init`) — там `resolve --role
  docs_author` даст exit 1 (проверено на этом репо) → честный exit 6 с подсказкой выше, а не тихий
  диспатч «чем попало». Поэтому T6 регистрирует роли и в дефолте (для новых проектов), и в
  `.memory-bank/pipeline.yaml` этого репо (dogfood).

### C8. Lint (REQ-008) — внутренний, обязательный шаг, не публичный флаг в v1

`docs_lint.py` — внутренняя субкоманда `lint` и обязательный шаг верификации каждого прогона
(`apply`, шаг 9), не опциональная проверка по запросу. Публичный флаг `/mb docs --lint` **не
добавляется** в этом слайсе (решение закрывает прежний Open Question — см. Decisions).

**Структурные проверки** — вычислимы из дерева вики, каждая со стабильным ключом `error=`:

| Код | Условие |
|---|---|
| `missing_index` | `index.md` отсутствует |
| `missing_log` | `log.md` отсутствует |
| `invalid_log_entry` | строка `log.md`, начинающаяся с `## [`, не матчит грамматику C4 (включая обязательный `run=<run_id>`) |
| `orphan_page` | файл в `pages/` не упомянут ни в одной строке `index.md` |
| `missing_index_entry` | строка `index.md` ссылается на несуществующий `pages/<slug>.md` |
| `invalid_index_entry` | строка `index.md` не матчит `- [Title](pages/slug.md) — one-line` |
| `broken_wikilink` | `[[slug]]` внутри `pages/*.md` не резолвится в существующую страницу |
| `missing_cross_reference` | в вики > 1 non-deprecated страницы, но НИ одной резолвящейся ссылки `[[other-slug]]` между разными страницами (REQ-003 требует, чтобы страницы cross-referenced друг друга — R3-005) |

**Положительная проверка cross-reference (`missing_cross_reference`, закрывает R3-005)**: прежние
Eval'ы проверяли только сохранение текста и отсутствие битой ссылки — вики вообще БЕЗ ссылок проходила
все проверки, хотя REQ-003 требует взаимных wikilinks. Теперь линтер даёт `error=missing_cross_reference`
(exit 1), если non-deprecated страниц больше одной, а ни одна `[[other-slug]]` не связывает две разные
страницы. Одна страница или полностью deprecated-вики — не нарушение.

**`source_leakage` — вычислим из явного входа линтера** (закрывает F-010). Ревизия 2 определяла его
как исторический факт «`docs_store.py` записал что-либо вне …», который из статического состояния
вики после записи вывести невозможно. Ревизия 3 делает этот вход явным:

```
python3 scripts/mb-docs.py lint --docs-path <p> [--manifest <path>]
```

Манифест — файл, который `apply` пишет во временный путь перед шагом lint и передаёт флагом
`--manifest` (в продакшене он передаётся **всегда**, поэтому проверка не факультативна). Ревизия 4
разводит durable-записи вики, control-записи и **ещё не финализированный** стейт (закрывает
внутреннее противоречие F-010: ревизия 3 объявляла `writes` «всё фактически записанное», но сам
манифест и лок писались вне этого множества, а стейт — только ПОСЛЕ lint, поэтому честно попасть в
`writes` он не мог):

```json
{"run_id": "string",
 "durable_writes_completed": ["<docs-path>/pages/<slug>.md", "<docs-path>/log.md", "<docs-path>/index.md"],
 "control_writes": ["<docs-path>/.mb-docs.lock/**", "<manifest-temp-path>", "<docs-path>/.mb-docs-state.json.tmp"],
 "pending_state_path": "<docs-path>/.mb-docs-state.json",
 "sources": {"<repo-relative path>": "<sha256 до прогона>", "..."}}
```

- `durable_writes_completed` — durable-страницы/лог/индекс, фактически записанные к шагу lint. Каждый
  обязан лежать под `docs_path` и матчить шаблоны `pages/**`, `log.md`, `index.md`; иначе
  `error=source_leakage path=<p> reason=write_outside_docs_path`.
- `control_writes` — служебные записи прогона: маркер лока `<docs-path>/.mb-docs.lock/**`, сам
  temp-манифест и temp-стейт `<docs-path>/.mb-docs-state.json.tmp`. Каждый обязан принадлежать **ровно
  этим** разрешённым шаблонам; любой иной control-write → `error=source_leakage path=<p>
  reason=write_outside_docs_path`. Так честные служебные записи не дают ложный leakage, но любая
  посторонняя даёт.
- `pending_state_path` — обязан равняться `<docs-path>/.mb-docs-state.json`; иначе
  `error=source_leakage path=<p> reason=bad_pending_state`. Финальный стейт ещё НЕ существует на момент
  lint — `apply` делает `os.replace(state_temp, pending_state_path)` только после зелёного lint (C5.2,
  шаг 10), поэтому в durable-множестве его нет и противоречия ревизии 3 не возникает.
- `sources` — `graph.json`, файлы `<bank>/codebase/wiki/**` и изменяемые исходники, захешированные
  **до** прогона. Линтер перехеширует и сверяет: расхождение → `error=source_leakage path=<p>
  reason=source_mutated`. Это даёт REQ-003/REQ-009 (immutable sources) детерминированную проверку
  в **продакшене**, а не только в тесте.
- `--manifest` отсутствует → структурные проверки исполняются, manifest-проверки пропускаются;
  на stdout печатается ровно одна строка `note=manifest_absent source_leakage=unchecked`, чтобы
  пропуск был громким, а не молчаливым. Это режим статических фикстур; `apply` всегда передаёт
  манифест.

Валидная фикстура → exit 0, без вывода (кроме `note=` при отсутствии манифеста). Каждое нарушение —
отдельная строка `error=<code> path=<...>` на stdout; exit 1 при ≥1 нарушении; malformed CLI/схема
(нечитаемый манифест, нечитаемый JSON-стейт, **явно переданный** невалидный `--docs-path`) — exit 2.
Отсутствие флага `--docs-path` **не** является malformed CLI — работает C3 precedence/default
(устранено противоречие ревизии 2: C8 объявлял отсутствие флага ошибкой, а C3 — легитимным
дефолтом).

### C9. `docs.path` и роли в `references/pipeline.default.yaml`

```yaml
docs:
  path: docs/

roles:
  docs_author:      { agent: mb-docs-author,      model: haiku }
  docs_synthesizer: { agent: mb-docs-synthesizer, model: sonnet }
```

Ключ `model` обязателен у обеих ролей: без него `mb-agent-caps.sh` отклоняет роль (exit 1,
`:241-244`), то есть C7 никогда не резолвил бы транспорт. Значения — bare tier-имена, как у
существующих ролей проектного `pipeline.yaml` (`model: sonnet`).

`mb-pipeline-validate.sh` расширяется: `docs` — опциональный top-level ключ; если присутствует,
обязан быть маппингом с ровно одним обязательным строковым ключом `path` (репо-relative, не
абсолютный, без `..`); отсутствие `docs:` не является ошибкой (легаси-совместимость); посторонние
ключи внутри `docs:` или `path` неправильного типа — структурная ошибка (закрывает F-009/F-012:
произвольное значение `docs:` больше не проходит валидатор молча).

### C10. `packs` JSONL — схема и лимиты

Один объект на строку:

```json
{"pack_id": "string", "mode": "bootstrap|delta", "community": "string|null",
 "files": ["string"], "symbols": ["string"], "wiki_refs": ["string"],
 "excerpts": [{"file": "string", "lines": "string", "text": "string"}],
 "deleted_files": ["string"],
 "degraded_sources": ["graph", "wiki"]}
```

`deleted_files` — repo-relative пути, удалённые в диапазоне `base..target` (`git diff --diff-filter=D`);
вход для `deprecate`-логики C5.1 (REQ-012).

Лимиты на пак (детерминированное усечение, не LLM-решение): ≤ 12 файлов, ≤ 40 строк excerpt
суммарно, ≤ 10 символов, ≤ 5 decision/wiki-ссылок. `mode=bootstrap` — когда `--since none` или
стейта нет (REQ-005). Недостижимый `--since <sha>` — ничего не печатается, stderr `error=
unreachable_sha suggestion=merge-base|bootstrap`, exit 4 (fallback вместо тихого полного
переобхода — Edge case из context.md).

## Decisions

S6-A-01…05 + D-27/28 — в context. Ревизия 2 закрыла: батчирование по graph-коммьюнити,
`docs.path` precedence, публичность lint (внутренний обязательный шаг), dogfood-override
`project-wiki/` (AGR-010, `docs/` занят MkDocs), разбиение T1, межслайсовую зависимость
`svp-sdd-core#7`. Ревизия 3 добавляет:

- **Шов прогона вместо прозы промпта** — `docs_run.py` `plan`/`apply` (C5): детерминизм прогона
  стал тестируемым на production-CLI; промпт отвечает только за диспатч (R2-002/R2-003).
- **Единственный writer** — `apply` (C1/C2): отдельные `write-page`/`log-append`/`index`/`set-sha`
  сняты как источник противоречия F-004; стейт пишется целиком и последним.
- **Lock — потребляемый, не изобретаемый** — `mb_lock_acquire`/`mb_lock_release` S4-C6 (umbrella
  Interface 2), владелец — живая bash-обёртка (C5.2); утверждение ревизии 2 «крах процесса
  освобождает лок» признано фактически неверным и удалено; авто-слом лока по возрасту >1ч удалён,
  т.к. он допускал второго writer'а поверх живого долгого прогона.
- **Идемпотентность повтора** — `run=<run_id>` в журнальной строке (C4/C5.4).
- **Транспорт** — исполнимый контракт поверх существующего `mb-agent-caps.sh` (C7), с измеренным
  ограничением file-substitution резолва пайплайна и осознанным отказом валить `substituted=true`.
- **`source_leakage`** — переведён из ненаблюдаемой истории в проверку манифеста (C8).
- **REQ-012 (deprecated-страницы)** — решение context.md § Edge cases вернулось в триплет:
  REQ-012 + `deleted_files` (C10) + `deprecate` (C5.1) + штамп (C5.3) + Scenario 10.

Ревизия 4 (2026-07-18, spec-review круг 3) добавляет:

- **Bootstrap больше не `stale_run`** (R3-001): `apply` вычисляет `expected_base` той же нормализацией,
  что `plan` (`state.sha` или литерал `bootstrap`), C5.2 шаг 4.
- **`apply` привязан к авторитетному плану** (R3-002): `mb-docs-apply.sh --plan --results`; `run_id`,
  `base_sha`, `target_sha`, `docs_path`, `deprecate`, `degraded_sources` — только из плана; схема
  результатов синтезатора (C6) их не содержит, поэтому LLM не может подменить SHA; `degraded_sources`
  доезжает до `applied`-вывода (REQ-010).
- **Page-schema = writer API** (F-008): `summary` добавлен, index one-line берётся из summary-блока,
  `write_page(page)` рендерит H1/summary/тело (C4).
- **Manifest lifecycle разведён** (F-010): `durable_writes_completed`/`control_writes`/
  `pending_state_path`/`sources`; стейт финализируется `os.replace` из temp только после зелёного lint.
- **REQ-004 — код, не reviewer-only** (R3-004): структурная запись `contradictions[]` + детерминированный
  рендер `## Contradictions` (C5.5); семантика обнаружения — non-gated промпт.
- **Положительный cross-reference-lint** (R3-005): код `missing_cross_reference` (C8).
- **`log_entry.description` валидируется до записи** (R3-007): single-line без CR/LF/`## [`/`run=` (C6).
- **Пустой `source_files` не депрекейтит** (R3-008): непустой у нового page (C6), легаси-пустой →
  `page_provenance:<slug>` в `degraded_sources` (C5.1).
- **Lock S4-C6 выровнен на ревизию 4 владельца** — owner-marker `<lock>/owner.<token>` + targeted
  `rmdir` мёртвого токена (НЕ `mv`), TTL только для owner-less окна (C5.2).
- **Жёсткая зависимость от lock-helper S4** (R3-003/CPR-B): `blocked_by` += `svp-roadmap-backlog-db`,
  T4 `Blocked-by` += `svp-roadmap-backlog-db#2`, fallback-фраза «реализовать helper, если не отгружен»
  удалена (нарушение Scope).

## Eval declarations (red → green в work-фазе)

Якоря — по umbrella Interface 1 / S2-C1 (S2-X-05): `output~:` обязателен на каждой задаче (все REQ
слайса — gated SHALL). Измерено на этом дереве 2026-07-17: `bats <отсутствующий файл>` → exit 1 +
`not ok 1 bats-gather-tests`, `pytest <отсутствующий файл>` → exit 4 + `no tests ran` — оба обязаны
**не** матчиться якорем, иначе «файла нет» сойдёт за red. Поэтому pytest-якоря опираются на
`ModuleNotFoundError` целевого модуля или строку `FAILED <файл>::`, а bats-якоря — на **именованный**
префикс теста (`not ok N docs …`), которого нет у `bats-gather-tests`.

- **T1** — red-условие: `docs_state.py` нет (тесты первыми):
  **Eval:** `pytest tests/pytest/test_mb_docs_state.py` — red: `memory_bank_skill/docs_state.py` нет, тесты первыми; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_state'|FAILED tests/pytest/test_mb_docs_state\.py::)`
- **T2** — red-условие: `docs_ingest.py` нет:
  **Eval:** `pytest tests/pytest/test_mb_docs_ingest.py` — red: `memory_bank_skill/docs_ingest.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_ingest'|FAILED tests/pytest/test_mb_docs_ingest\.py::)`
- **T3** — red-условие: `docs_store.py` нет:
  **Eval:** `pytest tests/pytest/test_mb_docs_store.py` — red: `memory_bank_skill/docs_store.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_store'|FAILED tests/pytest/test_mb_docs_store\.py::)`
- **T4** — red-условие: `docs_run.py` / обёртки нет:
  **Eval:** `pytest tests/pytest/test_mb_docs_run.py` — red: `memory_bank_skill/docs_run.py` нет; exit: 2; output~: `(ModuleNotFoundError: No module named 'memory_bank_skill\.docs_run'|FAILED tests/pytest/test_mb_docs_run\.py::)`
- **T5** — red-условие: агентов нет:
  **Eval:** `pytest tests/pytest/test_mb_docs_agents.py` — red: `agents/mb-docs-author.md` и `agents/mb-docs-synthesizer.md` нет; exit: 1; output~: `FAILED tests/pytest/test_mb_docs_agents\.py::`
- **T6** — red-условие: `docs.path`/роли/валидатор не расширены:
  **Eval:** `bats tests/bats/test_mb_docs_pipeline.bats` — red: `docs.path`/роли/валидатор не расширены; exit: 1; output~: `not ok [0-9]+ docs\.path: `
- **T7** — red-условие: `docs_lint.py` нет:
  **Eval:** `bats tests/bats/test_mb_docs_lint.bats` — red: `memory_bank_skill/docs_lint.py` нет; exit: 1; output~: `not ok [0-9]+ docs lint: `

Строки `**Eval:**` выше — байт-в-байт те же, что в `tasks.md` (CPR-D): исполняемое поле остаётся
единственным источником, а декларация здесь обязана совпадать с ним посимвольно, иначе валидатор
спеки падает.

## Risks & mitigation

| Risk | P | I | Mitigation |
|---|---|---|---|
| Догфуд-конфликт с MkDocs в `docs/` этого репо | H | M | `docs.path: project-wiki/` вне `mkdocs docs_dir` (C3, Decisions); Scenario 5 — детерминированные артефакты + byte-identical `docs/**`; T6 первым проверяет override |
| Дорогой полный bootstrap на большом репо | M | M | батчи по graph-коммьюнити (C10); Haiku-тир; `--dry-run` показывает план до диспатча |
| Дрейф вики от кода между запусками | M | L | contradiction-флаги (REQ-004, C6) + обязательный lint-шаг (C8) на каждом прогоне |
| Частичный сбой прогона продвигает SHA раньше времени | M | H | фиксированный порядок записи + запись стейта только после зелёного lint (C5.2) — устранено контрактом |
| Повтор после краха дублирует append-only журнал | M | M | `run=<run_id>` ключ + `{"appended":false}` (C5.4); тест краха после log в T4 |
| Параллельный `/mb docs` портит вики (гонка записи) | L | H | lock S4-C6 (owner-marker + targeted `rmdir`, liveness-reclaim) на критической секции + `stale_run`-гард (C5.2) |
| Роли не зарегистрированы в проектном `pipeline.yaml` → диспатч «чем попало» | M | M | file-substitution резолва измерен (C7); отсутствие роли даёт caps exit 1 → наш exit 6 с actionable-подсказкой, а не тихий фолбэк |
| S6 стартует до отгрузки lock-helper S4 (`_lib.sh`) | M | H | жёсткое ребро `blocked_by: [svp-sdd-core, svp-roadmap-backlog-db]` + T4 `Blocked-by … svp-roadmap-backlog-db#2`; fallback-реализация helper'а удалена (R3-003/CPR-B) |
| S6 и `svp-sdd-core` (S2) пишут одни файлы (`pipeline.default.yaml`, `mb-pipeline-validate.sh`) | M | H | T6 несёт `Blocked-by: 1, svp-sdd-core#7`; frontmatter спеки `blocked_by: [svp-sdd-core, svp-roadmap-backlog-db]` (F-003/R3-003) |

## Cross-slice requests (правки в чужих спеках — здесь не делаются)

| # | Адресат | Запрос | Основание |
|---|---|---|---|
| X6-01 | `svp-roadmap-backlog-db` (S4) | Информационно, правка текста C6 не обязательна: зафиксировать в C6, что владелец лока — **вызывающая оболочка** (`token="$$-RANDOM"`), поэтому не-shell потребитель (Python/Node) обязан оборачивать критическую секцию в живой shell-процесс, а не звать helper через `bash -c` (иначе владелец умирает сразу после захвата и лок мгновенно реклеймится живым). S6 решает это bash-обёрткой `mb-docs-apply.sh` (C5.2) и от S4 изменений НЕ требует | измерено `mb-agree.sh:120` + S4-C6 |
| X6-02 | `svp-sdd-core` (S2) | Информационно: X-05 исполнен — все 7 Eval'ов S6 несут `output~:`-якоря; для bats потребовалась конвенция именования тестов (`docs …`), т.к. ERE не поддерживает negative lookahead и «не `bats-gather-tests`» иначе невыразимо | S2-X-05 |

## Open questions

Нет открытых вопросов. Ревизия 2 закрыла: публичность lint (C8), `docs.path` precedence/миграция
(C3), атомарность (C5), разбиение T1, межслайсовую зависимость. Ревизия 3 закрыла: точку записи
стейта (C1/C2), владельца лока (C5.2), идемпотентность повтора (C5.4), наблюдаемость
`source_leakage` (C8), контракт транспорта (C7), судьбу удалённых сущностей (REQ-012).
