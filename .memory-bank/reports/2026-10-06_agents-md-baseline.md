# agents-md-diet — baseline размеров always-loaded файлов

План: `plans/2026-10-06_fix_agents-md-diet.md` (Stage 1–2). Гейт: `tests/bats/test_always_loaded_budget.bats`.

**Метод.** Копия репо → `install.sh --clients claude-code,cursor,windsurf,cline,kilo,opencode,pi,codex
--non-interactive` в temp HOME + temp git-проект (`MB_SKIP_DEPS_CHECK=1`), Key rules на дефолтах (пустой профиль).
Байты — `wc -c`. «MB-блок» — между `<!-- memory-bank:start/end -->`.

## Цифры (байты)

| Файл | HEAD e351a17 | Рабочее дерево до Stage 2 | После Stage 2 | Лимит |
|------|-------------:|--------------------------:|--------------:|------:|
| проектный `AGENTS.md` (codex/pi/opencode), весь | 50 751 | 53 933 (Key rules нет) | 4 092 (Key rules 3 012 + MB 1 079) | 4 096 |
| `_agents_md_section` (худший случай: nudge, путь репо) | — | 53 933 | 4 062 | 4 096 |
| `~/.codex/AGENTS.md` | 15 212 | 9 590 | — (Stage 3) | 8 192 |
| `~/.pi/agent/AGENTS.md` | 14 883 | 9 255 | — (Stage 3) | 8 192 |
| `~/.config/opencode/AGENTS.md` | 12 844 | 7 202 | — (Stage 3) | 8 192 |
| `~/.cursor/AGENTS.md` | 13 192 | 7 668 | — (Stage 3) | 8 192 |
| `~/.claude/CLAUDE.md` (справочно) | 12 242 | 6 668 | — | — |
| `.cursor/rules/memory-bank.mdc` | 47 377 | 50 559 | — (Stage 4) | 4 096 |
| `.windsurf/rules/memory-bank.md` | 47 231 | 50 413 | — (Stage 4) | 4 096 |
| `.clinerules/memory-bank.md` | 47 275 | 50 457 | — (Stage 4) | 4 096 |
| `.kilocode/rules/memory-bank.md` | 47 260 | 50 442 | — (Stage 4) | 4 096 |

Рост рабочего дерева против HEAD у проектных/правил-файлов — правки `rules/RULES.md` параллельными сессиями;
глобальные уже частично ужаты другой сессией (Key rules добавлены, шапки укорочены).

## RED → GREEN гейта

- До Stage 2: 6 из 6 проектных тестов красные (53 933 > 4 096; есть `## Source of Truth` и др.; первая строка не
  `mb-key-rules:start`; порядок блоков неверный; нет указателя на `.memory-bank/RULES.md`; нет абсолютного пути к
  `rules/RULES.md`). Глобальные / rule-файлы помечены `skip` (Stage 3/4); их тела, прогнанные без skip, падают на
  размере: `~/.codex/AGENTS.md` 9 590 > 8 192, `.mdc` 50 559 > 4 096.
- После Stage 2: 6 проектных зелёные, 2 skip.

## Запас

Проектный блок упирается в лимит: Key rules ≈ 3 КБ на дефолтах, MB-блок ≈ 1 КБ; запас 34 байта на пути репо,
21 байт на пути `~/.config/opencode/skills/memory-bank`, 4 байта при установке из длинного temp-пути. Любое новое правило в дефолтах `rules/key-rules.json` или
длинный HOME валит гейт.

## Раздельный бюджет и Stage 4 (2026-10-07)

Решение владельца плана: Key rules ≤ 3 072 B, MB-блок ≤ 1 536 B, проектный блок и rule-файлы хостов ≤ 4 608 B,
глобальные ≤ 8 192 B; путь скила в гейте нормализуется в `/SKILL` (длинный HOME не валит гейт). Запас из раздела
выше больше не критичен. MB-блок получил строку `- Language: <правило>` (язык раньше шёл только из копии RULES.md)
и раскрытые формулировки.

| Файл | До Stage 4 | После (сырой temp-путь) | После (нормализовано) | Лимит |
|------|-----------:|------------------------:|----------------------:|------:|
| проектный `AGENTS.md` | 4 092 | 4 472 (Key rules 3 012 + MB 1 459) | 4 346 (MB 1 333) | 4 608 |
| `.cursor/rules/memory-bank.mdc` | 50 786 | 4 500 | 4 374 | 4 608 |
| `.windsurf/rules/memory-bank.md` | 50 640 | 4 420 | 4 294 | 4 608 |
| `.clinerules/memory-bank.md` | 50 684 | 4 417 | 4 291 | 4 608 |
| `.kilocode/rules/memory-bank.md` | 50 669 | 4 392 | 4 266 | 4 608 |

Гейт: 7 ok, 1 skip (глобальные — Stage 3). Тест rule-файлов до Stage 4 был красным (50 559 > 4 096).

## Stage 5 — переустановка и замер (2026-10-07)

**Метод.** Как в baseline: копия рабочего дерева → `install.sh --clients claude-code,cursor,windsurf,cline,kilo,opencode,pi,codex
--non-interactive --project-root <temp-проект>` в temp HOME (`MB_SKIP_DEPS_CHECK=1`, XDG_* внутри temp HOME), дважды.
Отдельно — проектные адаптеры `adapters/{codex,pi,opencode,cursor,windsurf,cline,kilo}.sh install` в другом temp-проекте,
дважды. Байты — `wc -c`, путь temp HOME сырой (не нормализован).

