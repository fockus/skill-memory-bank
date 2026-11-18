# /mb graph — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `graph [--apply] [--cochange] [--questions] [src_root]` — Multi-language code graph. Always on: Python + Bash + Bats (stdlib `ast` / `re`, 0 deps) + Go/JS/TS/Rust/Java (via tree-sitter, opt-in through `pip install tree-sitter tree-sitter-go ...`). Output: `codebase/graph.json` (JSON Lines, `community` ids) + `codebase/god-nodes.md` (Top symbols / Top modules + Communities & Bridge files via optional networkx). Incremental SHA256 cache. Opt-in `--cochange` adds deterministic git co-change file edges (`co_change` kind); `--questions` appends deterministic suggested questions to `god-nodes.md`

### graph [--apply] [--cochange] [--questions] [--docs] [src_root]

Build a code graph for the project with 0 new deps: Python through stdlib `ast`, Bash (`.sh`) and Bats (`.bats`) through stdlib `re`. Replaces `grep` for questions like "where is X called?", "which classes inherit from Y?", "what is imported from model.py?" — deterministic, fast, incremental.

Extraction engines live in the `memory_bank_skill` package: `codegraph_python` (stdlib `ast`), `codegraph_shell` (Bash/Bats via stdlib `re`), `codegraph_treesitter` (opt-in multi-language), `codegraph_analytics` (degree split / communities / betweenness), `codegraph_cochange` (git co-change). `mb-codegraph.py` is a thin orchestrator over them.

`--apply` ends by warming the semantic vector index (`<bank>/.index/codesearch/`) from the graph it just wrote, so the first `mb-semantic-search.py --backend embeddings` reads a cache instead of encoding for minutes. The encoding runs detached (the graph build itself stays seconds) and only when the corpus changed; without the fastembed venv the step prints `semantic index skipped (no fastembed)` and exits 0. Install it with `MB_SEMANTIC_VENV="$HOME/.claude/hooks/.venv" bash "$SKILL_DIR"/hooks/mb-semantic-bootstrap.sh` (the index builder reads the venv from that path on every host).

**What it parses:**

- **Nodes:** module (per file), function (top-level + nested), class
- **Edges:** `import` (import X / from Y import Z), `call` (func() / obj.method()), `inherit` (class Child(Parent))

**Output (`--apply`):**

- `<mb>/codebase/graph.json` — JSON Lines (one node/edge per line, grep-friendly, streamable). Node lines carry a `community` id when networkx is installed; files with no file-level edge are not clusters and carry none. With `--cochange`, additional `{"kind":"co_change","weight":N}` edges are appended. With `--docs`, function/class/module nodes gain optional `signature`+`doc` fields (richer semantic search).
- `<mb>/codebase/god-nodes.md` — analytics report: **Top symbols** + **Top modules** (degree, split so test-module hubs no longer drown real abstractions) and, when networkx is available, **Communities** (auto-detected module clusters + cohesion score) + **Bridge files** (highest betweenness — refactoring/risk hotspots). With `--cochange`, a **Co-changing file pairs** section is appended.
- `<mb>/codebase/.cache/<hash>.json` — per-file SHA256 → parsed entities

**Analytics (optional `networkx`):** file-level community detection (Louvain, `seed=42` over a sorted file graph → the same clusters under any `PYTHONHASHSEED`; the `[codegraph]` extra pins one networkx minor; `communities=N` counts real clusters, not singleton files), per-cluster cohesion, and betweenness all live in the pure module `memory_bank_skill/codegraph_analytics.py`. Without networkx the report degrades gracefully (Top symbols / Top modules still render; the Communities / Bridge files sections of the previous `god-nodes.md` are carried over, not recomputed, under a line naming the commit and date of the build that computed them; rows naming files no longer in the graph are dropped; with no previous sections they are omitted; a one-line install note is always added). Install: `MB_SEMANTIC_VENV="$HOME/.claude/hooks/.venv" bash "$SKILL_DIR"/hooks/mb-semantic-bootstrap.sh` (puts the whole `[codegraph]` extra — tree-sitter, its grammars, networkx — into the bootstrap venv next to fastembed); `mb-codegraph.py` run under any python without networkx re-execs itself under that venv, as long as it has every tree-sitter module the current python has — so the tracked graph no longer depends on which interpreter rebuilt it.

