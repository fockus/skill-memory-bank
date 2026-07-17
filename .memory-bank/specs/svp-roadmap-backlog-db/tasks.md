# Tasks: svp-roadmap-backlog-db

> Слайс S4 (ICE 432). Eval первым (red) → реализация (green).
> Ревизия 3 (2026-07-17, spec-review круг 2): добавлена Task 9 (глобальный аллокатор I-NNN + приведение
> `mb-idea-promote.sh` к машине, F-012/R2-002); typed SPEC-writer добавлен в Task 8 (R2-004);
> Task 1 разделяет legacy/priority режимы (F-003); Task 4 — 10 кодов (F-008); portability-гейт
> добавлен в Task 7 (F-013). Роли — bare (парсер добавляет `mb-` сам).
> Бюджеты: Stage 1 = 210k, Stage 2 = 370k, Stage 3 = 210k, Stage 4 = 60k (каждый ≤ 400k);
> итого 850k < 900k. ID задач не перенумерованы.
> Порядок по Blocked-by: {1, 2} (Stage 1) → {6, 7, 9} → 3 (Stage 2) → {8, 4} (Stage 3) → 5 (Stage 4).
> Сериализация по Scope: `_lib.sh` — 2 → 9; `mb-backlog-state.sh` — 2 → 7 → 8; `mb-idea.sh` — 9 → 8.
> Test-seam (R3-004): Task 3 несёт migrate-vs-idea race-тест, требующий `mb-idea.sh` уже на общем
> локе (upgrade — Task 9), поэтому `Blocked-by: 2, 9`; сумма бюджета Stage 2 неизменна ({3,6,7,9}).
> Ревизия 4 (2026-07-17): каждый `Eval:` несёт `output~:`-якорь настоящего провала (групповая норма
> X-05, S2-C1 + S2 REQ-054/055) — положительный именованный префикс bats-теста, зафиксированный в
> Testing каждой задачи; red-условия переформулированы с «файла нет» на состояние ПОСЛЕ материализации
> теста (S2-C1: «файла теста нет» — не red-условие ни при каких обстоятельствах, D-05).
> Ревизия 5 (2026-07-18, spec-review круг 3): Task 2 — owner-marker/`rmdir` lock (R3-001), transition-
> примитив `mb_backlog_transition_locked` (R3-002), `list` flat без заглушки + `--tree`→exit 2 (R3-005),
> anti-cycle annotate-тест (R3-009); Task 3 `Blocked-by: 2, 9` + precondition (R3-004); Task 4 15 кодов
> (R3-003); Task 6 covers REQ-013 (unconfirmed_ice + позиция групп, AGR-021/R3-007); Task 9 promote
> partial-failure + concurrent same-title (R3-008/R3-001). ID задач не перенумерованы.

<!-- mb-task:1 -->
## Task 1: roadmap-sync — legacy/priority режимы порядка и ICE-компоненты

