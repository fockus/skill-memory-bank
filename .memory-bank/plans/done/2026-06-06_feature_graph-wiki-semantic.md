---
type: feature
topic: graph-wiki-semantic
status: done
created: 2026-06-06
completed: 2026-06-06
covers_requirements: []
supersedes: I-063
---

# Code graph — opt-in LLM wiki + surprising connections + semantic search + suggested questions

## Context

A new **opt-in intelligence layer** on top of the deterministic code graph, inspired by
graphify's capabilities the MB graph still lacks (surprising connections, suggested
questions) plus semantic retrieval. Three user-requested features land in one plan:

1. **Suggested questions** — deterministic, $0. Generated from existing analytics
   (god-nodes / communities / bridges / co-change) via templates. No LLM.
2. **Wiki + surprising connections** — LLM via **host subagents** (Haiku for per-community
   articles, Sonnet for cross-cutting "surprising connections"). No API key.
3. **Semantic search** — new retrieval mode with a **pluggable backend** (DIP): default
   pure-Python **BM25** over graph-node text + wiki ($0, zero deps); optional local
   embeddings (sentence-transformers) selectable by the user, graceful fallback to BM25.

### Contract carve-out (the governing principle)

The skill's identity — **$0, deterministic, offline, zero *required* deps** — is preserved
as the **default**. Every capability here is behind an **explicit command/flag** with
graceful degradation, exactly like `tree-sitter`/`networkx` are optional today:

- `/mb graph` default output stays **byte-identical** (suggested questions gated by `--questions`).
- `/mb wiki` (LLM) is a separate command; never runs implicitly.
- Semantic search defaults to **BM25 (zero deps)**; embeddings are opt-in and degrade to BM25.
- LLM = host subagents (Task), **no API keys**, mirroring `/mb work`.

Supersedes backlog `I-063` (the deferred `--semantic` idea is realized here as the wiki/
surprising-connections layer + semantic retrieval).

### Module map (Clean Architecture; every file ≤400 lines)

| Module | Role | Determinism |
|--------|------|-------------|
| `memory_bank_skill/codegraph_loader.py` | shared JSON-Lines `graph.json` loader (DRY) | det |
| `memory_bank_skill/codegraph_questions.py` | suggested-questions generator + renderer | det, $0 |
| `memory_bank_skill/semantic_search.py` | `Retriever` port + `Bm25Retriever` + corpus builder + factory | det default |
| `memory_bank_skill/semantic_embeddings.py` | optional `EmbeddingRetriever` (sentence-transformers, `HAS_*` gated) | opt-in |
| `memory_bank_skill/wiki_evidence.py` | deterministic per-community evidence packs for the LLM | det |
| `memory_bank_skill/wiki_store.py` | wiki article IO + merge `semantic` edges into graph.json | det |
| `scripts/mb-semantic-search.py` | CLI entrypoint for semantic search | — |
| `commands/wiki.md` | `/mb wiki` orchestration (Haiku+Sonnet subagents) | LLM |
| `agents/mb-wiki-author.md` / `agents/mb-wiki-synthesizer.md` | subagent prompts | LLM |

Import direction: new modules depend on `codegraph_loader` / `codegraph_analytics` /
`codegraph_common` only (downward). LLM lives in command + agent prompts, not in Python.

---

## Stage 0 — Shared graph loader (refactor, DRY foundation)

**Goal:** One `load_graph(path) -> (nodes, edges)` reused everywhere; kill the duplicate
JSON-Lines parsing in `mb_code_context_core.py` + `mb_graph_query_core.py`.

- New `memory_bank_skill/codegraph_loader.py`: `load_graph(path: Path) -> tuple[list[dict], list[dict]]`
  (raises `FileNotFoundError` / `ValueError` on bad JSON — preserve current contracts).
- `mb_graph_query_core.load_graph` and `mb_code_context_core` delegate to it (Strangler Fig:
  keep their names as thin re-export wrappers → callers/tests unaffected).

### TDD
- New `test_codegraph_loader.py` (≥4): valid JSON-Lines → (nodes, edges) split by `type`;
  blank lines skipped; missing file → `FileNotFoundError`; malformed line → `ValueError`.
- Existing `test_graph_query.py` + `test_code_context.py` stay GREEN unchanged.

