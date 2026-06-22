---
type: fix
scope: config-validation-docs
created: 2026-06-23
status: queued
priority: MED
backlog: I-086
---

# Fix: Config Validation & Doc Consistency

## Goal

Close the config-validation and doc-vs-code drift findings from the codex/GPT-5.5
review (`.memory-bank/reports/2026-06-23_codex-gpt5.5-skill-review.md` §06 configurability
and §03 consistency). Two outcomes: (1) the pipeline validator + runtime YAML parsers
reject bad enum/type values and duplicate YAML keys before they reach `/mb work`, and
documented config knobs (`budget.default_limit`, profile `scope`, project rule profiles)
are actually executed; (2) public docs are regenerated FROM the source of truth and locked
behind GENERATED pytest checks so drift (command count/table, hooks reference, stale
synopses) cannot silently recur.

**Source-of-truth facts confirmed during planning (Bash on current tree):**
- `commands/*.md` count = **29** (settles the 25-vs-29 discrepancy: README:41 cell `25`
  is STALE; README:259 `29` is CORRECT). Missing table rows for `/analyze-task`,
  `/flow`, `/goal` (files exist: `commands/analyze-task.md`, `flow.md`, `goal.md`).
- `.memory-bank/pipeline.yaml` has a **duplicate `judge:` key** inside `roles:` —
  line 34 `judge: { agent: main-agent }` and line 41 `judge: { agent: mb-judge }`;
  PyYAML silently keeps the last (`mb-judge`); `mb-pipeline.sh validate` returns 0.
- `scripts/mb-work-budget.sh:42` reads ONLY `budget.warn_at_percent/stop_at_percent`,
  never `budget.default_limit`; `commands/work.md:298` inits a budget only with `--budget`.
- `memory_bank_skill/rules_profile.py`: `scope` is in `_CANONICAL_KEYS` (so it is not
  rejected as unknown) but is NEVER validated against `{user, project}`; no `ALLOWED_SCOPES`.
- `scripts/mb-rules-check.sh:39` profile resolution reads only `MB_PROFILE`/`--profile`;
  project profiles from `mb-profile.sh init --scope=project` are not auto-consumed.
- `scripts/mb-config.sh` supports only `lang`; `scripts/mb-pipeline.sh:96,471-477` writes
  `pipeline=<name>` into the SAME `<bank>/.mb-config` — split/unclear ownership.
- `references/hooks.md:3,188,230` claims "five" tool hooks; `settings/hooks.json` has 9
  event keys (`Setup, PreToolUse, PostToolUse, Notification, PreCompact, Stop,
  UserPromptSubmit, SessionStart, SessionEnd`) covering ~15 distinct hook scripts.
- `/mb reindex` documented in `README.md:312` + `SKILL.md:290-291` but ABSENT from the
  `commands/mb.md` router; impl is the hook helper `hooks/mb-reindex.sh`.
- `mb-pipeline-validate.sh` ALREADY validates `budget.default_limit` (lines 553-556) and
  `workflow`/`workflows` blocks, but DOES NOT validate top-level `review`, `judge`,
  `review_ensemble`, `done_gates`, `done_placeholders`, `dispatch`.
- `tests/pytest/test_doc_counts.py` exists; its README check only matches the
  `**N top-level slash-commands**` phrase (catches README:259) but NOT the table cell
  at README:41 nor the per-command table ROWS — those need new generated assertions.
- No `tests/bats/test_*pipeline*validate*.bats` exists yet (new file required).

## Stages

---

### Stage 1 — Pipeline validator: runtime-block schema + duplicate-key rejection
**Files:**
- `scripts/mb-pipeline-validate.sh` (modify the embedded PyYAML validator, after line 622)
- `tests/bats/test_mb_pipeline_validate.bats` (CREATE)

