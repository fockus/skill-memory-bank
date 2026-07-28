---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Stop-hook full-test-suite hang (I-131) root cause

`hooks/mb-flow-closure-guard.sh` (a Stop hook, active only when `.memory-bank/goal.md` exists) synchronously ran `scripts/mb-flow-verify.sh`'s `tests` check = the entire pytest+bats suite (>180s), while the other 4 checks combined took <1s. This caused sessions to hang at the end, and had survived several prior fix attempts because nobody had measured per-check timing to isolate the culprit.

**Fix:** added a hard time budget (`MB_FLOW_VERIFY_BUDGET`) as a safety net, plus `--skip tests`; user chose (via AskUserQuestion) to drop `tests` from the Stop-path entirely — Stop now runs only fast checks (~1s), full suite still gates `/mb work verify`, `/mb drive`, manual runs.

**Takeaway:** when a session-end/Stop hook is slow or hangs, measure each check's wall-clock individually before proposing a fix — don't assume it's plugins or something external.

---
*Auto-captured by MB session-memory (session 63e7abcc).*
