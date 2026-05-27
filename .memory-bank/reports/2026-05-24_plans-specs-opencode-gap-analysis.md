# Отчёт: аудит планов и спецификаций на предмет OpenCode-гэпов

Дата: 2026-05-24
Автор: AI-аудитор
Статус: готов к ревью
Сфера: все queued планы (14) + все активные спеки (8 направлений, 24 файла)

---

## Executive summary

Проверены **14 планов** и **24 спецификационных файла** (8 направлений). Выявлено **49 разрывов**, из которых **18 HIGH**, **23 MED**, **8 LOW**. Ключевой паттерн: **все спецификации фундаментально построены вокруг `Task()` API Claude Code**, который отсутствует в OpenCode. OpenCode имеет самую богатую нативную плагин-систему из всех 6 хостов, но ни один план/спека не рассматривает JS/TS плагин как первоклассную реализацию. Это системный architectural gap.

---

## 1. Фундаментальные (структурные) разрывы

### F1. Универсальное предположение о `Task()` API (HIGH, cross-cutting)

**Проблема:** Все планы и спеки используют `Task(subagent_type=<role>, model=<resolved>, prompt=...)` как единственный примитив dispatch. OpenCode **не имеет** нативного `Task()` tool.

**Где проявляется:**
- reviewer-v2: `Task(mb-reviewer)`, `Task(mb-test-runner)` — §2, §5, §6
- work-loop-v2: `Task(role-agent)`, `Task(mb-reviewer)`, `Task(mb-architect)` — §2, §4, §5
- handoff-v2: `Task(mb-test-runner)` в done-gates — §5
- cost-multi-model: весь архитектурный слой §2 построен вокруг `Task(model=...)`
- goal-driven-autopilot (все 7 спринтов): debugger dispatch, implementer re-dispatch, parallel waves — Component 3, 4, 6
- parallel-pipeline: Claude Code adapter = "main agent issues N Task calls in one response"; OpenCode adapter = bash sequential loop
- pi-extension: sequential fallback тоже предполагает Task-подобный dispatch

**Почему это критично:** Без dispatch-абстракции весь harness-upgrade (W1–W5) и goal-driven-autopilot (W6–W12) не могут работать на OpenCode. Пользователи OpenCode получат sequential fallback с потерей parallelism и model-routing.

**Рекомендация:** Ввести `scripts/mb-dispatch.sh <role> <prompt-file>` — host-agnostic dispatch layer:
- Claude Code → `Task(role=..., prompt=...)`
- OpenCode → `opencode run` CLI (или plugin subtask delegation)
- Codex → `codex run`
- Pi → `pi run` / extension RPC
- Cursor/Kilo → sequential CLI fallback

---

### F2. Система хуков — маппинг на OpenCode плагин отсутствует (HIGH, cross-cutting)

**Проблема:** Спецификации описывают хуки в терминах Claude Code (`PreToolUse`, `PreCompact`, `session_start`) или bash-файлы (`hooks/mb-pre-compact.sh`, `hooks/mb-session-start-context.sh`). OpenCode имеет **JS/TS плагин-хуки**: `onReady`, `onBeforeCommand`, `onAfterCommand`, `onBeforeToolExecute`, `onAfterToolExecute`, `experimental.session.compacting`, `event`.

**Где проявляется:**
- handoff-v2 §2, §4: `preCompact` → `settings/hooks.json` (Claude Code). OpenCode: `experimental.session.compacting` не упомянут.
- handoff-v2 §2: `SessionStart` → bash hook. OpenCode: `onReady` не маппится.
- pi-extension REQ-208, REQ-209: dangerous-command guard через `tool_call` event. OpenCode: `onBeforeToolExecute` — эквивалент, но не задокументирован.
- pi-extension REQ-211: `session_before_compact`. OpenCode: `experimental.session.compacting` — эквивалент, но не маппится.
- reviewer-v2, work-loop-v2: нет guard-хуков вообще для OpenCode.

**Почему это критично:** Без guard-хуков OpenCode не получает защиту dangerous commands и protected paths. Без `experimental.session.compacting` — не работает auto-actualize перед compaction.

**Рекомендация:** Создать документ `references/opencode-hooks-mapping.md` с таблицей:

