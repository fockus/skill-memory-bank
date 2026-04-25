# Code Review Report — Full Repository Review
Date: 2026-04-21 15:00
Files reviewed: 228 (200 source/config/test/docs)
Lines changed: +0 / -0 (full-repo static review)
Scope: memory-bank-skill v3.1.1

---

## Critical
<!-- Merge blockers: bugs, vulnerabilities, broken tests -->

**None.** No critical bugs, security breaches, or broken tests were found.

- Tests: `pytest -q` → **216 passed, 14 skipped**
- Lint: `ruff check .` → **All checks passed!**
- Shellcheck: **0 warnings** (only SC2016 info in adapters — intentional markdown echo)

---

## Serious
<!-- SOLID / Clean Architecture violations, significant architecture issues -->

### S1. `install.sh` is a God Object (~950 lines, 8+ responsibilities)
**File:** `install.sh`  
**Principle:** SOLID — Single Responsibility  
**Description:** The installer conflates CLI parsing, interactive pickers, dependency preflight, file installation with idempotency, backup rotation, localization (Python heredocs), symlink management, Cursor-global-specific logic, settings hooks merging, manifest generation, and cross-agent adapter orchestration.  
**Impact:** Any change to one concern requires editing the monolith. Testability is low — e2e tests must exercise the entire surface.  
**Recommendation:** Extract each major phase into standalone scripts under `install.d/` or sourced functions. The installer should be a thin orchestrator (~100 lines).

### S2. Client-Specific Global Logic Inside Universal Installer
**File:** `install.sh` lines 629–797  
**Principle:** Clean Architecture — dependency direction  
**Description:** `install.sh` hardcodes Cursor global install logic (`~/.cursor/hooks.json`, `~/.cursor/memory-bank-user-rules.md`) while ALSO delegating project-level Cursor setup to `adapters/cursor.sh`. This violates the adapter boundary.  
**Impact:** Adding an 8th client requires modifying both the adapter AND the installer.  
**Recommendation:** Move ALL Cursor global logic into `adapters/cursor.sh`. The installer should only: (1) install the canonical skill dir, (2) create symlinks, (3) invoke adapters.

### S3. Massive Python Heredocs Inside Bash — Layer Inversion
**Files:** `install.sh`, `uninstall.sh`, `mb-compact.sh`  
**Principle:** KISS, Clean Architecture  
**Description:** Dozens of inline Python scripts in bash heredocs perform text processing. The uninstaller alone contains **four nearly identical** Python blocks for stripping AGENTS.md markers. Impossible to lint, type-check, or unit-test in isolation.  
**Recommendation:** Extract all Python text-processing into `memory_bank.lib.texttools` (typed functions: `strip_markers()`, `localize_file()`, `migrate_plan_bullets()`). Bash calls `python3 -m memory_bank.texttools <action>`.

### S4. `mb-compact.sh` Conflates Compaction with Structural Migration
**File:** `scripts/mb-compact.sh`, 509 lines  
**Principle:** SOLID — Single Responsibility  
**Description:** The script handles plan archival, note archival, checklist section removal (v3.1), AND roadmap.md legacy localized section migration (v3.1). The latter two are migrations, not compaction.  
**Recommendation:** Split v3.1 migration logic into `mb-migrate-structure.sh` (already exists!) and keep `mb-compact.sh` strictly for archival decay.

### S5. Adapter Boilerplate Duplicated ~70% Across 7 Files
**Files:** `adapters/*.sh` (7 adapters)  
**Principle:** DRY  
**Description:** ~840 lines of near-identical logic: manifest creation, hooks.json merge, rules header, `require_jq()`, uninstall pattern, empty directory cleanup.  
**Recommendation:** Extract `adapters/_framework.sh` with generic helpers: `adapter_install_rules_file()`, `adapter_merge_hooks_json()`, `adapter_write_manifest()`, `adapter_uninstall_files()`.

### S6. No Enforced Adapter Contract
**Files:** `adapters/*.sh`  
**Principle:** SOLID — ISP, DIP  
**Description:** Each adapter has its own internal structure. Some use functions, others top-level case statements. No enforced contract (all adapters MUST implement `install`, `uninstall`, `verify`).  
**Recommendation:** Create `adapters/_contract.sh` defining required functions with no-op defaults. Source it in every adapter. Add CI check for completeness.

