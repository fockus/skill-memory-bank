---
description: "Memory Bank — long-term project memory management"
allowed-tools: [Bash, Read, Write, Edit, Task, Glob, Grep]
---

# Memory Bank — /mb

The `/mb` command is the single entrypoint for managing project Memory Bank (`.memory-bank/`).

## Subcommands

Arguments: `$ARGUMENTS`

Determine the subcommand from the first word of `$ARGUMENTS`. Remaining words are parameters for that subcommand.

### Routing

#### GraphRAG-lite retrieval routing

`code_context is the default` for ambiguous code-understanding questions such as "where is the logic for X?" and "find similar implementation". Exact structural questions use graph tools directly: "who calls/imports/defines X?" → `graph_neighbors`, "reverse deps" or impact analysis → `graph_impact`, and "what tests cover this file/symbol?" → `graph_tests`. User explicitly asks "semantic search" → `search_code`; respect explicit tool intent.

Fail open: for missing graph or stale graph, explain the limitation and suggest `/mb graph --apply`; for missing semantic provider or unavailable native extension, use `scripts/mb-code-context.py`, `scripts/mb-graph-query.py`, `rg`, and `read` as CLI fallback instead of blocking.


| Subcommand                                               | Action                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| (empty) or `context`                                     | Collect project context                                                                                                                                                                                                                                                                                  |
| `start`                                                  | Extended session start                                                                                                                                                                                                                                                                                   |
| `search <query>`                                         | Search information in the memory bank                                                                                                                                                                                                                                                                    |
| `note <topic>`                                           | Create a note                                                                                                                                                                                                                                                                                            |
| `update`                                                 | Actualize core files (with real code-state analysis)                                                                                                                                                                                                                                                     |
| `doctor`                                                 | Find and fix internal MB inconsistencies                                                                                                                                                                                                                                                                 |
| `tasks`                                                  | Show unfinished tasks                                                                                                                                                                                                                                                                                    |
| `index`                                                  | Registry of all entries                                                                                                                                                                                                                                                                                  |
| `done`                                                   | End session (`actualize + note + progress`)                                                                                                                                                                                                                                                              |
| `plan <type> <topic>`                                    | Create a plan                                                                                                                                                                                                                                                                                            |
| `discuss <topic>`                                        | 5-phase requirements-elicitation interview → EARS-validated `context/<topic>.md` (Phase 1 Purpose & Users / Phase 2 Functional EARS / Phase 3 Non-Functional / Phase 4 Constraints / Phase 5 Edge Cases). Feeds traceability matrix.                                                                     |
| `sdd <topic> [--force]`                                  | Create Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`. If `context/<topic>.md` exists, EARS section copied verbatim into `requirements.md`. `--force` overwrites.                                                                                                                 |
| `config <init\|show\|validate\|path>`                    | Manage execution `pipeline.yaml` (spec §9). `init` copies bundled default into `<bank>/pipeline.yaml`; `show` prints resolved config; `validate` runs schema check; `path` prints absolute path of resolved file.                                                                                       |
| `work [target] [--range A-B] [--dry-run]`                | Execute stages from a plan. Auto-selects role-agent per stage (mb-backend / mb-frontend / mb-ios / mb-android / mb-architect / mb-devops / mb-qa / mb-analyst, fallback mb-developer). Sprint 2: implement-step dispatch + dry-run; Sprint 3 adds review-loop, severity gates, verifier integration.    |
| `verify`                                                 | Verify plan execution (plan vs code)                                                                                                                                                                                                                                                                     |
| `map [focus]`                                            | Scan the codebase and write MD documents to `.memory-bank/codebase/`. Focus: `stack / arch / quality / concerns / all` (default: `all`)                                                                                                                                                                  |
| `upgrade`                                                | Update the skill from GitHub (`git pull + re-install`). Flags: `--check` (check only), `--force` (skip confirmation)                                                                                                                                                                                     |
| `compact [--dry-run|--apply]`                            | Status-based decay: plans in `done/` older than 60d → BACKLOG archive, low-importance notes older than 90d → `notes/archive/`. Active plans are not touched. `--dry-run` (default) = reasoning only                                                                                                      |
| `import --project <path> [--since YYYY-MM-DD] [--apply]` | Bootstrap MB from Claude Code JSONL (`~/.claude/projects/<slug>/*.jsonl`). Extracts `progress.md` (daily), `notes/` (architecture-discussion heuristic), PII auto-wrap. Dedup via SHA256 + resume state                                                                                                  |
| `graph [--apply] [--cochange] [src_root]`                | Multi-language code graph: Python (stdlib `ast`, always on) + Go/JS/TS/Rust/Java (via tree-sitter, opt-in through `pip install tree-sitter tree-sitter-go ...`). Output: `codebase/graph.json` (JSON Lines, `community` ids) + `codebase/god-nodes.md` (Top symbols / Top modules + Communities & Bridge files via optional networkx). Incremental SHA256 cache. Opt-in `--cochange` adds deterministic git co-change file edges (`co_change` kind) the static graph cannot see |
| `tags [--apply] [--auto-merge]`                          | Normalize frontmatter tags: detect synonyms via Levenshtein ≤2 against a closed vocabulary and propose merges. `--auto-merge` only applies distance ≤1. Vocabulary is in `.memory-bank/tags-vocabulary.md` (fallback: `references/tags-vocabulary.md`). `mb-index-json.py` auto-normalizes to kebab-case |
| `init [--minimal|--full]`                                | Initialize Memory Bank. `--full` (default): add RULES + CLAUDE.md with stack autodetect. `--minimal`: structure only                                                                                                                                                                                     |
| `profile <subcommand>`                                   | Manage rule profiles: `init`, `show`, `path`, `validate`, `set`. See `commands/profile.md`. Example: `mb-profile.sh init --scope=user --role=backend --stack=go`                                                                                                                                        |
| `install [<clients>]`                                    | Install Memory Bank for the project. If `<clients>` is empty, ask for an 8-client multiselect (`claude-code/cursor/windsurf/cline/kilo/opencode/pi/codex`). Calls `memory-bank install --clients ... --project-root $PWD`                                                                                |
| `help [subcommand]`                                      | Help. No argument → list all subcommands. With argument → show details for that specific one (`/mb help compact`, `/mb help tags`, ...)                                                                                                                                                                  |
| `deps [--install-hints]`                                 | Dependency check (required: `python3`, `jq`, `git`; optional: `rg`, `shellcheck`, `tree-sitter`, `PyYAML`). `--install-hints` prints OS-specific install commands                                                                                                                                        |
| `idea <title> [HIGH\|MED\|LOW]`                          | Capture new idea in `backlog.md` with auto-generated monotonic `I-NNN` ID (priority defaults to `MED`)                                                                                                                                                                                                    |
| `idea-promote <I-NNN> <type>`                            | Promote an idea → plan. Creates plan file via `mb-plan.sh`, flips idea status `NEW\|TRIAGED → PLANNED`, adds `**Plan:** [plans/...]` link, runs plan-sync. `type ∈ feature\|fix\|refactor\|experiment`                                                                                                    |
| `adr <title>`                                            | Capture Architecture Decision Record with auto-generated monotonic `ADR-NNN` ID inside `backlog.md ## ADR` section — skeleton includes Context / Options / Decision / Rationale / Consequences                                                                                                           |
| `migrate-structure [--dry-run\|--apply]`                 | One-shot v3.0 → v3.1 structural migrator. Upgrades singular `<!-- mb-active-plan -->` to plural, adds `mb-active-plans` + `mb-recent-done` blocks to `status.md`, restructures `backlog.md` to `## Ideas` + `## ADR` skeleton. Creates `.pre-migrate/<timestamp>/` backup. Idempotent                    |
| (unrecognized)                                           | Search by `$ARGUMENTS`                                                                                                                                                                                                                                                                                   |


---

## Subcommand implementation

### Aliases for `/start`, `/done`, `/plan`

`/mb start`, `/mb done`, and `/mb plan` are aliases that dispatch to the canonical commands:

- `/mb start` → see `commands/start.md` (reads Memory Bank, suggests `/mb map` if `codebase/` empty)
- `/mb done` → see `commands/done.md` (MB Manager actualize + note + `.session-lock`)
- `/mb plan <type> <topic>` → see `commands/plan.md` (mb-plan.sh scaffold + fill + mb-plan-sync.sh)

> **Plan hierarchy reminder:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for size thresholds. Cyrillic «Этап / Спринт / Фаза» — legacy alias, allowed only in archived `plans/done/`.

Invoking `/mb start` = invoking `/start` — same scripts, same subagents, same outcome. Do not duplicate the logic here; read the primary command file and follow it.

### context / search / note / tasks

**Soft v1-layout detection.** Before invoking the subagent for `context` (or `(empty)`), run the v1-layout probe from `commands/start.md` (Pre-flight section). If v1 files are found without v2 counterparts, surface a one-line warning to the user:

```
WARN: v1 Memory Bank layout detected. Run `bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run` to preview the rename, then `--apply`. Context can still be assembled from v1 names during the 2-version backward-compat window.
```

Continue with context loading (do not hard-stop — the scripts fall back to v1 names while the window is open). For `search`, `note`, and `tasks` the warning is optional; the subagent itself handles v1 files.

For these subcommands, run the MB Manager subagent:

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Manager: <action>",
  prompt="<contents of ~/.claude/skills/memory-bank/agents/mb-manager.md>

action: <action>

<task description and current-session context>"
)
```

Concrete actions:

- **context** / **(empty)**: `action: context` — also delegated to `/start` for consistent behavior
- **search ****: **`action: search <query>` where `query` is the remainder of `$ARGUMENTS` after `search`
- **note ****: **`action: note <topic>` + pass what was done in the current session
- **tasks**: `action: tasks`

### update

Actualize core files using automatic analysis of the current project state.

Unlike `done`, **update** does not create a note and does not require a session summary — the agent analyzes the state directly:

1. **Collect metrics through the language-agnostic script**:

```bash
# Detects the stack (python/go/rust/node/multi), outputs key=value:
#   stack=<stack>
#   test_cmd=<cmd>
#   lint_cmd=<cmd>
#   src_count=<N>
# For an unknown stack it returns empty values with a warning on stderr (does not fail).
# Override via .memory-bank/metrics.sh if you need custom metrics.
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh

# Optional — run tests and capture status:
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh --run

# Git context
git log --oneline -5
git diff --stat HEAD~3 2>/dev/null | tail -5
```

1. **Run MB Manager** with the collected metrics:

```
Agent(
  prompt="<contents of ~/.claude/skills/memory-bank/agents/mb-manager.md>

action: actualize

Current metrics from code (from mb-metrics.sh):
- Stack: <detected>
- Tests: <test_status or suggest running them manually>
- Source files: <src_count>
- Lint: <lint output if it was run>
- Recent commits: <git log>
- Changed files: <git diff stat>

Update core files (STATUS metrics, checklist, plan focus) using REAL data from the codebase. Do not rely on the narrative description — verify through grep/find/bash.",
  subagent_type="general-purpose",
  model="sonnet"
)
```

1. Show the user what was updated.

**Note:** if `mb-metrics.sh` returns `stack=unknown`, warn the user that auto-metrics are unavailable and suggest creating `.memory-bank/metrics.sh` with custom logic (see `references/templates.md`).

### doctor

Diagnose and fix inconsistencies INSIDE Memory Bank.

**v2 naming migration check** is delegated to the subagent — see `agents/mb-doctor.md` → "Check: v2 naming migration". The agent will flag v1 files missing their v2 counterpart (WARN) or coexisting v1+v2 pairs (ERROR, manual resolution required) and point the user to `scripts/mb-migrate-v2.sh`.

Run the MB Doctor subagent:

```
Agent(
  prompt="<contents of ~/.claude/skills/memory-bank/agents/mb-doctor.md>

action: doctor

Check consistency across all core files in .memory-bank/:
- roadmap.md statuses vs checklist.md
- status.md metrics vs reality (pytest, source files)
- status.md constraints vs real code
- backlog.md vs roadmap.md
- progress.md completeness
- plan files in plans/ vs their statuses
- duplicates and stale references",
  subagent_type="general-purpose",
  model="sonnet"
)
```

Show the report to the user: what was found, what was fixed, and what still needs a decision.

### index

Quick operation, no subagent:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-index.sh
```

Show the result to the user.

### plan

**Alias** for `/plan` — dispatch to `commands/plan.md`. The canonical planning command lives there: mb-plan.sh scaffold → fill with `<!-- mb-stage:N -->` markers + SMART DoD + TDD per stage → mb-plan-sync.sh to reconcile with `checklist.md` + `roadmap.md`.

Allowed `type` values: `feature`, `fix`, `refactor`, `experiment`. If `type` is missing, ask the user.

### discuss <topic>

Run a 5-phase requirements-elicitation interview that produces an EARS-validated `context/<topic>.md`. Feeds `mb-traceability-gen.sh` (REQ → Plan → Test matrix) and is read by `/mb plan` to link stages to requirements.

**Alias** for `/discuss` — dispatch to `commands/discuss.md` for the canonical workflow.

**Phases:**

1. **Purpose & Users** — who uses this, what problem, success criteria.
2. **Functional Requirements (EARS-enforced)** — assigns IDs via `mb-req-next-id.sh`; validates via `mb-ears-validate.sh`. Five EARS patterns: Ubiquitous (`The ... shall ...`), Event-driven (`When ..., the ... shall ...`), State-driven (`While ..., the ... shall ...`), Optional (`Where ..., the ... shall ...`), Unwanted (`If ..., then the ... shall ...`).
3. **Non-Functional Requirements** — performance, security, scale, observability (NFR-NNN, free-form).
4. **Constraints + Out-of-Scope** — hard limits + explicit exclusions.
5. **Edge Cases & Failure Modes** — boundary conditions, dependency failures.

**Pre-flight:**

- If `<mb>/context/<topic>.md` exists → ask `AskUserQuestion`: continue editing / overwrite / cancel.
- Warm context — read `roadmap.md`, `research.md`, `codebase/STACK.md`, `codebase/ARCHITECTURE.md` (best-effort, skip missing).

**Finalize:**

- Render `context/<topic>.md` per the template in `references/templates.md` ("Context (`context/<topic>.md`)" section).
- `bash scripts/mb-ears-validate.sh "$CONTEXT_FILE"` — must exit 0 before commit. On violations, fix in place and retry.
- `bash scripts/mb-traceability-gen.sh "$MB_PATH"` — regenerate matrix.
- Set frontmatter `status: ready`.

**Exit conditions:**

- Success — file exists, EARS-valid, traceability regenerated.
- Cancel mid-interview — leave `status: draft` so `/mb discuss` resumes later.
- Validation failure user can't fix — keep `status: draft` + surface violation list.

**Out of scope:**

- Does not create a plan (`/mb plan` does that, optionally reading `context/<topic>.md`).
- Does not edit `roadmap.md` / `status.md` directly.

**Related scripts:**

- `bash scripts/mb-req-next-id.sh [--spec <name>] [mb_path]` — emits the next `REQ-NNN`. Default: project-wide max+1 across `specs/*/requirements.md`, `specs/*/design.md`, `context/*.md`. With `--spec <name>`: per-spec-local max+1 scoped to `specs/<name>/{requirements,design}.md` + `context/<name>.md` (a brand-new spec starts at `REQ-001`).
- `bash scripts/mb-ears-validate.sh <file>|-` — exit 0 if every `- **REQ-NNN** ...` bullet matches an EARS pattern; exit 1 with violation list on stderr otherwise; exit 2 on usage error.

### sdd <topic> [--force]

Create the Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`. Each file owns one concern: requirements (EARS-only), design (architecture + interfaces + decisions), tasks (numbered checkboxes).

**Alias** for `/sdd` — dispatch to `commands/sdd.md` for the canonical workflow.

**Behavior:**

1. Resolve `<mb>`. Sanitize topic.
2. If `specs/<safe_topic>/` exists and no `--force` → exit 1.
3. If `<mb>/context/<safe_topic>.md` exists → copy its `## Functional Requirements (EARS)` block verbatim into `requirements.md` (REQ-IDs preserved).
4. Write `requirements.md` (EARS reference + REQ list), `design.md` (Architecture / Interfaces / Decisions / Risks scaffold), `tasks.md` (numbered tasks with `**Covers:** REQ-NNN` placeholders).

**Underlying:** `bash scripts/mb-sdd.sh <topic> [--force] [mb_path]`.

**Connection with `/mb plan`:** the spec triple is the *source of truth* for the topic. `/mb plan <type> <topic>` auto-detects `<mb>/context/<safe_topic>.md` (or accepts `--context <path>`) and adds a `## Linked context` section to the plan. `--sdd` flag in `/mb plan` enforces EARS validity before plan creation.

**Out of scope:**

- Does not run `/mb discuss`. If no context exists yet, `requirements.md` gets an EARS placeholder block.
- Does not validate REQ → task coverage (deferred to `/mb verify` and `/mb work` review-loop).

### config <subcommand>

Manage the project's execution `pipeline.yaml` (spec §9) — the declarative config consumed by `/mb work` (Phase 3 Sprint 2). Defines roles → agents mapping, per-stage `implement → review → verify` loop, severity gates, sprint context guard, review rubric, and SDD enforcement policy.

**Alias** for `/config` — dispatch to `commands/config.md` for the canonical doc.

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `init [--force]` | Copy `references/pipeline.default.yaml` → `<bank>/pipeline.yaml`. Refuses overwrite without `--force`. |
| `show` | Print effective config (`<bank>/pipeline.yaml` if present, otherwise the bundled default). |
| `path` | Print absolute path of the effective config file. |
| `validate [yaml_file]` | Run `scripts/mb-pipeline-validate.sh` against the resolved config (no arg) or a given file. |

All subcommands accept a trailing `[mb_path]` arg pointing at an alternative bank.

**Behavior:**

1. Resolution chain: `<bank>/pipeline.yaml` → `references/pipeline.default.yaml`. The bundled default is always present and self-validates.
2. `init` writes a byte-for-byte copy of the default. Idempotency guard refuses without `--force`.
3. `validate` exits 0 if schema-clean, 1 with `[validate] <key>: <reason>` lines on stderr otherwise.

**Underlying:** `bash scripts/mb-pipeline.sh <subcommand> [args...]`.

**Why pipeline.yaml?** Different teams need different defaults — review tolerance, max review cycles, role-to-agent mapping, protected paths. Hard-coding these would lock the engine. `pipeline.yaml` makes them per-project, version-controlled, and reviewable. Until `/mb work` lands (Phase 3 Sprint 2), `/mb config` is mostly self-documentation; once `/mb work` is live, the resolved config drives every stage.

### work [target] [--range A-B] [--dry-run]

Execute stages from a plan with auto-selected role-agents. Phase 3 Sprint 2 ships target resolution + range parsing + execution-plan emission + implement-step dispatch. Review-loop, severity gates, fix-cycle, and verifier integration land in Phase 3 Sprint 3.

**Alias** for `/work` — dispatch to `commands/work.md` for the canonical workflow.

**Behavior:**

1. **Resolve target** (5 forms — see spec §8.2): existing path → substring in `plans/` → topic name → freeform (≥3 words, exit 3 → orchestrator confirms with user) → empty (active plan from `<!-- mb-active-plans -->` block in `roadmap.md`).
2. **Apply `--range`**: detects level automatically. Plan input → range over `<!-- mb-stage:N -->` markers. Phase input (multiple sprint-plans with `sprint:` frontmatter) → range over sprint numbers.
3. **Emit JSON Lines**: one object per stage with fields `plan`, `stage_no`, `heading`, `role` (auto-detected from heading + body keywords: ios / android / frontend / backend / devops / qa / architect / analyst, fallback `developer`), `agent` (mapped via `pipeline.yaml:roles`), `status`, `dod_lines`. `--dry-run` adds a human-readable header and stops here.
4. **Dispatch**: for each pending stage, invoke `Task` tool with `subagent_type="general-purpose"` and prompt = `<contents of agents/<agent>.md>` + plan path + stage body. The role-agent (mb-developer / mb-backend / mb-frontend / mb-ios / mb-android / mb-architect / mb-devops / mb-qa / mb-analyst) implements against the stage DoD.
5. **Stage close-out**: prompt the user (auto-confirm with `--auto`, deferred to Sprint 3); mark DoD items.

**Underlying scripts:**

```bash
bash scripts/mb-work-resolve.sh [target] [--mb <path>]
bash scripts/mb-work-range.sh <plan> [--range <expr>]
bash scripts/mb-work-plan.sh [--target <ref>] [--range <expr>] [--dry-run] [--mb <path>]
```

**Out of scope (Sprint 3):** review-loop after implement step, severity gates, fix-cycle on `CHANGES_REQUESTED`, `plan-verifier` as the verify step, `--auto` end-to-end with hard stops, `--budget` token tracking, `--slim`/`--full` context strategy (needs hooks from Phase 4), `--allow-protected` enforcement, `superpowers:requesting-code-review` skill override.

### verify

Plan verification — confirm that code matches the plan, all DoD items are satisfied, and nothing important is missing.

1. Find the active plan in `.memory-bank/plans/` (not in `done/`). If there are several, use the most recent one or the one specified in the arguments.
2. Run the Plan Verifier subagent:

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="Plan Verifier: plan verification",
  prompt="<contents of ~/.claude/skills/memory-bank/agents/plan-verifier.md>

Plan file: <path to plan>

Context: <description of current work, which stages are considered complete>"
)
```

1. Get the Plan Verifier report and show it to the user.
2. If there are CRITICAL issues, **fix them** before proceeding.
3. If there are WARNING issues, tell the user and ask whether they should be fixed.

**IMPORTANT:** `/mb verify` is **REQUIRED** before `/mb done` when the work followed a plan. Do not close out a plan without verification.

### map [focus]

Scan the codebase and generate structured MD documents in `.memory-bank/codebase/`.

`focus` values (the first word after `map`):

- `stack` — only `STACK.md` (languages, runtime, integrations)
- `arch` — only `ARCHITECTURE.md` (layers, structure, entrypoints)
- `quality` — only `CONVENTIONS.md` (naming, style, testing)
- `concerns` — only `CONCERNS.md` (tech debt, risks)
- `all` (default, if omitted) — all 4 documents

Run the MB Codebase Mapper subagent:

```
Agent(
  prompt="<contents of ~/.claude/skills/memory-bank/agents/mb-codebase-mapper.md>

focus: <stack|arch|quality|concerns|all>

Analyze the current project and write MD documents directly to `.memory-bank/codebase/`. Use `mb-metrics.sh` for stack detection, follow the ≤70-line templates, and return confirmation only.",
  subagent_type="general-purpose",
  model="sonnet",
  description="MB Codebase Mapper: focus=<focus>"
)
```

**After completion:**

- New/updated Markdown docs live in `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`
- `/mb context` now automatically shows a one-line summary for each doc
- `/mb context --deep` shows the full contents of codebase documents

Tell the user which documents were created/updated, which stack was detected, and suggest `/mb context --deep` for full context.

### upgrade

Update the skill to the latest version from GitHub. Requires a `git clone` installation.

Flags (the first word after `upgrade`):

- (no flags) — check and apply after confirmation
- `--check` — check only (exit 1 if an update is available, exit 0 if already up to date)
- `--force` — apply without interactive confirmation

Run directly (no subagent — this is a systems-level operation, no LLM needed):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-upgrade.sh $ARGS_AFTER_UPGRADE
```

The script:

1. Pre-flight: checks that `~/.claude/skills/skill-memory-bank` is a git repo with a clean working tree
2. Reads the `VERSION` file and local commit hash
3. Runs `git fetch origin` and compares local vs remote (`ahead/behind`)
4. Shows pending commits (`git log HEAD..origin/main`)
5. If `--check` is used — exits with a status code
6. If updates exist and `--force` is not used — asks for confirmation
7. On confirmation: `git pull --ff-only` + re-run `install.sh` (idempotent merge of hooks/commands)
8. Prints `local → new` version

**Typical flow:**

```
User: /mb upgrade
→ script fetches, shows: "3 behind, 0 ahead"
→ shows the latest 3 commits
→ asks: "Apply 3 updates? (y/n)"
→ user: y
→ `git pull` + `bash install.sh` → manifest refreshed
→ "Skill updated: 2.0.0-dev (cd65d0a) → 2.1.0 (abc1234)"
```

**Errors:**

- Skill is not a git clone → suggest reinstalling via clone
- Dirty working tree → suggest `git stash` / `git checkout --`
- Divergent branches → suggest manual pull
- Non-interactive mode without `--force` → error

**IMPORTANT:** The skill repo (`~/.claude/skills/skill-memory-bank`) is the canonical source. After `git pull`, `install.sh` must be rerun to refresh host-specific globals, symlink aliases `~/.claude/skills/memory-bank` and `~/.codex/skills/memory-bank`, and the managed block in `~/.codex/AGENTS.md`. The script does this automatically.

### compact [--dry-run|--apply]

Status-based archival decay. Cleans up old completed plans and unused low-importance notes, **without touching active work**.

**Criteria (AND, not OR):**


| Candidate                              | Age threshold | Done-signal (required)                                                                                                                  |
| -------------------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Plan in `plans/done/`                  | `>60d` mtime  | Primary: already physically in `plans/done/`                                                                                            |
| Plan in `plans/*.md` (active location) | `>60d` mtime  | `✅` / `[x]` marker in `checklist.md` line with the basename, OR mention in `progress.md`/`status.md` as `completed|done|closed|shipped` |
| Note in `notes/*.md`                   | `>90d` mtime  | `importance: low` in frontmatter + **no** basename references in `roadmap.md`/`status.md`/`checklist.md`/`research.md`/`backlog.md`        |


**Safety net:** active plans (not done) are **NOT archived** even if >180d old. Instead, emit a warning like "plan X is older than 180d but not done — check whether it is still relevant".

**Effects of `--apply`:**

- Plans → compressed into one line inside `backlog.md ## Archived plans`, original file deleted. Source path is preserved as `(was: plans/done/<file>.md)` — git history keeps the full text.
- Notes → moved to `notes/archive/` + body compressed to 3 non-empty lines + marker `<!-- archived on YYYY-MM-DD -->`. Entries get `archived: true` in `index.json`.
- Touched `.memory-bank/.last-compact` timestamp.

`--dry-run` (default) — prints reasoning per candidate to stdout, 0 file changes.

Run directly (systems-level, no LLM needed for the decision logic — it is deterministic):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-compact.sh $ARGS_AFTER_COMPACT
```

**Searching the archive:** default `mb-search` does NOT include archived items. Opt in via `mb-search.sh --include-archived <query>` or `--include-archived --tag <tag>`.

**Typical flow:**

```
User: /mb compact
→ dry-run output:
  mode=dry-run
  plans_candidates=2
  notes_candidates=5
  candidates=7

  # Plans to archive:
    archive: plans/done/2026-01-10_feature_x.md (reason=in_done_dir, age=100d)
    archive: plans/done/2026-02-01_fix_auth.md (reason=in_done_dir, age=78d)

  # Notes to archive:
    archive: notes/2025-12-15_experiment.md (reason=low_age_unref, age=125d)
    ...

  # Warnings — active plans older than 180d:
    warning: plans/2025-09-01_long_feature.md is 230d old but not done — check whether it is still relevant

User: /mb compact --apply
→ [apply] archived plan: plans/done/2026-01-10_feature_x.md (reason=in_done_dir)
  [apply] archived note: notes/2025-12-15_experiment.md → notes/archive/
  ...
```

### import --project  [--since YYYY-MM-DD] [--apply]

Bootstrap Memory Bank from Claude Code JSONL transcripts. Cold-start in seconds instead of weeks of manual reconstruction.

**Source:** `~/.claude/projects/<slug>/*.jsonl` — Claude Code stores all session transcripts there. The slug is derived from project paths (for example `-Users-fockus-Apps-X` for `/Users/fockus/Apps/X`).

**Extract strategy:**

- `progress.md` — daily-grouped `## YYYY-MM-DD (imported)` sections with a summary (N user turns + M assistant replies + the first 120 chars of the first user prompt)
- `notes/` — heuristic architectural discussions: ≥3 consecutive assistant messages >1K chars → note `YYYY-MM-DD_NN_<topic-slug>.md` with frontmatter `importance: medium`, tags `[imported, discussion]`, body = compressed first + last message

**Safety:**

- `--dry-run` (default) — stdout summary (jsonls/events/days/notes counts), 0 file changes
- `--apply` — performs writes + touches `.memory-bank/.import-state.json`
- **Dedup:** SHA256(timestamp + first 500 chars of text) persisted in state — two consecutive runs are idempotent
- **PII auto-wrap:** email + API key (`sk-...`, `sk-ant-...`, `Bearer <long>`, `gh[pousr]_<long>`) regex → `<private>...</private>`. This intersects with Stage 3 so imported data is protected from leaking into `index.json` / search
- **Resume:** `.import-state.json` stores `seen_hashes` — repeated imports skip already-seen events
- **Broken JSONL line:** skip with warning; continue parsing the rest

Run directly:

```bash
python3 ~/.claude/skills/memory-bank/scripts/mb-import.py $ARGS_AFTER_IMPORT
```

**Typical cold-start flow:**

```
User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01
→ dry-run output:
  jsonls=5
  events=342
  days=18
  notes=12
  mode=dry-run

User: /mb import --project ~/.claude/projects/-Users-fockus-Apps-myproject/ --since 2026-03-01 --apply
→ writes progress.md (18 daily sections) + 12 notes → state saved
  jsonls=5 events=342 days=18 notes=12 mode=apply
```

**Limitations in v2.2:**

- Summarization is currently deterministic (first+last chars), not LLM-based. Haiku-powered compression is backlog for v2.3+ if summary quality proves insufficient
- Debug-session detection for `lessons.md` — TODO (v2.2+)
- `status.md` seed — manual only

### graph [--apply] [--cochange] [src_root]

Build a code graph for the Python part of the project through stdlib `ast` (0 new deps). Replaces `grep` for questions like "where is X called?", "which classes inherit from Y?", "what is imported from model.py?" — deterministic, fast, incremental.

Extraction engines live in the `memory_bank_skill` package: `codegraph_python` (stdlib `ast`), `codegraph_treesitter` (opt-in multi-language), `codegraph_analytics` (degree split / communities / betweenness), `codegraph_cochange` (git co-change). `mb-codegraph.py` is a thin orchestrator over them.

**What it parses:**

- **Nodes:** module (per file), function (top-level + nested), class
- **Edges:** `import` (import X / from Y import Z), `call` (func() / obj.method()), `inherit` (class Child(Parent))

**Output (`--apply`):**

- `<mb>/codebase/graph.json` — JSON Lines (one node/edge per line, grep-friendly, streamable). Node lines carry a `community` id when networkx is installed. With `--cochange`, additional `{"kind":"co_change","weight":N}` edges are appended.
- `<mb>/codebase/god-nodes.md` — analytics report: **Top symbols** + **Top modules** (degree, split so test-module hubs no longer drown real abstractions) and, when networkx is available, **Communities** (auto-detected module clusters + cohesion score) + **Bridge files** (highest betweenness — refactoring/risk hotspots). With `--cochange`, a **Co-changing file pairs** section is appended.
- `<mb>/codebase/.cache/<hash>.json` — per-file SHA256 → parsed entities

**Analytics (optional `networkx`):** file-level community detection (Louvain, `seed=42` → deterministic), per-cluster cohesion, and betweenness all live in the pure module `memory_bank_skill/codegraph_analytics.py`. Without networkx the report degrades gracefully (Top symbols / Top modules still render; community/bridge sections are omitted with a one-line note). Install: `pip3 install networkx`.

**Co-change edges (opt-in `--cochange`):** files that change together across git history are coupled regardless of static imports/calls — a deterministic, $0 signal the AST/tree-sitter graph cannot see (e.g. a config file and the code that reads it, a test and its subject). Computed in the pure module `memory_bank_skill/codegraph_cochange.py` from `git log` (last 200 commits, bulk commits >25 files skipped, pairs needing ≥2 shared commits). Requires `--apply`; `git` is already a required dependency. Default (flag off) keeps `graph.json` + `god-nodes.md` byte-identical. Outside a git repo it degrades to zero co-change edges.

**Incremental:** if `sha256(file_content)` matches the cache — skip re-parse. On a large repo, the second run is near-instant.

**Safety:**

- `--dry-run` (default) — stdout summary (nodes/edges/reparsed/cached), 0 file changes
- `--apply` — writes all outputs + updates cache
- `--cochange` — appends git co-change edges (opt-in; requires `--apply`; no-op outside a git repo)
- Broken syntax → skip with warning, batch continues
- `.venv/`, `__pycache__/`, `.*/` — excluded

Run directly:

```bash
python3 ~/.claude/skills/memory-bank/scripts/mb-codegraph.py $ARGS_AFTER_GRAPH
```

**Typical flow:**

```
User: /mb graph
→ dry-run output:
  nodes=52
  edges=388
  reparsed=3
  cached=0
  mode=dry-run

