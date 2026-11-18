---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# pytest full-suite run leaks a write into the real .memory-bank

- Running the full suite (`pytest`, 2614 passed) in this repo caused some test to regenerate `.memory-bank/traceability.md` directly in the live bank instead of an isolated tmp copy — caught only because the commit script refused to proceed on an unexpected uncommitted change.
- The mutation itself was correct (added a new test's row) but the offending test was never identified.
- Gotcha: after a full local pytest run in this repo, check `git status` on `.memory-bank/` before trusting a "clean tree" assumption — a test isolation leak can silently rewrite real bank files.
- Open follow-up: find and fix the leaking test (likely a traceability generator missing tmp_path/monkeypatch); worth a backlog item.

---
*Auto-captured by MB session-memory (session ab6e3348).*