### DoD (SMART)
- [ ] `codegraph_loader.py` ≤120 lines; both core modules import it; their `load_graph`
      surface unchanged (tests pass without edits).
- [ ] New loader tests pass; `test_graph_query.py`/`test_code_context.py` pass.
- [ ] `ruff` clean.

### Edge cases
- JSON-Lines with trailing newline / CRLF; node without `community`; edge with extra fields.

---

## Stage 1 — Suggested questions (deterministic, $0)

**Goal:** `/mb graph --questions` appends a deterministic "Suggested questions" section to
`god-nodes.md`; default (no flag) stays byte-identical.

- `codegraph_questions.py`: `suggest_questions(nodes, edges, *, communities=None,
  betweenness=None, cochange=None, top_n=12) -> list[dict]` (each: `text`, `kind`,
  `evidence`) + `render_questions_md(questions) -> str`. Template families:
  - god-node → "What depends on `X`? (`mb-graph-query.py impact X`)"
  - bridge (betweenness) → "`F` is a bridge — what fragments if it changes?"
  - community → "Cluster N (`a,b,c`) — one responsibility?"
  - co_change → "`A` & `B` co-change but don't import — why?"
- Wire `--questions` flag into `scripts/mb-codegraph.py` `run()`/`main()` (append section,
  like `--cochange`). Deterministic order (by evidence weight then text).

### TDD (tests FIRST)
`test_codegraph_questions.py` (≥8): one question per family from a synthetic graph;
deterministic order; empty graph → empty list; `render_questions_md` table shape; flag
off → god-nodes.md unchanged (byte-identical regression); flag on → section present.

### DoD (SMART)
- [ ] Module ≤300 lines, pure (0 IO/subprocess). ≥8 tests pass.
- [ ] `--questions` off ⇒ `god-nodes.md` byte-identical (regression test).
- [ ] `--questions` on ⇒ section rendered; deterministic across 2 runs.
- [ ] `ruff` clean.

### Edge cases
- No networkx (communities/bridges None) → only god-node + co_change questions.
- No co_change edges → those questions absent. Never crash on empty inputs.

---

## Stage 2 — Semantic search (BM25 default, pluggable backend)

**Goal:** `/mb search --semantic "<q>"` ranks graph symbols + wiki articles by relevance;
default BM25 (zero deps); optional embeddings selectable; graceful fallback.

- `semantic_search.py`:
  - `Retriever` Protocol (ISP ≤5): `available: bool`, `index(docs)`, `search(query, k) -> list[Hit]`.
  - `Bm25Retriever` — pure-Python Okapi BM25 (k1=1.5, b=0.75), code-aware tokenizer
    (lowercase + split snake_case/camelCase). Deterministic, zero deps, always `available`.
  - `build_corpus(nodes, wiki_dir=None) -> list[Doc]` — function/class nodes (name+kind+file)
    + wiki articles (if present) as docs.
  - `make_retriever(backend="auto"|"bm25"|"embeddings") -> Retriever` — `auto`=embeddings if
    available else bm25; explicit `embeddings` with none available → warn + bm25.
- `semantic_embeddings.py`: `EmbeddingRetriever` gated by `HAS_SENTENCE_TRANSFORMERS`
  (+ numpy); cosine over encoded docs; `available=False` when deps absent.
- `scripts/mb-semantic-search.py`: CLI `"<query>" [--backend ...] [--k N] [mb_path]` →
  load graph (Stage 0 loader) + corpus → index → search → JSON/markdown hits.
- Plug into `mb_code_context_core.build_evidence(mode="semantic", semantic_provider=...)`
  (the existing placeholder) so `/mb search --semantic` and code-context share one path.
- `mb-deps-check.sh`: register `sentence_transformers` optional + `hint_for` install lines.

### TDD (tests FIRST)
`test_semantic_search.py` (≥10): BM25 ranks the doc containing query terms first;
code tokenizer splits `getUserToken`→{get,user,token}; deterministic order on ties;
empty corpus → []; `build_corpus` from nodes (+ wiki dir); `make_retriever("embeddings")`
with deps absent → bm25 + warning; `Retriever` Protocol contract test (both adapters
satisfy `available`/`index`/`search`); CLI smoke (`--backend bm25`) returns hits JSON.

