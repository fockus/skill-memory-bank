# Track D report — split commands/mb.md (master-completion Stage 12)

STATUS: DONE_WITH_CONCERNS

## Result
- `commands/mb.md`: 111444 -> 11772 bytes (limit 16384), 1792 -> 117 lines. Keeps frontmatter, setup block, GraphRAG routing, a 3-column router table (command | short action | `references/mb/<x>.md`), "Loading a route", General Rules. Rows that cited `commands/<x>.md` keep that citation.
- `references/mb/*.md`: 48 files. Each = header + "Router entries" (the full original table text for its rows) + the original `###` sections verbatim. Shared files: `context.md` (context/search/note/tasks/unrecognized), `aliases.md` (start/done), `update.md`, `discuss.md` (+askme). Rows with no section (tags, statusline, rules, team, qa) get a file holding the full row text.
- `/mb help [sub]`: `references/mb/help.md` algorithm rewritten: no arg prints the router table; `<sub>` finds the router row and prints its reference file. It keeps the `SKILL_MD="${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}..."` literal that `test_skill_root_resolver` pins. `wiki.md` got a `SKILL_DIR` assignment line (graph-wrapper test scans references/).
- Shared readers: `tests/pytest/mb_corpus.py` (`read_mb_corpus()`), `tests/bats/lib/mb_corpus.bash` (`mb_corpus`).
- New test `tests/pytest/test_mb_router_targets.py` (6 tests): every router row points at an existing file, no orphan files, byte budget, help route, and the help algorithm runs for every router row.
- Plan `2026-09-24_fix_opus55-prompt-fit.md`: Stage 6 ticked (mb.md part; mb-done-finalize dropped, SKILL.md bullet out of scope), Stage 7 marked `dropped (AGR-102)`.

## TDD evidence
Red: against the original file (`/` scratch copy) the router test's preconditions fail: 0 `references/mb/` targets, 111444 > 16384 bytes. (I wrote the split before running the test file, so the red is shown by those two measurements, not a pytest run.)
Green: `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_router_targets.py tests/pytest/test_graph_wrapper_instructions.py tests/pytest/test_commands_skill_root.py` -> `423 passed`; `ruff check` on my two py files -> no issues; `wc -c commands/mb.md` -> 11772.

