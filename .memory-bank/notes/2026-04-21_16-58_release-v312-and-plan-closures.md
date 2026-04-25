---
type: note
tags: [release, homebrew, pypi, plan-closure, two-repo-pattern, changelog, installer]
related_features: []
sprint: null
importance: high
created: 2026-04-21
---

# Release v3.1.2 + Plan Closures
Date: 2026-04-21 16:58

## What was done
- Released v3.1.2: git tag `v3.1.2` (beb2f9b), Homebrew formula sync (197d2eb), PyPI `memory-bank-skill==3.1.2` via OIDC Trusted Publishing, GitHub Release with wheel + sdist
- Closed plan `review-hardening-installer-boundaries` (7/7 stages) → plans/done/
- Closed plan `core-files-v3-1` (15/15 stages incl. Stage 12 dogfood: backlog.md migrated to I-NNN/ADR-NNN format, 22 ideas + 11 ADRs, backup in .pre-migrate-20260421-163107/)
- CHANGELOG: separate [3.1.2] patch section + accumulative [3.2.0] staging area preserved
- VERSION bumped 3.1.1 → 3.1.2 + `memory_bank_skill/__init__.py` synced

## New knowledge
- **Two-repo Homebrew pattern**: `packaging/homebrew/memory-bank.rb` in main repo is reference copy only; live formula is in `fockus/homebrew-tap/Formula/memory-bank.rb`. Both must bump url+sha256 after every PyPI publish. `source/m/` alias URL is simpler to maintain than hash-prefixed URL.
- **CHANGELOG for back-to-back releases**: keep accumulative `[3.2.0]` section as staging for next minor; add `[3.1.2]` separately for patch-level hardening. Patch bumps are correct SemVer for security/architectural refactors when API surface stays stable.
- **Pre-release version guard in CI** (`.github/workflows/publish.yml`) catches VERSION/`__init__.py`/tag mismatches before PyPI publish — prevents accidental publishes.
- **`.claude/` harness runtime state** (`scheduled_tasks.lock` etc.) must be in `.gitignore` — added this session to prevent accidental staging.
