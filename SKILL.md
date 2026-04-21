---
name: memory-bank
description: "Agent-agnostic long-term project memory through `.memory-bank/` + RULES (TDD/SOLID/Clean Architecture/FSD/Mobile) + dev-toolkit commands. Use when working in a project with a `.memory-bank/` directory or when the user explicitly asks for memory-bank workflow, code rules, or dev-toolkit commands."
---

# Memory Bank Skill

Three-in-one skill for code agents:

1. **Memory Bank** — long-term project memory through `.memory-bank/` (`STATUS`, `plan`, `checklist`, `RESEARCH`, `BACKLOG`, `progress`, `lessons`, `notes/`, `plans/`, `experiments/`, `reports/`, `codebase/`).
2. **RULES** — global engineering rules: TDD, Clean Architecture (backend), FSD (frontend), Mobile (iOS/Android UDF), SOLID, Testing Trophy.
3. **Dev toolkit** — 18 commands: `/mb`, `/commit`, `/review`, `/test`, `/plan`, `/pr`, `/adr`, `/contract`, `/security-review`, `/db-migration`, `/api-contract`, `/observability`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/start`, `/done`.

Supported host model:
- **Claude Code / OpenCode** — native command surface + global install.
- **Cursor** — native full support: global skill alias (`~/.cursor/skills/memory-bank/`), global hooks (`~/.cursor/hooks.json`), global slash commands (`~/.cursor/commands/`), `~/.cursor/AGENTS.md` with managed section, plus a paste-ready file for Settings → Rules → User Rules. Project-level `.cursor/` adapter remains available as an add-on via `--clients cursor`.
- **Codex** — global skill discovery + `AGENTS.md` hints + project-level `.codex/` adapter; no separate native slash-command surface.
- **Other code agents** — via adapters, `AGENTS.md`, local hooks/configs, or direct CLI/script usage.

---

## Quick start

```bash
# Initialization (stack auto-detect + CLAUDE.md generation)
/mb init                 # same as /mb init --full
/mb init --minimal       # only the .memory-bank/ structure

# Session flow
/mb start                # load context
# ... work, checklist.md updates as tasks complete ...
/mb verify               # verify plan alignment (if there was a plan)
/mb done                 # actualize + note + progress
```

If the host does not support native slash commands, use:
- `commands/mb.md` as the workflow entrypoint;
- the `memory-bank ...` CLI for install/init/doctor flows;
- bundled scripts and agent prompts from this skill bundle.

---

## Workspace resolution

Memory Bank supports external storage through `.claude-workspace`:

- If the project root contains `.claude-workspace` with `storage: external` and `project_id: <id>` → `mb_path = ~/.claude/workspaces/<id>/.memory-bank`
- Otherwise → `mb_path = ./.memory-bank` (default)

When invoking MB Manager or scripts, always pass the resolved `mb_path`.

---

## Tools — shell scripts

All scripts live in `scripts/` next to this `SKILL.md`. In global installs, the bundle is typically available through host aliases:
- Claude Code: `~/.claude/skills/memory-bank/`
- Codex: `~/.codex/skills/memory-bank/`
- Cursor: `~/.cursor/skills/memory-bank/`

Scripts work with `.memory-bank/` in the current directory or through the `mb_path` argument.

| Script | Purpose |
|--------|---------|
| `mb-context.sh [--deep]` | Build context from core files (`STATUS` + `plan` + `checklist` + `RESEARCH` + codebase summary). `--deep` shows full codebase docs |
| `mb-search.sh <q> [--tag t]` | Search. `--tag` filters via `index.json` |
| `mb-note.sh <topic>` | Create `notes/YYYY-MM-DD_HH-MM_<topic>.md`. Collision-safe (`_2` / `_3`) |
| `mb-plan.sh <type> <topic>` | Create `plans/YYYY-MM-DD_<type>_<topic>.md` with `<!-- mb-stage:N -->` markers |
| `mb-plan-sync.sh <plan>` | Synchronize plan ↔ checklist + `plan.md` (idempotent) |
| `mb-plan-done.sh <plan>` | Close a plan: `⬜→✅` + move to `plans/done/` |
| `mb-metrics.sh [--run]` | Language-agnostic metrics (12 stacks). `--run` captures `test_status=pass|fail` |
| `mb-index.sh` | Registry of all entries (core + notes/plans/experiments/reports) |
| `mb-index-json.py` | Build `index.json` (frontmatter notes + lessons headings). Atomic |
| `mb-upgrade.sh [--check|--force]` | Self-update the skill from GitHub |
| `_lib.sh` | Shared helpers sourced by other scripts |

---

## Agents — subagents (sonnet)

| Agent | When to invoke | Prompt |
|-------|----------------|--------|
| `mb-manager` | `/mb context`, `search`, `note`, `tasks`, `done`, `update`, PreCompact hook | `agents/mb-manager.md` |
| `mb-doctor` | `/mb doctor` — memory-bank inconsistencies (use `mb-plan-sync.sh` first, only edit for semantic drift) | `agents/mb-doctor.md` |
| `mb-codebase-mapper` | `/mb map [focus]` — scan the codebase → `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md` | `agents/mb-codebase-mapper.md` |
| `plan-verifier` | `/mb verify` — required before `/mb done` when work followed a plan | `agents/plan-verifier.md` |

Do **NOT** delegate plan creation, architectural decisions, or ML-result evaluation to a subagent — that is main-agent work.

### Invocation format

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="<description>",
  prompt="<contents of agents/<agent>.md>\n\naction: <action>\n\n<context>"
)
```

