# Tasks: tier1-graph-memory

> Numbered, checkbox-tracked work items. Each task references the
> REQ-IDs it satisfies via the Covers field.
>
> Execution: 3 sprints by group — A: tasks 1-6 (`--range 1-6`),
> B: tasks 7-13 (`--range 7-13`), C: tasks 14-17 (`--range 14-17`).
> Groups are independent; tasks inside a group are dependency-ordered.

<!-- mb-task:1 -->
## Task 1: RRF merge module

**Covers:** REQ-001
**Role:** developer

**What to do:**
- New `memory_bank_skill/rrf.py`: `rrf_merge(rankings, k=60) -> list[(key, score)]`,
  score = Σ 1/(k+rank), deterministic tie-break `(score desc, key asc)`.
- Pure stdlib, no I/O; handles empty lists and single-ranking input.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_rrf.py`: fusion math against hand-computed scores;
  item in one ranking only; identical rankings; empty inputs; determinism
  (two runs → identical order); k parameter effect.

**DoD:**
- [x] `rrf_merge` returns hand-verifiable RRF scores (scenario 2 math)
- [x] empty/one-ranking inputs degrade without error
- [x] tests pass
- [x] lint clean

<!-- mb-task:2 -->
## Task 2: RRF as the auto-backend default in code search

**Covers:** REQ-001, REQ-002
**Role:** developer

**What to do:**
- `memory_bank_skill/semantic_search.py::run_search`: backend `auto` +
  embeddings available → compute BM25 AND embedding rankings, fuse via
  `rrf_merge`; embeddings unavailable → pure BM25 unchanged (fail-open).
- `--backend bm25|embeddings` keep exact single-backend semantics.
- Keep module ≤400 lines (extract helpers into `rrf.py` side if needed).

**Testing (TDD — tests BEFORE implementation):**
- Extend `tests/pytest/test_semantic_search*.py`: scenario 1 (no
  sentence-transformers → BM25-only, exit 0); scenario 2 (both backends →
  fused order, deterministic across two runs); explicit backends unchanged
  (regression).

**DoD:**
- [x] scenarios 1-2 implemented as tests and green
- [x] explicit `--backend` paths byte-identical to 5.0.x output (regression test)
- [x] tests pass
- [x] lint clean

<!-- mb-task:3 -->
## Task 3: Import-aware call resolution (Python extractor)

**Covers:** REQ-003, REQ-004
**Role:** developer

**What to do:**
- `memory_bank_skill/codegraph_python.py`: import-binding pass —
  imported name → bind edge to imported definition; unimported ambiguous
  name → suppress; unique project-wide → keep (fallback). Attribute calls
  unchanged.
- Bump per-file cache version so existing graphs rebuild.
- Measure edge delta on this repo (`/mb graph --dry-run` before/after) and
  record numbers in the task report.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_codegraph_import_binding.py`: scenario 3 (ambiguous
  unimported → no edge), scenario 4 (`from b1 import process` → exactly one
  edge to `b1.process`), `import x` + `x.f()` module binding, `as`-alias,
  unique-fallback kept, same-module call unchanged.

**DoD:**
- [x] scenarios 3-4 green
- [x] edge delta on this repo measured and reported (false-edge reduction) — see progress.md 2026-06-12 (incl. honest correction: precision feature, not edge-count reduction)
- [x] cache version bumped; stale cache rebuilds automatically (test)
- [x] tests pass
- [x] lint clean

<!-- mb-task:4 -->
## Task 4: Personalized PageRank god-nodes

**Covers:** REQ-005, REQ-006
**Role:** developer

**What to do:**
- `memory_bank_skill/codegraph_analytics.py`: DiGraph over call/import
  edges, `nx.pagerank(alpha=0.85)`, stable sort, rounded scores;
  `god-nodes.md` ranks by PageRank with degree as secondary column.
