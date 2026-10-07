# Key rules onboarding — manual install.sh run on a TTY (temp HOME)

Date: 2026-10-07. Plan: plans/2026-10-06_feature_key-rules-onboarding.md, Stage 4.

Command (macOS script(1) pseudo-terminal, HOME=/tmp/krman/home, stdin kept open until exit):

```
printf '23 3
19

prefer composition over inheritance
ADR for every new module

' | MB_USER_RULES_AUTO_PROMPT=off script -q /dev/null bash install.sh --clients claude-code --language en
rc=0
```

Answers: toggle 23 (testing-trophy off) and 3 (kiss — locked, refused), toggle 19 (mobile-udf on), Enter; two own rules, empty line.

## Installer output (Key rules step)

```
Key rules — injected at the top of CLAUDE.md / AGENTS.md; [*] = always on.
Principles
  [*]  1. solid — SOLID: SRP — >300 lines or >3 unrelated public methods = split; ISP ≤5 methods; DIP — constructors take abstractions
  [*]  2. dry — DRY: the same logic in 3+ places → extract; three identical lines beat a premature abstraction
  [*]  3. kiss — KISS: the simplest working solution wins
  [*]  4. yagni — YAGNI: no code, flags or config for imagined needs
  [*]  5. fail-fast — Fail Fast: ask only when readings of the task lead to materially different work; else decide and state the assumption
  [*]  6. no-placeholders — No placeholders: no TODO, `...` or pseudocode; code is copy-paste ready (stubs only behind a feature flag)
  [*]  7. root-cause — Fix the root cause, not the symptom: check every caller and fix once in the shared path
Minimal code & comments
  [x]  8. ladder — Before writing code: does it need to exist → already in the codebase → stdlib → native platform → installed dependency → one line → minimal code
  [x]  9. no-unrequested-abstractions — No unrequested abstractions: no single-implementation interface, one-product factory or config for a constant
  [x] 10. deletion-over-addition — Deletion over addition, boring over clever
  [x] 11. shortest-diff — Shortest working diff wins — but only after you understand the problem and the code it touches
  [x] 12. comments-why-only — Comments only for the non-obvious why; never restate the code
  [x] 13. ponytail-marker — Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and upgrade path
  [x] 14. never-simplify-safety — Never simplify away trust-boundary validation, security, or error handling that prevents data loss
  [x] 15. one-runnable-check — Non-trivial logic (branch, loop, parser, money/security path) leaves one runnable check behind
Architecture
  [x] 16. clean-architecture — Clean Architecture: Infrastructure → Application → Domain, never backward; Domain has 0 external dependencies
  [x] 17. fsd — FSD (frontend): app → pages → widgets → features → entities → shared; imports only downward; slice public API via index.ts
  [x] 18. ddd-folders — DDD folders: group modules by bounded context in every layer; no flat dump, no single-file folders
  [ ] 19. mobile-udf — Mobile: UDF + Clean layers View → ViewModel → UseCase → Repository (SSOT) → DataSource; immutable UI state
  [ ] 20. backend-macro — Backend macro-architecture: pick one — serverless, microservices or modular monolith (modules talk only via shared contracts)
Tests
  [x] 21. tdd — TDD: new logic → failing test first, then code (skip only typos, formatting, exploratory prototypes)
  [x] 22. contract-first — Contract-First: Protocol/ABC → contract tests → implementation; tests pass for ANY correct implementation
  [x] 23. testing-trophy — Testing Trophy: integration > unit > e2e; mock only external boundaries; >5 mocks → integration test
  [x] 24. test-behavior — Tests check behavior, not lines: test_<what>_<condition>_<result>, AAA; no mock-tests of glue, config or external SDK calls
  [ ] 25. coverage — Coverage: overall 85%+, core/business 95%+, infrastructure 70%+
Process
  [*] 26. effort-tiers — Size the task first (trivial/small/standard/large/extra); plan, tests, docs and checks follow the tier — SKILL.md § Task routing
  [x] 27. targeted-verification — Evidence before "done": targeted tests + lint of changed files while working; full suite in /mb verify and before commit; don't re-run what was shown
  [x] 28. docs-minimal — No new documents unless asked; README/CHANGELOG get 1–2 lines
  [x] 29. protected-files — Protected files (.env, CI, Docker/K8s/Terraform) — touch only on explicit request
  [x] 30. scoped-git — Scoped `git add` only; no destructive git (reset --hard, force-push, mass delete) without an explicit request
  [x] 31. no-scope-creep — Do not expand scope without a request; report unrelated findings as follow-ups
  [x] 32. static-analysis — Static analysis (lint, type checks) — always
Your rules (user scope)
  (none)
Type numbers to toggle (e.g. "9 25"), Enter to accept.
>   ! locked rule 'kiss' cannot be disabled
Principles
  [*]  1. solid — SOLID: SRP — >300 lines or >3 unrelated public methods = split; ISP ≤5 methods; DIP — constructors take abstractions
  [*]  2. dry — DRY: the same logic in 3+ places → extract; three identical lines beat a premature abstraction
  [*]  3. kiss — KISS: the simplest working solution wins
  [*]  4. yagni — YAGNI: no code, flags or config for imagined needs
  [*]  5. fail-fast — Fail Fast: ask only when readings of the task lead to materially different work; else decide and state the assumption
  [*]  6. no-placeholders — No placeholders: no TODO, `...` or pseudocode; code is copy-paste ready (stubs only behind a feature flag)
  [*]  7. root-cause — Fix the root cause, not the symptom: check every caller and fix once in the shared path
Minimal code & comments
  [x]  8. ladder — Before writing code: does it need to exist → already in the codebase → stdlib → native platform → installed dependency → one line → minimal code
  [x]  9. no-unrequested-abstractions — No unrequested abstractions: no single-implementation interface, one-product factory or config for a constant
  [x] 10. deletion-over-addition — Deletion over addition, boring over clever
  [x] 11. shortest-diff — Shortest working diff wins — but only after you understand the problem and the code it touches
  [x] 12. comments-why-only — Comments only for the non-obvious why; never restate the code
  [x] 13. ponytail-marker — Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and upgrade path
  [x] 14. never-simplify-safety — Never simplify away trust-boundary validation, security, or error handling that prevents data loss
  [x] 15. one-runnable-check — Non-trivial logic (branch, loop, parser, money/security path) leaves one runnable check behind
Architecture
  [x] 16. clean-architecture — Clean Architecture: Infrastructure → Application → Domain, never backward; Domain has 0 external dependencies
  [x] 17. fsd — FSD (frontend): app → pages → widgets → features → entities → shared; imports only downward; slice public API via index.ts
  [x] 18. ddd-folders — DDD folders: group modules by bounded context in every layer; no flat dump, no single-file folders
  [ ] 19. mobile-udf — Mobile: UDF + Clean layers View → ViewModel → UseCase → Repository (SSOT) → DataSource; immutable UI state
  [ ] 20. backend-macro — Backend macro-architecture: pick one — serverless, microservices or modular monolith (modules talk only via shared contracts)
Tests
  [x] 21. tdd — TDD: new logic → failing test first, then code (skip only typos, formatting, exploratory prototypes)
  [x] 22. contract-first — Contract-First: Protocol/ABC → contract tests → implementation; tests pass for ANY correct implementation
  [ ] 23. testing-trophy — Testing Trophy: integration > unit > e2e; mock only external boundaries; >5 mocks → integration test
  [x] 24. test-behavior — Tests check behavior, not lines: test_<what>_<condition>_<result>, AAA; no mock-tests of glue, config or external SDK calls
  [ ] 25. coverage — Coverage: overall 85%+, core/business 95%+, infrastructure 70%+
Process
  [*] 26. effort-tiers — Size the task first (trivial/small/standard/large/extra); plan, tests, docs and checks follow the tier — SKILL.md § Task routing
  [x] 27. targeted-verification — Evidence before "done": targeted tests + lint of changed files while working; full suite in /mb verify and before commit; don't re-run what was shown
  [x] 28. docs-minimal — No new documents unless asked; README/CHANGELOG get 1–2 lines
  [x] 29. protected-files — Protected files (.env, CI, Docker/K8s/Terraform) — touch only on explicit request
  [x] 30. scoped-git — Scoped `git add` only; no destructive git (reset --hard, force-push, mass delete) without an explicit request
  [x] 31. no-scope-creep — Do not expand scope without a request; report unrelated findings as follow-ups
  [x] 32. static-analysis — Static analysis (lint, type checks) — always
Your rules (user scope)
  (none)
Type numbers to toggle (e.g. "9 25"), Enter to accept.
> Principles
  [*]  1. solid — SOLID: SRP — >300 lines or >3 unrelated public methods = split; ISP ≤5 methods; DIP — constructors take abstractions
  [*]  2. dry — DRY: the same logic in 3+ places → extract; three identical lines beat a premature abstraction
  [*]  3. kiss — KISS: the simplest working solution wins
  [*]  4. yagni — YAGNI: no code, flags or config for imagined needs
  [*]  5. fail-fast — Fail Fast: ask only when readings of the task lead to materially different work; else decide and state the assumption
  [*]  6. no-placeholders — No placeholders: no TODO, `...` or pseudocode; code is copy-paste ready (stubs only behind a feature flag)
  [*]  7. root-cause — Fix the root cause, not the symptom: check every caller and fix once in the shared path
Minimal code & comments
  [x]  8. ladder — Before writing code: does it need to exist → already in the codebase → stdlib → native platform → installed dependency → one line → minimal code
  [x]  9. no-unrequested-abstractions — No unrequested abstractions: no single-implementation interface, one-product factory or config for a constant
  [x] 10. deletion-over-addition — Deletion over addition, boring over clever
  [x] 11. shortest-diff — Shortest working diff wins — but only after you understand the problem and the code it touches
  [x] 12. comments-why-only — Comments only for the non-obvious why; never restate the code
  [x] 13. ponytail-marker — Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and upgrade path
  [x] 14. never-simplify-safety — Never simplify away trust-boundary validation, security, or error handling that prevents data loss
  [x] 15. one-runnable-check — Non-trivial logic (branch, loop, parser, money/security path) leaves one runnable check behind
Architecture
  [x] 16. clean-architecture — Clean Architecture: Infrastructure → Application → Domain, never backward; Domain has 0 external dependencies
  [x] 17. fsd — FSD (frontend): app → pages → widgets → features → entities → shared; imports only downward; slice public API via index.ts
  [x] 18. ddd-folders — DDD folders: group modules by bounded context in every layer; no flat dump, no single-file folders
  [x] 19. mobile-udf — Mobile: UDF + Clean layers View → ViewModel → UseCase → Repository (SSOT) → DataSource; immutable UI state
  [ ] 20. backend-macro — Backend macro-architecture: pick one — serverless, microservices or modular monolith (modules talk only via shared contracts)
Tests
  [x] 21. tdd — TDD: new logic → failing test first, then code (skip only typos, formatting, exploratory prototypes)
  [x] 22. contract-first — Contract-First: Protocol/ABC → contract tests → implementation; tests pass for ANY correct implementation
  [ ] 23. testing-trophy — Testing Trophy: integration > unit > e2e; mock only external boundaries; >5 mocks → integration test
  [x] 24. test-behavior — Tests check behavior, not lines: test_<what>_<condition>_<result>, AAA; no mock-tests of glue, config or external SDK calls
  [ ] 25. coverage — Coverage: overall 85%+, core/business 95%+, infrastructure 70%+
Process
  [*] 26. effort-tiers — Size the task first (trivial/small/standard/large/extra); plan, tests, docs and checks follow the tier — SKILL.md § Task routing
  [x] 27. targeted-verification — Evidence before "done": targeted tests + lint of changed files while working; full suite in /mb verify and before commit; don't re-run what was shown
  [x] 28. docs-minimal — No new documents unless asked; README/CHANGELOG get 1–2 lines
  [x] 29. protected-files — Protected files (.env, CI, Docker/K8s/Terraform) — touch only on explicit request
  [x] 30. scoped-git — Scoped `git add` only; no destructive git (reset --hard, force-push, mass delete) without an explicit request
  [x] 31. no-scope-creep — Do not expand scope without a request; report unrelated findings as follow-ups
  [x] 32. static-analysis — Static analysis (lint, type checks) — always
Your rules (user scope)
  (none)
Type numbers to toggle (e.g. "9 25"), Enter to accept.
> 
Your own rules (architecture, process, anything) — one per line, empty line to finish.
> > > 
merged /tmp/krman/home/.claude/CLAUDE.md
merged /tmp/krman/home/.codex/AGENTS.md
merged /tmp/krman/home/.pi/agent/AGENTS.md
merged /tmp/krman/home/.config/opencode/AGENTS.md
merged /tmp/krman/home/.cursor/AGENTS.md
  ✓ Key rules (/mb rules to change)
```

