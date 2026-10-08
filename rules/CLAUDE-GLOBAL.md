## Memory Bank status line

Open your first reply to the user in a project session with one line that says whether project memory is in play: `[MEMORY BANK: ACTIVE]` when a bank resolves for this project, `[MEMORY BANK: ABSENT]` when none does, and `[MEMORY BANK: INITIALIZED]` right after the user asked you to create one. A bank may be local (`.memory-bank/`), global (`/mb init --storage=global`) or legacy (`.claude-workspace`); `scripts/_lib.sh::mb_resolve_path` resolves all three. The line is for the human: leave it out of later replies, subagent reports, and output that a script parses.

A globally installed skill never means this project has a bank; only an explicit `/mb init` creates one. Do not silently initialize Memory Bank for meta/install/debug questions.

### Rules-only mode

`[MEMORY BANK: ABSENT]` is a valid steady state: the Key rules and the rules below still apply; only the `/mb` lifecycle commands stay inactive.

# Engineering rules

The `## Key rules` section at the top of this file is the active rule set — change it with `/mb rules`. Details: `~/.claude/RULES.md`; project overrides in `<project-root>/RULES.md` or `.memory-bank/RULES.md` add to it.

> **Language** — respond in English; technical terms may remain in English.

- No new libraries/frameworks without an explicit request; destructive actions → confirm first; a significant decision → ADR.
- Trivial and small tasks need no plan; standard+ gets a `/mb plan` with SMART DoD for the plan (per stage only at a real boundary); coverage gates only when the profile enables them — `SKILL.md` § Task routing.

## Memory Bank
- Start project work with `/mb context` (alias `/mb`); `/mb start` also reads the active plan in.
- Code questions (who calls / impact / tests / concept search) → the code graph first: `mb-graph.sh who-calls|impact|tests <Symbol>`, `mb-graph.sh search "<query>"`.
- `progress.md` is append-only; IDs (I-/EXP-/ADR-NNN) are monotonic and never reused; tick `checklist.md` as soon as an item is done; `notes/` hold patterns, not chronology.
- Parallel sessions in one working tree share `.memory-bank/COORDINATION.md`: read it with `scripts/mb-coord.sh active` at session start, before each stage/commit and before editing shared files; freezes, handovers and commit-order agreements need an ACK entry — `references/coordination.md`.
- Agreements: an explicit user decision → `mb-agree.sh add "<statement>"`, then announce `→ AGR-NNN записано: <statement>`; an unconfirmed idea → `mb-agree.sh question "<text>"`; a changed decision → `add "<new>" --supersedes N` — `references/agreements.md`.
