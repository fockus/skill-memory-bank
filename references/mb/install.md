# /mb install — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Contents

- [install []](#install-)
- [Step 1 — Check the CLI](#step-1--check-the-cli)
- [Step 2 — Collect the client list](#step-2--collect-the-client-list)
- [Step 3 — Run installation](#step-3--run-installation)
- [Step 4 — Resume hint](#step-4--resume-hint)
- [Extension offer (pi/opencode only)](#extension-offer-piopencode-only)


## Router entries

- `install [<clients>]` — Install Memory Bank for the project. If `<clients>` is empty, ask for an 8-client multiselect (`claude-code/cursor/windsurf/cline/kilo/opencode/pi/codex`). Calls `memory-bank install --clients ... --project-root $PWD`

### install []

Install Memory Bank for the current project + selected AI agents. The CLI can be run from Claude Code, OpenCode, Codex, and other agents with a Bash tool, but native `/mb` command surface is guaranteed only for Claude Code / OpenCode. In Codex, installation provides global skill registration + `~/.codex/AGENTS.md` hints, not a separate slash-command surface.

**Argument format** (first word after `install`):

- Empty → interactive selection.
- Comma/space-separated client list (for example `claude-code,cursor,windsurf`) → direct run without prompt.
- `all` → all 8 clients.

Allowed names: `claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`.

---

#### Step 1 — Check the CLI

```bash
command -v memory-bank >/dev/null 2>&1 && memory-bank version
```

If not found — tell the user and suggest:

```
memory-bank CLI not found. Install it using one of:

  pipx install memory-bank-skill           # cross-platform
  brew install fockus/tap/memory-bank      # macOS / Linuxbrew
  pip install memory-bank-skill            # alternative

Then retry installation via CLI `memory-bank install ...` or the matching host command where supported.
```

Then stop.

---

#### Step 2 — Collect the client list

**If `$ARGUMENTS` (after the word `install`) is non-empty** — use it directly. The CLI validates it.

**If empty:**

In **Claude Code**, use `AskUserQuestion` with `multiSelect: true`:

```
question: "Which AI coding agents should share this project's memory bank?"
header: "Clients"
options:
  - {label: "claude-code (recommended)", description: "Primary Claude Code setup"}
  - {label: "cursor", description: "Cursor 1.7+ with CC-compat hooks"}
  - {label: "windsurf", description: "Windsurf Cascade hooks"}
  - {label: "opencode + codex + pi (shared AGENTS.md)", description: "All three use AGENTS.md — refcount-tracked"}
```

If the user chose "opencode + codex + pi" — expand it into `opencode,codex,pi`.

If the user selected nothing — default to `claude-code`.

In **other agents without `AskUserQuestion`**, print the list and ask for input:

```
Which agents should share this project's memory bank?
  [1] claude-code (recommended)
  [2] cursor
  [3] windsurf
  [4] cline
  [5] kilo
  [6] opencode
  [7] pi
  [8] codex

Reply with names or numbers (e.g. "1,2" or "cursor,windsurf"),
'all' for every client, or press Enter for claude-code only.
```

Parse the reply into a comma-separated list of names.

---

#### Step 3 — Run installation

```bash
memory-bank install --clients "<selected-list>" --project-root "$PWD"
```

Show stdout — the CLI prints a step-by-step report (Rules / Agents / Hooks / Commands / Settings / Manifest + cross-agent adapters).

---

#### Step 4 — Resume hint

After success:

```
✓ Memory Bank installed for: <clients>
  Project root: <PWD>

Next steps:
  • Initialize the memory bank:   /mb init
  • Load context in this session: /mb start
  • Plan a feature:               /mb plan feature <topic>
```

If the installed client list includes one different from the current host (for example the user in Claude Code chose `cursor`) — remind them that the adapter will be picked up automatically when that IDE next opens the project.

---

#### Extension offer (pi/opencode only)

When the selected clients include `pi` and/or `opencode`, `install.sh` offers opt-in host parity extensions (session memory, subagent dispatch, GraphRAG promotion) — one prompt per host family, default No. Non-interactively, pass `--with-extensions[=pi,opencode]` (or set `MB_WITH_EXTENSIONS`) to accept without prompting; declining leaves the install unchanged. Mention this offer/flag when running Step 3 for `pi`/`opencode` clients so the user isn't surprised by the prompt. `memory-bank install` (the pipx/pip/brew CLI wrapper) already forwards the `MB_WITH_EXTENSIONS` env var to `install.sh` (it passes through `os.environ` untouched) — only the `--with-extensions` CLI flag form is missing from `cli.py`'s argparse (tracked as backlog I-118). Until that lands, `MB_WITH_EXTENSIONS=pi,opencode memory-bank install ...` works from the wrapper; a bare `--with-extensions` flag needs the repo's `install.sh` invoked directly:

```bash
bash install.sh --clients "pi,opencode" --project-root "$PWD" --with-extensions
```

---

**Errors:**

- `memory-bank: command not found` → see Step 1.
- `invalid client 'X'` → check the name (strict list of 8).
- `bash not found on PATH` (Windows) → suggest Git for Windows or WSL.

**Do not confuse with:**

- `/mb init` — initializes `.memory-bank/` **inside** the project after the skill is installed globally. Usually `install` → then `init`.
- `install.sh` in the repo root — the shell script that `memory-bank install` calls under the hood.
