---
tags: [session-memory, code-graph, testing, governed-work]
importance: medium
created: 2026-07-15
---

# Session-memory + graph hardening — patterns

Plan `2026-07-15_feature_session-memory-graph-hardening` (9 stages) shipped via
governed `/mb work` implement→verify (Sonnet implement · mb-test-runner independent
verify · review off). Reusable lessons:

- **Chunker must respect Live-log bullet structure.** `chunk_markdown` split on `\n\n`
  paragraphs, so a bulleted `## Live log` (no blank lines) became one giant paragraph;
  `_split_long` broke it on spaces and `_pack` char-slice overlap started chunks
  mid-path (`rs/fockus/…`). Fix: split on `^- HH:MM` boundaries + bullet-aware overlap.
  Any bullet/line-structured markdown needs boundary-aware chunking, not blank-line-only.

- **Recall drops dangling hits fail-open.** A pruned source keeps its embedding → `age:"?"`
  row. Filter in `_build_hits` only when `mb.is_dir()` (bogus base path keeps all).

- **`sc_semantic_py` prefers an ABSOLUTE `hooks/.venv/bin/python`.** PATH-stripping cannot
  simulate "no python" when a local `hooks/.venv` exists → a fail-open test flaked
  (`reindex=1`). Fix: honor `MB_SEMANTIC_PY` override in the resolver; tests pin it to a
  non-runnable path so the `command -v` guard fails-open deterministically. Never simulate
  "interpreter absent" by PATH alone in this repo.

- **Graph adoption needs reachable freshness.** Role files pointed at `/mb context`'s graph
  line, but a dispatched agent has no `/mb context` → dead check. Self-contain via
  `mb-graph-query.py status`. Applies to ALL role agents incl. `plan-verifier.md`.

See `reports/2026-07-15_review_session-memory-graph.md` (root-cause review) and
`plans/done/2026-07-15_feature_session-memory-graph-hardening.md`.
