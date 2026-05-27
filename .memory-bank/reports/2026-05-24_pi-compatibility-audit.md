# Аудит совместимости memory-bank × Pi Code

**Дата:** 2026-05-24
**Аудитор:** gsd-audit (automated + manual)
**Scope:** текущая реализация Pi-адаптера, планы в `roadmap.md`, спецификации `parallel-pipeline`, `goal-driven-autopilot`, `work-loop-v2`, `handoff-v2`

---

## Executive Summary

| Уровень | Количество |
|---------|-----------|
| 🔴 Блокер (реализация невозможна без изменения архитектуры Pi или спеки) | 2 |
| 🟠 Критический гэп (функционал работает, но существенно хуже, чем в Claude Code) | 3 |
| 🟡 Предупреждение (несоответствие документации и реализации, или "мертвый" код) | 4 |
| 🟢 Работает корректно | 7 |

**Вердикт:** Pi — поддерживаемый агент, но **не first-class citizen**. Параллельный pipeline (S5) в текущей спецификации **технически невозможен на Pi** без серьёзного переосмысления. Для Pi-адаптера нужен отдельный план ремедиации.

---

## 1. Что работает сейчас (🟢)

### 1.1 Глобальная установка skill
- `install.sh` создаёт symlink `~/.pi/agent/skills/memory-bank/` → canonical skill
- Pi discovery подхватывает `SKILL.md` и injects его в промпт агента
- **Тест:** `tests/bats/test_pi_adapter.bats` — 12/12 PASS

### 1.2 AGENTS.md — project-level fallback
- `adapters/pi.sh` в режиме `agents-md` (дефолт) создаёт `AGENTS.md` в проекте + git-hooks-fallback
- Совместимость с другими адаптерами (OpenCode, Codex) — `AGENTS.md` shared, ownership tracking через `.mb-agents-owners.json`
- **Тест:** coexistence test PASS

### 1.3 Prompt templates (slash-команды)
- Все 25 команд из `commands/` копируются в `~/.pi/agent/prompts/` как prompt templates
- Pi загружает их при старте (`/reload` для hot-reload)
- **Тест:** `test_pi_adapter.bats` не покрывает prompt resolution, но механизм простой

### 1.4 Global storage resolver
- Resolver поддерживает Pi global storage: `~/.pi/agent/memory-bank/projects/<id>/`
- `AGENTS.md` секция и `SKILL.md` (skill mode) упоминают resolver / global storage
- **Тест:** `test_pi_adapter.bats` "mentions global storage or resolver" — PASS

### 1.5 Git-hooks-fallback (agents-md mode)
- `post-commit` hook ставится при `agents-md` установке
- Обеспечивает SessionEnd auto-capture (placeholder в `progress.md`)
- **Тест:** `test_pi_adapter.bats` "creates AGENTS.md + git-hooks" — PASS

### 1.6 GraphRAG-lite extension (код существует, но не подключен)
- `adapters/pi_graph_rag_extension.ts` — TypeScript extension для Pi, регистрирует tools: `code_context`, `graph_neighbors`, `graph_impact`, `graph_tests`, `search_code`
- Использует `execFile` к Python CLI-скриптам (`mb-code-context.py`, `mb-graph-query.py`) — правильная архитектура (delegate to CLI)
- ⚠️ **НЕ установлен `install.sh` и `adapters/pi.sh`** — extension лежит мёртвым грузом (см. §3.3)

### 1.7 Dual-mode adapter
- `agents-md` (default) — для проектов без глобального skill
- `skill` (opt-in, `MB_PI_MODE=skill`) — нативный Pi skill
- **Тест:** оба режима покрыты bats

---

## 2. Блокеры (🔴)

### 🔴 B1: Pi НЕ имеет встроенного subagent API — parallel-pipeline S5 невозможен как специфицирован

**Где в спеке:** `specs/parallel-pipeline/design.md` §7, §10, план `2026-05-24_feature_parallel-pipeline.md` Stage 4

**Что написано:**
> "Pi: spawns native subagents" — `adapters/pi/dispatch.ts` reads dispatches.json, "Calls Pi native subagent spawn API in parallel"

**Реальность:**
- Pi **намеренно** не включает built-in subagents. Из README Pi: *"Pi ships with powerful defaults but skips features like sub agents and plan mode."*
- Pi extensions **могут** строить subagents через SDK (`AgentSession`), но это требует:
  1. Написания полноценного Pi extension (не skill!)
  2. Установки extension в `~/.pi/agent/extensions/`
  3. Использования RPC mode или SDK для spawn дополнительных сессий
