# Code Graph — usage

> On-demand reference. The structural code-graph cookbook — jq query library,
> `graph.json` data schema, the opt-in intelligence layer, benchmark-grounded
> semantic-search routing, and `/mb recall` session memory — lives here so the
> always-read `rules/RULES.md` stays lean. Linked from `SKILL.md` and surfaced via
> `/mb help`. This file is the source-of-truth for the intelligence-layer contract
> tests (`tests/pytest/test_rules_cover_intelligence_layer.py`).

`.memory-bank/codebase/graph.json` encodes the structural layer of the project (module/function/class nodes + import/call edges) in JSON Lines format. Use it in place of `grep -rn` for **structural** questions — deterministic, fast, and semantically grounded.

### Data schema

```jsonc
// Nodes
{"type":"node", "kind":"module",   "name":"path/to/file.ext", "file":"...", "line":1}
{"type":"node", "kind":"function", "name":"FuncName",         "file":"...", "line":N}
{"type":"node", "kind":"class",    "name":"ClassName",        "file":"...", "line":N}
// Optional: "community":N — Louvain cluster id, added when networkx is installed.
// Optional (only with `/mb graph --apply --docs`): "signature" + "doc" enrich nodes
//   so semantic search matches intent words, not just identifiers:
{"type":"node", "kind":"function", "name":"verifySignature", "file":"...", "line":N, "signature":"(req, secret)", "doc":"HMAC-SHA256 verify with nonce TTL"}

// Edges
{"type":"edge", "kind":"import", "src":"path/to/src.file", "dst":"pkg/import/path"}
{"type":"edge", "kind":"call",   "src":"path/to/src.file", "dst":"FuncOrMethodName"}
// Opt-in edge kinds (off by default — base graph stays byte-identical):
{"type":"edge", "kind":"co_change", "src":"file/a", "dst":"file/b", "weight":N}                       // git history (--cochange)
{"type":"edge", "kind":"semantic",  "src":"file/a", "dst":"file/b", "confidence":0.0-1.0, "rationale":"..."}  // LLM wiki (/mb wiki)
// IMPORTANT: src = source file path; dst = function name / import path
// IMPORTANT: inherit edges — Python stdlib-ast only. Tree-sitter extractors for Go/JS/TS/Rust/Java do NOT emit inherit edges (type inference is absent).
```

### Basic jq queries

```bash
# 1. Which files call function X?
jq -r 'select(.type=="edge" and .kind=="call" and .dst=="X") | .src' \
  .memory-bank/codebase/graph.json | sort -u

# 2. All functions defined in a directory
jq -c 'select(.type=="node" and .kind=="function" and (.file|startswith("src/service/")))' \
  .memory-bank/codebase/graph.json | head -20

# 3. What does a specific file import?
jq -r 'select(.type=="edge" and .kind=="import" and .src=="src/service/context.py") | .dst' \
  .memory-bank/codebase/graph.json

# 4. Which files import a particular package?
jq -r 'select(.type=="edge" and .kind=="import" and .dst=="my_project/utils") | .src' \
  .memory-bank/codebase/graph.json | sort -u

# 5. Top god-nodes for refactoring
head -25 .memory-bank/codebase/god-nodes.md
```

### Practical use cases

