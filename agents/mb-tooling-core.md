---
partial: true
name: mb-tooling-core
description: "[PARTIAL — not a standalone agent] Code-understanding tool routing prepended by /mb work before every dev-role agent. Graph-first, fail-open. Do not dispatch directly."
---

# MB Tooling Core — code-understanding routing

**This is a prepended partial, not an agent.** `/mb work` inlines this block ahead of the
role-specific agent delta. It carries the single routing table every MB implementer uses to
understand code before touching it.

## Code-understanding tools (graph-first, fail-open)

For code-understanding questions, prefer Memory Bank graph tools over `grep`:

| Intent | Token | Canonical command |
|--------|-------|-------------------|
| ambiguous "where is the logic for X?" / "find similar implementation" (fuzzy code-context) | `code_context` | `scripts/mb-code-context.py` |
| "who calls / imports / defines X?" (direct structural query) | `graph_neighbors` | `scripts/mb-graph-query.py neighbors` |
| "change impact" / "reverse deps" / blast-radius | `graph_impact` | `scripts/mb-graph-query.py impact` |
| "which tests cover this file/symbol?" | `graph_tests` | `scripts/mb-graph-query.py tests` |
| concept search (BM25 default, `--backend embeddings` opt-in) | `search_code` | `scripts/mb-semantic-search.py` |
| decisions / "why did we …?" | `recall` | `/mb recall <query>` |

Fail open: missing graph, stale graph, missing semantic provider, or unavailable native extension must not block work — CLI scripts / `Grep` / `Glob` / `Read` are the universal fallback.
These indexes are optional; if absent or stale, fall back to `Grep`/`Glob`/`Read` — never block.
