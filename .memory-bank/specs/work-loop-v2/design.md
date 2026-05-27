---
spec_id: work-loop-v2
topic: Work loop 2.0 — sprint contract, strategic pivoting, fail-fast default
status: ready
author: brainstorming-session
created: 2026-05-23
parent_roadmap: harness-upgrade (S2 of S1..S4)
addresses_gaps: [GAP-2, GAP-3, GAP-9]
non_addresses: [GAP-1, GAP-4, GAP-5, GAP-6, GAP-7, GAP-8, GAP-10]
depends_on_specs: [reviewer-2.0]
breaking_changes: no in v4 (v5 fail-fast default is gated by explicit migration)
---

# Work loop 2.0 — Design

Sub-project **S2** of the harness upgrade. Polishes the implement→review→fix cycle inside `/mb work`. Addresses sprint contract as an explicit artifact (GAP-2), strategic pivoting when scores stagnate (GAP-3), and switches the `on_max_cycles` default to fail-fast (GAP-9).

This spec assumes S1 (Reviewer 2.0) has landed because pivoting relies on the calibrated, tests-aware reviewer to produce reliable trend signal. Without S1, pivoting would react to noisy verdicts.

## 1. Goals & Non-goals

### Goals

- **G1 (GAP-2)** — Introduce **sprint contract** as a first-class artifact. Before any code is written, the role-agent (generator) emits a contract for the item: scope, plan-of-attack, test plan, out-of-scope. Reviewer signs off on the contract before implementation begins. Configurable: opt-in (`--contract` flag) and per-project mandatory (`pipeline.yaml:require_contract: true`).
- **G2 (GAP-3)** — Track `progress_trend` across cycles (`improving | stagnant | regressing`) and trigger **strategic pivoting** when stagnant for `pivot_after_cycles` (default 2). Pivot = explicit instruction to the generator to try a different approach, optionally with `mb-architect` redesign on second pivot.
- **G3 (GAP-9)** — Flip `on_max_cycles` default from `continue_with_warning` to `stop_for_human`. Existing projects that explicitly set `continue_with_warning` remain unaffected; projects with no entry get the new default.

### Non-goals (explicit)

- Calibrated reviewer rubric (S1 dependency).
- Tests-aware reviewer (S1 dependency).
- Auto-actualize on PreCompact (S3).
- Mandatory done-gates without plan (S3).
- Multi-model role assignment (S4).
- Changing `severity_gate` numeric thresholds.
- Adding new role-agents (sprint contract reuses `mb-reviewer` in a new `review_mode`).

## 2. Architecture overview

```
/mb work step 3 — per item:

  ┌─────────────────────────────┐
  │ 3a. (NEW) Contract phase    │  ← if --contract OR require_contract
  │                             │
  │   role-agent writes:        │
  │   contracts/<topic>_        │
  │      stage-<N>.md           │
  │                             │
  │   mb-reviewer (mode=        │
  │      contract) approves     │
  │   or asks for revisions     │
  └─────────────┬───────────────┘
                ▼
  ┌─────────────────────────────┐
  │ 3b. Implement (existing)    │  ← unchanged
  └─────────────┬───────────────┘
                ▼
  ┌─────────────────────────────┐
  │ 3c. Review                  │  ← S1 orchestrator, NOW emits
  │     progress_trend          │
  └─────────────┬───────────────┘
                ▼
  ┌─────────────────────────────┐
  │ 3d. Gate + Trend evaluation │  ← NEW logic
  │                             │
  │ if APPROVED → 3f Verify     │
  │ if CHANGES_REQUESTED:       │
  │   if trend == stagnant for  │
  │      pivot_after_cycles:    │
  │      → 3e' PIVOT            │
  │   else:                     │
  │      → 3e Refine            │
  │   if cycle == max_cycles:   │
  │      stop_for_human (new    │
  │      default)               │
  └─────────────────────────────┘
```

**Key idea**: the review loop gains two new exit branches — pivot and stop_for_human — and one new entry phase (contract). The Reviewer 2.0 orchestrator from S1 is extended to compute `progress_trend` and to support `review_mode: contract`.

## 3. File inventory

### New files

