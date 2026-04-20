---
type: note
tags: [cross-agent, research, stage-8, hooks, adapters, v3.0]
importance: high
---

# Cross-agent research — Stage 8 (v3.0)

Research upfront перед построением 7 adapters. **Фокус:** какие клиенты имеют hooks API, как выглядит финальная hook-матрица, где нужен git-fallback.

## Сводка (TL;DR)

**Только 1 из 7 клиентов БЕЗ hooks API — Kilo.** Остальные 6 поддерживают lifecycle events нативно. **Бонус-сюрприз:** Cursor 1.7+ и Codex — оба имеют `hooks.json` совместимый с Claude Code форматом, что даёт нам direct reuse наших существующих hook-скриптов.

| # | Client | Config | Hooks | Strategy |
|---|--------|--------|-------|----------|
| 1 | Cursor | `.cursor/rules/*.mdc` + `.cursor/hooks.json` | ✅ **CC-compat** | native hooks (reuse CC format) |
| 2 | Windsurf | `.windsurf/rules/*.md` | ✅ Cascade Hooks (JSON+shell) | native hooks |
| 3 | Cline | `.clinerules/` + `.clinerules/hooks/` | ✅ shell scripts | native hooks |
| 4 | Kilo | `.kilocode/rules/` + `kilo.jsonc` | ❌ (FR #5827 open) | rules + git-fallback |
| 5 | OpenCode | `AGENTS.md` + `opencode.json` | ✅ TypeScript plugins | native hooks |
| 6 | Pi Code | `~/.pi/skills/` (Skills API) | 🔄 in development | native + git-fallback transitional |
| 7 | Codex | `AGENTS.md` + `.codex/config.toml` + `hooks.json` | ✅ experimental | native hooks (flag behind experimental) |

## Per-client details

### 1. Cursor

- **Config path:** `.cursor/rules/*.mdc` (новый формат, `.cursorrules` legacy)
- **Frontmatter:** `description`, `alwaysApply` (bool), `globs` (patterns)
- **Hooks:** **✅ Cursor 1.7+ (октябрь 2025) добавил полноценный hooks API**
  - **Config file:** `<project>/.cursor/hooks.json` (project-level) + `~/.cursor/hooks.json` (user-level)
  - **Format:** JSON, spawned processes, stdin/stdout JSON contract
  - **Exit codes:** 0 = success (use JSON output), **2 = block action**, other = fail-open
  - **Events (Agent/Cmd+K):**
    - Lifecycle: `sessionStart`, `sessionEnd`, `stop`
    - Tool: `preToolUse`, `postToolUse`, `postToolUseFailure`
    - Subagent: `subagentStart`, `subagentStop`
    - Shell/MCP: `beforeShellExecution`, `afterShellExecution`, `beforeMCPExecution`, `afterMCPExecution`
    - Files: `beforeReadFile`, `afterFileEdit`
    - Prompt: `beforeSubmitPrompt`
    - Context: **`preCompact`** — прямой match!
    - Responses: `afterAgentResponse`, `afterAgentThought`
  - **Tab hooks (inline completions):** `beforeTabFileRead`, `afterTabFileEdit`
  - **Input base fields:** `conversation_id`, `generation_id`, `model`, `hook_event_name`, `cursor_version`, `workspace_roots`, `user_email`
  - **Output contracts:** `{ "permission": "allow|deny|ask" }` для permission decisions, custom fields для observational
  - **🎁 KILLER FEATURE:** "Cursor supports loading hooks from third-party tools like Claude Code" — **наш CC hooks формат работает в Cursor нативно**
  - **CLI vs IDE limitation:** Cursor CLI fires только `beforeShellExecution`/`afterShellExecution`. Остальные events — только в IDE. Документировать в `docs/cross-agent-setup.md`.
- **Slash:** `/create-rule` в Agent chat (для создания rules)
- **Вывод:** **полноценные native hooks, с reuse нашего CC формата.** Adapter минимальный — просто copy `hooks/` + генерация `.cursor/hooks.json` с references на наши scripts. Git-fallback НЕ нужен.

### 2. Windsurf

- **Config path:** `.windsurf/rules/*.md` (workspace) + `~/.codeium/windsurf/memories/global_rules.md` (global)
- **Frontmatter:** `trigger: always_on | model_decision | glob | manual`
- **Hooks:** **✅ Cascade Hooks**
  - Shell commands с JSON context через stdin
  - Pre-hooks: exit code 2 → block action
  - Events: userpromptsubmit, model.response (+ другие по доке)
  - Config: JSON на 3 уровнях (user/workspace/project), merged
- **Slash:** стандарт Windsurf
- **Вывод:** полноценные native hooks, git-fallback НЕ нужен

### 3. Cline

- **Config path:** `.clinerules/` (директория). Global: `~/Documents/Cline/Rules`
- **Format support:** `.clinerules/`, `.cursorrules`, `.windsurfrules`, `AGENTS.md` — auto-merge
- **Frontmatter:** conditional rules с `paths:` (globs)
- **Hooks:** **✅ shell-script hooks**
  - Path: `.clinerules/hooks/`
  - Events: `beforeToolExecution`, `afterToolExecution`, `onNotification`
  - Runner: captures stdout/stderr, timeouts, feeds back в context
  - Discovery cache для performance
- **Extension API:** gRPC-over-postMessage internally, но external subscription API ограничен
- **Вывод:** полноценные native hooks, git-fallback НЕ нужен

### 4. Kilo

- **Config path:** `.kilocode/rules/*.md` (legacy, backward-compat) + `kilo.jsonc` (new preferred). `instructions:` array с paths/globs
- **Hooks:** **❌ нет first-class hooks.** Active FR [#5827](https://github.com/Kilo-Org/kilocode/issues/5827) "expose session lifecycle hooks similar to OpenCode"
- **Workarounds:**
  - `.kilo/commands/*.md` — slash-command templates
  - Custom subagents с own model+prompt+permissions
  - Terminal shell integration (auto-enabled, но не lifecycle)
- **Вывод:** `.kilocode/rules/` + git post-commit fallback. Следить за FR #5827 для v3.1 update

### 5. OpenCode

- **Config path:** `AGENTS.md` (primary) + `opencode.json` (detailed config)
- **Hooks:** **✅ TypeScript plugin system**
  - Format: JS/TS module, exports plugin function(s), returns hooks object
  - Events:
    - `session.created`, `session.idle`, `session.deleted`
    - `chat.message`, `chat.params`
    - `tool.execute.before`, `tool.execute.after`
    - `message.updated`
    - `experimental.session.compacting` — **прямой match для нашего PreCompact!**
  - State management с cleanup on `session.deleted`
- **Slash:** Commands как часть конфига
- **Plugin install:** bundled с проектом или published как package
- **Вывод:** богатейший API, прямая 1-к-1 миграция наших hooks

### 6. Pi Code (pi-mono)

- **Config path:** `~/.pi/skills/<name>/` — Skills API
- **Components в pi-mono:** Unified LLM API, Agent Runtime, Coding Agent CLI, Skills API
- **Hooks:** Skills API + session lifecycle hooks в **recent development priorities**
- **Fallback:** `AGENTS.md` support если Skills API нестабилен
- **Session storage:** `~/.pi/agent/sessions/` — можно использовать как file-change trigger
- **Вывод:** preferred = native Pi Skill; fallback = `AGENTS.md` + git hooks. **Verify Skills API stability в PR/issue перед implementation**

### 7. Codex CLI (OpenAI)

- **Config path:** `AGENTS.md` (discovered, controlled by `project_doc_max_bytes` + `project_doc_fallback_filenames`) + `.codex/config.toml` (project-level)
- **Hooks:** **✅ `hooks.json` (experimental, off by default)**
  - Loaded from `hooks.json` рядом с active config layers
  - Events (known): `userpromptsubmit` (block/augment prompts before execution and history)
  - Lifecycle hooks actively developed в changelog
  - TUI shows live running + completed hooks
- **Slash:** Standard Codex CLI subcommands
- **MCP support:** да, extending functionality
- **OpenTelemetry:** observability встроена
- **Вывод:** Codex hooks работают, но experimental — documentation our users о флаге enable. Формат близок к Claude Code hooks.

## Финальная hook-матрица для Stage 8

### Наши 4 Claude-Code hooks → маппинг per client

| Наш hook | Что делает | Cursor | Windsurf | Cline | Kilo | OpenCode | Pi | Codex |
|----------|-----------|--------|----------|-------|------|----------|-----|-------|
| **SessionEnd auto-capture** | append placeholder в progress.md | **`sessionEnd`** (прямой CC-compat) | Cascade hook (session-end equivalent) | `afterToolExecution` | git `post-commit` | `session.idle` или `session.deleted` | Pi session-save + fallback | `hooks.json` session-end когда стабилизируется |
| **SessionEnd compact-reminder** | раз в 7 дней напомнить | **`sessionEnd`** (check `.last-compact`) | Cascade hook (same) | `afterToolExecution` (check age) | git `post-commit` | `session.idle` (check age) | Pi session-save | `hooks.json` (when available) |
| **PreCompact** | MB Manager actualize | **`preCompact`** (прямой CC-compat!) | — | — | — | **`experimental.session.compacting`** | — | `preCompact` (когда появится) |
| **PreToolUse block-dangerous** | block `rm -rf /` и др. | **`preToolUse` + `beforeShellExecution` exit 2** | **Cascade pre-hook exit 2** | **`beforeToolExecution` exit non-zero** | rules (гайдлайн, не enforcement) | **`tool.execute.before`** (blockable) | Pi native | Codex `approval_policy` + hook |

### Стратегия установки

1. **Universal layer** — всегда:
   - `rules/RULES.md` (адаптированный под формат клиента)
   - `.memory-bank/` структура (идентична всем)
2. **Native hooks** — где поддерживается (6 из 7):
   - **Cursor** — **`.cursor/hooks.json` с references на наши `hooks/*.sh`** (CC-compatible format = direct reuse)
   - **Windsurf** — `.windsurf/hooks.json` (Cascade JSON+shell)
   - **Cline** — `.clinerules/hooks/*.sh` (shell scripts)
   - **OpenCode** — TypeScript plugin file в `opencode.json` plugins array
   - **Pi** — native `~/.pi/skills/memory-bank/` Skill (когда API стабилен)
   - **Codex** — `.codex/hooks.json` (experimental, warn user)
3. **Git-hooks fallback** — **только** для Kilo (и как belt-and-suspenders для Pi до стабилизации):
   - `adapters/git-hooks-fallback.sh` устанавливает `.git/hooks/post-commit` + `.git/hooks/pre-commit`
   - Детектит изменения в `.memory-bank/` → запускает наши скрипты
   - Idempotent install (проверяет existing hooks, не ломает)
4. **Pi Code** — дуальная стратегия: preferred Pi Skill регистрация, fallback на `AGENTS.md` + git-hooks.

### Cursor ↔ Claude Code hooks compatibility (killer feature)

Cursor docs явно: *"Cursor supports loading hooks from third-party tools like Claude Code"*. Это означает:
- Формат `hooks.json` у Cursor и Claude Code совместим
- Наши существующие `hooks/*.sh` скрипты работают в Cursor без изменений
- `adapters/cursor.sh` просто:
  1. Copy `hooks/*.sh` → `.cursor/hooks/` (или reference к `~/.claude/hooks/`)
  2. Generate `.cursor/hooks.json` с mapping events → scripts
- **Не нужно** писать client-specific wrappers — tiniest adapter из всех 7

Это же upgrade-path для будущих CC-compatible клиентов: любой новый client который объявит CC-compat сразу получает наш skill.

### Единственный client без hooks — Kilo

Kilo explicit FR [#5827](https://github.com/Kilo-Org/kilocode/issues/5827) "expose session lifecycle hooks similar to OpenCode" — статус open. До тех пор:
- `.kilocode/rules/*.md` для правил
- git-hooks-fallback для SessionEnd auto-capture / compact-reminder / PreToolUse-block
- Follow FR #5827 → при closing upgrade Kilo adapter до native

### Важный edge-case: shared `AGENTS.md`

OpenCode, Codex и Pi (fallback) используют `AGENTS.md`. При одновременной установке:
- Single shared file, content identical across clients
- Manifest tracks ownership per-client (`owned_by: [opencode, codex]`)
- Uninstall одного не затирает файл пока остальные active
- Cline тоже читает `AGENTS.md` auto-merge → бонус, не конфликт

## Impact на Stage 8 план

**Что меняется в плане (обновление после research):**

1. **Matrix hooks вместо binary "native vs git-fallback":**
   - **6 клиентов — full native hooks** (Cursor, Windsurf, Cline, OpenCode, Pi, Codex)
   - **1 клиент — git-fallback only** (Kilo)
   - **Cursor ≡ Claude Code формат** — direct reuse hooks (huge win, minimal adapter)
   - **OpenCode `experimental.session.compacting`** — direct PreCompact equivalent, bonus
   - **Cursor `preCompact`** — нативный, совпадает с нашим именованием 1-к-1

2. **Новый adapter: `adapters/git-hooks-fallback.sh`** — обязательный **только для Kilo**, optional opt-in для Pi (до стабилизации Skills API)

3. **Adapter spec per client более богатый:**
   - `adapters/cursor.sh` → `.cursor/rules/*.mdc` + **`.cursor/hooks.json` (CC-compat, reuse наших `hooks/*.sh`)**
   - `adapters/windsurf.sh` → `.windsurf/rules/*.md` + Cascade hooks JSON config
   - `adapters/cline.sh` → `.clinerules/` + `.clinerules/hooks/*.sh`
   - `adapters/kilo.sh` → `.kilocode/rules/*.md` + **git-hooks-fallback (единственный без native)**
   - `adapters/opencode.sh` → `AGENTS.md` + `opencode.json` plugin + TS plugin file
   - `adapters/pi.sh` → `~/.pi/skills/memory-bank/` native + git-hooks fallback (transitional)
   - `adapters/codex.sh` → `AGENTS.md` + `.codex/config.toml` + `.codex/hooks.json` (experimental)

4. **Tests expansion:**
   - 2 теста per client × 7 = 14
   - \+ 1 тест git-hooks-fallback (kilo scenario)
   - \+ 1 тест AGENTS.md shared между opencode/codex/pi (ownership tracking)
   - \+ 1 тест `experimental.session.compacting` mapping в OpenCode
   - \+ 1 тест Cursor `hooks.json` CC-reuse (smoke: наш `mb-session-end.sh` вызывается из Cursor `sessionEnd`)
   - **Target: ≥18 e2e tests**

5. **DoD дополнение:**
   - `adapters/git-hooks-fallback.sh` idempotent install
   - `post-commit` hook не ломает existing hooks (chain)
   - `hooks.json` schema для Codex валидируется JSON schema
   - OpenCode TypeScript plugin компилируется без deps beyond peer `@opencode/plugin`

## Open questions to resolve during implementation

1. **Codex `hooks.json` schema** — experimental, формат может меняться. Pin к версии Codex CLI в docs. Provide fallback (только AGENTS.md) если hooks API breaks.
2. **Pi Skills API stability** — check recent PRs в `badlogic/pi-mono` перед implementation. Если API в active breaking changes — default на `AGENTS.md` + git-fallback.
3. **OpenCode plugin packaging** — bundled vs published npm. Для Stage 8 → bundled (файл в проекте), для v3.1 возможно npm `@fockus/opencode-memory-bank`.
4. **Windsurf Cascade hooks JSON merge** — 3 levels (user/workspace/project). Наш adapter пишет в project-level. Проверить конфликты с existing hooks пользователя.
5. **Cline hook discovery cache** — как инвалидировать после install? Проверить докой и CLI command.

## Decisions locked после research (updated)

- ✅ **Cursor — native hooks (не git-fallback!)**. `.cursor/hooks.json` совместим с Claude Code форматом → direct reuse `hooks/*.sh`
- ✅ **Kilo — единственный client требующий git-hooks-fallback.** Follow FR #5827 для upgrade
- ✅ OpenCode `experimental.session.compacting` — используем для PreCompact equivalent (unique advantage)
- ✅ Cursor `preCompact` — нативный, 1-к-1 имя совпадает с нашим (ещё один unique match)
- ✅ Codex hooks используем, но документируем "experimental, may change" warning
- ✅ Pi — dual-path (native Skill preferred, git-fallback as belt-and-suspenders)
- ✅ `AGENTS.md` — shared между OpenCode/Codex/Pi(fallback)/Cline(auto-read), manifest per-client ownership

## Next step

Обновить `plans/2026-04-20_refactor_skill-v2.1.md` Stage 8:
- **Cursor — не в git-fallback списке**, native `.cursor/hooks.json` с CC-reuse
- Per-adapter spec с native hooks details (6 из 7 клиентов имеют native)
- Добавить `adapters/git-hooks-fallback.sh` как отдельный пункт (**только для Kilo** mandatory)
- Tests target: 14 → ≥18
- DoD дополнить pin-version notes для experimental APIs (Codex hooks, Pi Skills)
- Highlight "Cursor-CC hooks compatibility" как killer feature в docs

После update плана → реализация adapters. Порядок implementation (от простого к сложному):
1. **Cursor** (native hooks CC-compat — **самый простой adapter!** Просто `hooks.json` c references)
2. **Kilo** (rules + git-fallback — без hooks complexity)
3. **Cline** (rules + shell hooks — формат знакомый)
4. **Windsurf** (rules + Cascade JSON hooks)
5. **OpenCode** (AGENTS.md + TypeScript plugin — самый богатый API)
6. **Codex** (AGENTS.md + config.toml + hooks.json experimental)
7. **Pi** (Skills API + fallback path)

---

**Sources:**
- [Cursor Rules docs](https://cursor.com/docs/context/rules)
- **[Cursor Hooks docs](https://cursor.com/docs/hooks)** — **Cursor 1.7+ полный hooks API, совместимый с Claude Code**
- [Cursor 1.7 Hooks announcement (InfoQ)](https://www.infoq.com/news/2025/10/cursor-hooks/)
- [Windsurf Cascade Hooks](https://docs.windsurf.com/windsurf/cascade/hooks)
- [Cline Rules docs](https://docs.cline.bot/features/cline-rules)
- [Kilo Custom Rules](https://kilo.ai/docs/agent-behavior/custom-rules) + [FR #5827 hooks](https://github.com/Kilo-Org/kilocode/issues/5827)
- [OpenCode Plugins](https://opencode.ai/docs/plugins/)
- [Pi-mono (badlogic/pi-mono)](https://github.com/badlogic/pi-mono)
- [Codex Advanced Config](https://developers.openai.com/codex/config-advanced) + [AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md)
