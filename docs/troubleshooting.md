# Troubleshooting

Common issues, grouped by symptom. If the fix isn't here, run `memory-bank doctor` first — it
reports the resolved bundle path, platform info, and bash discovery — and attach its output when
opening an [issue](https://github.com/fockus/skill-memory-bank/issues).

## Install & CLI

**`memory-bank install` fails with `ModuleNotFoundError: No module named 'memory_bank_skill'`**
You're on a version where the bundled scripts called a bare system `python3`, which can't see a
pipx/Homebrew virtualenv. Fixed in 5.0.1 (scripts now run through `MB_PYTHON`).
Upgrade: `pipx upgrade memory-bank-skill` (or `brew upgrade memory-bank`).

**`jq: command not found` during install or `/mb` commands**
`jq` is a required dependency. `brew install jq` (macOS) / `sudo apt install jq` (Debian/Ubuntu).
Check everything at once with `/mb deps --install-hints`.

**Windows: `bash not found`**
The CLI needs a bash. Either `winget install Git.Git` (supplies `bash.exe`) or `wsl --install`.
Verify with `memory-bank doctor` — it prints the detected bash path or an install hint.

**Reinstall keeps creating `.pre-mb-backup.*` files**
It shouldn't: since 3.0.0 installs are byte-level idempotent and back up only files whose content
actually differs. If you see repeated backups, you likely have a locally modified target file —
diff it against the backup, keep your changes outside the managed marker block.

**Running the installer with `sudo` writes into `/root/...` instead of your home directory**
Plain `sudo ./install.sh` (or `sudo memory-bank install`) resets `$HOME` to the invoking user's
home unless you preserve the environment — files end up under `/root/.claude`, `/root/.codex`,
etc. instead of your actual `~/.claude`. If you must run the installer with elevated privileges,
use `sudo -E ./install.sh` (or `sudo -E memory-bank install`) to keep `$HOME` intact. In general,
prefer a non-root install: `pipx`/Homebrew installs and the global-artifact writes under
`install.sh` do not require `sudo` at all.

## Memory Bank activation

**The agent prints `[MEMORY BANK: ABSENT]` although I installed the skill**
Expected: a **global skill install** never activates a **project bank**. Run `/mb init` in the
project (or `/mb init --storage=global --agent=<name>` to keep the repo untouched). Until then
you're in rules-only mode — engineering rules still apply, lifecycle commands stay off.

**`/mb` commands don't exist in my agent**
- Claude Code / OpenCode: re-run `memory-bank install`, then restart the session.
- Cursor: commands and hooks are global after install, but User Rules are UI-only — paste
  `~/.cursor/memory-bank-user-rules.md` into Settings → Rules → User Rules once per machine.
- Pi Code: run `/reload` after install if the session was already open.
- Codex: there is no native `/mb` surface — use the `memory-bank` CLI and `~/.codex/AGENTS.md`
  guidance; project adapters come from `memory-bank install --clients codex`.

**The agent ignores the bank / doesn't run `/mb start`**
Check that the project's `CLAUDE.md`/`AGENTS.md` contains the `<!-- memory-bank:start -->`
managed block (re-run `/mb init` or `memory-bank install` if missing), and that you haven't
removed the session hooks from `~/.claude/settings.json` (re-merge with `memory-bank install`).

## Features

**`/mb recall` finds nothing**
Recall searches `.memory-bank/session/` + `notes/`. If `session/` is empty, session capture may
be off (`MB_SESSION_CAPTURE=off`) or the bank is new — there's nothing to recall yet. Build the
semantic index with `/mb reindex` (degrades to lexical search without `fastembed`).

**`/mb graph` says tree-sitter is missing**
Python is parsed with the stdlib `ast`; Go/JS/TS/Rust/Java need the optional extra:
`pipx install --force 'memory-bank-skill[codegraph]'` or
`pip install 'memory-bank-skill[codegraph]'` in the relevant environment.

**`/mb work` refuses to run my plan**
Wrapper plans must link their source: either a `linked_spec` frontmatter key or
`<!-- mb-stage:N -->` markers. `/mb work` fails fast on an unlinked wrapper instead of guessing —
fix the plan header, don't bypass the gate.

**Review/judge stages don't run**
That's the v5 default: the pipeline is `implement → verify → done`. Opt in per run
(`--review`, `--judge`, `--workflow full`) or per project (`pipeline.yaml` — validate it with
`/mb config validate`).

## Uninstall & conflicts

**Will uninstalling break my other AI clients?**
No. `AGENTS.md` ownership is refcount-tracked across OpenCode/Codex/Pi; uninstalling one client
removes only its own managed sections. Full removal: `memory-bank uninstall -y`, then per-project
adapters via `adapters/<client>.sh uninstall <project-dir>`.

**My own content in `AGENTS.md` / hooks disappeared**
It shouldn't — adapters only touch content between `<!-- memory-bank:start/end -->` markers and
JSON entries flagged `_mb_owned: true`. Backups live next to the file as `.pre-mb-backup.<ts>`;
restore from there and report the case as a bug.

## Still stuck?

Open an issue with: `memory-bank version`, `memory-bank doctor` output, your OS, the agent
(Claude Code / Cursor / …), and the exact command + output.
