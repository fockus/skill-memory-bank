---
type: fix
topic: upgrade-safe-install
status: done
depends_on: []
parallel_safe: true
linked_specs: []
created: 2026-10-07
---
# Plan: fix — установка поверх старой версии + хвосты I-249…I-254

**Baseline commit:** 190251c15d3d721c9eaf723f7357b29e4e1b64e3

## Context

**Problem.** Релиз 5.4.0 не делаем (AGR-084): важные пользователи забирают `main` поверх уже стоящей старой версии
(git clone, pipx, brew). Сейчас:
- повторный `install.sh` без флагов сбрасывает язык/клиентов — их восстанавливает только `mb-upgrade.sh`;
- `pipx upgrade` не перезапускает `memory-bank install` → глобальные CLAUDE.md/AGENTS.md, агенты, роли Codex остаются старыми;
- проектные блоки (CLAUDE.md/AGENTS.md, ~51 КБ в старой версии) обновляются только в одной папке `project_root`;
  в остальных проектах пользователя они остаются старыми; проектная разница Key rules (AGR-083) устаревает после
  смены глобальных правил (I-251);
- переустановка делает `*.pre-mb-backup.*` копии файлов, которые скил сам поставил (I-250).
Плюс бэклог: I-249 (запас глобальных файлов), I-252 (механика архитектур кроме FSD), I-253 (живой `/mb init --full`),
I-254 (два старых красных теста).

**Expected result.** Установка из `main` поверх любой предыдущей версии даёт то же состояние, что чистая установка
той же версии (управляемые файлы байт-в-байт, без мусора от старой версии, пользовательский текст цел); устаревшие
проектные блоки в других проектах обнаруживаются при старте сессии; хвосты закрыты.

**Решение по умолчанию (принято за владельца, можно поменять):** устаревший проектный блок при старте сессии —
одна строка-подсказка с командой; тихая пересборка только по opt-in `MB_AUTO_REFRESH=on` (design contract: дефолты
не меняются без opt-in, пользовательские файлы не правятся молча).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Установка поверх старой версии (install.sh / upgrade)

**Files:** `install.sh`, `scripts/mb-upgrade.sh`, `scripts/_lib.sh`, `memory_bank_skill/cli.py`, `adapters/cursor.sh`,
`adapters/windsurf.sh`, `adapters/cline.sh`, `adapters/kilo.sh`, `adapters/opencode.sh`, `adapters/codex.sh`,
`adapters/pi.sh`, `uninstall.sh`, `docs/install.md`, `README.md`, тесты

**What to do:**
- Сохранённые опции установки (язык, язык комментариев, клиенты, project_root) восстанавливает сам `install.sh`
  при повторном запуске без флагов; явные флаги побеждают. `mb-upgrade.sh` использует тот же код (один источник).
- Миграция со старой версии: удаление файлов, которые старая версия ставила, а новая — нет (по манифесту старой
  установки); старые маркеры/толстые блоки заменяются; пользовательский текст вне маркеров не трогается.
- I-250: резервная копия делается только для файла, которого нет в манифесте прошлой установки (чужой файл);
  свой файл перезаписывается без копии.
- Команда обновления для pipx/pip/brew: `pipx upgrade memory-bank-skill && memory-bank install` (и в
  `mb_upgrade_command`, и в `memory-bank self-update`, и в docs).

**Testing (TDD):**
- bats «апгрейд»: в temp HOME + temp проект ставится версия `v5.3.1` (`git archive`), затем текущая → управляемые
  файлы равны чистой установке текущей версии (diff -r, кроме времени в манифестах); нет файлов, которых нет в
  чистой установке; пользовательский текст до/после блока цел; язык и клиенты из первой установки сохранены.
- повторная установка без флагов сохраняет `--language ru --clients claude-code,codex`; флаг перебивает.
- вторая установка не создаёт `*.pre-mb-backup.*`; чужой файл на месте управляемого — копия создаётся.

**DoD:**
- [x] тесты красные до, зелёные после; shellcheck чистый; реальный ~/ не трогается (temp HOME) — `tests/bats/test_install_upgrade_safe.bats` 7/7 (RED до кода: апгрейд v5.3.1, повтор без флагов сбрасывал en/claude-code, бэкапы своих файлов, осиротевший `mb-checklist-autoprune.sh`); апгрейд v5.3.1 → текущая = чистая установка после фикса пустых строк в `_lib_agents_md.sh`; `_mb_owned_unedited` вынесен в `adapters/_framework.sh`; OpenCode-подсказка свежести (тест в `test_opencode_adapter.bats`)

<!-- mb-stage:2 -->
### Stage 2: Свежесть проектных блоков (другие проекты + I-251)

**Files:** `adapters/_lib_agents_md.sh`, `scripts/mb-rules.sh`, `memory_bank_skill/key_rules.py`,
`hooks/mb-session-start.sh`, `tests/bats/test_always_loaded_budget.bats`, тесты

**What to do:**
- Штамп в маркере проектного блока: версия скила + отпечаток входов рендера (каталог, user-профиль для delta).
- При старте сессии (Claude Code и хуки других хостов, где есть session start) сверка штампа проектных CLAUDE.md /
  AGENTS.md / rule-файлов текущего проекта: устарел → одна строка с командой пересборки; `MB_AUTO_REFRESH=on` →
  пересборка сама. Без банка и без блоков — тишина. Быстро (без сети, ≤ 100 мс).
