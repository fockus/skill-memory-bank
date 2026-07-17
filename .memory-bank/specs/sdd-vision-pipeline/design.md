# Design: sdd-vision-pipeline (umbrella)

> Группа: `sdd-vision-pipeline` (D-31). Это umbrella-дизайн: фиксирует нарезку на слайсы,
> межслайсовые контракты и маршрутизацию открытых вопросов. Детальный дизайн каждого слайса
> рождается в его JIT-интервью и child-спеке (паттерн AGR-001).
> Входы: `context/sdd-vision-pipeline.md` (D-01…D-35, REQ-001…048);
> `context/svp-contract-test-loop.md` и AGR-018 (REQ-049…053); решение D-11 + закрытие SVP-012 (REQ-054);
> `context/sdd-vision-pipeline-interview.md` (обязателен для планировщика и spec-ревьювера, D-29/REQ-034).
> Ревизия 2 (2026-07-17): внесены исправления spec-ревью группы (SVP-001…016) —
> DAG уточнён, контракты 1–3 закрыты (грамматики и lock-протокол зафиксированы), добавлен
> Delegate-контракт мета-задач и REQ-054 (fast-to-code, D-11).
> Ревизия 3 (2026-07-17): закрыты находки круга 2 (SVP-008, R2-001…R2-011) + смысловой аудит —
> исполнимый DAG зашит в `**Blocked-by:**` каждой мета-задачи (SVP-008), ICE-контракт хранит
> компоненты I/C/E (R2-004), provenance REQ уточнён (R2-011), attribution-Eval стал поведенческим
> (R2-002), REQ-009/043/049 приведены к D-17/D-32/AGR-018.
> Ревизия 4 (2026-07-18, spec-review круг 3): Interface 2 lock-протокол перепроектирован на
> owner-marker + targeted `rmdir` (закрыт critical R3-001 — `mv`-reclaim ещё допускал двух писателей;
> добавлен полный stdout/exit-контракт acquire/release); §DAG получил task-level жёсткие рёбра к S4
> (R3-003); Interface 3 сериализует escalation-журнал общим lock-helper'ом вместо PIPE_BUF (R3-004);
> Interface 4 сделал `ice_confirmed` наблюдаемым и эскалируемым (AGR-021, UNFIXED:D-14-ICE-SCHEMA);
> risk-число S2 выправлено 760k→850k (R3-007). Пост-ремедиация: REQ-022 стал dual-owned
> (spec-time S2 / runtime S3, X-04); интегрирован девятый слайс S9 `svp-spec-review-loop` (AGR-022,
> D-08) — строка в таблице слайсов, ребро DAG S9←S2, автоматический судья в Interface 5, мета-задача
> Task 10; REQ-035 dual-owned (S2 ревью-конфиг / S9 судья-петля-гейт); Task 6 (S5) получил ребро →
> Task 3 (S4) для lock/annotate.

## Architecture — нарезка на слайсы

Девять child-спек + одна задача без спеки. Каждый слайс ≲1M токенов (D-13), проходит короткое
JIT-интервью (решения уже в леджере — только слайс-специфика), получает `group: sdd-vision-pipeline`
и `ice`/`blocked_by` во frontmatter requirements.md (bootstrap D-31 вручную, автоматика — в S4).