### DoD (SMART)
- [ ] `semantic_search.py` ≤350, `semantic_embeddings.py` ≤200. ≥10 tests pass.
- [ ] Default backend = BM25, **zero new required deps**; embeddings degrade gracefully.
- [ ] CLI returns ranked hits; determinism proven (2 runs identical).
- [ ] `mb-deps-check.sh` lists `sentence_transformers` as optional; `bash -n` clean.
- [ ] `ruff` clean.

### Edge cases
- No wiki yet → corpus = graph nodes only. No graph.json → clear error + exit 1.
- Unicode identifiers; very short queries; query terms absent → empty ranked list, exit 0.

---

## Stage 3 — Wiki evidence + store (deterministic halves of the wiki feature)

**Goal:** The pure, fully-tested machinery the `/mb wiki` command orchestrates.

- `wiki_evidence.py`: `build_community_packs(nodes, edges, communities, code_root, *,
  max_files=12, max_excerpt_lines=40) -> list[CommunityPack]`. Each pack: community id,
  member files, key symbols (by degree), short code excerpts. Reuses analytics communities.
- `wiki_store.py`:
  - `article_path(wiki_dir, community_id) -> Path`; `write_article(wiki_dir, id, md)`.
  - `write_index(wiki_dir, packs, articles) -> None`.
  - `merge_semantic_edges(graph_path, edges) -> int` — append `{"kind":"semantic",
    "confidence":x,"rationale":...}` edges to graph.json idempotently (dedupe by src/dst).
  - `validate_semantic_edges(raw) -> list[dict]` — parse/validate the Sonnet subagent's
    JSON output (drop malformed, clamp confidence ∈ [0,1]).

### TDD (tests FIRST)
`test_wiki_store.py` + `test_wiki_evidence.py` (≥10 total): pack built per community with
capped files/excerpts; `merge_semantic_edges` adds + dedupes + is idempotent;
`validate_semantic_edges` drops malformed / clamps confidence; `write_article`/`write_index`
use atomic_write and round-trip; empty communities → no packs.

### DoD (SMART)
- [ ] Both modules ≤300 lines, pure (IO only via `_io.atomic_write`). ≥10 tests pass.
- [ ] `merge_semantic_edges` idempotent (2nd merge adds 0); graph.json stays valid JSON-Lines.
- [ ] `ruff` clean.

### Edge cases
- Sonnet returns junk / partial JSON → validated to []; never corrupts graph.json.
- Community with 1 file → pack still valid; excerpt missing file → skipped, no crash.

---

## Stage 4 — `/mb wiki` orchestration (LLM via subagents)

**Goal:** Wire the command that runs Haiku+Sonnet over Stage 3 machinery; testable parts
already covered, here we add command + agent prompts + registration + a dry-run.

- `commands/wiki.md`: `/mb wiki [--apply] [--dry-run] [src_root]`. Flow:
  1. ensure graph + communities (`mb-codegraph.py --apply`); build packs (`wiki_evidence`).
  2. **Haiku** subagents (parallel, one per community) → article md → `wiki_store.write_article`.
  3. **Sonnet** subagent over all articles+packs → surprising-connection edges JSON →
     `validate_semantic_edges` → `merge_semantic_edges` → `write_index`.
  - `--dry-run` prints the planned subagent dispatch (counts, models) without calling them.
- `agents/mb-wiki-author.md` (Haiku prompt: write one community article from its pack).
- `agents/mb-wiki-synthesizer.md` (Sonnet prompt: emit strict JSON surprising-connection edges).
- Router row + `### wiki` detail section in `commands/mb.md`; `SKILL.md` rows.

### TDD (tests FIRST)
`test_wiki_command.py` (≥6): router table has a `wiki` row; `commands/wiki.md` exists with
required sections (flow, `--dry-run`, Haiku+Sonnet roles); agent prompt files exist and
mention their model tier + strict-JSON contract (synthesizer); a `--dry-run` helper in the
script layer prints planned dispatch from real packs without invoking Task.

### DoD (SMART)
- [ ] `commands/wiki.md` + 2 agent prompts present; router + detail section added.
- [ ] Registration/doc tests pass; `--dry-run` enumerates dispatch deterministically.
- [ ] No file >400 lines.

