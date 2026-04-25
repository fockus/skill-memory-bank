---
status: done
type: feature
sprint: phase4-sprint3
created: 2026-04-25
closed: 2026-04-25
---

# Phase 4 Sprint 3 — installer auto-register + superpowers reviewer detection + v4.0.0 release

## Context

Final Skill v2 sprint. Phase 3 (config, work, review-loop) and Phase 4 Sprint 1+2 (5 hooks) ship the runtime engine. This sprint puts everything behind `install.sh` so a fresh install lands a fully-wired system, and cuts the v4.0.0 SemVer release.

## Goal

A user running `bash install.sh` after this sprint gets:
- All 5 Sprint 1+2 hooks auto-registered in `~/.claude/settings.json` (idempotent, removable on re-install).
- `superpowers:requesting-code-review` skill detected if installed; `mb-reviewer-resolve.sh` honours `pipeline.yaml:roles.reviewer.override_if_skill_present` and routes review work to it.
- VERSION = `4.0.0`, CHANGELOG `[Unreleased]` cut to `[4.0.0] — 2026-04-25` with full Phase 3+4+I-033 scope.

## DoD (SMART)

- [x] **`settings/hooks.json`** updated: append 5 entries (PreToolUse Write/Edit for protected-paths-guard + ears-pre-write; PostToolUse Write for plan-sync-post-write; PreToolUse Task for context-slim-pre-agent + sprint-context-guard). Each command suffixed `# [memory-bank-skill]` so `merge-hooks.py` strips/re-appends idempotently.
- [x] **`scripts/mb-reviewer-resolve.sh`** created: prints `<reviewer-name>` to stdout. Default `mb-reviewer`. If `pipeline.yaml:roles.reviewer.override_if_skill_present == superpowers:requesting-code-review` AND `~/.claude/skills/superpowers/skills/.../requesting-code-review/` (or `~/.claude/plugins/superpowers/.../requesting-code-review/`) exists → prints `superpowers:requesting-code-review`.
- [x] **`install.sh`** updated:
  - probe section logs whether superpowers reviewer skill is detected (informational).
  - confirm 5 new hooks land in target via existing `for f in hooks/*.sh` loop (no installer changes needed beyond verification).
- [x] **`commands/work.md`** updated: Reviewer dispatch step references `mb-reviewer-resolve.sh` to choose agent name.
- [x] **VERSION** bumped `3.1.2 → 4.0.0`.
- [x] **CHANGELOG.md** `[Unreleased]` cut to `[4.0.0] — 2026-04-25` with Phase 3+4+I-033 summary; new empty `[Unreleased]` section above.
- [x] **Tests**:
  - `tests/pytest/test_hooks_registration.py` — settings/hooks.json contains 5 expected entries with markers; merge-hooks.py with new template produces final state with all 5 + legacy entries.
  - `tests/pytest/test_mb_reviewer_resolve.py` — fallback to `mb-reviewer` when no skill, honours override when both pipeline.yaml flag set + skill dir exists.
  - `tests/pytest/test_phase4_sprint3_registration.py` — VERSION = 4.0.0; CHANGELOG has `[4.0.0]` section; commands/work.md references resolver.
- [x] Full pytest suite green: 596 → 596+N. shellcheck `-x` clean.
- [x] **Plan moved to `plans/done/`** + close-out (status/roadmap/progress).

## Stages

### Stage 1: tests RED (hooks registration + reviewer resolver + release-prep)
Write all 3 test files first. Confirm RED.

### Stage 2: implement hook entries in settings/hooks.json
Append 5 entries with `[memory-bank-skill]` marker.

### Stage 3: implement mb-reviewer-resolve.sh
Bash + small inline python for pipeline.yaml read.

### Stage 4: wire commands/work.md + install.sh probe
Document resolver usage; informational log in installer.

### Stage 5: VERSION bump + CHANGELOG cut
3.1.2 → 4.0.0; cut Unreleased to [4.0.0] — 2026-04-25.

### Stage 6: full regress + close-out
pytest, shellcheck, plan → done/, status/roadmap/progress/lessons updates.
