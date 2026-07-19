# `/mb work` — sprint contracts, progress trend, strategic pivoting

Companion to `commands/work.md` / `references/work-reference.md`. Split out so
each file stays within the 400-line project limit (S2 review [26]); the content
is unchanged from the move.

## Sprint contracts, progress trend, and strategic pivoting (work-loop-v2)

Three additive layers wrap the base implement → verify → review → judge → fix loop above (design.md §4/§5/§6,
REQ-110/111/112/113/114). None of them replace a numbered step — they plug into it at a named point.
The scripts below only compute decisions/strings; **dispatch stays the host agent's job** — same
agent-native contract as the rest of this command.

### Sprint contract phase (opt-in, runs before 5a)

- **Gate.** Run this phase for an item only when `--contract` was passed for this invocation, or the
  project's resolved `pipeline.yaml` sets `review.require_contract: true` (design.md §4 "When mandatory";
  default is OFF — there is no dedicated resolver script for this key yet, so read it the same way the
  loop already reads other ad hoc pipeline values, e.g. `sprint_context_guard.hard_stop_tokens`: inspect
  `bash scripts/mb-pipeline.sh show --mb <bank>`). A per-item `<!-- mb-stage:N skip-contract -->` marker
  skips the phase for that one item even when the project requires it.
- **Create/reuse the contract file** (idempotent — a second `create` call for the same plan/stage is a
  no-op that never clobbers a hand-edited draft; the path is always derived through this script, never
  recomputed inline):

  ```bash
  bash scripts/mb-work-contract.sh create --mb <bank> --plan <plan-or-spec path> --stage <N> \
    --role <resolved role> --title "<item heading>"
  ```

  This scaffolds `<bank>/contracts/<plan-topic>_stage-<N>.md` with empty `In scope` / `Plan of attack` /
  `Test plan` / `DoD checkpoints` / `Out of scope` / `Open risks` sections.
- **Dispatch the resolved role-agent** (same `Task`/model/thinking resolution as 5a) to WRITE the
  contract body — concrete in-scope bullets, an ordered plan of attack, a Testing-Trophy-shaped test plan
  with one entry per DoD checkpoint, an explicit (never silent) out-of-scope list, and open risks —
  before any implementation begins.
- **Validate, then review.** `bash scripts/mb-work-contract.sh validate <contract-file>` checks all 7
  frontmatter keys, the `# Contract: <title>` heading, and all 6 body sections are present, naming
  anything missing (never a stack trace). Then dispatch the pipeline-resolved reviewer (same resolution
  as 5d) with the contract content (`mb-work-contract.sh read`) as payload, preamble `review_mode:
  contract` — `agents/mb-reviewer.md` documents the 4-category rubric (`scope` / `dod` / `test_plan` /
  `out_of_scope`; a silent/empty out-of-scope section is a **blocker**). The auto-generated-findings
  pre-injection from 5d does NOT apply here — there are no tests yet.
  - `APPROVED` → contract `status: approved`; proceed to 5a with the approved contract as additional
    implement-step input.
  - `CHANGES_REQUESTED` → generator revises and re-submits for another contract-review cycle, capped at
    **3 contract cycles**; a 4th exhausted cycle is a hard stop for human (there is no code yet to fall
    back on, so this is unconditional — not gated by `on_max_cycles`).
- If implementation later diverges from an approved contract, the normal 5d review flags it as a
  `scope` finding — the contract phase itself never re-runs mid-implementation.

### Progress trend (computed every review cycle, inside 5d)

- Once `mb-work-review-parse.sh` (5d, with or without `--external`) has normalized the reviewer verdict
  into `{"verdict": ..., "counts": {"blocker": N, "major": N, "minor": N}}`, derive this item's stable
  key ONCE through the script's own subcommand — never recompute the hash inline:

  ```bash
  ITEM_KEY=$(bash scripts/mb-work-trend.sh key --plan <plan-or-spec path> --stage <N> --item <M>)
  ```