| Слайс | Child-спека | Владеет | REQ | ICE (I×C×E, предложение) |
|---|---|---|---|---|
| S1 | `svp-interview-upgrade` | план интервью, финальный гейт, размерный триаж, глоссарий, транскрипт, batch-режим, self-interview, fast-to-code bypass (D-11) | 004, 010–015, 033, 034, 040, 054 | 8×9×7 = 504 |
| S2 | `svp-sdd-core` | sdd-конвейер, tasks.md-формат v2 (stages/blocked_by/Scope/Eval/бюджеты — грамматики зафиксированы в S2-C1), §Contract+seams, бюджет-валидация, spec-review, размерная эскалация на генерации (D-35), батарея самопроверки генерации, spec-time рубеж цикла blocked_by (REQ-022, REQ-052; runtime-рубеж — S3) | 001–003, 005–009, 016, 022, 035, 039, 047, 048 | 10×8×5 = 400 |
| S3 | `svp-parallel-engine` | `--parallel`, фронтир (включая fail-fast на DAG-цикле, REQ-022), claims-lock, Scope-сверка, оркестратор-only записи, group-target + вопросы режима исполнения/вмешательства (D-32/33) | 017–023, 042–044 | 9×7×4 = 252 |
| S4 | `svp-roadmap-backlog-db` | ICE-сортировка, %, счётчики, валидация формата, беклог-стейт-машина, out-of-scope-реестр, группы спек | 024–029, 041 | 8×9×6 = 432 |
| S5 | `svp-adapt-escalation` | complexity_escalation, дет-гарды, развилки auto/interactive | 030–032 | 7×7×6 = 294 |
| S6 | `svp-docs-wiki` | `/mb docs`, Karpathy-вики, SHA-инкремент | 036, 037 | 6×8×7 = 336 |
| S7 | `svp-brief` | `/mb brief`: одностраничник из запроса+документов, папка с исходниками, лёгкие вопросы, хендоф в discuss | 045, 046 | 8×8×7 = 448 |
| S8 | `svp-contract-test-loop` | контрактная задача первой (чекеры критериев + тесты на чекеры + обязательный red), задачи интеграционных и e2e тестов, отключение слоёв во frontmatter, Quality DoD (правила как критерий для исполнителя/ревьюера/судьи) | 049–053 | 9×8×5 = 360 |
| S9 | `svp-spec-review-loop` | автоматический spec_judge (GO/GO_WITH_BACKLOG/NO_GO — судья терминирует цикл), fix-петля с независимым re-review, журнал kind=judge/override, durable реестр отклонений `specs/<topic>/review-deviations.md`, preflight-гейт `/mb work`, детерминированный сборщик review-промпта + bundled-рубрика (расширяет S2-C5; судья-человек остаётся дефолтом D-30) | 035 | 8×7×6 = 336 (не подтверждён, AGR-021) |
| — | задача T1 (без спеки) | MIT-атрибуция mattpocock/skills | 038 | сделать сразу |

### DAG слайсов

- S1, S2, S4 — фронтир (не заблокированы).
- S6 `blocked_by: S2` — общий файл `references/pipeline.default.yaml` с S2-T7 (межспековая ссылка `svp-sdd-core#7`, находка F-003 ревью S6).
- S7 `blocked_by: S1` — Task 1 брифа потребляет secret-scan контракт S1-C5 (ревью SVP-008/BRIEF-002).
- S8 `blocked_by: S2` — надстраивается над конвейером `/mb sdd` и tasks.md v2 (контрактная задача и слои — задачи внутри `implement`, контрактный гейт — внутри `verify`; канонический порядок стадий не меняется).
- S9 `blocked_by: S2` — расширяет spec-review контракт S2-C5 (журнал `mb-sdd-review-result.sh`, pipeline-блок `sdd.*`, создаваемые S2-T7): S9-задачи потребляют их, добавляя автоматического судью, fix-петлю, реестр отклонений и preflight-гейт `/mb work`; судья-человек остаётся дефолтом (D-30, `spec_judge` off → поведение как было).
- S3 `blocked_by: S2` — грамматики Scope/Blocked-by зафиксированы в S2-C1 (ревизия 2, без «поздней ревизии»). Group-target (D-32): рёбра **зависимостей** между спеками группы (`blocked_by` frontmatter) деградируют до упорядоченного списка спек, НО сам **компаратор** порядка — код S4-C2 (задача S4), а lock-helper — код S4-C6 (задача S4); это код-зависимости, а не data-деградация.
- S5 `blocked_by: S2, S3` — Eval/max_cycles-гарды опираются на tasks.md v2; scope-гард потребляет вердикт S3-C3 напрямую (ревью SVP-008/AE-005: зависимость жёсткая, enum единый); двухфазный escalation-журнал сериализуется общим lock-helper'ом S4-C6 (Interface 3 ниже) — это добавляет task-level ребро S5 → S4.
- **Task-level жёсткие рёбра к S4 (ревью R3-003)** — фронтир строится по полю `Blocked-by:` конкретных задач, поэтому топологический порядок до S4 либо стопорит потребителя, либо толкает его нарушить Scope/DRY. Обязательные рёбра (правки `Blocked-by:` в чужих файлах — cross-package requests, см. § Cross-slice requests владельцев-потребителей): `svp-parallel-engine` claims-задача → `svp-roadmap-backlog-db#2` (lock-helper C6); `svp-parallel-engine` group-target-задача → `svp-roadmap-backlog-db#1` (компаратор C2); `svp-docs-wiki` lock-потребляющая задача → `svp-roadmap-backlog-db#2`; `svp-adapt-escalation` annotate/escalation-задача → `svp-roadmap-backlog-db#2`. Fallback-фразы «реализовать helper в `_lib.sh`, если он ещё не отгружен» удаляются из потребителей (нарушение их Scope).
- Порядок исполнения: T1 → S1 (504) → S7 (448, после S1) → S4 (432) → S2 (400) → S8 (360) → S6 (336) → S9 (336, после S2) → S3 (252) → S5 (294, после S3). ICE-цифры — предложение LLM, подтверждает пользователь; неподтверждённые используются с ворнингом + эскалацией на подтверждение/правку, порядок ими не блокируется (D-14, AGR-021; см. Interface 4).
- Цикл в `blocked_by` группы — ошибка с печатью полного пути цикла на двух рубежах (REQ-022): на spec-валидации — S2 (REQ-052 `svp-sdd-core`), в runtime-построении фронтира — S3 (fail-fast).