---

## Security

### HIGH-1. `uninstall.sh` Path Traversal via Manifest Poisoning
**File:** `uninstall.sh` lines 32–63  
**Severity:** High  
**Description:** Prefix checks like `$HOME/.claude/*` can be bypassed by manifest entries containing `../../` sequences, leading to arbitrary file deletion via `rm -rf`.  
**Fix:** Canonicalize paths with `realpath` or reject any path containing `..` before deletion.

### HIGH-2. `scripts/_lib.sh` `.claude-workspace` Traversal
**File:** `scripts/_lib.sh` lines 12–31  
**Severity:** High  
**Description:** The `project_id` value is read unsanitized. A malicious workspace file can redirect all memory-bank operations to arbitrary directories.  
**Fix:** Sanitize `project_id` (alphanumeric only) and reject paths with `..`.

### HIGH-3. `adapters/pi.sh` Manifest Poisoning in Uninstall
**File:** `adapters/pi.sh` lines 88–96  
**Severity:** High  
**Description:** `uninstall_skill_mode` executes `rm -rf` on a path read directly from the manifest without validation.  
**Fix:** Validate manifest paths against expected prefix before `rm -rf`.

### MED-1. `_lib_agents_md.sh` Non-Atomic Write
**File:** `adapters/_lib_agents_md.sh` lines 113–116  
**Severity:** Medium  
**Description:** `_owners_write()` uses `echo "$data" > file` — non-atomic. Crash during write leaves a truncated `.mb-agents-owners.json`.  
**Fix:** Use temp-file + `mv` pattern (as in `merge-hooks.py`).

### MED-2. `merge-hooks.py` Substring-Based Ownership Detection
**File:** `settings/merge-hooks.py` lines 63–74  
**Severity:** Medium  
**Description:** `_is_mb_managed` drops the entire hook entry if its first command contains `[memory-bank-skill]` substring. A user hook with that string in a comment or path will be deleted.  
**Fix:** Use anchored regex or structured metadata instead of raw substring.

---

## Notes
<!-- DRY / KISS / YAGNI, style, smaller improvements -->

### DRY-1. Uninstall Script Duplicates Cleanup Logic Four Times
**File:** `uninstall.sh` lines 89–253  
Four Python heredocs clean OpenCode, Codex, Cursor, and CLAUDE.md marker sections. They differ only by variable names. Replace with a single reusable function.

### DRY-2. `mtime()` Duplicated in 4+ Files
**Files:** `scripts/mb-compact.sh`, `scripts/mb-drift.sh`, `hooks/session-end-autosave.sh`, `hooks/mb-compact-reminder.sh`  
Recommendation: Add `mb_mtime()` to `_lib.sh`.

### DRY-3. `_atomic_write()` Reimplemented in Every Python Script
**Files:** `scripts/mb-index-json.py`, `scripts/mb-import.py`, `scripts/mb-codegraph.py`  
Recommendation: Create `memory_bank.lib.atomic_write()` in a shared Python package.

### DRY-4. `install.sh` Localization: Two Nearly Identical Functions
**File:** `install.sh` lines 352–445  
`localize_installed_file` and `localize_path_inplace` set the same env vars and run the same Python heredoc.

### KISS-1. Localization System Over-Engineered for Two Real Languages
**Files:** `install.sh`, `adapters/_lib_agents_md.sh`, `scripts/mb-config.sh`  
Supports 4 languages, but `es/zh` are scaffolds awaiting community translations. ~100 lines of code + 2 config files for a 50%-unimplemented feature.  
**Recommendation:** Hardcode `en`/`ru` only. Remove `es`/`zh` until translations exist.

### KISS-2. `mb-codegraph.py` Tree-Sitter Adapter is Speculative Complexity
**File:** `scripts/mb-codegraph.py` lines 33–265  
~230 lines of lazy-loading tree-sitter parser logic for Go/JS/TS/Rust/Java — marked as "Stage 6.5 opt-in extras." 42% of the file is dead weight for an optional feature.  
**Recommendation:** Move tree-sitter code to `scripts/mb-codegraph-ts.py` or optional plugin. Keep core `mb-codegraph.py` strictly Python AST.

