---
id: G-001
status: active
mode: static
progress_source: checklist
progress_target: 100
replan_with: ""
linked_plans: []
---

<!--
Durable goal artifact (DURABLE-ONLY — no live check-results, no route/phase).
Per ADR-5, the ephemeral flow-state (route, current_phase, check-results, gate)
lives in the `<!-- mb-flow -->` fence inside status.md, NOT here. The acceptance
aggregator greps THIS file for `- [x]/N` without fence noise.

Frontmatter fields:
  id              Stable goal id (G-NNN). Monotonic; never reused.
  status          active | done | abandoned.
  mode            static | adaptive.
                  - static  (default): today's Memory Bank flow, byte-identical.
                            Omitting `mode`, `replan_with`, `linked_plans`
                            implies NO behaviour change (REQ-DF-005).
                  - adaptive: the Router may re-pick a route mid-flight; REQUIRES
                            `replan_with` (REQ-DF-004).
  progress_source Where goal progress is COMPUTED at read-time (never a stored
                  stale percentage; REQ-DF-003). One of:
                    checklist     — % from checklist.md ✅/⬜
                    plan-stages   — % from the linked plan's stage markers
                                    (needs `linked_plan:`)
                    spec-tasks    — % from the linked spec's <!-- mb-task:N -->
                                    (needs `linked_spec:`)
                    tests         — % from passing tests (mb-test-run.sh)
                    req-trace     — % from traceability.md REQ coverage
                    composite     — weighted blend of the above
  progress_target Numeric completion target (default 100).
  replan_with     Skill the Router re-runs when adaptive (e.g. analyze-task).
                  Required ONLY when `mode: adaptive`. Leave "" for static goals.
  linked_plans    Plans this goal drives (adaptive routing); [] for static.

Body is the durable contract: end-state + the deterministic termination
condition. The `## Acceptance criteria` `- [ ]` list IS that condition
(REQ-DF-001) — the goal is "done" only when every item is `- [x]` AND the
deterministic firewall (mb-flow-verify.sh) exits 0.
-->

# Goal: <title>

## Description

<3-5 sentences describing the END-STATE this goal delivers — what is true when
the goal is complete, not the steps to get there.>

## Acceptance criteria

- [ ] <concrete, checkable criterion 1 (the termination condition)>
- [ ] <concrete, checkable criterion 2>
