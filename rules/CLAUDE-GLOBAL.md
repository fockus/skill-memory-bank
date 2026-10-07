## Memory Bank status line

Open your first reply to the user in a project session with one line that says whether project memory is in play: `[MEMORY BANK: ACTIVE]` when a bank resolves for this project, `[MEMORY BANK: ABSENT]` when none does, and `[MEMORY BANK: INITIALIZED]` right after the user asked you to create one. A bank may be **local** (`<project>/.memory-bank/`), **global** (registered under `<agent_config>/memory-bank/registry.json` via `/mb init --storage=global`), or **legacy** (`.claude-workspace`); `scripts/_lib.sh::mb_resolve_path` resolves all three. The line is for the human: leave it out of later replies, subagent reports, and output that a script parses.

A globally installed skill never means this project has a bank; only an explicit `/mb init` creates one. Do not silently initialize Memory Bank for meta/install/debug questions.

### Rules-only mode

`[MEMORY BANK: ABSENT]` is a valid steady state. When the user chooses not to initialize a Memory Bank, **the Key rules and the engineering rules below still apply**. Only the `/mb` lifecycle commands stay inactive.

# Engineering rules

The `## Key rules` section at the top of this file is the active rule set, one line per rule — change it with `/mb rules`. Details and examples: `~/.claude/RULES.md` + project-root `RULES.md`.

> **Language** — respond in English; technical terms may remain in English.

## Coding & Reasoning
- No new libraries/frameworks without explicit request; plans are written with `/mb plan`.
- Specification by Example (concrete input/output); refactor via Strangler Fig (tests green at every step); significant decision → ADR (context → decision → alternatives → consequences).
- Destructive actions → confirm first.
- Size the task before the first edit (memory-bank skill `SKILL.md` § Task routing, `references/effort-tiers.md`): trivial and small tasks need no plan; standard+ gets a `/mb plan` with SMART DoD for the plan (per stage only at a real boundary); coverage gates apply only when enabled in the profile.

## Memory Bank
**Skill:** `memory-bank`. **Command:** `/mb`. **Path:** `./.memory-bank/`.
**`/mb context`** (alias `/mb`) — gather the current project context (status + checklist + active plan + codebase summary). Run it at the START of any project work; `/mb context --deep` expands the full `codebase/*.md`. `/mb start` = extended start (context + the full active plan read in).
- Code questions (who calls / impact / covering tests / concept search) → the code graph first: `mb-graph.sh who-calls|impact|tests <Symbol>`, `mb-graph.sh search "<query>"`; procedures and opt-in layers live in the skill.
- `progress.md` = **append-only** (never rewrite old entries); IDs monotonic (I-/EXP-/ADR-NNN, never reused); `checklist.md` ✅/⬜ updated **immediately**; `notes/` = patterns (5–15 lines), not chronology.
- **Parallel sessions in one working tree** → coordinate via the append-only board `.memory-bank/COORDINATION.md`: read it with `scripts/mb-coord.sh active` (freezes + unACKed handovers + last 3 entries; the full file only when investigating) at session start, before each stage/commit, and before editing shared files; scoped `git add` only (never `-A`); freezes/handovers/commit-order agreements require an ACK entry. Protocol → skill `references/coordination.md`.
- **Running list of agreements** — explicit user decision → `mb-agree.sh add "<statement>"` then announce `→ AGR-NNN записано: <statement>`; unconfirmed idea/hypothesis → `mb-agree.sh question "<text>"`; a changed decision → `add "<new>" --supersedes N` (never leave two active). Kill-switch `MB_AGREEMENTS=off`. Protocol → skill `references/agreements.md`.

Project-specific overrides live in `<project-root>/RULES.md` (or `.memory-bank/RULES.md`). Read them **in addition to** the global ones, not instead.
