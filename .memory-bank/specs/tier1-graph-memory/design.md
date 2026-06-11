# Design: tier1-graph-memory

> Spec triple — see also: requirements.md, tasks.md.
> Sources: `reports/2026-06-11_graph-memory-improvements.md`,
> `reports/2026-06-11_competitive-landscape.md`.

## Architecture

Three independent work streams touching two subsystems:

```
Group A (graph quality)          Group B (session memory)        Group C (bridge)
─────────────────────────        ────────────────────────        ─────────────────
semantic_search.py  ──RRF──┐     mb-session-turn.sh (capture)    codegraph_sessions.py (NEW)
codegraph_python.py ─bind──┤     mb-session-end.sh  (summary)    wiki_evidence.py (staleness,
codegraph_analytics.py PPR ┤     mb-recall.sh (disclosure/age)     decisions)
codegraph_cochange.py churn┘     mb-consolidate.sh (NEW)         references/code-graph.md
                                 mb-recap.sh (NEW)                 (confidence docs)
                                 mb-conflicts.sh (NEW)
```

Streams are dependency-ordered internally but independent of each other —
execute/review per group (3 sprints) via `/mb work tier1-graph-memory --range`.

### A1. RRF hybrid retrieval (REQ-001, REQ-002)

- New module `memory_bank_skill/rrf.py` (~40 lines):
  `rrf_merge(rankings: list[list[str]], k: int = 60) -> list[tuple[str, float]]`.
  Pure function; deterministic tie-break by `(score desc, key asc)`.
- `semantic_search.py::run_search` (253 lines today): backend `auto` with
  embeddings available produces BOTH rankings and merges via `rrf_merge`.
  Explicit `--backend bm25|embeddings` keeps single-backend behavior (escape
  hatch doubles as opt-out).
- `hooks/mb-recall.sh` + recall index: same fusion for semantic + lexical
  recall hits (replaces "semantic first, lexical fallback-only").

### A2. Import-aware call resolution (REQ-003, REQ-004)

- `codegraph_python.py` (189 lines): add an import-binding pass before
  emitting `call` edges:
  1. `imports[caller] = {name -> defining_module}` from
     `import x` / `from x import y [as z]`;
  2. a called bare name binds to `imports[caller][name]` when present;
  3. else: exactly one definition project-wide → keep edge (unique fallback,
     preserves recall);
  4. else: suppress (no guessing among homonyms).
  Attribute calls (`obj.method()`) keep current behavior — type inference is
  out of scope (documented limit).
- tree-sitter extractors unchanged this sprint; the binding module is written
  language-agnostic so Go/JS/TS adopt it next.
- Per-file cache version bump so old graphs rebuild automatically.

### A3. Personalized PageRank god-nodes (REQ-005, REQ-006)

- `codegraph_analytics.py` (293 lines): `nx.DiGraph` over call/import edges
  (caller→callee), `nx.pagerank(G, alpha=0.85)`; stable sort
  `(score desc, name asc)`, rounded display scores.
- `god-nodes.md`: PageRank = primary column, degree stays as secondary.
  No networkx → existing degree path + one-line hint (established pattern).

### A4. Git churn signal (REQ-007)

- `codegraph_cochange.py` (171 lines): compute
  `churn_30d[file] = commits touching file in last 30 days` from the same
  `git log` pass (no extra subprocess). Emit additively:
  `{"type":"node-attr","file":...,"churn_30d":N}`.
- `semantic_search.py`: multiplier `1 + 0.1 * log1p(churn_30d)` only when the
  attribute is present (i.e. inside the `--cochange` opt-in).

### A5. Community-summary retrieval (REQ-008)

- `semantic_search.py`: a wiki article scoring in top-3 appends its
  community's member files as a labeled "expanded context" block (cap 10
  files). No wiki → no-op.

### B1. Capture upgrade (REQ-009)

- `hooks/mb-session-turn.sh` (104 lines): per-turn bullet gains `· ok|err(N)`
  (failed tool calls parsed from the transcript) and `· +A/-B` aggregate
  diffstat (`git diff --numstat`, absent outside a repo). Still no LLM, one
  `printf` through `sc_redact_secrets`.

