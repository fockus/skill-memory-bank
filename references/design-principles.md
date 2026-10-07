# Design principles

## Contents

- [The inviolable core](#the-inviolable-core)
- [Everything above is configurable](#everything-above-is-configurable)
  - [Configurability invariants](#configurability-invariants)
- [Layer model](#layer-model)
- [Token economy — concrete rules](#token-economy--concrete-rules)
- [What this implies for new features](#what-this-implies-for-new-features)
- [Anthropic skill guide: deliberate deviations](#anthropic-skill-guide-deliberate-deviations)

Memory Bank is built on one inviolable promise and a stack of configurable
layers above it. This document fixes the contract so future changes stay
coherent.

## The inviolable core

**Agents must remember.** Across sessions, across compactions, across
context resets — an agent working in a Memory Bank project can reconstruct:

- what was done (`progress.md`, `notes/`),
- what is being done (`status.md`, `checklist.md`, active `plans/`),
- what was decided (`adr.md` ADRs, `plans/done/`),
- what was learned the hard way (`lessons.md`).

This is the only mandatory layer. Everything else in this skill exists to
serve it. If a feature would compromise the memory subsystem's reliability,
the feature is wrong.

## Everything above is configurable

Workflows, prompts, rules, commands, hooks, agents — all of it is opt-in,
overrideable, or replaceable. The skill ships opinionated defaults; the
user owns their pipeline.

### Configurability invariants

1. **Default = unchanged behavior.** Installing or upgrading the skill
   never alters how a project behaves until the user explicitly opts in.
   New features land behind a flag.

2. **Opt-in over magic.** Features activate through explicit configuration
   (`pipeline.yaml`, `rules-profile.json`, install profiles, file presence),
   never through silent auto-detection that surprises the user.

3. **Overlay over fork.** Users customise without copying skill files.
   Project- and user-level overlays sit beside the shipped versions and
   are resolved by precedence. Forking is always available; needing to
   fork is a design failure.

4. **Configuration survives upgrade.** `mb-upgrade` never overwrites
   user-owned artefacts: `pipeline.yaml`, `rules-profile.json`,
   `.memory-bank/agents/*`, project `RULES.md`. New defaults arrive as
   suggestions, not silent rewrites.

5. **Composable, not monolithic.** Install profiles
   (`minimal | core | goals | autopilot | full`) let users take exactly
   what they need. Commands, hooks, and agents are independently
   installable.

6. **Reversible.** Every opt-in is opt-out. Disabling a flag restores the
   prior behaviour without manual cleanup.

7. **Token-economical by default.** Every feature must justify its token
   cost. Cheap paths are default; expensive ones (multi-agent loops,
   deep context, two-stage review, parallel waves) are opt-in. The skill
   instruments token spend (`mb-session-spend.sh`) and exposes budgets
   (`--budget`, `sprint_context_guard.hard_stop_tokens`). Features that
   can't fit a budget degrade gracefully — they don't refuse to start.

## Layer model

```
┌──────────────────────────────────────────────────┐
│ Memory  (inviolable)                             │
│   status / checklist / plans / progress /        │
│   lessons / notes / roadmap                      │
├──────────────────────────────────────────────────┤
│ Rules baseline  (immutable safety)               │
│   TDD · Clean Architecture · SOLID · protected   │
│   paths · no placeholders · verify before done   │
├──────────────────────────────────────────────────┤
│ Rules profile  (configurable, scoped)            │
│   role · stack · architecture · delivery         │
├──────────────────────────────────────────────────┤
│ Pipeline  (configurable, project-scoped)         │
│   pipeline.yaml: review_rubric, severity_gate,   │
│   protected_paths, execution.*, agents.*, goals.*│
├──────────────────────────────────────────────────┤
│ Agent prompts  (overlay system)                  │
│   user-global ◀ project ◀ skill-base             │
│   + opt-in preamble addons                       │
├──────────────────────────────────────────────────┤
│ Commands, hooks, skills  (install-profile)       │
│   pick the surface that fits your workflow       │
└──────────────────────────────────────────────────┘
```

## Token economy — concrete rules

The skill is designed to be cheap to run. Where comparable spec-driven
tools spend tokens lavishly on multi-agent loops and deep artefact
hierarchies, Memory Bank defaults to the minimum-viable path.

- **Read on demand, not on principle.** Subagents receive only the files
  referenced in their plan/DoD. No "fold the whole codebase in for
  context" by default.
- **Slim is default.** `MB_WORK_MODE=slim` is the default for `/mb work`
  subagent dispatch; `--full` is explicit opt-in for hard problems.
- **One artefact, not five.** Goal state lives in a single ~50-line
  `goal.md`. The skill does not replicate split hierarchies
  (PROJECT/REQUIREMENTS/ROADMAP/STATE/CONTEXT) — that is five rereads
  per session start.
- **Reuse signals, don't re-derive them.** Diagnostic agents consume
  the verifier's existing JSON output and the failing test stdout; they
  do not re-run tests or re-read every changed file from scratch.
- **Parallel costs tokens.** DAG waves save wall time but multiply
  in-flight context. `execution.parallel_waves` is opt-in and respects
  `--budget`; under tight budgets the engine falls back to sequential.
- **Skip when safe.** Review/verify steps can be skipped for trivial
  stages (`pipeline.yaml: stage_pipeline[].skip_if`) — e.g. docs-only
  diff, single-line typo fix.
- **Cache verifier verdicts.** If git diff hasn't changed since last
  PASS, `/mb verify` returns the cached verdict instead of re-dispatching.

## What this implies for new features

Before adding anything, check it against the contract:

- **Does it weaken the memory guarantee?** → reject.
- **Does it change default behaviour for existing users?** → gate it
  behind a flag or ship as a new install profile.
- **Does it require the user to copy skill files to customise?** → add
  an overlay/addon mechanism instead.
- **What does it cost in tokens per invocation?** Estimate, then justify.
  If it adds >10% to a typical `/mb work` stage, it must be opt-in.
- **Does it degrade under budget?** Every feature must answer
  "what happens at budget exhaustion?" — graceful fallback, not crash.
- **Is it discoverable when opted out?** `/mb config show` and install
  profiles list inactive flags honestly so users know the option exists.

The principles override convenience. A configurable, opt-in,
token-aware feature is always better than a clean, mandatory one —
even if it costs more lines of code.

## Anthropic skill guide: deliberate deviations

Where this skill knowingly departs from Anthropic's skill-authoring guidance
([best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
[Claude Code skills](https://code.claude.com/docs/en/skills)). The compliance
gate `tests/pytest/test_skill_guide_compliance.py` enforces everything else.

### 1. `$SKILL_DIR` instead of `${CLAUDE_SKILL_DIR}`

**Context.** The guide resolves skill files through `${CLAUDE_SKILL_DIR}`, but `SKILL.md` and `commands/` are also read by Codex, Cursor, Pi and OpenCode, which do not substitute it.
**Decision.** Paths go through `$SKILL_DIR` with the chain `MB_SKILLS_ROOT → SKILL_DIR → ~/.claude/skills/memory-bank`.
**Alternatives.** Bulk replace with `${CLAUDE_SKILL_DIR}` — rejected, it breaks every non-Claude host.
**Consequences.** Claude-only command text may use `${CLAUDE_SKILL_DIR}`, decided case by case when that text is edited; no bulk replace.

### 2. Skill directory = whole repository

**Context.** The skill folder is the repo itself, so it also holds `tests/`, `.memory-bank/`, `docs/`; the guide's generic audit script counted them as skill files and reported 881 violations, almost all false positives.
**Decision.** Only `references/`, `rules/` and `flow-templates/` are skill reference files.
**Alternatives.** A separate build/publish directory — rejected, it duplicates the tree for every host alias.
**Consequences.** The compliance gate scopes its reference checks to those three directories; files elsewhere are not judged as skill references.

### 3. Agents and commands have no table of contents

**Context.** The guide asks for a ToC in files over 100 lines because Claude may preview them partially (`head -100`).
**Decision.** `agents/*.md` and `commands/*.md` carry no ToC.
**Alternatives.** Add ToCs anyway — rejected, it spends tokens on every dispatch for no navigation gain.
**Consequences.** They are loaded whole as a system prompt or command body, never read via `Read`, so the `head -100` partial-read concern does not apply; the ToC rule stays enforced for reference files. For the same reason they are not linked from `SKILL.md` by file path: agents are dispatched by name (roster in `references/agents.md`), commands are invoked as `/name`; the guide's script reports them as "2nd level" — expected.

### 4. Side-effecting commands without `disable-model-invocation`

**Context.** Anthropic advises `disable-model-invocation: true` for workflows with side effects; `/commit`, `/pr`, `/db-migration`, `/drive` are such commands.
**Decision.** None of them sets it — owner decision AGR-061: Claude keeps the right to invoke any command.
**Alternatives.** Mark the four commands manual-only — rejected by the owner.
**Consequences.** Their descriptions must say precisely when to use them, since the description is the only gate on automatic invocation.

### 5. Two install paths under `~/.claude/skills/`

**Context.** `install.sh` defines `CANONICAL_SKILL_DIR=~/.claude/skills/skill-memory-bank` (the git-clone target named after the repo, also expected by the updater in `docs/updating.md`; for pipx/brew installs it is symlinked to the package source) and `CLAUDE_SKILL_ALIAS=~/.claude/skills/memory-bank` (the path every command and hook falls back to, matching `name: memory-bank`); the Codex/Cursor/Pi/OpenCode aliases point at the canonical one.
**Decision.** Keep both: each is load-bearing — the alias for runtime path resolution, the canonical one for clone/update installs.
**Alternatives.** Drop the alias (breaks every `~/.claude/skills/memory-bank` fallback) or move the canonical dir outside `~/.claude/skills/` (changes the documented clone path and updater).
**Consequences.** Both directories hold the same `SKILL.md`, so Claude Code may list `memory-bank` twice — to verify in a live `/skills` listing. The second entry is a side effect of the canonical dir living inside the skills scan root, not an unneeded alias; if a duplicate shows up, the fix is relocating the canonical dir, not deleting the alias.
