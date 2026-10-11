STATUS: DONE_WITH_CONCERNS

# Track C: T-CFG (stage 3) and T-RENDER (stage 7)

## Files
New:
- `scripts/mb_pipeline_validate_team.py`: the `team:` schema (keys, enums, lenses plus the `quality` alias, models, review, resources, checkpoint). It also checks for nested inline maps (D6) and normalizes `none` (the stdlib parser reads `none` as None, PyYAML reads it as a string).
- `scripts/mb_team_config.py`: C3 output plus the effective `team` block. Two commands: `show` and `resource <name>`. Exit codes: 2 for an invalid config, 3 for an unknown resource.
- `scripts/mb_team_pipeline.py`: `resolve` (C2: layers, per-field provenance, slot → host model through `mb_work_models`, warnings) and `parse-prompt`.
- `scripts/mb_team_vocab.py`: the closed prompt vocabulary. Not in the stage file list: I moved it out of the resolver to keep the resolver under 300 lines.
- `scripts/mb_team_render.py`, `templates/team/brief.md`, `templates/team/track-prompt.md`.
- Tests: `tests/pytest/test_mb_team_pipeline.py`, `tests/pytest/test_mb_team_config.py`, `tests/pytest/test_mb_team_render.py`.
- Fixtures: `tests/fixtures/team/{team.json,pipeline-team.yaml,golden/{brief.md,A.prompt.md,C.prompt.md}}`. `pipeline-team.yaml` is a copy of examples §1. The goldens were written by hand from examples §3–§4 before the code existed.

Changed:
- `references/pipeline.default.yaml`: `team:` block. Presets per AGR-097; team review `enabled: false`; `clean_when {blocker 0, major 0, medium 0}`; no resources.
- `scripts/mb_pipeline_minimal_yaml.py`: `team` added to the list of parsed blocks; a quoted list item containing `:` is no longer read as a mapping.
- `scripts/mb_pipeline_validate_core.py`: calls the team validator; `medium` added to `SEVERITY_KEYS` (HANDOVER from E).
- `scripts/mb-pipeline-validate.sh`: one help line (`severity_gate` keys now include medium). The file is not in the stage list; I changed it so the help text does not lie.
- `tests/pytest/test_pipeline_default_yaml.py` (+2 tests), `tests/pytest/test_mb_pipeline_validate.py` (+2 tests for medium).

## Tests: failing before, passing after
Before the code existed:
```
pytest tests/pytest/test_mb_team_pipeline.py tests/pytest/test_mb_team_config.py  ->  128 failed, 1 passed
pytest tests/pytest/test_pipeline_default_yaml.py                                   ->  2 failed, 40 passed
pytest tests/pytest/test_mb_team_render.py                                          ->  11 failed
pytest tests/pytest/test_mb_pipeline_validate.py -k medium (SEVERITY_KEYS without medium) -> 1 failed, 1 passed
```
After:
```
pytest test_mb_team_pipeline.py test_mb_team_config.py test_pipeline_default_yaml.py test_mb_pipeline_validate.py test_mb_team_render.py
217 passed in 14.17s
Related pytest (every file that mentions pipeline.default / minimal_yaml / mb-pipeline / validate / mb_work_models / effort_tiers): 549 passed
Related bats (pipeline / validate / severity_gate): 1..366, 366 ok
ruff check (all new and changed .py files): All checks passed!
```
Where each DoD item is covered:
- Layer matrix: 13 keys × 5 layers, value and provenance (`test_layer_matrix_later_layer_wins_with_provenance`). `size` has its own layers (`test_size_layers_*`).
- Provenance for every key: `test_every_resolved_key_has_provenance`.
- Exit 2 naming the field: unknown key, unknown value, unknown lens, `mode: work` without `--source`, nested inline map (`test_invalid_team_exits_2_naming_field`, `test_bad_attribute_exits_2_naming_it`, `test_mode_work_without_source_exits_2_naming_mode`, `test_validator_rejects_nested_inline_map_in_team`). The whole-file validator keeps its exit code 1, as before.
- PyYAML vs stdlib: same dicts and same errors (`test_*_identical_without_yaml`).
- A project without `team:` validates byte-identically. Checked by hand: the baseline validator (`git archive HEAD`) and the current one give identical output on the old default and on an invalid config. The existing validator tests pass unchanged.
- `resource build` on examples §1 gives exactly the C3 JSON from §2 (`test_resource_build_on_examples_matches_c3_json`).
- Ambiguous prompt → question with exit 3: `test_ambiguous_prompt_returns_question_not_guess` (vague phrase, conflict, model without a value, unknown lens, two models).
- Render: goldens for the brief and two prompts (direct small and direct large with review); absolute paths; `--mb` in every command; `unfilled` finds the 6 hints in the brief and 0 in the prompts.
- Track prompt as a one-stage plan: `test_track_prompt_is_a_one_stage_plan_for_mb_work_plan`. The real `mb-work-plan.sh --dry-run` gives 1 stage, role backend, dod_lines 3.

## Decisions and deviations (concerns)
1. **Med.** I followed the dispatcher's wording for the `large` preset: `mode: work` with lens review, the same as `extra`. Design §4 had `large` → review `single`. Switching back is one line in `references/pipeline.default.yaml` plus one row in `test_bundled_presets_follow_agr_097`.
2. **Low.** The contract grew by optional fields: C2 got `work` and `models.lens`; C1 got track `title`/`dod` and team `title`. The resolver takes `--source` and `--role`. A HANDOVER is on the board. T-STATE has to store `title`/`dod` at `track add`; without a `dod` the renderer refuses the track (exit 2).
3. **Low.** Exit codes: the whole-file validator (`mb-pipeline-validate.sh`) returns 1 as before. Exit 2 naming the field comes from `mb_team_config.py` and `mb_team_pipeline.py`.
4. **Low.** The brief keeps `<!-- fill: … -->` hints in 6 sections the orchestrator writes itself: Decisions, Deadline, Checked, Not doing, Contract, Limits. Track globs in the prompt are rendered as absolute paths under the tree (the DoD requires absolute paths; the example showed relative ones).
5. **Low.** Every `--json` flag is accepted, but output is always JSON; there is no human-readable format (YAGNI).

## Remaining / follow-ups
- The plan-time effort mismatch with the agent's frontmatter (REQ-TEAM-018) belongs to T-STATE (`/mb team plan`).
- The HANDOVER from E is ACKed under my track. Its open status on the board can only be closed by the orchestrator: the ACK scope has to match the `E:` prefix.
- `mb_pipeline_minimal_yaml.py` is at 400 lines, the existing limit for that file.