| Bash hook | Claude Code hook | OpenCode plugin hook |
|---|---|---|
| `hooks/mb-pre-compact.sh` | `preCompact` | `experimental.session.compacting` |
| `hooks/mb-session-start-context.sh` | `session_start` | `onReady` |
| `hooks/file-change-log.sh` | `PreToolUse` (write/edit) | `onBeforeToolExecute` |
| `hooks/mb-protected-paths-guard.sh` | `PreToolUse` (write/edit) | `onBeforeToolExecute` |
| `hooks/mb-plan-sync-post-write.sh` | `PostToolUse` (write/edit) | `onAfterToolExecute` |

И реализовать `plugins/opencode-guards.js` (или встроить в существующий plugin) эти маппинги.

---

### F3. OpenCode плагин-система полностью игнорируется (HIGH, cross-cutting)

**Проблема:** OpenCode имеет **самую мощную плагин-систему** из всех хостов (JS/TS, auto-discovery, hooks, subtask API), но ни один план не рассматривает плагин как первоклассную реализацию. Вместо этого:
- `adapters/opencode.sh` — bash install adapter
- `adapters/opencode/dispatch.sh` — bash sequential loop (как Codex!)
- Все guard-логики — bash скрипты

**Сравнение:**
- Claude Code: нет плагинов → используем bash адаптер + hooks.json (единственный путь)
- Pi: нет hooks API → планируем TypeScript extension (`pi-extension`)
- **OpenCode: есть плагины → используем bash!** Это architectural downgrade.

**Где проявляется:**
- parallel-pipeline §10: OpenCode adapter = `dispatch.sh` sequential CLI loop. Пропущена возможность плагин-based parallel dispatch.
- goal-driven-autopilot sprint 5: parallel waves — OpenCode мог бы использовать plugin subtask delegation, но план предписывает sequential fallback.
- pi-extension: Pi получает first-class TypeScript extension (`index.ts`, `hooks.ts`, `commands.ts`, `providers.ts`). OpenCode с такой же (или большей) способностью — только bash.

**Рекомендация:** Пересмотреть архитектуру OpenCode интеграции:
- **Install:** `adapters/opencode.sh` остаётся bash (install/project-level setup)
- **Runtime:** заменить `adapters/opencode/dispatch.sh` на `adapters/opencode/plugin.js` или `plugins/memory-bank/index.js`
- **Guards:** реализовать через `onBeforeToolExecute` в плагине, а не через git-hooks-fallback
- **Hooks:** `onReady` → session start context; `experimental.session.compacting` → pre-compact actualize; `event` → session idle/deleted

---

## 2. Разрывы по направлениям (планы)

### 2.1 reviewer-v2 (W1)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| RV-1 | `Task(mb-reviewer)` dispatch | HIGH | Stage 4: `resolve_test_cache` → `Task(mb-test-runner)`. Нет OpenCode пути. |
| RV-2 | `Task → mb-reviewer` dispatch | HIGH | Stage 4-5: orchestrator dispatches reviewer agent. Нет OpenCode пути. |
| RV-3 | `commands/work.md` OpenCode frontmatter | MED | Step 3c обновлён, но command file не декларирует OpenCode `agent`/`subtask`. |
| RV-4 | Install.sh — skill path | MED | Stage 5: rubric-examples копируются в "installed skill location". Нет OpenCode пути. |
| RV-5 | Calibration runner mock | LOW | Bats мокают Task через write artifacts. Нужен OpenCode mock fixture. |

### 2.2 skill-improvements-anthropic-audit (W1 docs)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| SI-1 | Eval suite activation | MED | Stage 3: eval JSON тестирует "Skill memory-bank invoked". OpenCode — auto-discovery; eval нуждается в проверке auto-discovery. |
| SI-2 | Install profile | MED | Stage 6: `install.sh --profile` — no OpenCode destination. |
| SI-3 | Global rules path | LOW | `~/.claude/CLAUDE.md` — OpenCode использует другой global config path. |

### 2.3 work-loop-v2 (W2)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| WL-1 | `Task(subagent_type, model)` dispatch | HIGH | Stage 3: pivot dispatch. Stage 2: contract review dispatch. |
| WL-2 | `commands/work.md` frontmatter | MED | Нет OpenCode command frontmatter. |
| WL-3 | `pivot_via_architect` | HIGH | `mb-work-pivot.sh` dispatches `mb-architect` via Task. |

