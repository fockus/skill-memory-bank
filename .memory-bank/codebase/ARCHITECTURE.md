# Architecture

**Analyzed:** 2026-04-21

## Pattern
**Overall:** Layered bundle-oriented — a thin Python CLI shell over a bash-script toolkit, plus per-host adapters. Not Clean Architecture; closer to a "dispatcher + plugins" pattern where `install.sh` is orchestrator, `adapters/*.sh` are pluggable targets, and `scripts/*.sh` are reusable operations.

## Layers
- **Presentation / Entry** — `memory_bank_skill/cli.py`, `commands/*.md` (slash-command prompts for host IDEs), `install.sh`, `uninstall.sh`. Responsible for argument parsing, platform detection, and routing to shell scripts.
- **Orchestration** — `install.sh` (938 lines) + `adapters/*.sh`. Manages install/uninstall lifecycle across 8 host IDEs, manifest tracking (`.installed-manifest.json`), and hook merging.
- **Domain operations** — `scripts/mb-*.sh` + `scripts/mb-*.py`. Pure memory-bank logic: context, search, plan sync, metrics, indexing, drift detection, compaction. Depend only on `scripts/_lib.sh`.
- **Shared library** — `scripts/_lib.sh` (stack detection, path resolution, topic sanitization), `adapters/_lib_agents_md.sh` (marker-section writer for `AGENTS.md`-style files), `memory_bank_skill/_bundle.py` (bundle-root resolution).
- **Agent prompts** — `agents/*.md` (mb-manager, mb-doctor, mb-codebase-mapper, plan-verifier). Read by host agents; not executed by the skill itself.

## Data Flow
1. User runs `memory-bank install` (CLI) or host invokes `/mb <cmd>` (slash command).
2. `cli.py` detects bash (`find_bash`), resolves bundle root (`_bundle.py::find_bundle_root`), forwards to `install.sh` with args.
3. `install.sh` copies skill bundle → `~/.claude/skills/skill-memory-bank`, creates aliases for Cursor/Codex, writes Cursor global hooks, calls selected `adapters/*.sh` for project-level integration.
4. At runtime, host invokes a script such as `scripts/mb-context.sh`, which sources `_lib.sh`, resolves `mb_path` (from `.claude-workspace` or default `.memory-bank/`), reads core files, prints context to stdout.
5. Manifests (`.installed-manifest.json`, `.mb-agents-owners.json`, `.cursor/.mb-manifest.json`) record ownership so `uninstall.sh` / `adapter uninstall` can restore pre-install state.

## Directory Structure
```
claude-skill-memory-bank/
├── memory_bank_skill/   # Python CLI package (cli.py, _bundle.py, __init__.py, __main__.py)
├── scripts/             # Bash/Python domain scripts — mb-*.sh operations + _lib.sh
├── adapters/            # Per-host-IDE install/uninstall shell adapters + _lib_agents_md.sh
├── hooks/               # Hook scripts (sessionEnd, preCompact, file-change-log, block-dangerous)
├── commands/            # Slash-command Markdown prompts — /mb, /commit, /plan, /review, etc.
├── agents/              # Subagent prompt definitions (mb-manager, mb-doctor, mb-codebase-mapper, plan-verifier)
├── rules/               # RULES.md (24k), CLAUDE-GLOBAL.md — rendered into host config
├── references/          # metadata.md, templates.md, structure.md, workflow.md — doc fragments
├── settings/            # hooks.json template + merge-hooks.py
├── tests/bats/          # 24 bats test files for shell layer
├── tests/e2e/           # 5 bats files — install/uninstall/cursor-global/idempotency
├── tests/pytest/        # 7 pytest files — cli, codegraph, import, index_json, merge_hooks, runtime_contract
├── tests/fixtures/      # Per-stack fixture projects (python/go/rust/node/java/kotlin/swift/cpp/ruby/php/csharp/elixir/multi/unknown/broken-mb)
├── packaging/homebrew/  # Homebrew formula
├── docs/                # MIGRATION-v1-v2.md, install.md, cross-agent-setup.md, repo-migration.md
├── install.sh / uninstall.sh   # Top-level orchestrators
├── pyproject.toml       # Hatch build + ruff + shared-data layout
└── SKILL.md / VERSION / CHANGELOG.md / README.md
```

## Entry Points
- `memory_bank_skill/cli.py::main` — console script `memory-bank` (`pyproject.toml:44`), subcommands: `install`, `uninstall`, `init`, `version`, `self-update`, `doctor`
- `memory_bank_skill/__main__.py` — enables `python -m memory_bank_skill`
- `install.sh` — direct invocation for git-clone users
- `commands/mb.md` — 37k-line dispatcher prompt; host routes `/mb <subcmd>` through it

## Where to Add
- **New shell operation:** `scripts/mb-<name>.sh` + source `_lib.sh` + bats test in `tests/bats/test_<name>.bats` + add to `pyproject.toml` `[tool.hatch.build] include` if bundled
- **New host-IDE adapter:** `adapters/<host>.sh` following `cursor.sh` pattern (install/uninstall actions, manifest in `.<host>/.mb-manifest.json`), bats test in `tests/bats/test_<host>_adapter.bats`
- **New CLI subcommand:** extend `memory_bank_skill/cli.py::build_parser` + pytest in `tests/pytest/test_cli.py`
- **New slash command:** `commands/<name>.md` + register in `install.sh` copy list

## Cross-cutting
- **Logging:** stderr with ANSI color helpers (`RED/YELLOW/GREEN/BLUE/BOLD/NC` in `install.sh:32`); bash `set -euo pipefail` enforced across scripts (`_lib.sh:8`)
- **Error handling:** bash fail-fast via `set -euo pipefail`; Python returns non-zero exit codes (`cli.py::cmd_doctor` exits 1 on missing bundle); user-facing errors include install hints (`windows_install_hint`)
- **Idempotency:** all installers re-run safely — manifests (`.installed-manifest.json`) track owned files; `<!-- memory-bank-*:start/end -->` markers in `AGENTS.md` files; `_mb_owned: true` tags in hook JSON entries (`SKILL.md:133`)
- **Privacy:** `<private>...</private>` Markdown blocks redacted by `mb-search.sh` + excluded from `index.json`; `forbidden_files` list honored by agents
