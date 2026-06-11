---
topic: tier1-graph-memory
created: 2026-06-11
status: ready
---

# Context: tier1-graph-memory

## Purpose & Users

**Users:** every agent (and human) querying the code graph, the semantic search,
`/mb recall`, or the wiki — this repo's maintainers first (dogfooding), then all
downstream Memory Bank installs.

**Problem (three threads, one sprint):**
1. *Graph quality* — call edges are name-matched (false cross-file edges),
   god-nodes rank by raw degree (misses transitive importance), and retrieval is
   either/or BM25 vs embeddings instead of fused.
2. *Session memory efficiency* — per-turn capture records tool names but not
   outcomes; summaries are free-form; `progress.md` ballooned to 172KB of
   auto-capture stubs with no consolidation, no staleness signal, no conflict
   detection, and recall injects full snippets (token-expensive).
3. *Graph ⊥ sessions* — the two memory surfaces don't feed each other: the graph
   knows structure but not work history; the wiki rebuilds everything from
   scratch and never sees decisions.

**Success criteria (qualitative):** an agent finds code by work history ("where
did we fix the token leak?"), recall costs ~10× fewer tokens by default,
god-nodes surface true hotspots, false call edges measurably drop on this repo,
re-running `/mb wiki` on an unchanged repo is a near-no-op, and stale/superseded
memory stops polluting answers.

**Sources:** `reports/2026-06-11_graph-memory-improvements.md` (Tier 1/2),
`reports/2026-06-11_competitive-landscape.md` (claude-mem, engram, KGCompass,
OpenMemory patterns). Scope decisions confirmed with the user 2026-06-11.

## Functional Requirements (EARS)

### Group A — graph quality & retrieval

- **REQ-001** (event-driven): When a semantic code search runs with backend
  `auto` and both BM25 and embedding rankings are available, the search engine
  shall fuse the two rankings with Reciprocal Rank Fusion (k=60) into a single
  result list.
- **REQ-002** (unwanted): If the embeddings backend is unavailable, then the
  search engine shall return pure BM25 results without error (fail-open).
- **REQ-003** (event-driven): When the caller module imports the callee symbol
  or its defining module, the graph builder shall bind the cross-module call
  edge to that imported definition.
- **REQ-004** (unwanted): If a called name resolves to multiple definitions and
  none of them is imported by the caller, then the graph builder shall suppress
  the cross-module call edge unless the name is unique project-wide.
- **REQ-005** (state-driven): While networkx is available, the god-nodes report
  shall rank symbols and modules by Personalized PageRank over the directed
  graph, keeping degree as a secondary column.
- **REQ-006** (unwanted): If networkx is not installed, then the god-nodes
  report shall degrade to degree-based ranking and surface a one-line install
  hint.
- **REQ-007** (optional): Where `--cochange` is enabled, the graph builder shall
  record a per-file `churn_30d` count and the search engine shall apply it as a
  recency ranking signal.
- **REQ-008** (optional): Where the wiki layer is built, the search engine shall
  expand a top-ranked wiki-article hit with the member files of its community
  (community-summary retrieval).

### Group B — session memory

- **REQ-009** (event-driven): When the per-turn capture hook fires, the system
  shall record the turn outcome (success or error signal of tool calls) and a
  diffstat of touched files in addition to request, tools, and file names.
- **REQ-010** (ubiquitous): The session summary shall follow a fixed section
  template (What changed / Decisions / Open questions / Files) so downstream
  consumers can parse it deterministically.
- **REQ-011** (event-driven): When the session-end summarizer runs, the system
  shall feed it the redacted structured Live log and turn outcomes as primary
  input instead of the raw transcript tail.
- **REQ-012** (event-driven): When `/mb consolidate --apply` runs, the system
  shall promote facts recurring across two or more sessions into `notes/`, move
  consolidated session files verbatim into an archive, and leave pointers
  behind.
- **REQ-013** (unwanted): If `/mb consolidate` is invoked without `--apply`,
  then the system shall only print candidates and write nothing (dry-run
  default).
- **REQ-014** (ubiquitous): The consolidation pass shall move `progress.md`
  entries verbatim to the archive file and shall never edit an entry's content
  in place (append-only invariant).
- **REQ-015** (event-driven): When a note or lesson is superseded by a new
  fact, the manager shall append the new entry and mark the old one with a
  `[SUPERSEDED: YYYY-MM-DD -> <new-ref>]` tag instead of editing it in place.
- **REQ-016** (event-driven): When `/mb recall` runs without an expand
  argument, the system shall return a compact index — stable id, one-line
  summary, and age — instead of full snippets (progressive disclosure).
- **REQ-017** (event-driven): When `/mb recall --expand <id>` is invoked, the
  system shall print the full snippet and source path for that id.
- **REQ-018** (unwanted): If `--expand` references an unknown id, then the
  system shall exit non-zero with a clear error message.
- **REQ-019** (ubiquitous): The recall output shall display the age of each hit
  and shall downrank entries marked `[SUPERSEDED]` below all non-superseded
  hits.
- **REQ-020** (event-driven): When `/mb recap <sid>` is invoked, the system
  shall reconstruct a full progress entry from `session/<sid>*.md` via one
  Haiku subagent call and replace that session's auto-capture stub
  idempotently.
- **REQ-021** (unwanted): If the referenced session file does not exist, then
  `/mb recap` shall exit non-zero without writing to `progress.md`.
- **REQ-022** (event-driven): When `/mb conflicts` runs, the system shall
  report pairs of memory entries with high lexical overlap and opposing
  assertions as conflict candidates using zero LLM calls.
- **REQ-023** (optional): Where `--judge` is passed, the conflicts command
  shall confirm or reject each candidate via an LLM subagent and emit suggested
  `[SUPERSEDED]` markers for confirmed conflicts.

### Group C — session→graph enrichment & wiki

- **REQ-024** (optional): Where `--sessions` is enabled, the graph builder
  shall emit `worked_on` edges from session nodes to the module nodes of files
  touched in that session, each carrying a one-line summary attribute.
- **REQ-025** (optional): Where `--sessions` is enabled, the graph builder
  shall append session-derived work summaries to the `doc` field of touched
  module nodes so the embedding index matches work-history queries.
- **REQ-026** (ubiquitous): The graph builder shall pass all session-derived
  content through the secret-redaction pipeline before writing it to
  `graph.json` (defense-in-depth on top of capture-time redaction).
- **REQ-027** (event-driven): When `/mb wiki` runs against an existing wiki,
  the system shall rebuild only the articles of communities whose member files
  changed since the last build and skip unchanged communities.
- **REQ-028** (ubiquitous): The wiki evidence pack shall include decisions
  relevant to the community's files drawn from `notes/` and session summaries.
- **REQ-029** (ubiquitous): The code-graph reference documentation shall define
  the meaning of `confidence` values on `semantic` edges.

## Non-Functional Requirements

- **NFR-001**: $0 default — no new required dependencies; LLM calls happen only
  inside explicitly invoked commands (`/mb recap`, `/mb conflicts --judge`,
  `/mb wiki`). networkx / sentence-transformers / tree-sitter stay optional.
- **NFR-002**: Determinism — base graph build stays byte-reproducible on
  identical input; PPR uses fixed seed/stable iteration order; RRF is
  deterministic for equal inputs.
- **NFR-003**: Fail-open — missing networkx, embeddings, git history, wiki, or
  session files degrade gracefully with a one-line hint; never block the task.
- **NFR-004**: Compatibility — `graph.json` schema changes are additive-only;
  existing jq recipes and `mb-graph-query.py` keep working; the per-file cache
  carries a version bump so stale caches invalidate automatically.
- **NFR-005**: Performance — RRF merge is O(k) over result lists; consolidate
  processes 100+ session files and a 172KB progress.md in seconds; wiki
  staleness check itself costs zero LLM calls.
- **NFR-006**: Test coverage — 85%+ on new code paths (95%+ for ranking/merge
  logic), TDD-first, tests assert business facts.
- **NFR-007**: Privacy — every session-derived string written to durable
  artifacts (graph.json, wiki, notes) passes `redact_secrets`; `<private>`
  blocks are stripped.

## Constraints

- Defaults policy (user decision 2026-06-11): RRF, import-aware call
  resolution, and PPR god-nodes become the **new defaults in 5.1.0** with a
  CHANGELOG `Changed` entry and graph-cache version bump. `--sessions` and
  `--cochange`/churn stay **opt-in** (privacy: graph.json is committable; other
  people's sessions must not leak into git by default).
- `progress.md` append-only invariant is inviolable; archive moves are
  verbatim.
- Hooks remain POSIX-sh/macOS-compatible (no flock, no GNU-only flags).
- Project file-size rule: modules ≤400 lines — `semantic_search.py` and
  `codegraph_python.py` may require extraction of new modules rather than
  inline growth.
- Existing CLI flags (`--backend bm25|embeddings`, `--source-only`) keep their
  exact semantics.
- CI runs Python 3.11/3.12 — no 3.13-only APIs.

## Edge Cases & Failure Modes

- Both backends empty (no graph, no index) → recall/search fall back to
  lexical/grep with the standard hint; RRF never raises on an empty list.
- Called name defined in 3 modules, caller imports none, name not unique →
  edge suppressed (REQ-004); name unique project-wide → edge kept (recall
  preserved).
- PPR on a disconnected or edge-free graph → stable ranking, no crash.
- `churn_30d` on a shallow clone or non-git directory → signal absent, ranking
  unchanged, no error.
- `/mb recall --expand` pointing at a session file pruned by consolidate →
  clear "archived, see <archive-ref>" error, exit non-zero.
- `/mb recap` for a session that already has a real (non-stub) progress entry
  → refuses with a hint, writes nothing; second run on a recapped session →
  no-op.
- `/mb conflicts` on a bank with fewer than two entries → exits 0 with empty
  result.
- Consolidate archives a session referenced by `session/_recent.md` → the
  recent window is rebuilt afterwards (no dangling links).
- `worked_on` extraction from a session file with no files-touched frontmatter
  → that session is skipped silently.
- Wiki staleness check when the graph was rebuilt from scratch (no cache) →
  full rebuild (safe default).
- Malformed `[SUPERSEDED]` marker → drift checker warns; recall treats the
  entry as a normal hit.
- A secret that survived capture-time redaction in an old session file → the
  `--sessions` layer redacts again at graph-write time (REQ-026), so it never
  reaches a committable artifact.

## Out of Scope

- Entity-centric memory (`entities/<name>.md`) — deferred (Tier-2, own spec).
- Leiden communities, cAST chunking, HippoRAG query-time PPR walk, FlashRank
  re-ranking — Tier-2 roadmap, not this sprint.
- SCIP/LSP integration spike, def-use data-flow edges, issue/PR→code edges —
  radar items from the landscape report.
- Wiki deep rework (auto-update hooks, new article structure, GraphRAG search
  mode) — only staleness + decisions + confidence docs are in scope.
- gitleaks CI gate over `.memory-bank/` — separate ops task.
- New language extractors (Kotlin/Swift/C++/...) — separate track.