### B2. Structured summary (REQ-010, REQ-011)

- `hooks/mb-session-end.sh` (245 lines): Haiku prompt demands the fixed
  template `### What changed / ### Decisions / ### Open questions /
  ### Files`. Input = redacted Live-log bullets + outcome signals (NOT the
  raw transcript tail) — cheaper and structured. Frontmatter
  `summary_schema: v2` marks new files for consumers (C1 reads it).

### B3. `/mb consolidate` (REQ-012..014) — NEW `scripts/mb-consolidate.sh`

- Window: sessions older than `MB_CONSOLIDATE_DAYS` (default 30) + contiguous
  auto-capture *stub* entries in `progress.md`.
- Pass 1 (deterministic, $0): cluster sessions by shared files-touched +
  lexical overlap; facts recurring in ≥2 sessions → note candidates
  (`notes/` 5-15 line pattern format).
- Dry-run default prints clusters/candidates; `--apply` writes notes, moves
  session files verbatim → `session/archive/`, appends one pointer line per
  batch to `progress.md`, rebuilds `_recent.md`
  (`mb-session-recent-rebuild.sh`).
- `progress.md`: only stub entries may move (verbatim) to
  `progress-archive.md` + pointer; real entries never move in v1.

### B4. supersedes convention (REQ-015)

- Format: `[SUPERSEDED: YYYY-MM-DD -> notes/<file>#<heading>]` appended to
  the old fact.
- Documented in `agents/mb-manager.md` + `references/metadata.md`; validated
  by a new `mb-drift.sh` checker (malformed marker → warning).

### B5. Progressive disclosure + age in recall (REQ-016..019)

- `hooks/mb-recall.sh` (60 lines) + index: stable hit id
  `<source-file-stem>:<chunk-ordinal>`. Default output one line per hit:
  `id · age · one-line summary · source` (~15 tokens). `--expand <id>` prints
  the full chunk; `--full` keeps legacy output (escape hatch).
- Age from frontmatter date/mtime; `[SUPERSEDED]` chunks sort after all clean
  hits with a `⊘ superseded` label.
- `hooks/mb-semantic-recall.sh` (UserPromptSubmit injection) switches to the
  compact form — this is where the ~10× token saving lands.

### B6. `/mb recap <sid>` (REQ-020, REQ-021) — NEW `scripts/mb-recap.sh`

- Resolve `session/<sid>*.md`; missing → exit 2, no writes.
- Stub for that sid found in `progress.md` → one Haiku `claude -p` call (same
  anti-recursion env as `mb-session-end.sh`) renders a full entry; the stub
  line is replaced (the only sanctioned edit: a stub is a placeholder, not
  history). Real entry already present → refuse with hint.
- Idempotency: `recapped` frontmatter flag on the session file.

### B7. `/mb conflicts` (REQ-022, REQ-023) — NEW `scripts/mb-conflicts.sh`

- Pass 1 ($0): token-set Jaccard > 0.4 between entries of `notes/` +
  `lessons.md` + recent progress entries, filtered to pairs with
  negation/replacement markers (`not|no longer|instead|replaced|moved to|
  deprecated|вместо|перешли|больше не`). Output: candidate pairs with paths.
- `--judge`: one Sonnet subagent per candidate confirms/rejects + suggests
  `[SUPERSEDED]` marker text. Prints suggestions only — never auto-writes.

### C1. `--sessions` graph layer (REQ-024..026) — NEW `memory_bank_skill/codegraph_sessions.py`

- Input: `session/*.md` frontmatter (files touched) + `### What changed`
  summary (schema v2 from B2; falls back to first Live-log bullet).
- Emits additive JSONL (same style as co-change):
  `{"type":"node","kind":"session","id":"session:<sid>","date":...}`,
  `{"type":"edge","kind":"worked_on","src":"session:<sid>","dst":"<module>","summary":"..."}`.
- Appends `| sessions: <summary> (<date>)` to touched module nodes' `doc`
  (cap: last 3 sessions per module) — feeds the embedding corpus, so local
  embeddings match work-history queries ("where did we fix the token leak?").
- All session-derived strings pass `redact_secrets` + `<private>` stripping at
  graph-write time (import from `hooks/lib/redact.py`).
