# ~/.claude/commands/doc.md

---

## description: Generate or update documentation for a module
agent: explorer
context: fork
allowed-tools: [Read, Glob, Grep, Bash, Write]

For module `$ARGUMENTS`:

1. Find all public APIs: exported functions, structs, interfaces
2. Read the existing comments and godoc/docstrings
3. Create or update `./docs/<module>.md`:
  - Module purpose
  - Public API with descriptions of every function/method
  - Usage examples from tests
  - Dependencies and configuration
4. If code comments are missing or incomplete, suggest adding them