| Path | Kind | Purpose |
|------|------|---------|
| `scripts/mb-work-contract.sh` | bash | Contract orchestrator — assembles contract prompt for generator and contract-review prompt for reviewer |
| `scripts/mb-work-trend.sh` | bash | Trend calculator — reads last N reviewer JSON verdicts, returns `improving/stagnant/regressing` |
| `templates/contract.md` | markdown | Contract template skeleton |
| `tests/bats/test_mb_work_contract.bats` | bats | Contract phase tests |
| `tests/bats/test_mb_work_trend.bats` | bats | Trend calculator tests |
| `tests/bats/test_mb_work_pivot.bats` | bats | Pivot branch integration tests |
| `tests/bats/test_pipeline_default_max_cycles.bats` | bats | Verifies new default for `on_max_cycles` |
| `docs/work-loop-2.0.md` | docs | User-facing guide |

### Project-owned (created during workflow)

- `.memory-bank/contracts/<plan-topic>_stage-<N>.md` — one per work item
- `.memory-bank/contracts/archive/<timestamp>_<topic>_stage-<N>.md` — superseded contracts

### Modified files

| Path | Change |
|------|--------|
| `agents/mb-reviewer.md` | New `review_mode` input: `contract` vs `implementation`. Contract mode evaluates scope completeness + DoD coverage + test plan; emits APPROVED/CHANGES_REQUESTED but with a contract-specific issue list (categories: `scope`, `dod`, `test_plan`, `out_of_scope`). |
| `commands/work.md` | New step 3a inserted before existing 3b. New 3d logic with pivot branch. Documents `--contract` flag and `--pivot-after N` flag. |
| `scripts/mb-review.sh` (from S1) | Extended to emit `progress_trend` field on every review verdict. Computes by reading the previous cycle's verdict from `.memory-bank/tmp/last-verdict-<item>.json`. |
| `references/pipeline.default.yaml` | `on_max_cycles: stop_for_human` (was `continue_with_warning`). New keys: `require_contract: false`, `pivot_after_cycles: 2`, `pivot_escalate_to_architect_on: 4` (cycle number to switch to architect-led pivot). |
| `agents/mb-reviewer.md` JSON schema | Adds `progress_trend` field at top level (`improving | stagnant | regressing | null` — null on first cycle). |
| `CHANGELOG.md` | Documents the on_max_cycles default flip + new contract phase. |

## 4. Sprint contract — format and lifecycle

### Contract file format

Path: `.memory-bank/contracts/<plan-topic>_stage-<N>.md`. Created once per work item, archived (not deleted) when superseded.

```markdown
---
plan: <plan-file-path>
stage: <N>
item_id: <stage-N>
generator_role: <role-agent>
created: <ISO-8601>
status: draft | approved | superseded
contract_version: 1
---

# Contract: <stage title>

## In scope (what THIS item delivers)
- ...

## Plan of attack (ordered, mechanical)
1. ...
2. ...

## Test plan
- Unit:
- Integration:
- E2E (if applicable):

## DoD checkpoints (echoes plan, with how-to-verify)
- [ ] <DoD item 1> → verified by <test or check>
- [ ] <DoD item 2> → verified by <test or check>

## Out of scope (explicit non-deliverables)
- ...

## Open risks (acknowledged at contract time)
- ...
```

### Lifecycle

```
generator role-agent writes contract
  → status: draft
  → mb-reviewer (mode=contract) reviews
    if APPROVED → status: approved, proceed to implement
    if CHANGES_REQUESTED → generator revises, re-review (max 3 contract cycles)
    if 3 cycles exhausted → stop_for_human

implement phase consumes approved contract as additional input to the role-agent

if implementation diverges from contract → reviewer flags as `scope` issue at impl review
```

### When mandatory

- Per-project: `pipeline.yaml:require_contract: true` → every `/mb work` item runs the contract phase first.
- Per-invocation: `/mb work <target> --contract` → opts in for this run only.
- Default: OFF. Existing projects keep current flow.

### Per-stage cost

One contract round adds roughly 1 subagent dispatch to role-agent (draft) + 1 to reviewer (review). On Claude Code this is `Task()`; on OpenCode `opencode run`; on Codex `codex run`. Budget guard counts these against the same `--budget TOK` ceiling regardless of host.

## 5. Strategic pivoting

### Trend signal

`progress_trend` is computed in `scripts/mb-work-trend.sh` on every review cycle.

