# Competitive landscape — agent memory & code graphs (2026-06-11)

Two research passes (memory systems / code-structure intelligence), 24 projects
verified against live READMEs. Complements `2026-06-11_graph-memory-improvements.md`
(internal roadmap) — this doc is the external map.

## Headline finding

The combination we ship — **deterministic code graph + git co-change edges +
LLM wiki semantic layer + automatic session capture + cross-session recall +
engineering rules** — exists nowhere else as a single tool. Only one project
pairs a code graph with an agent-memory layer at all:
**CodeGraph (codegraph-ai, 22★, very new)** — and its memory is manually
curated notes, not automatic session capture. Watch it.

## Memory systems — worth deep analysis

| Project | ★ | Architecture | Why analyze |
|---|---|---|---|
| **claude-mem** (thedotmack) | ~81k (viral; verify) | hooks → SQLite FTS5 + Chroma, worker :37777 | **Progressive disclosure**: search → 50-token index → timeline → full detail only for filtered IDs (~10× token savings). Biggest name in our exact niche. |
| **agentmemory** (rohitg00) | 22k | 12 hooks → SQLite + in-mem vectors, BM25+vector+graph fused via RRF | 4-tier consolidation (working→episodic→semantic→procedural) + decay + contradiction detection. 95.2% R@5 LongMemEval-S. |
| **basic-memory** (basicmachines) | 3.2k | Markdown-on-disk + SQLite index, fastembed, MCP | **Closest architectural twin** (files + wikilinks + hybrid search, no mandatory LLM). `memory://` URL scheme; MCP tool hints. |
| **engram** (Gentleman-Programming) | 4.3k | single Go binary, SQLite FTS5, explicit `mem_save` | `engram conflicts` — retroactive contradiction detection (FTS similarity → LLM judge). Simple-by-design, closest in spirit. |
| **codemem** (cogniplex) | 14 | single Rust binary, 9 hooks, HNSW + 9-signal scoring | Temporal graph of git commits + **diff blast-radius review** — fuses git history with conversational memory. Tiny but architecturally interesting. |
| **Supermemory** | 26.5k | LLM extraction, cloud-first, CC plugin | Self-expiring facts (infers validity from content, not TTL). Benchmark leader claims. |
| **Cognee** | 17.8k | LLM ontology → KuzuDB graph + vectors | Auto-inferred ontology; query-type auto-routing (vector vs graph). Heavy, adjacent. |
| **Memori** (MemoriLabs) | 15.2k | LLM augmentation, cloud-first | Captures **agent execution traces** (tool calls, edits), not just chat. 1,294 tokens/query on LoCoMo. |
| **MemOS** (MemTensor) | 9.7k | Neo4j+Qdrant+Redis | MemCube taxonomy: parametric/activation/plaintext memory. Mental model, not a tool to copy. |
| **LangMem** (langchain) | 1.5k | LLM extraction → Postgres | **Procedural memory**: system prompt rewrites itself from trajectories → idea: auto-suggested RULES.md amendments. |
| OpenMemory (CaviraOSS) | 4.2k (rewrite) | SQLite, 5 memory sectors | `valid_from`/`valid_to` validity windows + explainable recall traces. |
| A-MEM (NeurIPS'25) | 0.9k | research | Zettelkasten: agent restructures its own memory links. |

Stale/skip: Memary (Oct'24), MemoRAG (Sep'24), Motorhead (abandoned), Second-Me (identity, not memory).
Closed: AWS AgentCore Memory, Windsurf Memories, ChatGPT "Dreaming V3" (background re-synthesis of memory from raw history — idea for opt-in `/mb dream`).

## Code-graph systems — worth deep analysis

| Project | ★ | Approach | Why analyze |
|---|---|---|---|
| **codebase-memory-mcp** (DeusData) | 3.2k | tree-sitter ~159 langs, single C binary, SQLite, MCP×14 | **6-strategy confidence-scored call resolution** (import-map 0.95 → fuzzy 0.30); committable compressed graph artifact; Louvain; paper arXiv:2603.27277 — read it. |
| **CodeGraph** (codegraph-ai) | 22 | Rust, tree-sitter 38 langs, RocksDB, MCP×45 | Only other graph+memory pairing (`codegraph_memory_*` tools). Monitor. |
| **Potpie** | 5.4k | Neo4j + Postgres + Redis | Conversation history linked to graph queries; agent router over shared graph. Heavy infra. |
| **Blarify** | 229 | **SCIP** (compiler-grade, 330× faster than LSP) + tree-sitter fallback | SCIP = precision upgrade path for our Python call edges (`scip-python` via npm). Spike candidate. |
| **FalkorDB code-graph** | 313 | custom AST → FalkorDB, MCP×7 | `analyze-impact` as first-class primitive (we have it in mb-graph-query). Py/Java/C# only. |
| **kit** (cased) | 1.3k | tree-sitter symbols, no edges, MCP/REST/CLI | Clean composable "repo unit" API; symbol→docstring enrichment. Complementary. |
| **Joern + codebadger** | 3.2k/113 | CPG (AST+CFG+PDG), Scala/JDK21, Docker MCP | Compiler-level taint/data-flow. Reference answer for security questions, not a competitor. |
| **Glean** (Meta) | 1.4k | compiler-backed fact DB, Angle query DSL | Infrastructure-tier; schema-first fact design. |
| RepoGraph (ICLR'25) | 278 | NetworkX, **line-level nodes**, JSONL | +32.8% on SWE-bench; line granularity idea. |
| LocAgent (ACL'25) | 613 | hetero graph + BM25 entry → multi-hop expansion | 92.7% file-level localization; BM25→graph-walk pattern ≈ our HippoRAG Tier-2 item. |
| ARISE (arXiv:2605.03117) | no repo | Python ast, **def-use data-flow edges** | Most novel primitive: intra-procedural def-use chains. Future opt-in layer. |
| KGCompass | 34 | KG linking issues/PRs ↔ code nodes | Cross-artifact edges: 89.7% of located bugs had no location hint in issue text. Extension of our co-change idea. |

Dead: tree-hugger (2021), nuanced (archived 03/2026), CodeXGraph (demo only).

## Top transferable ideas (effort × impact)

1. **Progressive disclosure recall** (claude-mem) — `/mb recall` returns compact index first, expand by ID. Low effort, high impact, no deps.
2. **`/mb conflicts`** (engram) — lexical-overlap pass over notes/progress + optional LLM judge for contradictions. Medium/high.
3. **Validity windows / supersedes** (OpenMemory, Supermemory) — already Tier-1 #7 in roadmap; landscape confirms it.
4. **SCIP spike for Python edges** (Blarify) — measure precision delta vs our ast edges; roadmap candidate if >20%.
5. **Committed graph artifact for teams** (codebase-memory-mcp) — we already have graph.json in-repo; package/document the team workflow.
6. **Issue/PR→code edges** (KGCompass) — natural extension of `--cochange`.
7. **Def-use edges** (ARISE) — most novel primitive; backlog as future opt-in layer.

## Market signals

- MCP is table stakes — every live project ships an MCP server.
- Market bifurcated: file-first/$0 (us, basic-memory, engram, codemem) vs cloud/LLM-on-write (mem0, Supermemory, Memori). Privacy+cost vs benchmarks.
- Single-binary (Rust/Go) trend: "no Postgres, no Docker, no Python" is a user-valued feature.
- Biggest unsolved problem industry-wide: **memory staleness** (per Mem0's State of Memory 2026) — our supersedes/consolidate roadmap items target exactly this.
- Benchmarks that define credibility: LoCoMo, LongMemEval, BEAM (mostly self-reported).

## Caveats

- claude-mem's 81.6k★ from trendshift (viral pattern) — verify before citing.
- codebase-memory-mcp claims 159 langs; its paper says 66.
- CodeGraph (codegraph-ai) memory layer may be thinner than the README implies (22★, no paper).
- Benchmark numbers largely self-reported by the vendors being measured.
