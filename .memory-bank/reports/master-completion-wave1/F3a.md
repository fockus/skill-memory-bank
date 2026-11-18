# F3a report: svp-adapt-escalation rebased on ADaPT-lite (master-completion Stage 18a)

STATUS: DONE_WITH_CONCERNS

Concern (Med, orchestrator): `tests/pytest/test_spec_corpus_battery.py` now fails
`test_the_allowlist_has_no_stale_entries` because `svp-adapt-escalation` passes the validator. Delete the
`"svp-adapt-escalation"` line from `KNOWN_FAILING` (file is orchestrator-owned, not touched).

## Files
- `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/requirements.md` (rebase map, amended REQ-002..006 wording, scenarios 1-11 in English, frontmatter `blocked_by` without `svp-parallel-engine`)
- `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/design.md` (677 → ~270 lines; Seams block outside fences; Eval lines byte-identical to tasks.md)
- `/Users/fockus/Apps/skill-memory-bank/.memory-bank/specs/svp-adapt-escalation/tasks.md` (5 tasks, all Eval/Scope/Budget in the svp-sdd-core grammar)
- `/Users/fockus/Apps/skill-memory-bank/references/adapt.md` (§ Lite slice: status table only)
- No code, no tests, no stage, no commit. `adapt.verify_fail_cycles: 3` untouched.

## REQ map (code evidence from `scripts/mb_work_adapt.py`, graph fresh)

| REQ | Result | Evidence / owner |
|---|---|---|
| 001 | covered by `scripts/mb_work_adapt.py:155` `parse_escalation`, `commands/work.md` step 5c1, test `test_escalation_block_parses_with_and_without_pyyaml`, commit 190251c → waiver (Task 1) | |
| 002 | partly covered (`mb_work_adapt.py:247` `check`: verify + token guards, 190251c); open → Task 2 on `mb_work_adapt.py` (scope guard against the item's `Files:`, review/judge/eval-not-green counters) | |
| 003 | partly covered (`adapt.verify_fail_cycles: 3`, `references/pipeline.default.yaml:286`, `mb_work_adapt.py:37/51`); open → Task 2 (`review_cycles: 3`, `judge_cycles: 2`, `cascade_stop: 3` in the `adapt:` block) | |
| 004 | open → Task 5 (`stub-backlog` + autonomous branch in `commands/work.md`; stub is the fallback when the auto split is refused at `max_depth`) | |
| 005 | covered by `references/adapt.md` § Fork + `commands/work.md` 5c1 (continue/simplify/decompose/skip), 190251c → waiver (Task 1), wording amended | |
| 006 | covered by `mb_work_adapt.py:195/227/239` (`split`, `sub_done`, `gate`), 190251c → waiver (Task 1), wording amended (in-run sub-items, no spec registry) | |
| 007 | open → Task 3 (`mb_work_adapt_journal.py`, journal under `mb_lock_acquire` via a bash holder) | |
| 008 | open → Task 3 (`esc-summary`; stub lines come from journal `stub_continue` resolutions, Tasks 4-5 feed them) | |
| 009 | open → Task 4 (`verify-stub`, Python `subprocess` timeout replaces the bash bounded-run helper) | |
| 010 | open → Task 3 (`consecutive` in `esc-open`, `decision=stop_run`, `esc-clean`) | |

Dropped from revisions 1-3 as superseded by the lite code (YAGNI): `scripts/mb-work-adapt.sh`,
`escalation:` config section, `MB_WORK_RESULT_JSON` envelope in nine agents, `replan-gate` with
`requirements_sha256`, the child-spec registry route, S3 `mb-work-scope-check.sh` dependency.

## Tests (spec work: the validator is the test)

Before (baseline run at start):
```
$ bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-adapt-escalation
[spec-validate] REQ-049: task 3 has a documentation/configuration-only Scope but its Eval is not structural ...
[spec-validate] REQ-049: task 4 has a documentation/configuration-only Scope but its Eval is not structural ...
[spec-validate] REQ-051: design.md declares no **Seams:** block (C9 requires exactly one)
rc=1
```
After (known-red marker: new, now green):
```
$ bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-adapt-escalation
[spec-validate] layers=legacy
rc=0
```
Existing lite tests stay green (Task 1 green evidence); retro-red: `git show 190251c~1:scripts/mb_work_adapt.py` → `fatal: path ... exists on disk, but not in '190251c~1'`:
```
$ PYTHONPATH=. python3 -m pytest -q tests/pytest/test_adapt_lite_rules.py tests/pytest/test_mb_work_adapt.py
23 passed in 2.84s
```
Side effect (known, orchestrator-owned file): `tests/pytest/test_spec_corpus_battery.py::test_the_allowlist_has_no_stale_entries` FAILED, `svp-adapt-escalation` now passes the battery, entry in `KNOWN_FAILING` must be removed.

## Remaining
Stage 18b (code, role backend): Tasks 2-5 in order, one writer on `scripts/mb_work_adapt.py`, `commands/work.md`, `tests/pytest/test_mb_work_adapt*.py`. Task 3-5 add two sibling modules `scripts/mb_work_adapt_journal.py` and `scripts/mb_work_adapt_stub.py` (the dispatcher is already 338 lines, past the SRP threshold). Every `commands/work.md` edit must be net-zero lines (cap 400, `test_s2_file_size_contract.py`); Task 2 also updates the pinned `DEFAULT_LINE` in `tests/pytest/test_mb_work_adapt.py`.

## Questions for the orchestrator
1. Owner confirmation of the amended wording: REQ-004 (stub only when the auto split is refused at `max_depth`, since AGR-082 makes auto = split), REQ-005 (`decompose` instead of `replan`, requirement change = `simplify`), REQ-006 (in-run sub-items, no child-spec registry). Recorded as an open question in design.md; needs an AGR if the owner agrees.
2. Delete `svp-adapt-escalation` from `KNOWN_FAILING` in the corpus battery (see Concern).
3. Mixed-language corpus: I wrote the rebased spec in English (AGR-085); the umbrella and sibling specs are still Russian.

## Follow-ups
- `umbrella` REQ-030..032 mapping in `specs/sdd-vision-pipeline` untouched; umbrella T6 Eval (escalations logged as JSONL) becomes satisfiable after Task 3.
- `commands/work.md` was 377 lines in the working tree at the time of this run (the brief says 400); Track A owns it in wave 1, so Stage 18b must re-read the live size.