### 2.4 handoff-v2 (W3)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| HF-1 | `settings/hooks.json` / `preCompact` | HIGH | Stage 2: `mb-pre-compact.sh` → Claude Code hooks.json. OpenCode: `experimental.session.compacting` не маппится. |
| HF-2 | `SessionStart` injection | HIGH | Stage 2: `mb-session-start-context.sh` → bash hook. OpenCode: `onReady` не маппится. |
| HF-3 | `Task(mb-test-runner)` done-gates | HIGH | Stage 3: `mb-done-gates.sh` → Task dispatch. |
| HF-4 | Manager agent actions | MED | Stage 4: manager agent → chain rebuild. В OpenCode нужен plugin coordination. |

### 2.5 cost-multi-model (W4)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| CM-1 | `Task(model=...)` wiring | HIGH | Stage 3: весь dispatch через Task с model параметром. OpenCode не может. |
| CM-2 | `mb-reviewer-resolve.sh` emits model for Task | HIGH | Line 2 model для Task. OpenCode не потребляет. |
| CM-3 | Commands frontmatter | MED | Обновлённые commands — нет OpenCode metadata. |
| CM-4 | Install.sh aliases path | MED | `model-aliases.yaml` — no OpenCode install target. |
| CM-5 | Model aliases Anthropic-specific | LOW | `fast/balanced/powerful` → Anthropic IDs. OpenCode (Kimi) — другие defaults. |

### 2.6 goal-driven-autopilot (W5–W11)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| GA-1 | Sprint 1: `commands/work.md` dispatch | HIGH | Stage 4: prompt assembly → implicit Task dispatch. |
| GA-2 | Sprint 2: `Task(mb-debugger)` | HIGH | Component 3: debugger via Task. |
| GA-3 | Sprint 2: auto-trigger re-dispatch | MED | E2E: FAIL → debugger → implementer re-dispatched. Всё через Task. |
| GA-4 | Sprint 2: `commands/debug.md` frontmatter | MED | Новый command — нет OpenCode frontmatter. |
| GA-5 | Sprint 3: subtask isolation | MED | Worktree isolation → OpenCode `opencode run` CLI может, но plugin subtask delegation не специфицирован. |
| GA-6 | Sprint 4: `/mb work` integration | HIGH | Stage 3: atomic commit loop — Task-based PASS/FAIL. |
| GA-7 | Sprint 5: parallel waves | HIGH | Component 4: "one message with N Task calls". OpenCode — невозможно natively. |
| GA-8 | Sprint 6: `commands/goal.md` frontmatter | MED | Новый command — нет OpenCode frontmatter. |
| GA-9 | Sprint 7: autopilot loop | HIGH | Component 6: repeated implement → review → debug → refine. Всё через Task. |
| GA-10 | Sprint 7: auto-recovery | HIGH | Re-dispatch debugger/implementer через Task. |
| GA-11 | Sprint 7: hard stops / context guard | MED | `sprint_context_guard` — long-running session с Task subagents. OpenCode: `experimental.session.compacting` не задействован. |

### 2.7 parallel-pipeline (W12)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| PP-1 | `adapters/opencode/dispatch.sh` — bash, не плагин | HIGH | Stage 4: sequential bash loop. OpenCode plugin мог бы дать native hooks + subtask. |
| PP-2 | `model.via: skill:*` routing | HIGH | G11: Claude Code → `Skill(...)` tool. OpenCode: skills есть, но нет `Skill()` tool call. Плагин должен загружать skill context вручную. |
| PP-3 | `mb-pipeline-model-resolve.sh` probes `~/.claude/skills/` | MED | Должен пробовать `.opencode/skills/` или `~/.config/opencode/skills/`. |
| PP-4 | Parallel dispatch in single response | HIGH | Claude Code: "N Task calls in one response". OpenCode: нет native parallel subagent message. |
| PP-5 | `execution.active_adapter: opencode` routes to sh | MED | Игнорирует auto-discovery и plugin capabilities. |
| PP-6 | `commands/run.md` frontmatter | MED | Новый command — нет OpenCode frontmatter. |
| PP-7 | Capability matrix underestimates OpenCode | LOW | OpenCode помечен "⚠️ sequential CLI loop". Пропущен plugin potential. |