- No networkx → degree ranking + one-line install hint (existing pattern).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_codegraph_analytics*.py`: known toy graph → expected
  PageRank order (transitively-important node beats high-degree leaf);
  scenario 5 (no networkx → degree + hint, exit 0); deterministic output
  across runs.

**DoD:**
- [x] toy-graph PageRank order asserted; scenario 5 green
- [x] god-nodes.md format updated + existing doc/contract tests updated in
      the same change
- [x] tests pass
- [x] lint clean

<!-- mb-task:5 -->
## Task 5: Git churn ranking signal

**Covers:** REQ-007
**Role:** developer

**What to do:**
- `memory_bank_skill/codegraph_cochange.py`: derive `churn_30d` per file from
  the existing `git log` pass; emit additive `node-attr` JSONL rows.
- `semantic_search.py`: multiplier `1 + 0.1*log1p(churn_30d)` applied only
  when the attribute exists.

**Testing (TDD — tests BEFORE implementation):**
- pytest with a fixture git repo: file committed 3× in window → `churn_30d: 3`;
  no git / shallow history → attribute absent, ranking unchanged, no error;
  ranking shifts for hot file when attribute present.

**DoD:**
- [x] churn computed from the same git pass (no extra subprocess; assert call count)
- [x] fail-open without git history
- [x] tests pass
- [x] lint clean

<!-- mb-task:6 -->
## Task 6: Community-summary retrieval

**Covers:** REQ-008
**Role:** developer

**What to do:**
- `semantic_search.py`: wiki article in top-3 → append labeled
  "community files" block (≤10 member files). No wiki → no-op.

**Testing (TDD — tests BEFORE implementation):**
- pytest: fixture with wiki article + communities map → expansion block
  present, capped at 10; no wiki → output identical to pre-change (regression).

**DoD:**
- [x] expansion appears only on wiki hits, capped and labeled
- [x] no-wiki path byte-identical (regression test)
- [x] tests pass
- [x] lint clean

<!-- mb-task:7 -->
## Task 7: Per-turn capture upgrade (outcomes + diffstat)

**Covers:** REQ-009
**Role:** developer

**What to do:**
- `hooks/mb-session-turn.sh`: bullet gains `ok|err(N)` (failed tool calls
  from transcript) and aggregate `+A/-B` diffstat (`git diff --numstat`;
  absent outside a repo). Output still flows through `sc_redact_secrets`.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_session_turn.bats` extension: crafted transcript with one
  failed tool call → bullet contains `err(1)`; clean turn → `ok`; non-git
  tmpdir → no diffstat, exit 0; redaction still applied (existing e2e stays
  green).

**DoD:**
- [x] outcome + diffstat in bullets, $0 (no LLM call added)
- [x] non-git and no-jq guards keep exit 0
- [x] tests pass (bats + existing redaction e2e)
- [x] shellcheck clean

<!-- mb-task:8 -->
## Task 8: Structured session summary (schema v2)

**Covers:** REQ-010, REQ-011
**Role:** developer

**What to do:**
- `hooks/mb-session-end.sh`: summarizer input = redacted Live-log bullets +
  outcome signals (not raw transcript tail); prompt enforces sections
  `What changed / Decisions / Open questions / Files`; frontmatter
  `summary_schema: v2`.

**Testing (TDD — tests BEFORE implementation):**
- bats with stubbed `claude` binary: prompt fed to stub contains Live-log
  content and NOT raw-transcript markers; written summary carries
  `summary_schema: v2`; legacy summaries (no flag) still parse in
  `_recent.md` rebuild.

**DoD:**
- [x] summarizer input is the redacted structured log (asserted via stub)
- [x] v2 frontmatter flag present; legacy files unaffected
- [x] tests pass
- [x] shellcheck clean

<!-- mb-task:9 -->
## Task 9: Progressive disclosure + age + fusion in recall

**Covers:** REQ-001, REQ-016, REQ-017, REQ-018, REQ-019
**Role:** developer

**What to do:**
- `hooks/mb-recall.sh` (+ index layer): default = compact index
  (`id · age · summary · source`, one line per hit); `--expand <id>` full
  chunk; `--full` legacy; unknown id → exit non-zero with message.
- Fuse semantic + lexical hits via RRF (replaces fallback-only mode).
- `[SUPERSEDED]` chunks sort after clean hits with `⊘ superseded` label.
- `hooks/mb-semantic-recall.sh`: inject the compact form (token saving).

