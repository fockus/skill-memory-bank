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
- **Edges:** `import`, `call`, `inherit`. Python `call` edges are
  **import-aware** — resolved through the file's actual imports (local `def` >
  explicit/relative/aliased import > star-import > unique project-wide fallback,
  homonyms suppressed). The tree-sitter languages stay name-based.
- **Output (`--apply`):**
  - `codebase/graph.json` — JSON Lines (one node/edge per line, grep- and
    stream-friendly).
  - `codebase/god-nodes.md` — **Top symbols** + **Top modules** ranked by
    **PageRank** (transitive importance) with degree as a secondary
    column when `networkx` is available, plus auto-detected **communities** +
    **bridge files** (the highest-betweenness refactoring/risk hotspots). Without
    `networkx` the report degrades to degree-only ranking and prints a one-line
    install hint.
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
| `/mb graph --apply --cochange` | **`co_change` edges** — files that change together across git history (last 200 commits), a coupling signal the static graph can't see (e.g. a config and its reader, a test and its subject). Also emits a per-file **`churn_30d`** signal (from the *same* git-log pass) that gives recently-hot files a small ranking boost in semantic search. |
| `/mb graph --apply --docs` | Enriches function/class/module nodes with `signature` + `doc`, so **semantic search** matches intent, not just names. |
| `/mb graph --apply --sessions` | Bridges **session memory** into the graph: one `session` node per session that touched a graph module, a `worked_on` edge to each touched module with a one-line work summary, and an append of that summary to the module's `doc` (3 most recent sessions per module) so semantic search answers work-history queries. See the privacy note below. |

> **`--sessions` privacy & ranking note.** `graph.json` is meant to be
> committable, so every session-derived string is **`<private>`-stripped and
> secret-redacted at graph-write time** (defense-in-depth on top of capture-time
> redaction). The session layer is applied as the **last mutation** — after the
> structural community / betweenness / PageRank analytics — so it never skews
> god-node ranking: `god-nodes.md` is byte-identical with or without `--sessions`,
> while `graph.json` carries the extra `session` nodes + `worked_on` edges +
> `doc` appends.

## 3. Semantic search & wiki — meaning, not just names

### `mb-semantic-search.py` — search by intent

```bash
python3 scripts/mb-semantic-search.py "<query>" .memory-bank \
  [--backend auto|bm25|embeddings] [--source-only] [--k N]
```

Ranks graph symbols (+ wiki articles, if built) by relevance.

- **`--backend auto`** (default) = when local `sentence-transformers`
  **embeddings** are installed, the embeddings and BM25 rankings are fused via
  **Reciprocal Rank Fusion** (RRF) — combining concept recall with exact-name
  precision; without embeddings it stays pure-Python **BM25** (\$0, zero deps,
  deterministic, byte-identical to the embeddings-absent path). Explicit
  `--backend bm25` / `embeddings` skip the fusion.
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
  idempotent `{"kind":"semantic",…}` edges on `graph.json`, each carrying a
  `confidence` + `rationale`
  ([bands & the `< 0.5` drop floor](../../references/code-graph.md#semantic-edge-confidence-bands)).
- Each pack also gets a deterministic, `$0` **Decisions** section — `notes/`
  entries + session summaries matched to the community's files.
- **Incremental rebuild:** `index.md` records a per-article SHA256 over the graph
  records touching each community, so a refresh re-dispatches only the
  communities whose member files changed since the last build (`--force` rebuilds
  everything). A fully-fresh cache → zero subagent dispatches.
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

## How it compares with other approaches

| Tool | Approach | Structural queries | Persistent artifact | Cost |
|---|---|---|---|---|
| **memory-bank-skill** | AST/tree-sitter → JSONL graph + analytics + LLM wiki | ✅ jq / CLI | ✅ `graph.json` on disk, committable | $0 default |
| Aider repo-map | tree-sitter + personalized PageRank → ranked text into the prompt | ❌ (text, not edges) | ❌ per-request | $0 parse |
| Serena MCP | LSP servers (40+ langs) | ✅ compiler-precise | ❌ live server state | $0, server process |
| Cursor indexing | server-side embeddings | ❌ similarity only | ❌ vendor cloud | subscription |
| CodeGraphContext | tree-sitter → embedded graph DB | ✅ MCP tools | ✅ graph DB | $0, DB process |
| Cline | none by design — reads files on demand | ❌ | ❌ | $0 |

What's deliberately different here: the graph is a **plain file living next to your
plans, ADRs, and session memory** — any agent (or you, with `jq`) can query it with
no server, no API key, and no vendor. Unique extras: git **co-change edges**
(coupling invisible to AST) and the **LLM wiki** whose `semantic` edges carry a
`confidence` + `rationale` and merge idempotently into the same graph — the
`confidence` bands (and the deterministic `< 0.5` drop floor) are defined in
[`references/code-graph.md`](../../references/code-graph.md#semantic-edge-confidence-bands).

Honest limits: 6 languages (Python/Go/JS/TS/Rust/Java); call resolution is
**import-aware for Python** (stdlib `ast` — follows the file's imports) but
**name-based** for the tree-sitter languages (Go/JS/TS/Rust/Java), so an LSP like
Serena is still more precise on dynamic dispatch and cross-language aliases; no
automatic PageRank-style context packing — agents query explicitly instead.

---

## See also

- **[Cross-session memory](session-memory.md)** — `/mb recall` over past chats (a different index).
- `references/code-graph.md` — the full jq cookbook, `graph.json` schema (incl.
  `co_change` / `semantic` edges), and benchmark-grounded search routing.
- `commands/mb.md` — `/mb map`, `/mb graph`, `/mb wiki` command reference.
