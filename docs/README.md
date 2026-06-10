# Memory Bank — Documentation

Long-term project memory for AI coding agents. Plus engineering rules
baseline (TDD / Clean Architecture / SOLID / FSD / Mobile) and a 25-command
dev toolkit.

**One inviolable promise, fully configurable above.** See
[`references/design-principles.md`](../references/design-principles.md)
for the contract.

---

## Start here

- **[Concepts → Overview](concepts/overview.md)** — what this skill is and
  what it does, in 5 minutes.
- **[Your first feature, end to end](first-feature.md)** — worked example:
  `/mb init` → plan → TDD work → verify → done.
- **[Design principles](../references/design-principles.md)** — the
  contract every feature is checked against.
- **[Install guide](install.md)** — pipx, Homebrew, git clone, with
  troubleshooting.
- **[Troubleshooting](troubleshooting.md)** — common issues by symptom.
- **[Cross-agent setup](cross-agent-setup.md)** — per-client cheatsheet
  (Claude Code, Cursor, Codex, OpenCode, Windsurf, Cline, Kilo, Pi).

## Concepts

Background reading on how the skill is structured.

- **[Overview](concepts/overview.md)** — high-level picture of the layers.
- **[Design principles](../references/design-principles.md)** — inviolable
  core + configurability invariants + token economy.
- **[Composable `/mb work` pipeline](../commands/work.md)** — review off by
  default; per-stage flags, the `full` preset, three-layer precedence.
- **[Code graph & semantic search](concepts/code-graph.md)** — `/mb map`,
  `/mb graph` (+ opt-in layers), `mb-semantic-search.py`, `/mb wiki`.
- **[Cross-session memory](concepts/session-memory.md)** — `/mb recall`,
  session hooks, the local semantic index.
- **Memory model** *(coming)* — `status.md` / `checklist.md` / `plans/` /
  `progress.md` / `lessons.md` / `notes/` and how they fit together.
- **Pipeline config** *(coming)* — `pipeline.yaml` schema with examples.
- **Overlay system** *(coming)* — agent-prompt and rule-profile overlays.
- **Glossary** *(coming)* — Phase / Sprint / Stage / Goal / Wave / Worktree.

## Workflows

Step-by-step guides for common ways of working.

- **[Plan-driven: your first feature](first-feature.md)** — `/mb plan` →
  `/mb work` → `/mb verify` → `/mb done`, with a worked example.
- **Basic session** *(coming)* — `/mb start` → work → `/mb done`.
- **Spec-driven** *(coming)* — `/mb discuss` → `/mb sdd` → `/mb work`.
- **Goal-driven** *(coming)* — `/goal init` → `/goal "..."` →
  `/mb work --autopilot` → `/goal done`.
- **Autopilot** *(coming)* — long-running Ralph-loop with hard stops.
- **Debugging** *(coming)* — `/mb debug` and auto-recovery on verify FAIL.

## Features

Reference pages, one per capability.

### Stable

- **[Rule profiles](rule-profiles.md)** — role × stack × architecture ×
  delivery preset matrix; 22 presets; immutable baseline; user/project
  scope precedence.

### Coming as part of the goal-driven-autopilot spec

- **Worktree isolation** — `git worktree`-based execution sandbox.
- **Parallel waves** — DAG-based stage parallelism via `depends_on`.
- **Atomic stage commit** — one commit per `/mb work` stage with safety
  gates.
- **Token economy** — concrete techniques: slim mode, signal reuse,
  artefact frugality, parallel-fallback.

### Existing features pending dedicated docs

The following are documented inside `SKILL.md` / `references/` today;
they will get their own pages in a follow-up backfill sprint.

- Memory Bank core (`.memory-bank/` structure, append-only progress).
- Codebase mapping (`/mb map` → `codebase/STACK.md` /
  `ARCHITECTURE.md` / `CONVENTIONS.md` / `CONCERNS.md`).
- Code graph (`/mb graph --apply`, `graph.json`, `god-nodes.md`).
- GraphRAG-lite retrieval (`mb-code-context.py`, semantic + graph + text
  fallback).
- Private content (`<private>...</private>` blocks, redaction in
  `index.json` and search).
- Auto-capture (SessionEnd hook, `MB_AUTO_CAPTURE=auto|strict|off`).
- Weekly compact reminder.

## Commands

Per-command reference pages. Until a page exists, see `commands/<name>.md`
in the skill bundle, or run the command with no args for inline help.

Full list (25): `mb`, `start`, `done`, `plan`, `discuss`, `sdd`, `work`,
`config`, `profile`, `commit`, `pr`, `review`, `test`, `refactor`, `doc`,
`changelog`, `catchup`, `adr`, `contract`, `security-review`,
`api-contract`, `db-migration`, `observability`, `roadmap-sync`,
`traceability-gen`.