**Testing (TDD — tests BEFORE implementation):**
- bats: scenario 6 (compact index, no bodies, superseded last), scenario 7
  (unknown id → non-zero + message), `--expand` happy path, `--full` legacy
  output, injection hook emits compact form; token-length budget assertion
  (compact line < 200 chars/hit).

**DoD:**
- [ ] scenarios 6-7 green
- [ ] UserPromptSubmit injection uses compact form
- [ ] tests pass
- [ ] shellcheck clean

<!-- mb-task:10 -->
## Task 10: `/mb recap <sid>`

**Covers:** REQ-020, REQ-021
**Role:** developer

**What to do:**
- New `scripts/mb-recap.sh`: resolve session file (missing → exit 2, no
  writes); stub detection in `progress.md`; one Haiku `claude -p` call
  (anti-recursion env as in `mb-session-end.sh`); replace stub; `recapped`
  frontmatter for idempotency; real entry present → refuse with hint.
- Register in `commands/mb.md` + SKILL.md scripts table.

**Testing (TDD — tests BEFORE implementation):**
- bats with stubbed `claude`: scenario 8 (replace stub → no-op on rerun →
  missing sid exits non-zero, progress untouched); refuse when real entry
  exists; no `claude` binary → hint + no writes.

**DoD:**
- [x] scenario 8 green; progress.md only ever loses the stub line
- [x] command documented (mb.md + scripts table)
- [x] tests pass
- [x] shellcheck clean

<!-- mb-task:11 -->
## Task 11: `/mb conflicts`

**Covers:** REQ-022, REQ-023
**Role:** developer

**What to do:**
- New `scripts/mb-conflicts.sh`: $0 pass — Jaccard token overlap (>0.4)
  across `notes/` + `lessons.md` + recent progress entries, filtered by
  negation/replacement markers (en+ru); print candidate pairs with paths.
- `--judge`: Sonnet subagent per candidate → confirm/reject + suggested
  `[SUPERSEDED]` marker; print-only, never writes.
- Register in `commands/mb.md` + SKILL.md scripts table.

**Testing (TDD — tests BEFORE implementation):**
- bats: scenario 12 (Postgres/MongoDB pair found, $0, exit 0); <2 entries →
  empty exit 0; threshold respected; `--judge` without `claude` → hint,
  candidates still printed.

**DoD:**
- [ ] scenario 12 green with zero LLM calls (assert no `claude` invocation)
- [ ] `--judge` is print-only (no file writes; test asserts)
- [ ] tests pass
- [ ] shellcheck clean

<!-- mb-task:12 -->
## Task 12: `/mb consolidate`

**Covers:** REQ-012, REQ-013, REQ-014
**Role:** developer

**What to do:**
- New `scripts/mb-consolidate.sh`: window `MB_CONSOLIDATE_DAYS` (default 30);
  deterministic clustering (shared files-touched + lexical overlap); ≥2-session
  facts → note candidates; dry-run default; `--apply` writes notes, moves
  session files verbatim → `session/archive/`, archives contiguous progress
  *stubs* verbatim → `progress-archive.md` + pointer, rebuilds `_recent.md`.
- Register in `commands/mb.md` + SKILL.md scripts table.

**Testing (TDD — tests BEFORE implementation):**
- bats: scenario 11 (dry-run → byte-identical bank); `--apply` on fixture
  bank → notes created in 5-15 line format, session files moved verbatim
  (checksum equal), pointer lines appended, `_recent.md` has no dangling
  refs; real progress entries never move (assert).

**DoD:**
- [ ] scenario 11 green; dry-run provably writes nothing
- [ ] verbatim moves verified by checksum; append-only preserved
- [ ] tests pass
- [ ] shellcheck clean

<!-- mb-task:13 -->
## Task 13: supersedes convention + drift checker

**Covers:** REQ-015
**Role:** developer

**What to do:**
- Document `[SUPERSEDED: YYYY-MM-DD -> <ref>]` in `agents/mb-manager.md` +
  `references/metadata.md` (append-new + mark-old, never edit in place).
- New `mb-drift.sh` checker: malformed/dangling SUPERSEDED markers → warning.

**Testing (TDD — tests BEFORE implementation):**
- bats for the drift checker: valid marker → silent; malformed date / missing
  ref → warning, exit code per drift conventions; no markers → silent.