```bash
# IMPACT ANALYSIS — how many files would be affected by changing a signature?
jq -r 'select(.type=="edge" and .kind=="call" and .dst=="WriteFile") | .src' \
  .memory-bank/codebase/graph.json | sort -u | wc -l

# ONBOARDING — survey an unfamiliar module
MODULE="src/service/codeagent"
jq -c 'select(.type=="node" and (.file|startswith("'$MODULE'/")))' .memory-bank/codebase/graph.json
jq -r 'select(.type=="edge" and .kind=="import" and (.src|startswith("'$MODULE'/"))) | .dst' \
  .memory-bank/codebase/graph.json | sort -u   # external deps of the module

# DEAD CODE — functions with no incoming call edges (removal candidates)
jq -r 'select(.type=="node" and .kind=="function") | .name' .memory-bank/codebase/graph.json \
  | sort -u > /tmp/defined.txt
jq -r 'select(.type=="edge" and .kind=="call") | .dst' .memory-bank/codebase/graph.json \
  | sort -u > /tmp/called.txt
comm -23 /tmp/defined.txt /tmp/called.txt | head
# CAVEAT: exported funcs may be called from outside, main/init/Test* have special lifecycles

# HYBRID (graph → grep) — find callers via graph, then read context via rg
files=$(jq -r 'select(.type=="edge" and .kind=="call" and .dst=="WriteFile") | .src' \
  .memory-bank/codebase/graph.json | sort -u)
for f in $files; do rg "WriteFile\(" "$f" -n | head -1; done

# REVERSE DEPENDENCIES — who depends on a given package (1-hop transit)
jq -r 'select(.type=="edge" and .kind=="import" and (.dst|contains("internal/core/toolnames"))) | .src' \
  .memory-bank/codebase/graph.json | sort -u
```

### Decision table — graph vs grep/code-read

| Question | Tool | Why |
|---|---|---|
| "Where is X called?" | **graph** | Deterministic, no noise from strings/comments |
| "What does Y import?" | **graph** | Exact structure, transitive via repeated queries |
| "How many callers does a function have?" | **graph** | Count edges |
| "Where is the string 'TODO: legacy'?" | **rg/grep** | Not a structural question |
| "Who implements interface I?" | **rg/grep + Read** | Graph does not resolve interface-implements (no type inference) |
| "What methods does struct S have?" | **rg/grep + Read** | Methods-on-receiver are not graph edges |
| "Complexity hotspots" | **`god-nodes.md` + `wc -l`** | Ready-made top-20 + real LoC |
| "Diff between branch and main" | **`git diff`** | Graph does not track VCS |

### Caveats

- **Call resolution.** Python `call` edges are **import-aware** — resolved through the file's actual imports (local `def` > explicit/relative/aliased import > star-import > unique project-wide fallback; homonyms suppressed). The tree-sitter languages (Go/JS/TS/Rust/Java) stay **name-based** (no type inference): generic names (`Error`, `New`, `String`, `Run`, `Close`, `Background`, `Now`, `Execute`) in `god-nodes.md` are lexical false-positives there — filter generics when analysing top-degree nodes.
- **Vendored code.** By default `skip_dirs = {.venv, __pycache__, node_modules, .git, target, dist, build}`. Projects with `vendor/` or `third_party/` (e.g. Go projects vendoring langchaingo) need a **project-local patched copy** in `.memory-bank/scripts/mb-codegraph-local.py` that adds those paths to `skip_dirs`. Run with: `PYTHONPATH="$HOME/.claude/skills/memory-bank" python3 .memory-bank/scripts/mb-codegraph-local.py --apply`.
- **Language coverage.** Python always works (stdlib `ast`). Go / JS / TS / Rust / Java require `pip install tree-sitter tree-sitter-<lang>` (opt-in). Without tree-sitter, non-Python files are silently skipped (graceful degradation).
- **Rebuild cost.** Incremental via SHA256 cache in `.cache/` — unchanged files are skipped. First run on a 1000-file project: ~3-5 min. Subsequent runs: seconds.

### When to rebuild

- Major refactor / new modules / moved packages → `/mb graph --apply && /mb map`
- Weekly or when you notice drift → `/mb map`
- Per focus area after a feature → `/mb map concerns` or `/mb map arch`

### Automation

For repeated queries, create project-local aliases/scripts under `.memory-bank/scripts/` — keep them project-scoped, never globalize.

### Keep the graph fresh on commit (opt-in)