---

## Host-specific notes

### Claude Code and native memory

Claude Code has built-in `auto memory` (user-level cross-project memory in `~/.claude/projects/.../memory/`). This skill does **not replace** it — the two complement each other:

| Aspect | `.memory-bank/` | Native `auto memory` |
|--------|------------------|----------------------|
| Scope | Project | User, cross-project |
| Stores | Status, plans, checklists, research, ADRs, lessons | Preferences, role, feedback |
| Owner | Team (via git) | Individual user |

Rule of thumb: if it helps a teammate pick up the project tomorrow, store it in `.memory-bank/`. If it helps you in another project, store it in native memory. They can coexist without conflict.

### Codex

For Codex, this skill is positioned as a global skill bundle plus a guidance layer:
- discovery goes through `~/.codex/skills/memory-bank/`
- global entrypoint/guidance goes through `~/.codex/AGENTS.md`
- hook/config integration remains primarily project-level through `.codex/`

Codex therefore uses the same Memory Bank workflow, but it does not need to expose the same native command surface as Claude Code/OpenCode.

### Cursor

Cursor is a first-class global target. `install.sh` writes five artifacts to `~/.cursor/`:

| Artifact | Purpose |
|----------|---------|
| `~/.cursor/skills/memory-bank/` | Personal skill alias — Cursor auto-discovers it by description |
| `~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` | Global hooks: `sessionEnd` (autosave), `preCompact` (reminder), `beforeShellExecution` (block-dangerous). Each entry tagged `_mb_owned: true` so user hooks are preserved |
| `~/.cursor/commands/*.md` | User-level slash commands mirrored from the skill `commands/` directory |
| `~/.cursor/AGENTS.md` | Marker section `memory-bank-cursor:start/end` — entrypoint for future Cursor versions that read global `AGENTS.md` |
| `~/.cursor/memory-bank-user-rules.md` | Paste-ready rules bundle for **Settings → Rules → User Rules** (Cursor exposes no file API for global User Rules, so this is a one-time manual step) |

Cursor User Rules paste flow:

```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```

The project-level adapter (`.cursor/rules/memory-bank.mdc` + `.cursor/hooks.json`) remains available and is installed only when the user passes `--clients cursor`. Global and project-level installs coexist — Cursor merges hooks from both.

