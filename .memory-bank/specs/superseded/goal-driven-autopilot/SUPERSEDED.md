# SUPERSEDED by `dynamic-flow` (2026-06-09)

**Do NOT implement this spec** (its `tasks.md` checkboxes are all `[ ]` — ignore them). Kept for design history only.

This spec proposed a single `--autopilot` loop on `/mb work`. That loop was **replaced** by the route-picking Dynamic Flow Router
(goal → choose route → run skills → verify → adapt → finish only on green deterministic checks). See `../../dynamic-flow/`.

**What survived (lifted into dynamic-flow):** the `goal.md` / `project.md` artifact shapes (end-state + computed-% acceptance),
the repair-loop idea, and the collision-waves concept (now an optional host-native template). **What changed:** the autopilot
loop → the Router; the LLM-only completion check → a deterministic firewall (`mb-flow-verify.sh`).
