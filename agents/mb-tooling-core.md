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

For code-understanding questions, prefer Memory Bank graph tools over `grep`. Bundled scripts run
through the skill bundle root, from the project directory. Bind it in the SAME shell call as the command
(shell state does not persist between calls). If your prompt carries a `Skill path: <dir>` line (the
`/mb work` dispatch sends one), that `<dir>` is the value — use `SKILL_DIR="<dir>"`; otherwise:

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
```

Check the graph first with `bash "$SKILL_DIR"/scripts/mb-graph.sh status`:

| Intent | Token | Canonical command |
|--------|-------|-------------------|
| ambiguous "where is the logic for X?" / "find similar implementation" (fuzzy code-context) | `code_context` | `scripts/mb-code-context.py` |
| "who calls X?" (direct structural query) | `graph_neighbors` | `bash "$SKILL_DIR"/scripts/mb-graph.sh who-calls <Symbol>` |
| "change impact" / "reverse deps" / blast-radius | `graph_impact` | `bash "$SKILL_DIR"/scripts/mb-graph.sh impact <Symbol>` |
| "which tests cover this file/symbol?" | `graph_tests` | `bash "$SKILL_DIR"/scripts/mb-graph.sh tests <Symbol>` |
| concept search (exact name → BM25, phrase → embeddings) | `search_code` | `bash "$SKILL_DIR"/scripts/mb-graph.sh search "<query>"` |
| decisions / "why did we …?" | `recall` | `/mb recall <query>` |

`mb-graph.sh` wraps `mb-graph-query.py` and `mb-semantic-search.py`; trailing flags pass through (`--json`, `--k N`, `--source-only`). Call the underlying scripts directly only for what the wrapper does not expose (`--file`, `neighbors --direction out|both`, `explain`, `summary`, `catchup`).
Fail open: missing graph, stale graph, missing semantic provider, or unavailable native extension must not block work — CLI scripts / `Grep` / `Glob` / `Read` are the universal fallback.
These indexes are optional; if absent or stale, fall back to `Grep`/`Glob`/`Read` — never block.
- On a **stale** graph you MAY run `python3 "$SKILL_DIR"/scripts/mb-graph-query.py catchup --graph <bank>/codebase/graph.json --src-root . --json` **once** (bounded single-consumer catch-up: non-blocking `codebase/.graph.lock` flock, hard `MB_GRAPH_CATCHUP_BUDGET` budget with process-group kill, cooldown after failure, opt-in layers preserved) — never call `mb-codegraph.py --apply` directly from an agent and never take ad-hoc locks. If the result is `locked`/`cooldown`/`timed_out`, proceed on the stale graph and fall back to `Grep`/`Glob`/`Read` — never block.
