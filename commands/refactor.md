# ~/.claude/commands/refactor.md

---

## description: Refactor the specified module while preserving behavior
allowed-tools: [Bash, Read, Write, Glob, Grep]

Goal: refactor `$ARGUMENTS`

1. Read all module files and related tests
2. Run the existing tests and capture a baseline (everything should pass)
3. Identify violations of `SOLID`, `DRY`, `KISS`, and Clean Architecture
4. Draft a refactoring plan and show it to me
5. After approval, refactor step by step
6. After each step, run tests — everything must still pass
7. If new tests are needed, write them before refactoring
8. Finish with a full test run and compare against the baseline