- `adapters/pi/dispatch.ts` в текущей спецификации предполагает "нативный API", которого не существует. Это **фантастическая спецификация**, не grounded в реальности Pi.

**Влияние:** Весь S5 parallel-pipeline для Pi — **недостижим в текущем виде**. Нужно либо:
- (A) Исключить Pi из S5 scope и задокументировать "sequential fallback only"
- (B) Переписать spec: Pi adapter = sequential loop через extension + RPC spawn (аналог Codex/OpenCode), а не "native parallel"
- (C) Создать отдельный Pi extension package (отдельный проект), что выходит за рамки memory-bank skill

**Рекомендация:** Выбрать (B) — изменить capability matrix: Pi parallelism = "⚠️ sequential via extension (RPC spawn), parallel requires custom extension".

---

### 🔴 B2: Pi НЕ имеет hook API — 4 критических hook'а skill'а не работают

**Где в спеке:** `docs/cross-agent-setup.md` hook-матрица, `notes/2026-04-20_03-36_cross-agent-research.md`

**Hook-матрица (из docs):**

| Our hook | Pi статус в docs | Реальность |
|----------|------------------|------------|
| SessionEnd auto-capture | "git-fallback when project is a git repo; global prompts otherwise" | ✅ Git-fallback работает (post-commit hook) |
| PreCompact actualize | "—" (пусто) | ❌ Невозможно. Pi не имеет `preCompact` или `session.compacting` событий |
| PreToolUse block-dangerous | "native" | ❌ **Ложь**. Pi не имеет PreToolUse hooks. "native" в доке означает "Pi сам блокирует опасное" — но это НЕ наш `block-dangerous.sh` (нет защиты от `rm -rf /`, `npm publish`, piping curl-to-shell) |
| Weekly compact reminder | "fallback" | ⚠️ Git-fallback не даёт weekly reminder; только post-commit trigger |

**Влияние:**
- `block-dangerous.sh` — ПОЛНОСТЬЮ отсутствует на Pi. Пользователь Pi не защищён от:
  - `rm -rf /` или `rm -rf ~`
  - `curl ... | bash` без review
  - `npm publish`, `pip upload`, `cargo publish` без блокировки
  - записи в `protected_paths` (`.env`, CI configs, Docker/K8s/Terraform)
- `mb-compact-reminder.sh` — нет. Pi пользователь не получает напоминание о компакте раз в 7 дней.
- `mb-session-start-context.sh` — нет hook'а на session start. Контекст загружается только если пользователь явно напишет `/mb start` или агент сам прочитает AGENTS.md.

**Рекомендация:**
- Обновить `docs/cross-agent-setup.md`: Pi PreToolUse = "❌ not supported — Pi lacks hook API; dangerous-op protection relies on user vigilance and AGENTS.md rules only"
- Добавить в `SKILL.md` (Pi section)显式ное предупреждение: "Pi does not support tool-use hooks; dangerous operations are NOT automatically blocked. Review all `bash` and `write` commands carefully."
- Рассмотреть Pi extension, который регистрирует custom tools, заменяющие `bash`/`write` с guard-логикой (hard — требует замены built-in tools)

---

## 3. Критические гэпы (🟠)

### 🟠 G1: Model dispatch (G11) на Pi — нет programmatic API для смены модели

**Где в спеке:** `specs/parallel-pipeline/design.md` §10.5

**Проблема:**
- G11 предполагает, что pipeline может сказать адаптеру: "исполни этот dispatch с моделью GPT-5.5 через skill:openai-gpt"
- Claude Code может это сделать (`Skill()` tool вызывает другой skill с другой моделью)
- Pi не имеет programmatic API для смены модели внутри extension/skill. Есть `/model` команда для пользователя, но нет API для кода.
- Pi extension может использовать `createCustomProvider` или RPC spawn с другой моделью, но это **существенно сложнее**, чем "native model dispatch"

**Влияние:** G11 на Pi работает только для `via: native` (текущая модель Pi) и `via: cli:<cmd>` (shell out). `via: skill:<name>` — невозможен.

**Рекомендация:** В `pipeline.yaml` capability matrix для Pi: `model.via` поддерживает только `native` и `cli:*`. Добавить в `mb-pipeline-model-resolve.sh` Pi-specific ограничение.

---

### 🟠 G2: Prompt templates ≠ Commands — нет аргумент-парсинга