## Recorded list
`D-baseline-list.txt` (42 files, `grep -rlE 'mb\.md' tests hooks/tests`). Caveat: my first baseline run was contaminated (I split while it ran, and other tracks' pkill killed background runs), so there is no clean pre-split run; the "red" below is the post-split state.

Red after split in the real tree (all from moved sections, none from a logic change):
audit_command_contracts 10, claude_md_template 2, drive_autopilot 1, mb_research_command 4, mb_team_command 1 (track C's), phase2/phase2_sprint2/phase3_sprint1/phase3_sprint2 registration 1 each, rules_command 1, terminology 1, tooling_core_wiring 1, wiki_command 1, runtime_contract 1; bats: mb_agree_docs 3, mb_brief_docs 2, mb_init_command_docs 5, mb_drive_command 1, skill_root_resolver 1. (graph_wrapper_instructions was red from my own files and is fixed.)

## HANDOVER (posted on the board)
All of these are outside my file list. One patch edits 20 files: `.memory-bank/reports/master-completion-wave1/D-tests.patch` (`git apply --check` passes against the current tree; apply with `git apply`). Each edit switches the reader to `read_mb_corpus()` / `mb_corpus`; `test_audit_command_contracts` (verify test) and `test_tooling_core_wiring` read `references/mb/verify.md`. Includes `test_mb_team_command::test_router_index_and_counts_list_team`.
Verified in a scratch overlay copy of the repo with the patch applied: all 13 pytest files above + graph_wrapper pass (453 passed, 1 skipped); `test_drive_autopilot_scenarios` 11 passed; `test_runtime_contract` -k mb/init/profile/storage 8 passed; bats agree_docs, brief_docs, init_command_docs, skill_root_resolver (mb.md test), drive_command_contract, mb_drive_command all ok.

## Not verified (concerns)
- Heavy installer tests did not finish under load (other tracks running): bats `test_codex_adapter`, `test_install_upgrade_safe` timed out at 400s; opencode_* bats, e2e bats, `test_cli`, `test_opencode_selective_install` not completed. They only check that `commands/mb.md` is installed/identical, not its sections, so I expect no effect; the orchestrator's full run decides.
- `test_audit_install_roundtrip::test_pi_settings_roundtrip...` fails in the install step (Pi settings), unrelated to mb.md; not investigated further.
- `test_doc_counts.py` is red because SKILL.md lacks a link to `work-loop-reference.md` (track A); I did not touch it.
- `fixtures/command_descriptions_baseline.json` not checked separately: frontmatter `description` of mb.md is unchanged.

## Shipping of references/mb/ to hosts
- Claude/Codex/Cursor/Pi/OpenCode skill aliases are symlinks to the whole bundle dir (`~/.claude/skills/memory-bank -> repo`), so `$SKILL_DIR/references/mb/` is reachable; `install.sh` copies only `commands/*.md` as slash commands and the router resolves references through `$SKILL_DIR`. No install.sh/adapter change needed.
- pip wheel: `pyproject.toml` force-includes `references` as a directory (line 108) and sdist `/references` (129); but the glob `"references/*.md"` at line 86 is non-recursive. Low risk, check once when a wheel is built; not my file.

## Files
Written: `commands/mb.md`, `references/mb/*.md` (48), `tests/pytest/mb_corpus.py`, `tests/bats/lib/mb_corpus.bash`, `tests/pytest/test_mb_router_targets.py`, plan opus55-prompt-fit, `reports/.../D-baseline-list.txt`, `D-tests.patch`. `commands/done.md` and `test_doc_counts.py` needed no edit.

## Fix cycle 1
- D-R1: `compact` / `init` rows in `commands/mb.md` escape `\|` and carry an Action cell; full original action text restored in `references/mb/compact.md` and `init.md` Router entries. New test: every router row has 3 non-empty cells.
- D-R2: `help.md` Mode 2 matches any backticked command in the first cell (`context`, `ask_me`, `grooming` now work); the help test runs every backticked command word plus those three.
- D-R3: pointers now name files: `init.md` -> `references/mb/map.md`, `agree.md` -> `references/mb/verify.md`, wiki row -> `references/mb/wiki.md`. A scan finds no other `### x` pointer into a different file.
- D-R4: the "Invoking `/mb start` = invoking `/start`" line moved from `openspec.md` to `aliases.md` (end of alias list).
- D-R5: `read_mb_router()` added to `mb_corpus.py`; the "router table lists X" tests (discuss, sdd, config, work, wiki, rules, team, research) read it. Agree bats: router-row tests read `commands/mb.md`, the verify check is bounded inside `references/mb/verify.md`. skill_root test renamed to "references/mb/help.md resolves ..." and reads that file. The agree router row regained its subcommand list (`--supersedes`) so the row test stays meaningful. The 8 import-order lint errors from the patch were fixed.
- D-R6: `docs/commands.md` and `commands/done.md:51` describe `references/mb/<sub>.md`.
- D-R7: duplicate `load` / MB_CORPUS lines removed. D-R8 skipped as instructed.
- Evidence: pytest on router-targets + 14 patched files + commands_skill_root + doc_counts: 551 passed, 1 failed (`test_doc_counts` work-loop-reference.md link, track A, pre-existing). bats ok: agree_docs (17), brief_docs (7), init_command_docs (6), drive_command_contract (19); skill_root and mb_drive_command only their changed tests (filtered, ok; full files too slow under load). ruff clean on touched py. `commands/mb.md` = 12059 bytes.