**TDD — write FIRST (RED):** add `tests/bats/test_mb_pipeline_validate.bats` covering, via
small fixture YAMLs written to `$BATS_TMPDIR`:
- `test_validate_rejects_review_severity_gate_bad_enum` — top-level `review.severity_gate`
  with an unknown key (e.g. `critical: 0`) → exit 1, stderr mentions `review.severity_gate`.
- `test_validate_rejects_review_on_max_cycles_bad_value` — `review.on_max_cycles: foo` → exit 1.
- `test_validate_rejects_judge_decisions_not_list` — `judge.decisions: GO` (scalar) → exit 1.
- `test_validate_rejects_done_gates_required_unknown_token` — `done_gates.required:
  [tests_pass, bogus]` → exit 1.
- `test_validate_rejects_dispatch_priority_unknown_transport` — `dispatch.priority:
  [pi, nope]` → exit 1; `test_validate_rejects_dispatch_on_none_available_bad` —
  `dispatch.on_none_available: maybe` → exit 1.
- `test_validate_rejects_stage_enabled_non_bool` — a stage block with `enabled: yes-please`
  (non-bool) → exit 1.
- `test_validate_rejects_duplicate_top_level_key` — file with two `judge:` keys at the
  SAME mapping level → exit 1, stderr mentions `duplicate key`.
- `test_validate_accepts_clean_default_pipeline` — `references/pipeline.default.yaml`
  passes (exit 0) — regression guard.

**Implementation:**
1. Add a duplicate-key-rejecting YAML load path. When `yaml is not None`, parse with a
   `yaml.SafeLoader` subclass overriding `construct_mapping` to raise on a repeated key
   (collect seen keys; `yaml.constructor.ConstructorError` on collision). On collision →
   `err(f"duplicate key '<k>' at line <n>")` and set `cfg=None`. Keep the existing
   `yaml.YAMLError` catch. No-PyYAML minimal loader path is unchanged (documented limitation).
2. Add top-level schema checks (only the keys that exist; absence stays valid — opt-in):
   - `review`: `enabled` bool; `severity_gate` keys ⊆ {blocker,major,minor}, int ≥ 0;
     `max_cycles` int ≥ 1; `on_max_cycles` ∈ {stop_for_human, continue_with_warning,
     judge_decides}; `categories` list of non-empty strings.
   - `judge`: `enabled` bool; `decisions` non-empty list ⊆ {GO, GO_WITH_BACKLOG, NO_GO};
     `register_backlog_before_done` bool; `blocking_policy` list of non-empty strings.
   - `review_ensemble`: `min_reviewers`/`max_reviewers` int ≥ 1 with min ≤ max;
     `reviewers` non-empty list of mappings each with non-empty `role`.
   - `done_gates`: `enabled`/`allow_force` bool; `required` ⊆ {tests_pass,
     no_critical_violations, no_placeholders}.
   - `done_placeholders`: `deny` non-empty list of non-empty strings.
   - `dispatch`: `priority` non-empty list ⊆ KNOWN_AGENTS (reuse the existing
     `KNOWN_AGENTS` set defined at line 628); `on_none_available` ∈ {fallback, error};
     `enumerable` list ⊆ KNOWN_AGENTS; `prefer`/`model_map` mappings; `fallback` mapping.
   - Per-stage `enabled` (for `discuss`, `plan`, `sdd`, `review`, `judge`): when present,
     must be bool.
3. Reuse the module-level `SEVERITY_KEYS` and `valid_max_cycles` already defined; do not
   redefine. Keep file ≤ 656 current lines + additions (stay well under 400-line guard for
   the bash wrapper; the Python heredoc is exempt-but-keep-tight).

**DoD:**
- [ ] All 9 new bats cases pass; `references/pipeline.default.yaml` and `.memory-bank/pipeline.yaml`
      (after Stage 1 fixes the dup key — see note) validate green.
- [ ] Validator rejects bad enum/type values for review/judge/review_ensemble/done_gates/
      done_placeholders/dispatch and per-stage `enabled` with a specific dotted-path message.