```
weighted_score(verdict) = 10 * counts.blocker + 3 * counts.major + 1 * counts.minor

current  = weighted_score(this_cycle.verdict)
previous = weighted_score(last_cycle.verdict)   # null on first cycle

improving:    current < previous (strictly less)
stagnant:     |current - previous| ≤ 1 AND current > 0
regressing:   current > previous
null:         first cycle (no previous)
```

The reviewer (S1 orchestrator) writes `progress_trend` into its JSON output. The trend script's logic is duplicated nowhere — the orchestrator owns the field.

Previous-cycle storage: `.memory-bank/tmp/last-verdict-<item>.json` (overwritten each cycle). Item key = sha of `(plan_path + stage_no + item_no)`.

### Pivot decision

```
on review verdict CHANGES_REQUESTED:
  consecutive_stagnant = count of consecutive stagnant trends including this one
  if consecutive_stagnant >= pivot_after_cycles (default 2):
    pivot_mode = "pivot_in_role"  # first time
    if current_cycle >= pivot_escalate_to_architect_on (default 4):
      pivot_mode = "pivot_via_architect"  # heavier
  else:
    pivot_mode = "refine"  # existing behavior
```

### Pivot dispatch — `pivot_in_role`

Re-dispatch the same role-agent with a specifically crafted prompt prefix:

```
PIVOT INSTRUCTION: Your previous attempts did not converge on a passing review (stagnant trend for {N} cycles). Do NOT continue refining the current approach. Discard it. Read the issue list as constraints, not as edits. Propose a different architecture/strategy/abstraction and implement it from scratch. State explicitly at the top of your work: "Pivot rationale: <one line>".
```

The role-agent is now expected to start fresh in code shape, not patch.

### Pivot dispatch — `pivot_via_architect`

First dispatch `mb-architect` with the issue list and current code state, asking for a redesign sketch (markdown to `.memory-bank/notes/<date>_pivot-<topic>.md`). Then dispatch the role-agent with both the issue list and the architect's sketch as context.

This branch is heavier but used only at cycle ≥4 when the cheaper pivot has not converged.

### Telemetry

Each pivot writes a one-line entry to `.memory-bank/tmp/pivot-log.jsonl`:

```json
{ "ts": "...", "item_id": "...", "cycle": 3, "mode": "pivot_in_role", "rationale_hash": "sha256:..." }
```

This is data for later analysis ("did pivoting help in this project?"). Not committed to git.

## 6. Fail-fast default

### Current state

`references/pipeline.default.yaml`: `on_max_cycles: continue_with_warning` (treat as soft).

### New default

`references/pipeline.default.yaml`: `on_max_cycles: stop_for_human` (treat as hard).

### Migration semantics

The orchestrator reads the key from the project's `pipeline.yaml`. If the key is **absent**, it falls back to the **new** default (`stop_for_human`). Existing projects that explicitly set `continue_with_warning` keep their behavior. Projects without a `pipeline.yaml` get the new default automatically.

`install.sh` does NOT rewrite existing `pipeline.yaml` files — the change is intentionally opt-in by silence.

The CHANGELOG entry warns: "Projects that prefer the old behavior must add `on_max_cycles: continue_with_warning` to their `pipeline.yaml` explicitly."

## 7. Reviewer agent — contract mode contract

The S1-simplified `mb-reviewer` learns one new mode toggle, passed via the orchestrator payload preamble:

```
review_mode: contract | implementation
```

### Contract mode rubric (categories)

- `scope` — Are in-scope items concrete enough to test? Is in-scope ≠ out-of-scope?
- `dod` — Does the contract echo every DoD checkbox from the plan with a "how to verify" line?
- `test_plan` — Is there at least one test per DoD checkbox? Does it match Testing Trophy split?
- `out_of_scope` — Is out-of-scope explicit, or is it silent (silent = blocker)?

Severity scale stays the same (blocker / major / minor). The auto-finding pre-injection rule from S1 (for failing tests) does NOT apply in contract mode — there are no tests yet.

### Output

Same JSON schema as implementation mode; orchestrator routes the verdict appropriately.

## 8. Testing strategy

### Integration (≈70%)

- `test_mb_work_contract.bats` — contract phase: file is created, reviewer is dispatched in contract mode, APPROVED transitions to implement phase, CHANGES_REQUESTED loops back for up to 3 revisions, archives are written.
- `test_mb_work_pivot.bats` — stagnant trend for 2 cycles triggers `pivot_in_role` prompt; cycle ≥4 triggers `pivot_via_architect` with note creation.
- `test_pipeline_default_max_cycles.bats` — absent `on_max_cycles` resolves to `stop_for_human`; explicit `continue_with_warning` honored.