- Feed the normalized verdict to `compute` to get this cycle's `progress_trend` and refresh the cache for
  next cycle:

  ```bash
  bash scripts/mb-work-trend.sh compute --mb <bank> --item-key "$ITEM_KEY" --verdict-file <normalized-verdict.json>
  # prints exactly one of: improving | stagnant | regressing | null
  ```

  `improving`: this cycle's weighted score (`10*counts.blocker + 3*counts.major + 1*counts.minor`) is
  strictly lower than last cycle's. `stagnant`: within ±1 of last cycle's AND the current score is > 0.
  `regressing`: strictly higher. `null`: first cycle (no previous cache), or a 0/0 converged recheck
  (never counted as stagnant/improving). The cache lives at `<bank>/tmp/last-verdict-<item-key>.json`,
  overwritten every cycle unless `--no-store` is passed.
  - **Known gap (backlog I-099).** `scripts/mb-review.sh` also reserves a `last_verdict_cache_path()`
    helper for this same file, but it is currently inert (its output is discarded) and derives the key
    differently (`mb_sanitize_topic(item)` vs. this script's `sha256(plan+stage+item)`). Until the two
    are reconciled, always derive the key via `mb-work-trend.sh key` above — never mb-review.sh's
    helper — so the cache the loop reads from stays the single source of truth.
- The orchestrator (not any script) tracks `consecutive_stagnant` for this item across cycles: increment
  on `stagnant`, reset to 0 on `improving` / `regressing` / `null`. This tally feeds the pivot decision
  below.

### Strategic pivoting (on a CHANGES_REQUESTED verdict, before the re-dispatch in 5f)

- Ask whether to keep refining or force a fresh start, passing the tracked `consecutive_stagnant` and
  the current cycle number (from `mb-work-state.sh cycle`/`status`):

  ```bash
  bash scripts/mb-work-pivot.sh decide --mb <bank> --consecutive-stagnant <N> --cycle <C> \
    --item-id "$ITEM_KEY" --rationale "<one-line reason>"
  # prints exactly one of: refine | pivot_in_role | pivot_via_architect
  ```

  `refine` while `consecutive_stagnant < pivot_after_cycles` (default 2, resolved from
  `pipeline.yaml:review.pivot_after_cycles`, falling back to a flat top-level key, then the default) —
  this is the existing 5f behavior, unchanged. Once that threshold is reached, `pivot_in_role`; once the
  cycle count also reaches `pivot_escalate_to_architect_on` (default 4,
  `pipeline.yaml:review.pivot_escalate_to_architect_on`), `pivot_via_architect`. A pivot decision (mode
  != `refine`) with `--item-id` given also appends one JSONL line to `<bank>/tmp/pivot-log.jsonl`
  (`ts` / `item_id` / `cycle` / `mode` / `rationale_hash`) — analysis data, intentionally not git-tracked.
- **`pivot_in_role`** — re-dispatch the SAME role-agent (never a different one), replacing the normal
  "fix these issues" framing with the script's own discard-and-restart instruction:

  ```bash
  bash scripts/mb-work-pivot.sh prompt-prefix --mode pivot_in_role --stagnant <N>
  ```

  This tells the agent to discard the current approach rather than patch it, read the issue list as
  constraints on a fresh design (not a literal edit list), implement a different
  architecture/strategy/abstraction from scratch, and state a one-line "Pivot rationale: ..." at the top
  of its work.
- **`pivot_via_architect`** — heavier, two-step dispatch, reached only at cycle ≥
  `pivot_escalate_to_architect_on`: first dispatch `mb-architect` with the issue list and current code
  state to produce a redesign sketch at `.memory-bank/notes/<date>_pivot-<topic>.md`; then dispatch the
  role-agent with both the issue list and the architect's sketch, prefixed with
  `bash scripts/mb-work-pivot.sh prompt-prefix --mode pivot_via_architect --stagnant <N>` (its output
  appends the two-step escalation text to the same discard-and-restart instruction).
- Either pivot mode still runs through the SAME 5f mechanics afterward (protected-path check, return to
  `verify`, review/judge again) — pivoting changes what the agent is asked to do, not the loop's control
  flow, and does not reset or extend `max_cycles`.

### Max-cycle policy (already covered by 5f — restated for completeness)

`on_max_cycles: stop_for_human` is the shipped default in `references/pipeline.default.yaml` (previously
`continue_with_warning` — see the `[Unreleased]` CHANGELOG entry for the migration note and the 5f
cycle-exhausted handling above for the full behavior). This applies identically whether the exhausted
cycles were plain `refine` cycles or included one or more pivots.