- [ ] Duplicate top-level (and nested same-level) keys → exit 1 when PyYAML is available.
- [ ] `bash -n scripts/mb-pipeline-validate.sh` clean; `shellcheck scripts/mb-pipeline-validate.sh` clean.
- [ ] Tests: 9 bats cases added (0 unit/integration python — validator is a bash entrypoint).

**Verification commands:**
```bash
bash -n scripts/mb-pipeline-validate.sh
shellcheck scripts/mb-pipeline-validate.sh
bats tests/bats/test_mb_pipeline_validate.bats
bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml; echo "exit=$?"
```

**Edge cases:** no-PyYAML environment (duplicate-key check skipped, documented in the
heredoc comment); empty `dispatch: {}` (valid — all sub-keys absent); `prefer: {}` /
`model_map: {}` (valid empty maps); a stage block that is just `enabled: false`.

---

### Stage 2 — Duplicate-key rejection in runtime YAML parsers + fix the project pipeline
**Files:**
- `.memory-bank/pipeline.yaml` (FIX: remove the duplicate `judge:` role key at line 34/41)
- `scripts/_lib.sh` (modify the shared `safe_load`-based pipeline read helper, if present)
- `scripts/mb-pipeline.sh` (the `validate` subcommand at line ~292, and any direct `safe_load`)
- `tests/bats/test_mb_pipeline_validate.bats` (extend with a runtime-parser case)

**TDD — write FIRST (RED):**
- `test_runtime_parser_rejects_duplicate_keys` — a fixture pipeline with a duplicate
  top-level `budget:` key; `bash scripts/mb-pipeline.sh validate <dir>` → exit non-zero
  mentioning duplicate (currently returns 0 → RED).
- Add a fixture-based assertion that `.memory-bank/pipeline.yaml` has exactly ONE `judge:`
  key under `roles:` (grep-count guard so the regression cannot reappear).

**Implementation:**
1. Decide the canonical `judge` role for THIS project. The two values are
   `{ agent: main-agent }` (line 34) and `{ agent: mb-judge }` (line 41). Per memory note
   "Judge terminates the review loop" + the active `codex-governed` workflow, the intended
   judge is `mb-judge`. **DECISION (confirm with maintainer if unsure → mark UNCONFIRMED):**
   keep `judge: { agent: mb-judge }` (the later, currently-effective value), delete the
   earlier `judge: { agent: main-agent }` at line 34. This is behavior-preserving (PyYAML
   already used the last value).
2. Introduce a single shared duplicate-key-rejecting loader used by the runtime parsers
   that currently call `yaml.safe_load` on pipeline files. Confirmed callers (13):
   `scripts/_lib.sh`, `mb-pipeline.sh`, `mb-workflow.sh`, `mb-work-plan.sh`,
   `mb-work-budget.sh`, `mb-work-protected-check.sh`, `mb-work-severity-gate.sh`,
   `mb-reviewer-resolve.sh`, `mb-session-spend.sh`, `mb-agent-caps.sh`, `mb-done-gates.sh`,
   `mb-index-json.py`, `mb-pipeline-validate.sh`. SCOPE this stage to the validate path
   (`mb-pipeline.sh validate` + the shared helper in `_lib.sh` if one exists). Other
   callers stay on `safe_load` for now (last-value behavior is benign once the file is
   clean) — leave a one-line note in BACKLOG that full propagation is follow-up.

**DoD:**
- [ ] `.memory-bank/pipeline.yaml` has exactly one `judge:` under `roles:`
      (`grep -c "^  judge:" .memory-bank/pipeline.yaml` == 1).
- [ ] `bash scripts/mb-pipeline.sh validate .memory-bank` returns 0 on the cleaned file
      and non-zero on a duplicate-key fixture.
- [ ] No behavior change to resolved judge agent (still `mb-judge`).
- [ ] `bash -n` + `shellcheck` clean on every modified `.sh`.
- [ ] Tests: 1 new bats case + 1 grep-count guard.