### Unit (≈20%)

- `test_mb_work_trend.bats` — trend computation: weighted score correct; improving/stagnant/regressing edge cases; first-cycle returns null.

### E2E (≈10%, manual)

- Synthetic sandbox: small plan with one item that intentionally has a hard issue. Run `/mb work --contract --max-cycles 5`. Expect: contract approved cycle 1, implementation cycle 1 fails, stagnant cycle 2, pivot at cycle 3, success cycle 4. Manual smoke at S2 close.

### Static checks

- `shellcheck` on new bash scripts (`mb-work-contract.sh`, `mb-work-trend.sh`).
- `mb-rules-check.sh` CLEAN on all changed files.

## 9. Definition of Done (SMART)

- [ ] `scripts/mb-work-contract.sh` exists, executable, `shellcheck` clean.
- [ ] `scripts/mb-work-trend.sh` exists, executable, `shellcheck` clean.
- [ ] `templates/contract.md` exists with the §4 structure.
- [ ] `agents/mb-reviewer.md` documents the new `review_mode: contract` and its rubric.
- [ ] `commands/work.md` has explicit step 3a (Contract) and step 3d updated with pivot decision tree.
- [ ] `references/pipeline.default.yaml` updated: `on_max_cycles: stop_for_human`, `require_contract: false`, `pivot_after_cycles: 2`, `pivot_escalate_to_architect_on: 4`.
- [ ] `scripts/mb-review.sh` (from S1) emits `progress_trend` on every verdict, sourced from a previous-verdict cache.
- [ ] `tests/bats/test_mb_work_contract.bats` ≥4 tests, all PASS.
- [ ] `tests/bats/test_mb_work_trend.bats` ≥5 tests covering all branches, all PASS.
- [ ] `tests/bats/test_mb_work_pivot.bats` ≥3 tests, all PASS.
- [ ] `tests/bats/test_pipeline_default_max_cycles.bats` ≥2 tests, all PASS.
- [ ] `docs/work-loop-2.0.md` covers contract lifecycle, pivot decision tree, fail-fast migration.
- [ ] `CHANGELOG.md` entry under `[Unreleased]` enumerates: contract phase, pivot, fail-fast default, new pipeline keys, `progress_trend` field.
- [ ] `/mb verify` clean on branch — no regression in existing bats.

## 10. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Contract phase adds token cost on small items | Opt-in by default; pipeline-mandatory only when the project explicitly chooses. Encourage skipping for trivial items via plan flag (`<!-- mb-stage:N skip-contract -->`). |
| Pivot detection too aggressive on noisy reviewer | Calibrated reviewer from S1 mitigates noise; threshold `pivot_after_cycles=2` requires 2 consecutive stagnant cycles. Tunable per project. |
| Pivot via architect creates a new note every cycle | Archive policy: notes under `.memory-bank/notes/<date>_pivot-<topic>.md` rotate via existing `mb-compact.sh` (>90d + low importance). |
| Fail-fast default surprises long-time users | CHANGELOG warning; users can restore old behavior with one-line addition to `pipeline.yaml`. |
| Trend cache collisions when running parallel `/mb work` on different items | Item key includes sha of `(plan_path + stage_no + item_no)`; collisions practically impossible. |
| Contract drift from approved version mid-implementation | Reviewer flags scope deviation as a `scope` issue at impl review; orchestrator can refuse to proceed if drift is severe (future enhancement; not in S2 scope). |

## 11. Out-of-scope follow-ups

- Hard scope-drift blocker (orchestrator-side enforcement that implementation hasn't strayed from approved contract) — backlog.
- Pivot-effectiveness telemetry dashboard from `pivot-log.jsonl` — backlog.
- Contract versioning (allow re-negotiation mid-implementation) — backlog.

## 12. Open questions to resolve during implementation

- Exact archive policy for superseded contracts (rotate by count vs by age).
- Whether the contract should reference the spec's `linked_spec` when applicable (likely yes — pulls EARS requirements into scope discussion).
- Whether pivot triggers should also bump severity gate slightly downward (e.g., allow 1 extra minor on pivot cycle) — left for empirical tuning post-S2.
