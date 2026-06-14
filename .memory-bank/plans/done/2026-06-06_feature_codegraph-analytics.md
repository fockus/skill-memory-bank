---
type: feature
topic: codegraph-analytics
status: done
created: 2026-06-06
---

## Result (2026-06-06)

Shipped Tier 1. New pure module `memory_bank_skill/codegraph_analytics.py` (293 L)
+ `tests/pytest/test_codegraph_analytics.py` (19 tests). `scripts/mb-codegraph.py`
delegates degree/rendering (674→660 L, shrank). `god-nodes.md` now splits Top
symbols / Top modules and adds Communities (cohesion) + Bridge files (betweenness)
when networkx present; `graph.json` nodes carry `community` ids. networkx is an
optional dep (mb-deps-check.sh). Verified: 40 codegraph tests + full suite (959)
green, ruff clean, dogfooded on FaberlicApp (77 communities; abstractions now
surface above test-module hubs), `mb-graph-query` backward-compatible.

Follow-ups (not in scope): git co-change edges, `--semantic` LLM code↔docs layer,
import name-resolution, extract tree-sitter block out of mb-codegraph.py (still
660 L > 400 gate — pre-existing).

# Feature — Code-graph analytics layer (ports from graphify)

Bring deterministic graph-analytics from `graphify` into the MB code-graph,
preserving MB's contract: **deterministic, $0, zero *required* deps, graceful
degradation**. `networkx` is an *optional* dep (mirrors the tree-sitter pattern).

## Scope (Tier 1 only)

IN: file-level community detection (module clusters), per-community cohesion,
file-level betweenness (bridge files), god-node ranking split (modules vs symbols).
OUT (follow-ups): LLM/semantic code↔docs edges, git co-change edges, HTML viz,
import name-resolution. Captured as ideas, not built here.

## Design

- New pure module `memory_bank_skill/codegraph_analytics.py` (no I/O). Keeps the
  already-oversized `scripts/mb-codegraph.py` from growing; SRP-clean, unit-testable.
- `scripts/mb-codegraph.py` delegates degree + rendering to the new module
  (net: it shrinks, not grows).
- networkx optional: present → communities + betweenness; absent → those sections
  omitted with a one-line note, god-node split + degree still work.

## Stages

### Stage 1 — pure analytics module (TDD)
DoD (SMART):
- `tests/pytest/test_codegraph_analytics.py` written FIRST, fails before impl.
- `memory_bank_skill/codegraph_analytics.py` (< 400 lines) implements:
  `compute_degree`, `build_file_graph`, `detect_communities` (None w/o networkx),
  `file_cohesion`, `file_betweenness` (None w/o networkx), `split_god_nodes`,
  `render_god_nodes_md`.
- All new tests green; determinism via `seed=42` + name tie-breaks.
Edge cases: empty graph; isolated files; over-ambiguous names (defined in >8 files)
skipped; networkx absent (monkeypatch) → None paths; single-file community cohesion=1.

### Stage 2 — wire into mb-codegraph.py (behaviour-preserving)
DoD:
- `graph.json` node lines gain optional `community` field (still valid JSON Lines).
- `god-nodes.md` shows **Top modules** + **Top symbols** + **Communities** (size +
  cohesion) + **Bridge files** (betweenness); without networkx → only the splits.
- Existing 21 codegraph tests stay green (backward compat).
- `summary`/stdout gain `communities=N`.

### Stage 3 — verify + deps + docs
DoD:
- Full `pytest tests/pytest/test_codegraph*.py` green.
- `mb-deps-check.sh` lists `networkx` as optional (advisory, never blocks).
- Dogfood on a real repo (`/mb graph --apply`) — outputs render correctly.
- SKILL.md `graph` doc updated (new sections + optional networkx).