### KISS-3. `mb-tags-normalize.sh` Heavyweight Solution for Rare Problem
**File:** `scripts/mb-tags-normalize.sh`, 247 lines  
Full Levenshtein distance + synonym detection + auto-merge for note frontmatter tags. A simple convention ("tags are lowercase kebab-case") would suffice.  
**Recommendation:** Reduce to a simple linter that prints unknown tags.

### YAGNI-1. Pi Adapter "Skill Mode" is Speculative
**File:** `adapters/pi.sh` lines 40–96  
`MB_PI_MODE=skill` installs a native `~/.pi/skills/memory-bank/` package for an API "in active development" that "will need refinement."  
**Recommendation:** Remove `skill` mode. Re-add when Pi Skills API is stable.

### YAGNI-2. `settings/merge-hooks.py` Legacy Patterns
**File:** `settings/merge-hooks.py` lines 25–46  
16 hardcoded legacy string patterns from v1/v2 installs. At v3.1.1, these should have been purged.  
**Recommendation:** Remove `LEGACY_PATTERNS` and `LEGACY_BARE_PATHS`. Handle v1→v2 via `mb-upgrade.sh` migration.

### YAGNI-3. `mb-import.py` Complex Heuristic for Niche Use Case
**File:** `scripts/mb-import.py`, 327 lines  
Imports Claude Code JSONL transcripts with architectural heuristics, PII regex, SHA256 dedup, resume state. "Haiku summarize" mentioned in docstring is not actually implemented.  
**Recommendation:** Deprecate or extract to `contrib/`. Not core skill functionality.

---

## Contracts & Interfaces

### CW-1. `memory_bank_skill/cli.py` — `find_bash()` Contract Break
**File:** `memory_bank_skill/cli.py` lines 67–97  
On Windows may return `wsl.exe` — which is NOT bash. Callers expecting a bash path will break.  
**Fix:** Return a discriminated type `(path, kind)` or split WSL detection into its own function.

### CW-2. `cli.py` — No Client Validation
**File:** `memory_bank_skill/cli.py` lines 152–162  
`cmd_install` forwards `--clients` as raw string without validating against `VALID_CLIENTS`. User gets a late error from `install.sh`.  
**Fix:** Add client-list validation in `cmd_install`.

### CW-3. `uninstall.sh` — No `--non-interactive` Flag
**File:** `uninstall.sh` line 28  
Unconditional interactive prompt breaks automation, remote execution, CI pipelines.  
**Fix:** Add `-y` / `--non-interactive` flag.

### CW-4. Adapter Manifest Schemas Diverge
**Files:** `adapters/cursor.sh`, `adapters/opencode.sh`, `adapters/cline.sh`  
`cursor` uses `hooks_events`; `opencode` uses `plugin_ref` + `agents_md_owned`; `cline` uses `hooks_events`. No generic tool can validate or bulk-uninstall.  
**Fix:** Define unified schema in `references/adapter-manifest-schema.json`.

### CW-5. `mb-index-json.py` — Python 3.11+ Only
**File:** `scripts/mb-index-json.py` line 29  
Uses `from datetime import UTC` which is Python 3.11+. Crashes on 3.10.  
**Fix:** Use `datetime.now(timezone.utc)`.

### CW-6. `install.sh` — Manifest Deduplication Destroys Order
**File:** `install.sh` lines 882–907  
Python `set(files)` destroys insertion order, making manifest non-deterministic.  
**Fix:** Use `dict.fromkeys(files)` (Python 3.7+) or sort before writing.

### CW-7. `install.sh` — Adapter Files Not in Global Manifest
**File:** `install.sh` lines 910–925  
Step 8 invokes adapters but never adds their files to global `INSTALLED_FILES`. Global uninstall is unaware of adapter artifacts.  
**Fix:** Record adapter manifest paths in global manifest, or make `uninstall.sh` invoke adapter uninstall scripts.