**Stage:** 1
**Covers:** REQ-001
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb-roadmap-sync.sh, tests/bats/test_mb_roadmap_sync_ice.bats, tests/fixtures/**
**Budget:** 100000

**What to do:**
- Контрактный снимок ДО правок: текущий вывод `mb-roadmap-sync.sh` (внутри и вне fences) на всём сегодняшнем `plans/*.md` — зафиксировать как regression-фикстуру.
- Реализовать ДВА режима на секцию (design.md C2), не один алгоритм: **legacy mode** — если ни у одного элемента секции нет валидного `ice` и нет `pin`, вызывается существующая `dependency_order(items)` (`mb-roadmap-sync.sh:175-212`) БЕЗ изменений, её порядок и её предупреждения возвращаются как есть; **priority mode** — включается только при наличии валидного `ice`/`pin` хотя бы у одного элемента.
- Priority mode: раундовый Kahn; frontier → `prioritized` (валидный `ice` или `pin`) + `legacy_tail` (исходный относительный порядок); компаратор `pin`↑ → `score`↓ → `created`↑ → `topic`↑ → `rel`↑ (тотальный, design.md C2 п.3); цикл → сегодняшняя грамматика warning с `<name>` = первый оставшийся элемент, остаток в исходном порядке.
- Парсер ICE-компонентов (design.md C1): `ice: {impact: N, confidence: N, ease: N}` flow-style одной строкой, ровно три ключа, каждый целый 1..10; `score = I×C×E` вычисляется при рендере и НИКОГДА не хранится; `ice_confirmed` читается, но на порядок не влияет; невалидный/plain-int/block-style `ice` → no-ice tail + stderr-warning грамматики существующего block-style предупреждения, без падения.
- Читать `ice`/`ice_confirmed`/`pin` из frontmatter планов (новые опциональные поля) — расширить `parse_frontmatter`/`plans.append` без изменения остальных полей.

**Eval:** `bats tests/bats/test_mb_roadmap_sync_ice.bats` — red: bats-файл материализован; legacy/priority-режимы и парсер ICE-компонентов не реализованы — кейсы порядка и ICE-грамматики падают; exit: 1; output~: `not ok [0-9]+ roadmap_sync_ice: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `roadmap_sync_ice: `. Причина: `bats` на отсутствующем файле даёт exit 1 + `not ok 1 bats-gather-tests` — тот же код, что и настоящий провал, поэтому exit-only якорь принял бы «файла нет» за red; ERE не поддерживает negative lookahead, и якорь опирается на положительный именованный префикс, которого у `bats-gather-tests` нет.
- bats legacy mode: фикстура A/B/C в файловом порядке, где `A.depends_on = [C]`, ни у кого нет `ice`/`pin` → Next = `C, A, B` (сегодняшний DFS), НЕ `B, C, A`; отдельный кейс — сегодняшний corpus целиком byte-identical; фикстура только с `invalid_ice` → тоже legacy mode (byte-identical).
- bats priority mode: ICE-порядок по вычисленному score; `pin` override; дублирующийся `pin` → сортировка не падает, порядок детерминирован остальными ключами (код `duplicate_pin` проверяется в T4); no-ice tail; равный score → `created`→`topic`→`rel`; цикл — warning той же грамматики.
- bats ICE-грамматика: валидные компоненты → score; отсутствие `ice` → tail; plain-int / block-style / 4 ключа / дубль ключа / `impact: 0` / `impact: 11` / нецелое → tail без падения.
- Вне fences byte-identical во всех кейсах.
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] Legacy mode вызывает немодифицированную `dependency_order()`; фикстура A→C даёт `C, A, B` byte-identical
- [ ] Priority mode (Kahn + тотальный компаратор) включается только при валидном `ice`/`pin`
- [ ] ICE-компоненты парсятся, score = I×C×E считается скриптом; невалидный ICE деградирует в tail без падения
- [ ] bats green (были red)
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Беклог-стейт-машина + общий lock-хелпер

**Stage:** 1
**Covers:** REQ-005, REQ-007
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb-backlog-state.sh, scripts/_lib.sh, tests/bats/test_mb_backlog_state.bats, tests/bats/test_mb_lock_helper.bats
**Budget:** 110000

**What to do:**
- Новый `scripts/mb-backlog-state.sh` по design.md C3: `transition <I-NNN> <NEW_STATE> [--reason TEXT] [--mb PATH]`, `annotate <I-NNN> --brief <TEXT> [--parent <I-NNN|none>] [--mb PATH]` (единственный writer `**Brief:**`/`**Parent:**`; brief валидируется той же функцией, что READY-гейт; stdout `item=<id> annotated`) и `list [--mb PATH]` (**flat-режим полностью**: `depth=0`, порядок по числовому I-ID, точная JSON title-грамматика C3). **Опция `--tree` в Task 2 НЕ объявляется** (полная иерархия — Task 7): до Task 7 неизвестная опция завершается `exit 2` без мутации — никаких заглушек placeholder-кода (RULES.md §no-placeholders). Машина `NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX`; success/domain-error/usage-error stdout/stderr/exit контракт.
- Общий **transition-примитив** `mb_backlog_transition_locked <backlog_path> <I-NNN> <NEW_STATE> [--reason TEXT] [--plan REL]` в `scripts/_lib.sh` (design.md C3, R3-002): **precondition — caller уже владеет `<bank>/.locks/backlog.lock`; функция сама лок не берёт и не отпускает**; валидирует ребро + гейты READY/WONTFIX, рендерит токен `<STATE>` + опц. Reason/Plan в один temp-файл, один `mv`; stdout пуст, exit 0/1/2; публичную success-строку печатает вызывающий скрипт. Переиспользуется Task 9 для `mb-idea-promote.sh` (с `--plan`); второй реализации машины в репо быть не должно.
- READY-гейт блокирующий (не warning): behavioral-эвристика + запрет путей файлов/номеров строк; отказ — точная причина, без частичной мутации.
- **Обязательное чтение перед реализацией (D-29)**: `mb-agree.sh:56-116` — четыре disproved-итерации stale-break со стресс-тестами `tests/bats/test_mb_agree.bats`. Отвергались они за (а) ключевание решения на mtime/TTL и (б) вторичный `.reclaiming`-мьютекс. Контракт C6 сохраняет liveness-ключевание и не вводит мьютекса; owner-marker + targeted `rmdir` — не повтор отвергнутого дизайна (он не использует ни `mv`, ни `rm -rf`).
- Вынести lock в `scripts/_lib.sh` как `mb_lock_acquire <lock_dir> <timeout> <ttl>` / `mb_lock_release <lock_dir> <token>` по design.md C6 — **полный I/O-контракт**: acquire печатает РОВНО `<PID>-<RANDOM>`+`\n`, exit 0; timeout → пустой stdout + stderr `code=lock_timeout lock=<JSON>` + exit 1; кривые args → stderr `code=lock_usage` + exit 2. release → stdout пуст; снимает только `<lock_dir>/owner.<token>` затем пустой `<lock_dir>`; exit 0 (снял свой ИЛИ лок отсутствует), exit 1 (чужой токен, ничего не удаляя). `mb-agree.sh` НЕ меняется.
- Reclaim-протокол owner-marker (design.md C6, R3-001, точно): захват — атомарный `mkdir "<lock_dir>"`, победитель создаёт РОВНО один маркер `<lock_dir>/owner.<token>` (`<token>=<PID>-<RANDOM>`). При доказанно мёртвом владельце `D` (`kill -0` провален): (1) `rmdir "<lock_dir>/owner.<D>"` — только маркер мёртвого токена (`ENOENT` безвреден); (2) `rmdir "<lock_dir>"` — только на пустом (`ENOTEMPTY` = появился свежий `owner.<Z>` → отступить, ничего не тронув); (3) повторить `mkdir`. Никаких `mv`/`rm -rf`. TTL — только owner-less окно (лок есть, `owner.*` нет) после `<ttl>` секунд. Reclaim ключуется на liveness (`kill -0`), PID-reuse → консервативный не-reclaim.

**Eval:** `bats tests/bats/test_mb_backlog_state.bats && bats tests/bats/test_mb_lock_helper.bats` — red: оба bats-файла материализованы; `scripts/mb-backlog-state.sh` (`transition`/`annotate`/`list`) и `mb_lock_acquire`/`mb_lock_release` в `_lib.sh` не существуют — кейсы машины, annotate и лока падают; exit: 1; output~: `not ok [0-9]+ (backlog_state|lock_helper): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста в `test_mb_backlog_state.bats` (включая кейсы `annotate`) начинается с `backlog_state: `, в `test_mb_lock_helper.bats` — с `lock_helper: ` (обоснование — то же, что в T1). Якорь покрывает первый (короткозамыкающий) конъюнкт `&&`-цепи и остаётся валидным для второго.
- bats state: все валидные рёбра и репрезентативная выборка невалидных (включая DONE→NEW, NEW→READY, WONTFIX→*); READY без Brief / с путём файла / с номером строки — каждый свой отказ и своя причина; success stdout `item=… old_state=… new_state=…`; usage exit 2; доп.-детали после токена статуса сохраняются байт-в-байт.
- bats annotate: добавление и замена `**Brief:**`; `--parent` на существующий I-NNN / `none` (удаление блока) / несуществующий (exit 1); невалидный brief (без глагола / с путём файла) → exit 1, тело записи байт-в-байт нетронуто; после `annotate` валидный переход `TRIAGED→READY` проходит (сквозной кейс достижимости READY); остальные блоки записи не мутируются.
- bats annotate — **anti-cycle (R3-009)**: I-061 уже несёт `**Parent:** I-060`; `annotate I-060 --brief <валидный> --parent I-061` → exit 1 `code=parent_cycle`, оба блока записи байт-в-байт, success-stdout не печатается.
- bats list (flat, R3-005): `list` на нескольких записях с/без `**Parent:**` → все строки `depth=0`, порядок по числовому I-NNN, `title=<JSON>` корректен; **неизвестная опция `--tree` в Task 2 → exit 2 без мутации файла** (полный `--tree` приходит в Task 7).
- bats lock (`test_mb_lock_helper.bats`) — **parity-часть**: общие фикстуры против приватных функций `mb-agree.sh` и против нового хелпера дают одинаковые вердикты по общим поведениям (захват `mkdir`; отказ при живом владельце; reclaim мёртвого владельца; TTL только при нечитаемом owner-файле; release только своим токеном; соблюдение timeout).
- bats lock — **divergence-часть (R3-001)**: отставший reclaim'ер + вклинившийся новый владелец (X и Y видят мёртвого D; Y реклеймит `rmdir owner.D`+`rmdir lock`; Z захватывает свежий лок `owner.Z`; отставший X исполняет своё решение) → у X `rmdir owner.D` даёт `ENOENT`, `rmdir lock` даёт `ENOTEMPTY`, `owner.Z` цел; единственный держатель сохраняется. Для `mb-agree.sh` этот кейс зафиксирован как известный дефект (ожидаемый результат прописан в тесте, скрипт не чинится).
- bats lock — release чужим токеном → exit 1, ничего не удалено; release своим → снят `owner.<token>` + пустой лок, exit 0; release при отсутствующем локе → exit 0 (идемпотентность); owner-less лок держится до `<ttl>`, затем снимается.
- bats lock — targeted `rmdir owner.<D>` не трогает соседний `owner.<Z>`; непустой лок `rmdir "<lock_dir>"` не проходит (`ENOTEMPTY`).
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] C3 (transition + READY-гейт) реализован; `mb_backlog_transition_locked` (precondition «caller владеет локом») выделен и покрыт тестами
- [ ] `list` flat реализован полностью; `--tree` в Task 2 → exit 2 без заглушки (полный tree — Task 7)
- [ ] `mb_lock_acquire`/`mb_lock_release` в `_lib.sh`: owner-marker + targeted `rmdir` reclaim (liveness), полный stdout/exit-контракт; parity- и divergence-тесты (R3-001) зелёные; `mb-agree.sh` не изменён
- [ ] bats green (были red)
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Мигратор беклога — легаси-таблица и SPEC-реестр

**Stage:** 2
**Covers:** REQ-009, REQ-010, REQ-011
**Role:** backend
**Blocked-by:** 2, 9
**Scope:** scripts/mb-backlog-migrate.sh, tests/bats/test_mb_backlog_migrate.bats, tests/fixtures/**
**Budget:** 100000

**What to do:**
- Новый `scripts/mb-backlog-migrate.sh [--dry-run|--apply] [mb_path]` по design.md C4: `--dry-run` — дефолт; `--apply` — backup в `.pre-migrate/<ts>/` (паттерн migrate-structure) + мутация; повторный `--apply` — `actions_pending=0`, файл не изменён, новый backup не создаётся.
- Мутация — под `mb_lock_acquire "<bank>/.locks/backlog.lock"` (design.md C6, хелпер из Task 2) + atomic-запись (temp + `mv`): мигратор такой же writer, как остальные (NFR-003).
- Финальная таблица легаси-статусов (design.md C4): `NEW→NEW`; `TRIAGED|OPEN|PROPOSED→TRIAGED`; `PLANNED→IN-PROGRESS`; `DONE[ <date>]→DONE` (не трогается); `RESOLVED[ <date>][ — <hash>]→DONE` (доп.текст сохраняется байт-в-байт); `DECLINED→WONTFIX` (блок **переносится** в `## Out of scope`, без ретроактивного `**Reason:**`); `DEFERRED→TRIAGED`. Статус вне таблицы и вне алфавита — warning `unknown_legacy_state`, не падение.
- `[SPEC:<group>]`-префикс → типизированные метастроки `**Type:**`/`**Group:**`/`**Parent:** none`/`**Spec:**` (design.md C4); ID/priority/date/тело — байт-в-байт.
- **Не штамповать `**Type:** IDEA` на исторические записи** (design.md C4): предикат grandfather («ни одной v2-метастроки») обязан пережить миграцию, иначе мигрированные `DECLINED→WONTFIX` без `**Reason:**` немедленно зафлагуются lint'ом.
- Легаси-записи без новых полей (без `--apply`) парсятся/отображаются unchanged (REQ-011 — негативные тесты).

**Eval:** `bats tests/bats/test_mb_backlog_migrate.bats` — red: bats-файл материализован; `scripts/mb-backlog-migrate.sh` не существует — кейсы маппинга статусов и `--dry-run`/`--apply` падают; exit: 1; output~: `not ok [0-9]+ backlog_migrate: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `backlog_migrate: ` (обоснование — то же, что в T1).
- bats на анонимизированной легаси-фикстуре этого репо (реальный инвентарь статусов, см. context.md): каждый маппинг отдельным кейсом; двойной `--apply` = no-op (файл byte-identical, backup не создаётся повторно); `--dry-run` не мутирует; `[SPEC:<group>]` → 4 метастроки; DECLINED-запись физически оказывается в `## Out of scope` без `**Reason:**`; после `--apply` ни одна историческая запись не получила `**Type:** IDEA`.
- bats конкурентность: `mb-backlog-migrate.sh --apply` и `mb-idea.sh` одновременно → сериализованы общим lock'ом, ни одна запись не потеряна, файл остаётся валидным. **Precondition (R3-004)**: `test_mb_backlog_id_alloc.bats` зелёный (т.е. `mb-idea.sh` уже переведён Task 9 на общий лок) ДО прогона migrate-vs-idea race-кейса — иначе test-seam отсутствует.
- Portability: Bash 3.2 (macOS) и Linux; путь с пробелами.
- shellcheck clean.

**DoD:**
- [ ] C4 реализован полностью по финальной таблице; мигратор пишет под общим lock'ом атомарно
- [ ] Grandfather-предикат переживает миграцию (нет `Type: IDEA` на исторических записях)
- [ ] bats green (были red)
<!-- /mb-task:3 -->

<!-- mb-task:6 -->
## Task 6: roadmap-sync — прогресс, Group-секции, `--check`, bootstrap

**Stage:** 2
**Covers:** REQ-002, REQ-003, REQ-012, REQ-013
**Role:** backend
**Blocked-by:** 1
**Scope:** scripts/mb-roadmap-sync.sh, tests/bats/test_mb_roadmap_sync_group.bats, tests/fixtures/**
**Budget:** 90000

**What to do:**
- Прогресс (design.md C2): для каждого плана/спеки — `python3 scripts/mb_work_items.py <path>` → `total_dod`/`checked_dod` → `progress_percent = floor(100*checked/total)` (0 при total=0); рендер `progress=<N>% stages(...)`/`tasks(...)` с counters done/in_progress/planned/total; пересчёт при каждом рендере, никогда не парсится обратно из roadmap.md.
- Group-секции (design.md C2): скан `specs/*/requirements.md` frontmatter по `group:`; `## Group: <name>` внутри fences; члены в порядке компаратора Task 1 (по `blocked_by: [<topic>...]` вместо `depends_on`, всегда priority-веткой); строка члена `<topic> — ice=<score|no-ice|invalid>[ (unconfirmed)] — <status> — progress=<N>% — blocked_by=<csv|none>`; агрегированный процент группы = floor среднего по членам.
- **Позиция/порядок Group-блоков (design.md C2, R3-007)**: блоки эмитируются ПОСЛЕ `## Linked Specs (active)` и ПЕРЕД `<!-- /mb-roadmap-auto -->`; несколько групп — по slug bytewise C-locale ↑; заголовок ровно `## Group: <slug>`, группы разделяет одна пустая строка; контент вне fence не трогается.
- **Наблюдаемый `unconfirmed_ice=` + эскалация (design.md C2, AGR-021, REQ-013)**: когда рендеримый порядок использует ≥1 валидный, но неподтверждённый `ice` (`ice_confirmed ≠ true`), печатать в **stderr** ровно одну строку `unconfirmed_ice=<csv topic-слагов, bytewise C-locale ↑>`; порядок из-за неподтверждённости НЕ меняется; когда неподтверждённых нет — строка не печатается. Флип `ice_confirmed` пишет оркестратор (скрипт frontmatter спеки не мутирует).
- `orphan_group` (design.md C2): множество отрендеренных ранее групп читается ТОЛЬКО из `## Group: <slug>`-заголовков ВНУТРИ текущего fence; slug, отсутствующий среди `specs/*/requirements.md`, → warning + исчезает из нового блока; ручные `## Group:` вне fences никогда не читаются как реестр.
- `--check [mb_path]` (read-only): вычисляет ожидаемый autosync-блок в памяти, никогда не пишет, exit 0 идентично / exit 1 устарело.
- Bootstrap: перенести ручной блок `roadmap.md § Group: sdd-vision-pipeline` под fences, удалить ручной текст (единственный источник — автосинк).

