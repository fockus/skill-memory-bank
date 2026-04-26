---
type: note
tags: [audit, remediation, drift, hardening, terminology, ssot, testing, security]
related_features: [I-035]
sprint: null
importance: high
created: 2026-04-27
---

# v4-audit-remediation-closeout
Date: 2026-04-27 01:04

## What was done
- Closed all 7 stages of the `refactor — v4-audit-remediation` plan (2026-04-25 → 2026-04-27) — the v4.0.0 full-skill audit identified 7 drift groups; remediation now ships.
- Stage 1: SKILL.md/README.md realigned to 24 commands / 45 scripts / 16 agents / 9 hooks; new `test_doc_counts.py` (6) enforces doc↔reality contract.
- Stage 2: status.md / CHANGELOG / project-CLAUDE realigned to v4.0.0 truth; `test_status_drift.py` (3) + `test_changelog_no_orphan_section.py` (2) enforce.
- Stage 3: Git/repo hygiene — `.session-lock` gitignored, `old-origin` removed, `dist/` purged; `test_gitignore_invariants.py` (5).
- Stage 4: Flaky CLI tests root-caused — `install.sh:17` MANIFEST hard-coded to source dir bypassed `$HOME` sandbox; fix: autouse `_protect_repo_install_manifest` fixture in `test_cli.py`. 3 consecutive 663/663 × 0 flake.
- Stage 5: `BaseException → Exception` in `_io.py:23` + `merge-hooks.py:147` (KeyboardInterrupt/SystemExit propagate); `set -euo pipefail` in `scripts/_lib.sh` inherits to all consumers via `source`. 9 pytest + 4 bats RED→GREEN. Bonus: `commands/mb.md` frontmatter closing `---` fix.
- Stage 6: Security hardening — `mb-idea.sh` literal-string dedup via `grep -F` + boundary-aware `awk index()`; `mb-search.sh` end-of-flags `--` parser + rg/grep `-e`; `hooks/file-change-log.sh` chmod 600 + atomic rotation. 7 bats RED→GREEN, shellcheck clean.
- Stage 7: Phase/Sprint/Stage SSoT propagation — 5 cross-link refs added; new `drift_check_terminology` in `mb-drift.sh` (filter-aware: legacy/alias/Cyrillic/«»/deprecat tags, regex literals, TDD jargon, backtick code spans); soft-warn in `mb-plan.sh` on legacy-Cyrillic in topic; MB core cleanup (Этап → Stage). 6 tests RED→GREEN.
- Plan-verifier fix-cycle resolved 2 CRITICAL (ruff SIM117 + README:419 v4.0.0 mention) + 5 WARN; backlog `I-035` captured for legacy bats fixture refresh (11 pre-existing fails — separate refactor).
- Final totals: pytest 649 passed × 14 skipped × 0 flake (3 consecutive runs); bats 532 ok / 11 pre-existing not-ok; ruff + shellcheck `-S warning` clean; `mb-drift.sh` → `drift_check_terminology=ok`.

## New knowledge
- **Drift remediation = doc↔reality contract tests**. Each drift group needs an automated assertion (count test, status drift test, gitignore invariant) — narrative comments rot, tests don't. Pattern reusable for any v.next audit.
- **`install.sh` MANIFEST path is the hidden cross-test-state vector**. When a script writes to a path computed from its own location (rather than `$HOME` or an arg), pytest sandboxes leak across runs. Always check `$SOURCE_DIR`-relative writes when chasing flakes.
- **`BaseException` catchall is a control-flow bug, not a defensive one** — it swallows `KeyboardInterrupt` / `SystemExit`, breaking Ctrl-C and `sys.exit()`. Use `Exception` unless you have an explicit reason (and document it).
- **`set -euo pipefail` in `_lib.sh` propagates via `source`** — single point of strictness for every consumer, no need to repeat per-script. Verified by 4 bats covering downstream behavior.
- **Boundary-aware dedup in shell** = `grep -F` (literal) + `awk index()` (no regex eval). `grep -qE`/`awk $0 ~ "..."` give false-positives on titles with regex metachars (`.* / [bug] / ^foo$`).
- **`--` end-of-options is a contract, not a convenience**. CLI parsers must respect it AND propagate `-e <pattern>` to underlying tools so user queries starting with `--` round-trip safely.
- **SSoT propagation gap = declarative intent without contract**. Stating "X is the source of truth" in one file does nothing unless cross-link refs + a drift-checker assert it. Pattern continues earlier `lessons.md` insight (declarative intent ≠ contract). Filter-aware drift checker (skip legacy/alias/regex literals/code spans) avoids false positives that would erode trust.
- **Plan-verifier fix-cycle is part of `/mb done`, not optional**. CRITICAL findings (ruff, README staleness) must round-trip before session close — verifier output is a real gate, not advisory.