User: /mb graph --apply
→ nodes=52 edges=388 reparsed=3 cached=0 mode=apply
  [writes codebase/graph.json + god-nodes.md + .cache/]

# Modified 1 file, reran:
User: /mb graph --apply
→ `reparsed=1 cached=2` — one file re-parsed, two loaded from cache
```

**Example top god-nodes (dogfood on this repo):**

```
| # | Name          | Kind     | File:Line            | Degree |
|---|---------------|----------|----------------------|--------|
| 1 | run_import    | function | mb-import.py:185     | 60     |
| 2 | main          | function | mb-index-json.py:187 | 23     |
| 3 | _atomic_write | function | mb-import.py:157     | 22     |
```

**Integration with `mb-codebase-mapper`:** the agent uses `graph.json` as the source for CONVENTIONS and CONCERNS instead of grep (backlog for v2.3).

**Language support (v2.2 + Stage 6.5):**

- **Always works** (stdlib `ast`): Python (`.py`)
- **Opt-in** (requires tree-sitter + grammars): Go (`.go`), JavaScript (`.js`/`.jsx`/`.mjs`), TypeScript (`.ts`/`.tsx`), Rust (`.rs`), Java (`.java`)
- Install tree-sitter: `pip install tree-sitter tree-sitter-go tree-sitter-javascript tree-sitter-typescript tree-sitter-rust tree-sitter-java`
- Without tree-sitter: non-Python files are silently skipped (graceful degradation). The `HAS_TREE_SITTER` flag in the script reflects the status
- Skipped directories: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`, any `.`*

