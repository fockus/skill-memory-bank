# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versioning follows [SemVer](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

---

## [3.0.0] — 2026-04-20

First stable 3.x release. Combines the work from the `3.0.0-rc1` / `rc2` / `rc3`
candidates: native cross-agent install (Claude Code, Codex, Cursor, OpenCode),
five-artifact global parity for Cursor, byte-level idempotent `install.sh`,
and the `memory-bank install` / `memory-bank uninstall` / `memory-bank doctor`
CLI. Install via `pipx install memory-bank-skill` or `brew install fockus/tap/memory-bank`.

### Fixed (idempotency, promoted from `3.0.0-rc3`)

- **`install.sh` is now byte-level idempotent** — repeat runs on an up-to-date tree create **zero** `.pre-mb-backup.*` files.
  - Root cause: `backup_if_exists()` did an unconditional `mv` on any existing target, and `install_file()` called it without comparing `src` / `dst` content. For localized files (`RULES.md`, Cursor paste-file) a raw `cmp -s src dst` never matched because `dst` had been language-substituted.
  - Observed damage before the fix: 14 historic installs → 1628 accumulated `.pre-mb-backup.*` files; a single "clean" reinstall generated 48 backups, 37 of them byte-identical to the active file.
- **New helpers** in `install.sh`:
  - `install_file()` short-circuits via `cmp -s "$src" "$dst"` when content is already identical.
  - `backup_if_exists()` accepts an optional 2nd arg `expected_content_path` and returns `2` (skip marker) on content match.
  - `install_file_localized()` — composes expected post-install content in a temp file (`cp src` + `localize_path_inplace`), compares to `dst` via `cmp -s`, skips backup+write on match. Used for `RULES.md` in Step 1.
  - `localize_path_inplace()` — substitution helper without the existence shortcut.
  - `install_cursor_user_rules_paste()` rewritten with a compose-to-tmp + `cmp -s` skip instead of unconditional overwrite.
- **Manifest `.backups[]`** is now filtered via `os.path.exists` — stale refs from user-cleaned `.pre-mb-backup.*` files are dropped instead of accumulating across installs.
- **`tests/e2e/test_install_idempotent.bats`** — 5 bats scenarios: zero backups on repeat install, exactly-one backup per real content diff, zero backups after external delete, language-swap backs up only localize-target files, manifest lists only existing backup paths.

**Result**: repeat install on an up-to-date tree → 0 backups. Language swap (`--language en` → `--language ru`) → exactly 2 backups (`RULES.md` + `memory-bank-user-rules.md`) and nothing else.

### Added

- **Cursor global parity — five artifacts under `~/.cursor/` are now installed unconditionally** (without `--clients cursor`):
  - `~/.cursor/skills/memory-bank/` — symlink to the canonical skill bundle (Cursor auto-discovers personal skills).
  - `~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` — three global hooks (`sessionEnd` / `preCompact` / `beforeShellExecution`); each entry is marked `_mb_owned: true`, while user hooks on the same events are preserved.
  - `~/.cursor/commands/*.md` — user-level slash commands mirroring the skill `commands/` directory.
  - `~/.cursor/AGENTS.md` — managed section with unique `memory-bank-cursor:start/end` markers, preserving user content above and below.
  - `~/.cursor/memory-bank-user-rules.md` — paste-ready bundle for **Settings → Rules → User Rules** (Cursor has no file API for global User Rules; this is a one-time manual step per machine). The post-install hint prints `pbcopy`/`xclip` commands.
