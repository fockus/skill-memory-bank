# claude-skill-memory-bank: Статус проекта

## Текущая фаза
**Phase: v2.1 planning → execution.** После обратной связи внешнего ревью составлен план на 10 этапов через 3 минорных релиза: v2.1 (hardening) → v2.2 (knowledge reach) → v3.0 (public). Профиль — **гибрид C** (personal сейчас, public позже).

План: `plans/2026-04-20_refactor_skill-v2.1.md` (10 этапов, DoD SMART, TDD, риски, 3 Gate).

Three-in-one skill для Claude Code: (1) Long-term project memory через `.memory-bank/`, (2) global dev rules (TDD, Clean Architecture для backend, FSD для frontend, Mobile UDF+Clean для iOS/Android, SOLID, Testing Trophy), (3) dev toolkit из 18 команд.

## Ключевые метрики (v2.0.0 baseline)
- Shell-скрипты: **11**, Python-скрипты: **2**, Агенты: **4**, Команды: **18**
- Bats: **148/148 green**, Pytest: **35/35 green**, Coverage: **94%**, Shellcheck: **0**
- CI: matrix `[ubuntu-latest, macos-latest]` × (bats + e2e + pytest) + lint
- **VERSION**: **2.0.0** (released, public на GitHub, tag `v2.0.0`)

## Roadmap

### ✅ v2.0.0 (released 2026-04-20)
- 10 этапов рефактора завершены, план в `plans/done/`
- Language-agnostic (12 стеков), cross-platform CI, TDD-covered
- Three-in-one: MB + RULES + dev toolkit

### ⬜ v2.1 — Auto-capture + hardening (текущая фаза)
- **Этап 1:** Auto-capture через SessionEnd hook (lock-файл, Haiku, `MB_AUTO_CAPTURE` флаг)
- **Этап 2:** Drift checkers без AI (`mb-drift.sh`, 8 deterministic чекеров)
- **Этап 3:** PII markers `<private>...</private>` (exclude из index, REDACTED при search)
- **Этап 4:** Compaction decay (`/mb compact`, plans>60d → BACKLOG, notes low>90d → archive)

### ⬜ v2.2 — Knowledge reach
- **Этап 5:** Import from Claude Code JSONL (`~/.claude/projects/*.jsonl` → bootstrap MB)
- **Этап 6:** Tree-sitter code graph (AST → graph.json, god-nodes, wiki, incremental)
- **Этап 7:** Tags normalization (closed vocabulary, Levenshtein consolidation)

### ⬜ v3.0 — Public release
- **Этап 8:** Cross-agent output (Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code = [pi-coding-agent](https://github.com/badlogic/pi-mono))
- **Этап 9:** pipx/PyPI distribution (`pipx install memory-bank-skill`) + Homebrew tap secondary + Anthropic plugin manifest tertiary

### ⬜ v3.1+ backlog
- **Benchmarks** (LongMemEval + custom 10 scenarios) — отложены по решению пользователя 2026-04-20, вернуться после v3.0 с реальной baseline
- sqlite-vec semantic search (после Gate v3.0, если keyword+tags+codegraph окажутся insufficient)
- i18n error-сообщений
- Native memory bridge (программная синхронизация с Claude Code auto memory)
- Viewer dashboard (если adoption потребует)

### ❌ Отклонено после ревью (YAGNI / дубль existing)
- Hash-based IDs, KB compilation, GWT в DoD, Schema drift, `/mb debug`, REST API / daemon

## Gate v2 — passed ✅
1. ✅ Language coverage: 12 стеков
2. ✅ Cross-platform: CI matrix macos+ubuntu
3. ✅ Ecosystem: 0 `Task(` legacy, coexistence documented
4. ✅ DRY + tested: `_lib.sh` в 5+ скриптах, 94% Python coverage
5. ✅ UX: `/mb init [--minimal|--full]`, `mb-codebase-mapper`, `/mb context`
6. ✅ Dogfooding: skill использует `.memory-bank/`, план перенесён в `plans/done/`
7. ✅ Versioning: CHANGELOG v1→v2, migration guide, VERSION 2.0.0, GitHub Release

## Gate v2.1 (после этапов 1-4)
- ⬜ Auto-capture end-to-end работает (фейковая SessionEnd → progress.md обновлён без `/mb done`)
- ⬜ `mb-drift.sh` ловит ≥5 категорий на broken fixture, 0 warnings на live banks
- ⬜ PII security smoke-test: `<private>` содержимое не утекает в `index.json`
- ⬜ `/mb compact` dogfood успешно выполнен
- ⬜ CI green, VERSION 2.1.0, tag `v2.1.0`

## Gate v2.2 (после этапов 5-7)
- ⬜ `/mb import` bootstrap реального JSONL за ≤30 сек
- ⬜ `mb-codegraph.py` ≤30 сек на этом repo, ≥5× экономия токенов vs grep
- ⬜ Tags normalization: auto-merge distance ≤1, drift-warn для unknown tags
- ⬜ CI green, VERSION 2.2.0, tag `v2.2.0`

## Gate v3.0 (после этапов 8-9)
- ⬜ 6 client adapters (Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code) с e2e coverage
- ⬜ `pipx install memory-bank-skill && memory-bank install` работает из clean env
- ⬜ Homebrew tap `fockus/homebrew-tap/memory-bank` работает
- ⬜ `memory-bank self-update` поднимает версию через `pipx upgrade`
- ⬜ CHANGELOG v2→v3, VERSION 3.0.0, tag `v3.0.0`, GitHub Release

## Решённые вопросы (2026-04-20)
- ✅ **"Pi" в cross-agent** = [pi-coding-agent от Mario Zechner](https://github.com/badlogic/pi-mono) — 6-й adapter в Этапе 8 (preferred: native Pi Skill; fallback: `AGENTS.md`)
- ✅ **Distribution** — pipx/PyPI primary, Homebrew tap secondary, Anthropic plugin tertiary. npm убран (overhead без value для mix-stack). ADR-008
- ✅ **Benchmarks** — отложены в v3.1+ backlog (user decision)
- ✅ **Имена свободны**: `memory-bank-skill` (PyPI), `@fockus/memory-bank` (npm, reserved), `fockus/homebrew-tap/memory-bank` (создать перед release)

## Новые open questions
1. **`fockus/homebrew-tap` repo** — создать заранее или перед v3.0 release?
2. **PyPI OIDC trusted publisher** — однократная настройка пользователем в PyPI web UI после создания проекта
3. **Windows support** — explicit skip с hint "Use WSL" (default) или попытка Git Bash/MSYS2?