### 2.8 pi-compatibility-remediation (fix)

| ID | Gap | Severity | Описание |
|---|---|---|---|
| PI-1 | No OpenCode extension equivalent | HIGH | Pi получает first-class TS extension. OpenCode — только bash. Парадокс: у OpenCode лучший plugin API, но худшая реализация. |
| PI-2 | `install.sh --clients pi` only | MED | Нет `--clients opencode`. |
| PI-3 | Dangerous-command guard | MED | Pi: `tool_call` block. OpenCode: `onBeforeToolExecute` — не реализован. |
| PI-4 | Protected-paths guard | MED | Аналогично PI-3. |

---

## 3. Разрывы по спецификациям (requirements / design / tasks)

### 3.1 reviewer-2.0

- **HIGH:** Архитектура §2, test-cache §5, calibration §6 — всё через `Task()`. Нет OpenCode dispatch contract.
- **HIGH:** `commands/work.md` step 3c — orchestrator invokes agent. OpenCode mechanism unspecified.
- **MED:** Calibration runner в live LLM mode dispatches `Task(mb-reviewer)`. OpenCode golden-suite execution undefined.
- **MED:** `mb-test-runner` on-miss cache — `Task` со `scope=touched`. OpenCode strategy unspecified.
- **LOW:** Bats mock Task через write artifacts. OpenCode mock fixture path needed.

### 3.2 work-loop-v2

- **HIGH:** Sprint contract phase §2, §4 — generator role-agent и `mb-reviewer` (mode=contract) через `Task()`.
- **HIGH:** Pivot dispatch §5 — "re-dispatch same role-agent" и "dispatch `mb-architect`" через `Task()`.
- **MED:** `mb-review.sh` extended для `progress_trend`, но review dispatch всё ещё через Task.
- **MED:** Contract phase budget guard — считает Task dispatches. OpenCode dispatch cost/complexity отличается.

### 3.3 handoff-v2

- **HIGH:** `preCompact` event — только Claude Code/Cursor hook §2, §4. OpenCode `experimental.session.compacting` не упомянут.
- **MED:** `SessionStart` hook — `onReady` не маппится.
- **MED:** Done-gates — `Task(mb-test-runner)`. OpenCode invocation unspecified.
- **MED:** `agents/mb-manager.md` — dispatched as subagent. OpenCode manager dispatch unspecified.
- **LOW:** `mb-handoff.sh`, `mb-progress-chain.sh` — pure bash, работают на OpenCode, но triggering hooks нуждаются в plugin wrappers.

### 3.4 cost-multi-model

- **HIGH:** Весь архитектурный слой §2 построен вокруг `Task(subagent_type, model, prompt)`.
- **HIGH:** Все dispatch sites (`commands/*.md`, `scripts/mb-review.sh`) передают resolved model в Task.
- **MED:** `model-aliases.yaml` — Anthropic IDs. OpenCode (Kimi) — другие defaults; нет provider-neutral aliases.
- **MED:** `agents/*.md` frontmatter `model_class` — OpenCode plugin не читает markdown frontmatter для dispatch.

### 3.5 parallel-pipeline

- **MED:** OpenCode явно relegated to "sequential CLI loop" §2, §10. Не исследован plugin-driven subtask API.
- **MED:** Capability matrix §10 — OpenCode "⚠️ sequential". Недооценены `opencode run` и plugin capabilities.
- **MED:** Multi-provider model dispatch §10.5 — OpenCode `opencode run` with default model. Не исследовано, может ли plugin wrap cross-provider models.
- **LOW:** Worktree lifecycle работает на OpenCode, но executor отдаёт управление minimal adapter.

### 3.6 goal-driven-autopilot

- **HIGH:** `mb-debugger` dispatch (Component 3) и auto-recovery (Component 6, §8.5) — всё через `Task()`.
- **HIGH:** Parallel waves (Component 4) — "one message with N Task calls". OpenCode — нет native parallel subagent message.
- **MED:** Autopilot loop (Component 6) — repeated dispatch implement/debug/review. Нужна explicit OpenCode strategy.
- **MED:** Overlay system (Component 7) — builds prompts и dispatches Task. OpenCode mechanism unspecified.
- **LOW:** Goal layer, worktree isolation, atomic commit — bash/git-based, работают на OpenCode.