**Eval:** `bats tests/bats/test_mb_roadmap_sync_group.bats` — red: bats-файл материализован; прогресс, Group-секции, `--check` и bootstrap не реализованы — соответствующие кейсы падают; exit: 1; output~: `not ok [0-9]+ roadmap_sync_group: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `roadmap_sync_group: ` (обоснование — то же, что в T1).
- bats: процент+счётчики на фикстурах с частично отмеченными DoD; `total_dod=0` → `0%`; Group-рендер (member order, blockers, aggregate, `(unconfirmed)`-метка); `orphan_group` — stale-заголовок внутри fence при отсутствующей спеке → warning + удаление из блока; ручной `## Group:` ВНЕ fence не даёт warning и не трогается; `--check` exit 0/1 без мутации файла; bootstrap-перенос происходит один раз и идемпотентен.
- bats позиция/порядок групп (R3-007): фикстура с ДВУМЯ группами и обратным порядком скана файлов → Group-блоки после `## Linked Specs (active)`, до закрывающего fence, slug'и по C-locale ↑, ровно `## Group: <slug>`, одна пустая строка между группами; контент вне fence byte-identical.
- bats `unconfirmed_ice=` (AGR-021, REQ-013): фикстура с валидным неподтверждённым `ice` → stderr несёт `unconfirmed_ice=<slug>`, порядок = по score (не изменён неподтверждённостью); после флипа `ice_confirmed: true` строка исчезает и `(unconfirmed)` снят; когда все подтверждены — строки нет.
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] Прогресс + Group + `orphan_group` из fence-источника + `--check` + bootstrap реализованы
- [ ] Позиция/порядок Group-блоков (R3-007) и `unconfirmed_ice=`-эскалация (AGR-021, REQ-013) реализованы
- [ ] bats green (были red)
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: Иерархия — `list`/`list --tree`, parent

