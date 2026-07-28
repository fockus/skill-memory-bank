---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Partial fix in one file ≠ finding closed across a spec triple

svp-sdd-core round-4 review: finding [10] (rejected step order) was believed fully closed by commit f886e21 after fixing `commands/sdd.md`. A later full-triple sweep found `design.md:468` still carried the rejected order — the same finding, unfixed in a second location.
- **Gotcha:** when a finding is "wrong text repeated across N files/instances," a commit that fixes the instance you checked does not prove the finding is closed.
- **Fix:** grep/sweep the ENTIRE affected scope (all files in the spec triple, not just the one edited) before marking a review finding resolved, especially for order/numbering-type findings that tend to be copy-pasted across requirements/design/tasks.

---
*Auto-captured by MB session-memory (session 62c43c7d).*