Coming as part of goal-driven-autopilot: `goal`, `debug`.

## Reference

Schemas and exhaustive listings — material agents may need.

- **[Hooks](../references/hooks.md)** — per-host wiring and lifecycle.
- **[Tags vocabulary](../references/tags-vocabulary.md)** — canonical tags
  for `index.json`.
- **[Templates](../references/templates.md)** — plan decomposition (Phase
  / Sprint / Stage), drift checks.
- **[Planning + verification](../references/planning-and-verification.md)**
  — plan-verifier workflow.
- **[Memory Bank structure](../references/structure.md)** — every file in
  `.memory-bank/` and what it stores.
- **[Workflow](../references/workflow.md)** — session lifecycle (start,
  during, finish, before compaction).
- **[Rules-profile schema](../references/rules-profile.schema.md)** —
  dimensions, immutable baseline, validation.
- **[Adapter manifest schema](../references/adapter-manifest-schema.md)** —
  for adding new AI-client integrations.
- **[Metadata protocol](../references/metadata.md)** — `index.json`
  fields, 8 key rules.
- **[CLAUDE.md template](../references/claude-md-template.md)** —
  auto-generated by `/mb init --full`.
- **[Command file template](../references/command-template.md)** — for
  authoring new `/commands/*.md`.
- **[Agents reference](agents-reference.md)** — all 29 subagents grouped
  by role, and which command invokes each.
- CLI scripts reference *(coming)* — every `scripts/mb-*.{sh,py}` with
  arguments and exit codes.
- `pipeline.yaml` schema *(coming)* — full configuration reference.
- Artefact schemas *(coming)* — `project.md`, `goal.md`, plan
  frontmatter, spec frontmatter, note frontmatter.

## Integration

How the skill fits with each AI coding agent.

- **[Cross-agent setup](cross-agent-setup.md)** — supported clients
  matrix, install paths, host-specific notes.
- Claude Code *(coming)* — native command surface, hooks, native auto
  memory coexistence.
- Cursor *(coming)* — global vs project install, User Rules paste flow,
  hooks integration.
- Codex *(coming)* — global skill bundle + project-level adapter.
- OpenCode *(coming)* — TS plugin, `experimental.session.compacting`.
- Pi *(coming)* — dual-mode discovery.
- CI/CD *(coming)* — using `mb-test-run.sh` / `mb-drift.sh` from
  pipelines.

## Recipes

Practical "how do I…" guides. Grow as we accumulate notes worth
generalising.

- TDD workflow *(coming)*
- Multi-stage feature delivery *(coming)*
- Refactoring with the Strangler Fig pattern *(coming)*
- Debugging flaky tests *(coming)*

## Operations

Run, upgrade, ship the skill itself.

- **[Install guide](install.md)** — install methods and troubleshooting.
- **[Release process](release-process.md)** — PyPI OIDC + tag workflow.
- **[Repo migration](repo-migration.md)** — for users upgrading from
  `claude-skill-memory-bank`.
- **[i18n](i18n.md)** — adding a new locale (en / ru ship; es / zh
  scaffolds).
- Upgrading *(coming)* — `/mb upgrade`, what changes, what survives.

## Migrations

Version-specific upgrade guides.

- **[v4 → v5](MIGRATION-v4-v5.md)** — composable `/mb work` pipeline;
  review off by default. No file migration needed.
- **[v1 → v2](MIGRATION-v1-v2.md)** — first structural migration.
- **[v3.0 → v3.1](MIGRATION-v3-v3.1.md)** — multi-active plans, `I-NNN`
  ideas, `ADR-NNN`.
- **[Install v1 → v2](MIGRATION-install-v1-v2.md)** — installer changes.

## Security

- **[Security policy](../SECURITY.md)** — reporting, scope, response
  timeline, design decisions.
- **[Archived audit (2026-04-21)](security/audit-2026-04-21.md)** —
  third-party audit snapshot; key findings addressed in 3.x/4.x (path
  validation on uninstall, `MB_ALLOW_METRICS_OVERRIDE` opt-in gate).

---

## Contributing to docs

- Each `docs/*.md` ≤ 300 lines. If a page grows, split.
- Cross-link liberally, do not duplicate content.
- `concepts/` explains *why*. `features/` explains *what*.
  `workflows/` explains *how*. `reference/` is exhaustive lookup.
- New skill capability ⇒ at least one `docs/features/<name>.md` page
  before the feature is released.
- Existing files are not moved while their paths are referenced from
  `README.md`, `CONTRIBUTING.md`, or tests. Restructuring is a deliberate
  refactor with link updates.