**Проблема:**
- В Claude Code: `/mb work reviewer-v2 --auto --budget 50000` → структурированный вызов с флагами
- В Pi: `/mb` раскрывается в prompt template. Нет механизма передачи аргументов (`--auto`, `--budget`, `--max-cycles`). Пользователь должен вручную писать аргументы в тексте.
- `commands/work.md` содержит сложный DSL с таблицами форм, флагов и примеров. Этот DSL неприменим к prompt templates.

**Влияние:** UX на Pi существенно хуже. Сложные команды (`/mb work`, `/mb plan`, `/mb sdd`) теряют свою структурированность.

**Рекомендация:**
- Создать Pi-specific упрощённые prompt templates (без сложного DSL)
- Или: написать Pi extension, который регистрирует `/mb` как command с аргумент-парсингом (hard)
- Минимум: добавить в `docs/cross-agent-setup.md` troubleshooting section: "Pi uses prompt templates, not structured commands. Pass flags in natural language."

---

### 🟠 G3: GraphRAG-lite extension — существует, но не подключён

**Проблема:**
- `adapters/pi_graph_rag_extension.ts` лежит в репозитории с 2026-04
- Ни `install.sh`, ни `adapters/pi.sh` его не устанавливают
- Extension требует TypeScript компиляции и npm-зависимостей (`@earendil-works/pi-coding-agent`, `typebox`)
- Даже если установить вручную — нет гарантии совместимости с текущей версией Pi

**Влияние:** Pi пользователи не получают GraphRAG-lite tools (`code_context`, `graph_neighbors`, etc.), хотя они есть для Claude Code (через `search_code` / `index_codebase` native tools)

**Рекомендация:**
- Либо удалить `pi_graph_rag_extension.ts` как dead code
- Либо создать задачу на packaging Pi extension + CI test
- Либо (лучшее): заменить extension на Pi skill + instructions, чтобы Pi использовал `bash` calls к `mb-code-context.py` / `mb-graph-query.py` напрямую (аналогично тому, как GraphRAG работает в generic AGENTS.md mode)

---

### 🟠 G4: No agents/ или hooks/ для Pi в global install

**Проблема:**
- `install.sh` Step 2 (Agents) копирует `agents/*.md` только в `~/.claude/agents/`
- `install.sh` Step 3 (Hooks) копирует `hooks/*.sh` только в `~/.claude/hooks/`
- Pi не получает ни agents, ни hooks глобально
- Pi prompt templates (commands) — единственная global install артефакт для Pi

**Влияние:**
- Роли (`mb-developer`, `mb-reviewer`, etc.) агенты недоступны глобально для Pi
- В `work.md` есть fallback: "Если host не поддерживает native subagents, используй `agents/*.md` как prompt". Но для Pi эти prompts не установлены.

**Рекомендация:**
- Копировать `agents/*.md` в `~/.pi/agent/prompts/` (или `~/.pi/agent/skills/memory-bank/agents/`)
- Или: добавить в `SKILL.md` (Pi) инструкцию, что агенты доступны только в project-level через `AGENTS.md`

---

## 4. Предупреждения (🟡)

### 🟡 W1: `docs/cross-agent-setup.md` содержит неточности про Pi hooks

- "PreToolUse block — native" — вводит в заблуждение. Pi не имеет PreToolUse hooks.
- "SessionEnd auto-capture — git-fallback when project is a git repo; global prompts otherwise" — частично верно, но "global prompts otherwise" не объясняет, что происходит (ничего — нет auto-capture без git).

**Fix:** Переписать hook-матрицу с честными статусами.

---

### 🟡 W2: `notes/2026-04-20_03-36_cross-agent-research.md` — устаревшие амбиции

- Research note заявляет: "6 клиентов — full native hooks (Cursor, Windsurf, Cline, OpenCode, **Pi**, Codex)"
- Это было написано на основе предположений, не проверено на реальном Pi API
- Фактически: Pi — **единственный** из 7 клиентов без native hooks (даже Kilo имеет git-fallback, который реально работает)

**Fix:** Обновить research note с disclaimer'ом: "Pi hook claims were aspirational; Pi lacks native hook API as of 2026-05-24"

---

### 🟡 W3: `test_pi_adapter.bats` — покрытие слишком поверхностное

- 12 тестов покрывают только install/uninstall/idempotency
- Нет тестов на:
  - Prompt template resolution (`~/.pi/agent/prompts/`)
  - Skill mode content (правила из `RULES.md` попадают в `SKILL.md`?)
  - Git-hooks-fallback content (hook body содержит `memory-bank: managed hook`?)
  - Extension install (если решим его оживить)
  - Global storage path resolution

**Fix:** Добавить ≥6 тестов на prompt install, skill content, hook body, MB_PATH propagation.

