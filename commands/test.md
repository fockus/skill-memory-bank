---
description: Run tests, analyze failures, and propose fixes
allowed-tools: [Bash, Read, Glob, Grep]
argument-hint: [test-filter]
---

## 1. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
# Exposes: stack, test_cmd (e.g., "go test ./..." / "pytest -q" / "npm test"), lint_cmd, src_count
```

If `stack=unknown` or `test_cmd` is empty, ask the user for the test runner (or suggest creating `.memory-bank/metrics.sh` with a custom override — see `references/templates.md`).

## 2. Run the tests

Use `$test_cmd` — narrowed by `$ARGUMENTS` when provided (file path, test name, marker, or tag). Known runners:

- Go: `go test ./... -run "<pattern>"` / `-race`
- Python: `pytest` (+ `-k "<pattern>"` / `-m "<marker>"`)
- Node.js: `npm test` / `vitest` / `jest --testNamePattern "<pattern>"`
- Rust: `cargo test "<pattern>"` (+ `--release` / `--doc`)
- Java: `mvn test -Dtest=<Class>#<method>` / `gradle test --tests "<pattern>"`
- Ruby: `rspec` / `bundle exec rspec` / `rake test`
- .NET: `dotnet test --filter "<expression>"`

## 3. If tests pass

Show a summary (counts, durations, coverage if the runner supports it).

## 4. If tests fail

- List failing tests with the first-line failure message
- Read the failing test source and the code under test in full
- Check `.memory-bank/lessons.md` for known flaky patterns or recurring anti-patterns
- Classify: code bug vs. outdated test vs. environmental (flaky) issue
- Propose a concrete fix — show the diff
- Ask `y/N` before applying the fix (default = No)

## 5. Memory Bank

If the run surfaced a recurring pattern worth remembering (flakiness, shared setup bug, environment issue), append to `lessons.md` using the template in `references/templates.md`.
