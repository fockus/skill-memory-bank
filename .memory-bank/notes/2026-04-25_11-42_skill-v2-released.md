---
type: milestone
tags: [release, skill-v2, retrospective]
importance: high
created: 2026-04-25
---

# Skill v2 released as v4.0.0

## What was done

- Phase 4 Sprint 3 (final v2 sprint) merged: installer auto-registration of all 5 v2 hooks (`settings/hooks.json` + idempotent `merge-hooks.py`), `scripts/mb-reviewer-resolve.sh` for pipeline-aware reviewer routing (default `mb-reviewer`, override → `superpowers:requesting-code-review` when skill detected), `commands/work.md` step 3c rewritten to call resolver, `install.sh` step 6.5 informational probe.
- VERSION bumped 3.1.2 → 4.0.0; `CHANGELOG.md [Unreleased]` cut to `[4.0.0] — 2026-04-25` with full Phase 3+4+I-033 scope summary.
- 8 commits pushed to `origin/main`: phase3-sprint1+2+3, phase4-sprint1+2, i-033, prior-artifacts, phase4-sprint3.
- `v4.0.0` annotated tag pushed.
- GitHub release published at <https://github.com/fockus/skill-memory-bank/releases/tag/v4.0.0> with Highlights / Breaking change / Full scope sections.
- `/mb done` close-out: this note + `.session-lock` touch + `index.json` regen + checklist prune (idempotent — file is at 36 lines, well under 120-cap).

## New knowledge

- **Idempotent settings merge as default contract.** `merge-hooks.py` strips every `[memory-bank-skill]`-marked entry before re-appending. Adding 5 entries was a one-file change in `settings/hooks.json` — installer code untouched. Pattern usable for any future skill-managed external config.
- **Resolver indirection > hard-coded agent names.** `mb-reviewer-resolve.sh` decouples `commands/work.md` from a specific reviewer agent. Same pattern can route any role to a plugin agent: declare `override_if_skill_present` in `pipeline.yaml`, ship a tiny resolver, orchestrator dispatches via resolver output. No code change needed when the override target shifts.
- **Per-sprint git history paid off.** 6 standalone commits (one per sprint) made the `v4.0.0` release notes trivial to draft — each commit message was already a CHANGELOG section. `git log --oneline 9a1857a..HEAD` reads as the changelog itself.
- **TDD held across 8 sprints, 280 new tests, zero regressions.** RED-first discipline + small per-stage commits = no debugging cycle longer than ~30 min. Final regression at the end of every sprint always passed cleanly.

## See also

- `plans/done/2026-04-25_feature_phase4-sprint3-installer-and-release.md` — full DoD + retrospective.
- `lessons.md` "rotating artifact without enforcement" — the I-033 pattern (companion script + CI test for any spec-declared lifecycle).
- `CHANGELOG.md [4.0.0]` — full release scope.
