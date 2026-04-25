# Coding Conventions

**Analyzed:** 2026-04-21

## Naming

- **Shell scripts:** `kebab-case.sh`, prefixed `mb-` for memory-bank domain ops (`scripts/mb-context.sh`), adapter files named by host (`adapters/cursor.sh`). Shared libs: leading underscore — `scripts/_lib.sh`, `adapters/_lib_agents_md.sh`.
- **Python modules:** `snake_case.py` (`memory_bank_skill/cli.py`, `scripts/mb_index_json.py` → actually `mb-index-json.py` as script). Private modules prefixed `_` (`memory_bank_skill/_bundle.py`).
- **Shell functions:** `snake_case`, domain-prefixed — `mb_resolve_path`, `mb_detect_stack`, `mb_sanitize_topic` (`scripts/_lib.sh:12,39,184`).
- **Python functions:** `snake_case` — `find_bash`, `run_shell`, `cmd_install` (`memory_bank_skill/cli.py`). Command handlers named `cmd_<name>`.
- **Env vars:** `SCREAMING_SNAKE_CASE` prefixed `MB_` — `MB_BASH`, `MB_SKILL_BUNDLE`, `MB_AUTO_CAPTURE`, `MB_SHOW_PRIVATE`.
- **Markers in managed files:** `<!-- memory-bank-<host>:start -->` / `:end -->` pairs (see `install.sh:21-24`).

## Style

- **Python formatter/linter:** `ruff` with `line-length = 100`, `target-version = "py311"` (`pyproject.toml:118-124`). Selected rules: `E, F, W, I, UP, B, SIM`; `E501` ignored.
- **Shell style:** `#!/usr/bin/env bash` + `set -euo pipefail` at top of every script (`install.sh:5`, `scripts/_lib.sh:8` uses `# shellcheck shell=bash`).
- **Indentation:** 2 spaces (shell), 4 spaces (Python).
- **Line endings:** LF; no trailing whitespace.

## Imports

- **Python:** `from __future__ import annotations` at top (see `cli.py:18`, `_bundle.py:9`). Stdlib → first-party. No third-party imports in core modules.
- **Shell:** `source "$(dirname "$0")/_lib.sh"` pattern for sharing utilities.

## Testing

- **Runners:** `pytest -q` for Python (`tests/pytest/`), `bats` for shell (`tests/bats/` unit + adapter tests, `tests/e2e/` end-to-end).
- **Layout:** split by layer — `tests/pytest/test_*.py` (7 files), `tests/bats/test_*.bats` (24 files), `tests/e2e/test_*.bats` (5 files), shared inputs under `tests/fixtures/<stack>/`.
- **Naming:** files `test_<subject>.bats` / `test_<subject>.py`; cases describe behavior — `@test "install is idempotent on second run"` style.
- **Fixtures:** per-stack manifest-only projects in `tests/fixtures/<stack>/` (python, go, rust, node, java, kotlin, swift, cpp, ruby, php, csharp, elixir, multi, unknown, broken-mb) — drive `mb_detect_stack` tests.
- **Coverage scope:** `.coveragerc` limits to `settings/merge-hooks.py` + `scripts/mb-index-json.py` — most bash logic is covered by bats, only Python glue is under `coverage`.
- **Mocking:** no runtime deps to mock. Shell tests spawn real scripts in temp dirs; Python tests use `tmp_path` + `subprocess` against `MB_SKILL_BUNDLE` overrides.
- **Green baseline (per user context):** 49/49 install/idempotent/cursor-global suites; ~368 bats + 115 pytest total.
- **Run:** `pytest -q` (root) and `bats tests/bats tests/e2e` (root).

## Error Handling

- **Shell:** fail-fast via `set -euo pipefail`; guard optional inputs with `${VAR:-default}`; silently degrade on missing optional tools (`jq` fallback patterns in adapters).
- **Python:** return exit codes from `cmd_`* handlers (never `sys.exit` inside handlers except `require_bash`); user-facing errors go to `sys.stderr` with an install hint (`cli.py::windows_install_hint`).

## Comments

- **Module-level docstrings** on every Python file describing purpose + priority order (`cli.py:1-16`, `_bundle.py:1-7`).
- **Shell header blocks** describe usage, arguments, and guarantees (idempotency, exit codes) — see `install.sh:1-6`, `scripts/_lib.sh:1-8`, `adapters/cursor.sh:1-14`.
- Inline comments explain non-obvious WHY only (e.g. `cli.py:82` explains why `system32\\bash.exe` is skipped on Windows).

## Function Design

- **Python:** small handlers (`cmd_install`, `cmd_doctor` ~5-20 lines); one public function per concept; `_` prefix for private helpers (`_env_bash_override`, `_candidate_paths`).
- **Shell:** functions print to stdout, return 0 on success, avoid `exit` so sourcing scripts stay in control (explicit rule in `_lib.sh:5-7`).
- **Idempotency contract:** every installer/adapter must be safe to re-run; enforced by manifest files + bats idempotency tests (`tests/e2e/test_install_idempotent.bats`).