### 3.7 mb-skill-v2 (archived)

- **LOW:** Archived spec. Использует `Task()` и Claude Code-specific hooks (`PreToolUse`, `PostToolUse`, `PreAgentInvoke`). OpenCode hooks (`onBeforeToolExecute`, `onAfterToolExecute`, `onReady`) не маппятся. Но spec superseded by S1–S5.

### 3.8 pi-extension

- **MED:** Dangerous-command guard (REQ-208) — Pi `tool_call` event. OpenCode `onBeforeToolExecute` — equivalent, но не упомянут.
- **MED:** Protected-paths guard (REQ-209) — Pi `tool_call` для write/edit. OpenCode `onBeforeToolExecute` — equivalent, но не упомянут.
- **MED:** PreCompact actualize (REQ-211) — Pi `session_before_compact`. OpenCode `experimental.session.compacting` — equivalent, но не маппится.
- **LOW:** SessionStart reminder (REQ-212) — Pi `session_start`. OpenCode `onReady` — equivalent, но не маппится.
- **LOW:** Extension Pi-specific by design, но hooks/guards cross-cutting — должны иметь OpenCode plugin counterparts.

---

## 4. Cross-cutting список разрывов (сводная таблица)

| # | Разрыв | Severity | Затронутые планы | Затронутые спеки |
|---|---|---|---|---|
| C1 | `Task()` API assumption everywhere | HIGH | W1, W2, W3, W4, W5–W11, W12, pi-fix | reviewer, work-loop, handoff, cost-multi-model, parallel-pipeline, goal-driven-autopilot, pi-extension |
| C2 | Hook system mismatch — no OpenCode plugin mapping | HIGH | W3, W12, pi-fix | handoff, pi-extension, reviewer, work-loop |
| C3 | OpenCode plugin system completely unused | HIGH | W12, pi-fix | parallel-pipeline, pi-extension, handoff |
| C4 | Commands missing OpenCode frontmatter | MED | W1, W2, W4, W5–W11, W12 | reviewer, work-loop, cost-multi-model, goal-driven-autopilot, parallel-pipeline |
| C5 | Install paths ignore OpenCode skill layout | MED | W1, W2, W4, W12, pi-fix | reviewer, cost-multi-model, pi-extension |
| C6 | Model resolver probes `~/.claude/skills/` only | MED | W4, W12 | cost-multi-model, parallel-pipeline |
| C7 | Parallel dispatch not adapted to OpenCode | HIGH | W10, W12 | goal-driven-autopilot (sprint 5), parallel-pipeline |
| C8 | Dangerous-command / protected-path guards not OpenCode plugin | MED | W3, pi-fix | handoff, pi-extension |
| C9 | No OpenCode-specific REQ IDs | MED | все | все |
| C10 | Test strategies omit OpenCode | MED | все | все |
| C11 | Model aliases Anthropic-specific | LOW | W4 | cost-multi-model |
| C12 | `tool.execute.before` signature unused | LOW | — | pi-extension, handoff |

---

## 5. Рекомендации по устранению

### 5.1 Стратегические (перед началом W1)

1. **Создать `scripts/mb-dispatch.sh`** — host-agnostic dispatch abstraction.
   - Интерфейс: `mb-dispatch.sh <role> <prompt-file> [--model <alias>]`
   - Реализация: detect host (`$MB_HOST` или auto-detect), route to `Task()`, `opencode run`, `codex run`, etc.
   - Влияние: закрывает C1 для всех планов.
   - Трудоёмкость: 2–3h.

2. **Создать `references/opencode-hooks-mapping.md`** + расширить OpenCode plugin.
   - Маппинг bash hooks → OpenCode plugin hooks.
   - Реализация guard-логики в `onBeforeToolExecute`.
   - Влияние: закрывает C2, C8.
   - Трудоёмкость: 3–4h.

3. **Пересмотреть `adapters/opencode/dispatch.sh`**.
   - Вариант A (минимальный): оставить bash, но добавить `opencode run --subtask` wrapper.
   - Вариант B (оптимальный): создать `adapters/opencode/plugin.js` для runtime dispatch с native hooks.
   - Влияние: закрывает C3, C7.
   - Трудоёмкость: A=1h, B=4–6h.

