# Agent operating guide

This page is written **for an AI coding agent**. Hand it to your agent as-is — it is plain
markdown with no page chrome — and the agent will know what Memory Bank gives it and how to
operate it. Humans can read it as the shortest complete tour.

Raw file: `https://raw.githubusercontent.com/fockus/skill-memory-bank/main/docs/agent-guide.md`.
Installed copy: `$SKILL_DIR/docs/agent-guide.md`.

## 1. What you are working with

memory-bank-skill (v5.4.1) is a framework installed next to the code:

- **Memory** — a `.memory-bank/` directory holding status, plans, specs, decisions and past
  sessions.
- **Rules** — a short Key rules block at the top of `CLAUDE.md` / `AGENTS.md`, backed by the
  project `RULES.md`.
- **A pipeline** — `/mb work` runs a plan or spec through subagents with gates.
- **Teams and goals** — `/mb team` runs tracks in parallel; `/mb drive` drives a goal to evidence.
- **A code graph** — structural answers without grep.
- **Acceptance QA** — `/mb qa` checks the live product.

Resolve the skill bundle once and call every helper through it:

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
```

Each command has a canonical contract in `$SKILL_DIR/commands/<name>.md`. When this guide and a
contract disagree, the contract wins.

## 2. Session protocol

| When | Do |
|---|---|
| First reply in a project | Open with `[MEMORY BANK: ACTIVE]` if a bank resolves, `[MEMORY BANK: ABSENT]` if not. Only the first reply |
| Session start | `/mb start` — reads `status.md`, `checklist.md`, `roadmap.md`, `research.md` and the active plan |
| A task finishes | Tick it in `checklist.md` immediately |
| A decision is confirmed by the user | `mb-agree.sh add "<statement>"`, then say `→ AGR-NNN recorded` |
| An idea is not yet confirmed | `mb-agree.sh question "<text>"` |
| Work followed a plan | `/mb verify` before `/mb done` |
| Session end | `/mb done` — appends `progress.md`, updates status, writes a note |
| After a compaction | Read `orchestrator-console.md`, the agreements tail, `mb-coord.sh active`, `mb-team.sh status` before acting |

A globally installed skill does **not** mean this project has a bank. Never run `/mb init` unless
the user asks for it. Without a bank the rules still apply; only the `/mb` lifecycle is inactive.

## 3. Size the task before you start

State the tier in one line before the first edit.

| Tier | Signals | What to do |
|---|---|---|
| trivial | A typo, a config value, a rename | Edit. Run the one check that covers the line |
| small | One feature in 1–3 files, clear contract | Inline. One test per stated behavior |
| standard | Several modules, an endpoint with storage | `/mb plan` → `/mb work` (preset `medium`) |
| large | A new subsystem, unclear requirements | `/mb discuss` → `/mb sdd` → `/mb work` (preset `complex`) |
| extra | Security, money, user data, reliability | A plan or spec, `/mb work` preset `governed`, every gate |

An explicit user request beats the estimate. Unsure between two tiers → take the lower one and
raise it when a risk appears.

## 4. Route what the user says

| The user says | Run |
|---|---|
| "what are we working on", "restore context" | `/mb start` |
| "formalize this", attaches documents | `/mb brief <topic> --input <path>` |
| "let's discuss", "clarify the requirements" | `/mb discuss <topic>` |
| "write the spec" | `/mb sdd <topic>` |
| "make a plan" | `/mb plan <type> <topic>` |
| "implement", "continue", "next step", "go by the plan" | `/mb work [target]` |
| "run it as a team", "in parallel tracks" | `/mb team` |
| "drive it to the end", "work autonomously" | `/mb goal`, then `/mb drive` |
| "run QA", "check the live stand" | `/mb qa run` |
| "is it done?", before closing planned work | `/mb verify` |
| "who calls X", "what breaks if I change X" | `mb-graph.sh who-calls X`, `impact X`, `tests X` |
| "what did we decide about X" | `/mb recall <query>` |
| "we're done", "save progress" | `/mb done` |

Work that refers to an existing plan or spec **always** goes through `/mb work`. Do not implement
planned work inline unless the user explicitly says to skip it.

## 5. Running `/mb work`

1. Resolve the workflow from `pipeline.yaml` (`mb-workflow.sh`) and the target (`mb-work-resolve.sh`,
   `mb-work-plan.sh`).
2. Treat `<!-- mb-task:N -->` blocks in `specs/<topic>/tasks.md` and `<!-- mb-stage:N -->` blocks
   in a plan as the executable source of truth.
3. Dispatch each role **by agent name** with the exact model the resolved plan prints.
4. Follow the resolved steps in order. Presets: `simple` → `medium` → `complex` → `governed`.
5. Flip checkboxes only through the deterministic helpers, never by hand.
6. Do not claim completion until the configured verify, review and judge gates are satisfied.

## 6. Running `/mb team` and `/mb drive`

Both are **loops you drive**. A script prints the next action and records state; you execute it.

- `team next` prints one action per line — execute all of them, parallel ones in one turn, then
  call `next` again.
- `mb-drive.sh next` prints exactly one action — run it, report it with `returned --tokens N`,
  call `next` again.
- A `stop_human` is final until the user resolves it. Do not work around it.
- Your own sense that the work looks finished is never a stop. Only `stop_success` means done.
- Tracks never commit or push. Only you commit, through `team commit`, after the user's yes.
- Keep `<bank>/orchestrator-console.md` current (40 lines or fewer): open questions, running
  tracks, next step, unrecorded decisions.

## 7. Code questions: graph first

| Question | Tool |
|---|---|
| Who calls or imports X | `bash "$SKILL_DIR/scripts/mb-graph.sh" who-calls X` |
| What breaks if X changes | `mb-graph.sh impact X` |
| Which tests cover X | `mb-graph.sh tests X` |
| Where is the logic for a concept | `mb-graph.sh search "<phrase>"` |
| Is the graph fresh | `mb-graph.sh status` |
| A regex or raw text | `grep` is still right |

Exit codes: `1` no match, `2` usage, `3` no graph, `4` no Memory Bank. If the graph is missing or
stale, fall back to grep and read — the graph never blocks work. Rebuild with `/mb graph --apply`.

## 8. Rules for writing memory

- `progress.md` is append-only.
- IDs (`I-NNN`, `ADR-NNN`, `AGR-NNN`, `EXP-NNN`, `BUG-NNN`) are monotonic and never reused.
  Allocate them through the helper scripts, never by scanning one file.
- `notes/` hold patterns and lessons, not chronology.
- Backlog state changes go only through `mb-backlog-state.sh`.
- `qa/bugs.md` is written only by `mb-qa-bug.sh`.
- Everything you write to the repository follows the project's language rule.

## 9. Evidence before "done"

- Run the targeted tests and lint of the files you changed while working; the full suite in
  `/mb verify` and before a commit.
- Report outcomes as they are: if tests fail, say so with the output.
- The firewall (`mb-flow-verify.sh`) exit code is the verdict: `0` pass, `1` a check is red, `2` a
  check itself broke. Never report success on `1` or `2`.
- No placeholders: no `TODO`, no `...`, no pseudocode in shipped code.

## 10. Sharing a working tree

If `.memory-bank/COORDINATION.md` exists, other sessions are working in the same tree:

- Read the board with `mb-coord.sh active` at session start, before each stage or commit, and
  before editing a shared file.
- Obey `FREEZE` entries. A freeze, a handover or a commit-order agreement needs an `ACK` entry.
- Use scoped `git add` only — never `git add -A`.
- No destructive git (`reset --hard`, force-push, mass delete) without an explicit request.
- Protected files (`.env`, CI, Docker, Kubernetes, Terraform) are touched only on explicit request.

## 11. What ships in 5.4.1, and what does not

| Capability | Status | Note |
|---|---|---|
| Project memory, session capture, recall | Shipped | `/mb recall` is model-free BM25 |
| Key rules, profiles, five languages | Shipped | `en ru es pt zh` |
| Brief, discuss, spec, plan | Shipped | `/mb brief` has no overwrite flag |
| `/mb work` presets and cost tiers | Shipped | On Cursor and OpenCode the tier model is static, via installed agents |
| `/mb team` | Shipped, new | No daemon; the orchestrator session is the runtime. Never pushes |
| `/mb drive` | Shipped, rebuilt | Needs a validated goal file |
| `/mb goal` | Partial | Scaffold and validate only; no `status`, `set`, `done` or `list` lifecycle |
| `/mb qa` | Shipped, new | Claude Code, Codex, OpenCode, Pi. One runner per run |
| Code graph | Shipped | Python, Bash, Bats built in; Go, JS, TS, Rust, Java need tree-sitter |
| Call resolution | Partial | Import-aware for Python; name-based for the other languages |
| OpenSpec round-trip | Shipped, new | Conflicts write nothing |
| `/mb cost` | Partial | Reads Claude Code transcripts only |
| Hermes Agent | Shipped, new | Installed by hand with symlinks, not by `memory-bank install` |
| Local build check in the firewall | Not shipped | `build` always resolves to a skip |

## 12. Where to read more

| Topic | File |
|---|---|
| Any command's contract | `$SKILL_DIR/commands/<name>.md` |
| Any `/mb` sub-command | `$SKILL_DIR/references/mb/<name>.md`, or `/mb help <name>` |
| Task tiers | `$SKILL_DIR/references/effort-tiers.md` |
| Coordination between sessions | `$SKILL_DIR/references/coordination.md` |
| Agreements | `$SKILL_DIR/references/agreements.md` |
| Orchestrator console | `$SKILL_DIR/references/orchestrator-console.md` |
| Pipeline config | `$SKILL_DIR/docs/pipeline-yaml.md` |
| The flow, team, drive, QA guides | `$SKILL_DIR/docs/{flow,mb-team,mb-drive,mb-qa,routes-and-firewall}.md` |
