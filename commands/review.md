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

Read every changed file in full, not just the diff — you need full context for architectural analysis.

## 2. Principles analysis

### SOLID
- **S** — Are there classes/functions with multiple responsibility areas?
- **O** — Are there changes that force modifications to existing code instead of extension?
- **L** — Is substitutability broken in inheritance hierarchies?
- **I** — Are there bloated interfaces that should be split?
- **D** — Are there direct dependencies on concrete implementations instead of abstractions?

### DRY
- Logic duplicated across changed files or against existing project code
- Copy-paste that should be extracted into a shared function/utility

### KISS
- Overcomplicated solutions that can be simplified
- Extra abstractions without real need

### YAGNI
- Code written “for the future” without a present need

## 3. Clean Architecture

- Correct dependency direction (outer layers → inner layers, not the other way around)
- Business logic does not contain infrastructure details (DB, HTTP, frameworks)
- Use cases / services do not depend directly on concrete repositories
- No leakage of domain objects into the presentation layer and vice versa
- Layer boundaries are clear, with no “through-layer” imports

## 4. Implementation correctness

- Does the code do what the diff/commit claims?
- Is there dead or unreachable code?
- Are there unfinished `TODO`, `FIXME`, `HACK`, stubs, or placeholders?
- Error handling: are all exceptional paths covered?
- Edge cases: empty values, `nil`/`None`, empty collections, boundary numbers
- Race conditions in async code

## 5. Plan alignment

If `./.memory-bank/plan.md` or `./.memory-bank/checklist.md` is found:
- Which plan items are implemented in these changes?
- Which plan items are NOT implemented even though they should be?
- Is there any code that was not part of the plan (scope creep)?

If there is no plan, skip this section.

## 6. Security

- Hardcoded secrets, tokens, passwords, keys
- SQL injection, XSS, CSRF — if applicable
- Unsafe deserialization or `eval`
- Logging of sensitive data
- Excessive permissions, missing input validation
- Dependencies with known vulnerabilities (if they can be checked)

## 7. Tests

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

## 8. Report

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
