# Changelog

Все значимые изменения документируются здесь. Формат — [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), версионирование — [SemVer](https://semver.org/spec/v2.0.0.html).

## [3.0.0-rc1] — 2026-04-20

### Repository moved

Этот skill переехал в новый публичный репозиторий: **[`fockus/skill-memory-bank`](https://github.com/fockus/skill-memory-bank)**. Старое имя `claude-skill-memory-bank` отражало только один из 8 поддерживаемых клиентов и стало misleading.

**Migration guide:** [docs/repo-migration.md](docs/repo-migration.md).

Historical releases (`v1.x`, `v2.0.0`, `v2.1.0`, `v2.2.0`) остаются доступны в старом репозитории. `v3.0.0` и далее публикуются в новом.

### Added

- **Stage 8 — Cross-agent adapters** (7 clients beyond Claude Code): Cursor (CC-compat hooks), Windsurf (Cascade), Cline (`.clinerules/hooks/`), Kilo (+ git-hooks fallback), OpenCode (TS plugin с `experimental.session.compacting`), Codex (experimental hooks), Pi Code (dual-mode). See `docs/cross-agent-setup.md`.
- **`adapters/_lib_agents_md.sh`** — refcount-based shared `AGENTS.md` ownership via `.mb-agents-owners.json`. Enables safe coexistence of OpenCode / Codex / Pi installs.
- **`adapters/git-hooks-fallback.sh`** — universal `.git/hooks/` installer (post-commit auto-capture, pre-commit `<private>` warnings, chain pattern preserves user hooks).
- **`install.sh --clients <list>`** — non-interactive multi-client install. Valid: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`.
- **`docs/cross-agent-setup.md`** — complete per-client cheatsheet + hook capability matrix + troubleshooting FAQ.
- **`docs/repo-migration.md`** — upgrade instructions for existing users.

### Changed

- Repository name: `claude-skill-memory-bank` → `skill-memory-bank`.
- Install target directory: `~/.claude/skills/skill-memory-bank/` (was `claude-skill-memory-bank/`).
- `mb-upgrade.sh` tracks new origin URL.

### Tests

- **340+/340+ bats + e2e green** (+90 adapter bats, +10 install-clients e2e over v2.2.0).

---

## [2.2.0] — 2026-04-20

Knowledge-reach release: cold-start через JSONL-импорт, code graph для 6 языков, tags normalization через controlled vocabulary.

### Added

- **`/mb import --project <path> [--since] [--apply]`** (`scripts/mb-import.py`) — bootstrap Memory Bank из Claude Code транскриптов (`~/.claude/projects/<slug>/*.jsonl`). Извлекает daily-grouped `progress.md` секции и arch-discussion notes (≥3 consecutive assistant messages >1K chars). Dedup SHA256(timestamp + first 500 chars), resume через `.import-state.json`. PII auto-wrap (email + API-key → `<private>`) интегрирован с v2.1 Stage 3. `--dry-run` default.
- **`/mb graph [--apply] [src_root]`** (`scripts/mb-codegraph.py`) — code graph для Python (stdlib `ast`, always-on) + Go / JavaScript / TypeScript / Rust / Java (через tree-sitter, opt-in). Nodes = module/function/class, edges = import/call/inherit. Output: `codebase/graph.json` (JSON Lines, grep/jq friendly) + `codebase/god-nodes.md` (top-20 by degree). SHA256 incremental cache per-file. `HAS_TREE_SITTER` флаг обеспечивает graceful degrade без grammars. Skipped dirs: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`.
- **`/mb tags [--apply] [--auto-merge]`** (`scripts/mb-tags-normalize.sh`) — Levenshtein-based synonym detection + merge через controlled vocabulary. Distance ≤2 detection, ≤1 для `--auto-merge`. Vocabulary в `.memory-bank/tags-vocabulary.md` (user-editable) → fallback на `references/tags-vocabulary.md` (35 default tags). Exit 2 если найдены unknown tags (drift signal).
- **`references/tags-vocabulary.md`** — template с 35 default тегами (Core: arch/auth/bug/perf/refactor/test/...; Process: debug/review/post-mortem/adr/spike; Workflow: blocked/todo/wip/imported/discussion).
- **`mb-index-json.py`** — авто-kebab-case для тегов: `FooBar → foo-bar`, `AUTH → auth`, `someThing → some-thing`. Dedup preserving order. Source files не трогаются — только index.

### Changed

- **`mb-codegraph.py`** — Python-only v1 расширен tree-sitter adapter для 5 новых языков. Same node/edge schema. Lazy parser loading per language via `_TS_PARSERS` cache.
- **`commands/mb.md`** — секции `/mb import`, `/mb graph`, `/mb tags` с полными примерами, dogfood-outputs, ограничениями.
- **`install.sh`** — печатает hint для tree-sitter extras.

### Tests

- pytest: **96** (было 44 после v2.1) — +17 test_import, +21 test_codegraph (Python), +14 test_codegraph_ts (tree-sitter).
- bats: **208** (было 194) — +14 test_tags_normalize.
- shellcheck: 0 warnings. ruff: all passed.

### Gate v2.2 — passed ✅

1. ✅ `/mb import` на реальном JSONL (2573 events) — **0.127s** (target ≤30s).
2. ✅ `mb-codegraph.py` на `scripts/` — **0.068s** для 60 nodes + 487 edges (target ≤30s).
3. ✅ Tags normalization: `sqlite_vec → sqlite-vec` auto-merged distance=1, 2 notes rewritten. Unknown tag → exit 2 drift signal works.
4. ✅ Full regression: 96 pytest + 208 bats + ruff + shellcheck clean.
5. ✅ VERSION 2.2.0, CHANGELOG updated.

### ADR pivots

- **ADR-006 обновлён (Stage 6.5):** изначально tree-sitter был deferred opt-in. После feedback пользователя ("часто работаю на Node/Go") — реализовано в v2.2, с graceful degrade при отсутствии grammars. Python path остался zero-dep. См. BACKLOG (Stage 6.5 shipped entry).

### Deferred to v3.x backlog

- Haiku-powered compression для `/mb import` summaries (сейчас deterministic first+last chars).
- Debug-session detection в `/mb import` для `lessons.md`.
- Type inference в `/mb graph` (edges сейчас name-based, не различают модули с одноимёнными функциями).
- tree-sitter grammars для C/C++/Ruby/PHP/Kotlin/Swift (добавить по запросу через `_TS_LANG_CONFIG`).

## [2.1.0] — 2026-04-20

Hardening release: auto-capture при забытом `/mb done`, detection drift без AI, защита PII в заметках, status-based decay для старых планов и заметок.

### Added

- **Auto-capture SessionEnd hook** (`hooks/session-end-autosave.sh`) — если сессия закрылась без `/mb done`, hook добавляет placeholder-запись в `progress.md`. Lock-файл `.memory-bank/.session-lock` пишется командой `/mb done` → hook видит свежий lock (<1h) и пропускает auto-capture. `MB_AUTO_CAPTURE` env: `auto` (default) / `strict` / `off`. Concurrent-safe через `.auto-lock` (30s TTL). Идемпотентен по session_id.
- **Drift checkers без AI** (`scripts/mb-drift.sh`) — 8 deterministic checkers (path, staleness, script_coverage, dependency, cross_file, index_sync, command, frontmatter). Output: `drift_check_<name>=ok|warn|skip` + `drift_warnings=N`. Exit 0 если 0 warnings, 1 иначе. `agents/mb-doctor.md` Step 0 = `mb-drift.sh` → LLM call только если `drift_warnings > 0`. Экономит AI-токены.
- **PII markers `<private>...</private>`** в notes — содержимое блоков не попадает в `index.json` (summary + tags filtered), при `mb-search` заменяется на `[REDACTED]` (inline) или `[REDACTED match in private block]` (multi-line). Unclosed `<private>` fail-safe: хвост до EOF считается приватным. Entries получают `has_private: bool` флаг. `--show-private` требует `MB_SHOW_PRIVATE=1` env (double-confirmation). `hooks/file-change-log.sh` warnит при Write/Edit `.md` файла с `<private>` блоком.
- **Compaction decay `/mb compact`** (`scripts/mb-compact.sh`) — status-based archival: требует **age > threshold AND done-signal**. Active планы (not done) **НЕ архивируются** даже >180d — warning only. Done-signal (OR): файл физически в `plans/done/`, ИЛИ метка `✅`/`[x]` в `checklist.md`, ИЛИ упоминание как "завершён|done|closed|shipped" в `progress.md`/`STATUS.md`. Notes — `importance: low` + mtime >90d + нет референсов в core файлах. `--dry-run` (default) reasoning only, `--apply` выполняет + touch `.last-compact`. Entries из `notes/archive/` получают `archived: bool` флаг. `mb-search --include-archived` — opt-in для поиска в архиве.

### Changed

- **`agents/mb-doctor.md`** — Step 0 теперь вызов `mb-drift.sh`; LLM-шаги (1-4) выполняются только при drift_warnings > 0 или `doctor-full`.
- **`scripts/mb-index-json.py`** — парсер `<private>` блоков, `has_private: bool` + `archived: bool` fields в entry schema.
- **`scripts/mb-search.sh`** — span-aware Python filter для REDACTED replacement. `--show-private` + `--include-archived` флаги.
- **`settings/hooks.json`** — добавлен SessionEnd event для auto-capture.
- **`commands/mb.md`** — `/mb done` пишет `.session-lock`. Секция `/mb compact` с полной status-based логикой и примерами.
- **`SKILL.md`** — секции "Private content" и "Auto-capture".
- **`references/metadata.md`** — schema extended с `has_private` + `archived` fields.

### Tests

- bats: **194** (20 test_compact + 4 test_search_archived + 5 test_search_private + 20 test_drift + 12 test_auto_capture + регрессии).
- pytest: **44** (7 PII + 2 archived + регрессии).
- e2e: 18 install/uninstall (включая SessionEnd hook roundtrip).
- shellcheck: 0 warnings (SC1091 info expected для `source _lib.sh`).
- ruff: all passed.

### Gate v2.1 — passed ✅

1. ✅ Auto-capture end-to-end: симулированный SessionEnd → `progress.md` обновлён без `/mb done`.
2. ✅ `mb-drift.sh` на broken fixture: 7 warnings из 8 categories (≥5 target).
3. ✅ PII security smoke: `TOP-SECRET-LEAK-CHECK-GATE21` внутри `<private>` → **0 matches** в `index.json`.
4. ✅ `/mb compact` dogfood: живой banks чистый (0 candidates), artificial 150d done-plan → archive, 150d active-plan → не archive (safety works).
5. ✅ CI matrix `[macos, ubuntu]` × (bats + e2e + pytest) green.

### Deferred to backlog

- LLM upgrade для auto-capture (сейчас append-only, детали дочитывает `/mb start` из JSONL).
- `/mb done` weekly prompt для compaction check.
- Pre-commit drift hook как отдельный file (YAGNI, документирован в `references/templates.md`).

## [2.0.0] — 2026-04-19

Крупный рефакторинг: skill становится language-agnostic, tested, CI-covered, integrated с экосистемой Claude Code. Три концепта под одной крышей: **Memory Bank + RULES + dev toolkit**.

### Added

- **Language detection (12 стеков)**: Python, Go, Rust, Node/TypeScript, Java, Kotlin, Swift, C/C++, Ruby, PHP, C#, Elixir. `scripts/mb-metrics.sh` выдаёт key=value метрики для любого из них.
- **Override для проектных метрик**: `.memory-bank/metrics.sh` (приоритет 1 над auto-detect).
- **`scripts/_lib.sh`** — общие утилиты (workspace resolver, slug, collision-safe filename, detect_stack/test/lint/src_glob). 7 функций, 36 bats-тестов.
- **`scripts/mb-plan-sync.sh`** и **`scripts/mb-plan-done.sh`** — автоматизация консистентности plan↔checklist↔plan.md через маркеры `<!-- mb-stage:N -->`.
- **`scripts/mb-upgrade.sh`** — `/mb upgrade` для самообновления skill из GitHub (git fetch → prompt → ff-only pull + re-install).
- **`scripts/mb-index-json.py`** — прагматичный index для `notes/` (frontmatter) + `lessons.md` (H3 маркеры). Atomic write. PyYAML opt-in с fallback.
- **`mb-search --tag <tag>`** — фильтрация по тегам через `index.json`.
- **`/mb init [--minimal|--full]`** — единая инициализация. `--full` (default) = `.memory-bank/` + `RULES.md` copy + auto-detect стека + `CLAUDE.md` + optional `.planning/` symlink.
- **`/mb map [focus]`** — сканирование кодовой базы и генерация `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`.
- **`/mb context --deep`** — полный codebase-контент (default = 1-line summary).
- **Правила Frontend (FSD)** и **Mobile (iOS + Android)** в `rules/RULES.md` и `rules/CLAUDE-GLOBAL.md`.
- **`MB_ALLOW_NO_VERIFY=1`** — bypass для `--no-verify` в `block-dangerous.sh`.
- **Log rotation** для `file-change-log.sh`: >10 MB → `.log.1 → .log.2 → .log.3`.
- **GitHub Actions** `.github/workflows/test.yml`: matrix `[ubuntu-latest, macos-latest]` × (bats + e2e + pytest) + lint job (shellcheck + ruff).
- **148 bats-тестов** (unit + e2e + hooks + search-tag), **35 pytest-тестов**, **94% total coverage**.

### Changed

- **`codebase-mapper` → `mb-codebase-mapper`** (MB-native): output path `.planning/codebase/` → `.memory-bank/codebase/`; 770 строк → 316 (−59%); 6 шаблонов → 4 (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS), каждый ≤70 строк.
- **`/mb update` и `mb-doctor`** больше не хардкодят `pytest`/`ruff`/`src/taskloom/` — используют `mb-metrics.sh`.
- **`SKILL.md` frontmatter** — `user-invocable: false` (невалидное поле) заменено на `name: memory-bank` с описанием three-in-one concept.
- **`Task(...)` → `Agent(subagent_type=...)`** во всех skill-файлах. Grep-проверка: 0 вхождений `Task(`.
- **`mb-doctor`** чинит рассинхроны приоритетно через `mb-plan-sync.sh`/`mb-plan-done.sh`, Edit — только для семантических проблем.
- **`install.sh`** — всегда пишет `# [MEMORY-BANK-SKILL]` маркер при создании нового `CLAUDE.md` (раньше — только при merge в существующий).
- **`mb-manager actualize`** — вызывает `mb-index-json.py` вместо ручного Write на `index.json`.
- **`file-change-log.sh`** — убран `pass\s*$` из placeholder-regex (false-positive); placeholder-поиск теперь вне Python docstrings.
- **`install.sh` banner**: `19 dev commands` → `18 dev commands` (после слияния init-команд).

### Deprecated

- (нет — все deprecations полные в этом релизе; см. Removed)

### Removed

- **`/mb:setup-project`** — слит в `/mb init --full`. Команда `commands/setup-project.md` удалена.
- **Orphan-агент `codebase-mapper`** — заменён на `mb-codebase-mapper`.
- **Хардкод `pytest -q` / `ruff check src/`** в `commands/mb.md` и `agents/mb-doctor.md`.
- **Все `Task(...)` вызовы** в skill-файлах (осталось 0).

### Fixed

- **E2E-found bug #1**: `install.sh` не добавлял маркер `[MEMORY-BANK-SKILL]` при создании **нового** `CLAUDE.md`. Результат: `uninstall.sh` не находил секцию для очистки.
- **E2E-found bug #2**: `uninstall.sh` использовал GNU-only флаг `realpath -m`. На macOS BSD realpath падал. Fix: манифест хранит абсолютные пути, `realpath` не нужен.
- **Node src_glob**: brace-pattern `*.{ts,tsx,js,jsx}` заменён на space-separated для portable grep.
- **mb-note.sh**: коллизия имени (две заметки в одну минуту) теперь → `_2/_3` суффикс (было: `exit 1`).
- **file-change-log false-positives**: bare `pass` в Python, TODO внутри docstring.
- **shellcheck SC1003** в awk-блоке hook'а — переписан через `index()` без nested single-quote escapes.

### Security

- **`block-dangerous.sh`** обновлён с `MB_ALLOW_NO_VERIFY=1` explicit-opt-in override — раньше `--no-verify` блокировался наглухо без safe-escape.
- **secrets-detection** в `file-change-log.sh` продолжает работать (`password|secret|api_key|token|private_key` в source-коде).

### Infrastructure

- **Dogfooding**: сам skill использует `.memory-bank/` в своём репозитории. План рефактора v2 лежит в `.memory-bank/plans/`, сессии закрываются через `/mb done`.
- **VERSION marker**: `2.0.0-dev` → `2.0.0` пишется install.sh в `~/.claude/skills/memory-bank/VERSION`.
- **CI-зелёный** на macOS + Ubuntu, 0 shellcheck warnings, ruff all passed.

---

## [1.0.0] — 2025-10-XX (pre-refactor baseline)

- Initial Memory Bank skill: `.memory-bank/` structure, `/mb` roadmap-команда, 4 агента, 2 hooks, 19 commands.
- Python-first: хардкод `pytest`, `ruff`, `src/taskloom/`.
- Orphan-артефакты от GSD: `codebase-mapper`, `.planning/`.
- 0 автоматических тестов.

[2.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v2.0.0
[1.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v1.0.0
