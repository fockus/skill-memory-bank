---
type: fix
topic: opus55-prompt-fit
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-24
---
# Plan: fix — opus55-prompt-fit · скил под Opus 5.5 / Fable 5.1 и любые агенты

**Baseline commit:** cfee2e0 (ветка `feat/opus55-prompt-fit`, worktree `~/Apps/skill-memory-bank-opus55`).
Незакоммиченная работа по embeddings в основном дереве не трогается.

## Context

**Problem.** Аудит 24.09 по `claude-api/shared/prompt-audit.md` и разделу «Migrating to Claude Opus 5.5»
плюс замер по 50 сессиям пользователя показали три класса дефектов:

1. Механика сломана тихо: хуки на запуск сабагентов ждут `Task`, а инструмент называется `Agent`
   (0 срабатываний на 571 запуск); echo-хуки `Setup` и `PreToolUse:Write` пишут в stdout, который
   модель не видит; `PreCompact` велит суммаризатору запустить агента на sonnet; подсказка графа
   троттлится по часу, а не по сессии (28 раз за сессию); recall срабатывает на `<task-notification>`.
2. Диспетчеризация: `/mb work`, `/mb`, `/test`, `/review`, `plan-verifier` зовут `general-purpose`
   и вклеивают тело агента в prompt (11–16 КБ выходных токенов оркестратора на вызов); frontmatter
   агентов (`model`, `tools`, `effort`) не работает; параметра `thinking` у Agent tool нет.
3. Текст: регистр давления («CRITICAL», «MUST», «never omit»), обязательная строка статуса в каждом
   ответе (маркер в 144 отчётах сабагентов и в выводе для скриптов), «Fail Fast — стоп и план»,
   обязательный формат «Goal → Action → Result», противоречивые копии SRP/DRY и четыре таблицы
   маршрутизации графа, зашитый `sonnet`, устаревшие числа.

**Decisions (пользователь, 24.09):**
- работа в отдельной ветке в worktree;
- строка `[MEMORY BANK: …]` — только первый ответ человеку, без чек-листа, без сабагентов и вывода для скриптов;
- SRP: превышение порога — WARNING; блок — только если этот дифф добавил ответственность / перевёл файл через порог;
- DRY — правило трёх; KISS/YAGNI — без абстракций «на будущее»; один канонический источник правил;
- язык ответов и язык комментариев настраиваются раздельно, глобально и по проекту;
- модель — только в `pipeline.yaml`; уровень рассуждений — `effort` во frontmatter агента;
- реализация без `/mb work`; `/mb work` проверяется реальным прогоном после выпуска.

**Constraints.**
- Правки только в исходниках скила; попадают к пользователям через `install.sh` / `mb-upgrade.sh`
  (блок CLAUDE.md пересобирается между маркерами, хуки заменяются по маркеру `[memory-bank-skill]`).
  Установленные файлы в `~/.claude` руками не трогаем.
- Кросс-агентность: Codex, Cursor, OpenCode, Windsurf, Cline, Kilo, pi получают тот же
  `rules/CLAUDE-GLOBAL.md`; всё, что специфично для Claude Code (matcher `Agent`, `effort` во
  frontmatter), живёт в Claude-адаптере; общие понятия (`effort` в pipeline) каждый адаптер мапит сам.
- Обратная совместимость: ключ `thinking` в `pipeline.yaml` не меняется;
  старые имена агентов при консолидации остаются псевдонимами минимум на один минорный релиз.
- Версия выпуска согласуется отдельно: AGR-009 резервирует 5.4.0 под Baseline донорской программы.

**Expected result.** Батарея зелёная (baseline фиксируется до правок), обновление с 5.3.1 во
временном `HOME` для каждого клиента идемпотентно, метрики после выпуска: маркер статуса в отчётах
сабагентов → 0; выходные токены оркестратора на вызов исполнителя −3K+; подсказка графа ≤1 раз за сессию;
recall не срабатывает на служебные уведомления.

## Stages

<!-- mb-stage:1 -->
### Stage 1: механика хуков

- `settings/hooks.json`: matcher `Task` → `Task|Agent`; удалить `Setup` и `PreToolUse:Write` echo;
  `PreCompact` echo → инструкция суммаризатору «что сохранить, без вызова тулов, без модели».
