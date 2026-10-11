STATUS: DONE_WITH_CONCERNS

# Track E — Stage 6 T-ENGINE

## Files

Changed:
- `scripts/mb-workflow.sh` — `--lenses <csv>` → JSON `review_lenses` (ensemble workflows only; validated against the project `review_ensemble`, else the bundled one; alias `quality` → `code_rules`; dedup; unknown lens / empty list / non-ensemble workflow → exit 2). The key is absent without the flag.
- `scripts/mb-work-plan.sh` — `--step-model verifier|reviewer|judge=<model>` (repeatable, forwarded to every plan of a multi-target run) overrides only that entry of `step_models`; invalid role or form → exit 2. 395 lines (zone limit 400).
- `scripts/mb-work-review-parse.sh` — optional `medium`: accepted in issues and `counts`; `counts.medium` appears only when the report uses it, so three-level reports normalize byte-identically. `--external` now keeps `medium` (it used to fold it into `minor`).
- `scripts/mb-work-severity-gate.sh` — a gate that declares `medium` enforces it (absent medium count = 0); a gate without `medium` stays three-level and medium findings count toward `minor`.
- `agents/mb-reviewer-lead.md` + `agents/mb-reviewer-{logic,tests,quality,security,scalability}.md` — one line each: `medium` is optional and used only when the brief or gate declares it.
- `commands/work.md` §5d — one sentence: when `review_lenses` is present, dispatch only those reviewers. Still 399 lines.

New:
- `scripts/mb_work_light.py` — acceptance of a `light` track result (contract below).
- `tests/bats/test_mb_workflow_lenses.bats` (8), `tests/bats/test_mb_work_severity_medium.bats` (12), `tests/pytest/test_mb_work_step_models.py` (7), `tests/pytest/test_mb_work_light.py` (11).

## The light-track contract (AGR-097, Q4 = C)

- `orchestrated`: the engine is unchanged. The orchestrator runs `/mb work` with `MB_WORK_PARALLEL=1`, `--workflow … --lenses …`, and `mb-work-plan.sh --model … --step-model …`.
- `light`: the track agent walks the stages itself and does not tick the source. It returns a report:
  ```
  STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
  ...
  ## Stages
  - <N>: done|blocked|skipped[ — evidence]
  ```
  `python3 scripts/mb_work_light.py accept --source <track source> --report <report> --json` returns `{accepted, status, items, pending, errors}` with exit 0 / 1 / 2. The report is accepted when all of these hold:
  - the STATUS is DONE or DONE_WITH_CONCERNS;
  - every stage still pending in the source (emoji or Markdown boxes) is reported `done`;
  - the report names no stage the source lacks;
  - no pending stage declares a non-waived `**Eval:**`. The red→green proof for such a stage exists only in the orchestrated loop, so the error says "run the track orchestrated".

  After acceptance, the orchestrator runs the verifier (cadence `plan`) and the review as configured. It then closes each item through `mb-work-state.sh done` + `mb-work-checkbox.sh flip`.
- This matches T-CFG's `work: orchestrated|light` key (`mb_pipeline_validate_team.py`). T-STATE `next` maps a rejection to `stop_human` or `fix`. T-DOCS should copy the contract into `commands/team.md`.

## Tests: red before the change, green after

Red before the change:
```
test_mb_workflow_lenses.bats: not ok 1-5 (--lenses unknown arg); ok 6-8 (key absence + both goldens, by design green on baseline)
test_mb_work_severity_medium.bats: not ok 1,2,3,5,7,9,11,12; ok 4,6,8,10 (back-compat and baseline-equal cases)
pytest test_mb_work_step_models.py test_mb_work_light.py: 13 failed, 5 passed
  (the 4 invalid-form cases and "missing report exits 2" already passed: unknown arg / missing script both exit 2)
```
Green after the change:
```
bats lenses + severity_medium + test_mb_work_command_doc + test_mb_workflow_presets + test_agent_report_delivery: 97 ok, 0 not ok
pytest step_models, light, review_parse, severity_gate, workflow_compose, work_cost_tiers, mb_work_plan,
  s2_file_size_contract, discipline_by_model, pipeline_work_integration, flow_pattern_templates, pi_native_work: 283 passed
shellcheck -x (4 scripts + 2 bats): clean · ruff (mb_work_light.py + 2 pytest): All checks passed!
```
The golden checks (DoD 1) run `mb-workflow.sh` (7 flag sets) and `mb-work-plan.sh` (4 flag sets) from the baseline `f050443` and from the working tree. Outputs are byte-identical when the new flags are not used. The same baseline comparison covers the parser (3 reports × 3 modes) and the gate (4 count sets × 3 gates).

## Concerns and what is left

1. **Medium — HANDOVER on the board.** `mb-pipeline-validate.sh` rejects `medium` in any `severity_gate`: `SEVERITY_KEYS = {"blocker","major","minor"}` in `scripts/mb_pipeline_validate_core.py:113`. That file belongs to T-CFG. Until `"medium"` is added there with one test, a project cannot declare `medium` in `pipeline.yaml`. `--gate` and team `clean_when` are not affected.
2. **Low — deviation from the plan's wording.** The plan says "absent limit = 0", and its DoD says "one medium passes the default gate of an existing pipeline". Both cannot hold at once. I chose the reading where existing gates keep their verdicts: without a `medium` key, medium counts toward `minor`. A gate that declares `medium` enforces it, and team `clean_when` declares `medium: 0`.
3. **Low — `--external` keeps `medium` now.** It used to fold it into `minor`. With a three-level gate the verdict is unchanged, but the normalized JSON differs for reports that contain `medium`.
4. **Low — follow-up outside scope.** `mb-work-trend.sh` weighs only blocker, major and minor, so fixing a medium finding does not show up in the pivot trend.
5. **Not related to this track.** `tests/bats/test_opencode_adapter.bats` fails in `setup` (`python3 -m site --user-base`). That is the environment or the parallel session's `adapters/*`; no code from this track runs there.

The done-gates session's files were not touched. Nothing was committed.