**Co-change edges (opt-in `--cochange`):** files that change together across git history are coupled regardless of static imports/calls — a deterministic, $0 signal the AST/tree-sitter graph cannot see (e.g. a config file and the code that reads it, a test and its subject). Computed in the pure module `memory_bank_skill/codegraph_cochange.py` from `git log` (last 200 commits, bulk commits >25 files skipped, pairs needing ≥2 shared commits). Requires `--apply`; `git` is already a required dependency. Default (flag off) keeps `graph.json` + `god-nodes.md` byte-identical. Outside a git repo it degrades to zero co-change edges.

**Incremental:** if `sha256(file_content)` matches the cache — skip re-parse. On a large repo, the second run is near-instant.

**Safety:**

- `--dry-run` (default) — stdout summary (nodes/edges/reparsed/cached), 0 file changes
- `--apply` — writes all outputs + updates cache
- `--cochange` — appends git co-change edges (opt-in; requires `--apply`; no-op outside a git repo)
- `--questions` — appends deterministic suggested questions to god-nodes.md (opt-in; requires `--apply`)
- `--docs` — enrich function/class/module nodes with `signature`/`doc` for richer semantic search (opt-in; requires `--apply`; re-parses on toggle; default off keeps `graph.json` byte-identical)
- Broken syntax → skip with warning, batch continues
- `.venv/`, `__pycache__/`, `.*/` — excluded

Run directly:

```bash
python3 ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-codegraph.py $ARGS_AFTER_GRAPH
```

**Typical flow:**

```
User: /mb graph
→ dry-run output:
  nodes=52
  edges=388
  reparsed=3
  cached=0
  mode=dry-run

User: /mb graph --apply
→ nodes=52 edges=388 reparsed=3 cached=0 mode=apply
  [writes codebase/graph.json + god-nodes.md + .cache/]

# Modified 1 file, reran:
User: /mb graph --apply
→ `reparsed=1 cached=2` — one file re-parsed, two loaded from cache
```

**Example top god-nodes (dogfood on this repo):**

```
| # | Name          | Kind     | File:Line            | Degree |
|---|---------------|----------|----------------------|--------|
| 1 | run_import    | function | mb-import.py:185     | 60     |
| 2 | main          | function | mb-index-json.py:187 | 23     |
| 3 | _atomic_write | function | mb-import.py:157     | 22     |
```

**Integration with `mb-codebase-mapper`:** the agent uses `graph.json` as the source for CONVENTIONS and CONCERNS instead of grep (backlog for v2.3).

**Language support (v2.2 + Stage 6.5):**

- **Always works** (stdlib only, no install): Python (`.py`) via `ast`; Bash (`.sh`) and Bats (`.bats`) via `re`
- **Opt-in** (requires tree-sitter + grammars): Go (`.go`), JavaScript (`.js`/`.jsx`/`.mjs`), TypeScript (`.ts`/`.tsx`), Rust (`.rs`), Java (`.java`)
- Install tree-sitter (with networkx — the whole `[codegraph]` extra): `MB_SEMANTIC_VENV="$HOME/.claude/hooks/.venv" bash "$SKILL_DIR"/hooks/mb-semantic-bootstrap.sh`; `mb-codegraph.py` re-execs under that venv when the current python lacks networkx
- Without tree-sitter: files outside the always-on set (Python/Bash/Bats) are silently skipped (graceful degradation). The `HAS_TREE_SITTER` flag in the script reflects the status
- Skipped directories: `.venv`, `node_modules`, `__pycache__`, `.git`, `target`, `dist`, `build`, any `.`*

**Limitations:**

- Type inference is absent — edges work on names only (`foo()` calls do not distinguish modules with the same function name). Name resolution through imports — TODO v2.3+
- Tree-sitter extractor is intentionally simplified (MVP): not all language edge cases are covered — if you notice a missing node, open an issue
- `god-nodes.md` wiki/per-node documentation — deferred (YAGNI until there is real demand)
- C/C++/Ruby/PHP/Kotlin/Swift are not supported (can be added on demand via a new entry in `LANG_CONFIG` in `memory_bank_skill/codegraph_treesitter.py`)
