---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Graph/vector adoption gap: cold-start index never built + routing hint decays before decision point

Investigated why code-graph/vector search sit under 1% of search traffic despite being fully implemented (see AGR-038, plan `2026-07-28_fix_graph-semantic-adoption.md`). Two distinct root causes, deeper than the earlier fix in [[code-graph-underuse-root-cause-agent-routing-fix]] (2026-07-15, which only added routing text):
- **Cold-start bootstrap never fires.** `.index/codesearch/` only existed in 1 of 4 projects. Building it means embedding the whole codebase (minutes) — no single mid-task moment justifies paying that cost inline, so it's never triggered. Same shape as AGR-025 (memsearch 24KB stub), now confirmed as a repeating pattern for any tool with an expensive first-use setup: it needs an out-of-band/background trigger, not a lazy on-first-query one.
- **Hint-decay by the time the decision happens.** Even where the graph is fresh and routing guidance exists, grep still wins: the hint is injected once at session start, but the actual "which tool do I search with" choice happens mid-session — the early hint doesn't survive that far. Fix direction: repeat the nudge every N grep calls with the symbol pre-filled, not a one-shot session-start mention.

---
*Auto-captured by MB session-memory (session d88c78b6).*
