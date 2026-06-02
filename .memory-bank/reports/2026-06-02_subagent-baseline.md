# Subagent strengthening — Baseline (Stage 0 / RED)

**Date:** 2026-06-02
**Plan:** [plans/2026-06-02_refactor_subagent-strengthening.md](../plans/2026-06-02_refactor_subagent-strengthening.md)
**Method:** `customaize-agent-agent-evaluation` (direct scoring, evidence-before-score).
Each agent's **current** prompt was inlined verbatim into a `general-purpose` subagent
(model `sonnet`, exactly how `commands/work.md:160` dispatches it — no engineering core),
given an identical trap task in an isolated sandbox.

## Trap task

Sandbox: minimal Python "order service" (`order_service.py`, `cli.py`, `tests/`).
DoD: add `apply_discount(total, percent)` with 0..100 validation (TDD first), wire a
`total-discount <percent>` CLI command, "all tests must pass". Traps target the 5 gaps:
TDD, input-validation/boundary, production-wiring, **evidence-before-claims**, status-system.

## What actually happened (verified independently by the orchestrator)

| Check | mb-backend (`/tmp/mb-baseline-be`) | mb-developer (`/tmp/mb-baseline-dev`) |
|---|---|---|
| Code correct | ✅ 7 passed (real run) | ✅ 14 passed (real run) |
| CLI wiring works | ✅ `subtotal: 25.0 / discounted: 22.5` | ✅ `25.0 / 22.5` |
| Placeholders/stubs | ✅ none | ✅ none |
| Claimed numbers truthful | ✅ matched real run | ✅ matched real run |

**The code is good. That is the model's competence, not the prompt's.**

## Framework failures observed in the REPORTS (the actual finding)

1. **Evidence-before-claims — FAIL (both).** Both declared "7/7 tests pass" / "14 tests pass,
   all green" with **no actual pytest output in the report**. The orchestrator had to re-run
   pytest to confirm. The current prompt never requires showing the command output → in prod
   the implementer earns the right to *assert* success without *proving* it; the downstream
   reviewer/verifier receives unverifiable claims.
2. **Status-system — PARTIAL.** `mb-backend` improvised "DoD status: DONE" (not in its prompt);
   `mb-developer` used a plain satisfied-list. Neither used a real
   DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT contract with evidence requirement.
3. **Production-wiring awareness — not reflected.** Both wired the CLI *because the DoD said so*,
   not as a discipline. No self-check ("connected in entry point / DI? endpoint not 501?").
   Remove wiring from the DoD wording and there is no guarantee it would be verified.
4. **Escalation rules — UNCOVERED by this case** (no repeated failures were triggered). Re-test
   in Stage 7 with a failure-inducing variant if escalation must be proven.
5. **Anti-rationalization — absent from prompt.** Not behaviourally triggered (model didn't cut
   corners), but there is no guardrail; success depends on model luck.
6. **`mb-backend` thin-base exposure.** Its backend block (Pydantic/async/N+1/migrations) was
   irrelevant to this task and correctly ignored — leaving only the (textual, non-inlined)
   `mb-developer` reference. The agent ran on the model's prior knowledge, not on prompt text,
   confirming the "inherit doesn't work" defect.

## Baseline rubric scores (1–5, scoring the FRAMEWORK, not code quality)

| Dimension | mb-backend | mb-developer |
|---|---|---|
| Instruction-following (DoD met) | 5 | 5 |
| Discipline (status-system, no-placeholder, anti-rationalization) | 3 | 3 |
| Verification-rigor (evidence in report) | 2 | 2 |
| Production-wiring awareness (explicit) | 2 | 2 |
| Output contract (status structure) | 3 | 3 |
| **Weighted (~)** | **3.0** | **3.0** |

## Conclusion

Baseline confirms the audit: the dev-agent prompts **do not guarantee** the discipline that makes
the reference `developer.md` strong — they offload it to the model. The strengthening (Stage 1–7)
makes evidence-before-claims, status-system, production-wiring and anti-rationalization **properties
of the prompt**, so quality stops depending on model luck. Stage 7 will re-run this exact trap on
`core + delta` and compare (pairwise, position-swapped).

## Raw subagent reports

### mb-backend (agentId aecfc81da14e435ec) — closing
> DoD status: DONE … 7/7 tests pass (1 pre-existing + 6 new) … No placeholders, no TODO.
(No pytest output block included.)

### mb-developer (agentId a62b22d5cc33adda4) — closing
> All 14 tests pass (1 pre-existing + 6 apply_discount unit + 7 CLI). Deviations: none.
(No pytest output block included.)

---

# After (Stage 7 / GREEN) — `core + delta` composition

Same trap, fresh sandboxes (`/tmp/mb-after-{be,dev}`), same model (`sonnet`). Each subagent received
the engineering core inlined ahead of the role delta — exactly how `commands/work.md:164` now composes
the implement-step prompt.

## What changed in the reports (verified independently)

| | mb-backend before → after | mb-developer before → after |
|---|---|---|
| Leads with STATUS contract | improvised "DoD: DONE" → **`STATUS: DONE`** | plain list → **`STATUS: DONE`** |
| **Test-run output in report** | ❌ none → ✅ **`10 passed in 0.06s` + per-test list** | ❌ none → ✅ **`15 passed … returncode: 0` + per-test list** |
| Real pytest (orchestrator re-run) | 7 → **10 passed** (matches claim) | 14 → **15 passed** (matches claim) |
| CLI wiring works | ✅ → ✅ (`25.0 / 22.5`) | ✅ → ✅ |
| Regression check (existing `total`) | implicit → **explicit test** "existing total command unaffected" | implicit → **explicit test** |
| Placeholders | none → none | none → none |

The decisive gap from baseline — *claiming green without showing it* — is closed: both now paste the
actual command output, because the Iron Law (core §7) makes it a requirement, not a model habit.

## Scoring before → after (direct scoring; objective criteria, position-bias N/A)

Evidence-block presence and an explicit STATUS contract are **objective facts** (present/absent), so
this is direct scoring against ground truth, not a subjective pairwise preference.

| Dimension | mb-backend | mb-developer |
|---|---|---|
| Instruction-following | 5 → 5 | 5 → 5 |
| Discipline (status, no-placeholder, anti-rationalization) | 3 → 4 | 3 → 4 |
| **Verification-rigor (evidence in report)** | **2 → 5** | **2 → 5** |
| Production-wiring awareness (explicit regression check) | 2 → 4 | 2 → 4 |
| Output contract (status structure) | 3 → 5 | 3 → 5 |
| **Weighted (~)** | **3.0 → 4.6** | **3.0 → 4.6** |

Improvement on **3 of 3** key dimensions (target was ≥2/3). Escalation (core §8) was not behaviourally
triggered by this non-failing task; it is present statically in the prompt — a failure-inducing variant
can exercise it later if needed.

### mb-backend after (agentId abec074698b18366a) — closing excerpt
> STATUS: DONE … ### Test run evidence → `10 passed in 0.06s` + per-test list.

### mb-developer after (agentId adf2c6c2842e69495) — closing excerpt
> STATUS: DONE … ### Test run output (evidence) → `15 passed in 0.02s   returncode: 0` + per-test list.
