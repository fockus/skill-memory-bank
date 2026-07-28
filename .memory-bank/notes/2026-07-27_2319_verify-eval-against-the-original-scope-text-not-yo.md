---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Verify Eval against the original Scope text, not your own split intent

svp-sdd-core review cycle: an implementer split a task and then checked their Eval battery against what they *intended* to carve out in the split, not against the `Scope:` text as originally written in the task — masking a real coverage gap that surfaced 3 instances instead of the 1 originally reported.
- **Root cause pattern:** self-authored restructuring becomes the comparison baseline instead of the spec's own words, so verification passes against your own memory of what you did rather than what was required.
- **Fix:** after splitting/refactoring a task, diff Eval coverage against the literal `Scope:` field in the task doc, not against your mental model of the split.

---
*Auto-captured by MB session-memory (session 62c43c7d).*