- **`install.sh` helpers**: `cursor_agents_section()`, `install_cursor_global_agents()`, `install_cursor_user_rules_paste()`, `install_cursor_global_hooks()` (with jq-based `hooks.json` merge similar to Codex). `ensure_skill_aliases()` now creates the `~/.cursor/skills/memory-bank` alias.
- **`uninstall.sh` Cursor branches**: preserve `~/.cursor/AGENTS.md` and `~/.cursor/hooks.json` from manifest-removal (managed merged files), remove only the memory-bank section and `_mb_owned` entries, delete `memory-bank-user-rules.md` and the `skills/memory-bank` alias, and `rmdir` empty `~/.cursor/{skills,hooks,commands}` directories.
- **`tests/e2e/test_cursor_global.bats`** — 17 bats scenarios: install creates all five artifacts, idempotency, preserve-user-content in `AGENTS.md` + `hooks.json`, clean uninstall.
- **`tests/pytest/test_cli.py::test_cli_install_uninstall_smoke_with_cursor_global`** — pytest smoke: real `install.sh` / `uninstall.sh` run in sandboxed `$HOME` with Cursor steps.
- **Docs**:
  - `SKILL.md` — Cursor promoted to the "native full support" tier, plus a new **Host-specific notes → Cursor** subsection with the five-artifact table and paste flow.
  - `docs/cross-agent-setup.md` — supported clients table, **Cursor (full global parity + project adapter)** section, resource availability matrix with a Cursor column and a "Global rules" row, troubleshooting Q&A for User Rules.
  - `README.md` — global install hint updated (Cursor included in baseline `memory-bank install`), new "Cursor-only quick start" section, adapter table extended with global artifacts.

### Fixed

- **`adapters/cursor.sh` — removed duplicate `# Global Rules` heading** in `.cursor/rules/memory-bank.mdc`. Previously the script wrote its own `# Global Rules` and then concatenated `rules/RULES.md`, which starts with the same heading, so the MDC file ended up with two identical H1s.

### Changed

- `install.sh` / `uninstall.sh` — added constants `CURSOR_DIR`, `CURSOR_SKILL_ALIAS`, `CURSOR_USER_RULES_FILE`, `CURSOR_START_MARKER` / `CURSOR_END_MARKER` (independent from Codex markers — allowing coexistence without conflicts in `~/.codex/AGENTS.md` vs `~/.cursor/AGENTS.md`).

### Added (rolled up from prior Unreleased)

- **Interactive client picker in `install.sh`** — when `--clients` is not set and stdin is a TTY, a multi-select menu is shown for 8 clients (`claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`). Accepts numbers, names, `all`, or empty input (`claude-code`). Suppressed by `--non-interactive` or non-TTY stdin.
- **`install.sh --non-interactive`** — explicit interactive bypass for CI / scripted installs.
- **Env `MB_CLIENTS`** — alternate way to set clients (same semantics as `--clients`), useful in Docker / pipx wrappers.
- **`memory-bank install --non-interactive`** — forwards the flag from the Python CLI.
- **`/mb install` subcommand** (section in `commands/mb.md`) — installs adapters from inside Claude Code / OpenCode / Codex. Uses `AskUserQuestion` for multi-select in CC and inline prompt in other agents. The `/mb` namespace protects against collisions with other skills.
- **Windows compromise — Git Bash / WSL support**:
  - `cli.py` no longer hard-fails on Windows. Added `find_bash()` with priority order: `MB_BASH` env override → `bash.exe` on PATH → `C:\Program Files\Git\bin\bash.exe` → WSL fallback.
  - `system32\bash.exe` (WSL launcher shim) is ignored in favor of Git Bash / explicit WSL.
  - `memory-bank doctor` now prints the resolved bash path on any platform.
  - Missing bash on Windows now yields an actionable install hint (`winget` / WSL).
- **README: full command reference** — two tables (18 top-level slash commands + 20 `/mb` subcommands), replacing the previous partial list of 23 lines.
- **README: 3 ways to install cross-agent adapters** — interactive menu, CLI flags, `/mb install` from inside the agent.

### Changed (rolled up from prior Unreleased)

- `memory-bank install / uninstall / init / doctor` — removed `require_posix()` calls; now work on Windows when bash is available.
- `tests/pytest/test_cli.py` — updated for the new platform model (29 tests, including 9 new `find_bash()` discovery tests + WSL wrapper mode).
- `tests/bats/test_install_interactive.bats` — new file with 13 tests for CLI flags, validation, env overrides.

### Docs (rolled up from prior Unreleased)

- README: Platform matrix expanded (macOS native / Linux native / Windows Git Bash / Windows WSL / Windows without bash — the last one with a hint).
- README: command tables numbered as "18 top-level + 20 `/mb` subcommands".

---

## [3.0.0-rc1] — 2026-04-20

### Repository moved

