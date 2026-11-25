---
type: feature
topic: bounded-rag-refresh
status: done
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — no QA target
created: 2026-11-25
---
# Plan: feature — bounded-rag-refresh

**Baseline commit:** c0e56506df71bd1d066ff77870382797a4bf611b

## Context

**Problem:** A tracked edit disables semantic results until a manual full rebuild. On the same 4,102-chunk corpus this took 42 minutes with Qwen3 and nearly six hours with Perplexity.

**Expected result:** AGR-114: automatically refresh a configured index when the agent notices a source change, without making an edit, startup or lookup wait for embeddings. First setup and downloads still need consent.

**Related files:**
- `scripts/mb_project_rag.py`, `scripts/mb_rag_{qmd,pplx}.py`, `scripts/mb-rag.py`, `scripts/mb_code_context_core.py`, `references/code-graph.md`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Bounded incremental refresh for an enrolled worktree

**Files:** provider and publication modules, detached scheduling helper, code-context/status entry points, installed guidance, and their respective contract tests.

**What to do:**
- Reuse unchanged embeddings for both providers, remap document IDs after additions/deletions, and atomically switch to the new generation. Leave existing indexes usable after failure.
- Trigger on an agent's startup check or stale retrieval. Coalesce edits until two minutes of quiet, start at most once per 15 minutes per project, and allow a single writer. Keep ordinary `rag status` read-only and `rag update` available immediately.
- Cap automatic work (at most 32 new chunks and three minutes per attempt). If a change needs a larger rebuild, report the explicit command instead of repeatedly starting expensive work. Never provision models from a background job.

**Testing (TDD — tests BEFORE implementation):**
- Offline fixtures for tracked edits/deletes, old indexes, bounded work, concurrent/failed updates, and CLI/search fallback. Time and embedding calls must be observable without waiting for production timers.

**DoD (Definition of Done):**
- [x] Both providers preserve unchanged embeddings; changed/deleted sources and failure isolation are covered by runnable checks. QMD retained `embedded_at` for reused content; ONNX reused rows bit-for-bit (10.42 s for one new unique text in the mini-corpus); 40 scoped tests passed.
- [x] Startup and stale lookup return without waiting; a single bounded worker honors quiet time, cooldown and opt-in. Offline CLI proof covers stale → ready, manual fallback, killing a hung subprocess tree, and empty published indexes (65 scoped tests).
- [x] Generated guidance, public docs, targeted tests, lint and the independent installed-wheel recheck passed.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| A mass checkout or legacy index would re-encode the tree | M | Preflight delta and budget; surface manual update for oversized or unsupported automatic work. |
| Another process edits or publishes during a build | M | Separate writer lock and revalidate before publication; continue graph/text fallback. |

## Gate (plan success criterion)

Pass the three DoD checks above on the working revision; report measured behavior and any verification limits.

Generated prompt checks: 145 targeted pytest checks passed, 3 additional pytest checks and 8 + 14 final Bats regressions passed, including idempotent reinstall and budgets. The project block fits its 1,536-byte cap exactly.

First installed-wheel verification: **FAIL** (`verify-rag.8qARzB/`): broken row-map lookup and QMD's token-split budget. The healthy Qwen3 mini-delta took 5.90 s after worker start.

Independent fresh-wheel recheck: **PASS** (`recheck-bounded.XcTvqx/`). With production timers and network denied, damaged rows before or after scheduling left the pointer intact; exactly 32 vectors were accepted and 36 refused before embedding. A small edit returned live text in 1.18 s and was searchable semantically after 139.62 s including debounce. All 690 wheel hashes verified; 23 installed files matched. Release CI remains separate.