| Файл | HEAD e351a17 | После (Stage 5) | Лимит |
|------|-------------:|----------------:|------:|
| `~/.claude/CLAUDE.md` (справочно) | 12 242 | 6 828 | — |
| `~/.codex/AGENTS.md` | 15 212 | 7 463 | 8 192 |
| `~/.pi/agent/AGENTS.md` | 14 883 | 7 895 | 8 192 |
| `~/.config/opencode/AGENTS.md` | 12 844 | 7 307 | 8 192 |
| `~/.cursor/AGENTS.md` | 13 192 | 7 289 | 8 192 |
| проектный `AGENTS.md` (codex/pi/opencode) | 50 751 | 4 297 | 4 608 |
| `.cursor/rules/memory-bank.mdc` | 47 377 | 1 444 (Key rules уже в AGENTS.md) | 4 608 |
| `.windsurf/rules/memory-bank.md` | 47 231 | 4 245 | 4 608 |
| `.clinerules/memory-bank.md` | 47 275 | 4 242 | 4 608 |
| `.kilocode/rules/memory-bank.md` | 47 260 | 4 217 | 4 608 |
| `AGENTS.md` этого репо (с соглашениями и языком; файл в .gitignore) | ≈80 000 (замер Sprint 2) | 7 987 | 12 288 |
| `CLAUDE.md` этого репо | 29 609 (109 строк) | 8 352 (82 строки) | 10 240 / 200 строк |

Прямой прогон адаптеров дал те же размеры проектных файлов, что и `install.sh`.

**Идемпотентность.** Второй `install.sh` байт-в-байт совпал с первым по всем 394 файлам temp HOME и temp-проекта
(`diff -r`). Отличаются только `.mb-manifest.json` / `.mb-pi-manifest.json` (`installed_at` и список `backups`).
Второй прогон один раз сохраняет `*.pre-mb-backup.*` для уже установленных файлов OpenCode (commands, agent,
plugin), Cursor `.mdc`, Windsurf и Cline hooks. Третий прогон новых копий не создаёт, манифесты 2 и 3 совпадают без
`installed_at`. Прямые адаптеры дважды: 87 файлов совпали, те же разовые backup-копии. Управляемые файлы
(`CLAUDE.md`, все `AGENTS.md`, rule-файлы) совпадают байт-в-байт.

**Лимит Codex.** `project_doc_max_bytes = 32768` по умолчанию: `codex-rs/config/defaults.toml`
(https://github.com/openai/codex/blob/main/codex-rs/config/defaults.toml) и документация
(https://developers.openai.com/codex/guides/agents-md, «32 KiB by default»). Override 65 536 в `adapters/codex.sh`
оставлен. Он больше не нужен: проектный `AGENTS.md` занимает 4 297 Б, `AGENTS.md` репо — 7 987 Б.
Даже если Codex считает глобальный файл в том же лимите (документация говорит о «combined size» цепочки), выходит
7 463 + 7 987 = 15 450 Б ≤ 32 768. Гард: `tests/pytest/test_repo_instruction_budget.py`.

**Репо.** `adapters/opencode.sh install <repo>` (temp HOME; plain install ничего не пишет в HOME) оставил `AGENTS.md`
без изменений — 7 987 Б, блоки key-rules / memory-bank / agreements. Пользовательского текста вне маркеров нет,
`.mb-agents-owners.json` не изменился.

## I-249 — запас глобальных файлов (2026-10-07)

План `2026-10-07_fix_upgrade-safe-install.md`, Stage 3. `rules/CLAUDE-GLOBAL.md`: 31 строка / 3 868 Б → 25 строк / 2 640 Б.
Замер — `install.sh --non-interactive --clients claude-code,codex,pi,opencode,cursor` в пустой temp HOME, `wc -c`.

| Файл | До | После | Запас до 8 192 |
|---|---|---|---|
| `~/.claude/CLAUDE.md` | 6 828 | 5 600 | 2 592 |
| `~/.codex/AGENTS.md` | 7 463 | 6 235 | 1 957 |
| `~/.pi/agent/AGENTS.md` | 7 895 | 6 667 | 1 525 |
| `~/.config/opencode/AGENTS.md` | 7 307 | 6 079 | 2 113 |
| `~/.cursor/AGENTS.md` | 7 289 | 6 061 | 2 131 |

**Что убрано** (всё есть в Key rules, `rules/RULES.md` или `references/`):
- Заголовок `## Coding & Reasoning`; «Specification by Example», «Strangler Fig» — есть в RULES.md (§ Tests — Testing Trophy, § Coding Standards).
  От ADR-строки осталось «significant decision → ADR».
- Длинная строка про размер задачи: дублировала Key rules «Size the task first…». Осталась короткая: нет плана для
  trivial/small, SMART DoD на план, coverage по профилю, ссылка на § Task routing.
- `**Skill:** / **Command:** / **Path:**`, `/mb context --deep` — путь и флаг есть в SKILL.md и RULES.md.
- «procedures and opt-in layers live in the skill» в строке про граф.
- Из координации: перечень того, что показывает `mb-coord.sh active`, и «scoped `git add` only (never `-A`)» — первое есть
  в `references/coordination.md`, второе в Key rules.
- Из соглашений: «never leave two active», «Kill-switch `MB_AGREEMENTS=off`» — есть в `references/agreements.md`.
- В строке статуса: пути `registry.json` и `<project>/` (резолвер и `--storage=global` остались).
- Отдельная строка «Project-specific overrides…» слита со строкой «Details: `~/.claude/RULES.md`».
- Выделение `**…**` и «never/immediately» заменены спокойными формулировками (AGR-068).

Гард: `tests/pytest/test_global_prompt_guard.py::test_global_host_files_keep_one_kb_headroom` — самый большой
глобальный файл ≤ 8 192 − 1 024 Б. Существующие гарды смысла не менялись, все зелёные.
