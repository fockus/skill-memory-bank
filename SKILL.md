---
name: memory-bank
description: "Agent-agnostic long-term project memory through `.memory-bank/` + RULES (TDD/SOLID/Clean Architecture/FSD/Mobile) + dev-toolkit commands. Use when working in a project with a `.memory-bank/` directory or when the user explicitly asks for memory-bank workflow, code rules, or dev-toolkit commands."
---

# Memory Bank Skill

Three-in-one skill for code agents:

1. **Memory Bank** — long-term project memory through `.memory-bank/` (`STATUS`, `plan`, `checklist`, `RESEARCH`, `BACKLOG`, `progress`, `lessons`, `notes/`, `plans/`, `experiments/`, `reports/`, `codebase/`).
2. **RULES** — global engineering rules: TDD, Clean Architecture (backend), FSD (frontend), Mobile (iOS/Android UDF), SOLID, Testing Trophy.
3. **Dev toolkit** — 24 commands: `/mb`, `/start`, `/done`, `/plan`, `/discuss`, `/sdd`, `/work`, `/config`, `/commit`, `/pr`, `/review`, `/test`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/adr`, `/contract`, `/security-review`, `/api-contract`, `/db-migration`, `/observability`, `/roadmap-sync`, `/traceability-gen`.

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
| `_lib.sh` | Shared helpers sourced by other scripts |
| `mb-context.sh [--deep]` | Build context from core files (`STATUS` + `plan` + `checklist` + `RESEARCH` + codebase summary). `--deep` shows full codebase docs |
| `mb-search.sh <q> [--tag t]` | Keyword search across the memory bank. `--tag` filters via `index.json` |
| `mb-note.sh <topic>` | Create `notes/YYYY-MM-DD_HH-MM_<topic>.md`. Collision-safe (`_2` / `_3`) |
| `mb-plan.sh <type> <topic>` | Create `plans/YYYY-MM-DD_<type>_<topic>.md` with `<!-- mb-stage:N -->` markers |
| `mb-plan-sync.sh <plan>` | Synchronize a plan ↔ checklist + roadmap + status (idempotent) |
| `mb-plan-done.sh <plan>` | Close a plan: `⬜→✅` + move to `plans/done/` |
| `mb-idea.sh <title> [HIGH\|MED\|LOW]` | Capture a new idea in `backlog.md` with monotonic `I-NNN` |
| `mb-idea-promote.sh <I-NNN>` | Promote an idea (I-NNN) into an active plan |
| `mb-adr.sh <title>` | Capture an Architecture Decision Record in `backlog.md` (ADR-NNN) |
| `mb-init-bank.sh` | Deterministic, locale-aware `.memory-bank/` scaffolder |
| `mb-config.sh` | Memory Bank config resolver + locale auto-detector |
| `mb-metrics.sh [--run]` | Language-agnostic metrics (12 stacks). `--run` captures `test_status=pass\|fail` |
| `mb-index.sh` | Registry of all entries (core + notes/plans/experiments/reports) |
| `mb-index-json.py` | Build `index.json` (frontmatter notes + lessons headings). Atomic write |
| `mb-drift.sh` | 8 deterministic drift checkers (path, staleness, script coverage, dependency, cross-file, index sync, command, frontmatter) |
| `mb-rules-check.sh` | Deterministic rules enforcement (SRP / Clean Architecture / TDD delta) |
| `mb-test-run.sh` | Structured test runner with per-stack output parsing → strict JSON |
| `mb-deps-check.sh [--install-hints]` | Preflight dependency checker (python3, jq, git + optional tree-sitter) |
| `mb-checklist-prune.sh [--apply]` | Collapse completed sections in `checklist.md` to one-liners (≤120-line cap) |
| `mb-compact.sh [--apply]` | Status-based compaction decay — archive old done plans + low-importance notes |
| `mb-tags-normalize.sh [--apply]` | Levenshtein-based tag synonym detection + merge across `notes/` |
| `mb-roadmap-sync.sh` | Regenerate `roadmap.md` autosync block from `plans/*.md` frontmatter |
| `mb-traceability-gen.sh` | Regenerate `traceability.md` from specs + plans + tests |
| `mb-ears-validate.sh <file>` | Validate REQ bullets against the 5 EARS patterns |
| `mb-req-next-id.sh` | Emit the next monotonic `REQ-NNN` identifier |
| `mb-sdd.sh <topic>` | Create a Kiro-style spec triple under `specs/<topic>/` (requirements / design / tasks) |
| `mb-pipeline.sh` | Manage the project's `pipeline.yaml` (spec §9) |
| `mb-pipeline-validate.sh` | Structural validation for `pipeline.yaml` (spec §9) |
| `mb-work-resolve.sh` | Resolve `<target>` arg into a plan/spec path (spec §8.2) |
| `mb-work-range.sh` | Emit per-stage indices (plan mode) or per-sprint paths |
| `mb-work-plan.sh` | Emit per-stage execution plan as JSON Lines (spec §8) |
| `mb-work-budget.sh` | Token budget tracker for `/mb work --budget` |
| `mb-work-protected-check.sh` | Match files against `pipeline.yaml:protected_paths` |
| `mb-work-review-parse.sh` | Validate reviewer output for `/mb work` review-loop |
| `mb-work-severity-gate.sh` | Apply `pipeline.yaml:severity_gate` to review counts |
| `mb-reviewer-resolve.sh` | Pick the active reviewer agent name |
| `mb-session-spend.sh` | Session token-spend tracker (sprint context guard) |
| `mb-auto-commit.sh` | Opt-in auto-commit of `.memory-bank/` after `/mb done` (`MB_AUTO_COMMIT=1`) — 4 safety gates |
| `mb-migrate-v2.sh` | One-shot v1 → v2 migrator for `.memory-bank/` |
| `mb-migrate-structure.sh` | One-shot v3.0 → v3.1 structure migrator for `.memory-bank/` |
| `mb-import.py` | Claude Code JSONL → Memory Bank bootstrap importer |
| `mb-codegraph.py` | Python AST-based code graph builder (multi-language via tree-sitter) |
| `mb-context-slim.py` | Slim a full agent prompt on stdin → terse version on stdout |
| `mb-upgrade.sh [--check\|--force]` | Self-update the skill from GitHub |

---

## Agents — subagents (sonnet)

| Agent | When to invoke | Prompt |
|-------|----------------|--------|
| `mb-manager` | `/mb context`, `search`, `note`, `tasks`, `done`, `update`, PreCompact hook | `agents/mb-manager.md` |
| `mb-doctor` | `/mb doctor` — memory-bank inconsistencies (use `mb-plan-sync.sh` first, only edit for semantic drift) | `agents/mb-doctor.md` |
| `mb-codebase-mapper` | `/mb map [focus]` — scan the codebase → `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md` | `agents/mb-codebase-mapper.md` |
| `plan-verifier` | `/mb verify` — required before `/mb done` when work followed a plan. Uses `**Baseline commit:**` from plan header for `git diff`, delegates tests to `mb-test-runner`, enforces RULES.md via `mb-rules-enforcer` | `agents/plan-verifier.md` |
| `mb-rules-enforcer` | `/review`, `/commit`, `/pr`, `plan-verifier` step 3.6 — runs `mb-rules-check.sh` (solid/srp, clean_arch/direction, tdd/delta) + LLM ISP/DRY judgment. Returns strict JSON + summary | `agents/mb-rules-enforcer.md` |
| `mb-test-runner` | `/test`, `plan-verifier` step 3.5 — runs `mb-test-run.sh`, correlates failures with session diff. Returns JSON `{stack, tests_pass, tests_total, failures[], coverage, duration_ms}` | `agents/mb-test-runner.md` |
| `mb-reviewer` | `/mb work` review-loop — reads stage diff + `pipeline.yaml:review_rubric`, emits structured JSON verdict (APPROVED / CHANGES_REQUESTED) with severity-classified issues | `agents/mb-reviewer.md` |
| `mb-developer` | `/mb work` — generic implementer when no specialist role matches. TDD discipline + Clean Architecture | `agents/mb-developer.md` |
| `mb-architect` | `/mb work` — architecture / ADR / system-design specialist. Domain modelling, interface definition, refactoring strategy | `agents/mb-architect.md` |
| `mb-backend` | `/mb work` — APIs, services, database, async/concurrency, server-side business logic | `agents/mb-backend.md` |
| `mb-frontend` | `/mb work` — React/Vue/Svelte/Solid components, browser UI, accessibility, responsive layouts | `agents/mb-frontend.md` |
| `mb-ios` | `/mb work` — SwiftUI/UIKit, Combine, async/await, Apple platform conventions | `agents/mb-ios.md` |
| `mb-android` | `/mb work` — Jetpack Compose, Kotlin coroutines, Hilt/DI, Room, Material3 | `agents/mb-android.md` |
| `mb-devops` | `/mb work` — CI/CD, Docker, Kubernetes, Terraform, observability, release engineering | `agents/mb-devops.md` |
| `mb-qa` | `/mb work` — test design, coverage strategy, edge-case enumeration, flake elimination, contract tests | `agents/mb-qa.md` |
| `mb-analyst` | `/mb work` — data / analytics / metrics: SQL, dashboards, cohorts, ETL pipelines, instrumentation | `agents/mb-analyst.md` |

Do **NOT** delegate plan creation, architectural decisions, or ML-result evaluation to a subagent — that is main-agent work.

> **Plan hierarchy:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for size thresholds, terminology, and when to use which level. Cyrillic «Этап / Спринт / Фаза» — legacy alias, allowed only in `plans/done/*.md`.

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

## Hooks

Lifecycle hooks shipped in `hooks/`. Installed automatically by `install.sh` (Claude Code, Cursor, Codex, OpenCode); see `references/hooks.md` for per-host wiring details.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `block-dangerous.sh` | PreToolUse (Bash) | Block dangerous shell patterns (`rm -rf /`, `~`, `/*`) — best-effort guardrail |
| `mb-protected-paths-guard.sh` | PreToolUse (Write/Edit) | Block writes to `pipeline.yaml:protected_paths` (e.g. `.env`, CI configs) |
| `mb-ears-pre-write.sh` | PreToolUse (Write) | Validate REQ bullets in `context/<topic>.md` against EARS patterns before save |
| `mb-context-slim-pre-agent.sh` | PreToolUse (Task) | Slim oversized agent prompts on subagent dispatch |
| `mb-sprint-context-guard.sh` | PreToolUse (Task) | Hard-stop subagent dispatch if `mb-session-spend.sh` shows budget exhaustion |
| `mb-plan-sync-post-write.sh` | PostToolUse (Write) | Auto-sync plan ↔ checklist + roadmap after editing a plan file |
| `file-change-log.sh` | PostToolUse (Write/Edit) | Append change log + scan for placeholders / secrets in committed files |
| `session-end-autosave.sh` | SessionEnd | Memory Bank auto-capture (`MB_AUTO_CAPTURE=auto\|strict\|off`) when `/mb done` was skipped |
| `mb-compact-reminder.sh` | SessionEnd | Weekly `/mb compact` reminder (opt-in: triggers only after first `/mb compact --apply`) |

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
- Plan decomposition (Phase / Sprint / Stage), templates, drift checks: `references/templates.md`
- Planning + Plan Verifier workflow: `references/planning-and-verification.md`
- Structure of `.memory-bank/`: `references/structure.md`
- Workflow (session lifecycle): `references/workflow.md`
- Command file template: `references/command-template.md`
- Hooks (per-host wiring + lifecycle): `references/hooks.md`
- Adapter manifest schema: `references/adapter-manifest-schema.md`
- Tags vocabulary: `references/tags-vocabulary.md`
- CLAUDE.md auto-generation template: `references/claude-md-template.md`
- CHANGELOG: `CHANGELOG.md`
- Migration v1→v2: `docs/MIGRATION-v1-v2.md`
- Primary entrypoint:
  - `/mb` — if the host supports native commands
  - `commands/mb.md` / `memory-bank` CLI — if native command surface is unavailable
