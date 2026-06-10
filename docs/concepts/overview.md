# Overview

Memory Bank is a skill bundle for AI coding agents (Claude Code, Cursor,
Codex, OpenCode, Pi, Windsurf, Cline, Kilo). It gives an agent three
things at once:

1. **Long-term project memory** — through a `.memory-bank/` directory at
   the project root (or registered globally), so agents can pick up where
   the last session left off without re-deriving context.

2. **An engineering rules baseline** — TDD, Clean Architecture (backend) /
   FSD (frontend) / Mobile (iOS, Android), SOLID, Testing Trophy, plus
   universal hygiene (no placeholders, no edits to protected files,
   verify before declaring done). The baseline is non-negotiable; the
   profile on top of it is fully customisable.

3. **A 25-command dev toolkit** — `/mb`, `/start`, `/done`, `/plan`,
   `/discuss`, `/sdd`, `/work`, `/config`, `/profile`, `/commit`, `/pr`,
   `/review`, `/test`, `/refactor`, `/doc`, `/changelog`, `/catchup`,
   `/adr`, `/contract`, `/security-review`, `/api-contract`,
   `/db-migration`, `/observability`, `/roadmap-sync`,
   `/traceability-gen`.

## The contract

One promise, kept always; everything else, fully under the user's
control.

> **Inviolable.** An agent working in a Memory Bank project can always
> reconstruct what was done, what is being done, what was decided, and
> what was learned the hard way. The memory subsystem
> (`status.md` / `checklist.md` / `plans/` / `progress.md` /
> `lessons.md` / `notes/` / `roadmap.md`) is the only mandatory layer.
>
> **Configurable.** Workflows, prompts, rules, commands, hooks, agents —
> opt-in, overridable, replaceable. Default behaviour never changes
> without explicit consent. User customisations survive upgrades.
> Expensive paths (multi-agent loops, deep context, parallel waves) are
> off by default.

Full text: [`references/design-principles.md`](../../references/design-principles.md).

## What is in `.memory-bank/`

```
.memory-bank/
├── status.md         current status, milestones, key metrics
├── checklist.md      ⬜/✅ tasks (updated immediately as work happens)
├── roadmap.md        high-level direction, active plans, focus
├── progress.md       append-only history of finished work
├── lessons.md        anti-patterns and insights worth remembering
├── backlog.md        ideas (I-NNN), ADRs (ADR-NNN)
├── research.md       hypotheses (H-NNN), experiment results
├── plans/            detailed multi-stage plans with DoD and TDD rules
│   └── done/         archived plans
├── specs/            spec triples — requirements / design / tasks
│   └── <topic>/{requirements,design,tasks}.md
├── notes/            short reusable knowledge (5–15 lines each)
├── experiments/      ML / A-B experiment records
├── reports/          longer findings worth keeping for future sessions
├── codebase/         living project map (STACK / ARCHITECTURE /
│                     CONVENTIONS / CONCERNS) + graph.json
├── context/          EARS-validated requirements drafts per topic
├── goals/            archived goals (active goal lives in goal.md)
└── index.json        searchable registry of all entries
```

Everything in this tree is part of the inviolable memory subsystem and
is owned by the project.

## How the layers stack

```
┌──────────────────────────────────────────────────┐
│ Memory  (inviolable)                             │
│   .memory-bank/                                  │
├──────────────────────────────────────────────────┤
│ Rules baseline  (immutable safety)               │
│   TDD, Clean Architecture, SOLID, protected      │
│   paths, no placeholders, verify before done     │
├──────────────────────────────────────────────────┤
│ Rules profile  (configurable)                    │
│   role × stack × architecture × delivery         │
│   user-global ◀ project ◀ skill-base             │
├──────────────────────────────────────────────────┤
│ Pipeline  (configurable, project-scoped)         │
│   pipeline.yaml: review_rubric, severity_gate,   │
│   protected_paths, execution.*, agents.*, goals.*│
├──────────────────────────────────────────────────┤
│ Agent prompts  (overlay system)                  │
│   user-global ◀ project ◀ skill-base             │
│   + opt-in preamble addons                       │
├──────────────────────────────────────────────────┤
│ Commands, hooks, skills  (install profile)       │
│   minimal | core | goals | autopilot | full      │
└──────────────────────────────────────────────────┘
```

## Two session shapes you will actually use

### 1. Plan-driven session

```
/mb start                       load context
/mb plan feature add-search     create plan with DoD + TDD per stage
/mb work add-search             run the plan, stage by stage
/mb verify                      audit code against the plan
/mb done                        actualize + note + progress
```

By default each `/mb work` stage goes through: implement → verify → done
(**review is off by default**). Opt into review/judge per run with
`--review` / `--judge` (or persist via `pipeline.yaml`), which add the
review (severity gate) → fix-cycle (capped) stages. Hard stops on
protected paths, budget, context exhaustion.

### 2. Spec-driven session

```
/mb start
/mb discuss inventory-sync      EARS-validated requirements in
                                context/inventory-sync.md
/mb sdd inventory-sync          spec triple in
                                specs/inventory-sync/{requirements,
                                design,tasks}.md
/mb work inventory-sync         execute tasks.md item by item
/mb verify
/mb done
```

`tasks.md` is a first-class executable artefact, not a scaffold. Each
`<!-- mb-task:N -->` block is resolved by `/mb work` as a work item
with role-routed implementation.

## Token economy by default

Memory Bank is built to be cheap to run.

- `MB_WORK_MODE=slim` is the default — subagents get only the files
  their plan/DoD references.
- One artefact per concept (single `goal.md`, single `status.md`) — no
  five-file split hierarchies.
- Diagnostic agents reuse the verifier's existing output and failing
  test stdout — they do not re-run tests or re-read the codebase.
- Parallel waves and multi-cycle review loops are opt-in; under a
  `--budget` ceiling they degrade gracefully to sequential.
- `mb-session-spend.sh` tracks token spend; `sprint_context_guard.hard_stop_tokens`
  hard-stops dispatch when the main agent's context is exhausting.

Concrete techniques are documented in
[`references/design-principles.md`](../../references/design-principles.md)
→ "Token economy — concrete rules".

## Multi-agent support

Memory Bank is agent-agnostic. The same `.memory-bank/` works under any
supported host; only the discovery and integration glue differs.

| Host | Status | Highlights |
|------|--------|------------|
| Claude Code / OpenCode | First-class, native commands | `/mb`, full hook surface, native skill marketplace |
| Cursor | First-class | Global skill alias, 10 global hooks, slash commands, User Rules paste flow |
| Codex | Global discovery + project adapter | `~/.codex/skills/memory-bank/` + `~/.codex/AGENTS.md` |
| Windsurf, Cline, Kilo, Pi | Adapter-based | Project-level integration via `AGENTS.md`, hooks where supported |
| Anything with a shell | CLI-fallback | `memory-bank ...` and `scripts/mb-*.sh` work without native integration |

See [cross-agent setup](../cross-agent-setup.md) for the full matrix.

## Where to go next

- New to the skill? Read this page, then [install](../install.md).
- Want to understand the design contract? Read
  [`references/design-principles.md`](../../references/design-principles.md).
- Want to start a project? Run `/mb init` in your project root, then
  `/mb start`.
- Want to see what is shipping in the next release? Look at
  `.memory-bank/specs/` and `.memory-bank/plans/` of this repo.
