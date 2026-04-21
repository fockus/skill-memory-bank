---
description: Full review of uncommitted code — principles, architecture, tests, security
allowed-tools: [Read, Glob, Grep, Bash, Write]
---

# Code Review — uncommitted code

## 1. Gather context

Run:
```bash
git diff --staged --name-only
git diff --name-only
git diff
git diff --staged
```

If `./.memory-bank/plan.md` or `./.memory-bank/checklist.md` exists, read it. That is the current work plan — compare the implementation against it.

If `./.memory-bank/codebase/ARCHITECTURE.md` and `./.memory-bank/codebase/CONCERNS.md` exist, read them too — `ARCHITECTURE.md` grounds the architectural analysis in Section 3, `CONCERNS.md` tells you which known-fragile areas deserve extra scrutiny when touched.

Read every changed file in full, not just the diff — you need full context for architectural analysis.

## 2. Principles + architecture — delegated to `mb-rules-enforcer`

Do NOT inline SOLID / Clean Architecture / TDD-delta checks here. Delegate to the dedicated subagent, which returns a structured JSON report + human summary:

```
Agent(
  subagent_type="general-purpose",
  model="sonnet",
  description="mb-rules-enforcer: principles + architecture audit",
  prompt="<contents of ~/.claude/skills/memory-bank/agents/mb-rules-enforcer.md>

files: <comma-separated list from step 1 (git diff --name-only)>
diff_range: HEAD...HEAD
rules_path: .memory-bank/RULES.md"
)
```

The enforcer runs `scripts/mb-rules-check.sh` (deterministic SRP / Clean Arch / TDD-delta) and adds LLM-level judgment for ISP / DRY. Parse its JSON for the Report in step 8 — every `CRITICAL` violation becomes a Critical item, every `WARNING` a Serious item.

Apply the remaining judgment-only checks inline:

- **KISS** — overcomplicated solutions, needless abstractions
- **YAGNI** — code written "for the future" with no present call site

These are intentionally not deterministic; the enforcer cannot replace a careful human look at "is this code simpler than it needs to be?"

## 3. Implementation correctness

- Does the code do what the diff/commit claims?
- Is there dead or unreachable code?
- Are there unfinished `TODO`, `FIXME`, `HACK`, stubs, or placeholders?
- Error handling: are all exceptional paths covered?
- Edge cases: empty values, `nil`/`None`, empty collections, boundary numbers
- Race conditions in async code

## 4. Plan alignment

If `./.memory-bank/plan.md` or `./.memory-bank/checklist.md` is found:
- Which plan items are implemented in these changes?
- Which plan items are NOT implemented even though they should be?
- Is there any code that was not part of the plan (scope creep)?

If there is no plan, skip this section.

## 5. Security

- Hardcoded secrets, tokens, passwords, keys
- SQL injection, XSS, CSRF — if applicable
- Unsafe deserialization or `eval`
- Logging of sensitive data
- Excessive permissions, missing input validation
- Dependencies with known vulnerabilities (if they can be checked)

## 6. Tests

Run:
```bash
# Find test files related to the changed files
# Adapt commands to the project stack (pytest, jest, go test, etc.)
```

Check:
- Are there unit tests for every changed module?
- Do tests cover the main scenarios and edge cases?
- Are there integration tests for component interactions?
- Are there e2e tests for affected user scenarios?

Run tests and record the result:
```bash
# Run the project's test suite
# Show a summary: passed / failed / skipped
```

## 7. Report

Write the report in the format below. For each finding, include the file, line, and a concrete recommendation.

```markdown
# Code Review Report
Date: YYYY-MM-DD HH:MM
Files reviewed: N
Lines changed: +N / -N

## Critical
<!-- Merge blockers: bugs, vulnerabilities, broken tests -->

## Serious
<!-- SOLID / Clean Architecture violations, significant architecture issues -->

## Notes
<!-- DRY / KISS / YAGNI, style, smaller improvements -->

## Tests
- Unit: ✅/❌ (passed/total)
- Integration: ✅/❌/⚠️ missing
- E2E: ✅/❌/⚠️ missing
- Uncovered modules: [list]

## Plan alignment
- Implemented: [items]
- Not implemented: [items]
- Outside the plan: [items]

## Summary
<!-- 1-3 sentences: overall assessment, top risk, recommendation (merge / revise) -->
```

If `./.memory-bank/` exists, save the report to `./.memory-bank/reports/YYYY-MM-DD_review_<short-description>.md`.
