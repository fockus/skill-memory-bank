---
type: feature
topic: agent-retrieval-routing
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — no QA target
created: 2026-11-25
---
# Plan: feature — agent-retrieval-routing

**Baseline commit:** c0e56506df71bd1d066ff77870382797a4bf611b

## Context

**Problem:** The multilingual retrieval experiment required a separate script. Agent-facing tools cannot express the tested query, and the old prompt only suggests looking up code.

**Expected result:** A model can use its own English paraphrase of the user's question to find source files, independently open them and substantiate its answer (AGR-112).

**Related files:**
- `scripts/mb-code-context.py`, `adapters/pi_native_graph.mjs`, `adapters/_lib_agents_md.sh`, `agents/mb-tooling-core.md`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Wire retrieval options through real agent entry points and verify their use

**Files:** `scripts/mb-code-context.py`, `scripts/mb_code_context_core.py`, `adapters/`, `SKILL.md`, `AGENTS.md`, `agents/mb-tooling-core.md`, agent routing guidance and associated tests.

**What to do:**
- Add optional `--search-query` and `--source-only` (`searchQuery`, `sourceOnly` in Pi). Keep the original question for evidence. For implementation use up to 50 provider hits and keep the first hit per non-test file. Leave unfiltered and exact structural queries available.
- Put actionable first-call and read-before-answer guidance in generated and local AGENTS.md and the installed agent prompts. Fallback to graph/text and source reads when RAG is unavailable; no automatic index/model setup.

**Testing (TDD — tests BEFORE implementation):**
- Exercise duplicate chunks, test intent, identifier preservation at the caller, absent/stale search, native-to-CLI forwarding and installer-owned instructions in a temporary project.

**DoD (Definition of Done):**
- [x] CLI routing, local setup and status: 70 targeted tests passed after the subdirectory fix. Pi called the CLI without a bank; OpenCode root-only notification, no repeat after idle, and installer refresh/uninstall were exercised. CI lint passed; standalone JS type checking has 41 pre-existing diagnostics.
- [x] Blind Qwen3 acceptance: 16 Russian-only inputs, agent-authored English queries recorded before retrieval, 16 CLI calls and 16 source excerpts checked against disk. Expected file top-1 8/16, top-5 14/16 (target 10/16; misses H04, H09). Audit: `mb-routing-eval-zIq1sX/{questions,scoring,paraphrases,results}.json` and `raw/`.
- [x] `mb-graph.sh who-calls project_candidates` returned `build_evidence`. Installed global instructions include discovery/routing on all five tested hosts and preserve at least 1 KB of prompt headroom.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

<!-- mb-stage:2 -->
### Stage 2: Project onboarding and actionable release notices (AGR-113)

**Files:** project RAG lifecycle and CLI, existing release notifier, skill entry points and generated agent instructions.

**DoD:**
- [x] Read-only status covers all five states including broken/missing artifacts. Installed global and project instructions offer setup or repair only when appropriate; ready routes directly to retrieval. Non-Git and read-only behavior covered by CLI tests.
- [x] Installed Claude startup hook rendered both fixture versions, the pipx command and invitation. Current version: zero output. Unknown install asks for the installation method. Notifier/resolver/flavor tests: 132 passed, one expected skip; transport checked on Claude, Codex, Cursor, Pi and OpenCode.
- [x] Isolated wheel in a separate two-file Git checkout: no bank; Qwen3 `unconfigured → ready`, from `nested/` semantic hit `recovery.py` first; tracked edit `→ stale`, fallback, explicit update `→ ready`. Logs: `mb-final-installed-GlOT8I/logs/`. Installed notice fixture and hookless guidance checked as above.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Models merely quote instructions or hallucinate paths | M | Verify actual tool output and file reads; the blind question does not provide English translations or answer keys. |

## Gate (plan success criterion)

Verify the changed retrieval contract independently; distinguish measured behavior from instructions or guarantees about arbitrary agents.

**Independent verification: PASS.** Re-ran the three original failures on a freshly built wheel. Pi searched only the nested repository; damaged Qwen3 weights reported `broken` with the correct repair; Pi and Codex delivered the verified offer to root model context without child or compact repeats. 17 packaged files matched the checkout. The verifier exercised real retrieval and host inputs, not generated replies on every host. Evidence: `mb-routing-recheck-YhiU1b/`.
