# Superseded plans — do NOT implement

These plan files are archived. They are kept on disk for traceability only and are
excluded from the active roadmap (the roadmap auto-sync globs `plans/*.md` non-recursively,
so this subdirectory is invisible to it).

## goal-driven-autopilot — phase plan + 7 sprints

Superseded by **`specs/dynamic-flow/`** (commit `c4c6740`, 2026-06-09).

The parent spec `specs/goal-driven-autopilot/` was moved to `specs/superseded/` and replaced
by the route-picking **Dynamic Flow Router** + a *deterministic* completion firewall
(`mb-flow-verify.sh`). The surviving ideas (the `goal.md`/`project.md` artifact shapes, the
repair loop, the collision-waves concept) live on inside `dynamic-flow`; the LLM-only autopilot
loop and LLM-only "done" check these plans specified were deliberately rejected in favour of the
deterministic gate. Implement `specs/dynamic-flow/` instead.

- `2026-05-23_feature_goal-driven-autopilot-phase.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-1-prompt-overlay.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-2-mb-debugger.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-3-worktree.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-4-atomic-commit.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-5-parallel-waves.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-6-goal-layer.md`
- `2026-05-23_feature_goal-driven-autopilot-sprint-7-autopilot.md`

## opencode-first-adaptation

Superseded by the **`adapters/` layer** (commits `8dcb26a`, `f359b42`, `d3c712a`).

OpenCode host parity was delivered through `adapters/opencode.sh` + `adapters/_lib_agents_md.sh`
(plus cursor/codex/pi/cline/kilo/windsurf), not through this plan's central
`scripts/mb-dispatch.sh` design (which never shipped). Any genuinely-missing residual (a native
OpenCode *plugin* package, provider-neutral `fast/balanced/powerful` aliases) should be filed as a
fresh backlog item after diffing against `adapters/` — not revived from this plan.

- `2026-05-24_feature_opencode-first-adaptation.md`