- Команда пересборки одного проекта (например `mb-rules.sh sync --scope=project` + проектный адаптер) — одна,
  её же печатает подсказка.

**Testing (TDD):** bats: старый блок без штампа → подсказка; смена user-правил → delta-блок помечен устаревшим;
свежий блок → тишина; `MB_AUTO_REFRESH=on` → пересобран, повтор байт-в-байт.

**DoD:**
- [x] тесты красные до, зелёные после; время хука в бюджете; без банка поведение прежнее
  — `tests/bats/test_project_blocks_freshness.bats`: до 7/8 красных (зелёный только «без банка — тишина»), после 8/8;
  проверка штампов ~16 мс вместе со стартом bash (бюджет 100 мс), весь хук ~51 мс; соседние bats 446 + e2e 79 +
  pytest 135 зелёные; живая установка (temp HOME, `--language ru`, 6 клиентов) → хук молчит, `sync` повторно байт-в-байт

<!-- mb-stage:3 -->
### Stage 3: I-249 — запас глобальных файлов

**Files:** `rules/CLAUDE-GLOBAL.md`, `tests/pytest/test_global_prompt_guard.py`

**What to do:** сократить `rules/CLAUDE-GLOBAL.md` без потери смысла (повторы с Key rules и с `references/`),
цель — у всех глобальных AGENTS.md (Codex, Pi, OpenCode, Cursor) ≥ 1 КБ запаса до 8192 Б.

**Testing:** гард «запас ≥ 1 КБ» для самого большого глобального файла; существующие гарды смысла зелёные.

**DoD:**
- [x] Pi ≤ 7168 Б; список убранных строк в отчёте; тесты зелёные — Pi 7 895 → 6 667 Б (запас 1 525), CLAUDE-GLOBAL 3 868 → 2 640 Б; список в `reports/2026-10-06_agents-md-baseline.md` § I-249; гард `test_global_host_files_keep_one_kb_headroom`; 350 pytest + bats agree-docs + budget global — зелёные

<!-- mb-stage:4 -->
### Stage 4: I-252 — механические проверки архитектур

**Files:** `scripts/mb-rules-check.sh`, `scripts/mb_rules_check_*.sh`, `references/rules-presets/architecture/*.json`,
тесты

**What to do:** для пресетов, у которых правило формулируется как направление импортов (modular-monolith — нет
импорта внутренностей чужого модуля; hexagonal — домен не импортирует адаптеры; и т.п.), добавить проверку по образцу
fsd; остальные пресеты явно помечены «guidance only» в json и в выводе проверки.

**Testing (TDD):** bats на каждый новый чек: нарушение ловится, корректный код чист, без выбранной архитектуры чек не
запускается.

**DoD:**
- [x] тесты красные до, зелёные после; без профиля вывод прежний байт-в-байт — `tests/bats/test_rules_check_arch.bats`: RED 6/19 (5 «нарушение ловится» + конвенция `mechanical`), GREEN 19/19; байт-в-байт — golden `tests/fixtures/rules-check-arch/no-profile.golden`, снят старым скриптом до правок, `cmp` зелёный. Чеки: modular-monolith, hexagonal, microservices, ddd, mobile-udf (`check` в json, `scripts/mb_rules_check_arch.sh`); event-driven — `"mechanical": false` (только guidance). Смежные bats (10 файлов, 158) и pytest (7 файлов, 94) зелёные; shellcheck чистый.

<!-- mb-stage:5 -->
### Stage 5: I-253 — живой `/mb init --full`; I-254 — старые красные

**Files:** `references/claude-md-template.md` (только при найденном баге), `tests/bats/test_pi_agents_dispatch.bats`,
`.memory-bank/reports/2026-10-06_sprint2-instructions.md`

**What to do:**
- живой headless-прогон `/mb init --full` в tmp-проекте (python + pytest), вывод — в отчёт; баги шаблона — фикс.
- I-254: две «пустые» проверки `! grep` в `test_pi_agents_dispatch.bats` → `refute_grep` (рабочая копия Pi-сессии,
  запись на доске); `venv-requirements.sh` уже в git (190251c).

**DoD:**
- [x] отчёт с реальным выводом; `test_bats_assertion_contract` и `test_session_memory_packaging` зелёные — живые прогоны `claude -p "/mb init --full"`: 1-й нашёл 3 бага шаблона (нет Key rules, глобальный RULES.md, путь `mb-coord.sh`), 2-й чистый (44 строки); отчёт — раздел I-253 в `reports/2026-10-06_sprint2-instructions.md`; I-254: `refute_grep` в `test_pi_agents_dispatch.bats`, `venv-requirements.sh` в git с 190251c

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Удаление «осиротевших» файлов старой версии заденет пользовательский файл | M | удаляется только то, что записано в манифесте старой установки и не изменено пользователем (хеш); иначе — копия |
| Хук старта сессии замедлит каждую сессию | M | только локальные файлы, без сети; бюджет времени в тесте |
| Параллельные агенты правят общие файлы | M | у каждого файла один владелец (поля Files); CHANGELOG — только в конце |

## Gate (plan success criterion)

Установка `main` поверх `v5.3.1` даёт тот же результат, что чистая установка, и сохраняет выбор пользователя;
устаревший проектный блок в любом проекте виден при старте сессии; I-249…I-254 закрыты; полный pytest/bats зелёные.