**Verification commands:**
```bash
grep -c "^  judge:" .memory-bank/pipeline.yaml   # expect 1
bash scripts/mb-pipeline.sh validate .memory-bank; echo "exit=$?"
bash scripts/mb-agent-caps.sh resolve --role judge --mb .memory-bank 2>&1 | grep -i mb-judge
bats tests/bats/test_mb_pipeline_validate.bats
```

**Edge cases:** legacy banks without PyYAML (validate falls back, dup-key check skipped —
documented); the cleaned file must still pass the Stage-1 schema additions.

---

### Stage 3 — Executable defaults: `budget.default_limit` + profile `scope` + auto-consume
**Files:**
- `scripts/mb-work-budget.sh` (modify `resolve_pipeline_defaults` + add a default-limit reader)
- `memory_bank_skill/rules_profile.py` (add `ALLOWED_SCOPES`, validate `scope`)
- `scripts/mb-rules-check.sh` + `scripts/mb_rules_check_profile.sh` (auto-resolve project/user profile)
- `commands/work.md` (line ~298: document budget auto-init from `default_limit`)
- `tests/bats/test_mb_work_budget.bats` (CREATE or extend)
- `tests/pytest/test_rules_profile.py` (extend — verify file exists first; else create)
- `tests/bats/test_mb_rules_check.bats` (extend — verify exists first)

**TDD — write FIRST (RED):**
- Budget: `test_budget_uses_default_limit_when_no_total` — pipeline with
  `budget.default_limit: 50000`; `mb-work-budget.sh init` invoked WITHOUT an explicit total
  applies 50000 (currently `init` requires `<total>` → must add a `--from-default` /
  no-arg-resolves-default path). Assert state JSON `total == 50000`.
- Budget: `test_budget_default_limit_null_means_no_budget` — `default_limit: null` and no
  total → no state file created (unlimited), exit 0.
- Profile: `test_validate_rejects_unknown_scope` — `{scope: "team", ...}` →
  `validate_profile` returns a `ValidationError(field="scope", ...)`.
- Profile: `test_validate_accepts_user_and_project_scope` — both valid → no scope error.
- Rules-check: `test_rules_check_auto_consumes_project_profile` — with
  `<bank>/rules-profile.json` present and no `--profile`/`MB_PROFILE`, the project profile
  is loaded; `test_rules_check_cli_profile_overrides_project` — explicit `--profile` wins.

**Implementation:**
1. `mb-work-budget.sh`: extend `resolve_pipeline_defaults` to ALSO read `default_limit`
   (currently only warn/stop). Add behavior: when `cmd_init` is called and `total` is empty,
   resolve `budget.default_limit`; if non-null → use it as total; if null → print
   `[budget] no default_limit; budget tracking off` and exit 0 WITHOUT writing state.
   Keep the explicit `<total>` path and `--budget` (CLI) winning over the default.
2. `rules_profile.py`: add `ALLOWED_SCOPES = ("user", "project")`; in `validate_profile`,
   after schema_version, validate `scope` when present (it is optional in some profiles —
   if absent, no error; if present and not in `ALLOWED_SCOPES`, append a `ValidationError`).
3. `mb-rules-check.sh`: change `PROFILE_PATH="${MB_PROFILE:-}"` resolution so that when no
   `--profile` and no `MB_PROFILE`, it defaults to `<resolved-mb>/rules-profile.json` (and
   user-scope `<agent_config>/rules-profile.json` as a secondary), with explicit CLI/env
   override winning. Resolve the bank via the existing `_lib.sh` helper. Keep file ≤ 400
   lines (delegate the lookup to `mb_rules_check_profile.sh` if it is the natural home).
4. `commands/work.md:298`: update the budget paragraph to state that when `--budget` is not
   passed, a non-null `budget.default_limit` from `pipeline.yaml` is applied automatically;
   `null` = unlimited.

**DoD:**
- [ ] `mb-work-budget.sh init` with no `<total>` applies `budget.default_limit` (non-null)
      and is a no-op (unlimited) when null.