- Opt-in `--sessions` on `mb-codegraph.py`; base output byte-identical
  without it. Docs carry a privacy note (graph.json is committable).

### C2. Wiki staleness (REQ-027)

- `mb-wiki.py plan`: `wiki/index.md` records the graph hash per article; the
  per-file SHA256 cache identifies changed files → changed communities.
  Unchanged community → `skipped (fresh)` in the dispatch plan. `--force`
  rebuilds all. Cache absent → full rebuild (safe default).

### C3. Decisions in evidence packs (REQ-028)

- `wiki_evidence.py` (92 lines): pack gains `## Decisions` — deterministic
  grep of `notes/` + session summaries for the community's file basenames,
  top-5 lines with source refs. $0.

### C4. Confidence semantics (REQ-029)

- `references/code-graph.md`: table — `0.9` explicit shared contract/protocol;
  `0.7` same domain concept, indirect evidence; `0.5` plausible thematic link;
  `<0.5` not emitted. `mb-wiki-synthesizer.md` prompt cites the same rubric.

## Interfaces

```python
# memory_bank_skill/rrf.py
def rrf_merge(rankings: list[list[str]], k: int = 60) -> list[tuple[str, float]]:
    """Fuse N rankings; score(item) = sum(1/(k+rank_i)). Deterministic."""

# memory_bank_skill/codegraph_python.py (internal pass)
def bind_calls(calls: list[Call], imports: dict[str, dict[str, str]],
               definitions: dict[str, list[str]]) -> list[Edge]:
    """Import-bound > unique-fallback > suppressed."""

# memory_bank_skill/codegraph_sessions.py
def extract_session_layer(mb_path: Path, modules: set[str]) -> SessionLayer:
    """SessionLayer(nodes, edges, doc_appends) — all strings pre-redacted."""
```

```bash
# New scripts (all: dry-run default where mutating, --help, exit 0/1/2)
mb-consolidate.sh [mb_path] [--apply] [--days N]
mb-recap.sh <sid> [mb_path]
mb-conflicts.sh [mb_path] [--judge] [--threshold 0.4]
mb-recall.sh <query> [--expand <id>] [--full] [-k N]   # extended
```

## Decisions

1. **Defaults (user decision 2026-06-11):** RRF / import-aware / PPR ship as
   new defaults in **5.1.0** (CHANGELOG `Changed` + cache version bump).
   `--sessions` and churn stay opt-in. Rationale: precision is a quality fix;
   session traces in a committable artifact are a privacy choice.
2. **Import binding is Python-first.** Reusable binding module; tree-sitter
   languages adopt next. Honest-docs line updated (import-aware for Python,
   name-based elsewhere).
3. **Stub replacement ≠ history rewrite.** `/mb recap` replaces auto-capture
   *stubs* only; real progress entries are immutable; consolidate moves
   verbatim only. Append-only invariant survives.
4. **RRF replaces the "semantic-first, lexical-fallback" mode boundary** in
   recall — fusion is strictly better and removes a concept users had to
   learn.
5. **No new required deps** (NFR-001): new scripts are bash + python3 stdlib,
   matching existing patterns; LLM only inside explicitly invoked commands.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Import binding drops true edges on dynamic code (re-exports, decorators) | M | M | unique-fallback rule; DoD measures edge delta on this repo; documented limit |
| PPR reorders god-nodes.md, breaking doc-count/contract tests | H | L | update tests/docs in the same task |
| Recall ids shift after reindex (chunk ordinals) | M | L | ids documented as session-scoped hints, not permalinks (v1) |
| Consolidate moves files (destructive-adjacent) | M | H | dry-run default; bats test asserts byte-identical dry-run; verbatim moves; `--apply` gate |
| `claude` CLI absent for recap/judge | M | L | same guard as mb-session-end.sh: exit with hint, no writes |
| Sprint size (~16 tasks) blows context | M | M | 3 independent groups; `/mb work --range` per group; each task ≤ one 200k context |
| Session summaries leak secrets into committable graph.json | L | H | REQ-026 write-time redaction + `<private>` strip; scenario 9 e2e test |
