---
partial: true
name: mb-tooling-core
description: "[PARTIAL — not a standalone agent] Code-understanding tool routing composed into the dev-role agents, mb-reviewer, and plan-verifier at install time. Graph-first, fail-open. Do not dispatch directly."
---

# MB Tooling Core — code-understanding routing

**This is a partial, not an agent.** The installer places it above the text of every agent that
lists it under `compose:`. It is the single routing table MB agents use to understand code before
touching it; agents do not keep their own copies.

## Code-understanding tools (graph-first, fail-open)

For code-understanding questions, prefer Memory Bank graph tools over `grep`. Check the graph first with
`scripts/mb-graph-query.py status --graph <bank>/codebase/graph.json --src-root . --json`:

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
- On a **stale** graph you MAY run `python3 scripts/mb-graph-query.py catchup --graph <bank>/codebase/graph.json --src-root . --json` **once** (bounded single-consumer catch-up: non-blocking `codebase/.graph.lock` flock, hard `MB_GRAPH_CATCHUP_BUDGET` budget with process-group kill, cooldown after failure, opt-in layers preserved) — never call `mb-codegraph.py --apply` directly from an agent and never take ad-hoc locks. If the result is `locked`/`cooldown`/`timed_out`, proceed on the stale graph and fall back to `Grep`/`Glob`/`Read` — never block.