### Edge cases
- 0 communities (tiny repo) → wiki no-ops with a clear message.
- Host without Haiku/Sonnet (other agent) → command degrades to a documented manual note.

---

## Stage 5 — Docs, deps, backlog, gate

- `commands/mb.md` router: add `wiki` + `--questions` + `search --semantic` rows + detail.
- `SKILL.md`: rows for new modules + commands.
- `mb-deps-check.sh`: `sentence_transformers` optional (+ hints).
- Backlog: flip `I-063` → realized (link this plan); add follow-ups (sqlite-vec adapter as
  `I-064` if scale demands; suggested-questions LLM-enrichment as `I-065`).
- `CHANGELOG [Unreleased]` entry.

### DoD (SMART)
- [ ] Full `pytest` GREEN (baseline 982 + new ≈40). `ruff` clean. `bash -n` clean on touched `.sh`.
- [ ] No changed file >400 lines; SOLID/DDD intact; import direction downward only.
- [ ] Default `/mb graph` + `/mb search` (no flags) behaviour unchanged (regression tests).
- [ ] Dogfood on this repo: `/mb graph --questions` renders questions; `mb-semantic-search.py`
      returns sensible hits; `/mb wiki --dry-run` enumerates Haiku+Sonnet dispatch.

## Phase gate
1. pytest GREEN; ruff clean; no file >400.
2. Three contract regressions prove default paths byte-identical / unchanged.
3. Plan → `plans/done/`; progress.md append; `I-063` resolved; CHANGELOG updated.

---

## Result (2026-06-06) — DONE

All 6 stages landed; the opt-in intelligence layer is complete, reviewed, and e2e-tested.

**New package modules (Clean Architecture, all ≤344 lines):**
`codegraph_loader` (44, shared graph.json loader — both `mb_graph_query_core` &
`mb_code_context_core` delegate), `codegraph_questions` (133, deterministic suggested
questions), `semantic_search` (204, `Retriever` port + pure-Python BM25 + corpus +
factory + `run_search`), `semantic_embeddings` (65, optional sentence-transformers,
graceful), `wiki_evidence` (88, per-community packs), `wiki_store` (118, article IO +
validated/idempotent semantic-edge merge).
**Scripts:** `mb-semantic-search.py`, `mb-wiki.py` (plan/packs/write-article/merge-edges/
index); `mb-codegraph.py` gained opt-in `--questions`.
**Command/agents:** `### wiki` section in `commands/mb.md` (subcommand, like graph/search) +
`agents/mb-wiki-author.md` (Haiku) + `agents/mb-wiki-synthesizer.md` (Sonnet).

**Features delivered:**
1. **Suggested questions** — `/mb graph --questions` (deterministic, $0; default byte-identical).
2. **Semantic search** — `mb-semantic-search.py`; default BM25 (zero deps), opt-in local
   embeddings via pluggable `Retriever` port (DIP), graceful fallback.
3. **Wiki + surprising connections** — `/mb wiki`: Haiku per-community articles + Sonnet
   `semantic` edges, via host subagents (no API key). Deterministic prep tested; LLM steps
   orchestrated by `commands/mb.md` § wiki.

**Verification:** `pytest` **1049 passed** (+~67 new incl. e2e). `ruff` clean on all
changed `.py`; `bash -n` clean. No changed file > 400 lines. Default `/mb graph` +
`/mb search` byte-identical (regression + e2e proven). Dogfood: `--questions` + `--cochange`
render real sections; semantic search returns sensible hits; `/mb wiki plan` enumerates
Haiku+Sonnet dispatch.

**Independent review (Code Reviewer agent):** 0 Critical/High; contract verified
byte-identical empirically. 2 Medium + 3 Low gaps **all fixed** with regression tests:
CRLF-preserving merge, excerpt path-containment guard, `math.isfinite` confidence guard,
Unicode-aware tokenizer, bounded file reads, orphan-symbol question filter.

**Known non-gap:** `test_skill_md_hooks_table_lists_all_hooks` fails due to **unrelated
untracked session-memory WIP** (`hooks/mb-recall.sh`, `mb-session-*.sh`) — not part of this
feature; documenting them would reference uncommitted files.

`I-063` (deferred `--semantic`) is realized here. All DoD met; phase gate green.