---

### 🟡 W4: `specs/parallel-pipeline/design.md` §17 "Open questions" — Pi subagent API stability

> "Pi subagent API stability — verify before spec close; if unstable, downgrade to sequential fallback with a warning"

- Это open question предполагает, что API существует и просто "unstable"
- Реальность: API не существует как first-class feature. "Downgrade to sequential" — единственно возможный путь.

**Fix:** Закрыть open question с ответом: "Pi has no native subagent API. Sequential fallback via extension/RPC is the only path. Capability matrix updated."

---

## 5. Матрица совместимости (Ground Truth)

| Функция | Claude Code | Cursor | Pi | Codex | OpenCode | Kilo |
|---------|-------------|--------|-----|-------|----------|------|
| **Skill alias** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| **AGENTS.md** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Slash commands** | ✅ native | ✅ native | ⚠️ prompts | ✅ native | ✅ native | ❌ |
| **PreToolUse block** | ✅ | ✅ | ❌ | ⚠️ experimental | ✅ | ❌ |
| **SessionEnd auto-capture** | ✅ | ✅ | ⚠️ git-only | ⚠️ experimental | ✅ | ⚠️ git-only |
| **PreCompact actualize** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Weekly compact reminder** | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
| **Parallel subagents** | ✅ native | ✅ native | ❌ | ❌ | ❌ | ❌ |
| **Model dispatch (G11)** | ✅ | ✅ | ⚠️ native/cli only | ⚠️ native/cli only | ⚠️ native/cli only | ❌ |
| **GraphRAG-lite** | ✅ native | ✅ native | ❌ dead code | ✅ CLI | ✅ CLI | ✅ CLI |
| **Global storage** | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |

---

## 6. Рекомендуемый план ремедиации

### Немедленно (Wave 0 / CI baseline)
- [ ] **Fix W1:** Переписать `docs/cross-agent-setup.md` hook-матрицу — честные статусы для Pi
- [ ] **Fix W2:** Добавить disclaimer в `notes/2026-04-20_03-36_cross-agent-research.md`
- [ ] **Fix B2:** Добавить в `SKILL.md` (Pi section) и `AGENTS.md` (Pi) предупреждение: "Pi lacks tool-use hooks — dangerous operations must be reviewed manually"

### Краткосрочно (Reviewer-v2 wave или skill-improvements wave)
- [ ] **Fix B1:** Обновить `specs/parallel-pipeline/design.md` §7, §10, §17:
  - Pi parallelism = "sequential via extension/RPC or CLI loop"
  - Убрать "native subagent API" для Pi
  - Добавить `adapters/pi/dispatch.ts` как **sequential fallback**, использующий `AgentSession` spawn
- [ ] **Fix G11:** `mb-pipeline-model-resolve.sh` — Pi-specific ограничение: `via: skill:<name>` → `host_supported=false`
- [ ] **Fix G2:** Создать Pi-specific упрощённые prompt templates (или хотя бы добавить troubleshooting в docs)
- [ ] **Fix G4:** Копировать `agents/*.md` в Pi global install path
- [ ] **Fix W3:** Дополнить `test_pi_adapter.bats` ≥6 тестами

### Среднесрочно (Backlog / следующий milestone)
- [ ] **Fix G3:** Решить судьбу `pi_graph_rag_extension.ts`:
  - Вариант A: удалить (упрощение)
  - Вариант B: packaging + CI + интеграция в `install.sh` (усложнение, требует npm build)
  - Вариант C: заменить на инструкции в prompt — "для code context используй `bash` → `mb-code-context.py`"
- [ ] **Fix B2 (полноценно):** Написать Pi extension, который регистрирует `safe_bash` tool с guard-логикой (hard, отдельный проект)

---

## 7. Вывод

**Pi поддерживается, но существенно уступает Claude Code и Cursor.**

- Базовый flow (`/mb start`, `/mb plan`, `/mb work`, `/mb done`) работает через prompt templates + AGENTS.md + git-hooks-fallback.
- **Безопасность** — критический гэп: нет PreToolUse hooks, нет protected-paths guard, нет block-dangerous.
- **Pipeline** — S5 parallel-pipeline требует радикального пересмотра для Pi; текущая спецификация описывает несуществующий API.
- **Model routing (G11)** — ограничен `native` + `cli` только.
- **Extension (`pi_graph_rag_extension.ts`)** — мёртвый код.

**Приоритет:** Зафиксировать документацию (W1, W2, B2), затем переписать Pi-адаптер в parallel-pipeline как sequential fallback (B1). Остальное — в backlog.
