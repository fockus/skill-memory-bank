---
type: spec-tasks
topic: reviewer-2.0
status: ready
created: 2026-05-24
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Reviewer 2.0

Executable task list for traceability. Detailed implementation steps remain in the linked plan file when one exists.

<!-- mb-task:1 -->
### Task 1: Build review payload orchestrator and cache helpers

**Covers:** REQ-100, REQ-102
**Role:** developer

Testing: bats verifies SHA stability, TTL cache hits and misses, and help output.

**DoD:**
- [x] `scripts/mb-review.sh` exists and emits a deterministic payload.
- [x] Cache helper stores touched-file test evidence under `.memory-bank/tmp/`.
- [x] Focused bats tests pass.

<!-- mb-task:2 -->
### Task 2: Implement layered rubric example loading

**Covers:** REQ-101
**Role:** developer

Testing: bats verifies precedence, max-count truncation, and deterministic rotation.

**DoD:**
- [x] Bundled common/python/go examples exist.
- [x] Project override wins on duplicate `example_id`.
- [x] Loader degrades to an empty examples section without crashing.

<!-- mb-task:3 -->
### Task 3: Complete stack example baseline

**Covers:** REQ-101
**Role:** analyst

Testing: bats verifies every supported stack loads at least three examples and category coverage is balanced.

**DoD:**
- [x] TypeScript/frontend/mobile/backend examples exist.
- [x] Every reviewer category has at least three examples across the pool.

<!-- mb-task:4 -->
### Task 4: Inject test evidence and auto-findings

**Covers:** REQ-102, REQ-103
**Role:** developer

Testing: bats validates green-test payloads omit auto-findings and red-test payloads contain a blocker tests issue.

**DoD:**
- [ ] Payload sections appear in fixed order.
- [ ] Red tests force a blocker finding before LLM review.

<!-- mb-task:5 -->
### Task 5: Wire reviewer agent and work command

**Covers:** REQ-100, REQ-103, REQ-105
**Role:** developer

Testing: bats stubs reviewer output and verifies dropped auto-findings are restored before severity gate.

**DoD:**
- [ ] `commands/work.md` review stage assembles the payload via `scripts/mb-review.sh`, then dispatches the
      pipeline-resolved reviewer (`codex-cli` default, `mb-reviewer` fallback) — NOT a hard-coded `Task → mb-reviewer`.
- [ ] Reviewer output is normalized via `mb-work-review-parse.sh --external`; the dropped-auto-finding post-validation
      hooks onto that normalizer (no second parser).
- [ ] `agents/mb-reviewer.md` consumes one assembled payload and emits JSON only (fallback path).
- [ ] Existing severity-gate tests still pass.

<!-- mb-task:6 -->
### Task 6: Ship calibration suite and docs

**Covers:** REQ-104, REQ-105
**Role:** qa

Testing: calibration runner validates fixture cases without live LLM calls; docs links resolve.

**DoD:**
- [ ] `tests/calibration/run.sh` exists with at least five cases.
- [ ] Non-blocking scheduled workflow is documented.
- [ ] `CHANGELOG.md` describes compatibility and migration notes.