**Limitations:**

- Type inference is absent — edges work on names only (`foo()` calls do not distinguish modules with the same function name). Name resolution through imports — TODO v2.3+
- Tree-sitter extractor is intentionally simplified (MVP): not all language edge cases are covered — if you notice a missing node, open an issue
- `god-nodes.md` wiki/per-node documentation — deferred (YAGNI until there is real demand)
- C/C++/Ruby/PHP/Kotlin/Swift are not supported (can be added on demand via a new entry in `LANG_CONFIG` in `memory_bank_skill/codegraph_treesitter.py`)

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
- `tree_sitter` (Python package) + grammars — multi-language `/mb graph` (Go/JS/TS/Rust/Java). Without it, only Python works
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
bash ~/.claude/skills/memory-bank/scripts/mb-deps-check.sh $ARGS_AFTER_DEPS
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

### help [subcommand]

Help for `/mb` subcommands. Single source of truth — reads `~/.claude/skills/memory-bank/commands/mb.md` directly.

**Modes (first word after `help`):**

1. `**/mb help`** (no argument) — print the router table of all subcommands with one-line descriptions.
2. `**/mb help <subcommand>**` — extract and show the detailed implementation block for that subcommand (sections like `### <subcommand>`).

**Algorithm for the agent:**

```bash
SKILL_MD="$HOME/.claude/skills/memory-bank/commands/mb.md"
SUB="$SUBCOMMAND_ARG"  # first word after "help"; may be empty

SKILL_MD="$SKILL_MD" SUB="$SUB" python3 - <<'PY'
import os, sys
path = os.environ["SKILL_MD"]
sub = os.environ.get("SUB", "").strip()
lines = open(path, encoding="utf-8").read().splitlines()

if not sub:
    # Mode 1: router table — between "### Routing" and the next "---"
    in_section = False
    for line in lines:
        if line.startswith("### Routing"):
            in_section = True
            continue
        if in_section and line.startswith("---"):
            break
        if in_section:
            print(line)
    print("\nDetails: /mb help <subcommand>  (e.g. /mb help compact)")
    sys.exit(0)

# Mode 2: extract "### SUB" block (exact, space-after, or bracket-after)
header = f"### {sub}"
in_block = False
for line in lines:
    is_header = line == header or line.startswith(header + " ") or line.startswith(header + "[")
    if is_header:
        in_block = True
        print(line)
        continue
    if in_block and line.startswith("### "):
        break
    if in_block and line.rstrip() == "---":
        break
    if in_block:
        print(line)
PY
```

