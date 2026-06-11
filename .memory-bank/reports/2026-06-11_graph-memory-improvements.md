# Improvement roadmap — code graph & cross-session memory (2026-06-11)

Synthesis of three research passes: internal deep-dive, competitor comparison
(Aider / Serena / graphify / Cursor / Cline / CodeGraphContext / Sourcegraph),
and SOTA survey (HippoRAG, LightRAG, cAST, Mem0, Zep/Graphiti, gitleaks).
Sources and file:line evidence live in the session transcripts of this date.

## Shipped this session (baseline)

- ✅ Default secret redaction in session capture (3 layers: Live log, summarizer
  input, semantic chunker) + `<private>` stripping in chunks. `MB_REDACT_SECRETS=off`.
- ✅ Honest auto-capture stub (no more false "will be reconstructed" promise).

## Tier 1 — high impact / low effort (one sprint, no new required deps)

| # | Improvement | Where | Why |
|---|---|---|---|
| 1 | **RRF hybrid retrieval** — run BM25 + embeddings, merge with Reciprocal Rank Fusion (k=60) instead of either/or | `semantic_search.py::run_search` (~20 lines) | Consistently beats single-backend on all benchmarks, no tuning |
| 2 | **Import-aware call resolution** — restrict `A → f` edges to the module A actually imports `f` from | `codegraph_python.py` (~50 lines, stdlib only) | Kills most false cross-file call edges (current matching is name-only) |
| 3 | **Personalized PageRank god-nodes** — directed graph + task-context personalization (Aider's trick) | `codegraph_analytics.py` (DiGraph + `nx.pagerank`, ~10 lines) | Transitive importance > raw degree; better refactoring hotspots |
| 4 | **Git churn/recency ranking signal** — `churn_30d` per file multiplied into ranking | extend `codegraph_cochange.py` | arXiv 2601.06185: structure+recency beats either alone |
| 5 | **Community-summary retrieval** — a wiki-article hit expands to its community's files (GraphRAG-local pattern) | `semantic_search.py` + `detect_communities()` | Concept queries return whole subsystems, not single symbols |
| 6 | **Consolidation pass `/mb consolidate`** — cluster old sessions, promote ≥2-times-accessed facts to notes/, archive the rest | new script + manager prompt | Fixes progress.md/session bloat (progress.md is 172KB of stubs); Ebbinghaus-style decay |
| 7 | **`supersedes:` convention in notes/lessons** — append new fact + mark old `[SUPERSEDED]` instead of in-place edits | manager agent prompt + lessons format | Zep-style temporal invalidation, zero infra |

## Tier 2 — high value, medium effort

- **Leiden instead of Louvain** (`nx.community.leiden_communities`, needs networkx ≥3.4) — fixes Louvain's disconnected-community artefacts; check version, else keep Louvain.
- **cAST-style chunking for the embedding corpus** — index full function/class bodies split at AST boundaries (tree-sitter already wired); +1.8–5.6 Recall@5 in the cAST paper.
- **HippoRAG-style PPR walk at query time** — seed PageRank with top-k BM25 hits, return union; retrieves structurally-related context keyword search misses.
- **Entity-centric memory** (Mem0 pattern) — `.memory-bank/entities/<name>.md` micro-factsheets updated at session end; makes "what do we know about X?" O(1). Gate the LLM extraction behind opt-in ($0-default contract).
- **FlashRank cross-encoder re-rank** after RRF (CPU, local) — experimental: MS MARCO models unproven on code, benchmark first.
- **gitleaks/betterleaks CI gate** over `.memory-bank/` — catches whatever runtime redaction misses; one CI step.
- **Auto-capture recap command** — `/mb recap <sid>` reconstructs a proper progress entry from session/*.md on demand (Option A from the audit; the stub is now honest but still noise).

## Explicitly NOT worth it (for a local-first, $0-default toolkit)

- Full **LSP integration** (per-language servers; ~15% precision gain, large operational cost).
- **stack-graphs** (archived Sept 2025, Rust dep; community consensus: tree-sitter + import binding ≈ same RAG value).
- **Graphiti/Zep deployment** (Neo4j dep; entity files give ~80% of the benefit).
- **TruffleHog as runtime hook** (network verification per write; fine as a quarterly audit script).

## Known gaps to keep on the radar

- Language coverage 6 vs Aider 130+ / graphify 28 — Kotlin, Swift, C/C++, C#, Ruby, PHP are the most-requested absentees; each is one tree-sitter grammar + node-type whitelist.
- `.memsearch/` (external memsearch plugin) stores full transcript paths in HTML comments — out of our control; coordinate or document.
- Auto-capture dedup uses an 8-char sid prefix (theoretical same-day collision).
- Semantic-edge `confidence` semantics are undocumented (what does 0.7 mean?).
