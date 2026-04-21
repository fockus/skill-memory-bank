# Memory Bank — planning and verification

Rules for plan creation and the verification process through Plan Verifier.

---

## Plan creation rules

Plan creation belongs to the **main agent** (not MB Manager).

### Steps

1. Create the file: `bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"`. Types: `feature`, `fix`, `refactor`, `experiment`.
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

The `mb-plan.sh` template automatically adds `<!-- mb-stage:N -->` before `### Stage N: <name>`. Those markers are used by `mb-plan-sync.sh` and `mb-plan-done.sh` for automatic synchronization with `checklist.md` and `plan.md`.

### Consistency — REQUIRED when creating a plan

After creating a plan, run:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-sync.sh <path-to-plan>
```

The script idempotently:
- adds missing `## Stage N: <name>` sections to `checklist.md`
- updates the `<!-- mb-active-plan -->` block in `plan.md`

### Source-of-truth chain

```text
plan.md (Active plan → link) → plans/<file>.md (tasks, DoD) → checklist.md (tracking) → STATUS.md (phase)
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
2. Plan Verifier rereads the plan, checks `git diff`, and finds gaps.
3. Fix all CRITICAL issues.
4. WARNING issues are discretionary — ask the user.
5. Only then run `/mb done`.

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
