---
description: Generate or update documentation for a module
allowed-tools: [Read, Glob, Grep, Bash, Write]
argument-hint: <module-path>
agent: explorer
context: fork
---

<!--
  `agent: explorer` and `context: fork` are plugin-specific keys (e.g. Codex uses
  `context: fork`). Harmless in hosts that don't recognize them; where supported
  they route the command to the Explorer subagent in a forked context so the
  main session is not polluted by read-heavy exploration.
-->

## 0. Validate arguments

If `$ARGUMENTS` is empty, stop and ask the user which module to document.

## 1. Document the module

For module `$ARGUMENTS`:

1. Find all public APIs: exported functions, structs, interfaces
2. Read the existing comments and godoc/docstrings
3. Create or update `./docs/<module>.md`:
  - Module purpose
  - Public API with descriptions of every function/method
  - Usage examples from tests
  - Dependencies and configuration
4. If code comments are missing or incomplete, suggest adding them