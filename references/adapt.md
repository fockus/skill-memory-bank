# ADaPT — decompose as needed

## Contents

- [Principle](#principle)
- [Triggers](#triggers)
- [`complexity_escalation` block](#complexity_escalation-block)
- [Fork — auto vs HITL](#fork--auto-vs-hitl)
- [/mb work handling (implemented in Stage 2)](#mb-work-handling-implemented-in-stage-2)
- [Lite slice vs the full spec](#lite-slice-vs-the-full-spec)

ADaPT (As-Needed Decomposition and Planning, Prasad et al., 2023, arXiv 2311.05772): plan coarse,
let the executor try each item whole, and decompose only the item that does not go through — only
when it fails, and only that item. This replaces up-front fine-grained splitting (AGR-078, AGR-080).

## Principle

- **Plans stay coarse.** A stage marks a boundary (`commands/plan.md` § 1.5), not a size unit.
- **The implementer takes the item whole.** Most items fit; splitting them in advance only adds
  hand-offs and checks.
- **Escalate, do not improvise.** When an item turns out to need a new subsystem or clearly will not
  fit, the implementer stops and returns a `complexity_escalation` block. It neither splits the item
  on its own nor keeps going blind.

## Triggers

The ADaPT fork opens on any of these (one escalation even if several fire at once):

| Trigger | Condition | Default |
|---|---|---|
| implementer signal | the report carries a `complexity_escalation` block | always on |
| verify guard | verify failed on the same item `adapt.verify_fail_cycles` times (`count >= threshold`) | 3 |
| token guard | the item spent more than `adapt.item_token_budget` tokens | `null` = off |

## `complexity_escalation` block

The implementer puts it in its report next to the STATUS (`BLOCKED`, since the item is not done):

```yaml
complexity_escalation:
  reason: "Needs a token-refresh subsystem the item does not mention; the HTTP client has no hook for it."
  estimate: "~3x the item: new refresh module, retry wiring in the client, 2 test files"
  proposed_subitems:
    - title: "Token refresh module with its contract tests"
      Files: src/auth/refresh.py, tests/auth/test_refresh.py
    - title: "Wire refresh into the HTTP client retry path"
      Files: src/http/client.py, tests/http/test_client_retry.py
```

- `reason` — required, non-empty: what makes the item bigger than it looked, with the evidence.
- `estimate` — required: the size as you see it (effort, files, rough tokens). The full spec's
  envelope carries the same fact as `estimated_tokens`.
- `proposed_subitems[]` — 2–5 entries, each with `title` and `Files:` (the files that sub-item edits).
  Together they cover the whole item (AND semantics): the parent closes only after all of them.

## Fork — auto vs HITL

- **auto** — the planner (`mb-architect`, decompose mode) splits only this item into 2–5 sub-items with
  `Files:`, starting from `proposed_subitems` when present. Sub-items run through the same workflow.
- **HITL** — the user picks one of four choices:
  1. **continue** — run the item as is; a later failure can open a new fork;
  2. **simplify** — the item stays open and the run stops until its scope/DoD is cut;
  3. **decompose** — split the item into sub-items as in auto;
  4. **skip** — leave the item open, move to the next one, list it as not done in the summary.

**Depth ≤ 2** (`adapt.max_depth`): a sub-item may escalate once more; a third level is refused with a
message and the run halts on that item.

## /mb work handling (implemented in Stage 2)

Stage 2 of `plans/2026-10-07_feature_adapt-lite.md` wires this into `/mb work` (`commands/work.md` step
5c1). The mechanics live in `scripts/mb_work_adapt.py` and `scripts/mb-work-state.sh`.

**Config.** `pipeline.yaml` → `adapt: {enabled: true, verify_fail_cycles: 3, item_token_budget: null,
max_depth: 2}` (validated by `mb-pipeline-validate.sh`). `mb-workflow.sh --json` returns the effective
block once per run as `adapt`. `--no-adapt` (or `enabled: false`) sets `enabled: false`, which means
today's behavior: an escalation is a plain `BLOCKED` and a failed verify halts the item.

**Detect.** Run the checks after each implement/fix dispatch and after each verify FAIL:

1. Signal: save the implementer report to a file and run
   `python3 "$SKILL_DIR"/scripts/mb_work_adapt.py parse --file <report>`. It accepts a YAML block
   (fenced or bare) or a JSON object with the key. Exit 0 prints the normalized block
   (`proposed_subitems[].files` as a list). Exit 1 = no block. Exit 3 = invalid block (fewer than 2
   or more than 5 sub-items, a missing `title`/`Files`, an empty `reason`/`estimate`), with the reason
   on stderr; treat it as `BLOCKED` and ask the implementer for a valid block once.
2. Verify guard: on a verify FAIL record `mb-work-state.sh step verify_fail` (for a sub-item:
   `step verify_fail@<id>`), then run `mb-work-state.sh adapt-check [<sub-item id>] --run-id "$RUN_ID"
   --mb <bank>`. It counts those steps in the item's run state (`steps[]`, reset by `init` for the next
   item; the fix loop's `cycle` ceiling still applies on its own). The JSON reports
   `trigger: true` with `reasons: ["verify_fail_cycles"]` once `count >= verify_fail_cycles`.
   Below the threshold the item is retried within the run: re-dispatch the implementer with the
   verifier's findings, then verify again. With `enabled: false` the first FAIL halts, as before.
   Under `plan`/`run` cadence one verifier pass judges several items: record `verify_fail` on each
   item its findings name (on the last item when they name none) and retry those items.
3. Token guard: pass `--item-tokens N` to the same call, where N is the item's spend: the
   `mb-work-budget.sh status` `spent` delta since the item started, or the sum of its Task usage. It
   fires only when `item_token_budget` is set and N is over it.

Without a trigger nothing changes. With `enabled: false`, `adapt-check` never triggers.

**Fork.** On a trigger (once per item, even when several fire):

- **auto (`--auto`)** — dispatch `roles.planner` (`mb-architect`, "Decompose mode") with the item body,
  the escalation block or guard reason, and the verifier findings. Pass its 2–5 sub-items as JSON to
  `mb-work-state.sh split <item> --subitems '[{"title":…,"Files":…},…]' --run-id "$RUN_ID" --mb <bank>`.
- **HITL** — show reason, estimate and proposed sub-items, then ask for one of:
  - **continue** — record `step adapt_continue`, re-dispatch the implementer; a later failure can open
    a new fork;
  - **simplify** — stop the run; the item stays open until the user cuts its scope/DoD;
  - **decompose** — as auto;
  - **skip** — leave the item open (no `done`, no checkbox flip), go to the next item, list it as not
    done in the summary.

**Split and run.** `split` validates the list, stores the sub-items in the run state under
`adapt.subitems[]` (`id` = `<parent>.<n>`, `parent`, `depth`, `title`, `files`, `phase: open`), appends
`ADaPT: item <N> split into <ids> (depth d)` to `progress.md` through `mb-work-progress-append.sh`, and
prints the sub-items with a `wave` number (`scripts/mb_work_waves.py`: disjoint `Files:` share a wave).

Each sub-item runs the workflow's item steps (implement → verify → review/judge/fix when selected)
with its title, `Files:` and the parent's DoD as context. The diff and verify are scoped to its
`Files:`. A same-wave group may be dispatched in one message, as in `commands/work.md` step 3. Close
each sub-item with `mb-work-state.sh sub-done <id>`. The plan file is never edited: `mb-stage:N` stays
an integer, and the sub-items live only in the run state and the progress line. `status` shows them,
and re-arming `init` on the same open item keeps them (resume).

**Close.** The parent goes through the normal `done` → `flip` once every sub-item is done.
`mb-work-state.sh done` (and `sub-done` of a split sub-item) exits **6** while a sub-item is open.

**Depth.** A sub-item may escalate once more: `split 2.1` creates `2.1.1…` at depth 2. Splitting at depth
`max_depth` (`split 2.1.1` with the default 2) exits **6** with `ADaPT refused: … > max_depth 2`. Halt on
that item and report it.

**Summary.** The end-of-run summary has one line per escalation: item, trigger (signal / verify guard /
token guard), and outcome (split into ids / continue / simplify / skip / refused at depth).

## Lite slice vs the full spec

This is the first slice of `specs/svp-adapt-escalation` (AGR-080). It covers REQ-001 (signal), REQ-002
in part (verify and token guards; the scope guard needs `svp-parallel-engine`), REQ-003 (thresholds in
`pipeline.yaml`), REQ-005 (four HITL choices) and REQ-006-lite (sub-items inside the run, no new spec
registry). Stubs behind a flag (REQ-004), the escalation journal (REQ-007/008) and the cascade stop
(REQ-010) stay in the full spec.