**Stage:** 2
**Covers:** REQ-006
**Role:** backend
**Blocked-by:** 2
**Scope:** scripts/mb-backlog-state.sh, tests/bats/test_mb_backlog_state_hierarchy.bats
**Budget:** 70000

**What to do:**
- `**Parent:** <I-NNN|none>` (по умолчанию `none`, поле опционально) в теле записи (design.md C3).
- Грамматика вывода (design.md C3, F-005) — ровно одна строка на элемент: `item=<I-NNN> state=<STATE> parent=<I-NNN|none> depth=<int≥0> title=<JSON-string>`; `title` — компактный JSON-литерал (`ensure_ascii=False`), что снимает экранирование кавычек/юникода.
- `list` — плоский, `depth=0`, порядок по числовому I-NNN; `list --tree` — pre-order, родитель раньше потомков, siblings по числовому I-NNN, `depth` = глубина (корни 0); записи `## Out of scope` не печатаются.
- Ошибки: stdout ПУСТ, stderr `code=missing_parent item=<I-NNN> parent=<I-NNN>` или `code=parent_cycle path=<I-a>-><I-b>-><I-a>`, exit 1 — без частичного дерева.

**Eval:** `bats tests/bats/test_mb_backlog_state_hierarchy.bats` — red: bats-файл материализован; `**Parent:**`, грамматика вывода и `list --tree` не реализованы — кейсы дерева и fail-fast падают; exit: 1; output~: `not ok [0-9]+ backlog_hierarchy: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `backlog_hierarchy: ` (обоснование — то же, что в T1).
- bats: parent-before-children с `depth=0`/`depth=1`; сиблинги по числовому ID; несуществующий parent → exit 1, stdout пуст; цикл (A parent=B, B parent=A) → exit 1 с полным путём; плоский `list` даёт `depth=0` у всех и порядок по ID; заголовок с кавычками/юникодом/пробелами корректно кодируется в `title=`; записи `## Out of scope` не появляются в выводе.
- Portability: прогон синтаксиса/тестов под Bash 3.2 (macOS) и текущим Bash (Linux); запрещены ассоциативные массивы, `mapfile`/`readarray` и GNU-only флаги без fallback; кейс с путём банка, содержащим пробелы (NFR-004).
- shellcheck clean.