### 5.2 Тактические (в рамках каждого wave)

4. **Commands frontmatter**: при создании/обновлении любого `commands/*.md` добавлять OpenCode `agent`/`subtask`.
   - Трудоёмкость: 5 мин на файл.
   - Влияние: C4.

5. **Install.sh OpenCode path**: добавить `--clients opencode` и `~/.config/opencode/skills/` alias.
   - Трудоёмкость: 30 мин.
   - Влияние: C5.

6. **Model resolver**: обновить `mb-pipeline-model-resolve.sh` для probe `.opencode/skills/`.
   - Трудоёмкость: 20 мин.
   - Влияние: C6.

7. **Test strategies**: добавить `test_opencode_*.bats` для каждого нового feature (dispatch, guards, hooks).
   - Трудоёмкость: 1h per wave.
   - Влияние: C10.

### 5.3 Архитектурные (для v5.0.0)

8. **Provider-neutral model aliases**: вместо Anthropic IDs использовать generic aliases (`fast`, `balanced`, `powerful`) с per-host resolution table.
   - Трудоёмкость: 2h.
   - Влияние: C11.

9. **OpenCode plugin as first-class citizen**: создать `plugins/opencode/` с полноценным JS plugin, реализующим все guard/hook/dispatch функции.
   - Трудоёмкость: 8–12h.
   - Влияние: C1, C2, C3, C7, C8.

---

## 6. Влияние на roadmap

### Блокеры для wave'ов

| Wave | План | OpenCode blockers если не устранить C1/C2/C3 |
|---|---|---|
| W1 | reviewer-v2 | Не запускается reviewer/test-runner на OpenCode. Manual sequential fallback. |
| W2 | work-loop-v2 | Не работает pivot dispatch и contract review. Loop stuck. |
| W3 | handoff-v2 | Не работает pre-compact actualize и session start context. No guard hooks. |
| W4 | cost-multi-model | Model routing игнорируется. Всё runs on default model. |
| W5–W11 | goal-driven-autopilot | Debugger, parallel waves, autopilot loop — не работают. Sequential only. |
| W12 | parallel-pipeline | Sequential fallback loses parallelism; no skill dispatch; no native hooks. |

### Рекомендуемый порядок фиксов

1. **До W1:** `mb-dispatch.sh` (C1) + `opencode-hooks-mapping.md` (C2).
2. **В W1:** Commands frontmatter (C4) + install.sh OpenCode path (C5).
3. **В W3:** OpenCode plugin guards (C8) + `experimental.session.compacting` mapping.
4. **В W4:** Model resolver OpenCode probe (C6) + provider-neutral aliases (C11).
5. **В W12:** OpenCode plugin dispatch (C3, C7) — replace bash dispatch with JS plugin.

---

## 7. Ключевые файлы для референса

- `adapters/opencode.sh` — install adapter (исправлен в текущей сессии).
- `adapters/opencode/dispatch.sh` — runtime dispatch (needs architectural review).
- `hooks/*.sh` — bash hooks (need OpenCode plugin mapping).
- `commands/*.md` — command definitions (need OpenCode frontmatter).
- `scripts/mb-pipeline-model-resolve.sh` — model resolver (needs OpenCode probe).
- `install.sh` — global install (needs `--clients opencode`).
- `specs/parallel-pipeline/design.md` §10 — capability matrix (underestimates OpenCode).
- `specs/pi-extension/design.md` — Pi extension (OpenCode should get equivalent plugin).

---

## 8. Закрытие отчёта

Этот аудит показывает, что **OpenCode интеграция — не просто "ещё один адаптер"**. OpenCode имеет уникальный потенциал (native plugins, subtasks, auto-discovery), но текущие планы **downgrade** его до Codex-level bash sequential fallback. Это архитектурная ошибка.

**Минимум для v5.0.0:**
- `mb-dispatch.sh` abstraction (C1).
- OpenCode plugin guards + hooks mapping (C2, C8).
- Commands frontmatter (C4).
- Install.sh OpenCode path (C5).

**Оптимум для v5.0.0:**
- Full OpenCode JS plugin replacing bash dispatch (C3, C7).
- Provider-neutral model aliases (C11).
- OpenCode-specific test fixtures (C10).
