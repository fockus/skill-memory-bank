# Requirements: tier1-graph-memory

> Spec triple — see also: design.md, tasks.md.
> Source context: `context/tier1-graph-memory.md` (status: ready, 2026-06-11).
>
> EARS patterns:
> - Ubiquitous:        `The <system> shall <response>`
> - Event-driven:      `When <trigger>, the <system> shall <response>`
> - State-driven:      `While <state>, the <system> shall <response>`
> - Optional feature:  `Where <feature>, the <system> shall <response>`
> - Unwanted:          `If <trigger>, then the <system> shall <response>`

## Requirements (EARS)

### Group A — graph quality & retrieval

- **REQ-001** (event-driven): When a semantic code search runs with backend `auto` and both BM25 and embedding rankings are available, the search engine shall fuse the two rankings with Reciprocal Rank Fusion (k=60) into a single result list.
- **REQ-002** (unwanted): If the embeddings backend is unavailable, then the search engine shall return pure BM25 results without error (fail-open).
- **REQ-003** (event-driven): When the caller module imports the callee symbol or its defining module, the graph builder shall bind the cross-module call edge to that imported definition.
- **REQ-004** (unwanted): If a called name resolves to multiple definitions and none of them is imported by the caller, then the graph builder shall suppress the cross-module call edge unless the name is unique project-wide.
- **REQ-005** (state-driven): While networkx is available, the god-nodes report shall rank symbols and modules by Personalized PageRank over the directed graph, keeping degree as a secondary column.
- **REQ-006** (unwanted): If networkx is not installed, then the god-nodes report shall degrade to degree-based ranking and surface a one-line install hint.
- **REQ-007** (optional): Where `--cochange` is enabled, the graph builder shall record a per-file `churn_30d` count and the search engine shall apply it as a recency ranking signal.
- **REQ-008** (optional): Where the wiki layer is built, the search engine shall expand a top-ranked wiki-article hit with the member files of its community (community-summary retrieval).

### Group B — session memory

- **REQ-009** (event-driven): When the per-turn capture hook fires, the system shall record the turn outcome (success or error signal of tool calls) and a diffstat of touched files in addition to request, tools, and file names.
- **REQ-010** (ubiquitous): The session summary shall follow a fixed section template (What changed / Decisions / Open questions / Files) so downstream consumers can parse it deterministically.
- **REQ-011** (event-driven): When the session-end summarizer runs, the system shall feed it the redacted structured Live log and turn outcomes as primary input instead of the raw transcript tail.
- **REQ-012** (event-driven): When `/mb consolidate --apply` runs, the system shall promote facts recurring across two or more sessions into `notes/`, move consolidated session files verbatim into an archive, and leave pointers behind.
- **REQ-013** (unwanted): If `/mb consolidate` is invoked without `--apply`, then the system shall only print candidates and write nothing (dry-run default).
- **REQ-014** (ubiquitous): The consolidation pass shall move `progress.md` entries verbatim to the archive file and shall never edit an entry's content in place (append-only invariant).
- **REQ-015** (event-driven): When a note or lesson is superseded by a new fact, the manager shall append the new entry and mark the old one with a `[SUPERSEDED: YYYY-MM-DD -> <new-ref>]` tag instead of editing it in place.
- **REQ-016** (event-driven): When `/mb recall` runs without an expand argument, the system shall return a compact index — stable id, one-line summary, and age — instead of full snippets (progressive disclosure).
- **REQ-017** (event-driven): When `/mb recall --expand <id>` is invoked, the system shall print the full snippet and source path for that id.
- **REQ-018** (unwanted): If `--expand` references an unknown id, then the system shall exit non-zero with a clear error message.
- **REQ-019** (ubiquitous): The recall output shall display the age of each hit and shall downrank entries marked `[SUPERSEDED]` below all non-superseded hits.
- **REQ-020** (event-driven): When `/mb recap <sid>` is invoked, the system shall reconstruct a full progress entry from `session/<sid>*.md` via one Haiku subagent call and replace that session's auto-capture stub idempotently.
- **REQ-021** (unwanted): If the referenced session file does not exist, then `/mb recap` shall exit non-zero without writing to `progress.md`.
- **REQ-022** (event-driven): When `/mb conflicts` runs, the system shall report pairs of memory entries with high lexical overlap and opposing assertions as conflict candidates using zero LLM calls.
- **REQ-023** (optional): Where `--judge` is passed, the conflicts command shall confirm or reject each candidate via an LLM subagent and emit suggested `[SUPERSEDED]` markers for confirmed conflicts.

### Group C — session→graph enrichment & wiki