**DoD:**
- [x] convention documented in both files
- [x] drift checker wired into `mb-drift.sh` roster
- [x] tests pass
- [x] shellcheck clean

<!-- mb-task:14 -->
## Task 14: `--sessions` graph layer

**Covers:** REQ-024, REQ-025, REQ-026
**Role:** developer

**What to do:**
- New `memory_bank_skill/codegraph_sessions.py`:
  `extract_session_layer(mb_path, modules)` → session nodes, `worked_on`
  edges (with one-line summary), module `doc` appends (cap 3 per module).
  All strings through `redact_secrets` + `<private>` strip at write time.
- `scripts/mb-codegraph.py`: `--sessions` flag; base output byte-identical
  without it. Privacy note in docs.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_codegraph_sessions.py`: scenario 9 (legacy session file
  with fake `sk-or-…` token → `[REDACTED]` in graph.json, raw token absent);
  edges/doc-appends from fixture sessions; session without files-touched →
  skipped; without `--sessions` → graph byte-identical (regression).

**DoD:**
- [ ] scenario 9 green (e2e: secret never reaches graph.json)
- [ ] base build without flag byte-identical (regression test)
- [ ] embedding corpus picks up doc appends (search finds module by
      work-history query in fixture)
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:15 -->
## Task 15: Wiki staleness — incremental rebuild

**Covers:** REQ-027
**Role:** developer

**What to do:**
- `scripts/mb-wiki.py` (`plan` step) + `memory_bank_skill/wiki_store.py`:
  record graph hash per article in `wiki/index.md`; changed files → changed
  communities → rebuild only those; others `skipped (fresh)`. `--force` =
  full rebuild; no cache → full rebuild.

**Testing (TDD — tests BEFORE implementation):**
- pytest: scenario 10 (only community 7 changed → plan schedules 1 rewrite,
  rest skipped); `--force` schedules all; missing cache → all; index
  records hashes idempotently.

**DoD:**
- [ ] scenario 10 green; staleness check itself is $0 (no LLM in `plan`)
- [ ] `--force` and no-cache paths covered
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:16 -->
## Task 16: Decisions in wiki evidence packs

**Covers:** REQ-028
**Role:** developer

**What to do:**
- `memory_bank_skill/wiki_evidence.py`: `## Decisions` section — deterministic
  match of `notes/` + session summaries against the community's file
  basenames, top-5 lines with source refs.

**Testing (TDD — tests BEFORE implementation):**
- pytest: fixture note mentioning a community file → appears in pack with
  ref; unrelated notes absent; empty notes/ → section omitted, no error.

**DoD:**
- [x] decisions matched deterministically, capped at 5, with refs
- [x] empty/missing notes fail open
- [x] tests pass
- [x] lint clean

<!-- mb-task:17 -->
## Task 17: Docs & 5.1.0 release prep (defaults change + confidence semantics)

**Covers:** REQ-001, REQ-003, REQ-005, REQ-029
**Role:** developer

**What to do:**
- `references/code-graph.md`: confidence band table (0.9/0.7/0.5, <0.5 not
  emitted); `agents/mb-wiki-synthesizer.md` cites the same rubric.
- `docs/concepts/code-graph.md` + `docs/concepts/session-memory.md` + README:
  RRF/import-aware/PPR as new defaults, `--sessions` layer + privacy note,
  recall progressive disclosure, new commands (`consolidate`/`recap`/
  `conflicts`); honest-limits line updated (import-aware Python, name-based
  others).
- `CHANGELOG.md` `[Unreleased]` → `Changed` (defaults) + `Added` entries.

**Testing (TDD — tests BEFORE implementation):**
- Doc-count/contract tests (`test_doc_counts.py`, landing tests) updated and
  green; `mb-spec-validate.sh tier1-graph-memory` passes; link check on
  edited docs.

**DoD:**
- [ ] confidence table single-sourced (reference + synthesizer prompt)
- [ ] all touched docs consistent with shipped behavior (no premature claims)
- [ ] CHANGELOG entries complete for every task in this spec
- [ ] tests pass
- [ ] lint clean