An opt-in git `post-commit` hook refreshes the graph incrementally after every
commit. It is **not** auto-installed (it mutates the tracked `graph.json` and
lives outside the skill's Claude-Code hook system). Enable it per-repo:

```bash
ln -sf ~/.claude/skills/memory-bank/hooks/git/post-commit-codegraph.sh \
       .git/hooks/post-commit
```

`post-commit` (not pre-commit) never slows a commit; it refreshes an already-built
graph in the background under a lock, and is fail-safe (always exits 0).

> ⚠️ **Warning:** this hook writes to `.memory-bank/codebase/graph.json`, which is
> git-tracked — expect the graph to show up as a working-tree change after commits.
> Prefer it only where you commit the graph deliberately, or add `graph.json` to
> `.gitignore` first. Alternatively, enable the SessionStart auto-rebuild with
> `MB_GRAPH_AUTO=on` (also off by default, same tracked-file caveat).

### Intelligence layer (opt-in) — suggested questions · semantic search · wiki

Beyond the deterministic structural graph, three **opt-in** layers add what plain AST/import edges cannot see. All are off by default — base `/mb graph` output stays byte-identical, and none add a mandatory dependency (graceful degradation when an optional one is absent).

- **Suggested questions** — `/mb graph --apply --questions`. Appends a *"Suggested questions"* section to `god-nodes.md`: deterministic, $0 starting points derived from graph structure (highest-degree symbols, bridge files by betweenness, large / low-cohesion clusters, co-changing pairs). Use it to orient in an unfamiliar codebase before diving in.
- **Co-change edges** — `/mb graph --apply --cochange`. Adds `co_change` edges from **git history** (files that change together across commits) — coupling the static graph misses. Query: `jq -c 'select(.type=="edge" and .kind=="co_change")' .memory-bank/codebase/graph.json`. High co-change with **no** structural edge = hidden/implicit coupling worth a second look.
- **Semantic search** — `python3 ~/.claude/skills/memory-bank/scripts/mb-semantic-search.py "<query>" [--backend auto|bm25|embeddings] [--source-only] [--k N]`. Answers *"where is the logic for X?"* by ranking graph symbols (+ wiki articles, if built) by relevance. `--backend auto` (default) = when local `sentence-transformers` **embeddings** are installed, the embeddings and BM25 rankings are **fused via Reciprocal Rank Fusion (RRF)** (concept recall + exact-name precision); without embeddings it stays pure-Python **BM25** ($0, zero deps, byte-identical to the embeddings-absent path). Explicit `--backend bm25`/`embeddings` skip the fusion. `--source-only` drops test/spec files (find the implementation, not its tests). First embeddings query loads the model (~5-15s); subsequent queries reuse a cached vector matrix under `.memory-bank/.index/codesearch/` (sub-second). Build the graph with `/mb graph --apply --docs` so nodes carry `signature`+`doc` and the index matches intent, not just names. See the routing table below.
- **Wiki + surprising connections** — `/mb wiki` (LLM, via host subagents — **no API key**). **Haiku** writes one article per community → `codebase/wiki/community-<N>.md` + `index.md`; **Sonnet** finds *surprising connections* (semantically related files with **no** import/call/inherit edge) and merges them as `semantic` edges (`confidence` + `rationale`, validated + **idempotent**). The wiki articles also feed semantic search. Run/refresh after a major feature when you want a navigable map + the non-obvious links the static graph cannot derive. `--dry-run` previews the dispatch plan without spending tokens.

#### `semantic` edge confidence bands

Every `semantic` edge carries a `confidence ∈ [0, 1]`. The bands below are the single
source of truth — the wiki synthesizer prompt (`agents/mb-wiki-synthesizer.md`) assigns
confidence by them, and `mb-wiki.py merge-edges` enforces the floor (`wiki_store.py`):

| Band | Range | Meaning |
| --- | --- | --- |
| **High** | `≥ 0.9` | strong, unambiguous semantic alignment |
| **Medium** | `0.7 – 0.9` | reasonable connection worth surfacing |
| **Low** | `0.5 – 0.7` | weak but non-obvious — kept, read with care |
| **Not emitted** | `< 0.5` | dropped at merge time; never reaches `graph.json` |

The `< 0.5` floor is enforced deterministically, so a `semantic` edge in `graph.json`
always means `confidence ≥ 0.5` regardless of what the model proposed.

**Routing for the code-agent:** exact structural question ("who calls / imports / inherits X?") → `jq` over `graph.json`; intent/fuzzy ("where is the logic for X?", "find similar") → `mb-semantic-search.py`; "what else changes with this file?" → `co_change` edges; "give me a map / the non-obvious links" → `/mb wiki`. **Fail open:** missing/stale graph → suggest `/mb graph --apply`; missing optional dep (`networkx` for communities, `sentence-transformers` for embeddings) → degrade and surface the one-line install, never block the task.

### Semantic code search — when & how (benchmark-grounded)

`mb-semantic-search.py` ranks code-graph symbols by relevance; `mb-graph-query.py` traverses the graph structurally. They answer *different* questions — pick by intent (empirically benchmarked on a real repo: embeddings win concept queries, BM25 wins exact names, neither does graph-analytics):

Shorthand below: `$G = .memory-bank/codebase/graph.json` (mb-graph-query requires `--graph $G` on every subcommand).

| You want… | Command | Why |
|---|---|---|
| concept / "how does X work" / synonym (no exact name) | `mb-semantic-search.py "how does auth work" .memory-bank --backend embeddings` | vectors match *meaning* — finds `auth/*` even with no "authentication" token (requires `sentence-transformers`; else degrades to BM25) |
| an exact symbol/keyword you already know | `mb-semantic-search.py "pickWeighted" .memory-bank --backend bm25` | lexical, sharp score separation, fastest |
| the implementation, not its tests | append `--source-only` | drops `*test*` / `*.spec.*` / `__tests__/` / `test_*.py` |
| "what breaks if I change X" / blast-radius | `mb-graph-query.py impact --graph $G --symbol X` | directed dependents — a *retriever cannot answer this* |
| which tests cover X | `mb-graph-query.py tests --graph $G --symbol X` | call-edge traversal into test files |
| the most-connected hub / refactor bridge | `mb-graph-query.py summary --graph $G --out-dir .memory-bank/codebase` + `god-nodes.md` | a fact about node *degree*, not text — search misses it |
| "why was it built this way" (rationale/trade-off) | `/mb wiki` `semantic` edges · `/mb recall` | design intent isn't in code symbols |

- **Enrich first:** `/mb graph --apply --docs` indexes docstrings+signatures (opt-in; toggling re-parses via the cache). Without it the index sees only `name + kind + path`.
- **Embeddings cache** lives in `.memory-bank/.index/codesearch/` (gitignored, auto-invalidated by a corpus hash) — separate from session-recall's vectors, never collides.

### Session memory — cross-session recall

The skill logs every session to `.memory-bank/session/*.md` (git-tracked markdown) via lifecycle hooks (Stop → per-turn bullet, SessionEnd → Haiku summary + gated Sonnet auto-notes, SessionStart → injects recent sessions). This is **persistent project memory that carries across chats**, distinct from the codebase graph.

- **`/mb recall <query>`** — **progressive-disclosure** recall over `session/` + `notes/`: the default is a compact index (one `id · age · summary · source` line per hit, no chunk bodies), `--expand <id>` returns one full chunk, `--full` keeps the legacy bodies. Semantic + lexical hits are **RRF-fused** when the semantic backend is available (fail-open to **lexical-only** otherwise); `[SUPERSEDED]` chunks sort last. Use for *"did we discuss X before?"*, *"why did we choose Y?"*, *"have we hit this error?"* — before re-deriving something from scratch.
- Distinct from `/mb search` (searches core MB files) and from semantic code search (`mb-semantic-search.py`, searches the code graph). Session memory = conversation history; code graph = structure; core files = status/plan.
- **Off-switch:** `export MB_SESSION_CAPTURE=off` disables capture. Recall stays read-only and safe even when capture is off.
