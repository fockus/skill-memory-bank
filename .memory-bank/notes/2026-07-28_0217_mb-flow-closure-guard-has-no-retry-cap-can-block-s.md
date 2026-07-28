---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# mb-flow-closure-guard has no retry cap — can block session closure forever on a red flow

14-day transcript audit found the Stop-hook closure guard blocked flow closure 96+ times, one taskloom session hitting 160 consecutive blocks (finish attempt → block → retry, looped). I-131 (b5f074c, 2026-07-27) already fixed the *slowness* half (synchronous full pytest+bats run on Stop, was >180s, now budgeted to 20s + `--skip tests`) — see [[stop-hook-full-test-suite-hang]].
- **Remaining gap, not yet fixed:** the guard has no session-scoped attempt counter, so on a genuinely red flow it will now block fast but forever, not slow but finite.
- Recommendation surfaced but not implemented: count blocks per session, degrade to a warning after N with an explicit "flow not certified" marker instead of hard-blocking indefinitely.
- Found via quantitative cross-session transcript analysis (grep counts across 405 transcripts), not code reading — worth repeating that kind of audit periodically rather than only reasoning from the code.

---
*Auto-captured by MB session-memory (session d88c78b6).*