- [ ] `--budget`/explicit total still overrides `default_limit`.
- [ ] `validate_profile({"scope":"bogus"})` yields a `scope` `ValidationError`; `user`/`project`
      accepted; absent `scope` still valid.
- [ ] `mb-rules-check.sh` auto-consumes `<bank>/rules-profile.json` when no CLI/env profile;
      CLI `--profile` overrides.
- [ ] `commands/work.md` budget section matches the new behavior.
- [ ] Tests: ≥2 bats (budget) + ≥2 pytest (profile scope) + ≥2 bats (rules-check auto-consume).
- [ ] `bash -n` + `shellcheck` clean on modified `.sh`; `ruff check memory_bank_skill/rules_profile.py` clean.

**Verification commands:**
```bash
bash -n scripts/mb-work-budget.sh scripts/mb-rules-check.sh && shellcheck scripts/mb-work-budget.sh scripts/mb-rules-check.sh
pytest tests/pytest/test_rules_profile.py -q
bats tests/bats/test_mb_work_budget.bats tests/bats/test_mb_rules_check.bats
ruff check memory_bank_skill/rules_profile.py
```

**Edge cases:** `default_limit: 0` (treat as 0-budget → immediate stop, distinct from null);
profile JSON with `scope` absent (back-compat — no error); both project and user profile
present (project wins over user, CLI wins over both); rules-check run outside any bank
(no profile file → baseline rules only, current behavior preserved).

---

### Stage 4 — Config ownership: `mb-config` ↔ `mb-pipeline` `.mb-config` split
**Files:**
- `scripts/mb-config.sh` (add `pipeline` get/set/validate delegating to `mb-pipeline.sh`)
- `commands/config.md` (document the shared `.mb-config` ownership + new `pipeline` key)
- `tests/bats/test_mb_config.bats` (extend — verify exists first; else create)

**TDD — write FIRST (RED):**
- `test_mb_config_get_pipeline_reads_mbconfig` — after `mb-pipeline.sh use <name>` writes
  `pipeline=<name>`, `mb-config get pipeline` returns `<name>` (currently `unknown key`).
