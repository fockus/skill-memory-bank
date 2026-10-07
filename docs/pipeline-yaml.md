# pipeline.yaml reference

`pipeline.yaml` is the declarative config `/mb work` (and its supporting hooks) read to decide
which agent handles which role, which workflow steps run by default, how strict the review gates
are, and which paths are off-limits for automated edits. The skill ships a bundled default at
`references/pipeline.default.yaml`; `/mb config init` copies it into `<bank>/pipeline.yaml` so a
project can override any value locally.

The full selection is a 5-step ladder, checked in order (first match wins):

1. `--pipeline <name>` (or the `$MB_PIPELINE` env var) → `<mb_path>/pipelines/<name>.yaml`.
2. Host binding — the pipeline whose `agents:` list includes the detected code-agent host.
3. `<mb_path>/.mb-config` `pipeline=<name>` (set by `/mb pipeline use`).
4. The pipeline marked `default: true` under `<mb_path>/pipelines/*.yaml`.
5. Legacy `<mb_path>/pipeline.yaml`, then the bundled `references/pipeline.default.yaml`.

The rest of this page documents step 5 — the legacy single-file `pipeline.yaml` — which is still
the simplest path for a single-pipeline project: `/mb work` reads `<bank>/pipeline.yaml` if it
exists, otherwise falls back to the bundled default. The default is always present and always
self-validates, so a project never starts with a broken config. See `commands/work.md` for the
full named-pipeline ladder (steps 1-4).

## roles — mapping a role to an agent

```yaml
roles:
  developer: { agent: mb-developer }
  backend:   { agent: mb-backend,   fallback: mb-developer }
  frontend:  { agent: mb-frontend,  fallback: mb-developer }
  reviewer:
    agent: mb-reviewer
    override_if_skill_present:
      skill: superpowers
      agent: superpowers:requesting-code-review
  judge:     { agent: mb-judge }
  verifier:  { agent: plan-verifier }
```

Every dev-role (`backend`, `frontend`, `ios`, `android`, `devops`, `qa`, `analyst`, `architect`,
`researcher`) can declare a `fallback` agent used when the primary specialist isn't a good fit for
a stage. `reviewer` supports `override_if_skill_present`: if a named host skill (e.g. `superpowers`)
is installed, its own review agent takes over the reviewer role transparently — the rest of the
pipeline contract is unaffected.

## workflow — selecting and naming presets

```yaml
workflow:
  default: medium
  aliases:
    everything: full
    execution: medium
    governed-execution: governed
```

`workflow.default` picks which named preset `/mb work` uses when no `--workflow` flag is passed.
`aliases` lets a project give a preset a shorter or more memorable name. The bundled aliases keep
the pre-2026-10 names working: `execution` → `medium`, `governed-execution` / `strict` → `governed`.

## workflows — the named presets themselves

Each entry under `workflows.<name>` declares an ordered `steps` list plus optional loop behavior:

```yaml
workflows:
  medium:
    description: Default /mb work path from an existing plan/spec; one verifier pass at plan end.
    steps: [implement, verify, done]
    entrypoint: plan_or_spec
    verify: {cadence: plan}

  governed:
    description: Verifier, review ensemble, lead reviewer, independent judge, bounded fix loop.
    steps: [implement, verify, review, judge, fix, done]
    entrypoint: plan_or_spec
    verify: {cadence: plan}
    review_profile: ensemble
    judge_profile: independent
    loop:
      after: judge
      until: judge_go
      returns_to: verify
      max_cycles: 2
      on_max_cycles: judge_decides
```

The bundled default ships four complexity presets — `simple` (implementer only, self-check),
`medium` (the review-free default), `complex` (one reviewer, bounded fix loop) and `governed`
(review ensemble + judge) — plus `full` (the whole composable chain from `discuss` to `done`),
`full-cycle`, `requirements-plan`, `implement-only`, `review-fix`, and `review-only`. `review_profile: single` resolves one reviewer
via `mb-reviewer-resolve.sh`; `review_profile: ensemble` dispatches the 3-5 aspect reviewers plus a
lead-role synthesis, driven by the `review_ensemble` block below.

## stage_pipeline — legacy per-item fallback

`stage_pipeline` exists for older `/mb work` orchestrators that only understand a flat per-item
list rather than named workflows. It documents the same review-free baseline
(`implement → verify → done`) so an orchestrator that predates `workflows.*` still behaves
sensibly. New orchestrators should read `workflow.default` / `workflows.<name>` instead.

## review / judge / discuss / sdd / plan — composable stage toggles

