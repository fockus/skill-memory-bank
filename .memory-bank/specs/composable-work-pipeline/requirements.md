# Requirements: composable-work-pipeline

> Spec triple — see also: design.md, tasks.md.
>
> EARS patterns:
> - Ubiquitous:        `The <system> shall <response>`
> - Event-driven:      `When <trigger>, the <system> shall <response>`
> - State-driven:      `While <state>, the <system> shall <response>`
> - Optional feature:  `Where <feature>, the <system> shall <response>`
> - Unwanted:          `If <trigger>, then the <system> shall <response>`

## Requirements (EARS)

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


## Scenarios

<!-- OPTIONAL but recommended: GIVEN/WHEN/THEN acceptance scenarios.            -->
<!-- Each scenario links to its REQ(s) via **Covers:** and becomes a test-plan  -->
<!-- item (scripts/mb-scenario-extract.py) that /mb work turns into a real test -->
<!-- in the project's own stack. Enforce "every REQ has a scenario" with         -->
<!-- mb-spec-validate.sh --require-scenarios (off by default).                   -->

<!-- mb-scenario:1 -->
### Scenario: <name>
**Covers:** REQ-NNN

- GIVEN <initial state>
- WHEN <action taken>
- THEN <observable outcome>
- AND <additional outcome — optional>
<!-- /mb-scenario:1 -->