- `test_mb_config_set_pipeline_validates_name` — `mb-config set pipeline "../evil"` →
  exit 2 (reuses `mb-pipeline.sh`'s `valid_pipeline_name`).
- `test_mb_config_unknown_key_still_rejected` — `mb-config get nope` → exit 2 (regression).

**Implementation:**
Add a `pipeline` key to `mb-config.sh`'s `cmd_get`/`cmd_set` that delegates to
`scripts/mb-pipeline.sh` (`path`/`use`/`valid_pipeline_name`), so the two scripts share ONE
documented owner for `<bank>/.mb-config`. Do NOT duplicate the pipeline name grammar —
source/call `mb-pipeline.sh`. Update the `mb-config.sh` header `Keys:` block to list both
`lang` and `pipeline`, and `commands/config.md` to state that `.mb-config` is co-owned and
both keys are managed through `mb-config`.

**DoD:**
- [ ] `mb-config get pipeline` / `set pipeline <name>` work and round-trip through `.mb-config`.
- [ ] Invalid pipeline names rejected (exit 2) via the existing `valid_pipeline_name`.
- [ ] `lang` behavior unchanged; unknown keys still exit 2.
- [ ] Header + `commands/config.md` document the shared ownership.
- [ ] Tests: ≥3 bats cases; `bash -n` + `shellcheck` clean.

**Verification commands:**
```bash
bash -n scripts/mb-config.sh && shellcheck scripts/mb-config.sh
bats tests/bats/test_mb_config.bats
bash scripts/mb-config.sh get lang; bash scripts/mb-config.sh set pipeline default; bash scripts/mb-config.sh get pipeline
```

**Edge cases:** `.mb-config` absent (get pipeline → empty/default, exit 0 or graceful);
`mb-pipeline.sh` not co-located (resolve via `SCRIPT_DIR`); name with `/` or `..` rejected.

---

### Stage 5 — Doc regeneration + GENERATED consistency checks (anti-drift)
**Files:**
- `README.md` (fix the `25` table cell at :41 → 29; ensure :259 stays 29; add the 3 missing
  command rows `/analyze-task`, `/flow`, `/goal`; update `20+ sub-commands` if it drifts)
- `commands/mb.md` (add `reindex` to the router table; OR remove `/mb reindex` from public
  docs — DECISION below)
- `references/hooks.md` (regenerate: replace "five" claims at :3,:188,:230 with the actual
  tool-vs-lifecycle split derived from `settings/hooks.json`)
- `tests/pytest/test_doc_counts.py` (EXTEND — new generated assertions)
- `scripts/mb-hooks-doc-gen.sh` or `scripts/mb-hooks-doc.py` (CREATE — generate the hooks
  reference table from `settings/hooks.json`; pytest asserts doc ⊇ generator output)

**TDD — write FIRST (RED), extending `tests/pytest/test_doc_counts.py`:**
- `test_readme_command_table_lists_every_command` — parse the per-command table; the set of
  first-column `/x` tokens (excluding `/mb <sub>`) must equal `{commands/*.md stems} - {mb}`.
  Currently missing `/analyze-task`, `/flow`, `/goal` → RED.
- `test_readme_summary_table_cell_matches_command_count` — the metrics table at README:39-41
  "Slash commands" cell must equal the `commands/*.md` count (29) → catches the stale `25`.
- `test_mb_router_lists_reindex_iff_public_docs` — if `/mb reindex` appears in README OR
  SKILL.md, it MUST appear in the `commands/mb.md` router table (and vice-versa). Locks the
  reindex decision either way → currently RED.
- `test_hooks_md_covers_every_settings_hook` — every hook script referenced in
  `settings/hooks.json` must appear in `references/hooks.md`; and `references/hooks.md` must
  NOT claim a literal "five" count (assert no `\bfive\b` count-claim, or assert the stated
  count == distinct lifecycle hooks). Currently RED ("five" + missing lifecycle hooks).

**Implementation:**
1. `README.md`: change the summary-table cell `25` (:41) → `29`; add three rows to the
   command table (`/analyze-task`, `/flow`, `/goal` with one-line purposes pulled from each
   command file's intro). Keep `**29 top-level slash-commands**` at :259.
2. `commands/mb.md`: **DECISION — ADD routing** (impl `hooks/mb-reindex.sh` exists and the
   semantic-index layer is a real, documented feature; removing public docs would lose a
   working capability). Add a `reindex [--full|--incremental]` row to the router table and a
   short `### reindex` section pointing at `hooks/mb-reindex.sh` + `mb-semantic-bootstrap.sh`.
   (If maintainer prefers removal instead → delete README:312 + SKILL:290-291 rows; the
   pytest enforces consistency either way. Mark this as the one open DECISION.)
3. `references/hooks.md`: add a generator (`scripts/mb-hooks-doc.py`, stdlib-only) that reads
   `settings/hooks.json`, emits a markdown table grouped into **tool hooks** (PreToolUse/
   PostToolUse) vs **lifecycle hooks** (Setup/SessionStart/SessionEnd/Stop/PreCompact/
   Notification/UserPromptSubmit). Rewrite `references/hooks.md` intro to drop the "five"
   wording and embed/reference the generated table (between `<!-- mb:hooks:begin -->` /
   `<!-- mb:hooks:end -->` markers so the pytest can compare). Update :188/:230 wording.
4. Extend `tests/pytest/test_doc_counts.py` with the 4 generated assertions above. Prefer
   parsing the filesystem/JSON as the source of truth — NO hardcoded numbers in assertions.

**DoD:**
- [ ] README summary cell = 29; command table contains all 29 commands (28 `/x` rows + the
      `/mb <sub>` hub row); :259 says 29.
- [ ] `/mb reindex` consistent across README, SKILL.md, and `commands/mb.md` router.
- [ ] `references/hooks.md` lists every `settings/hooks.json` hook, split tool vs lifecycle,
      with NO stale "five" count claim.
- [ ] `scripts/mb-hooks-doc.py` regenerates the table deterministically (idempotent).
- [ ] 4 new pytest cases pass and are GENERATED (source-of-truth driven, no magic numbers).
- [ ] `ruff check scripts/mb-hooks-doc.py` clean; `pytest tests/pytest/test_doc_counts.py` green.

**Verification commands:**
```bash
ruff check scripts/mb-hooks-doc.py
python3 scripts/mb-hooks-doc.py --check   # idempotent regen check (no diff)
pytest tests/pytest/test_doc_counts.py -q
```

**Edge cases:** a new command added later (table-coverage test fails until the row exists —
that is the point); a hook added to `settings/hooks.json` (hooks-md test fails until
regenerated); `/mb <sub>` hub row must be excluded from the per-command equality set.

---

### Stage 6 — Stale-count / synopsis cleanup (covered by generated checks where possible)
**Files:**
- `commands/mb.md` (line 52 graph flags; line 929 "18 subcommands")
- `commands/work.md` (line 12 / 416 / 482 stale "Phase 4 will add --slim/--full"; line 472
  `max-cycles` → `--max-cycles`)
- `commands/done.md` (line 42 "6-step flow" → 8 steps, or drop the count)
- `SKILL.md` (line 219 test-runner JSON — add `tests_failed`)
- `references/structure.md` (line 269 god-nodes "Top-20 by degree" → PageRank primary,
  degree fallback)
- `tests/pytest/test_doc_counts.py` (EXTEND with cheap generated guards where feasible)

**TDD — write FIRST (RED) where a generated check is feasible:**
- `test_mb_help_subcommand_count_or_no_count` — `commands/mb.md` must NOT hardcode a wrong
  router count: assert either no `\d+ subcommands` literal OR that the literal equals the
  actual router-table row count parsed from the file. Currently "18 subcommands" ≠ actual → RED.
- `test_skill_test_runner_json_lists_tests_failed` — the `mb-test-runner` row in SKILL.md
  must mention `tests_failed` (which `mb-test-run.sh:202` emits). Currently RED.
- `test_done_md_step_count_matches_listed_steps` — if `commands/done.md` states "N-step",
  N must equal the count of numbered `^\d+\.` step lines in that section (8). Currently
  "6-step" ≠ 8 → RED.
- The remaining NITs (mb.md:52 `--docs/--sessions`, work.md Phase-4 wording,
  work.md:472 `--max-cycles`, structure.md PageRank) are prose-only — fix manually; add a
  lightweight `test_mb_graph_flag_docs_mention_docs_and_sessions` (assert `commands/mb.md`
  graph summary line mentions `--docs` and `--sessions`) since the script supports both.

**Implementation:**
1. `commands/mb.md:52`: add `--docs` and `--sessions` to the graph router synopsis (the
   detailed `### graph` at :687 also gains `--sessions`). Line 929: replace "18 subcommands"
   with a count-free phrasing ("the full router table below") OR the correct generated count.
2. `commands/work.md`: rewrite the Phase-4 paragraphs (:12, :416, :482) as CURRENT behavior
   — `--slim`/`--full` are implemented via `hooks/mb-context-slim-pre-agent.sh`; drop
   "Phase 4 will add". Fix `:472` `max-cycles` → `--max-cycles`.
3. `commands/done.md:42`: change "6-step flow" → "8-step flow" (8 steps are listed) or drop
   the count.
4. `SKILL.md:219`: add `tests_failed` to the documented test-runner JSON shape.
5. `references/structure.md:269`: change "Top-20 nodes by degree" → "Top nodes by PageRank
   (degree fallback when networkx absent)".
6. Extend `tests/pytest/test_doc_counts.py` with the generated guards above.

**DoD:**
- [ ] `commands/mb.md` graph synopsis mentions `--docs` + `--sessions`; no wrong hardcoded
      "18 subcommands".
- [ ] `commands/work.md` describes `--slim`/`--full` as current; uses `--max-cycles`.
- [ ] `commands/done.md` step count matches the 8 listed steps.
- [ ] `SKILL.md` test-runner JSON includes `tests_failed`.
- [ ] `references/structure.md` documents PageRank-primary god-node ranking.
- [ ] Tests: 4 new generated pytest guards green.
- [ ] `pytest tests/pytest/test_doc_counts.py` green; no other doc test regressions.

**Verification commands:**
```bash
pytest tests/pytest/test_doc_counts.py -q
grep -n -- '--docs' commands/mb.md | head     # graph synopsis present
grep -n 'tests_failed' SKILL.md               # documented
```

**Edge cases:** the step-count regex must scope to the `done.md` flow section only (not the
whole file); the "18 subcommands" guard must count router rows, not table rows elsewhere.

---

## Verification (whole plan)

```bash
# Bash entrypoints
bash -n scripts/mb-pipeline-validate.sh scripts/mb-work-budget.sh scripts/mb-rules-check.sh \
        scripts/mb-config.sh scripts/mb-pipeline.sh scripts/mb-hooks-doc.py 2>/dev/null
shellcheck scripts/mb-pipeline-validate.sh scripts/mb-work-budget.sh scripts/mb-rules-check.sh scripts/mb-config.sh

# Python
ruff check memory_bank_skill/rules_profile.py scripts/mb-hooks-doc.py
pytest tests/pytest/test_rules_profile.py tests/pytest/test_doc_counts.py -q

# Bats
bats tests/bats/test_mb_pipeline_validate.bats tests/bats/test_mb_work_budget.bats \
     tests/bats/test_mb_rules_check.bats tests/bats/test_mb_config.bats

# End-to-end sanity
bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml; echo "default exit=$?"
bash scripts/mb-pipeline.sh validate .memory-bank; echo "project exit=$?"
python3 scripts/mb-hooks-doc.py --check
```

## DoD (plan-level)

- [ ] Stage 1: validator schema-checks review/judge/review_ensemble/done_gates/
      done_placeholders/dispatch + per-stage `enabled`; duplicate-key rejection (PyYAML).
- [ ] Stage 2: `.memory-bank/pipeline.yaml` has one `judge:` role; `mb-pipeline.sh validate`
      rejects duplicate keys; resolved judge agent unchanged (`mb-judge`).
- [ ] Stage 3: `budget.default_limit` applied when no CLI budget; profile `scope` validated;
      project rule profiles auto-consumed (CLI override wins).
- [ ] Stage 4: `mb-config` owns both `lang` and `pipeline` keys of `.mb-config`.
- [ ] Stage 5: README count/table + `references/hooks.md` regenerated; reindex consistent;
      4 GENERATED consistency pytests added to `test_doc_counts.py`.
- [ ] Stage 6: stale counts/synopses fixed; 4 generated guards added.
- [ ] All new + existing pytest/bats green; shellcheck + ruff clean; files ≤ 400 lines;
      no placeholders.
- [ ] Drift cannot silently recur: every count/table/hooks claim is asserted from the
      source of truth (filesystem / `settings/hooks.json` / `mb-test-run.sh`).

## Open decisions / UNCONFIRMED

- **`/mb reindex` (Stage 5):** ADD routing to `commands/mb.md` (recommended — impl exists)
  vs REMOVE from README/SKILL. Plan assumes ADD; the generated pytest enforces whichever is
  chosen. **Maintainer confirmation requested.**
- **`judge` role value (Stage 2):** plan keeps `mb-judge` (the currently-effective last
  value). If the intent was `main-agent`, flip the deletion — behavior would then change.
  Marked as a confirm-if-unsure decision.
- Full propagation of the duplicate-key-rejecting loader to ALL 13 `safe_load` callers is
  deferred to a follow-up BACKLOG item (Stage 2 scopes it to the validate path).
