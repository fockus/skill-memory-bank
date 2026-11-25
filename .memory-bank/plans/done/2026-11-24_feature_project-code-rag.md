---
type: feature
topic: project-code-rag
status: done
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — disabled
created: 2026-11-24
---
# Plan: feature — project-code-rag

**Baseline commit:** c0e56506df71bd1d066ff77870382797a4bf611b

## Context

**Problem:** Russian questions about English source code frequently miss with MiniLM.

**Expected result:** explicit project setup offers Qwen3/QMD or Perplexity ONNX Q4; normal queries consume a local index without fetching weights or rebuilding it.

**Related files:**
- `scripts/mb-code-context.py`, `references/code-graph.md`, AGR-111.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Ship both providers and the project setup/search lifecycle

**Files:** `scripts/mb*rag*`, `memory_bank_skill/cli.py`, `scripts/mb_code_context_core.py`, `references/code-graph.md`, `tests/pytest/test_*rag*`.

**What to do:**
- Implement two independent provider adapters and a shared install/update/search path; publish a new index only after successful initialization. Connect the existing evidence-pack builder; retain explicit candidate and graph-only modes.

**Testing (TDD — tests BEFORE implementation):**
- Test offline selection, project isolation, stale/missing and failed builds; smoke both real models on a tiny disposable Git project.

**DoD (Definition of Done):**
- [x] Both selected models returned `backup.py:1–2` for a Russian query from an installed wheel with network access denied. Queries left the generation unchanged. Stale source fell back to text, and explicit init repaired a partially missing ONNX index.
- [x] All 55 scoped retrieval and evidence-pack tests passed; the independent verifier passed Stage 1.
- [x] CI-scope Ruff and JavaScript syntax checks passed; the scoped rules check found no critical violations.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Large downloads, cross-project leaks or partial updates | M | Select before fetching; isolate cache by project; test failed installation and fallback. |

## Gate (plan success criterion)

Targeted tests, static checks and real offline retrieval for both models, followed by verification against the criteria above.
