---
type: pattern
tags: [script, doc-count, done-gate, ci, macos]
related_features: []
sprint: null
importance: high
created: 2026-11-20
---

# New script doc row and local done-gates
Date: 2026-11-20 03:32

## What was done
- Added scripts/mb_work_active.py; test_doc_counts failed until references/scripts.md got its row (I-308, fixed in c499012).
- Forced /mb done: local scope=full suite ran >45 min on macOS and was stopped.

## New knowledge
- Every new file in scripts/ needs a row in references/scripts.md; run tests/pytest/test_doc_counts.py before pushing.
- mb-done-gates.sh picks scope=full locally; macOS has no `timeout`; sharded CI (~15–22 min) is the practical full-suite gate (idea I-309).
