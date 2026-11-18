# /mb deps — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `deps [--install-hints]` — Dependency check (required: `python3`, `jq`, `git`; optional: `rg`, `shellcheck`, `tree-sitter`, `PyYAML`). `--install-hints` prints OS-specific install commands

### deps [--install-hints]

Check all required and optional skill dependencies. This runs automatically before `install.sh` (step 0) and is also available standalone via `/mb deps`.

**Required (exit 1 if missing):**

- `bash` — runtime for shell scripts
- `python3` — required by `mb-index-json.py`, `mb-import.py`, `mb-codegraph.py`, and hooks
- `jq` — required by `session-end-autosave.sh`, `block-dangerous.sh`, `file-change-log.sh` (JSON parsing from hook stdin)
- `git` — required by `mb-upgrade.sh` and version tracking

**Optional (warning, not a blocker):**

- `rg` (ripgrep) — speeds up `mb-search`, with fallback to `grep`
- `shellcheck` — dev-only (CI lint)
- `tree_sitter` (Python package) + grammars — multi-language `/mb graph` (Go/JS/TS/Rust/Java). Without it, the always-on extractors (Python/Bash/Bats) still work
- `PyYAML` — strict YAML parsing in frontmatter, with fallback to the simple parser

**Output format** (key=value, machine-parseable):

```
dep_bash=ok
dep_python3=ok
dep_jq=missing
dep_git=ok
...
deps_required_missing=1
deps_optional_missing=2
```

**Install hints** — `--install-hints` prints OS-specific commands (brew/apt/dnf/pacman detected via `/etc/os-release`).

Run directly:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-deps-check.sh $ARGS_AFTER_DEPS
```

**Typical first-install flow:**

```
User: bash install.sh
→ [0/7] Dependency check
  ❌ dep_jq=missing
  ═══ Required tools missing — install before proceeding ═══
    jq: brew install jq
  Exit 1

User: brew install jq && bash install.sh
→ [0/7] ✅ All required dependencies present.
  [1/7] Rules → ...continues
```

**Override:** `MB_SKIP_DEPS_CHECK=1 bash install.sh` — skips preflight (CI / isolated environments where tools are checked differently).