```yaml
review:
  enabled: false
  role: reviewer
  categories: [logic, code_rules, security, scalability, tests]
  severity_gate: { blocker: 0, major: 0, minor: 3 }
  max_cycles: 3
  on_max_cycles: stop_for_human
  pivot_after_cycles: 2
  pivot_escalate_to_architect_on: 4

judge:
  enabled: false
  role: judge
  decisions: [GO, GO_WITH_BACKLOG, NO_GO]
  blocking_policy:
    - unmet_acceptance_criteria
    - failed_verification
    - security_or_data_loss_risk
    - broken_build_or_tests
    - protected_path_violation

discuss: { enabled: false }
plan:    { enabled: false }
sdd:
  enabled: false
  require_ears_in_sdd_command: true
  require_ears_in_plan_command: false
  covers_requirements_policy: warn
```

Every one of these stages is **off by default** — a project turns one on persistently by setting
`enabled: true`, or per-run with the matching launch flag (`--review`, `--judge`, `--brainstorm`,
`--sdd`, `--plan`). Launch flags always win over the persisted `pipeline.yaml` value. `judge`
requires `review` to also be active; requesting `--judge` alone fails fast with a message naming
the missing prerequisite.

`review.pivot_after_cycles` / `review.pivot_escalate_to_architect_on` feed the strategic-pivoting
behavior documented in [/mb work § Sprint contracts](mb-work.md#sprint-contracts-progress-trend-and-strategic-pivoting-work-loop-v2).

## review_ensemble — the governed reviewer wave

```yaml
review_ensemble:
  min_reviewers: 3
  max_reviewers: 5
  reviewers:
    - role: reviewer_logic
      focus: logic
    - role: reviewer_tests
      focus: tests
    - role: reviewer_quality
      focus: code_rules
    - role: reviewer_security
      focus: security
    - role: reviewer_scalability
      focus: scalability
  lead_role: reviewer_lead
  previous_report_required_after_cycle: 1
```

Each aspect reviewer judges the exact same scoped diff (built once via `mb-work-diff.sh`, shared
across the ensemble for consistency), then `lead_role` synthesizes one canonical report:
deduplicating findings, separating blocking issues from backlog candidates, and emitting the
strict JSON the judge step consumes.

## budget / protected_paths / sprint_context_guard — risk controls

```yaml
budget:
  default_limit: null       # null = unlimited; CLI --budget overrides
  warn_at_percent: 80
  stop_at_percent: 100

protected_paths:
  - ".env*"
  - "ci/**"
  - ".github/workflows/**"
  - "Dockerfile*"
  - "k8s/**"
  - "terraform/**"

sprint_context_guard:
  soft_warn_tokens: 150000
  hard_stop_tokens: 190000
```

`protected_paths` is a glob list checked by `mb-work-protected-check.sh` after every implement/fix
dispatch — a `Write`/`Edit` attempt inside one of these globs halts the loop unless
`--allow-protected` was passed. `sprint_context_guard` is a running-spend estimate (character
length of dispatched prompts, ~4 chars/token) that hard-stops a session before it burns through the
context window entirely.

## review_rubric — the fixed-key, extensible checklist

```yaml
review_rubric:
  logic:
    - "Every EARS requirement has at least one assertion in tests"
    - "Edge cases from requirements covered"
  code_rules:
    - "SOLID: SRP — files <300 lines OR <=3 public methods"
    - "No placeholders (TODO/...)"
  security:
    - "Input validation at boundaries"
    - "No secrets in code"
  scalability:
    - "No N+1 queries introduced"
    - "Async where IO-bound"
  tests:
    - "Contract-first: Protocol/ABC defined before impl"
    - "Integration tests > unit tests (Testing Trophy)"
```

The five top-level keys (`logic`, `code_rules`, `security`, `scalability`, `tests`) are required
and match the reviewer's own category set — `mb-pipeline-validate.sh` errors if any of the five is
missing or not a non-empty list of strings. The bullet list under each key is freely extensible
per project.

## cost tiers and model profiles

```yaml
cost: optimal                         # premium | optimal | economy
cost_tiers:                           # role class → premium | mid, one table for every host
  premium: {implementer: premium, planner: premium, researcher: premium, verifier: premium, reviewer: premium, judge: premium}
  optimal: {implementer: mid, planner: premium, researcher: mid, verifier: mid, reviewer: premium, judge: premium}
  economy: {implementer: mid, planner: mid, researcher: mid, verifier: mid, reviewer: mid, judge: mid}
model_profiles:                       # two model ids per host
  claude-code: {premium: opus, mid: sonnet}
  codex: {premium: gpt-6-astra, mid: gpt-6.1-sol}
  cursor: {premium: claude-opus-5-5, mid: claude-sonnet-5-5}
hosts:                                # optional per-host overrides
  codex: {cost: economy, preset: complex, verify: stage}
```

The tier picks only the model; reasoning effort stays in the agent file. Role classes:
`implementer` (developer, backend, frontend, ios, android, devops, qa, debugger, analyst),
`planner` (architect, planner), `researcher`, `verifier`, `reviewer` (reviewer and every
`reviewer_*`), `judge`. `mb-work-plan.sh` resolves each role, first match wins:

1. `--model <id>` — the item's own role only (`model_source: cli`);
2. `roles.<role>.model` — an item role without one takes `roles.developer.model`, as before (`role`);
3. `model_profiles[host][cost_tiers[cost][class]]` (`profile`);
4. `inherit` — the dispatch passes no model; a profile with an unset slot warns and inherits.

Cost: `--cost` ▸ `hosts.<host>.cost` ▸ `cost` ▸ `optimal`. Host: `--host` ▸ auto-detect
(`MB_PIPELINE_HOST`, `MB_AGENT`, host environment). `hosts.<host>.preset` sits between `--tier`
and `workflow.default`; `hosts.<host>.verify` between `--verify` and the workflow's
`verify.cadence`. Each JSON line carries `model`, `model_source`, `cost`, `host` and
`step_models` (verifier, reviewer, judge); `discipline` follows the resolved model. A project
block replaces the default key by key (one tier, one host profile). The `claude-code` profile
matches the `mb-agent-caps.sh` claude-agent fallback.

Host templates (`/mb config init --host <host>`; ids from
`.memory-bank/reports/2026-10-07_host-model-matrix.md`):

| Host | premium | mid | Shipped in the default | Applied |
|------|---------|-----|------------------------|---------|
| `claude-code` | `opus` | `sonnet` | yes | per dispatch (`model=`) |
| `codex` | `gpt-6-astra` | `gpt-6.1-sol` | yes | per dispatch; installed `.toml` roles carry the tier model |
| `cursor` | `claude-opus-5-5` | `claude-sonnet-5-5` | yes | static frontmatter, written by install and `config init --host cursor` |
| `pi` | `defaultProvider/defaultModel` from `.pi/settings.json` ▸ `~/.pi/agent/settings.json`, or `--model-premium` | `--model-mid`, same provider | no (any provider) | per dispatch; bare aliases collapse to the parent |
| `opencode` | `model` from `opencode.json` (global ▸ `$OPENCODE_CONFIG` ▸ project ▸ `$OPENCODE_CONFIG_CONTENT`), or `--model-premium` | `--model-mid` (never `small_model`) | no (any provider) | static agent file, written by install and `config init --host opencode` |

`config init --host pi|opencode` exits 2 when no current model is found and `--model-premium` is
missing, when `--model-mid` is missing, when a value is not `provider/id`, or (Pi) when mid uses
another provider. Nothing is written in those cases, so no placeholder reaches `pipeline.yaml`.
`/mb config show` prints what each role will actually get.

Host constraints:

- **Pi** maps `opus`/`sonnet`/`haiku` to the parent model (AGR-056), so a Pi profile needs
  `provider/id` values from one provider; the validator rejects bare aliases.
- **OpenCode, Cursor** take a subagent model only statically (agent file / config), so a tier
  applies when the agents are rendered (`/mb config init`), not per dispatch.
- `dispatch.model_map` and `mb-agent-caps.sh` translate a model for another CLI transport; they
  are not consulted for the host's own model and `/mb work` does not call them.

The validator rejects an unknown tier or role class, a slot other than `premium|mid`, a profile
without both slots, a `mid` model that matches `discipline.strict_models` (no cheapest model),
unknown `hosts.<host>` keys and an undeclared `hosts.<host>.preset`.

## Validating a pipeline

```bash
/mb config validate                          # validate the resolved pipeline.yaml
bash scripts/mb-pipeline-validate.sh <file>  # validate an arbitrary file
```

Only document keys the shipped validator actually accepts — `mb-pipeline-validate.sh` is the
source of truth for the schema, this page is a guide to it, not the other way around.

## Related

- [/mb work](mb-work.md) — the consumer of every section above.
- [Reviewer 2.0](reviewer-2.md) — how `review_rubric` and `severity_gate` feed the reviewer payload.
- [Hooks reference](hooks.md) — `protected_paths` and `sprint_context_guard` enforced at the hook
  level, not just inside the `/mb work` loop.
