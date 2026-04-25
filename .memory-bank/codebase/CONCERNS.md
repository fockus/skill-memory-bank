# Codebase Concerns

**Analyzed:** 2026-04-21

## Tech Debt
**`install.sh` size and responsibility:**
- Issue: 938-line monolith mixing Claude/Cursor/Codex/OpenCode global install, Cursor hook merge, skill alias creation, manifest bookkeeping, and adapter dispatch.
- Files: `install.sh`
- Impact: high change risk — every new host adds branches; rc3 install-idempotency fix touched many sections.
- Fix: extract per-host install stages into `install/_<host>.sh` helpers (same pattern as `adapters/`), leaving `install.sh` as an orchestrator only.

**`commands/mb.md` dispatcher size:**
- Issue: 37.6 KB single prompt file handling every `/mb <subcmd>`.
- Files: `commands/mb.md`
- Impact: fragile to edit; risks prompt drift vs. `agents/mb-manager.md`.
- Fix: split into `commands/mb/<subcmd>.md` and have `mb.md` delegate (if host supports sub-file routing), or at minimum extract shared preamble into a reference.

**Known TODO marker:**
- `scripts/mb-import.py:11` — "lessons.md: TODO (v2.2+) — debug-session pattern detection". Low severity, documented roadmap item.

## Known Bugs
- None currently tracked as open bugs. The latest rc (v3.0.0-rc3) explicitly closed install idempotency — see `.memory-bank/plans/2026-04-20_bugfix_install-idempotency.md`. The accompanying e2e test `tests/e2e/test_install_idempotent.bats` guards regression.

## Security Considerations
**Hook execution and `beforeShellExecution`:**
- Risk: `hooks/block-dangerous.sh` is user-trusted; a corrupted hook script could block or allow arbitrary commands.
- Files: `hooks/block-dangerous.sh`, `settings/hooks.json`, Cursor global bindings in `install.sh:27-31`
- Current mitigation: scripts have `_mb_owned: true` tags and manifest tracking so uninstall removes them cleanly; no network access.
- Recommended: ship an integrity check (hash in manifest) so re-install detects tampered scripts.

**Secret exposure through indexing:**
- Risk: `scripts/mb-index-json.py` scans note frontmatter + content; without `<private>` blocks, secrets could leak to `index.json` (committed by users).
- Files: `scripts/mb-index-json.py`, `scripts/mb-search.sh`
- Current mitigation: `<private>...</private>` redaction documented in `SKILL.md:151-184`; `hooks/file-change-log.sh` warns on commit.
- Recommended: add a pre-commit scanner for common secret patterns (e.g. `sk-`, `AKIA`, `AWS_`) — currently only `<private>` is blocklisted.

**`mb-upgrade.sh` self-update path:**
- Risk: pulls from GitHub and runs `install.sh`; compromised repo = RCE. HTTPS-only, no signature verification.
- Recommended: pin to tagged releases + checksum check.

## Performance Hotspots
**`scripts/mb-codegraph.py` (634 lines, largest script):**
- Cause: full tree-sitter parse of every source file on every invocation; no incremental cache.
- Improvement path: mtime/hash cache under `.memory-bank/codebase/.cache/` (already gitignored at `.gitignore:15`).

## Fragile Areas
**Hook merge logic (Cursor global + project-level coexistence):**
- Files: `install.sh` (Cursor block), `adapters/cursor.sh`, `settings/merge-hooks.py`
- Why fragile: Cursor merges hooks from `~/.cursor/hooks.json` and `.cursor/hooks.json`; ownership tracked only via `_mb_owned: true` entries, easy to desync if user hand-edits.
- Safe change: always go through `settings/merge-hooks.py`; never append raw JSON in adapters.
- Test gaps: `tests/pytest/test_merge_hooks.py` covers merge math, but no end-to-end test exercises a user-edited mixed-ownership `hooks.json`.

**AGENTS.md marker-section manipulation:**
- Files: `adapters/_lib_agents_md.sh`, used by `adapters/codex.sh`, `adapters/cursor.sh`, etc.
- Why fragile: uses sed/awk markers `<!-- memory-bank-*:start -->` — unclosed markers or malformed user edits corrupt the file.
- Safe change: always round-trip through `_lib_agents_md.sh`; add a unit bats case per adapter with malformed input.

## Test Coverage Gaps
**Windows `cli.py::find_bash` branches:** not exercised on macOS/Linux CI; Windows users are the top support source. Risk: Medium.
**Adapter uninstall with hand-deleted manifest:** bats tests assume clean install→uninstall cycle. Risk: Low–Medium.

## Scaling Limits
**`mb-search.sh` linear grep** across `notes/`, `plans/`, `experiments/`, `reports/`: slows past ~1000 notes on HDD; OK on SSD for 10k+ files. Path to scale: JSON-path queries against `index.json` (already built by `mb-index-json.py`), reserve grep for `--deep`.
