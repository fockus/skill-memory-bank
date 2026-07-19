---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Code-graph underuse root cause + agent routing fix

Research (rs-graph teammate) found `/mb work` implementer subagents never queried `scripts/mb-graph-query.py` (neighbors/impact/tests/explain/summary/status subcommands existed and worked) because nothing in their prompts routed structural questions to it — they defaulted to grep.

Fix shipped same session: routing guidance added to `agents/mb-developer.md`, `agents/mb-tooling-core.md`, `commands/work.md`, backed by `tests/bats/test_agent_graph_routing.bats`.

**Lesson:** a capability existing as a tool/script is not enough — subagents only use it if their own instructions explicitly route the question type to it. Verify tool adoption with a routing test, not just tool availability.

---
*Auto-captured by MB session-memory (session 5d8d86ec).*