### CW-8. Cache/State JSON Files Lack Schema Version
**Files:** `scripts/mb-codegraph.py`, `scripts/mb-import.py`  
No `_version` field in cache or import state. Upgrades may silently consume stale data.  
**Fix:** Add `"_version": 1` to all persisted JSON models.

---

## Tests

### Summary
| Suite | Result |
|-------|--------|
| Unit (pytest) | ✅ 216 passed, 14 skipped |
| Unit (bats) | ✅ ~368 ok |
| E2E (bats) | ✅ 15+ ok |
| Lint (ruff) | ✅ All passed |
| Lint (shellcheck) | ✅ 0 warnings |

### Well-Covered Modules
- `scripts/_lib.sh` — all 6 public functions
- `scripts/mb-compact.sh` — extensive archival + safety tests
- `scripts/mb-plan-sync.sh` / `mb-plan-done.sh` — stage parsing, idempotency
- `scripts/mb-drift.sh` — all 8 checkers
- `settings/merge-hooks.py` — 92% coverage
- `hooks/session-end-autosave.sh` — lock modes, idempotency
- All 7 adapters — install/uninstall/idempotency roundtrips
- E2E install/uninstall — manifest, backup, idempotency

### Coverage Gaps
| Module | Risk | Gap |
|--------|------|-----|
| `scripts/mb-note.sh` | Medium | No direct tests for happy path, collision suffixes, non-ASCII rejection |
| `scripts/mb-plan.sh` | Medium | No direct tests for type validation, topic sanitization, collision handling |
| `adapters/_lib_agents_md.sh` | Medium | Critical refcount logic tested only indirectly through adapters |
| `scripts/mb-search.sh` | Low | Python fallback redaction boundaries not directly tested |
| `memory_bank_skill/cli.py` | Low | `run_shell` FileNotFoundError (return 4) not tested |
| `install.sh` interactive paths | Low | TTY menu paths not tested; only `--non-interactive` exercised |
| Concurrent hook invocation | Low | `session-end-autosave.sh` has lock logic but no stress test |

### Recommendations
1. **P1:** Add `tests/bats/test_mb_note.bats` and `tests/bats/test_mb_plan.bats`
2. **P1:** Add direct tests for `adapters/_lib_agents_md.sh` refcount logic
3. **P2:** Add error-path tests for `mb-plan-done.sh` (already-in-done-dir, file-collision)
4. **P2:** Expand `block-dangerous.sh` tests for additional dangerous patterns
5. **P3:** Consider `kcov`/`bashcov` in CI for quantitative shell script coverage

---

## Plan Alignment

- **Implemented:** Этапы 0–10 закрыты (DRY-утилиты, language detection, mb-doctor, mb-codebase-mapper, plan-sync/done, auto-capture, drift checkers, PII markers, compaction, JSONL import, code graph, tags normalization, 7 cross-agent adapters, Cursor global parity, install idempotency fixes, landing website)
- **Not implemented:** Stages 11–15 из `plans/2026-04-21_refactor_core-files-v3-1.md`:
  - Stage 11: `commands/mb.md` — новые subcommands
  - Stage 12: Dogfood — migrate наш `.memory-bank/`
  - Stage 13: `install.sh` — новые скрипты + uninstall
  - Stage 14: Docs — README + CHANGELOG + MIGRATION guide
  - Stage 15: Release v3.1.0
- **Outside the plan:** None — all code aligns with documented plans.

---

## Summary

The memory-bank-skill v3.1.1 codebase is **functional, well-tested, and production-ready** but suffers from **organic growth without architectural refactoring**. The v2→v3 evolution added adapters, global installs, pip packaging, and cross-agent support incrementally, layering complexity onto the original installer rather than restructuring it.

**Top risks:**
1. **Security:** Path traversal in `uninstall.sh` and `_lib.sh` (HIGH severity)
2. **Architecture:** `install.sh` god object and adapter boundary violations make new client support unnecessarily difficult
3. **Maintainability:** ~20 untestable Python heredocs in bash and ~840 lines of duplicated adapter boilerplate

**Recommendation:** Before v3.1.0 final release, address the 3 HIGH security findings and begin the P0 architectural refactor (extract Python text-processing lib + move client global logic into adapters). This would reduce core codebase by ~30% while improving security, testability, and extensibility.