**Examples:**

```
User: /mb help
→ prints the router table with 18 subcommands

User: /mb help compact
→ prints the full section "### compact [--dry-run|--apply]" with logic,
  examples, and limitations

User: /mb help tags
→ prints the section "### tags [--apply] [--auto-merge]"
```

**Do not confuse with:**

- `/help` — built-in Claude Code command (not a skill).
- `commands/catchup.md` / `commands/start.md` / `commands/done.md` — standalone top-level slash commands (lightweight), not `/mb` subcommands.

### init [--minimal|--full] [--storage=local|global] [--agent=NAME] [--lang=XX]

Initialize Memory Bank in a new project.

**Modes** (first word after `init`):

- `--minimal` — only `.memory-bank/` structure + core files. For advanced users who will write `CLAUDE.md` themselves.
- `--full` (default, if no flag is provided) — `.memory-bank/` + `RULES.md` copy + stack auto-detect + `CLAUDE.md` generation + optional `.planning/` symlink prompt.

**Storage (`--storage`)** — since Sprint 1 / global-storage, Memory Bank supports two storage layouts. Default is local (backward compatible).

- `--storage=local` (default) — bank lives at `<project>/.memory-bank/`. **Team-shared** layout: the directory is committable so the whole team shares status / plans / checklist / progress. Use this for any project where Memory Bank state is part of the codebase contract.
- `--storage=global` — bank lives under the chosen agent config directory (`$HOME/.claude/memory-bank/projects/<id>/` for Claude Code, `$HOME/.pi/agent/memory-bank/projects/<id>/` for Pi, etc.) and is registered in `<agent_config>/memory-bank/registry.json`. **Repository stays clean** — no `.memory-bank/` appears in the project tree. Use this for personal storage in a third-party repo, where committing Memory Bank state would create noise for other contributors.

