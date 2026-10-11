STATUS: DONE

## Files
- scripts/_lib.sh (mb_resolve_path: walk up from PWD; if an ancestor is named `.memory-bank` and holds status/progress/checklist/roadmap/COORDINATION, return it; placed before the relative-`.memory-bank` fallback, after explicit arg and MB_PATH)
- tests/bats/test_mb_resolve_nested_bank.bats (new, 4 cases)
- scripts/mb-coord.sh (BLOCKED, COMMIT, `--track`, `tracks --json`, `active` lists open BLOCKED)
- references/coordination.md (two table rows + --track/tracks paragraph)
- tests/bats/test_mb_coord.bats (+6 cases), tests/pytest/test_mb_coord_docs.py (tag list extended)

## Tests
Before: nested-bank bats: 3 of 4 failed (coord from bank dir, coord from bank subdir, progress-append from bank dir; the 4th, ordinary project dir, is the regression guard). test_mb_coord.bats: 5 of the 6 new cases failed (empty-board tracks case was among them via unknown subcommand: 5 not ok counted).
After: `bats test_mb_resolve_nested_bank test_lib test_mb_storage_resolver` 110/110 ok; `bats test_mb_coord.bats` 18/18 ok; pytest test_mb_coord_docs 3 passed. shellcheck -x on _lib.sh and mb-coord.sh clean; ruff clean.

## Notes
- `tracks --json` open_blocked/open_handover items: {track,date,title}. Scope matching is casefolded like `active`; a tagged legacy entry whose scope happens to start with `word:` would be attributed to a track (untagged legacy are not).
- Track id grammar: [A-Za-z0-9][A-Za-z0-9_-]{0,31}.
- Remaining: nothing. Not committed.
