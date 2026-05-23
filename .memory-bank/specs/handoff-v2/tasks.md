---
type: spec-tasks
topic: handoff-v2
status: ready
created: 2026-05-24
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Handoff 2.0

Executable task list for traceability. Detailed implementation steps remain in the linked plan file when one exists.

<!-- mb-task:1 -->
### Task 1: Handoff capsule writer and template

**Covers:** REQ-120
**Role:** developer

Testing: bats verifies capsule creation, freshness metadata, and atomic write behavior.

**DoD:**
- [ ] Capsule writer records now, done, blockers, next step, and pointers.
- [ ] Latest symlink or copy is updated idempotently.

<!-- mb-task:2 -->
### Task 2: PreCompact and SessionStart integration

**Covers:** REQ-120, REQ-121
**Role:** developer

Testing: bats simulates PreCompact and SessionStart with fresh and stale capsules.

**DoD:**
- [ ] PreCompact writes a capsule without blocking compaction on failure.
- [ ] SessionStart prefers a fresh capsule and falls back cleanly.

<!-- mb-task:3 -->
### Task 3: Mandatory done gates

**Covers:** REQ-122, REQ-123
**Role:** qa

Testing: bats covers green gates, red tests, rule violations, placeholder hits, and force reason logging.

**DoD:**
- [ ] Done command invokes tests, rules, and placeholder scan.
- [ ] Force bypass records a reason in progress history.

<!-- mb-task:4 -->
### Task 4: Progress hash chain and drift check

**Covers:** REQ-124
**Role:** developer

Testing: pytest verifies chain update and drift failure when historical progress content is modified.

**DoD:**
- [ ] `index.json` stores progress chain metadata.
- [ ] `mb-drift.sh` reports tampering as a critical drift.

<!-- mb-task:5 -->
### Task 5: Docs and integration verification

**Covers:** REQ-120, REQ-121, REQ-122, REQ-123, REQ-124
**Role:** analyst

Testing: docs checks verify command references and handoff lifecycle sections.

**DoD:**
- [ ] User docs explain capsule lifecycle, done gates, force semantics, and hash-chain limits.
- [ ] `CHANGELOG.md` lists the handoff-v2 behavior behind its config gate.