## Resulting ~/.claude/CLAUDE.md (head)

```markdown
<!-- mb-key-rules:start -->
## Key rules

- SOLID: SRP — >300 lines or >3 unrelated public methods = split; ISP ≤5 methods; DIP — constructors take abstractions
- DRY: the same logic in 3+ places → extract; three identical lines beat a premature abstraction
- KISS: the simplest working solution wins
- YAGNI: no code, flags or config for imagined needs
- Fail Fast: ask only when readings of the task lead to materially different work; else decide and state the assumption
- No placeholders: no TODO, `...` or pseudocode; code is copy-paste ready (stubs only behind a feature flag)
- Fix the root cause, not the symptom: check every caller and fix once in the shared path
- Before writing code: does it need to exist → already in the codebase → stdlib → native platform → installed dependency → one line → minimal code
- No unrequested abstractions: no single-implementation interface, one-product factory or config for a constant
- Deletion over addition, boring over clever
- Shortest working diff wins — but only after you understand the problem and the code it touches
- Comments only for the non-obvious why; never restate the code
- Mark a deliberate shortcut with a `ponytail:` comment naming its ceiling and upgrade path
- Never simplify away trust-boundary validation, security, or error handling that prevents data loss
- Non-trivial logic (branch, loop, parser, money/security path) leaves one runnable check behind
- Clean Architecture: Infrastructure → Application → Domain, never backward; Domain has 0 external dependencies
- FSD (frontend): app → pages → widgets → features → entities → shared; imports only downward; slice public API via index.ts
- DDD folders: group modules by bounded context in every layer; no flat dump, no single-file folders
- Mobile: UDF + Clean layers View → ViewModel → UseCase → Repository (SSOT) → DataSource; immutable UI state
- TDD: new logic → failing test first, then code (skip only typos, formatting, exploratory prototypes)
- Contract-First: Protocol/ABC → contract tests → implementation; tests pass for ANY correct implementation
- Tests check behavior, not lines: test_<what>_<condition>_<result>, AAA; no mock-tests of glue, config or external SDK calls
- Size the task first (trivial/small/standard/large/extra); plan, tests, docs and checks follow the tier — SKILL.md § Task routing
- Evidence before "done": targeted tests + lint of changed files while working; full suite in /mb verify and before commit; don't re-run what was shown
- No new documents unless asked; README/CHANGELOG get 1–2 lines
- Protected files (.env, CI, Docker/K8s/Terraform) — touch only on explicit request
- Scoped `git add` only; no destructive git (reset --hard, force-push, mass delete) without an explicit request
- Do not expand scope without a request; report unrelated findings as follow-ups
- Static analysis (lint, type checks) — always
- prefer composition over inheritance (your rule)
- ADR for every new module (your rule)

Details: `~/.claude/RULES.md`.
<!-- mb-key-rules:end -->

# [MEMORY-BANK-SKILL]

```

## User profile

```json
{
  "schema_version": 1,
  "scope": "user",
  "role": "backend",
  "stack": "generic",
  "architecture": "clean",
  "delivery": "tdd",
  "strictness": "warn",
  "key_rules": {
    "enabled": [
      "mobile-udf"
    ],
    "disabled": [
      "testing-trophy"
    ],
    "custom": [
      "prefer composition over inheritance",
      "ADR for every new module"
    ]
  }
}
```
