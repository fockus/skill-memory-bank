# Memory Bank — planning and verification

Rules for plan creation and the verification process through Plan Verifier.

> **Plan hierarchy:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for size thresholds and the canonical decomposition rules.

---

## Plan creation rules

Plan creation belongs to the **main agent** (not MB Manager).

### Steps

1. Create the file: `bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"`. Types: `feature`, `fix`, `refactor`, `experiment`.
   - The scaffold now captures `**Baseline commit:** <git HEAD>` at creation time. `plan-verifier` diff's against this ref instead of `HEAD~N`, so the audit sees exactly what was written against this plan. Outside a git repo → field stores `unknown` and the verifier falls back to ctime lookup.
2. Fill the sections:
   - **Context**: the problem, what triggered the plan, expected outcome.
   - **Stages**: each with SMART DoD (specific, measurable, achievable, realistic, time-bounded).
   - **Testing**: unit + integration tests BEFORE implementation (TDD).
   - **Each stage**: what to test, edge cases, lint requirements.
   - **Code rules**: SOLID, DRY, KISS, YAGNI, Clean Architecture/FSD/Mobile — per `RULES.md`.
   - **Risks**: probability (H/M/L), mitigation.
   - **Gate**: success criterion for the whole plan.
3. Stages must be atomic and dependency-ordered.
4. No placeholders — every step must be concrete.
5. Every `assert` in tests must verify a business requirement or edge case.

### Stage markers

The `mb-plan.sh` template automatically adds `<!-- mb-stage:N -->` before `### Stage N: <name>`. Those markers are used by `mb-plan-sync.sh` and `mb-plan-done.sh` for automatic synchronization with `checklist.md` and `roadmap.md`.

### Consistency — REQUIRED when creating a plan

After creating a plan, run:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-sync.sh <path-to-plan>
```

The script idempotently:
- adds missing `## Stage N: <name>` sections to `checklist.md`
- updates the `<!-- mb-active-plan -->` block in `roadmap.md`

### Source-of-truth chain

```text
roadmap.md (Active plan → link) → plans/<file>.md (tasks, DoD) → checklist.md (tracking) → status.md (phase)
```

**When finishing a plan:**

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-done.sh <path-to-plan>
```

The script moves the file into `plans/done/`, closes `⬜ → ✅`, and clears the active-plan block.

---

## Plan Verifier — plan verification

Plan Verifier is a Sonnet subagent that checks code against the plan. Prompt: `agents/plan-verifier.md`.

### When to run it

**REQUIRED** before closing a plan (`/mb done` when the session followed a plan):

1. Run `/mb verify`.
2. Plan Verifier rereads the plan, resolves the diff base from `**Baseline commit:**`, and finds gaps.
3. Fix all CRITICAL issues.
4. WARNING issues are discretionary — ask the user.
5. Only then run `/mb done`.

### What it checks (v3.2+)

| Step | Check | Source |
|------|-------|--------|
| 2 | `git diff <Baseline commit>...HEAD` (with ctime / `HEAD~10` fallback) | Plan header |
| 3 | DoD items against real code (file existence, tests, lint, no TODO/FIXME/placeholder) | Plan stages |
| 3.5 | `bash mb-metrics.sh --run` → `test_status=pass\|fail` + coverage when exposed | Live execution |
| 3.6 | RULES.md enforcement (SRP ≥300 lines, Clean Arch direction, TDD delta, ISP, DRY) | `.memory-bank/RULES.md` → `~/.claude/RULES.md` |
| 4 | Categorize findings into CRITICAL / WARNING / INFO | Step 3 + 3.5 + 3.6 output |
| 5 | Produce structured report with `Tests run:` and `RULES violations:` rows | — |

### Invocation format

```text
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="Plan Verifier: plan verification",
  prompt="<contents of agents/plan-verifier.md>\n\nPlan file: <path>\n\nContext: <what was done>"
)
```

### Issue categories

| Category | Meaning | Action |
|----------|---------|--------|
| CRITICAL | Stage not implemented, DoD not met, tests missing | Must fix |
| WARNING | Partial coverage, deviation from the plan | Ask the user |
| INFO | Additional work outside the plan | Record for awareness |