**DoD:**
- [ ] Иерархия + грамматика `item=… depth=… title=<JSON>` реализованы для `list` и `list --tree`
- [ ] Fail-fast (missing_parent/parent_cycle) без частичного вывода
- [ ] bats green (были red)
<!-- /mb-task:7 -->

<!-- mb-task:9 -->
## Task 9: Глобальный аллокатор I-NNN + promote на машине C3

**Stage:** 2
**Covers:** REQ-005, REQ-011, NFR-003
**Role:** backend
**Blocked-by:** 2
**Scope:** scripts/_lib.sh, scripts/mb-idea.sh, scripts/mb-idea-promote.sh, tests/bats/test_mb_backlog_id_alloc.bats, tests/bats/test_mb_idea_promote_v2.bats
**Budget:** 110000

**What to do:**
- `mb_next_backlog_id <bank>` в `scripts/_lib.sh` (design.md C6) — **единственный** аллокатор I-NNN; вызывается только при удерживаемом `<bank>/.locks/backlog.lock`; `next = max(все I-[0-9]{3}) + 1` по источникам: `backlog.md` (обязателен), `progress.md` (обязателен, если существует), `progress-archive.md` (если существует — `/mb consolidate` физически переносит записи туда, `mb-consolidate.sh:24`), `index.json` (если существует). НЕ сканируются: `status.md`/`roadmap.md`/`checklist.md`/`notes/`/`session/` (только цитируют ID) и `.index/`/`.pre-migrate*/`/`.migration-backup-*/`/`session/archive/` (производные и бэкапы).
- Нечитаемый опциональный источник → `[warn] backlog id scan: unreadable source <path>; ignored`, продолжение; нечитаемый обязательный → exit 1 без аллокации; `max ≥ 999` → exit 1 (расширение формата вне scope).
- Заменить самодельный аллокатор `mb-idea.sh:65` (`grep` только по `backlog.md`) вызовом хелпера; `mb-idea.sh` и `mb-idea-promote.sh` берут `mb_lock_acquire` ДО чтения максимума/мутации и освобождают сразу после atomic-записи (temp + `mv`).
- **`mb-idea-promote.sh` → машина C3 (design.md C7)**: `PLANNED` не пишется НИКОГДА; единственный записываемый переход — `READY → IN-PROGRESS` через `mb_backlog_transition_locked` Task 2 (precondition: promote уже держит `backlog.lock`, зовёт функцию с `--plan <rel>` — она сама лок не берёт); порядок lock → read → validate READY → создать план → одна atomic-запись (статус + `**Plan:**`) → unlock; отказ на валидации → ни плана, ни мутации. Матрица состояний и exit-коды — таблица C7 (`NEW`/`NEEDS-INFO`/`TRIAGED` → exit 2 с ремедиацией до READY; легаси-токен C4 → exit 2 с «run mb-backlog-migrate.sh»; `IN-PROGRESS`/`DONE`/`WONTFIX` → exit 2; иное → exit 1; invalid type → exit 3).
- **Partial-failure recovery (design.md C7, R3-008)**: план создан, но backlog-write/sync упал → exit 1 + stderr `code=promote_partial plan=<rel> backlog_updated=<true|false>`; повторный promote того же I-NNN обнаруживает ровно этот план, второго НЕ создаёт, идемпотентно дозакрывает недостающий шаг; ни один сбой не выдаётся за успех.

