# Track A report — GraphRAG: nudge, cost-report graph share, work.md room

STATUS: DONE_WITH_CONCERNS

Concerns: (1) `agent_id` in the PreToolUse payload is unconfirmed; (2) `SKILL.md` needs a link to the new reference (orchestrator).

## Files
- `hooks/mb-graph-nudge.sh` — symbol picker, throttle key, stale-marker cleanup
- `hooks/tests/graph-nudge.bats` (new, 8 cases)
- `memory_bank_skill/cost_report.py`, `scripts/mb-cost-report.py`, `tests/pytest/test_mb_cost_report.py` — graph_share
- `commands/work.md` (400 -> 358 lines), `references/work-loop-reference.md` (new, 57 lines)
- `tests/bats/test_mb_work_command_doc.bats` — added the new reference to the `DOCS` set (one line)
- No edits to `hooks/tests/graph-discipline.bats`, `test_work_source_bundle.bats`, `test_work_eval_first.bats`, `test_work_5g_graph_refresh.bats` (they read only work.md text that stayed).

## Stage 2 — nudge
Red (before the hook change), `bats hooks/tests/graph-nudge.bats`: 5 of 8 not ok — `grep sed foo` gave `who-calls sed`-class output instead of `<Name>`, `graph pack` leaked, an unknown name was suggested, the second `agent_id` shared the first one's budget, a 2-day-old marker survived.
Green after: `bats hooks/tests/graph-nudge.bats hooks/tests/graph-discipline.bats tests/bats/test_mb_graph_nudge.bats` -> 46 tests, 0 not ok (the 37 existing nudge/discipline tests stay green); `shellcheck -x --source-path=SCRIPTDIR hooks/mb-graph-nudge.sh` clean.
Behavior:
- Symbol picker: the "defined identifier" rule (`def foo`, `class Foo`) is kept (still checked against a command/keyword stoplist). The fallback now needs an identifier that is not a shell command or keyword (stoplist extended: `sed awk graph pack ls cd wc …`), looks like code (underscore, capital or digit — plain lowercase words are prose) and exists as a node in `codebase/graph.json` (`"name": "<X>"`, anchored on the closing quote). Nothing passes -> `<Name>`. The graph is always present at that point (the hook exits earlier without it), so fail-open is inherent.
- Throttle: key is `agent_id` when the payload carries it, else `session_id`, else env/day.
- Cleanup: `find .index -name '.graph-nudge.*' -mmin +1440 -delete` on every run past the graph gate.
- `agent_id` is UNCONFIRMED: no captured Claude Code PreToolUse payload was found in the repo (only Codex hook payload code reads `agent_id`; `subagent-history.jsonl` shows `agent_id:"unknown"`). Implemented as "use it when present, else session_id", as instructed. If Claude Code does not send it, behavior equals the old per-session key.
- Known limit: a real lowercase-only function (`resolve`) is never suggested; underscore/Capital names are.

## Stage 3 — graph_share
Red: 4 new tests in `tests/pytest/test_mb_cost_report.py` failed (new). Green: `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_cost_report.py` -> 32 passed; `ruff check` on both files and the test: no issues.
- `session_stats`/`subagent_stats` add `graph_calls`, `grep_calls`, `graph_share` (null when both are 0). Graph call = Bash command naming `mb-graph.sh|mb-graph-query.py|mb-code-context.py|mb-semantic-search.py` (graph wins when piped through grep); grep call = `Grep` tool or Bash `grep|egrep|rg` (also `rtk grep`).
- `build_report`: per-role `graph_calls/grep_calls/graph_share`, plus top-level `graph_calls`, `grep_calls`, `graph_share`. Text output prints `graph_share: 0.03 (graph 7 / grep 263)` and a `gshare` column per role.
- `python3 scripts/mb-cost-report.py --json` on this machine: `graph_share 0.0259` (graph 7 / grep 263); roles judge 0.0, other 0.0202, research 0.1481, verifier 0.0.
- Pre-existing, not mine: `ruff format --check` would reformat `_ROLE_AVG_FIELDS` in cost_report.py (outside my diff).

