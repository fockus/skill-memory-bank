# Аудит: почему `/mb work` медленный и дорогой — и какие гэпы у скила

Дата: 2026-09-05. Автор: Claude (Opus 5), по запросу пользователя.

## 1. Что и как смотрел

**Скил:** `commands/work.md` (44 KB), `commands/mb.md` (97 KB), `references/work-reference.md`, `.memory-bank/pipeline.yaml`, `agents/*` (29 файлов, 162 KB), `hooks/*` (29), `scripts/mb-context.sh`, `mb-review*.sh`, `mb-checklist-prune.sh`, `settings/merge-hooks.py`, `install.sh`; `lessons.md`, `backlog.md` (I-131, I-158, I-102 …), `notes/` за июль, `status.md`.

**Транскрипты Claude Code** (`~/.claude/projects/*`): 53 сессии и 587 сабагентов за ~2 месяца в 5 проектах — harness (35 сессий, 470 MB), jeeves-go (11, 435 MB), techflow (6, 122 MB), code-agent, skill-memory-bank. Три скрипта-анализатора: `/tmp/mb_analyze*.py` (кандидаты в `scripts/mb-cost-report.py`).

**Банки:** 6 штук (skill-memory-bank, techflow, code-agent, harness/src, jeeves-go global, my_vpn) — размеры core-файлов и вывод `mb-context.sh`.

Хуки замерены по времени (PreToolUse-цепочка ~360 ms на вызов Bash, Stop-гейт 0.1 s после I-131) — **хуки не являются источником тормозов.**

## 2. Ключевые цифры

| Метрика | Значение |
|---|---|
| Сессий / сабагентов | 53 / 587 |
| Output-токены: main / сабагенты | 54 M / 37 M |
| Cache-write: main / сабагенты | 237 M / **493 M** |
| Cache-read: main / сабагенты | 7.2 B / **13.6 B** (≈23 M на сабагента) |
| Компакций в длинных сессиях | 112 (до 21 на сессию; сессии по 100–500 ч) |
| Пик контекста main-сессии | 450–610 k |
| **Implementer-сабагент (avg, n=45)** | 243 хода · 87 Bash · 35 Edit · **15.6 прогонов тестов** (48 s каждый) · 299 KB tool-результатов · пик контекста 260 k · **35–108 мин** |
| Verifier (n=55) | 181 ход · **12.6 прогонов тестов** · 3.8 sleep-poll (6.7 мин ожидания) |
| Reviewer (n=257, вкл. PR-ревью) | 142 хода · 6.5 прогонов тестов |
| Judge (n=4–7) | 68–76 ходов · 14 мин |
| **Governed-item (harness, замер по `init → flip`)** | **123–148 мин · 10–12 Task-диспатчей · 170–193 k output-токенов только у оркестратора** |
| Промпт сабагента | медиана 4.4 KB, p90 7.3 KB; engineering-core вложен лишь в 39 из 554 |
| Модель сабагентов | opus 349 · (не задана) 147 · fable 40 · sonnet 17 |
| Items, закрытых через `mb-work-checkbox.sh flip` | **19** на три проекта |
| `mb-context.sh` при `/mb start` | skill-memory-bank 112 KB (~28 k ток.) · code-agent 165 KB · **techflow 337 KB (~84 k ток.)** |
| Bash grep/cat в сабагентах | 15.5 k + 12 k вызовов (harness+jeeves) против 43 `mb-graph-query` |

Экономика: cache-read — крупнейшая статья (20 B токенов). Стоимость ≈ **ходы × размер контекста**. Рычаг — не «модель дешевле», а **меньше ходов и меньше контекста на ход**.

## 3. Находки (по вкладу в время/токены)