When `--storage=global` is requested, the agent must also resolve `--agent=NAME` (one of `claude-code`, `cursor`, `codex`, `opencode`, `pi`, `windsurf`, `cline`, `kilo`). Default in non-interactive runs comes from `$MB_AGENT` or `claude-code`.

**Interactive prompt** (when stdin is a TTY and `--storage` is not given):

```
Where should this project's Memory Bank live?
  1. local  — .memory-bank/ inside the project (team-shared, default)
  2. global — personal storage under the agent config dir (repo stays clean)
(1/2, default = 1)
```

**Non-interactive shell equivalents** (CI, dotfile bootstrap, scripts):

```bash
# Local mode (team-shared):
bash scripts/mb-init-bank.sh --storage=local --lang=ru

# Global mode (personal, repo stays clean):
bash scripts/mb-init-bank.sh --storage=global --agent=pi \
                             --project-root "$PWD" --lang=ru
```

Safety contract: existing local `.memory-bank/` refuses an implicit local→global switch. The script exits non-zero with migration guidance unless `--force` is provided (and even with `--force` no data is moved — `--force` only allows a parallel global bank).

**Locale (`--lang`)** — since v3.1.1 Memory Bank ships localized template bundles:

- `--lang=en` (default) — English templates
- `--lang=ru` — full Russian translation
- `--lang=es`, `--lang=zh` — scaffolds (EN copy + `TODO(i18n-<lang>)` banner; community translations welcome via PR, see `docs/i18n.md`)

