---
description: Auto-classify the goal + diff scope into one route and write it into the mb-flow fence
allowed-tools: [Bash, Read]
---

# /mb analyze-task

Auto-route the current flow. This is the **default** Dynamic Flow entry point
(REQ-DF-020): read the durable `goal.md` and the `git diff --name-only` scope,
classify a single candidate route from the catalogue, then hand that candidate
to `scripts/mb-flow-route.sh`, which applies the **deterministic route-floor**
(REQ-DF-022) and writes the resolved `route:` into the `<!-- mb-flow -->` fence
in `status.md`.

> Auto-routing is the default. To bypass classification with a fixed route, use
> the explicit escape-hatch `/mb flow <route>` (see `commands/flow.md`). Both
> paths still apply the route-floor and the firewall — the override never wins
> below the floor (REQ-DF-025).

## The route catalogue

Pick exactly ONE candidate (lowest route that genuinely fits the work):

- `research` — investigation/spike; no production code change expected.
- `bugfix` — reproduce → debug → patch a localized defect.
- `code-change` — the dominant case: a feature/change inside existing seams
  (reuses the `work.md` loop, ADR-7). **Default when unsure.**
- `arch` — touches contracts, domain rules, ports/interfaces, or cross-module
  structure. The route-floor can FORCE this regardless of your pick.
- `migration` — schema/data/dependency migration with ordering risk.

## What it does

1. Resolve the active Memory Bank (`scripts/_lib.sh::mb_resolve_path`).
2. Read `.memory-bank/goal.md` (end-state + `## Acceptance criteria`) and the
   changed-file scope from `git diff --name-only` (plus `--cached`).
3. Classify a candidate route from the catalogue above.
4. Call the resolver — it applies the floor and writes the fence:

   ```bash
   SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # memory-bank skill bundle root
   bash "$SKILL_DIR/scripts/mb-flow-route.sh" --candidate <your-pick>
   ```

5. Report the **resolved** route from the JSON the resolver prints
   (`{"candidate":...,"floor":...,"route":...,"floor_triggered":...,"reasons":[...]}`).
   If `floor_triggered` is `true`, say so and name the `reasons` — the floor
   overrode your candidate on purpose.

The resolver derives the changed files from git itself; pass `--changed
"<csv>"` / `--changed-file <f>` only when you need to drive it explicitly (e.g.
a dry run before any edits exist). Add `--dry-run` to preview the route without
touching the fence.

## The deterministic route-floor (REQ-DF-022)

The resolver forces the route to **at least `arch`** — independent of your
classification — when the changed scope touches any of:

- a `domain/` path segment,
- an `application/ports` path,
- an interface / `*Protocol` / `ABC` / contract file,
- a declared `protected_path` (from `pipeline.yaml`),
- a linked plan with `depends_on > 0`.

You cannot route *below* the floor. The floor only ever **raises** a route
(`migration` stays `migration`; `bugfix`/`code-change`/`research` under a
trigger become `arch`).

## Re-routing rules (do NOT advance through these)

- **Red boundary check → re-run analyze-task (REQ-DF-024).** When a
  phase-boundary `scripts/mb-flow-verify.sh` run reports a red `diff_scope`
  breach or unmet `acceptance`, HALT. Surface the breach (name the failing
  check + findings) and **re-run `analyze-task`** to re-classify and rebuild the
  flow — do NOT patch around it or advance to the next phase.
- **Goal changed mid-flight → rewrite goal.md, then re-run (REQ-DF-023).** When
  the user's goal changes, rewrite `goal.md` (durable end-state + acceptance
  criteria) and re-run `analyze-task`. Never do manual plan-file surgery to
  force a route.

## Exit codes (resolver)

- `0` — route resolved (and written to the fence unless `--dry-run`).
- `1` — usage error / unknown route / bad bank (write target missing).
- `2` — internal error (the fence writer failed).
