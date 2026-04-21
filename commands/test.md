# ~/.claude/commands/test.md

---

## description: Run tests, analyze failures, and propose fixes

allowed-tools: [Bash, Read, Glob, Grep]

1. Detect the project's test framework (`go test`, `pytest`, `jest`, etc.)
2. Run the full test suite: use `$ARGUMENTS` if provided, otherwise run all tests
3. If tests pass, show a summary and coverage
4. If tests fail:
  - Show which tests failed and why
  - Read the failing test source and the code under test
  - Analyze the cause: code bug or outdated test?
  - Propose a concrete fix
  - Ask whether to implement it