---
type: feature
topic: codegraph-cochange
status: done
created: 2026-06-06
completed: 2026-06-06
owner: codegraph
covers_requirements: []
---

# Code graph — git co-change edges + module decomposition

## Context

Tier-3 follow-ups to the codegraph analytics layer (commit `56f4711`). Two
contract-preserving wins, ordered by dependency:

1. **Decomposition (refactor, behaviour-preserving).** `scripts/mb-codegraph.py`
   is **660 lines** — violates the project HARD gate (≤400, target ≤300). Two
   coherent SOLID seams: the tree-sitter multi-language adapter (~232 lines) and
   the Python `ast` extractor (~120 lines). Extract both into the
   `memory_bank_skill` package; the script becomes a thin orchestrator (~310).
2. **Git co-change edges (feature, opt-in).** A *unique, deterministic, $0*
   signal MB does not have: files that change together across git history are
   coupled regardless of static imports/calls. Emitted as a new `co_change` edge
   kind, gated behind `--cochange` so default output stays **byte-identical**
   (roadmap cross-phase invariant).

**Out of scope (deferred → backlog `I-063`):** `--semantic` LLM code↔docs layer.
It breaks the core $0 / deterministic / zero-required-deps contract and warrants
its own ADR + plan. Not in this session.

## Contract invariants (every stage must hold)

- `mb-codegraph.py --apply` **without** new flags produces byte-identical
  `graph.json` + `god-nodes.md` as before this plan.
- No new **required** dependency. `git` is already required; `networkx` /
  `tree-sitter` stay optional with graceful degradation.
- Existing script public surface preserved for tests via re-export facade:
  `parse_file`, `build_graph`, `run`, `HAS_TREE_SITTER`, `_get_ts_parser`.
- No file among changed files > 400 lines. All deterministic (seeded / sorted).

---

## Stage 1 — Decompose `mb-codegraph.py` (behaviour-preserving)

**Goal:** Split the 660-line script into orchestrator + 3 package modules with
zero output change, every test green at each atomic step (Strangler Fig).

New modules under `memory_bank_skill/`:

| Module | Moves | ~LOC |
|--------|-------|------|
| `codegraph_common.py` | `sha256`, `rel` (shared helpers) | 25 |
| `codegraph_python.py` | `_Extractor`, `_name_of`, `parse_file` | 145 |
| `codegraph_treesitter.py` | `HAS_TREE_SITTER`, `_TS_*` config, `get_ts_parser`, all `_ts_*`, `parse_ts_file` | 250 |

`scripts/mb-codegraph.py` keeps: cache, gitignore filter, `build_graph`
(dispatches to the two extractors), `_write_graph_jsonl`, `run`, `main`, plus
re-export aliases (`parse_file`, `HAS_TREE_SITTER`, `_get_ts_parser`).

Import direction (no cycles): `common ← {python, treesitter}`;
`{common, python, treesitter, analytics, cochange} ← script`.

### TDD
- No new behaviour ⇒ no new test required first; the **existing** suites are the
  spec. RED-equivalent = run `test_codegraph.py` + `test_codegraph_ts.py` +
  `test_codegraph_analytics.py` after each extraction; they must stay GREEN.
- Add `tests/pytest/test_codegraph_modules.py` (≥4 tests) asserting the new
  package modules import standalone and expose the documented API
  (`codegraph_python.parse_file`, `codegraph_treesitter.HAS_TREE_SITTER`,
  `codegraph_common.sha256`/`rel`) — locks the new contract.

### DoD (SMART)
- [ ] `wc -l scripts/mb-codegraph.py` ≤ 400 (target ≤ 320); every new module ≤ 400.
- [ ] `parse_file`, `build_graph`, `run`, `HAS_TREE_SITTER`, `_get_ts_parser`
      resolve as attributes of the loaded script module (back-compat).
- [ ] `test_codegraph.py`, `test_codegraph_ts.py`, `test_codegraph_analytics.py`
      pass unchanged; new `test_codegraph_modules.py` passes.
- [ ] A `--apply` run on this repo yields a `graph.json` + `god-nodes.md`
      byte-identical to a pre-refactor baseline (diff empty).
- [ ] `ruff check` clean on all changed `.py`.

### Edge cases
- Circular import risk → shared helpers live only in `codegraph_common`.
- `_get_ts_parser` name (underscore) is what the TS test reads → alias exactly.
- Script run both as `__main__` and imported via `spec_from_file_location` → the
  existing `try/except ModuleNotFoundError` sys.path bootstrap must cover all
  new imports.

---

## Stage 2 — Git co-change edges (pure core + integration)

**Goal:** New module `memory_bank_skill/codegraph_cochange.py` computing
deterministic file-coupling edges from git history, fully unit + integration
tested, **before** any wiring.

API (SRP-split for testability):
- `parse_git_log(raw: str) -> list[set[str]]` — pure; split `git log` output into
  per-commit file-sets (NUL-record delimited).
- `count_pairs(commits, known_files, *, min_shared, max_files_per_commit, max_pairs) -> list[tuple[str, str, int]]`
  — pure; co-occurrence counting, threshold, deterministic sort
  `(-count, a, b)`, cap. Only pairs where both endpoints ∈ `known_files`.
- `co_change_edges(src_root, known_files, *, window=200, min_shared=2, max_files_per_commit=25, max_pairs=100) -> list[dict]`
  — runs `git -C … log --no-merges --name-only -n window -z`, maps git-toplevel
  paths → relative-to-`src_root`, returns
  `[{"src": a, "dst": b, "kind": "co_change", "weight": n}]` (a < b).