### F1. Сабагент живёт 150–250 ходов, потому что всё узнаёт сам
Промпт 4 KB → агент сам ищет файлы, читает по 300 KB результатов, гоняет тесты 15 раз. `--slim`/context-pack обещаны в `work.md` («Phase 4 will add»), хук `mb-context-slim-pre-agent.sh` есть, но advisory и никем не вызывается. Нет бюджета ходов/инструментов на сабагента. Роутинг в граф добавлен в промпты (2026-07-15), но адопшн <1 % (AGR-038).

### F2. Governed-цикл — дефолт этого репо, и он тяжёлый по построению
`pipeline.yaml`: `default: codex-governed`, все роли на Opus, reviewer `gpt-5.6-sol xhigh`, `max_cycles: 2`. Один item = implement + verify + review + judge, и на каждом NO_GO — снова verify + review + judge (+fix). Судья NO_GO в 12 из 25 записей `progress.md` → фикс-циклы норма. В `work.md` на item приходится **28 обязательных вызовов скриптов** (state/eval-red/quality-dod/contract-gate ×2 dispatch/rules-check/payload/preflight/parse/cycle/done/flip/catchup/budget…). `mb-work-adapt.sh` упомянут в `work.md`, **но файла нет**.

### F3. Тесты гоняются ~35 раз на item
implementer 15.6 + verifier 12.6 + reviewer 6.5 (+ eval-green + judge). Кэш test-evidence (`mb-review-cache.sh`, TTL 600 s) используется только при сборке review-payload. В Arcadia `ya make -tt` упирается в 10-минутный таймаут инструмента — самые долгие Bash-вызовы в транскриптах.

### F4. Ожидание оплачивается токенами
Оркестратор ждёт внешние ревью циклами `for i in …; do sleep 30; lsof OUT.md …` (5–10 мин на вызов, десятки вызовов); есть сабагент-«бебиситтер pi» (4 запуска) — целый агент ради `sleep`. Причина: у скила нет штатного раннера долгого внешнего ревью; pi/codex запускаются через `nohup … & disown` + polling (гочи описаны в memory-нотах пользователя, а не решены инструментом).

### F5. Контекст на старте и «вечные» core-файлы
`mb-context.sh` печатает `status/roadmap/checklist/research` **целиком, без лимита**. Core-файлы только растут: techflow — progress 768 KB, status 121 KB, checklist 173 KB (596 строк при hard-cap 120; `mb-checklist-prune.sh --dry-run` → «No collapse candidates», т.е. прунер не распознаёт структуру). Для `status.md` ротации нет вообще. `COORDINATION.md` этого репо — 204 KB (~50 k ток.), а engineering-core §11 велит каждому сабагенту его читать (50 явных Read в транскриптах). Блок `## Active Agreements` в `CLAUDE.md` — 19 KB (36 AGR), попадает в каждую сессию и каждого сабагента.

### F6. Вес инструкций
`commands/mb.md` 97 KB — вход для **любого** `/mb`-подкоманды; `work.md` 44 KB + `work-reference.md` 19 KB; `~/.claude/CLAUDE.md` 13 KB + проектный `CLAUDE.md` 23 KB + `RULES.md` 47 KB. До первого полезного действия — порядка 25–40 k токенов инструкций.

### F7. Движок в основном обходят
19 items через `flip` на три проекта; в harness-банке **нет `pipeline.yaml`**; оркестратор пишет промпты руками («Ты — Opus-исполнитель в оркестрации /mb work…», «Opus-верификатор…»), 349/554 диспатчей на Opus, `mb-work-*` скрипты вызваны 8–79 раз на проект. То есть «медленно и дорого» — это на 80 % ручная governed-оркестрация *в стиле* `/mb work`, к которой подталкивают мандатный гейт в `CLAUDE.md` («implement/fix/continue → /mb work») и memory-заметка «только через /mb work, сабагенты на Opus». Дешёвый путь (`execution`, bundled default) существует, но не является очевидным выбором.

### F8. Обратная крайность — всё инлайн
techflow `8f08bc9f`: 6 795 ходов main-сессии, 9.2 M output-токенов, 16 компакций, 23 Task — оркестратор сам кодил. Без размера задачи оба режима (тяжёлый цикл и «всё сам») стоят дорого.