Locale resolution (highest → lowest): `--lang` flag → `MB_LANG` env → `.memory-bank/.mb-config` (`lang=XX`) → auto-detect from existing bank content → `en`.

The agent should invoke `scripts/mb-init-bank.sh --lang=<resolved> --storage=<resolved> [--agent=<resolved>]` to copy the correct `templates/locales/<lang>/.memory-bank/` bundle and wire the storage layout. Canonical anchors (`<!-- mb-active-plans -->`, `## Ideas`, `## ADR`) stay English across every locale — every `mb-*` script depends on them.

> **Rules-only mode reminder.** A project may deliberately have *neither* local nor global Memory Bank (`[MEMORY BANK: ABSENT]`). In that case `/mb` lifecycle commands stay inactive, but the **engineering rules baseline still applies**: TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders. Skipping `/mb init` is a valid user choice — never auto-initialize on first response.

---

#### Step 1: Create the structure

```bash
mkdir -p .memory-bank/{experiments,plans/done,notes,reports,codebase}
```

Core files (templates — `~/.claude/skills/memory-bank/references/templates.md`):

- `status.md` — project header, "Current phase: Start"
- `roadmap.md` — "Current focus: define", `## Active plan` section with markers `<!-- mb-active-plan -->` / `<!-- /mb-active-plan -->` (for auto-sync)
- `checklist.md` — empty checklist
- `research.md` — header + empty hypothesis table
- `backlog.md` — header + empty sections (HIGH/LOW ideas, ADRs)
- `progress.md` — header
- `lessons.md` — header

