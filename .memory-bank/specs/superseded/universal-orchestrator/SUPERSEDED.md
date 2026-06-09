# SUPERSEDED by `dynamic-flow` (2026-06-09)

**Do NOT implement this spec.** It is kept for design history only.

This spec proposed a **standalone Python orchestrator** (`mb-pipeline-run.py` runner + `HostAdapter.dispatch` + durable-execution
journal) that would itself drive subagents. That model was **rejected**: the host code-agent is the runtime (agent-native hard
constraint). See `../../dynamic-flow/` and its `design.md` § ADR-1/ADR-2.

**What survived here (as portable CLI primitives in dynamic-flow):** the severity-gate comparator, the deterministic check
runners, the git-fact actualizer (mutate-in-fence / loud-flag-outside), the status-vocab SSOT, and the greedy networkx-free DAG
as an OPTIONAL CLI. **What was killed:** the standalone runner, the `HostAdapter` dispatcher, the durable journal. **Demoted to
optional:** collision-DAG + parallel tracks (now a host-native template/skill), the heartbeat-TTL registry (cron/CI only).