### F9. Гигиена
- `merge-hooks.py` при переустановке удаляет **все** managed-хуки и добавляет заново → выключенный пользователем хук (I-158) молча возвращается. Персистентного opt-out нет.
- `/mb done` всегда диспатчит MB Manager-сабагента; PreCompact-echo просит запускать MB Manager при каждой компакции (97 компакций).
- `.session-spend.json` не был в `.gitignore` (исправлено сегодня); сам счётчик считает только длины Task-промптов — реальной стоимости не видит.

## 4. Что предлагаю (сначала конфиг, потом код)

| # | Мера | Эффект | Цена |
|---|---|---|---|
| A | **Fast lane без кода:** в `pipeline.yaml` этого репо `default: execution`; governed — opt-in (`--workflow codex-governed`) для рискованных задач; implement на Sonnet (пресет уже зафиксирован нотой 2026-07-06), reviewer `thinking: high` для S/M | ×3–5 по времени и токенам на item | 0 кода |
| B | **Size-triage → auto-workflow:** `mb-work-adapt.sh` (уже упомянут в `work.md`) на базе `mb-estimate-lib.sh`: S (≤2 файла) → single-agent implement+tests, M → execution, L → governed. Флаг `--fast` = force S | убирает 28-шаговую церемонию для мелочи | S |
| C | **Context pack для implementer** (обещанный `--slim`): оркестратор собирает `Files:` + `mb-graph-query neighbors/tests` + DoD ≤8 KB и вкладывает в промпт; бюджет «≤60 tool-вызовов, без обхода репо» | ходов 240 → ~80 | M |
| D | **Одна тест-улика на item:** `mb-test-run.sh` → JSON с sha touched-файлов; verifier/reviewer/judge читают улику, перегоняют только при расхождении sha (расширить `mb-review-cache.sh` на все роли) | 35 прогонов → 2–3 | S–M |
| E | **Раннер внешнего ревью** `mb-review-external.sh`: синхронно, heartbeat, таймаут, `run_in_background` + нотификация; запрет sleep-циклов и бебиситтеров в `work.md` | –5…20 мин ожидания на item | S |
| F | **Диета контекста:** `mb-context.sh` — лимиты (status: верхние N секций/30 дней; checklist: только открытые; roadmap: active-блок); ротация `status.md` в `progress.md`; починить прунер checklist под реальную структуру; `COORDINATION.md` — читать только активные FREEZE/HANDOVER через `mb-coord.sh active`; Agreements в `CLAUDE.md` — только активные последние N, остальное по ссылке | –20…80 k ток. на старт, –50 k на сабагента | S |
| G | **Диета инструкций:** `mb.md` → тонкий роутер ≤10 KB (тела команд уже в отдельных файлах); нормативный цикл `work.md` → `mb-work-next.sh`, печатающий следующий шаг (модель не держит 44 KB процедуры) | –15…25 k ток. на вызов | M |
| H | Переустановка уважает opt-out: `hooks.disabled` в `.mb-config`/`hooks.json` | доверие к настройкам | S |
| I | **`/mb cost`** — отчёт по транскриптам (готовые `/tmp/mb_analyze*.py` → `scripts/mb-cost-report.py`): стоимость per item/role; без этого улучшения не измерить | измеримость | S |

Порядок: **A → F → D → B/C → E → G → H → I**. A и F дают основной выигрыш за один день; B–D делают дешёвый путь путём по умолчанию, не отменяя governed там, где он нужен.

## 5. Что НЕ проблема
- Хуки: суммарно <0.5 s на вызов инструмента, инъекция ~0.3–0.6 KB; semantic-recall 180 ms/511 B.
- Stop-хуки: после I-131 гейт 0.1 s (I-158 закрыт по факту — хук в settings присутствует, но лёгкий).
- Скрипты `mb-work-*`: 2–6 s на вызов, ~8 мин на сессию.