This skill moved to a new public repository: **[`fockus/skill-memory-bank`](https://github.com/fockus/skill-memory-bank)**. The old name `claude-skill-memory-bank` described only one of the 8 supported clients and had become misleading.

**Migration guide:** [docs/repo-migration.md](docs/repo-migration.md).

Historical releases (`v1.x`, `v2.0.0`, `v2.1.0`, `v2.2.0`) remain available in the old repository. `v3.0.0` and later are published in the new one.

### Added

- **Stage 8 — Cross-agent adapters** (7 clients beyond Claude Code): Cursor (CC-compat hooks), Windsurf (Cascade), Cline (`.clinerules/hooks/`), Kilo (+ git-hooks fallback), OpenCode (TS plugin with `experimental.session.compacting`), Codex (experimental hooks), Pi Code (dual-mode). See `docs/cross-agent-setup.md`.
- **`adapters/_lib_agents_md.sh`** — refcount-based shared `AGENTS.md` ownership via `.mb-agents-owners.json`. Enables safe coexistence of OpenCode / Codex / Pi installs.
- **`adapters/git-hooks-fallback.sh`** — universal `.git/hooks/` installer (post-commit auto-capture, pre-commit `<private>` warnings, chain pattern preserving user hooks).
- **`install.sh --clients <list>`** — non-interactive multi-client install. Valid: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`.
- **`docs/cross-agent-setup.md`** — complete per-client cheatsheet + hook capability matrix + troubleshooting FAQ.
- **`docs/repo-migration.md`** — upgrade instructions for existing users.

### Changed

- Repository name: `claude-skill-memory-bank` → `skill-memory-bank`.
- Install target directory: `~/.claude/skills/skill-memory-bank/` (previously `claude-skill-memory-bank/`).
- `mb-upgrade.sh` now tracks the new origin URL.

### Tests

- **340+/340+ bats + e2e green** (+90 adapter bats, +10 install-clients e2e over v2.2.0).

---

## [2.2.0] — 2026-04-20

Knowledge-reach release: cold-start through JSONL import, code graph for 6 languages, tags normalization through a controlled vocabulary.

### Added

- **`/mb import --project <path> [--since] [--apply]`** (`scripts/mb-import.py`) — bootstrap Memory Bank from Claude Code transcripts (`~/.claude/projects/<slug>/*.jsonl`). Extracts daily-grouped `progress.md` sections and arch-discussion notes (≥3 consecutive assistant messages >1K chars). Dedup via SHA256(timestamp + first 500 chars), resume through `.import-state.json`. PII auto-wrap (email + API-key → `<private>`) integrated with v2.1 Stage 3. `--dry-run` by default.
- **`/mb graph [--apply] [src_root]`** (`scripts/mb-codegraph.py`) — code graph for Python (stdlib `ast`, always-on) + Go / JavaScript / TypeScript / Rust / Java (through tree-sitter, opt-in). Nodes = module/function/class, edges = import/call/inherit. Output: `codebase/graph.json` (JSON Lines, grep/jq friendly) + `codebase/god-nodes.md` (top-20 by degree). SHA256 incremental cache per file. `HAS_TREE_SITTER` flag provides graceful degradation without grammars. Skipped dirs: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`.
- **`/mb tags [--apply] [--auto-merge]`** (`scripts/mb-tags-normalize.sh`) — Levenshtein-based synonym detection + merge through a controlled vocabulary. Distance ≤2 detection, ≤1 for `--auto-merge`. Vocabulary in `.memory-bank/tags-vocabulary.md` (user-editable) → fallback to `references/tags-vocabulary.md` (35 default tags). Exit 2 when unknown tags are found (drift signal).
- **`references/tags-vocabulary.md`** — template with 35 default tags (Core: arch/auth/bug/perf/refactor/test/...; Process: debug/review/post-mortem/adr/spike; Workflow: blocked/todo/wip/imported/discussion).
- **`mb-index-json.py`** — auto-kebab-case for tags: `FooBar → foo-bar`, `AUTH → auth`, `someThing → some-thing`. Dedup while preserving order. Source files remain untouched — only the index changes.

### Changed

- **`mb-codegraph.py`** — the Python-only v1 path was extended with a tree-sitter adapter for 5 new languages. Same node/edge schema. Lazy parser loading per language through `_TS_PARSERS` cache.
- **`commands/mb.md`** — `/mb import`, `/mb graph`, `/mb tags` sections with full examples, dogfood outputs, and limitations.
- **`install.sh`** — now prints a hint for tree-sitter extras.

### Tests

- pytest: **96** (was 44 after v2.1) — +17 `test_import`, +21 `test_codegraph` (Python), +14 `test_codegraph_ts` (tree-sitter).
- bats: **208** (was 194) — +14 `test_tags_normalize`.
- shellcheck: 0 warnings. ruff: all passed.

### Gate v2.2 — passed ✅

1. ✅ `/mb import` on real JSONL (2573 events) — **0.127s** (target ≤30s).
2. ✅ `mb-codegraph.py` on `scripts/` — **0.068s** for 60 nodes + 487 edges (target ≤30s).
3. ✅ Tags normalization: `sqlite_vec → sqlite-vec` auto-merged at distance=1, 2 notes rewritten. Unknown tag → exit 2 drift signal works.
4. ✅ Full regression: 96 pytest + 208 bats + ruff + shellcheck clean.
5. ✅ VERSION 2.2.0, CHANGELOG updated.

### ADR pivots

- **ADR-006 updated (Stage 6.5):** tree-sitter originally started as deferred opt-in. After user feedback ("I often work with Node/Go") it was implemented in v2.2, with graceful degradation when grammars are absent. The Python path remained zero-dependency. See BACKLOG (Stage 6.5 shipped entry).

### Deferred to v3.x backlog

- Haiku-powered compression for `/mb import` summaries (currently deterministic first+last chars).
- Debug-session detection in `/mb import` for `lessons.md`.
- Type inference in `/mb graph` (edges are currently name-based and do not distinguish modules with same-named functions).
- tree-sitter grammars for C/C++/Ruby/PHP/Kotlin/Swift (add on demand via `_TS_LANG_CONFIG`).

## [2.1.0] — 2026-04-20

Hardening release: auto-capture when `/mb done` is forgotten, drift detection without AI, PII protection in notes, status-based decay for old plans and notes.

### Added

- **Auto-capture SessionEnd hook** (`hooks/session-end-autosave.sh`) — if a session closes without `/mb done`, the hook appends a placeholder entry to `progress.md`. Lock file `.memory-bank/.session-lock` is written by `/mb done` → the hook sees a fresh lock (<1h) and skips auto-capture. `MB_AUTO_CAPTURE` env: `auto` (default) / `strict` / `off`. Concurrent-safe through `.auto-lock` (30s TTL). Idempotent per `session_id`.
- **Drift checkers without AI** (`scripts/mb-drift.sh`) — 8 deterministic checkers (path, staleness, script_coverage, dependency, cross_file, index_sync, command, frontmatter). Output: `drift_check_<name>=ok|warn|skip` + `drift_warnings=N`. Exit 0 when 0 warnings, otherwise 1. `agents/mb-doctor.md` Step 0 = `mb-drift.sh` → LLM call only if `drift_warnings > 0`. Saves AI tokens.
- **PII markers `<private>...</private>`** in notes — block contents do not enter `index.json` (summary + tags filtered), and `mb-search` replaces them with `[REDACTED]` (inline) or `[REDACTED match in private block]` (multi-line). Unclosed `<private>` is fail-safe: tail to EOF is treated as private. Entries get `has_private: bool`. `--show-private` requires `MB_SHOW_PRIVATE=1` env (double confirmation). `hooks/file-change-log.sh` warns when a `.md` file with a `<private>` block is Write/Edit-ed.
- **Compaction decay `/mb compact`** (`scripts/mb-compact.sh`) — status-based archival: requires **age > threshold AND done-signal**. Active plans (not done) are **NOT archived** even if >180d — warning only. Done-signal (OR): file physically under `plans/done/`, OR a `✅`/`[x]` marker in `checklist.md`, OR mentioned as "done|closed|shipped" in `progress.md`/`STATUS.md`. Notes — `importance: low` + mtime >90d + no references in core files. `--dry-run` (default) reasons only; `--apply` executes and touches `.last-compact`. Entries under `notes/archive/` get `archived: bool`. `mb-search --include-archived` is opt-in for archive search.

### Changed

- **`agents/mb-doctor.md`** — Step 0 is now `mb-drift.sh`; LLM steps (1-4) run only when `drift_warnings > 0` or `doctor-full`.
- **`scripts/mb-index-json.py`** — parser for `<private>` blocks, `has_private: bool` + `archived: bool` fields in the entry schema.
- **`scripts/mb-search.sh`** — span-aware Python filter for REDACTED replacement. Added `--show-private` + `--include-archived`.
- **`settings/hooks.json`** — SessionEnd event added for auto-capture.
- **`commands/mb.md`** — `/mb done` writes `.session-lock`. Added `/mb compact` section with full status-based logic and examples.
- **`SKILL.md`** — "Private content" and "Auto-capture" sections.
- **`references/metadata.md`** — schema extended with `has_private` + `archived` fields.

### Tests

- bats: **194** (20 `test_compact` + 4 `test_search_archived` + 5 `test_search_private` + 20 `test_drift` + 12 `test_auto_capture` + regressions).
- pytest: **44** (7 PII + 2 archived + regressions).
- e2e: 18 install/uninstall (including SessionEnd hook roundtrip).
- shellcheck: 0 warnings (SC1091 info expected for `source _lib.sh`).
- ruff: all passed.

### Gate v2.1 — passed ✅

1. ✅ Auto-capture end-to-end: simulated SessionEnd → `progress.md` updated without `/mb done`.
2. ✅ `mb-drift.sh` on broken fixture: 7 warnings across 8 categories (≥5 target).
3. ✅ PII security smoke: `TOP-SECRET-LEAK-CHECK-GATE21` inside `<private>` → **0 matches** in `index.json`.
4. ✅ `/mb compact` dogfood: live bank is clean (0 candidates), artificial 150d done-plan → archived, 150d active-plan → not archived (safety works).
5. ✅ CI matrix `[macos, ubuntu]` × (bats + e2e + pytest) green.

### Deferred to backlog

- LLM upgrade for auto-capture (currently append-only; details are reloaded by `/mb start` from JSONL).
- `/mb done` weekly prompt for compaction checks.
- Pre-commit drift hook as a separate file (YAGNI; documented in `references/templates.md`).

## [2.0.0] — 2026-04-19

Large refactor: the skill becomes language-agnostic, tested, CI-covered, and integrated with the Claude Code ecosystem. Three concepts under one roof: **Memory Bank + RULES + dev toolkit**.

### Added

- **Language detection (12 stacks)**: Python, Go, Rust, Node/TypeScript, Java, Kotlin, Swift, C/C++, Ruby, PHP, C#, Elixir. `scripts/mb-metrics.sh` emits key=value metrics for any of them.
- **Override for project metrics**: `.memory-bank/metrics.sh` (priority 1 over auto-detect).
- **`scripts/_lib.sh`** — shared utilities (workspace resolver, slug, collision-safe filename, detect_stack/test/lint/src_glob). 7 functions, 36 bats tests.
- **`scripts/mb-plan-sync.sh`** and **`scripts/mb-plan-done.sh`** — automate plan↔checklist↔plan.md consistency through `<!-- mb-stage:N -->` markers.
- **`scripts/mb-upgrade.sh`** — `/mb upgrade` self-update for the skill from GitHub (git fetch → prompt → ff-only pull + reinstall).
- **`scripts/mb-index-json.py`** — pragmatic index for `notes/` (frontmatter) + `lessons.md` (H3 markers). Atomic write. PyYAML opt-in with fallback.
- **`mb-search --tag <tag>`** — tag filtering via `index.json`.
- **`/mb init [--minimal|--full]`** — unified initialization. `--full` (default) = `.memory-bank/` + `RULES.md` copy + stack auto-detect + `CLAUDE.md` + optional `.planning/` symlink.
- **`/mb map [focus]`** — scan the codebase and generate `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`.
- **`/mb context --deep`** — full codebase content (default = 1-line summary).
- **Frontend rules (FSD)** and **Mobile (iOS + Android)** in `rules/RULES.md` and `rules/CLAUDE-GLOBAL.md`.
- **`MB_ALLOW_NO_VERIFY=1`** — bypass for `--no-verify` in `block-dangerous.sh`.
- **Log rotation** for `file-change-log.sh`: >10 MB → `.log.1 → .log.2 → .log.3`.
- **GitHub Actions** `.github/workflows/test.yml`: matrix `[ubuntu-latest, macos-latest]` × (bats + e2e + pytest) + lint job (shellcheck + ruff).
- **148 bats tests** (unit + e2e + hooks + search-tag), **35 pytest tests**, **94% total coverage**.

### Changed

- **`codebase-mapper` → `mb-codebase-mapper`** (MB-native): output path `.planning/codebase/` → `.memory-bank/codebase/`; 770 lines → 316 (−59%); 6 templates → 4 (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS), each ≤70 lines.
- **`/mb update` and `mb-doctor`** no longer hardcode `pytest`/`ruff`/`src/taskloom/` — they use `mb-metrics.sh`.
- **`SKILL.md` frontmatter** — invalid `user-invocable: false` replaced by `name: memory-bank` with a three-in-one concept description.
- **`Task(...)` → `Agent(subagent_type=...)`** in all skill files. Grep check: 0 occurrences of `Task(`.
- **`mb-doctor`** fixes desynchronization primarily through `mb-plan-sync.sh`/`mb-plan-done.sh`; Edit is reserved for semantic issues.
- **`install.sh`** — always writes the `[MEMORY-BANK-SKILL]` marker when creating a new `CLAUDE.md` (previously only when merging into an existing one).
- **`mb-manager actualize`** — now calls `mb-index-json.py` instead of manually writing `index.json`.
- **`file-change-log.sh`** — removed `pass\s*$` from the placeholder regex (false positive); placeholder search now ignores Python docstrings.
- **`install.sh` banner**: `19 dev commands` → `18 dev commands` (after init-command consolidation).

### Deprecated

- (none — all deprecations in this release are full removals; see Removed)

### Removed

- **`/mb:setup-project`** — merged into `/mb init --full`. `commands/setup-project.md` removed.
- **Orphan agent `codebase-mapper`** — replaced with `mb-codebase-mapper`.
- **Hardcoded `pytest -q` / `ruff check src/`** in `commands/mb.md` and `agents/mb-doctor.md`.
- **All `Task(...)` invocations** in skill files (0 left).

### Fixed

- **E2E-found bug #1**: `install.sh` did not add the `[MEMORY-BANK-SKILL]` marker when creating a **new** `CLAUDE.md`. Result: `uninstall.sh` could not find the section to clean.
- **E2E-found bug #2**: `uninstall.sh` used the GNU-only `realpath -m` flag. BSD `realpath` on macOS failed. Fix: the manifest already stores absolute paths, so `realpath` is unnecessary.
- **Node `src_glob`**: brace-pattern `*.{ts,tsx,js,jsx}` replaced by space-separated globs for portable grep.
- **`mb-note.sh`**: name collision (two notes in one minute) now yields `_2/_3` suffixes (previously `exit 1`).
- **`file-change-log` false positives**: bare `pass` in Python, TODO inside docstrings.
- **shellcheck SC1003** in the awk hook block — rewritten through `index()` without nested single-quote escapes.

### Security

- **`block-dangerous.sh`** updated with `MB_ALLOW_NO_VERIFY=1` explicit opt-in override — previously `--no-verify` was blocked with no safe escape.
- **Secrets detection** in `file-change-log.sh` continues to work (`password|secret|api_key|token|private_key` in source code).

### Infrastructure

- **Dogfooding**: the skill now uses `.memory-bank/` in its own repository. The v2 refactor plan lives in `.memory-bank/plans/`, and sessions are closed through `/mb done`.
- **VERSION marker**: `2.0.0-dev` → `2.0.0` written by `install.sh` into `~/.claude/skills/memory-bank/VERSION`.
- **CI green** on macOS + Ubuntu, 0 shellcheck warnings, ruff all passed.

---

## [1.0.0] — 2025-10-XX (pre-refactor baseline)

- Initial Memory Bank skill: `.memory-bank/` structure, `/mb` roadmap command, 4 agents, 2 hooks, 19 commands.
- Python-first: hardcoded `pytest`, `ruff`, `src/taskloom/`.
- Orphan artifacts from GSD: `codebase-mapper`, `.planning/`.
- 0 automated tests.

[2.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v2.0.0
[1.0.0]: https://github.com/fockus/claude-skill-memory-bank/releases/tag/v1.0.0