---

## Private content — `<private>...</private>` (since v2.1)

Markdown syntax for excluding sensitive information (client data, API keys, partner names) from indexing and search:

```markdown
---
type: note
tags: [auth, partner-x]
importance: high
---

Discussed with client <private>Jane Doe, +1-555-***</private>.
Integration with <private>api_key=sk-abc123...</private> is scheduled for Tuesday.
```

**Protection model:**
- Content inside `<private>...</private>` does **not** go into `index.json` (neither `summary` nor `tags`)
- `mb-search` output redacts it as `[REDACTED]` (inline) or `[REDACTED match in private block]` (multi-line)
- The entry gets a `has_private: true` flag for downstream filtering
- An unclosed `<private>` without `</private>` makes the rest of the file private (fail-safe)
- `hooks/file-change-log.sh` warns when committing a file containing `<private>` blocks (reminder to review git exposure)

**Double confirmation for reveal:**
```bash
# Rejected without env:
mb-search --show-private <query>
# [error] --show-private requires MB_SHOW_PRIVATE=1

# Only with explicit opt-in:
MB_SHOW_PRIVATE=1 mb-search --show-private <query>
```

**Important:** `<private>` protects against leakage through `index.json` / `mb-search`, but it does **not** filter `git diff`. For full protection, consider `.gitattributes` filters or git hooks.

---

## Auto-capture (since v2.1)

The SessionEnd hook automatically appends a placeholder entry to `progress.md` when a session ends without an explicit `/mb done`. Work is not lost even if manual actualization was skipped.

**Modes (`MB_AUTO_CAPTURE` env):**
- `auto` (default) — hook writes an entry on session end
- `strict` — hook skips but prints a warning to stderr (for flows where manual actualization is required)
- `off` — full noop

**How it works:**
- After successful `/mb done`, the command writes `.memory-bank/.session-lock` → the hook sees the fresh lock (<1h) and skips auto-capture (manual actualization already happened)
- Without a lock, the hook adds a short note to `progress.md`. Full details can be reconstructed by `/mb start` in the next session (MB Manager can read the JSONL transcript)
- Concurrency-safe through a short `.auto-lock` (30 seconds) — prevents duplicates on parallel invocations
- Idempotent by `session_id` — same session + same day = one entry

**Opt-out:** `export MB_AUTO_CAPTURE=off` in `~/.zshrc` or disable the hook via `/mb upgrade` once that flag is available.

---

## Weekly compact reminder (since v2.2.1)

The SessionEnd hook `hooks/mb-compact-reminder.sh` reminds the user to run `/mb compact` once a week — **only if the user has explicitly run `/mb compact --apply` at least once** (which creates `.memory-bank/.last-compact`). It is opt-in by design, so new installs stay silent.

**Logic:**
- `.last-compact` missing → silent (user not subscribed)
- `.last-compact` < 7 days → silent
- `.last-compact` ≥ 7 days + `mb-compact.sh --dry-run` shows `candidates > 0` → reminder to stderr with a `/mb compact` hint
- `.last-compact` ≥ 7 days + `candidates=0` → silent (nothing to compact)

**Opt-out:** `export MB_COMPACT_REMIND=off`. Read-only — it never changes files.

---

## References

- Metadata protocol + `index.json` + 8 key rules: `references/metadata.md`
- Planning + Plan Verifier workflow: `references/planning-and-verification.md`
- Templates: `references/templates.md`
- Structure: `references/structure.md`
- Workflow: `references/workflow.md`
- CHANGELOG: `CHANGELOG.md`
- Migration v1→v2: `docs/MIGRATION-v1-v2.md`
- Primary entrypoint:
  - `/mb` — if the host supports native commands
  - `commands/mb.md` / `memory-bank` CLI — if native command surface is unavailable
