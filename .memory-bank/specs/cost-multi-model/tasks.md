---
type: spec-tasks
topic: cost-multi-model
status: ready
created: 2026-05-24
linked_design: design.md
linked_requirements: requirements.md
---

# Tasks: Cost multi-model role assignment

Executable task list for traceability. Detailed implementation steps remain in the linked plan file when one exists.

<!-- mb-task:1 -->
### Task 1: Aliases table and resolver script

**Covers:** REQ-130, REQ-131, REQ-132
**Role:** developer

Testing: bats verifies role lookup, project override precedence, deprecated alias warnings, and fallback output.

**DoD:**
- [ ] `references/model-aliases.yaml` exists.
- [ ] `scripts/mb-model-resolve.sh` returns the expected model id or default marker.

<!-- mb-task:2 -->
### Task 2: Default model matrix and agent metadata

**Covers:** REQ-130, REQ-131
**Role:** architect

Testing: pytest verifies every shipped role has a resolvable model alias.

**DoD:**
- [ ] `references/pipeline.default.yaml` documents role model defaults.
- [ ] Agent frontmatter or role config references aliases, not hard-coded frontier ids.

<!-- mb-task:3 -->
### Task 3: Wire dispatch sites

**Covers:** REQ-130, REQ-133
**Role:** developer

Testing: bats stubs host capabilities and verifies model parameter pass-through or fallback logging.

**DoD:**
- [ ] Work/review/verify dispatch sites call the resolver.
- [ ] Unsupported host behavior is deterministic and documented.

<!-- mb-task:4 -->
### Task 4: Docs, changelog, and calibration validation

**Covers:** REQ-131, REQ-132, REQ-133
**Role:** analyst

Testing: docs checks validate alias examples and migration notes.

**DoD:**
- [ ] User docs explain aliases, overrides, host fallback, and cost trade-offs.
- [ ] `CHANGELOG.md` records that defaults remain backward-compatible unless enabled.
