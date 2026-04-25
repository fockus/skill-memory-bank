# Technology Stack

**Analyzed:** 2026-04-21

## Languages & Runtime

- **Primary:** Python 3.11+ — CLI entry at `memory_bank_skill/cli.py` (thin wrapper over bundled shell scripts)
- **Co-primary:** Bash 3.2+ — all business logic scripts under `scripts/*.sh`, `adapters/*.sh`, `hooks/*.sh`, `install.sh`, `uninstall.sh`
- **Runtime:** CPython 3.11 / 3.12 declared in `pyproject.toml`; bash shell required on PATH (Git Bash / WSL on Windows via `memory_bank_skill/cli.py::find_bash`)
- **Build backend:** `hatchling>=1.18` (`pyproject.toml:2`)
- **Package manager:** pipx (primary), pip, Homebrew (`packaging/homebrew/`), or `git clone + ./install.sh`

## Frameworks

- No runtime framework — zero hard dependencies (`dependencies = []` in `pyproject.toml:28`)
- Python stdlib-only core: `argparse`, `subprocess`, `pathlib`, `shutil`, `platform` (see `memory_bank_skill/cli.py:18-26`)

## Key Dependencies

- **Runtime core:** none required — intentional design, keeps pipx install fast
- **Optional `codegraph` extra:** `tree-sitter>=0.21` + language bindings (python/go/js/ts/rust/java) — powers `scripts/mb-codegraph.py`
- **Optional `yaml` extra:** `PyYAML>=6.0` — frontmatter parsing for `scripts/mb-index-json.py`
- **Dev extra:** `pytest>=7`, `pytest-cov>=4`, `ruff>=0.5`
- **Test runners (not packaged):** `bats-core` for `tests/bats/` and `tests/e2e/`; `jq` used by several adapter scripts

## External Integrations

- **None at runtime.** The skill writes to the local filesystem only.
- **Host IDE surfaces** (via `install.sh` + `adapters/*.sh`):
  - Claude Code → `~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/hooks/`
  - Cursor → `~/.cursor/skills/`, `~/.cursor/commands/`, `~/.cursor/hooks.json`, `~/.cursor/AGENTS.md`
  - Codex → `~/.codex/skills/`, `~/.codex/AGENTS.md`
  - OpenCode → `~/.config/opencode/`
  - Project adapters: `cursor.sh`, `windsurf.sh`, `cline.sh`, `kilo.sh`, `opencode.sh`, `pi.sh`, `codex.sh`, `git-hooks-fallback.sh`
- **GitHub** — `scripts/mb-upgrade.sh` self-updates from the public repo via `curl`/`git`

## Configuration

- **Env files:** `.env`* ignored in `.gitignore:4-5` — not read by the skill
- **Config files:** `pyproject.toml` (build/lint), `.coveragerc` (test coverage scope), `.gitignore`, `opencode.json`, `settings/hooks.json`
- **Env vars consumed:** `MB_BASH` (Windows bash override, `cli.py:60`), `MB_SKILL_BUNDLE` (dev override, `_bundle.py:19`), `MB_SHOW_PRIVATE`, `MB_AUTO_CAPTURE`, `MB_COMPACT_REMIND` (see `SKILL.md`)

## Platform

- **Dev:** macOS / Linux with bash, Python 3.11+, bats-core, pytest, ruff
- **Prod (end-user install):** macOS / Linux native; Windows via Git for Windows bash or WSL (auto-detected by `cli.py:findBash`)
- **Distribution channels:** PyPI wheel/sdist (via hatchling shared-data layout at `pyproject.toml:82-94`), Homebrew formula (`packaging/homebrew/`), direct `git clone && ./install.sh`