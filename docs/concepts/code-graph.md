# Code graph & semantic search

Memory Bank can build a **structural map of your codebase** and search it by both
*name* and *meaning* — so the agent stops guessing with `grep` and starts
answering "who calls X?", "where is the logic for Y?", and "what changes
together?" deterministically. Everything here is **opt-in and fails open**: a
missing graph, missing index, or missing optional dependency never blocks the
agent — it degrades to `grep`/`Read` and surfaces a one-line install hint.

There are three layers, from cheapest to richest.

---

## 1. Codebase map — `/mb map`

`/mb map [stack|arch|quality|concerns|all]` scans the repo and writes four
human-readable docs under `.memory-bank/codebase/`:
`STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `CONCERNS.md`. These are
auto-loaded by `/mb context`, so every session starts already knowing your
stack and architecture. This is prose, not a graph — the orientation layer.

## 2. Code graph — `/mb graph`

`/mb graph [--apply]` builds a deterministic graph of your code:

- **Languages:** Python via stdlib `ast` (zero new deps); Go / JS / TS / Rust /
  Java via tree-sitter (opt-in).
- **Nodes:** module (per file), function (top-level + nested), class.
- **Edges:** `import`, `call`, `inherit`.
- **Output (`--apply`):**
  - `codebase/graph.json` — JSON Lines (one node/edge per line, grep- and
    stream-friendly).
  - `codebase/god-nodes.md` — **Top symbols** + **Top modules** by degree, and
    (with `networkx`) auto-detected **communities** + **bridge files** (the
    highest-betweenness refactoring/risk hotspots).
- `--dry-run` (default) prints a summary and writes nothing; `--apply` writes
  the graph + an incremental per-file SHA256 cache (second run is near-instant).

**Query it** with `mb-graph-query.py` (`neighbors` / `impact` / `tests` /
`explain` / `summary`) or raw `jq` — prefer this over `grep -rn` for structural
questions:

```bash
# Who calls function X? (impact analysis)
jq -c 'select(.type=="edge" and .dst=="WriteFile")' .memory-bank/codebase/graph.json
python3 scripts/mb-graph-query.py impact WriteFile --mb .memory-bank
```

### Opt-in graph layers (base output stays byte-identical)

| Flag | Adds |
|---|---|
| `/mb graph --apply --questions` | Deterministic **suggested exploration questions** appended to `god-nodes.md` (from god-nodes / bridges / communities / co-change). $0, no LLM. |
| `/mb graph --apply --cochange` | **`co_change` edges** — files that change together across git history (last 200 commits), a coupling signal the static graph can't see (e.g. a config and its reader, a test and its subject). |
| `/mb graph --apply --docs` | Enriches function/class/module nodes with `signature` + `doc`, so **semantic search** matches intent, not just names. |

## 3. Semantic search & wiki — meaning, not just names

### `mb-semantic-search.py` — search by intent

```bash
python3 scripts/mb-semantic-search.py "<query>" .memory-bank \
  [--backend auto|bm25|embeddings] [--source-only] [--k N]
```

Ranks graph symbols (+ wiki articles, if built) by relevance.

- **`--backend auto`** (default) = local `sentence-transformers` **embeddings**
  when installed (best for concept/synonym queries), else pure-Python **BM25**
  (\$0, zero deps, deterministic — best for exact identifiers).
- `--source-only` drops test/spec files (find the implementation, not its tests).
- First embeddings query loads the model (~5–15 s); subsequent queries reuse a
  cached vector matrix under `.memory-bank/.index/codesearch/` (sub-second).
- Build with `/mb graph --apply --docs` so the index matches intent.

### `/mb wiki` — per-community articles + surprising connections

`/mb wiki` is an **opt-in LLM layer** over the deterministic graph (never runs
implicitly). It builds a per-community codebase wiki and discovers **surprising
connections** — semantic links the static import/call/inherit graph misses —
using **host subagents** (no API key; cost is only the subagent calls):

- **Haiku** subagents write per-community articles (cheap, parallel);
- one **Sonnet** subagent synthesizes cross-cutting connections into validated,
  idempotent `{"kind":"semantic",…}` edges on `graph.json`.
- Outputs: `codebase/wiki/community-<N>.md` + `index.md`. The articles also feed
  semantic search. `--dry-run` stops after printing the dispatch plan.
- Communities need `networkx` (`pip3 install networkx`); 0 communities → no-op.

---

## Routing — which tool for which question

| Question | Tool |
|---|---|
| "who calls / imports / inherits X?" | `jq` over `graph.json` / `mb-graph-query.py neighbors` |
| change impact / reverse deps | `mb-graph-query.py impact` |
| "what tests cover this?" | `mb-graph-query.py tests` |
| "where is the logic for X?" / "find similar" / concept | `mb-semantic-search.py --backend embeddings` |
| an exact symbol you already know | `mb-semantic-search.py --backend bm25` |
| "what else changes with this file?" | `co_change` edges (`--cochange`) |
| "give me a map / the non-obvious links" / "why" | `/mb wiki`, or `/mb recall` for past decisions |

**Fail open:** missing/stale graph → suggest `/mb graph --apply`; missing
optional dep (`networkx`, `sentence-transformers`) → degrade and surface the
install, never block the task.

---

## See also

- **[Cross-session memory](session-memory.md)** — `/mb recall` over past chats (a different index).
- `references/code-graph.md` — the full jq cookbook, `graph.json` schema (incl.
  `co_change` / `semantic` edges), and benchmark-grounded search routing.
- `commands/mb.md` — `/mb map`, `/mb graph`, `/mb wiki` command reference.
