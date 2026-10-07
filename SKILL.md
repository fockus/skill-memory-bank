---
name: memory-bank
description: "Agent-agnostic long-term project memory through `.memory-bank/` + RULES (TDD/SOLID/Clean Architecture/FSD/Mobile) + dev-toolkit commands. Use when working in a project with a `.memory-bank/` directory or when the user explicitly asks for memory-bank workflow, code rules, or dev-toolkit commands (`/mb`, plan, spec, verify, done; «память проекта», «контекст проекта», «план», «продолжай по плану»)."
---

# Memory Bank Skill

Three-in-one skill for code agents:

1. **Memory Bank** — long-term project memory through `.memory-bank/` (`status.md`, `checklist.md`, `roadmap.md`, `research.md`, `backlog.md`, `adr.md`, `progress.md`, `lessons.md`, `notes/`, `plans/`, `experiments/`, `reports/`, `codebase/`).
2. **RULES** — global engineering rules: TDD, Clean Architecture (backend), FSD (frontend), Mobile (iOS/Android UDF), SOLID, Testing Trophy.
3. **Dev toolkit** — 34 commands: `/mb`, `/start`, `/done`, `/plan`, `/brief`, `/discuss`, `/groom`, `/sdd`, `/work`, `/drive`, `/config`, `/pipeline`, `/profile`, `/rules`, `/commit`, `/pr`, `/review`, `/test`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/adr`, `/contract`, `/security-review`, `/api-contract`, `/db-migration`, `/observability`, `/roadmap-sync`, `/traceability-gen`, `/analyze-task`, `/flow`, `/goal`, `/agree`.

> **Design contract.** Memory Bank rests on one inviolable promise — *agents remember* — and a stack of fully configurable, token-economical layers above it. Default behaviour never changes without explicit opt-in; user customisations survive upgrades; expensive paths are off by default. See [`references/design-principles.md`](references/design-principles.md) for the full contract.

Details live in one-level reference files read on demand — see [References](#references) at the end.

---

## Development flow — stages a code agent should expect

Work in a Memory Bank project follows this order. Depth scales with task complexity — every stage except development itself can be skipped for trivial work; review and judge are **opt-in**.

| # | Stage | Command | Notes |
|---|-------|---------|-------|
| 1 | **Interview** | `/mb discuss <topic>` (alias `/mb ask_me`) | Grilling interview → decisions + EARS-validated requirements draft in `context/<topic>.md` |
| 2 | **Spec or plan** | `/mb sdd <topic>` · `/mb plan <type> <topic>` | Pick by complexity: feature/multi-task → spec triple (`specs/<topic>/requirements+design+tasks.md`, executable `<!-- mb-task:N -->`); smaller bounded change → plan (`plans/*.md`, `<!-- mb-stage:N -->`); trivial fix → no artifact (rules still apply) |
| 3 | **Development** | `/mb work <target>` | Executes spec tasks / plan stages one by one through an implement → verify loop with role subagents (TDD, contract-first) |
| 4 | **Verification** | `/mb verify` | plan-verifier audits diff vs plan/spec DoD; **mandatory before `/mb done`** when work followed a plan/spec |
| 5 | **Review** *(optional)* | `/mb work <target> --review` | Reviewer verdict (subagent ensemble or external codex) + severity gate; off by default |
| 6 | **Judge** *(optional)* | `/mb work <target> --judge` | `mb-judge` decides GO / GO_WITH_BACKLOG / NO_GO and terminates the review loop |
| 7 | **Close** | `/mb done` | Actualize bank: progress append, checklist/status update |

**Grooming (any stage).** `/mb groom <topic>` (also `grooming`) runs a critical grooming session outside the fixed order — for a raw idea, a task that already has a spec, or a decision worth revisiting. Unlike `/mb discuss`, the goal is not a spec: the agent challenges necessity and approach, proposes its own solutions, covers white spots; the summary lands in `context/<topic>-groom.md`, confirmed decisions go to `agreements.md` / backlog (ADR/Ideas), and the session ends with proposed next steps (e.g. `/mb sdd`).

**Pipeline.** The whole chain can be encoded in `<bank>/pipeline.yaml` as a named workflow (steps, per-role `model`/`thinking`, severity gates, protected paths, budget). When present, `/mb work` resolves it automatically (`mb-workflow.sh`) and follows the configured steps — e.g. governed `implement → verify → review → judge → fix → done` — without per-run flags. Manage with `/mb pipeline` / `/mb config`; validate with `/mb config validate`. Defaults never change without opt-in: no pipeline and no flags = simple implement → verify.

**Command index — all `/mb` subcommands** (know these exist; suggest them to the user when relevant; details per subcommand → `commands/mb.md` or `/mb help <sub>`):

- **Session & context:** `context` (default, empty arg) · `start` · `done` · `update` · `tasks` · `note <topic>` · `index`
- **Requirements & decisions:** `discuss <topic>` (alias `ask_me`) · `groom <topic>` (alias `grooming`) · `sdd <topic>` · `openspec <import|list|status|sync>` · `plan <type> <topic>` · `idea <title>` · `idea-promote <I-NNN>` · `adr <title>` · `agree <sub>` · `goal`
- **Execution:** `work [target]` · `verify` · `config <sub>` · `pipeline <sub>` · `flow <route>` · `analyze-task`
- **Codebase intelligence & memory:** `map [focus]` · `graph` · `wiki` · `research <query>` · `search <query>` · `recall <query>` · `recap <sid>` · `conflicts` · `consolidate` · `tags`
- **Setup & maintenance:** `init` · `install` · `profile <sub>` · `rules <sub>` · `doctor` · `compact` · `migrate-structure` · `import` · `upgrade` · `deps` · `statusline` · `help [sub]`

Beyond `/mb`, the toolkit ships standalone commands (see the list in the intro above): `/commit`, `/pr`, `/review`, `/test`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/contract`, `/security-review`, `/api-contract`, `/db-migration`, `/observability`, `/roadmap-sync`, `/traceability-gen`.

> **Plan hierarchy:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for size thresholds, terminology, and when to use which level. Cyrillic «Этап / Спринт / Фаза» — legacy alias, allowed only in `plans/done/*.md`.

---

## Task routing

Before starting, size the task — trivial / small / standard / large / extra — and match plan, tests, docs and checks to the tier: [`references/effort-tiers.md`](references/effort-tiers.md). An explicit user request beats the estimate. Independent tasks go to parallel subagents. Plan coarse; decompose only when stuck (ADaPT).

## Workspace resolution — agent-agnostic storage

Memory Bank resolves its active bank through `scripts/_lib.sh::mb_resolve_path`. The precedence is fixed and explicit:

1. **Explicit argument** — `mb-*.sh <mb_path>` always wins.
2. **`MB_PATH` env override** — for ad-hoc redirection in shell sessions.
3. **Local mode** — `<project>/.memory-bank/` (default of `/mb init`, team-shared, committable).
4. **Global mode** — registered in `<agent_config>/memory-bank/registry.json`. Requires `--storage=global --agent=<name>` on init (or `$MB_AGENT` env). Per-agent paths: [`references/structure.md`](references/structure.md) § Global storage paths.
5. **Legacy `.claude-workspace`** — old pointer mode, see [`references/structure.md`](references/structure.md) § Old patterns.
6. **Fallback** — relative `.memory-bank` (compat with existing scripts).

### Active-state semantics

- `[MEMORY BANK: ACTIVE]` — when the resolver returns an **existing** bank (local or registered global).
- `[MEMORY BANK: ABSENT]` — when no bank exists for the current project. Surface this and **stop** the Memory Bank lifecycle — do **not** silently initialize.
- `[MEMORY BANK: INITIALIZED]` — only after a successful explicit `/mb init`.

### Rules-only mode

A project may intentionally have no Memory Bank (`[MEMORY BANK: ABSENT]`). In that case:

- `/mb` lifecycle commands stay inactive until the user explicitly runs `/mb init`.
- The **engineering rules baseline still applies**: TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders, verification before completion. Global skill installation never auto-enables Memory Bank state.

When invoking MB Manager or scripts, always pass the resolved `mb_path`.

---

## Tools — shell scripts

All scripts live in `scripts/` next to this `SKILL.md`. In global installs, the bundle is typically available through host aliases:
- Claude Code: `~/.claude/skills/memory-bank/`
- Codex: `~/.codex/skills/memory-bank/`
- Cursor: `~/.cursor/skills/memory-bank/`

Scripts work with `.memory-bank/` in the current directory or through the `mb_path` argument.

### GraphRAG-lite retrieval routing

`code_context is the default` for ambiguous code-understanding questions such as "where is the logic for X?" or "find similar implementation". Exact structural questions route directly to graph tools: "who calls/imports/defines X?" → `graph_neighbors`, "reverse deps" or change impact → `graph_impact`, and "what tests cover this file/symbol?" → `graph_tests`. User explicitly asks "semantic search" → `search_code` because explicit tool intent wins.

Fail open: missing graph, stale graph, missing semantic provider, or unavailable native extension must not block the agent. Optional dependencies (tree-sitter, networkx, fastembed) are not assumed installed: `bash "$SKILL_DIR"/scripts/mb-deps-check.sh --install-hints` prints the exact install command. Use `bash "$SKILL_DIR"/scripts/mb-graph.sh who-calls|impact|tests <Symbol>` / `search "<query>"` / `status` (`SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"`, i.e. this skill's directory) and `scripts/mb-code-context.py` as the universal CLI fallback; Pi and OpenCode may expose native tool wrappers, while Claude Code, Codex, and generic AGENTS.md agents can call the scripts directly.

**Entry points agents call** (full grouped table incl. internal libraries → [`references/scripts.md`](references/scripts.md)):

- `mb-context.sh [--deep]` — load bank context (status, checklist, active plan, codebase summary)
- `mb-graph.sh who-calls|impact|tests <Symbol>` / `search "<query>"` / `status` — graph + semantic code search front door
- `mb-search.sh <q> [--tag t]` — keyword search across the bank
- `/mb recall <query>` (`hooks/mb-recall.sh`) — hybrid semantic + lexical recall (RRF) over sessions, notes, agreements, progress
- `mb-plan.sh <type> <topic>` / `mb-plan-sync.sh <plan>` — create a plan with `<!-- mb-stage:N -->` markers, sync it to checklist/roadmap
- `mb-spec-validate.sh <topic>` — validate a spec triple (EARS, executable `<!-- mb-task:N -->` tasks, REQ coverage)
- `mb-workflow.sh` / `mb-work-resolve.sh` / `mb-work-plan.sh` — resolve the `/mb work` workflow, target, and per-item JSON plan
- `mb-agree.sh add|question|list …` — single writer for `agreements.md`
- `mb-coord.sh active` / `append` — read/write the cross-session board without loading it
- `mb-idea.sh` / `mb-adr.sh` — capture an idea (`I-NNN`) in `backlog.md` or an ADR (`ADR-NNN`) in `adr.md`
- `mb-profile.sh` — rule profiles (`init`, `show`, `validate`, `set`)
- `mb-drift.sh` / `mb-done-gates.sh` — deterministic drift checkers; mandatory `/mb done` gates

---

## Quick start

```bash
# Storage modes — pick one per project:
/mb init                                      # local mode (default) — bank in repo (.memory-bank/)
/mb init --storage=local                      # explicit local mode — same as above
/mb init --storage=global --agent=claude-code # global mode — bank in ~/.claude/memory-bank/...
                                              # (personal, NOT committed to the repo)
# Rules-only mode: no /mb init at all — [MEMORY BANK: ABSENT] state;
# /mb lifecycle stays inactive; all TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI rules still apply.

# Initialization flags
/mb init --full          # same as /mb init (stack auto-detect + CLAUDE.md generation)
/mb init --minimal       # only the .memory-bank/ structure

# Session flow (basic)
/mb start                # load context
# ... work, checklist.md updates as tasks complete ...
/mb verify               # verify plan alignment (if there was a plan)
/mb done                 # actualize + note + progress

# Unified SDD flow (spec-driven features)
/mb discuss <topic>      # EARS-validated requirements → context/<topic>.md
/mb sdd <topic>          # spec triple: requirements / design / tasks.md (executable)
# specs/<topic>/tasks.md is a first-class executable artifact with <!-- mb-task:N --> markers,
# NOT a scaffold — each block is resolved by /mb work <topic> as a work item.
/mb work <topic>         # execute spec tasks one by one (reads <!-- mb-task:N --> blocks)
/mb verify               # verify against spec + plan
/mb done                 # actualize + progress

# Personalize rules for your stack (optional):
/mb profile init --scope=project --role=backend --stack=go --architecture=microservices --delivery=contract-first
# or user-global (works even without a project Memory Bank):
/mb profile init --scope=user --role=frontend --stack=typescript
```

If the host does not support native slash commands, use:
- `commands/mb.md` as the workflow entrypoint;
- the `memory-bank ...` CLI for install/init/doctor flows;
- bundled scripts and agent prompts from this skill bundle.

---

## Agents — subagents

Full roster (when to invoke each agent, prompt files, `compose:` partials) → [`references/agents.md`](references/agents.md).

Plan authoring and ML-result evaluation stay with the main agent: it holds the user's context and decisions. `mb-architect` executes the architecture items of an approved plan. Bugs, failing or flaky tests, and unexplained behaviour go to `mb-debugger` (root cause before fix).

### Invocation

Dispatch agents by name — `Agent(subagent_type="mb-manager", description="…", prompt="action: <action>\n\n<context>")`.
Model, reasoning effort, and tools come from the installed agent definition or `pipeline.yaml`, not from the call.
The commands write this Claude Code form; other hosts dispatch the same installed role with their own tool:

| Host | Dispatch by name | Where the role is installed |
|---|---|---|
| Claude Code | `Agent(subagent_type=<name>, prompt=…)` (older builds: `Task`) | `~/.claude/agents/<name>.md` |
| OpenCode | `task(subagent_type=<name>, prompt=…)` | `.opencode/agent/<name>.md` |
| Codex | `spawn_agent(agent_type=<name>, message=…)`; a pipeline `thinking` goes to `reasoning_effort` | `~/.codex/agents/<name>.toml` |
| Pi | `mb_dispatch_subagent(role=<name>, task=…)` or pi-subagents `subagent(agent=<name>, task=…)`; `thinking` passes through | `~/.pi/agent/agents/<name>.md` |

A host without named dispatch reads the role file and its `compose:` partials and does the work inline.

---

## Hooks, hosts, privacy and capture

- Lifecycle hooks (inventory + per-host wiring): [`references/hooks.md`](references/hooks.md) § Hook inventory.
- Host-specific notes (Claude Code native memory, Codex, Cursor): [`references/hosts.md`](references/hosts.md).
- `<private>` content, auto-capture (`MB_AUTO_CAPTURE`), session logging, PreCompact handoff: [`references/privacy-and-capture.md`](references/privacy-and-capture.md). `/mb done` can auto-commit the bank (`MB_AUTO_COMMIT=1`, `scripts/mb-auto-commit.sh`).

---

## Cross-session coordination — `.memory-bank/COORDINATION.md`

When two or more sessions work in the same working tree in parallel (two agent CLIs, or agent + human), they coordinate through a single append-only board file at the bank root — `COORDINATION.md`. Opt-in by nature: the first session that learns about a parallel session creates it; no board file → no protocol overhead.

- **Read it with `scripts/mb-coord.sh active`**, never `cat` — the board is append-only and reaches hundreds of KB; the command prints active FREEZEs, HANDOVERs with no ACK, the last 3 entries and a totals line. Write entries with `mb-coord.sh append --type <T> --title <t>`.
- Full protocol (entry conventions, race handling, trust rules, hookup prompt for a new session): `references/coordination.md`.

---

## Running list of agreements — `.memory-bank/agreements.md`

The canonical registry of confirmed decisions currently in force, distinct from `progress.md`
(narrative history) and ADRs (rationale for the hard-to-reverse subset). Every mutation goes
through `scripts/mb-agree.sh` (`add | supersede | defer | reject | question | resolve | list |
sync`) — never a direct model edit — and auto-syncs a managed block
(`<!-- mb-agreements:start/end -->`) into project-root `CLAUDE.md`/`AGENTS.md` so a fresh session
sees every active agreement without being reminded.

- Full protocol (what is/isn't an agreement, anti-examples, statuses, ADR routing): `references/agreements.md`. Command reference: `commands/agree.md`.

---

## References

- Rule profiles schema (dimensions, immutable baseline, precedence, validation): `references/rules-profile.schema.md`
- Design principles (inviolable memory promise + configurable layers): `references/design-principles.md`
- Metadata protocol + `index.json` + 8 key rules: `references/metadata.md`
- Plan decomposition (Phase / Sprint / Stage), templates, drift checks: `references/templates.md`
- Planning + Plan Verifier workflow: `references/planning-and-verification.md`
- Effort tiers (sizing a task to trivial … extra and matching plan/tests/docs/checks): `references/effort-tiers.md`
- ADaPT-lite — decompose only a stuck item, `complexity_escalation`: [`references/adapt.md`](references/adapt.md)
- `/mb work` reference material (workflow modes, JSON schema, examples, scripts, parallel runs): `references/work-reference.md`
- `/mb work` sprint contracts, progress trend, strategic pivoting: `references/work-loop-v2.md`
- Structure of `.memory-bank/`: `references/structure.md`
- Code graph cookbook (jq library, `graph.json` schema, intelligence layer, semantic-search routing): `references/code-graph.md`
- Workflow (session lifecycle): `references/workflow.md`
- Session memory (cross-chat capture, `/mb recall`, session-doctor): `references/session-memory.md`
- Cross-session coordination board (`COORDINATION.md` protocol): `references/coordination.md`
- Running list of agreements (`agreements.md` protocol, statuses, anti-examples): `references/agreements.md`
- Command file template: `references/command-template.md`
- Hooks (per-host wiring + lifecycle): `references/hooks.md`
- Scripts — full grouped table (bank core, plans & specs, `/mb work`, graph, session memory, internal libraries): `references/scripts.md`
- Agents — full subagent roster: `references/agents.md`
- Debugging techniques for `mb-debugger` (adapted from superpowers, MIT): `references/debugging/root-cause-tracing.md` · `references/debugging/defense-in-depth.md` · `references/debugging/condition-based-waiting.md`
- Host-specific notes (Claude Code, Codex, Cursor): `references/hosts.md`
- Privacy and capture (`<private>`, auto-capture, session logging, PreCompact handoff): `references/privacy-and-capture.md`
- Codex native hooks adapter: `references/codex-native-hooks.md`
- Adapter manifest schema: `references/adapter-manifest-schema.md`
- Tags vocabulary: `references/tags-vocabulary.md`
- CLAUDE.md auto-generation template: `references/claude-md-template.md`
- Global rules (installed as `~/.claude/RULES.md`): `rules/RULES.md`; always-on core block: `rules/CLAUDE-GLOBAL.md`
- Key-rules catalog (one-line code/process rules, defaults, locked principles; selection via `/mb rules` / `mb-rules.sh`): `rules/key-rules.json`
- Reviewer calibration examples per stack: `references/rubric-examples/common.md` · `references/rubric-examples/backend.md` · `references/rubric-examples/frontend.md` · `references/rubric-examples/go.md` · `references/rubric-examples/mobile.md` · `references/rubric-examples/python.md` · `references/rubric-examples/typescript.md`
- Flow routes: `flow-templates/arch.md` · `flow-templates/bugfix.md` · `flow-templates/code-change.md` · `flow-templates/migration.md` · `flow-templates/research.md`
- Flow patterns: `flow-templates/patterns/adversarial-verify.md` · `flow-templates/patterns/classify-and-act.md` · `flow-templates/patterns/fanout-synthesize.md` · `flow-templates/patterns/generate-filter.md` · `flow-templates/patterns/loop-until-done.md` · `flow-templates/patterns/tournament.md`
- CHANGELOG: `CHANGELOG.md`
- Migration v1→v2: `docs/MIGRATION-v1-v2.md`
- Primary entrypoint:
  - `/mb` — if the host supports native commands
  - `commands/mb.md` / `memory-bank` CLI — if native command surface is unavailable