## Stage 4 — work.md room
Moved reference material (not executable steps, no text cut between by a test): the target-resolution forms table with Form 3/4 notes, the worktree rule, the durable-vs-ephemeral progress note, the hard-stop epilogue sentence, the Arguments flag table and the Related list, to `references/work-loop-reference.md` (sections: Target resolution forms, Worktree rule, Hard-stop epilogue, Durable vs. ephemeral progress, Arguments, Related commands). Pointers stay in work.md (`## Reference material` paragraph, the resolution paragraph, the durable-progress line). Headings kept in work.md: `## Concurrent core-file writes` (an end marker for `test_work_qa_contract.py`), `## Hard stops for --auto`, `## Per-item workflow…`. The keywords `Existing path/Substring/Topic name/Freeform/Empty` and `MB_WORK_MODE` stay in work.md because `test_phase3_sprint2_registration.py` / `test_phase4_sprint2_registration.py` read them there (an intermediate version failed those two; fixed in work.md, no foreign test edited).
`wc -l commands/work.md` = 358 (was 400). `test_s2_file_size_contract.py` green.

### Doc tests reading commands/work.md (recorded list)
bats (11 files, 175 tests): hooks/tests/graph-discipline, test_mb_coord, test_mb_spec_validate_layers, test_mb_work_command_doc, test_mb_work_prod_binding_r3, test_platform_limited_honesty, test_proportional_full_suite_once, test_quality_gates_doc, test_work_5g_graph_refresh, test_work_eval_first, test_work_source_bundle.
pytest (18 files): test_discipline_by_model, test_docs_cost_ladder, test_flow_route_templates, test_graph_wrapper_instructions, test_hook_plan_sync_post_write, test_mb_work_diff, test_mb_work_progress_append, test_mb_workflow_compose, test_phase3_sprint2/3 + test_phase4_sprint2/3_registration, test_planning_qa_sources_scenarios, test_proportional_verification_texts, test_quality_dod_delivery, test_s2_file_size_contract, test_tooling_core_wiring, test_work_qa_contract.

| | before | after |
|---|---|---|
| bats, per file | 175 ok, 0 not ok (graph-discipline 11, coord 18, spec_validate_layers 35, command_doc 48, prod_binding_r3 7, honesty 15, proportional 8, quality_gates 5, 5g 3, eval_first 15, source_bundle 10) | same counts, 0 not ok (honesty re-run last: 15 ok) |
| pytest | 627 passed, 2 failed | 629 passed, 2 failed |

The 2 pytest failures are identical before and after and are not mine: `test_phase3_sprint2_registration::test_mb_md_has_work_section` and `test_tooling_core_wiring::test_mb_md_verify_section_references_tooling_core` — Track D's in-flight `commands/mb.md` split (D-tests.patch on the board covers them). The 2 extra passes come from other tracks' new tests.

## Remaining / for the orchestrator
- `tests/pytest/test_doc_counts.py::test_skill_md_references_link_existing_files` fails now: `SKILL.md` `## References` has no link to `references/work-loop-reference.md` (SKILL.md is not in my list). Add one link line.
- I added the new reference to `DOCS` in `test_mb_work_command_doc.bats` so the tests that pin the moved text (target forms, durable/ephemeral, worktree rule) still search the doc set.

## Questions
- None blocking. Confirm `agent_id` from a real Claude Code PreToolUse payload when one is captured; if the field has another name, only the one `jq` line in the hook changes.

## Follow-ups
- A lowercase-only symbol pick (`resolve`) could be allowed when the graph has exactly one such node (ceiling of the current heuristic).
- `commands/work.md` still carries ~358 lines; further moves need the unpinned text identified by the owners of `test_tooling_core_wiring`/`test_phase*` tests.