- **REQ-024** (optional): Where `--sessions` is enabled, the graph builder shall emit `worked_on` edges from session nodes to the module nodes of files touched in that session, each carrying a one-line summary attribute.
- **REQ-025** (optional): Where `--sessions` is enabled, the graph builder shall append session-derived work summaries to the `doc` field of touched module nodes so the embedding index matches work-history queries.
- **REQ-026** (ubiquitous): The graph builder shall pass all session-derived content through the secret-redaction pipeline before writing it to `graph.json` (defense-in-depth on top of capture-time redaction).
- **REQ-027** (event-driven): When `/mb wiki` runs against an existing wiki, the system shall rebuild only the articles of communities whose member files changed since the last build and skip unchanged communities.
- **REQ-028** (ubiquitous): The wiki evidence pack shall include decisions relevant to the community's files drawn from `notes/` and session summaries.
- **REQ-029** (ubiquitous): The code-graph reference documentation shall define the meaning of `confidence` values on `semantic` edges.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: RRF degrades to BM25 when embeddings are missing

**Covers:** REQ-001, REQ-002

- GIVEN a built graph and no `sentence-transformers` installation
- WHEN `mb-semantic-search.py "redaction pipeline" --backend auto` runs
- THEN the result list equals the pure-BM25 ranking and the exit code is 0
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: RRF fuses both rankings deterministically

**Covers:** REQ-001

- GIVEN a symbol ranked #1 by BM25 only and another ranked #1 by embeddings only
- WHEN both backends are available and the search runs with backend `auto`
- THEN both symbols appear in the fused top-k with RRF scores `1/(60+rank)` summed across backends, and two consecutive runs return identical order
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: unimported ambiguous call produces no cross-module edge

**Covers:** REQ-003, REQ-004

- GIVEN modules `b1.py` and `b2.py` both defining `process()`, and `a.py` calling `process()` without importing either
- WHEN the graph is built
- THEN no `call` edge from `a.py` to `b1.process` or `b2.process` exists
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: imported call binds to the imported definition

**Covers:** REQ-003

- GIVEN `a.py` containing `from b1 import process` and a call `process()`
- WHEN the graph is built
- THEN exactly one `call` edge `a -> b1.process` exists and none to `b2.process`
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: god-nodes degrade without networkx

**Covers:** REQ-005, REQ-006

- GIVEN an environment where `import networkx` raises ImportError
- WHEN `/mb graph --apply` writes `god-nodes.md`
- THEN the report ranks by degree, contains the install hint line, and the build exits 0
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: recall returns a compact index by default

**Covers:** REQ-016, REQ-019

- GIVEN a session store with 10 indexed entries, one marked `[SUPERSEDED]`
- WHEN `/mb recall "auth tokens"` runs without `--expand`
- THEN the output contains one line per hit with id, one-line summary, and age, contains no full snippet bodies, and the superseded entry ranks below all non-superseded hits
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: expand of an unknown id fails loudly

**Covers:** REQ-017, REQ-018

- GIVEN a recall index that contains no id `zz99`
- WHEN `/mb recall --expand zz99` is invoked
- THEN the exit code is non-zero and stderr names the unknown id
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: recap is idempotent and refuses missing sessions

**Covers:** REQ-020, REQ-021

- GIVEN a session file `session/2026-06-11.md` whose progress entry is an auto-capture stub
- WHEN `/mb recap 2026-06-11` runs twice, and then `/mb recap 2099-01-01` runs
- THEN the first run replaces the stub with a full entry, the second run is a no-op, and the third exits non-zero leaving `progress.md` untouched
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: sessions layer redacts secrets before graph write

**Covers:** REQ-024, REQ-025, REQ-026

- GIVEN a legacy session file containing `sk-or-aaaaaaaaaaaaaaaaaaaaaaaa` in its summary line
- WHEN `/mb graph --apply --sessions` runs
- THEN `graph.json` contains the `worked_on` edge with `[REDACTED]` in its summary and the raw token appears nowhere in `graph.json`
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: wiki skips unchanged communities

**Covers:** REQ-027

- GIVEN a built wiki and a graph rebuild where only community 7's files changed
- WHEN `/mb wiki` runs again
- THEN the dispatch plan schedules a rewrite only for community 7 and reports the others as skipped
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: consolidate dry-run writes nothing

**Covers:** REQ-012, REQ-013, REQ-014

- GIVEN 20 session files older than the consolidation window and a 170KB `progress.md`
- WHEN `/mb consolidate` runs without `--apply`
- THEN candidate clusters are printed, and `session/`, `notes/`, and `progress.md` are byte-identical before and after the run
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: conflicts finds opposing assertions without LLM

**Covers:** REQ-022

- GIVEN one note saying "use Postgres for the ledger" and a later note saying "ledger moved to MongoDB"
- WHEN `/mb conflicts` runs in an environment with no API access
- THEN the pair is reported as a conflict candidate with both file paths and the command exits 0
<!-- /mb-scenario:12 -->