**Eval:** `bats tests/bats/test_mb_backlog_id_alloc.bats && bats tests/bats/test_mb_idea_promote_v2.bats` — red: оба bats-файла материализованы; `mb_next_backlog_id` не существует и `mb-idea-promote.sh` всё ещё пишет `PLANNED` — кейсы коллизии I-079 и READY-only promote падают; exit: 1; output~: `not ok [0-9]+ (backlog_id_alloc|idea_promote): `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста в `test_mb_backlog_id_alloc.bats` начинается с `backlog_id_alloc: `, в `test_mb_idea_promote_v2.bats` — с `idea_promote: ` (обоснование — то же, что в T1). Якорь покрывает первый (короткозамыкающий) конъюнкт `&&`-цепи и остаётся валидным для второго.
- bats аллокатор: воспроизвести коллизию I-079 — `backlog.md` max I-074 + `progress.md` с I-075 → выдан I-076 (регресс-тест на реальный дефект репо); `mb_next_backlog_id` печатает ровно `I-NNN`+`\n` (exit 0), фатальный сбой → пустой stdout + exit 1; ID из `progress-archive.md` учитывается; ID из `index.json` учитывается; ID в `status.md`/`notes/`/`.pre-migrate/` НЕ поднимает счётчик; нечитаемый опциональный источник → warning + успех; отсутствующий `backlog.md` → exit 1 без аллокации; `max = 999` → exit 1; два параллельных `mb-idea.sh` с РАЗНЫМИ title → разные ID, обе записи на месте; **два конкурентных процесса с ОДИНАКОВЫМ title (R3-001) → один блок и один общий ID** (idempotency+similarity перепроверены под тем же локом).
- bats promote: `READY` + валидный Brief → план создан, состояние `IN-PROGRESS`, `PLANNED` не появился; `NEW`/`NEEDS-INFO`/`TRIAGED` → exit 2, план НЕ создан, `backlog.md` byte-identical, stderr несёт ремедиацию до READY; легаси `PLANNED`/`DEFERRED` → exit 2 с подсказкой мигратора; `DONE`/`WONTFIX` → exit 2 (сегодняшняя семантика); неизвестный статус → exit 1; invalid type → exit 3; grep по всему репо не находит записи токена `PLANNED` ни в одном пути `mb-idea-promote.sh`.
- bats promote — **partial-failure (R3-008)**: fault-injection после создания плана и после backlog-`rename` → exit 1 `code=promote_partial …`; повторный вызов оставляет ровно один план и ровно одну `**Plan:**`-ссылку, второй план не создаётся.
- bats CLI совместимости `mb-idea.sh` (design.md C3, F-010): старый позиционный вызов `mb-idea.sh "title" HIGH <mb>` — поведение и stdout byte-identical; `--force` первым аргументом; `--` escape-hatch для заголовка с дефисами; неизвестный `--flag` первым аргументом → exit 2 ДО мутации файла.
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] `mb_next_backlog_id` — единственный аллокатор; коллизия I-079 воспроизведена тестом и не повторяется; самодельный аллокатор в `mb-idea.sh` удалён
- [ ] `mb-idea-promote.sh` не пишет `PLANNED` ни в одной ветке; единственный переход — READY→IN-PROGRESS через общий примитив
- [ ] Старые позиционные вызовы `mb-idea.sh` byte-identical; `--force`/`--` разобраны по C3
- [ ] bats green (были red)
<!-- /mb-task:9 -->