- `render_cochange_section(edges) -> str` — markdown section for `god-nodes.md`.

### TDD (tests FIRST)
`tests/pytest/test_codegraph_cochange.py` (≥10):
- `parse_git_log`: multi-commit split / empty input → `[]` / trailing record.
- `count_pairs`: pair counted across 2+ commits; below `min_shared` dropped;
  mega-commit > `max_files_per_commit` skipped; both-endpoints-in-known filter;
  deterministic order + `max_pairs` cap; single-file commits → no pairs.
- `co_change_edges` (integration, real `git init` in `tmp_path`): two files
  committed together twice → one weight-2 edge; non-git dir → `[]`; `git`
  missing simulated via PATH/monkeypatch → `[]`; paths returned relative to
  `src_root` and matching node `file` values.
- `render_cochange_section`: table rows for edges; empty edges → graceful note.

### DoD (SMART)
- [ ] Module ≤ 400 lines; pure fns have **0** subprocess/IO (mockless unit tests).
- [ ] ≥10 tests pass; co-change determinism proven (same repo state → identical edges).
- [ ] Graceful: non-git / missing-git → `[]` (no exception).
- [ ] `ruff check` clean.

### Edge cases
- Not a git repo / git binary absent / empty history → `[]`.
- File paths outside `src_root` (git root above src) → mapped or dropped, never crash.
- Renames under `--name-only` (new path only) → counted as the new path; documented.
- Deleted / binary / non-source files → filtered by `known_files` membership.

---

## Stage 3 — Wire `--cochange` + docs + optional-dep parity

**Goal:** Expose the feature opt-in, default output unchanged; update user-facing
docs/contract surfaces.

- `run(..., cochange: bool = False)`: when `True`, after `build_graph`, compute
  `known = {n["file"] …}`, append `co_change_edges(...)` to `graph["edges"]`
  (so they land in `graph.json`), and append `render_cochange_section(...)` to
  the `god-nodes.md` body. When `False` → no git-log call, output byte-identical.
- `main`: add `--cochange` flag (store_true). Print `cochange_edges=N` to summary
  only when enabled.
- Docs: `commands/mb.md` `### graph` Output + router row note the opt-in
  `--cochange`; `SKILL.md` codegraph row mention; plan's contract line in
  `mb-codegraph.py` module docstring.
- Backlog: add `I-063` (deferred `--semantic` layer) so the idea isn't lost.

### TDD (tests FIRST)
Extend `test_codegraph.py` / new cases (≥5):
- Default `--apply` (no flag): graph.json contains **no** `co_change` edge kind;
  output byte-identical to baseline (regression lock for the invariant).
- `--apply --cochange` on a temp git repo with a co-change pattern: graph.json
  gains ≥1 `{"kind":"co_change","weight":…}` edge; god-nodes.md contains the
  co-change section; summary prints `cochange_edges=`.
- `--cochange` outside a git repo → run succeeds, 0 co_change edges (graceful).
- Registration: `commands/mb.md` mentions `--cochange`.

### DoD (SMART)
- [ ] Default-path byte-identical regression test passes.
- [ ] `--cochange` happy-path + non-git graceful path pass.
- [ ] `commands/mb.md` + `SKILL.md` updated; registration test green.
- [ ] `mb-codegraph.py` still ≤ 400 lines after wiring.

---

## Phase gate (this plan)
1. Full `pytest` GREEN (was 959 at session start; expect +~19).
2. `ruff check` clean on all changed `.py`; `bash -n` clean on any touched `.sh`.
3. No changed file > 400 lines; SOLID/DDD structure intact.
4. Default `mb-codegraph --apply` output byte-identical (regression test proves it).
5. `I-063` recorded in backlog. Plan → `plans/done/` + progress.md append.

---

## Result (2026-06-06) — DONE

**Stage 1 — decomposition (behaviour-preserving):** `scripts/mb-codegraph.py`
660 → **326 lines** (under the 400 hard gate). Extracted 3 package modules:
`codegraph_common.py` (24), `codegraph_python.py` (142), `codegraph_treesitter.py`
(251). Back-compat re-exports on the script (`parse_file`, `build_graph`, `run`,
`HAS_TREE_SITTER`, `_get_ts_parser`). **Byte-identical proof:** `graph.json` +
`god-nodes.md` from a fixed fixture diff-identical pre/post refactor.

**Stage 2 — co-change feature:** new pure module `codegraph_cochange.py` (171).
SRP split: `parse_git_log` / `count_pairs` (pure, mockless) + `co_change_edges`
(real-git integration) + `render_cochange_section`. Deterministic, graceful → `[]`
outside git / git-missing.

**Stage 3 — wiring + docs:** opt-in `--cochange` flag in `run`/`main`; default off
keeps output byte-identical. Docs updated (`commands/mb.md` graph section + router
row + `_TS_LANG_CONFIG`→`codegraph_treesitter.LANG_CONFIG` fix; `SKILL.md` row).
`I-063` (deferred `--semantic`) captured in backlog.

**Verification:** full `pytest` **982 passed** (959 → +23: 19 cochange + 4 modules).
`ruff check` clean on all changed `.py`. No changed file > 400 lines. Dogfood on
this repo (`--cochange`): **8 co-change edges**, surfacing impl↔test couplings the
static graph misses (`cli.py↔test_cli.py` w=4, `mb-index-json.py↔test_index_json.py`
w=3) — exactly the intended "signal the static graph cannot see".

All DoD criteria across the three stages met; phase gate green.