**If `--minimal` — stop here.** Report `[MEMORY BANK: INITIALIZED]` + a hint to run `/mb start`.

---

#### Step 1.5: Offer to populate `codebase/` (`--full` only)

Before continuing to RULES and stack detection, ask the user whether the skill should seed `.memory-bank/codebase/` now via the `mb-codebase-mapper` subagent:

```
Populate .memory-bank/codebase/ with STACK / ARCHITECTURE / CONVENTIONS / CONCERNS?
This launches the `mb-codebase-mapper` subagent (sonnet) with focus=all.
Default: skip — you can run `/mb map` anytime later.
(y/N)
```

If the answer is `y`, run the subagent exactly as documented in `### map [focus]` with `focus: all`. If the answer is `N` or empty, skip and continue to Step 2 — never auto-invoke the mapper. The folder stays empty; `/mb start` will suggest `/mb map` on the next session if still empty.

---

#### Step 2: Copy RULES (`--full` only)

```bash
cp ~/.claude/RULES.md .memory-bank/RULES.md
# If it already exists — compare via diff and ask the user before overwriting
```

---

#### Step 3: Auto-detect the stack (`--full` only)

Run `mb-metrics.sh` to detect the stack, then enrich it with more detailed information:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh
# → stack, test_cmd, lint_cmd, src_count
```

Augment with framework information (grep imports/deps):

- Python: FastAPI, Django, Flask (pyproject.toml + imports)
- Node: Next.js, Express, Nest (package.json deps)
- Go: gin, echo, fiber (go.mod)
- Frontend: React/Vue/Angular/Svelte + FSD layers (check `src/app/`, `src/pages/`, `src/features/`, `src/entities/`, `src/shared/`)

Store the results: `{LANGUAGE}`, `{FRAMEWORK}`, `{STRUCTURE}`, `{TOOLS}`.

---

#### Step 4: Generate `CLAUDE.md` (`--full` only)

Use the template from `~/.claude/skills/memory-bank/references/claude-md-template.md`. Fill in `{LANGUAGE}`, `{FRAMEWORK}`, `{TOOLS}`, project structure, and key dependencies.

Required sections in generated `CLAUDE.md`:

- **Project** — name and description
- **Technology Stack** — languages, runtime, frameworks, package manager
- **Conventions** — naming patterns (detect from existing code), code style
- **Architecture** — for backend: Clean Architecture dependency direction; for frontend: FSD layers
- **Rules** — link to `~/.claude/RULES.md` + `.memory-bank/RULES.md` + short critical rules (TDD, Contract-First, Clean Arch/FSD, SOLID thresholds, coverage)
- **Memory Bank** — `/mb` command and key files

**Show the user the draft before writing it.** Ask: "Write CLAUDE.md? Anything to add or change?"

---

#### Step 5: `.planning/` symlink (`--full` only, optional)

If `.planning/` already exists (from GSD or other tools) and `.memory-bank/.planning/` does not exist:

```
I suggest moving `.planning/` inside `.memory-bank/`:
  mv .planning .memory-bank/.planning
  ln -s .memory-bank/.planning .planning

This keeps project artifacts in one directory.
The symlink preserves GSD compatibility.

Do this? (y/n)
```

If `y` — execute it. If `n` — leave everything as-is.

---

#### Step 5.5: Optional profile setup (`--full` only)

After the symlink step, offer to configure a project rule profile:

```
Would you like to configure a rule profile for this project now?
  This personalizes stack/architecture/delivery rules on top of the immutable baseline.
  Skipping keeps the immutable baseline active — you can run `/mb profile init` anytime.
  (y/N)
```

If the answer is `y`, run:

```bash
mb-profile.sh init --scope=project [--role=...] [--stack=...] [--architecture=...] [--delivery=...]
```

Do **not** make profile setup mandatory. Skipping a profile keeps the immutable safety baseline active without any reduction in safety guarantees.

If the user prefers a user-global profile (so it applies across all projects, even without Memory Bank):

```bash
mb-profile.sh init --scope=user --role=<role> --stack=<stack>
```

**Note:** `--profile-skip` documents that skipping is intentional. `--profile-auto` (future flag) would apply stack auto-detection as an advisory recommendation before user confirmation.

---

#### Step 6: Summary

Print:

- Created files: `.memory-bank/` + `CLAUDE.md` (if `--full`)
- Detected stack: `{language}`, `{framework}`, `{tools}`
- Report: `[MEMORY BANK: ACTIVE]`
- Suggest the next steps:
  - `/mb start` — load context in subsequent sessions
  - `/mb map` — populate `.memory-bank/codebase/` (STACK / ARCHITECTURE / CONVENTIONS / CONCERNS) if skipped in Step 1.5
  - `/mb profile init --scope=project` — personalize rule profile (if skipped in Step 5.5)
  - (if the project needs planning) `/mb plan feature "<topic>"`

---

### profile <subcommand>

Manage rule profiles — configurable role, stack, architecture, and delivery presets layered on top of the immutable safety baseline. See the full command documentation in `commands/profile.md`.

**Quick examples:**

```bash
# User-global profile (no project Memory Bank required):
mb-profile.sh init --scope=user --role=backend --stack=go \
  --architecture=microservices --delivery=contract-first

# Project profile:
mb-profile.sh init --scope=project --role=frontend --stack=typescript \
  --architecture=fsd --delivery=sdd

# Show resolved profile:
mb-profile.sh show