<!-- mb-task:8 -->
## Task 8: Out-of-scope, похожесть и типизированный SPEC-writer

**Stage:** 3
**Covers:** REQ-008, REQ-009
**Role:** backend
**Blocked-by:** 2, 7, 9
**Scope:** scripts/mb-backlog-state.sh, scripts/mb-idea.sh, tests/bats/test_mb_backlog_out_of_scope.bats
**Budget:** 110000

**What to do:**
- Переход в `WONTFIX` требует непустой `--reason TEXT`; при успехе блок записи физически переносится из `## Ideas` в `## Out of scope` с добавленной строкой `**Reason:** <TEXT>`; ID/title/created-date байт-в-байт.
- Similarity-хук в `mb-idea.sh` перед записью нового I-NNN (design.md C3): normalize (casefold, non-alphanumeric→пробел, уникальные токены ≥4 символов) только против заголовков `## Out of scope`; `score = |∩|/min(|a|,|b|)`; `score≥0.5` → печать `similar_out_of_scope=<I-NNN> score=<0..1>` на stderr + отказ exit 1, если не передан `--force`; несколько совпадений → наименьший I-NNN.
- **Типизированный writer реестра (design.md C4, R2-004)**: `mb-idea.sh` распознаёт точный префикс заголовка `[SPEC:<group>] <child-topic>` → префикс убирается из хранимого title, атомарно эмитируются `**Type:** SPEC`, `**Group:** <group>`, `**Parent:** none`, `**Spec:** <child-topic>`; обычная запись получает `**Type:** IDEA`; заголовочная строка и stdout (`I-NNN`) сохраняют сегодняшнюю грамматику байт-в-байт. Similarity-гейт к SPEC-записи НЕ применяется (иначе call-site S2 мог бы быть заблокирован).

**Eval:** `bats tests/bats/test_mb_backlog_out_of_scope.bats` — red: bats-файл материализован; WONTFIX-перенос, similarity-хук и типизированный SPEC-writer не реализованы — соответствующие кейсы падают; exit: 1; output~: `not ok [0-9]+ backlog_out_of_scope: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `backlog_out_of_scope: ` (обоснование — то же, что в T1).
- bats WONTFIX: без `--reason` → exit 1, ничего не меняется; успешный перенос — блок в `## Out of scope`, в `## Ideas` его нет, ID/дата байт-в-байт.
- bats similarity: match → блокирует создание (exit 1, stderr-строка), `--force` создаёт; несколько совпадений → наименьший ID; пустые токен-множества → score 0 (не блокирует); идемпотентность по title `--force` НЕ обходит.
- bats writer: `mb-idea.sh "[SPEC:g] topic"` → typed-запись сразу, без прогона мигратора, stdout ровно `I-NNN`, similarity не вызывался; обычная идея → `**Type:** IDEA`; мигратор (T3) на уже типизированной записи — no-op (`actions_pending=0`, паритет writer↔мигратор на общей фикстуре).
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] WONTFIX-перенос + similarity-хук реализованы; SPEC-записи гейт не блокирует
- [ ] `mb-idea.sh` пишет typed SPEC-запись сразу; паритет с мигратором доказан тестом (мигратор = no-op)
- [ ] bats green (были red)
<!-- /mb-task:8 -->

<!-- mb-task:4 -->
## Task 4: mb-bank-lint.sh

**Stage:** 3
**Covers:** REQ-004, REQ-012
**Role:** backend
**Blocked-by:** 1, 2, 6, 7
**Scope:** scripts/mb-bank-lint.sh, tests/bats/test_mb_bank_lint.bats
**Budget:** 100000

**What to do:**
- Новый `scripts/mb-bank-lint.sh <roadmap|backlog|all> [--mb PATH]` по design.md C5: одна строка на находку `severity=<warning|error> code=<code> file=<JSON-string> line=<int≥0> detail=<JSON-string>`; JSON-строки — `json.dumps(value, ensure_ascii=False, separators=(',',':'))`; детерминированный порядок вывода `file`↑ → `line`↑ → `code`↑.
- **15 кодов**, каждый со своим тест-кейсом. Warning: `no_ice`, `ice_unconfirmed`, `orphan_group`, `duplicate_pin`, `legacy_state`. Error: `invalid_ice`, `invalid_ice_confirmed`, `invalid_pin`, `invalid_group`, `invalid_blocked_by`, `progress_mismatch` (через `mb-roadmap-sync.sh --check`, Task 6 — логика рендера не дублируется), `invalid_state`, `ready_without_brief`, `wontfix_without_reason`, `parent_cycle`.
- `invalid_ice` — нарушение грамматики C1 (не flow-mapping / не 3 ключа / дубль ключа / не целое / вне 1..10 / plain-int); `ice_unconfirmed` — валидный `ice` без `ice_confirmed: true`.
- Новые коды REQ-004-полей (R3-003): `invalid_ice_confirmed` (не литерал `true`/`false`), `invalid_pin` (не base-10 `>0`), `invalid_group` (не `[a-z0-9][a-z0-9-]*`), `invalid_blocked_by` (не flow-list уникальных слагов той же грамматики), `wontfix_without_reason` (v2-WONTFIX без непустого `**Reason:**`; чисто-легаси grandfathered).
- `legacy_state` (warning) vs `invalid_state` (error): токен из таблицы C4 → warning с указанием целевого токена и `mb-backlog-migrate.sh`; токен вне алфавита C3 И вне таблицы C4 → error. Это обязательное следствие REQ-011 — не-мигрированный банк не должен краснеть.
- Grandfather-исключение (design.md C4): `ready_without_brief` и требование `**Reason:**` не применяются к записям без единой v2-метастроки.
- Область скана: `roadmap` — `roadmap.md` + питающий frontmatter (`plans/*.md`, `specs/*/requirements.md`); `backlog` — `backlog.md`; `all` — оба. Exit 0 нет errors / 1 ≥1 error / 2 неверный вызов. Read-only во всех режимах.

