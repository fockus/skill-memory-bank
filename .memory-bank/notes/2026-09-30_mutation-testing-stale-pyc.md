---
title: Mutation testing — stale .pyc can fake a result
tags: [testing, mutation, python, agr-027]
importance: high
---
AGR-027 mutation proof (`cp` backup → mutate → run → `cp` restore → `cmp`) has a Python-specific hole.
If the mutant keeps the file SIZE and the restore lands in the same mtime SECOND, the interpreter's
`__pycache__/*.pyc` check (size + mtime) still matches the mutant. `cmp` says the source is restored,
yet the next test run executes the cached mutant — a false red after "restore", or a false green
during a mutation.

Seen in graph-semantic-adoption Stage 9: a `live`→`None` swap (same length) poisoned the next mutation.

**How to apply:** run mutation loops with `PYTHONDONTWRITEBYTECODE=1`, or delete the module's
`__pycache__` after every restore. Treat any "restored but tests still fail" as this first.
