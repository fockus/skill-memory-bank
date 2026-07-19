---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# disown-detached codex exec fakes completion

Launching `codex exec ... &` then `disown` makes the *launcher script* return immediately, which reads as "task finished / empty output" — but the actual `codex exec` process is still running detached in the background.

**Why:** cost one teammate an unnecessary re-run/false alarm mid Stage-4 review before they diagnosed it and switched to a genuine blocking background call (`codex exec ... > file 2>&1` wrapped directly in `run_in_background`, no `disown`).

**How to apply:** never background a Codex/long-running CLI call via shell `&`+`disown` when you need its actual completion signal — use the harness's own `run_in_background` on the foreground-blocking command instead, or synchronous dispatch. Related: [[background-agents-need-sendmessage]].

---
*Auto-captured by MB session-memory (session 7223ccff).*