**Eval:** `bats tests/bats/test_mb_bank_lint.bats` — red: bats-файл материализован; `scripts/mb-bank-lint.sh` не существует — кейсы всех 10 кодов и формата падают; exit: 1; output~: `not ok [0-9]+ bank_lint: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `bank_lint: ` (обоснование — то же, что в T1).
- bats: чистый банк → exit 0, пустой stdout; **отдельная отрицательная фикстура на КАЖДЫЙ из 15 кодов** (включая по кейсу на `invalid_ice_confirmed`/`invalid_pin`/`invalid_group`/`invalid_blocked_by`/`wontfix_without_reason`); `legacy_state` не влияет на exit, `invalid_state` влияет; grandfather-исключение (легаси WONTFIX без Reason и легаси READY без Brief не флагуются, v2-запись — флагуется); неизвестный аргумент раздела → exit 2; файлы банка байт-в-байт не изменены после каждого запуска.
- bats формат: путь с пробелами и заголовок с кавычками/юникодом корректно кодируются в `file=`/`detail=`; повторный запуск даёт байт-идентичный вывод (детерминированный порядок).
- Portability: Bash 3.2 (macOS) и Linux; путь банка с пробелами.
- shellcheck clean.

**DoD:**
- [ ] C5 реализован (15 кодов, детерминированный порядок, read-only); `legacy_state`/`invalid_state` разделены
- [ ] bats green (были red)
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Документация статусов, схемы и CLI

**Stage:** 4
**Covers:** REQ-001, REQ-002, REQ-003, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009
**Role:** developer
**Blocked-by:** 1, 2, 3, 4, 6, 7, 8, 9
**Scope:** commands/mb.md, references/templates.md, CLAUDE.md, tests/bats/test_mb_roadmap_backlog_docs.bats
**Budget:** 60000

**What to do:**
- Обновить `commands/mb.md` (idea/idea-promote/agree-блоки: машина `NEW→NEEDS-INFO⇄TRIAGED→READY→IN-PROGRESS→DONE|WONTFIX`, `**Type:**`/`**Parent:**`/`**Brief:**`, synopsis `mb-backlog-state.sh`/`mb-bank-lint.sh`/`mb-backlog-migrate.sh`, идентичный `--help` скриптов).
- **Задокументировать смену поведения `mb-idea-promote.sh`** (design.md C7): promote требует `READY`; путь `NEW → NEEDS-INFO → TRIAGED → READY (нужен Brief) → promote`; токен `PLANNED` больше не пишется, легаси-`PLANNED` мигрируется в `IN-PROGRESS`. Это единственная ломающая привычки правка слайса — она обязана быть в доках, а не только в stderr.
- Обновить `references/templates.md`: frontmatter-схема `group`/`ice: {impact, confidence, ease}` (1..10, score = I×C×E считает скрипт)/`ice_confirmed`/`pin`/`blocked_by` для спек и планов (design.md C1).
- Обновить `CLAUDE.md`-инварианты: стейт-машина вместо `NEW/TRIAGED/PLANNED/DONE/DECLINED/DEFERRED`; I-NNN аллоцируется глобально по банку одним хелпером (design.md C6).

**Eval:** `bats tests/bats/test_mb_roadmap_backlog_docs.bats` — red: bats-файл материализован; `commands/mb.md`, `references/templates.md` и `CLAUDE.md` не обновлены — кейсы сверки доков с реализацией падают; exit: 1; output~: `not ok [0-9]+ roadmap_backlog_docs: `

**Testing (TDD — tests BEFORE implementation):**
- **Конвенция именования (обязательна — она и есть red-якорь)**: имя каждого bats-теста файла начинается с `roadmap_backlog_docs: ` (обоснование — то же, что в T1).
- bats извлекает документированные блоки и assert-ит точное совпадение с реализацией: полный список допустимых переходов; READY-брифо-гейт; WONTFIX reason/out-of-scope; promote требует READY и `PLANNED` не пишется; frontmatter-поля `topic/group/ice{impact,confidence,ease}/ice_confirmed/pin/status/created/blocked_by` документированы; CLI synopsis в `commands/mb.md` совпадает с `--help`/usage-комментарием каждого нового скрипта; `CLAUDE.md` содержит инвариант state-машины и глобального аллокатора.

**DoD:**
- [ ] Доки обновлены по всем пунктам, включая смену поведения promote
- [ ] bats green (был red)
<!-- /mb-task:5 -->
