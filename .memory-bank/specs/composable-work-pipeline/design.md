# Design: composable-work-pipeline

Reuses the existing resolution surface — no parallel engine. Source of truth for
the stage list is `mb-workflow.sh`; `commands/work.md` drives it; the gate and
validator enforce the composed result.

## Architecture — 3-layer stage resolution

Resolution lives in `scripts/mb-workflow.sh` and produces one ordered stage list:

```
                built-in default            pipeline.yaml                 launch flags
                (lowest precedence)         (project persistent)          (per-run, highest)
 base list  ──►  execution = [implement,  ─► workflow.default: <preset>  ─► --workflow <preset>
                 verify, done]                + <stage>.enabled: bool        + --review/--judge/... (+ --no-*)
                                                                             + --stages a,b,c (overrides all)
                                          └────────────── merge ──────────────┘
                                                       │
                                              composed ordered stage list
                                                       │
                       ┌───────────────────────────────┼────────────────────────────────┐
                       ▼                                ▼                                 ▼
            mb-pipeline-validate.sh          mb-work-severity-gate.sh             commands/work.md
            (fail-fast on bad chains)        (PASS no-op if no review)            (dispatch each stage)
```

**Canonical order** (composition adds/removes, never reorders, except `--stages`):
`discuss → sdd → plan → implement → verify → review → judge → done`.

**Merge algorithm** (deterministic — NFR-003):
1. Start from the resolved preset's `steps` (preset = `--workflow` ▸ else `workflow.default` ▸ else `execution`).
2. Apply `pipeline.yaml` per-stage `<stage>.enabled` add/remove.
3. Apply launch per-stage flags (`--review`/`--no-review`, …) add/remove — these win over step 2 (REQ-008).
4. Re-sort the resulting set into canonical order.
5. If `--stages a,b,c` is present, discard 1–4 and use that exact ordered list (REQ-009).

## Interfaces

### `mb-workflow.sh` (CLI — additions)
```
mb-workflow.sh [--mb <path>] [--workflow <name>]
               [--review|--no-review] [--judge|--no-judge]
               [--brainstorm|--no-brainstorm] [--sdd|--no-sdd] [--plan|--no-plan]
               [--stages <csv>] [--json|--steps]
# stdout (--steps): newline-separated canonical stage list
# stdout (--json):  {"workflow": "...", "steps": [...], "source": "flags|pipeline|default"}
# inputs:  pipeline.yaml (resolved), launch flags
# outputs: ordered stage list
# errors:  unknown --workflow / unknown stage in --stages → exit 2 with message
```

### `pipeline.yaml` schema (additions)
```yaml
workflow:
  default: execution            # preset selection (unchanged)
workflows:
  full:                         # NEW preset (REQ-010)
    steps: [discuss, sdd, plan, implement, verify, review, judge, done]
    entrypoint: freeform_or_topic
# Per-stage opt-in blocks (REQ-007) — review: already present this session:
review:   { enabled: false, role: reviewer, severity_gate: {blocker: 0, major: 0, minor: 3}, max_cycles: 3, on_max_cycles: stop_for_human }
judge:    { enabled: false }
discuss:  { enabled: false }
sdd:      { enabled: false }
plan:     { enabled: false }
```

### `mb-work-severity-gate.sh` (behaviour change — REQ-011/012)
- Reads gate limits from `review.severity_gate` (modern) ▸ `stage_pipeline[step=review].severity_gate` (legacy) ▸ active workflow `loop.severity_gate`.
- Returns a "no review configured" sentinel when none is found → `main` prints PASS and exits 0 (was `exit 2`). Identical in the no-PyYAML fallback (NFR-005).

### `mb-pipeline-validate.sh` (validation — REQ-013/014)
- Accepts a composed stage list with or without review (no "verify before review" rule — already removed this session).
- Fail-fast: `judge` present without `review` → error naming the missing prerequisite.
- Fail-fast: `sdd`/`plan` present with no upstream input (no topic / no spec) → error naming the missing input.

## Decisions

- **D1 — brainstorm = discuss alias** (REQ-016). No new stage type; `--brainstorm` enables `discuss`. Keeps the stage vocabulary minimal (KISS).
- **D2 — `--stages` is an escape hatch** that overrides every other layer (REQ-009); the only way to express a non-canonical order.
- **D3 — flags beat pipeline.yaml beats default** (REQ-001/008). One documented precedence avoids ambiguity.
- **D4 — `--review` = single-reviewer path** (mb-reviewer-resolve.sh + gate), NOT the ensemble. The 5-reviewer ensemble stays behind `--workflow governed-execution` (Out of Scope).
- **D5 — fail-fast over auto-insert** (REQ-013/014). Invalid chains error with a hint rather than silently mutating the pipeline (project Fail-Fast rule).
- **D6 — legacy `stage_pipeline` kept** as a fallback when no `workflows` block exists (REQ-015) — back-compat, not primary.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| R1 — backward-compat regression (NFR-001) | M | H | Existing `workflows.*` step lists unchanged; new behaviour additive; full pytest + bats stay green. |
| R2 — no-PyYAML drift (NFR-005) | M | M | Mirror every new read in `parse_*_without_yaml`; keep `test_default_gate_works_without_pyyaml` green. |
| R3 — non-deterministic merge (NFR-003) | L | M | Canonical re-sort (merge step 4) + unit test asserting flag/yaml combos resolve to a fixed list. |
| R4 — contract-test churn | H | L | The 3 currently-red pytest contracts encode the OLD review-in-default assumption; rewritten (TDD) to the new default-no-review contract as Task 1. |