# Validate:
mb-profile.sh validate .memory-bank/rules-profile.json
```

**Dispatch:** run `scripts/mb-profile.sh <subcommand> [flags]` directly. Full subcommand reference: `commands/profile.md`.

**Immutable baseline reminder:** skipping a profile keeps the immutable baseline active (no-placeholders, protected-files, destructive-confirm, fail-fast, DRY/KISS/YAGNI, verification-before-completion, explicit-storage-choice). The immutable baseline cannot be disabled by any profile.

---

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

**Errors:**

- `memory-bank: command not found` → see Step 1.
- `invalid client 'X'` → check the name (strict list of 8).
- `bash not found on PATH` (Windows) → suggest Git for Windows or WSL.

**Do not confuse with:**

- `/mb init` — initializes `.memory-bank/` **inside** the project after the skill is installed globally. Usually `install` → then `init`.
- `install.sh` in the repo root — the shell script that `memory-bank install` calls under the hood.

---

### idea <title> [HIGH|MED|LOW]

Capture a new idea in `backlog.md ## Ideas` with an auto-generated monotonic `I-NNN` ID.

**Arguments:**

- `title` — free-form idea title (first positional).
- priority (optional) — `HIGH`, `MED` (default), or `LOW`. Case-insensitive.

**Effect:**

- Appends `### I-NNN — <title> [PRIO, NEW, YYYY-MM-DD]` under `## Ideas` in `backlog.md`.
- `I-NNN` is monotonic across the entire file (zero-padded 3 digits).
- Idempotent: re-running with the exact same title reports the existing ID and exits without a duplicate.
- Invalid priority → exit 2 with usage hint.

Run directly (systems-level, no LLM needed):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-idea.sh "<title>" [HIGH|MED|LOW]
```

**Typical flow:**

```
User: /mb idea "Telemetry opt-in" LOW
→ [idea] I-007 added (LOW)

User: /mb idea "Add dark mode"
→ [idea] I-008 added (MED)
```

Surface the created ID back to the user so they can reference it in `/mb idea-promote`.

---

### idea-promote <I-NNN> <type>

Promote an existing idea into an active plan.

**Arguments:**

- `I-NNN` — ID of the idea in `backlog.md` (must exist and be in `NEW` or `TRIAGED` status).
- `type` — `feature`, `fix`, `refactor`, or `experiment` (passed through to `mb-plan.sh`).

**Effect:**

- Creates a plan file via `mb-plan.sh` using the idea title as the topic (title → slug).
- Flips the idea status `NEW|TRIAGED` → `PLANNED`.
- Adds `**Plan:** [plans/YYYY-MM-DD_<type>_<slug>.md](plans/...)` to the idea block.
- Runs `mb-plan-sync.sh` so the new plan appears in `roadmap.md` / `status.md` `<!-- mb-active-plans -->` blocks and its stages are appended to `checklist.md`.

**Refuses to promote** already-`PLANNED`, `DONE`, `DECLINED`, or `DEFERRED` ideas — asks the user to reset status manually or `/mb idea` a fresh one.

Run directly:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-idea-promote.sh <I-NNN> <type>
```

**Typical flow:**

```
User: /mb idea-promote I-007 feature
→ [promote] I-007 → 2026-04-21_feature_telemetry-opt-in.md
  plans/2026-04-21_feature_telemetry-opt-in.md
```

The idea's `**Plan:**` link lets anyone navigate from `backlog.md` to the live plan; `mb-plan-done.sh` later flips status back to `DONE` automatically when the plan is closed.

---

### adr <title>

Capture an Architecture Decision Record (ADR) inside `backlog.md ## ADR`.

**Arguments:**

- `title` — ADR title (free-form).

**Effect:**

- Appends `### ADR-NNN — <title> [YYYY-MM-DD]` under `## ADR` (creates the section if missing).
- ID is monotonic across the entire `backlog.md`.
- Skeleton includes: `**Context:**`, `**Options:**`, `**Decision:**`, `**Rationale:**`, `**Consequences:**` — all with `<!-- hint -->` placeholders for the user to fill in.
- Idempotent per call — each invocation creates a new ADR (no de-dup by title; ADR history is cumulative).

Run directly:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-adr.sh "<title>"
```

**Typical flow:**

```
User: /mb adr "Use OIDC for PyPI publishing"
→ ADR-003
  [writes ### ADR-003 — Use OIDC for PyPI publishing [2026-04-21] + skeleton]
```

After capture, open `backlog.md` and fill in Context / Options / Decision / Rationale / Consequences. The skeleton is intentionally short — the value is in the completed reasoning, not the template.

---

### migrate-structure [--dry-run|--apply]

One-shot migrator for the v3.0 → v3.1 Memory Bank file structure. Safe to run on an already-migrated bank (idempotent).

**Detection — triggers if any of:**

- `roadmap.md` has singular `<!-- mb-active-plan -->` marker (but not plural variant).
- `roadmap.md` uses the legacy text-only "## Active plan" + "**Active plan:** `plans/...`" without a HTML-comment block.
- `status.md` is missing `<!-- mb-active-plans -->` or `<!-- mb-recent-done -->` blocks.
- `backlog.md` contains legacy placeholder markers such as `(empty)` or lacks `## ADR`.

**Effect of `--apply`:**

1. Backs up `roadmap.md`, `status.md`, `backlog.md`, `checklist.md` → `.memory-bank/.pre-migrate/<timestamp>/`.
2. Upgrades `roadmap.md` singular → plural marker block, rebuilds `## Active plans` with correct entries.
3. Ensures `status.md` has `## Active plans` + `## Recently done` sections with proper markers.
4. Rewrites `backlog.md` skeleton: strips placeholders, guarantees `## Ideas` + `## ADR` sections.
5. Prints a per-action summary.

`--dry-run` (default) — prints the action plan, 0 file changes.

Run directly:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-structure.sh $ARGS_AFTER_MIGRATE
```

**Typical flow:**

```
User: /mb migrate-structure
→ mode=dry-run
  actions_pending=3
    - roadmap.md: add <!-- mb-active-plans --> block
    - status.md: add <!-- mb-recent-done --> block
    - backlog.md: restructure to skeleton (## Ideas + ## ADR)

User: /mb migrate-structure --apply
→ [apply] backup → .pre-migrate/20260421_093045/
  [apply] roadmap.md migrated
  [apply] status.md blocks ensured
  [apply] backlog.md skeleton ensured
  [apply] v3.1 structural migration complete
```

**Safety:**

- Running `--apply` twice on an already-migrated bank reports `actions_pending=0` and exits without changes.
- The `.pre-migrate/<timestamp>/` directory is persistent — restore with `cp .memory-bank/.pre-migrate/<ts>/*.md .memory-bank/` if anything goes wrong.
- Does not touch `notes/`, `plans/`, `progress.md`, `lessons.md`, `research.md`, `experiments/`, `codebase/`, or custom files.

**Recommended usage:** once per bank, after upgrading the skill to v3.1.x. Subsequent compaction is handled by `/mb compact`.

---

## General Rules

- If `.memory-bank/` does not exist and the command is not `init` — report `[MEMORY BANK: INACTIVE]` and suggest `/mb init`
- After execution — show the user a short result summary
- progress.md = APPEND-ONLY
- Numbering is global: H-NNN, EXP-NNN, ADR-NNN
