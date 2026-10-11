STATUS: DONE_WITH_CONCERNS

# Track G: Stage 9 T-REVIEW (team review cycles and the external reviewer)

## Files
New:
- `scripts/mb-team-review.sh`: thin entry point (`exec python3 mb_team_review.py "$@"`).
- `scripts/mb_team_review.py` (192 lines): CLI with `start` and `gate`.
- `scripts/mb_team_review_core.py` (119 lines): shared state: config, paths, cycle masters, owner routing, `to_close`.
- `scripts/mb_team_review_external.py` (132 lines): `external` (prompt) and `ingest` (schema check + merge).
- `templates/team/external-review.md`: external reviewer prompt, per examples §7.
- `tests/bats/test_mb_team_review.bats`: 16 tests, run in a temp project with a space in its path.

The three Python modules are not in the stage file list. One file came out at 386 lines, so I split it to stay under the 300-line limit. Same situation as B's `mb_lock_resource.py`: T-WIRE has to add them to the manifest.

## Contract (what other stages call)
```
mb-team-review.sh start|gate|external|ingest --team <team.json> --mb <bank> --cycle N
    [--pipeline F] [--lenses a,b] [--range <base>..<rev>] [--name X] [--rev R]
exit: 0 ok/clean · 1 fixes needed · 2 broken input or usage · 3 team review disabled
```
- Files go to `<dir of team.json>/review/`:
  - `cycle-N/{brief.md,<lens>.json,master.json,external-<name>.json}`;
  - `external-<name>-cycle-N/{prompt.md,meta.json,findings.json,prior-closure.json}`.
- **Enabled check:** `team.review.enabled` from the resolved config, or `"team_review": true` in team.json. Without either, every subcommand exits 3. The bundled default is `false`.
- **`start`** writes the cycle brief. It contains:
  - the object (the diff command, with the tree path quoted);
  - what to read first: team brief, plan, agreements, previous master, external reports;
  - the lenses, each with its output path. `--lenses` accepts the `quality` alias; an unknown lens exits 2;
  - the tracks with their globs, so the lead can fill `owner`;
  - the known open items;
  - the previous issues to close;
  - the lens and lead format, including `previous_issues` with an `id`.
- **`gate`** steps:
  1. Checks `master.json` through `mb-work-review-parse.sh`. Every issue needs an `id`.
  2. Applies `clean_when` through `mb-work-severity-gate.sh --gate … --ignore-approval`. Severities missing from `clean_when` are unlimited.
  3. Requires a `previous_issues` status for every routed issue of cycle N-1, including issues still open there. A missing status means exit 2. An `unresolved|open|partial` status keeps the cycle dirty and sends the issue back to its owner.
  4. Owner: the issue's `owner` when it is a track id, otherwise matched by the track's file globs.

  Output JSON: `{cycle, verdict: clean|fixes_needed, counts, clean_when, fixes: {track: [ids]}, unowned, previous_open, actions}`. `actions`:
  - `fix <track>` in track order;
  - `stop_human review-unowned` when an issue has no owner;
  - `stop_human review-cycles` when the cycle is dirty and N ≥ `max_cycles`. In that case it is the only action.
- **`external`** renders the prompt. It names:
  - the commit and the baseline; the diff command uses the mirror when there is one;
  - the rule "read from the commit (`<vcs> show <rev>:<path>`), not from the working tree";
  - the delta since this reviewer's previous cycle (`meta.json`);
  - what to read first, the lenses, the known open items;
  - the earlier findings to close;
  - both output schemas.
- **`ingest`** steps:
  1. Validates `findings.json`: required `id`, `severity`, `lens`, `file`, `line`, `scenario`.
  2. Validates `prior-closure.json`: `id`, `status` closed|open|partial, `evidence`, plus one entry for every earlier routed finding. All errors exit 2.
  3. Writes the aspect report `cycle-N/external-<name>.json`.
  4. If the cycle's `master.json` exists, merges the findings into it: no duplicate ids, counts recomputed, verdict set to CHANGES_REQUESTED.

## Tests: failing before, passing after
Before (the script did not exist):
```
bats tests/bats/test_mb_team_review.bats
1..16
not ok 1 team review is off by default: start refuses with exit 3
... (all 16) ...
not ok 16 ingest: prior-closure must cover every earlier medium+ finding with a valid status
```
Midway, tests 2 and 13 caught `/var` → `/private/var` from `Path.resolve()`. Test 6 caught the parse rule "APPROVED requires empty issues". The fixture now uses CHANGES_REQUESTED with minors only, and that is clean by `clean_when`.

After:
```
bats tests/bats/test_mb_team_review.bats   -> 16 ok, 0 not ok
shellcheck -x scripts/mb-team-review.sh tests/bats/test_mb_team_review.bats   -> clean
ruff check scripts/mb_team_review.py scripts/mb_team_review_core.py scripts/mb_team_review_external.py -> All checks passed
pytest tests/pytest/test_mb_team_render.py tests/pytest/test_mb_team_config.py -> 49 passed
```
Requested cases:
- cycle with findings → fix → clean cycle: tests 5 and 6;
- `previous_issues`: tests 4, 7, 8;
- external JSON, valid: test 14 (including idempotency); broken: tests 15 and 16;
- `clean_when` with medium: test 9 (fails the default; passes with a declared `medium: 1`).

DoD:
- [x] `gate` 0/1/2 with owner grouping: tests 5, 6, 10.
- [~] `max_cycles` gives `stop_human review-cycles` in `gate` (test 11). For it to appear in `next`, T-STATE has to wire it (see concern 1).
- [x] The external prompt names the commit, the read-from-commit rule, the known open items and both schemas (test 13). `ingest` rejects a finding without file, line or severity (test 15).
- [x] Tests green; shellcheck clean.

## Concerns
1. **Med: `next` belongs to T-STATE.** `mb_team_state.py` is not my file. HANDOVER on the board: `next` takes `actions` from `gate`, records `reviews[]` in team.json, and `init --team-review` writes `"team_review": true`.
2. **Low: `previous_issues` needs an `id`.** The `agents/mb-reviewer-lead.md` schema has `message` and statuses `resolved|unresolved|superseded`, with no `id`. The gate accepts those statuses plus `closed|open|partial`, and the cycle brief requires an `id`. The agent text is not touched; whether to add `id` there is for T-DOCS or the orchestrator to decide.
3. **Low: three extra Python modules** (see Files): manifest work for T-WIRE.
4. **Low: `test_doc_counts.py::test_skill_md_script_table_lists_all_scripts`** already failed: 20 scripts are missing, including other tracks' and done-gates'. This track adds 4: `mb-team-review.sh` and `mb_team_review{,_core,_external}.py`. The rows in `references/scripts.md` belong to T-DOCS.
5. **Low: merging into master directly.** When `ingest` runs after the lead has already written master N, the external findings go in without the lead's dedup. That is the stricter direction. If master N does not exist yet, the lead reads `external-*.json` from the cycle folder, and the brief says so.

The done-gates files were not touched. Nothing was committed.