- `hooks/mb-context-slim-pre-agent.sh`, `hooks/mb-sprint-context-guard.sh`: принимать `tool_name`
  `Task` и `Agent`.
- `hooks/mb-graph-nudge.sh`: ключ троттлинга — `.session_id` из stdin, фолбэк — дата (сутки).
- `hooks/mb-semantic-recall.sh`: пропускать промпты, начинающиеся с `<task-notification>`,
  `<system-reminder>`, `<local-command`, `[SYSTEM NOTIFICATION`.
- `scripts/mb-freshness.sh`: баннер без императива `--force`, без относительного `scripts/`.
- `settings/merge-hooks.py`: legacy-список сохраняет `PRE-WRITE`/`[COMPACTION]`/Setup, чтобы
  апгрейд удалил старые записи; `references/hooks.md`, `docs/hooks.md` синхронизировать.

**DoD:**
- [x] тест: хук context-slim и sprint-guard реагируют на `tool_name: "Agent"` (красный до правки);
- [x] тест: merge поверх settings от 5.3.1 удаляет Setup/PRE-WRITE/старый COMPACTION и не дублирует записи;
- [x] тест: graph-nudge с одинаковым `session_id` во входе печатает подсказку один раз за сессию при смене часа;
- [x] тест: recall на `<task-notification>…` возвращает `{}` без запуска python;
- [x] тест: баннер freshness не содержит `--force`;
- [x] батарея без новых падений относительно baseline (pytest 2945/0; bats 3443 ok против 3406 в baseline; два теста NFR-001 в `test_extensions_offer.bats` сравнивают с `HEAD:install.sh` и зазеленеют после коммита; `test_mb_update_notify` #31 — тайминг под нагрузкой, в одиночку 3/3 зелёный).

<!-- mb-stage:2 -->
### Stage 2: диспетчеризация сабагентов и тексты исполнителя/проверяющих

- `commands/work.md`, `commands/mb.md`, `commands/test.md`, `commands/review.md`,
  `agents/plan-verifier.md`, `SKILL.md`: вызов по имени (`subagent_type="<agent>"`), в prompt только
  данные пункта; не перепечатывать файлы агентов; убрать параметр `thinking` из вызова.
- Полнота системного промпта агента при вызове по имени: role-агенты при установке собираются как
  `engineering-core + tooling-core + role` (или читают partials сами — выбрать по тому, как это уже
  делают адаптеры OpenCode/pi; не держать два механизма).
- `pipeline.yaml` сохраняет ключ `thinking` (переименование сломало бы пользовательские pipeline и ~95 тестов
  без выигрыша): Claude Code берёт глубину из `effort:` frontmatter агента, адаптеры — из своих настроек.
- `agents/*.md`: убрать `model: sonnet`; добавить `effort:` (manager, wiki-author — low;
  implementers — medium; verifier, judge — high).
- `agents/mb-engineering-core.md`: не читать глобальный `RULES.md` целиком; добавить раздел
  «Scope — the item is the deliverable»; убрать «Scope is small, no plan needed → not an exemption».
- `agents/plan-verifier.md`, `agents/mb-reviewer.md`: заменить «adversarial default», «better to flag
  an extra issue», «default CHANGES_REQUESTED», «do not stop short» на стандарт доказательности
  (file:line + сценарий поломки; блок — корректность, безопасность, DoD; стиль — minor).
- `agents/mb-research.md`: добавить WebSearch/WebFetch в tools, описание без перечисления триггеров.
- `commands/*.md`: голые `bash scripts/…` → `"$SKILL_DIR/scripts/…"`.

**DoD:**
- [x] тест: ни одна команда/агент не содержит `subagent_type="general-purpose"` с вклеенным телом агента и `thinking=`;
- [x] тест: у всех агентов нет `model: sonnet|haiku`, у всех есть валидный `effort`;
- [x] ~~pipeline `thinking` → `effort`~~ — отменено, см. выше;
- [x] тест: в командах нет `bash scripts/` без `$SKILL_DIR`;
- [x] тест: установленный role-агент содержит core и tooling (или явный шаг чтения partials);
- [x] установка в temp HOME для opencode и pi не ломает их маппинг агентов (5.3.1 → ветка → повтор, 5 клиентов: хуки без дублей, md5 глобальных файлов стабильны, бэкапов не добавилось; pi-роли с `thinking` и pi-тулами, OpenCode global с ядром и `edit: deny`, Codex 27 TOML-ролей).

<!-- mb-stage:3 -->
### Stage 3: постоянно загруженный текст

- `rules/CLAUDE-GLOBAL.md`: строка статуса — только первый ответ человеку, без чек-листа;
  заголовок «Engineering rules»; Fail Fast — «уточнять, только если разные прочтения ведут к
  существенно разной работе; иначе решить и назвать допущение»; «multi-file → plan first» →
  «многоэтапная работа → план `/mb plan`»; удалить «Goal → Action → Result»; убрать «25 commands»,
  «Subagents (sonnet)», несуществующие `planner`/`codebase-research`/`graphify`; абзац маршрутизации
  без противоречия про ревью.
- `rules/RULES.md`: те же правки, дубли строки статуса → ссылка; регистр давления
  («violation means failure», «hard requirement», «no exceptions») → обычный тон с причиной.
- `hooks/mb-session-start.sh`: шпаргалка без `graphify`, «CHEAP» → обычный тон.
- `hooks/mb-session-end.sh`, `hooks/mb-session-summarize.sh`: обходы вырезания маркера оставить
  (старые установки), но пометить как совместимость.
- Репо `CLAUDE.md` / `AGENTS.md`: правило о `thinking` → `effort`, строка статуса — как в шаблоне.

**DoD:**
- [x] обновлены `test_global_prompt_guard.py`, `test_doc_counts.py`, `test_graph_rag_guidance.py` — проверяют новые формулировки;
- [x] тест: в `CLAUDE-GLOBAL.md` нет `MUST`/`CRITICAL`/`Never omit` в поведенческих правилах;
- [x] тест: шаблон рендерится для всех клиентов (claude, codex, pi, cursor, windsurf, cline, kilo, opencode) без потерь маркеров.

<!-- mb-stage:4 -->
### Stage 4: один источник правил SOLID/DRY/KISS и маршрутизации графа

- `rules/RULES.md` — канон: SRP (порог 300 строк / >3 публичных методов разной природы → WARNING;
  блок — дифф перевёл файл через порог или добавил ответственность), DRY (логика в 3+ местах →
  вынести; три одинаковые строки лучше преждевременной абстракции), KISS/YAGNI, ISP ≤5.
- `agents/mb-engineering-core.md`, `agents/mb-reviewer.md`, `agents/plan-verifier.md`,
  `agents/mb-rules-enforcer.md`: ссылаться на канон, не пересказывать пороги иначе.
- `scripts/mb_rules_check_baseline.sh` (+ связанные): SRP CRITICAL только при переходе через порог
  в этом диффе; уже превышенный порог — WARNING.
- Маршрутизация графа: одна таблица в `agents/mb-tooling-core.md`; удалить копии в role-агентах,
  `mb-research.md`, `mb-codebase-mapper.md`; `rm -rf .cache && mb-codegraph.py --apply` →
  `mb-graph-query.py catchup`.

**DoD:**
- [x] тест: файл уже >300 строк, дифф его не увеличил через порог → WARNING, ревью не блокируется;
- [x] тест: файл был 280, стал 320 в диффе → CRITICAL;
- [x] тест: формулировки SRP/DRY в агентах совпадают с каноном (или ссылаются на него);
- [x] тест: таблица маршрутизации графа встречается ровно в одном файле.

<!-- mb-stage:5 -->
### Stage 5: язык ответов и комментариев — глобально и по проекту

- `install.sh` / `mb-upgrade.sh`: опция `--comments-language` (по умолчанию = `--language`),
  сохраняется в manifest; рендер правила разделяет язык ответов и комментариев.
- Проектный уровень: `/mb language <xx> [--comments <yy>] | off | show` (`scripts/mb-language.py`) пишет
  управляемый блок `<!-- mb-language:start -->…<!-- mb-language:end -->` в начало проектных `AGENTS.md`
  и `CLAUDE.md` — источник правды сам блок, без отдельного профиля: rules-profile требует банк и схему,
  а блок читают все агенты нативно (Codex/OpenCode/pi — AGENTS.md, Claude Code — CLAUDE.md); в начале
  файла он не обрезается лимитом Codex 32 KiB.

**DoD:**
- [x] тест: `--language ru --comments-language en` рендерит «respond in Russian», «code comments in English»;
- [x] тест: без `--comments-language` поведение как в 5.3.1;
- [x] тест: `mb-language.py set` создаёт/обновляет блок в начале AGENTS.md и CLAUDE.md, повторный вызов не дублирует, symlink CLAUDE.md→AGENTS.md получает один блок, `off` возвращает исходный текст (`tests/pytest/test_mb_language.py`);
- [x] тест: апгрейд сохраняет выбранные языки из manifest.
- [x] es, pt, zh — полные строки правила и переведённые шаблоны банка (по решению пользователя 24.09).

<!-- mb-stage:6 -->
### Stage 6: объём и детерминированная работа

- `commands/mb.md`: оставить маршрутизацию и setup; разделы `### <sub>` → `references/mb/<sub>.md`,
  чтение по требованию; `/mb help` продолжает работать.
- `SKILL.md`: таблицы скриптов, хуков и раздел Cursor/Codex → `references/`, в SKILL.md ссылка.
- `/mb tasks`, `/mb context` — скрипт в основной сессии, без сабагента.
- `/mb done`: шаги prune/core-cap/auto-commit/хеш-цепочка → `scripts/mb-done-finalize.sh`;
  модель — только actualize и заметка.
- `mb-test-runner`, `mb-rules-enforcer`: вызывающие стороны зовут скрипты напрямую; агенты остаются
  тонкими обёртками на скрипт (совместимость) с пометкой deprecated.

**DoD:**
- [ ] тест: `/mb help <sub>` находит каждый раздел после выноса;
- [ ] тест: `mb-done-finalize.sh` повторяет шаги 3–9 и хеш-цепочку, mb-drift без CRITICAL после него;
- [ ] размер `commands/mb.md` ≤ 4K токенов (оценка), `SKILL.md` ≤ 9K.

<!-- mb-stage:7 -->
### Stage 7: состав агентов (отдельный релиз)

- `mb-implementer` (engineering-core + tooling-core + `Role:` + `references/roles/<role>.md`)
  вместо developer/backend/frontend/ios/android/devops/qa/analyst; `mb-architect` остаётся.
- `mb-reviewer` с `focus` вместо reviewer + 5 аспектных; `mb-reviewer-lead` → дедуп в скрипте.
- `mb-research` вбирает `mb-researcher`.
- Старые имена — псевдонимы (агент-файл-переадресация и маппинг в резолвере `pipeline.yaml`).

**DoD:**
- [ ] тест: pipeline со старыми именами резолвится в новые с предупреждением;
- [ ] тест: адаптеры opencode/pi/codex устанавливают новый состав и псевдонимы;
- [ ] grep по старым именам в `install.sh`, `pipeline.default.yaml`, `mb-agent-caps.sh`, тестах — согласован.

<!-- mb-stage:8 -->
### Stage 8: выпуск и проверка

- Полная батарея pytest + bats + e2e; сравнение с baseline.
- Апгрейд с 5.3.1 → новая версия во временном `HOME` для каждого клиента: блок CLAUDE.md заменён,
  хуки без дублей, бэкапы есть, повторная установка идемпотентна.
- `CHANGELOG.md`, версия **5.3.2** (решение пользователя 24.09: 5.4.0 остаётся за Baseline по AGR-009); `VERSION` и url+sha256 Homebrew-формулы меняются в релизном коммите после публикации sdist на PyPI, как в релизе 5.3.1; `README`/docs.
- Локальная установка с `--language ru` (и выбранным языком комментариев).
- Реальный прогон одного пункта `/mb work` на Fable; замер метрик из Context.
- Коммит/PR/push — только после просмотра диффа пользователем.

## Risks

- Тесты, проверяющие формулировки, падают массово → правим тесты вместе с текстом, одна находка — один коммит.
- Вызов агентов по имени в других клиентах работает иначе → Stage 2 проверяет установку opencode/pi до мёржа.
- Слияние с незакрытой веткой embeddings (`commands/mb.md`, `CHANGELOG.md`) → Stage 6 выполнять
  последним и ребейзить на актуальный main перед мёржем.