## Interfaces — межслайсовые контракты

Декларации — код пишется в слайсах (D-05 применён к самой стройке):

1. **tasks.md v2** (S2 определяет, S3/S5/S8 потребляют): поля `Stage:`, `Blocked-by:`, `Scope:`, `Eval:`, `Budget:`. Грамматики **зафиксированы в S2-C1**: Blocked-by — CSV из `<n>` | `<topic>#<n>`; Scope — CSV repo-relative POSIX globs (`*` не пересекает `/`, `**` пересекает; без абсолютных/`..`/negation; task-Scope не включает `.memory-bank/**`). Парсер `mb_work_items.py` расширяется backward-compatible (REQ-039): проекция pre-v2 ключей byte-identical, новые ключи с дефолтами для легаси. **Red-якоря Eval**: на gated-задачах `Eval:` обязан нести `output~:`-якорь (сигнатура вывода настоящего провала), `exit:` опционален — отсутствие target-файла red'ом НЕ считается (`bats <missing>` даёт тот же exit 1, что и настоящий провал; S2 REQ-054/055).
2. **Frontier API + claims-lock** (S3): `mb_work_items.py --frontier` → задачи с закрытыми блокерами, свободными claim и Scope-дизъюнктностью; fail-fast на цикле DAG с печатью пути. Мутации claims — под owner-token `mkdir`-lock (`<bank>/tmp/.work-claims.lock`): под lock читается последнее событие task_id, валидируется переход, append-ится ровно одно JSONL-событие `{task_id, session_id, ts, op: claim|release|release_stale}`, lock снимается. Exit: 0 успех; 1 занято/не-владелец; 2 usage/битое состояние; 3 lock-timeout.
   - **Lock-протокол — owner-marker, а не bulk-move** (ревью R3-001, закрывает PARTIAL R2-007: `mv`-reclaim прошлой ревизии всё ещё допускал двух писателей). Полный контракт двух функций (S4-C6 их реализует в `scripts/_lib.sh`, потребители S3/S5/S6 только вызывают):
     - `mb_lock_acquire <lock_dir> <timeout> <ttl>` — при захвате печатает в stdout **РОВНО** токен `<PID>-<RANDOM>` плюс `\n` и возвращает `0`; при таймауте — stdout **пуст**, stderr `code=lock_timeout lock=<JSON-string>`, exit `1`; при кривых аргументах (нечисловой `timeout`/`ttl`, пустой `lock_dir`) — stdout пуст, stderr `code=lock_usage`, exit `2`.
     - `mb_lock_release <lock_dir> <token>` — stdout всегда пуст; удаляет ТОЛЬКО `<lock_dir>/owner.<token>`, затем пустой `<lock_dir>` (`rmdir`, проходит лишь на пустом каталоге); возвращает `0`, если снял свой owner ИЛИ лок уже отсутствует; возвращает `1` при чужом токене (owner другого) и при этом **не удаляет ничего**.
     - **Критическая секция — атомарный `mkdir "<lock_dir>"`** (единственный гейт захвата). Победитель `mkdir` немедленно создаёт РОВНО один маркер владельца — подкаталог `<lock_dir>/owner.<token>`. Инвариант: у корректного лока внутри 0 или 1 маркеров `owner.*`.
     - **Reclaim ключуется на liveness (`kill -0` по PID из токена), а НЕ на mtime/TTL**, и НЕ двигает, НЕ сносит лок целиком: при доказанно мёртвом владельце `D` reclaim = `rmdir "<lock_dir>/owner.<D>"` (удаляет ТОЛЬКО маркер именно мёртвого токена; `ENOENT` = уже реклеймлено другим, безвредно) → затем `rmdir "<lock_dir>"` (проходит ТОЛЬКО если пусто; `ENOTEMPTY` = внутри уже появился свежий `owner.<Z>` живого владельца → отступить, ничего не тронув) → повторить `mkdir`. Никаких `mv`/`rm -rf` в reclaim: отставший reclaim'ер физически не может убрать чужой свежий лок, т.к. (а) целится в **именованный** мёртвый токен `D`, а не в каталог целиком, и (б) `rmdir "<lock_dir>"` не проходит, пока внутри есть живой `owner.<Z>`. Это и закрывает разрушительный интерливинг R3-001 (X читает dead D; Y удаляет D; Z захватывает новый lock; поздний X больше не может снести лок Z).
     - **TTL — только для owner-less окна**: лок существует, но `owner.*` внутри нет (окно между `mkdir` и записью маркера, между `rmdir owner.<D>` и `rmdir <lock_dir>`, или crash в этом окне). Такой лок НЕ сносится немедленно — только после `<ttl>` секунд устойчивого owner-less состояния (консервативно, чтобы не гонять с почти-завершившимся reclaim'ером). PID-reuse (`kill -0` на живой PID) → консервативный НЕ-reclaim → громкий timeout: потеря доступности, не корректности.
     - **Ровно одно расхождение с `mb-agree.sh` — механизм критической секции, а НЕ liveness-решение**: оригинал держит `<lock>/owner`-файл и сносит лок неатомарным `rm -rf` (`mb-agree.sh:138`), у которого гонка «отставший сносит уже ДРУГОЙ, свежий лок». Owner-marker + targeted `rmdir` эту гонку закрывает целиком. Это не повтор отвергнутого `mv`-варианта (`mb-agree.sh:60-78`): тот продолжал ключевать решение на mtime/TTL и добавлял вторичный `.reclaiming`-мьютекс; здесь liveness сохранён, вторичного мьютекса нет, а bulk-move/`rm -rf` заменён на targeted-`rmdir` именованного мёртвого токена. `mb-agree.sh` этим слайсом не рефакторится (D-29: `mb-agree.sh:56-116` обязателен к чтению перед реализацией — 4 disproved-итерации).
     - **Обязательный race-тест**: X и Y видят мёртвого `D`; Y полностью реклеймит (`rmdir owner.D`, `rmdir lock`); Z захватывает свежий лок (`owner.Z`); поздний X исполняет своё решение — `rmdir owner.D` даёт `ENOENT` (no-op), `rmdir lock` даёт `ENOTEMPTY` (отступает), `owner.Z` цел; во всей трассе РОВНО один процесс в критической секции.
   - **Crash-устойчивость обязательна**: `trap` не исполняется на SIGKILL/падении хоста, поэтому лок без liveness-reclaim навсегда запирает все мутации (каждый следующий вызов → exit 3). Мёртвый владелец обязан реклеймиться; PID-reuse → консервативный НЕ-reclaim (loud timeout, ноль записей) — потеря доступности, не корректности.
   - **Согласованное чтение `list`**: конкурентный append может оставить временно оборванную последнюю строку; `list` обязан отличать её от порчи состояния — частичная хвостовая строка retryable (перечитать под локом или дождаться его), а не exit 2 «битое состояние».
   - **Жёсткая task-level зависимость S3 → S4** (ревью R3-003): общий helper `mb_lock_acquire`/`mb_lock_release` выносится в `scripts/_lib.sh` слайсом S4 (S4-C6). Задача S3, потребляющая лок (claims-слой), **не самодостаточна** — её Scope не включает `_lib.sh`, поэтому «fallback-реализация helper'а, если он ещё не отгружен» удалена как нарушение Scope/DRY: helper обязан существовать ДО неё. Это **добавляет жёсткое ребро** на уровне задач (`svp-parallel-engine#<claims-task>` → `svp-roadmap-backlog-db#<helper-task>`), зафиксированное в §DAG ниже и запрошенное у S3 как cross-package request (S3 меняет своё `Blocked-by:` и убирает fallback-фразу). S4 (ICE 432) идёт раньше S3 (252), поэтому ребро согласуется с порядком.
3. **Escalation-контракт** (S5): структурный блок в отчёте имплементера `{"complexity_escalation": {reason, estimated_tokens}}` + гард-вердикты от `mb-work-budget.sh` / Scope-чека (S3-C3) / severity-gate. Запись — двухфазная append-only: событие `opened` (без resolution) при эскалации, событие `resolved` после решения; читатель сворачивает по `escalation_id`, последнее событие побеждает.
   - **Конкурентность — сериализация общим lock-helper'ом, а НЕ опора на PIPE_BUF** (ревью R3-004): `rules/RULES.md` явно допускает несколько orchestrator-сессий в одном working tree, поэтому `<bank>/tmp/escalations.jsonl` пишется конкурентно, а гарантия атомарности `write()` при длине ≤`PIPE_BUF` относится к pipe/FIFO, НЕ к concurrent append в regular file (повреждённая строка потом делает журнал fail-loud и блокирует cascade/replan). Требование: весь путь read → validate (вычисление seq/consecutive по `escalation_id`/`run_id`) → один append выполняется под `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` (Interface 2, S4-C6), release — через `trap`; `replan-gate` и summary читают согласованный snapshot под тем же lock. Утверждение про PIPE_BUF и лимит 4096 как гарантию атомарности удаляется. Приземление в S5 (`svp-adapt-escalation` C1.0 §Concurrency) — cross-package request.
4. **Group frontmatter** (S4 автоматизирует, до того — вручную): `group: <name>` + `ice: {impact: <1..10>, confidence: <1..10>, ease: <1..10>}` + `ice_confirmed: <true|false>` + `blocked_by: [<spec-slug>…]` во frontmatter `specs/<topic>/requirements.md`; `mb-roadmap-sync.sh` рендерит `## Group:`-секции. Хранятся **компоненты**, а не готовый балл: `score = impact×confidence×ease` вычисляет скрипт, `mb-bank-lint.sh` отклоняет отсутствующий или вне-диапазонный компонент (D-14: «заполняется скриптом где возможно», REQ-024). `pin` — отдельный override порядка, не трогает score. Bootstrap-значения слайсов (I×C×E из таблицы выше): S1 `{8,9,7}`, S2 `{10,8,5}`, S3 `{9,7,4}`, S4 `{8,9,6}`, S5 `{7,7,6}`, S6 `{6,8,7}`, S7 `{8,8,7}`, S8 `{9,8,5}` — миграция 8 child-frontmatter и валидатор принадлежат S4 (`svp-roadmap-backlog-db`).
   - **`ice_confirmed` больше не декоративен** (AGR-021, закрывает UNFIXED:D-14-ICE-SCHEMA): авто-приоритизация остаётся и порядок **не блокируется** неподтверждённостью, но неподтверждённый `ice` наблюдаем и эскалируется. Рендер S4-C2 помечает такие члены/секции строкой `unconfirmed_ice=<csv-слагов>` и суффиксом `(unconfirmed)`, `mb-bank-lint.sh` даёт warning `ice_unconfirmed`, а оркестратор ЭСКАЛИРУЕТ пользователю «подтверди/поправь приоритеты». Подтверждение = флип `ice_confirmed: false → true` во frontmatter `requirements.md` члена; писать его вправе ТОЛЬКО оркестратор (D-23 «банк пишет только оркестратор» — скрипта-writer'а frontmatter спеки нет). Детали контракта — S4-C1/C2 и S4 REQ-013.
5. **Spec-review контракт** (S2-C5): `pipeline.yaml: sdd.spec_review {enabled, agent, model, thinking}`; проверка `same_model` (exit 2 до диспатча); строгий JSON-вердикт **append-only** в `<bank>/tmp/spec-review/<topic>.jsonl` — одна строка на попытку с обязательными `ts`/`attempt`, последняя валидная строка = действующий вердикт, SKIPPED — отдельная строка (согласовано с NFR-005; писатель — `scripts/mb-sdd-review-result.sh`, S2-T7); судья — человек/оркестратор (D-30); недоступность → SKIPPED loudly.
   - **Автоматический судья — слайс S9** (`svp-spec-review-loop`, AGR-022): поверх этого контракта S9 добавляет опциональный `sdd.spec_judge {enabled: false, …}` — автоматического судью `GO/GO_WITH_BACKLOG/NO_GO` (строки того же журнала, kind=`judge`/`override`), fix-петлю с независимым re-review (`max_cycles` + honest stop), durable реестр отклонений `specs/<topic>/review-deviations.md` и preflight-гейт `/mb work`. Судья-человек/оркестратор остаётся **дефолтом** (D-30): при `spec_judge` off поведение S2-C5 byte-identical. Дублирует REQ-035 с S2 (spec-review опционален) — dual-ownership: конфиг/диспатч ревью — S2, автоматический судья/петля/гейт — S9.
6. **Interview-plan файл** (S1): `<bank>/tmp/interview-plan-<topic>.md` — темы ⬜/✅; финальный гейт и сверка перед генерацией (REQ-012/013).
7. **`/mb brief` C0** (S7): `/mb brief <topic> [--request <text> | --request-file <path>] [--input <path>]… [--auto]` — ровно один источник запроса; повторяемый `--input`; конфликт basename и нечитаемый файл — fail до создания каталога; выход — `briefs/<topic>/brief.md` + предложение `/mb discuss <topic>`.
8. **Delegate-контракт мета-задач** (этот umbrella): мета-задача с `**Delegate:** <child-topic>` закрывается только когда child-спека доведена до done через `/mb work <child-topic>`; её Eval — детерминированный гейт: `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/<child-topic> && [ "$(grep -c '^- \[ \]' .memory-bank/specs/<child-topic>/tasks.md)" -eq 0 ]` (red, пока есть незакрытые чекбоксы).

## Decisions

Все решения — в `context/sdd-vision-pipeline.md` § Decision Log (D-01…D-35); здесь не дублируются (D-01: пересечения принадлежат sdd-openspec-parity / quality-track). Ключевые для дизайна: D-05 (декларации на sdd, код на work), D-11 (fast-to-code bypass с записью trade-off, REQ-054), D-13 (бюджеты 120k/400k/1M), D-23 (банк пишет только оркестратор), D-26 (легаси-совместимость).

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Расползание парсера tasks.md v2 — легаси ломается | M | H | Contract-first: контрактные тесты парсера на легаси-фикстурах ДО изменений (REQ-039); negative parity tests как в adapter-parity |
| Параллель портит git-state (прецедент T3 adapter-parity) | M | H | S3 после S2 по DAG; Scope-дизъюнктность + orchestrator-only банк (D-23); mkdir-lock для claims (контракт 2); worktree-опция — решение внутри S3 |
| ICE-сортировка конфликтует с ручным порядком существующего роадмепа | M | M | pin-override (D-14); autosync не трогает контент вне fences |
| Слайс S2 сам превысит ~1M | M | M | Size gate в S2 design: спека draft, пока Stage-суммы ≤ 400k и общая оценка ≤ 900k (сейчас 850k — `svp-sdd-core/tasks.md` frontmatter `estimated_tokens.total`) |
| Модель spec-review недоступна в среде | L | M | паттерн codex-reviewer: health-check + SKIPPED loudly; судья-человек решает |
| Генерация без самопроверки повторит дефекты 2026-07-17 | M | H | батарея самопроверки: промпт-версия уже в `commands/sdd.md`, кодовая — S2 REQ-015/C8 |

## Open questions → маршрутизация в слайсы

- Порог циклов эскалации (verify/review/judge) → S5 (вход: телеметрия pivot-log).
- Параллель × review-ансамбль (сериализация judge) → S3.
- Эвристика оценки объёма темы в токенах на интервью → S1 (совместно с бюджет-валидатором S2).
- Формат реестра декомпозированных спек (`[SPEC:<group>]` в backlog) → S4 (переходный writer до S4 — S2-C4).
- ~~Механика claim~~ — закрыто ревизией 2: mkdir-lock, контракт 2.
- ~~Грамматика Scope~~ — закрыто ревизией 2: S2-C1.
