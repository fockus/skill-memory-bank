---
topic: composable-work-pipeline
created: 2026-06-10
status: ready
---

# Context: composable-work-pipeline

## Purpose & Users

**Users:** developers driving the `/mb work` execution engine (this repo's own
maintainers first — dogfooding — and every downstream project that installs the
Memory Bank skill).

**Problem:** the work engine ships a fixed set of workflow presets
(`execution`, `full-cycle`, `governed-execution`, …) but no preset spans the
complete chain, and individual stages cannot be toggled. Users cannot say
"run my default flow plus a review" or "the full chain minus sdd" without
authoring a bespoke preset. The review stage is also wired into the default,
which makes the common path heavier (and more expensive) than it should be.

**Solution:** make the pipeline composable end-to-end across the canonical chain
`discuss(brainstorm) → sdd → plan → implement → verify → review → judge → done`
(`fix` is a loop inside review→judge, not a standalone stage), configurable in
two complementary ways — the project `pipeline.yaml` and the `/mb work` launch
flags — with a minimal default.

**Success (qualitative):** a user can land on any subset/superset of the chain
either persistently (`pipeline.yaml`) or per-run (flags); the default run is
`implement → verify → done` with no review; review and judge are opt-in; and
existing projects keep working unchanged.

## Functional Requirements (EARS)

- **REQ-001** (ubiquitous): The `/mb work` engine shall resolve its ordered stage list from three layers in precedence order — launch flags first, then `pipeline.yaml` configuration, then the built-in default.
- **REQ-002** (ubiquitous): The `/mb work` engine shall use the `execution` workflow (implement → verify → done) as its built-in default when no launch flag and no `pipeline.yaml` setting selects another workflow.
- **REQ-003** (event-driven): When the user passes `--workflow <preset>`, the `/mb work` engine shall resolve the stage list from `workflows.<preset>` after alias expansion in `pipeline.yaml`.
- **REQ-004** (optional): Where the project `pipeline.yaml` sets `workflow.default`, the `/mb work` engine shall use that preset in the absence of a `--workflow` launch flag.
- **REQ-005** (event-driven): When the user passes a per-stage enable flag (`--review`, `--judge`, `--brainstorm`, `--sdd`, `--plan`), the `/mb work` engine shall insert the corresponding stage into the resolved pipeline at its canonical position.
- **REQ-006** (event-driven): When the user passes a per-stage disable flag (`--no-review`, `--no-judge`, `--no-brainstorm`, `--no-sdd`, `--no-plan`), the `/mb work` engine shall remove the corresponding stage from the resolved pipeline.
- **REQ-007** (optional): Where the project `pipeline.yaml` sets `<stage>.enabled` to true or false, the `/mb work` engine shall add or remove that stage on top of the resolved preset.
- **REQ-008** (event-driven): When a launch flag and a `pipeline.yaml` setting target the same stage with conflicting values, the `/mb work` engine shall apply the launch-flag value.
- **REQ-009** (event-driven): When the user passes `--stages <comma-separated-list>`, the `/mb work` engine shall use exactly that ordered list and shall override the resolved preset and per-stage flags.
- **REQ-010** (ubiquitous): The `/mb work` engine shall provide a `full` preset whose stages are discuss → sdd → plan → implement → verify → review → judge → done.
- **REQ-011** (state-driven): While review is absent from the resolved pipeline, the severity gate (`mb-work-severity-gate.sh`) shall exit PASS without applying severity limits.
- **REQ-012** (event-driven): When review is present in the resolved pipeline, the `/mb work` engine shall resolve the reviewer agent via `mb-reviewer-resolve.sh` and gate its findings via `mb-work-severity-gate.sh` against the `review.severity_gate` limits.
- **REQ-013** (unwanted): If the resolved pipeline contains `judge` without `review`, then the `/mb work` engine shall abort before execution with an error that names the missing `review` prerequisite.
- **REQ-014** (unwanted): If a resolved stage lacks a required upstream artifact such as `sdd` or `plan` with no topic or spec input, then the `/mb work` engine shall abort before execution with an error that names the missing input.
- **REQ-015** (ubiquitous): The `/mb work` engine shall stay backward compatible by resolving the legacy `stage_pipeline` block when the active `pipeline.yaml` defines no `workflows` block.
- **REQ-016** (event-driven): When the user passes `--brainstorm`, the `/mb work` engine shall enable the `discuss` stage, treating brainstorm as an alias of discuss.

## Non-Functional Requirements

- **NFR-001**: Backward compatibility — a project that adds no new configuration must resolve to today's behaviour (default `execution`, review off), and the existing `workflows.*` presets must keep their current step lists.
- **NFR-002**: Token economy — the minimal default keeps per-run cost low; cost grows only as the user opts into heavier stages (review ensemble, judge, full chain).
- **NFR-003**: Determinism — identical launch flags plus identical `pipeline.yaml` must always resolve to the identical ordered stage list (no implicit ordering ambiguity).
- **NFR-004**: Discoverability — `commands/work.md` (the `/mb work` reference) must document every per-stage flag, the `full` preset, and the three-layer precedence.
- **NFR-005**: No-PyYAML parity — stage/gate resolution must behave identically whether or not PyYAML is importable (the existing `parse_*_without_yaml` fallback path must cover the new `review:` / per-stage blocks).

## Constraints

- Must reuse the existing resolution surface (`mb-workflow.sh`, `mb-work-severity-gate.sh`, `commands/work.md`, `references/pipeline.default.yaml`) rather than introduce a parallel engine.
- Must not edit protected CI files (`.github/workflows/*`) to make this work.
- The immutable safety baseline stays: protected-paths, no-placeholders, verification-before-completion are unaffected by stage composition.
- Canonical stage order is fixed; composition adds/removes stages but never reorders the canonical sequence (except the explicit `--stages` escape hatch).

## Edge Cases & Failure Modes

- `/mb work --judge` (no review) → fail-fast: error "judge requires review — add --review or enable review in pipeline.yaml" (REQ-013).
- `/mb work --sdd` against an existing plan target with no topic → fail-fast: error naming the missing upstream input (REQ-014).
- `--workflow full --no-sdd` → resolves discuss → plan → implement → verify → review → judge → done (per-stage disable subtracts from the preset, REQ-006).
- `--no-review` while `pipeline.yaml` sets `review.enabled: true` → review removed (launch flag wins, REQ-008).
- `--stages implement,verify` while `pipeline.yaml` sets `workflow.default: full` → exactly implement,verify runs (`--stages` overrides everything, REQ-009).
- Severity gate invoked on a no-review pipeline → PASS no-op, never the old `exit 2 "no review step"` error (REQ-011).
- PyYAML absent → the `review:` block and per-stage `enabled` flags still parse via the fallback parser (NFR-005).
- Legacy project with only a `stage_pipeline` block and no `workflows` → still resolves and runs (REQ-015).

## Out of Scope

- Adding brand-new stage *types* beyond the canonical chain (e.g. a deploy stage).
- Changing the internal behaviour of any individual stage (the review ensemble, judge logic, verifier checks stay as-is).
- A GUI/TUI for composing pipelines — configuration stays file + flags.
- Reworking the heavyweight `governed-execution` ensemble; `--review` enables the **single-reviewer** path, the ensemble stays behind `--workflow governed-execution`.
