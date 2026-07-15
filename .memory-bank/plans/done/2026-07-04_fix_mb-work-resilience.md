---
type: fix
scope: mb-work-resilience
created: 2026-07-04
status: done
priority: HIGH
complexity: L
backlog: I-093
---

# Fix: /mb work engine resilience (durable loop-state · deterministic checkbox flip · lenient external review · codex preflight)

Hardens the `/mb work` execution engine so a governed run survives compaction / abort, enforces
`max_cycles` deterministically (not from the orchestrator's memory), only flips DoD checkboxes after
the gate actually passes, tolerates a real cross-model reviewer's "APPROVED with 1 minor" output, and
never lets a dead codex CLI silently disable the cross-model gate.

Tracked as backlog **I-093**. Four independent themes (T1–T4), 9 bite-sized stages. All findings below
were **re-verified against the current code at the cited lines on 2026-07-04**.

## Goal

Move the four fragile pieces of the `/mb work` loop from orchestrator-memory into deterministic,
crash-surviving scripts: (T1) a durable `<bank>/.work-state.json` cycle counter that enforces
`max_cycles` by exit code and binds the token budget to a `run_id`; (T2) a checkbox flipper that only
fires after judge-GO and an explicit ban on implement-agents editing checkboxes; (T3) a `--external`
lenient reviewer parser that normalizes "APPROVED-with-issues" and consumes the `codex-reviewer`
SKIPPED contract; (T4) a codex preflight that degrades loudly (records `cross-model review SKIPPED`)
and forces confirmation under `--auto`.

## Scope

### Входит
- `scripts/mb-work-state.sh` (NEW) — durable loop-state + `max_cycles` enforcement by exit code.
- `scripts/mb-work-budget.sh` (EDIT) — bind budget to `run_id`; ignore orphaned state from an aborted run.
- `scripts/mb-work-checkbox.sh` (NEW) — deterministic DoD-checkbox flip, gated on `.work-state.json phase=done`.
- `scripts/mb-work-review-parse.sh` (EDIT) — `--external` lenient normalization + `codex-reviewer` SKIPPED passthrough.
- `scripts/mb-work-codex-preflight.sh` (NEW) — codex availability/auth health-check, fail-safe.
- `commands/work.md` (EDIT) — wire all four into the 5a–5g loop, resume path, and the Hard-stops table.
- Tests: `tests/pytest/test_mb_work_state.py`, `test_mb_work_checkbox.py`, `test_mb_work_codex_preflight.py` (NEW);
  extend `test_mb_work_budget.py`, `test_mb_work_review_parse.py`; extend `tests/bats/test_mb_work_command_doc.bats`.

### НЕ входит
- Any `hooks/mb-session-*`, `scripts/mb-session-*`, `session-end-autosave.sh`, `hooks/lib/session-common.sh`,
  `hooks/lib/extract-tools-files.sh`, `scripts/mb-freshness.sh`, `settings/hooks.json`, `SKILL.md`,
  `commands/done.md`, `references/session-memory.md` — **owned by the queued plan
  `2026-07-04_fix_session-capture-and-mb-hygiene.md` (I-087)**. See *Zones of non-contact* below.
- Changing the `max_cycles` **value** in any pipeline file (the value already exists; this plan only
  makes it **enforced**).
- Authoring the `codex-reviewer` subagent (already shipped globally at `~/.claude/agents/codex-reviewer.md`);
  this plan makes the loop *consume* its contract.
- Ensemble-reviewer fan-out mechanics, `mb-fanout.sh`, dispatcher transports (I-084 territory).

## Assumptions
- The `/mb work` loop is orchestrated by the code-agent following `commands/work.md`; the scripts are the
  deterministic backbone the orchestrator MUST call, so "enforcement by exit code" means the doc mandates
  reacting to those exit codes. Doc-contract bats tests lock this in (mirroring the existing
  `test_mb_work_command_doc.bats` pattern).
- `run_id` is generated once per item-run by `mb-work-state.sh init` (or supplied via `--run-id`) and
  threaded to `mb-work-budget.sh`.
- All new/edited shell runs under `set -eu`, PyYAML-optional, atomic writes (`mktemp` → `mv`), bash 3.2
  **and** 5.x (no `mapfile`, no `declare -A`, no `${var^^}`), shellcheck-clean, ≤400 lines.
- Design contract: **fail-safe** (a malformed/absent state file must never wedge a session — degrade to
  a no-op, not a crash); **token-economical defaults**; any default-behaviour change ships behind an
  `MB_*` opt-out. The one intentional non-zero exit is the **cycle-exhausted** signal (exit 3) — that is
  the enforcement, not a failure.
- Next free backlog id verified = **I-093** (bank max = I-092).

## Correction to the audit brief (verified)
- The brief cited `flow-templates/phase71-governed.yaml:66 max_cycles:4`. **That file does not exist.**
  The real `max_cycles` lives in `references/pipeline.default.yaml`: `workflows.governed-execution.loop.max_cycles: 2`
  (line 94), `workflows.full.loop.max_cycles: 2` (line 63), `review.max_cycles: 3` (line 167). The finding
  itself holds — the cap is defined but only enforced in the orchestrator's head. This plan enforces
  whatever value the resolved pipeline declares; it does not hard-code `2` or `4`.
- All other cited lines confirmed: `commands/work.md:306-323` (implement prompt), `:371-379` (5f fix-cycle);
  `scripts/mb-work-plan.sh:324-330` (source-dependent status/dod from self-set checkboxes, via
  `detect_status_plan` :244-253 / `_plan_checkbox_states` :226-241); `scripts/mb-work-review-parse.sh:140-148`
  (strict APPROVED cross-check; existing `--lenient` :86-91 is only a JSON-fail Markdown fallback, it does
  NOT normalize "APPROVED with issues"); `scripts/mb-work-budget.sh:152-186` (`cmd_check`, no run-id, orphaned
  `.work-budget.json` survives an abort).

## Риски
| Риск | Вероятность | Impact | Mitigation |
|------|-------------|--------|------------|
| Cycle-exhausted exit code clashes with usage/parse exit 2 | Med | Loop misreads halt as usage error | Reserve a **distinct exit 3** for "cycle budget exhausted"; keep 2=usage; document in work.md hard-stops |
| Checkbox flipper corrupts a plan/spec body | Low | Data loss in plan file | Atomic `mktemp`→`mv`; flip ONLY within the item's marker block; gate on `.work-state.json phase=done`; idempotent |
| `--external` normalization masks a real reviewer failure | Med | False PASS | Recompute counts from issues; "APPROVED+issues"→CHANGES_REQUESTED (stricter, never looser); strict mode stays default and byte-identical |
| Orphaned `.work-budget.json` throttles a new run | Med (observed) | New run stops early | run_id guard: `add`/`check` on a mismatched run_id → warn + no-op; `init` auto-resets a stale run_id |
| Codex preflight false-negative kills a healthy gate | Low | Cross-model review skipped needlessly | Preflight is advisory + fail-safe (exit 0); loud SKIPPED note is recoverable; `--auto` asks, does not abort the item |
| Merge churn on `commands/work.md` (4 wiring stages) | High | Rebase pain | Single owner for work.md; land wiring stages sequentially S3→S5→S7→S9 (see merge section) |

---

<!-- mb-stage:1 -->
## Stage 1 (T1): `scripts/mb-work-state.sh` — durable loop-state + max_cycles enforcement
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester для red)
**Файлы:** `scripts/mb-work-state.sh` (создать, `+x`), `tests/pytest/test_mb_work_state.py` (создать, тесты FIRST)

**Confirmed gap:** the fix-cycle counter lives only in the orchestrator's context (`commands/work.md:371-379`
reads `workflow.loop.max_cycles` but nothing persists the current cycle). A compact/abort loses the count;
real sessions ran 5 rounds against a `max_cycles: 2` cap. No `.work-state.json` exists anywhere
(`grep -rl work-state scripts hooks commands` → empty).

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_state.py` (mirror `test_mb_work_budget.py` `_run`/`_init_mb` style):
   - `test_init_creates_state_and_prints_run_id` — `init plans/x.md 2 --mb <bank>` → `<bank>/.work-state.json` exists,
     stdout is a non-empty `run_id`, JSON has `cycle:0`, `phase:"in-progress"`, `item_no:2`, `max_cycles` populated.
   - `test_init_accepts_explicit_run_id` — `--run-id fixed-id` → state `run_id == "fixed-id"`.
   - `test_step_appends_transition` — after `step implement` then `step verify`, `status` JSON `steps == ["implement","verify"]`.
   - `test_cycle_increments_and_passes_under_cap` — `init … --max-cycles 2`; `cycle` → exit 0, `cycle==1`; `cycle` again → exit 0, `cycle==2`.
   - `test_cycle_exhausted_returns_exit_3` — third `cycle` (cycle would be 3 > 2) → **exit 3**, stderr contains `cycle budget exhausted`.
   - `test_done_sets_phase_done` — `done` → `status` JSON `phase == "done"`.
   - `test_clear_removes_state` — `clear` → file gone.
   - `test_status_missing_state_is_fail_safe` — `status` with no file → exit 0, empty/`{}` stdout (never crash a session).
   - `test_malformed_state_is_fail_safe` — corrupt JSON → `status` exit 0 (degrade, no traceback).
2. **Implement** `scripts/mb-work-state.sh` (`set -eu`, `source _lib.sh`, atomic `mktemp`→`mv`):
   - State `<bank>/.work-state.json`: `{run_id, source, item_no, heading, cycle, max_cycles, steps[], phase, updated}`.
   - Subcommands (each takes `[--mb <path>]`): `init <source> <item_no> [--run-id ID] [--max-cycles N] [--heading TXT]`
     (prints run_id; auto-resets any existing state); `step <name>`; `cycle` (increment; **exit 3** when `cycle > max_cycles`);
     `status` (print JSON); `done` (phase=done); `clear` (rm).
   - `max_cycles` default resolved from `references/pipeline.default.yaml`/project pipeline via `mb-pipeline.sh path`
     when `--max-cycles` absent (reuse the `PIPELINE_YAML` PyYAML-optional pattern from `mb-work-budget.sh:28-46`).
   - Exit codes: 0 ok · 2 usage · 3 cycle-exhausted · fail-safe (missing/corrupt state on read subcommands → exit 0).

### DoD
- [x] `mb-work-state.sh init` writes `.work-state.json` with `cycle:0`/`phase:"in-progress"` and prints a unique `run_id`.
- [x] `cycle` returns exit 0 while `cycle ≤ max_cycles`, **exit 3** the run after it would exceed the cap (deterministic, memory-free).
- [x] `max_cycles` resolved from the effective pipeline when `--max-cycles` omitted (no hard-coded number).
- [x] Read subcommands are fail-safe: missing/corrupt state → exit 0, no traceback.
- [x] Тесты: 9 pytest green; `shellcheck` clean; file ≤400 lines; `+x` bit set; runs on bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_state.py -q
shellcheck scripts/mb-work-state.sh
test -x scripts/mb-work-state.sh
/bin/bash -c 'bash scripts/mb-work-state.sh -h >/dev/null && echo bash3.2-ok'
```
### Edge cases
- `init` over an existing state from a different `run_id` → overwrite (auto-reset), do not merge.
- `cycle`/`step`/`done` with no state file → exit 2 (usage: "no active work-state; run init first") — distinct from fail-safe reads.
- Concurrent writers: atomic temp→mv makes the last writer win without truncation.

---

<!-- mb-stage:2 -->
## Stage 2 (T1): bind `mb-work-budget.sh` to `run_id` (ignore orphaned state)
**Complexity:** S · **~4 мин** · **Зависимости:** Stage 1 (run_id contract) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-budget.sh` (edit), `tests/pytest/test_mb_work_budget.py` (extend, tests FIRST)

**Confirmed gap:** `.work-budget.json` (`scripts/mb-work-budget.sh:79/111/137/163/199`) has no run binding; after an
abort the file survives with `spent>0` (`cmd_check` :152-186 reads it verbatim), so the **next** run that forgets to
re-init inherits stale spend and stops early.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_budget.py` (new cases, keep existing 8 green):
   - `test_init_records_run_id` — `init 100000 --run-id r1` → `.work-budget.json` has `run_id == "r1"`.
   - `test_init_resets_stale_run_id` — pre-seed a budget with `run_id=old`, `spent=90000`; `init 100000 --run-id r2`
     → `spent==0`, `run_id=="r2"` (orphan auto-reset).
   - `test_add_run_id_mismatch_is_noop_warn` — budget `run_id=r1`; `add 50000 --run-id r2` → exit 1, `spent` unchanged, stderr `run_id mismatch`.
   - `test_check_run_id_mismatch_ignores_stale` — budget `run_id=r1` spent 100001; `check --run-id r2` → exit 1 (warn, treated as stale) NOT exit 2 stop.
   - `test_add_no_run_id_backcompat` — `add 10000` with no `--run-id` → applies as today (back-compat).
2. **Implement**:
   - `cmd_init`: accept `--run-id`; write `run_id` into state; if an existing state has a different `run_id`, overwrite (reset spent).
   - `cmd_add`/`cmd_check`: accept `--run-id`; when supplied AND state `run_id` differs → stderr `run_id mismatch (stale budget)`, **exit 1** (warn, no mutation / no stop). Absent `--run-id` → current behaviour unchanged.
   - Keep all existing exit-code semantics (0/1/2) and the `status` output format additive (`run_id=` field appended).

### DoD
- [x] `init --run-id` stamps the budget; a differing pre-existing `run_id` is auto-reset (no stale spend carried over).
- [x] `add --run-id`/`check --run-id` on a mismatched run → exit 1 warn, zero mutation, never a false stop.
- [x] Back-compat: all 8 existing `test_mb_work_budget.py` tests stay green (no `--run-id` path unchanged).
- [x] Тесты: 5 new + 8 existing pytest green; `shellcheck` clean; file ≤400 lines.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_budget.py -q
shellcheck scripts/mb-work-budget.sh
```
### Edge cases
- `status` on a run-id-stamped budget prints the id; consumers parsing the old format still find `total=/spent=/pct=`.
- `--run-id` empty string treated as "not supplied" (back-compat path).

---

<!-- mb-stage:3 -->
## Stage 3 (T1): wire durable state + budget run_id into `commands/work.md`
**Complexity:** M · **~5 мин** · **Зависимости:** Stage 1, Stage 2 · **Агент:** developer (+ tester)
**Файлы:** `commands/work.md` (edit — steps 4, 5f, 5g, resume, Hard-stops table, Underlying scripts),
`tests/bats/test_mb_work_command_doc.bats` (extend, tests FIRST)

**Confirmed gap:** `commands/work.md` step 5f (`:371-379`) drives the fix-cycle from `workflow.loop.max_cycles` with no
persisted counter; the Hard-stops table (`:390-402`) has no `.work-state.json` / cycle-exhausted entry; resume after
compact has no state source.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test` cases, grep-on-doc pattern):
   - doc mentions `mb-work-state.sh` and `.work-state.json`.
   - doc states the loop calls `mb-work-state.sh cycle` at 5f and **halts on exit 3** ("cycle budget exhausted").
   - doc's Hard-stops table lists the cycle-exhausted trigger surfaced via `mb-work-state.sh cycle`.
   - doc states budget init/check are threaded with `--run-id` from `mb-work-state.sh init`.
   - doc describes the **resume** path: on a fresh run, read `mb-work-state.sh status`; `phase:in-progress` for the
     item means mid-flight (do not treat as done even if checkboxes look flipped).
2. **Edit** `commands/work.md`:
   - Step 4 (budget init): capture `RUN_ID=$(bash scripts/mb-work-state.sh init <source> <n> --mb <bank>)`, pass
     `--run-id "$RUN_ID"` to every `mb-work-budget.sh` call.
   - Step 5f: replace memory-driven cycle counting with `bash scripts/mb-work-state.sh cycle --mb <bank>`; **exit 3 → halt**
     (even under `--auto`); on `on_max_cycles=judge_decides` run judge once more, else `stop_for_human`.
   - Step 5g: after judge-GO call `bash scripts/mb-work-state.sh done --mb <bank>` (sets the flip gate for T2); at end-of-run `clear`.
   - Add resume paragraph + a Hard-stops row: `max_cycles reached | mb-work-state.sh cycle exit 3 | yes`.
   - Add `mb-work-state.sh` to the "Underlying scripts" block.

### DoD
- [x] `commands/work.md` documents `.work-state.json`, the `cycle`→exit-3 halt, and budget `--run-id` threading.
- [x] Hard-stops table has an explicit cycle-exhausted row citing `mb-work-state.sh cycle`.
- [x] Resume path reads `mb-work-state.sh status` and treats `phase:in-progress` as mid-flight.
- [x] Тесты: 5 new bats `@test` green; existing `test_mb_work_command_doc.bats` green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- Non-governed workflows (`execution`) have no `fix` step → state is still initialised (for resume) but `cycle` is never called; doc must say cycle enforcement applies only when `fix` is in the workflow.
- `--max-cycles N` CLI flag still overrides; doc threads it into `mb-work-state.sh init --max-cycles N`.

---

<!-- mb-stage:4 -->
## Stage 4 (T2): `scripts/mb-work-checkbox.sh` — deterministic DoD flip, gated on state=done
**Complexity:** M · **~5 мин** · **Зависимости:** Stage 1 (reads `.work-state.json phase`) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-checkbox.sh` (создать, `+x`), `tests/pytest/test_mb_work_checkbox.py` (создать, тесты FIRST)

**Confirmed gap:** item status is *derived* from self-set checkboxes every run (`scripts/mb-work-plan.sh:324-330` via
`detect_status_plan`/`_plan_checkbox_states` :226-253). An implement-agent that ticks `[x]` before gates pass makes the
item silently `done` on resume; an abort before any flip re-dispatches the whole stage. No flip script exists.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_checkbox.py`:
   - `test_flip_marks_item_checkboxes_done` — plan with a `mb-stage:2` marker block containing `- ✅ a` / `- [x] b`;
     state `phase:done`; `flip <plan> 2` → those become `- ✅ a` / `- [x] b`.
   - `test_flip_scopes_to_item_block_only` — checkboxes in stage 1 and 3 are untouched when flipping stage 2.
   - `test_flip_refused_when_state_not_done` — state `phase:in-progress` → exit 1, file byte-identical (no premature flip).
   - `test_flip_is_idempotent` — second `flip` on an already-done block → no change (byte-identical).
   - `test_flip_spec_task_block` — a `tasks.md` with a `mb-task:1` marker and `- [x]` items flips correctly.
   - `test_flip_missing_item_is_usage_error` — item number absent from file → exit 2.
   - `test_flip_missing_state_is_fail_safe_refuse` — no `.work-state.json` → exit 1 refuse (never a blind flip), no crash.
2. **Implement** `scripts/mb-work-checkbox.sh flip <plan-or-spec> <item_no> [--mb <path>]`:
   - Read `.work-state.json` (via `mb-work-state.sh status` or direct); flip **only if** `phase == "done"` AND `item_no` matches — else exit 1 (refuse).
   - Within the item's marker block only (`<!-- mb-stage:N -->` / `<!-- mb-task:N -->` up to the next marker or EOF),
     rewrite `- ✅`→`- ✅` and `- [x]`→`- [x]` (both checkbox dialects `mb-work-plan.sh` recognises). Atomic `mktemp`→`mv`.
   - Idempotent; usage exit 2 for a missing item / bad args.

### DoD
- [x] `flip` converts an item's `✅`/`[ ]` DoD bullets to `✅`/`[x]` only inside that item's marker block.
- [x] Flip is **refused** (exit 1, zero mutation) unless `.work-state.json phase == done` for the matching item.
- [x] Idempotent and atomic; other items' checkboxes never touched.
- [x] Тесты: 7 pytest green; `shellcheck` clean; ≤400 lines; `+x`; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_checkbox.py -q
shellcheck scripts/mb-work-checkbox.sh
test -x scripts/mb-work-checkbox.sh
```
### Edge cases
- Mixed emoji/markdown checkboxes in one block → both dialects flipped.
- Item block whose bullets are already all done → no-op (idempotent).
- `run_id`/`item_no` mismatch between state and requested flip → refuse (exit 1).

---

<!-- mb-stage:5 -->
## Stage 5 (T2): wire flip + "implementers must not touch checkboxes" + state-based resume into `commands/work.md`
**Complexity:** S · **~4 мин** · **Зависимости:** Stage 4, Stage 1 · **Агент:** developer (+ tester)
**Файлы:** `commands/work.md` (edit — 5a implement prompt `:306-323`, 5g `:381-386`, resume note),
`tests/bats/test_mb_work_command_doc.bats` (extend, tests FIRST)

**Confirmed gap:** the implement dispatch prompt (`commands/work.md:306-323`) never forbids editing DoD checkboxes; 5g
(`:381-386`) says "mark DoD items satisfied … after all steps passed" as prose, not a deterministic call.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc's implement prompt explicitly instructs the agent **NOT** to tick/flip DoD checkboxes (`✅`/`[ ]`).
   - doc's 5g calls `mb-work-checkbox.sh flip` (deterministic), only after `mb-work-state.sh done`.
   - doc's resume note: item completion is decided by `.work-state.json phase`, not by checkbox appearance.
2. **Edit** `commands/work.md`:
   - 5a prompt (`:306-323`): append a line — *"Do NOT edit DoD checkboxes (`✅`/`[ ]` → `✅`/`[x]`); the loop flips them deterministically via `mb-work-checkbox.sh` only after judge-GO."*
   - 5g (`:381-386`): replace the "mark DoD items satisfied" prose with the sequence
     `mb-work-state.sh done` → `mb-work-checkbox.sh flip <source> <n> --mb <bank>`; note that a refused flip (exit 1) means the gate did not truly pass.
   - Resume note (near step 5 preamble): trust `.work-state.json phase` over checkbox state to detect a mid-flight item.

### DoD
- [x] Implement prompt in the doc bans agents from editing DoD checkboxes.
- [x] 5g documents the deterministic `mb-work-state.sh done` → `mb-work-checkbox.sh flip` sequence.
- [x] Resume note makes `.work-state.json phase` the source of truth for completion.
- [x] Тесты: 3 new bats `@test` green; existing doc tests green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- `execution` workflow (no judge): 5g still routes through `mb-work-state.sh done` (set after `verify` PASS) so the flip stays deterministic even without a judge step.
- Spec-task source (`tasks.md`): flip targets `<!-- mb-task:N -->` blocks (Stage 4 already covers).

---

<!-- mb-stage:6 -->
## Stage 6 (T3): `mb-work-review-parse.sh --external` — lenient normalization + codex SKIPPED contract
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-review-parse.sh` (edit), `tests/pytest/test_mb_work_review_parse.py` (extend, тесты FIRST)

**Confirmed gap:** strict cross-checks (`scripts/mb-work-review-parse.sh:140-148`) fail when APPROVED carries any issue or
non-zero count — a real GPT reviewer's "APPROVED with 1 minor" → exit 1, no retry. Existing `--lenient` (:86-91) is only a
JSON-parse-fail Markdown fallback, not a normalizer. The parser also cannot consume the `codex-reviewer` subagent's
`{"status":"SKIPPED"|"OK", …, "issues":[{severity,description,recommendation,line:null}], "counts":{…,info}}` contract
(`~/.claude/agents/codex-reviewer.md`).

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_review_parse.py` (new cases, keep existing 12 green):
   - `test_external_approved_with_issues_normalizes_to_changes` — `--external`, verdict APPROVED + 1 minor issue →
     exit 0, out `verdict=="CHANGES_REQUESTED"`, `counts.minor==1` (recomputed from issues).
   - `test_external_maps_codex_schema` — `--external` input with `description`/`recommendation`/`line:null`/`severity:"info"`
     → normalized issue has `message`/`fix`/`line:0`/`severity:"minor"`.
   - `test_external_skipped_passthrough` — `{"status":"SKIPPED","reason":"codex CLI 403 auth"}` → exit 0,
     out `verdict=="SKIPPED"`, `reason` preserved, `counts` all 0, `issues:[]`.
   - `test_external_status_ok_approved_clean_stays_approved` — `--external`, status OK, APPROVED, no issues → verdict APPROVED (unchanged).
   - `test_strict_mode_unchanged_backcompat` — without `--external`, "APPROVED with issues" still exits 1 (strict path byte-stable).
2. **Implement** in the embedded python of `mb-work-review-parse.sh`:
   - Add `--external` flag (implies lenient normalization). Precedence: `--external` ⊃ `--lenient` behaviours.
   - When `--external`: recognise top-level `status`; `SKIPPED` → emit `{"verdict":"SKIPPED","reason":…,"counts":{0,0,0},"issues":[]}` exit 0.
   - Map codex issue schema: `description`→`message`, `recommendation`→`fix`, `severity:"info"`→`minor`, `line:null`→0.
   - Recompute `counts` from normalized issues; if `verdict=="APPROVED"` but issues non-empty → set `CHANGES_REQUESTED` (stricter, never looser).
   - Emit the parser error text to stderr on genuine unparseable input so the orchestrator can retry (Stage 7).
   - **Strict mode (no flag) unchanged** — all 12 existing tests stay green.

### DoD
- [x] `--external` turns "APPROVED + issues" into `CHANGES_REQUESTED` with counts recomputed from issues.
- [x] `--external` maps the codex-reviewer issue schema (`description`/`recommendation`/`info`/`line:null`).
- [x] `--external` passes a `{"status":"SKIPPED"}` payload through as `verdict:"SKIPPED"` exit 0.
- [x] Strict default mode is byte-stable — 12 existing tests green.
- [x] Тесты: 5 new + 12 existing pytest green; `shellcheck` clean; file ≤400 lines.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_review_parse.py -q
shellcheck scripts/mb-work-review-parse.sh
```
### Edge cases
- `--external` with a `CHANGES_REQUESTED` + non-empty issues → unchanged (already valid).
- `SKIPPED` with no `reason` → default reason `"cross-model review unavailable"`.
- Downstream `mb-work-severity-gate.sh` must treat `verdict:"SKIPPED"` — Stage 9 handles the orchestrator's degradation; the parser only normalizes.

---

<!-- mb-stage:7 -->
## Stage 7 (T3): wire external-reviewer default `--external` + one auto-retry into `commands/work.md` 5d
**Complexity:** S · **~4 мин** · **Зависимости:** Stage 6 · **Агент:** developer (+ tester)
**Файлы:** `commands/work.md` (edit — 5d `:349-358`, Underlying scripts `:475-479`),
`tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** 5d (`commands/work.md:349-358`) parses reviewer output with `mb-work-review-parse.sh` and no retry;
the doc does not switch to `--external` when the reviewer is a cross-model (codex/GPT) agent.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc's 5d uses `mb-work-review-parse.sh --external` when the resolved reviewer is external (codex / `codex-reviewer`).
   - doc's 5d performs **exactly one** automatic retry, re-dispatching the reviewer with the parser's stderr text, before failing the step.
2. **Edit** `commands/work.md` 5d: when `mb-reviewer-resolve.sh` yields an external/cross-model reviewer, parse with
   `--external`; if parse exits non-zero, re-dispatch the reviewer once with the parser stderr appended to its prompt,
   then re-parse; a second failure surfaces the raw output and halts the review step. Add the `--external` form to the
   Underlying-scripts block.

### DoD
- [x] Doc's 5d selects `--external` for cross-model reviewers and stays strict for the in-model `mb-reviewer`.
- [x] Doc specifies a single bounded auto-retry carrying the parser error text.
- [x] Тесты: 2 new bats `@test` green; existing doc tests green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- Ensemble (`review_profile: ensemble`) lead reviewer stays in-model → strict parse (no `--external`); only external aspect/lead reviewers use `--external`.
- Retry must not loop unbounded — exactly one, then halt.

---

<!-- mb-stage:8 -->
## Stage 8 (T4): `scripts/mb-work-codex-preflight.sh` — codex availability/auth health-check (fail-safe)
**Complexity:** S · **~4 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-codex-preflight.sh` (создать, `+x`), `tests/pytest/test_mb_work_codex_preflight.py` (создать, тесты FIRST)

**Confirmed gap:** no preflight exists; a codex 403 silently disabled the cross-model gate in a real session (the judge
closed alone, trace only in `progress.md`). The global `codex-reviewer` subagent does its own preflight and returns
`{"status":"SKIPPED"}`, but nothing pre-checks before dispatching a whole review wave.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_codex_preflight.py` (stub `codex` on `PATH` via a temp bin dir):
   - `test_preflight_available_when_codex_ok` — stub `codex` returning success on the auth probe → `--json` prints `{"available":true}`, exit 0.
   - `test_preflight_unavailable_when_codex_missing` — empty `PATH` → `{"available":false,"reason":"codex CLI not found"}`, exit 0.
   - `test_preflight_unavailable_on_auth_403` — stub `codex` whose auth probe prints `403`/error → `{"available":false,"reason":...403...}`, exit 0.
   - `test_preflight_is_fail_safe` — stub `codex` that hangs/errors unexpectedly → exit 0, `available:false` (never non-zero, never wedge).
2. **Implement** `scripts/mb-work-codex-preflight.sh [--json] [--mb <path>]`:
   - `command -v codex` → if absent, `available:false reason:"codex CLI not found"`.
   - Cheap auth probe (`codex login status 2>&1`, short `timeout`), classify 403/unauth/error → `available:false` with the first error line as `reason`.
   - `--json` emits `{"available":bool,"reason":str}`; default emits a one-line human message. **Always exit 0** (advisory + fail-safe).

### DoD
- [x] Preflight reports `available:true` only when `codex` is present AND the auth probe succeeds.
- [x] Missing CLI / 403 / probe error → `available:false` with a concrete `reason`.
- [x] Always exit 0 (fail-safe; never blocks a session); `--json` schema stable.
- [x] Тесты: 4 pytest green; `shellcheck` clean; ≤400 lines; `+x`; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_codex_preflight.py -q
shellcheck scripts/mb-work-codex-preflight.sh
test -x scripts/mb-work-codex-preflight.sh
```
### Edge cases
- `codex` present but a newer/older version lacking `login status` → probe error → `available:false` with the version's error line (do not guess).
- Slow probe bounded by `timeout` so preflight can't hang the loop.

---

<!-- mb-stage:9 -->
## Stage 9 (T4): wire preflight + codex-reviewer SKIPPED consumption + loud degradation into `commands/work.md` 5d
**Complexity:** M · **~5 мин** · **Зависимости:** Stage 8, Stage 6 · **Агент:** developer (+ tester)
**Файлы:** `commands/work.md` (edit — 5d review preamble `:349-358`, Hard-stops table `:390-402`, Underlying scripts),
`tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** 5d has no pre-wave codex health-check and no defined behaviour when the cross-model reviewer is
unavailable; the Hard-stops table (`:390-402`) has no "cross-model gate degraded" entry.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc's 5d runs `mb-work-codex-preflight.sh` before a cross-model review wave.
   - doc says an unavailable codex → record `cross-model review SKIPPED (<reason>)` in the stage report AND append a NOTE to `progress.md` (loud, never silent).
   - doc says the loop consumes a `codex-reviewer` `{"status":"SKIPPED"}` / parser `verdict:"SKIPPED"` as a degraded gate.
   - doc's Hard-stops table: `cross-model review SKIPPED under --auto` → require explicit user confirmation (halt).
2. **Edit** `commands/work.md`:
   - 5d preamble: before dispatching an external review wave, run `bash scripts/mb-work-codex-preflight.sh --json --mb <bank>`.
     `available:false` (or a returned `verdict:"SKIPPED"` from Stage 6) → write `cross-model review SKIPPED (<reason>)` to the
     stage report + append a NOTE to `progress.md`; **do not** let the judge close a governed item alone silently.
   - Under `--auto`: a skipped cross-model gate requires explicit user confirmation before proceeding (new Hard-stops row).
   - Add `mb-work-codex-preflight.sh` to Underlying scripts.

### DoD
- [x] Doc runs codex preflight before a cross-model review wave and consumes the SKIPPED contract.
- [x] Doc mandates a loud `cross-model review SKIPPED (<reason>)` record in the stage report + `progress.md` NOTE.
- [x] Hard-stops table gains a `--auto` confirmation row for a skipped cross-model gate.
- [x] Тесты: 4 new bats `@test` green; full `test_mb_work_command_doc.bats` green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- In-model-only review (no external reviewer) → preflight skipped entirely (no false SKIPPED note).
- Preflight false-negative is recoverable: the note is informational; `--auto` asks rather than aborting the whole run.

---

## Zones of non-contact with I-087 (`2026-07-04_fix_session-capture-and-mb-hygiene.md`)

I-087 owns the **session-capture + MB-drift** surface; this plan owns the **`/mb work` engine** surface. Verified
**zero file overlap**:

| I-087 touches (do NOT touch here) | This plan touches (not in I-087) |
|---|---|
| `hooks/mb-session-turn.sh`, `hooks/mb-session-start.sh` | `scripts/mb-work-state.sh` (new) |
| `hooks/lib/session-common.sh`, `hooks/lib/extract-tools-files.sh` | `scripts/mb-work-checkbox.sh` (new) |
| `scripts/mb-session-prune.sh`, `scripts/mb-session-repair.sh` (new), `session-end-autosave.sh` | `scripts/mb-work-codex-preflight.sh` (new) |
| `scripts/mb-freshness.sh` (new), `settings/hooks.json`, adapter mirrors | `scripts/mb-work-budget.sh`, `scripts/mb-work-review-parse.sh` (edit) |
| `SKILL.md` (checklist/auto-commit rules), `commands/done.md`, `references/session-memory.md` | `commands/work.md` (edit) |
| `hooks/tests/session-*.bats`, `tests/bats/test_session_repair.bats`, `test_mb_freshness.bats`, `test_compact_checklist.bats` | `tests/pytest/test_mb_work_*.py`, `tests/bats/test_mb_work_command_doc.bats` |

Shared-in-principle but **explicitly avoided** to keep the merge clean: `SKILL.md` (I-087 B2/B3 edit it) — this plan keeps
all its doc changes in `commands/work.md`, not `SKILL.md`. `settings/hooks.json` (I-087 B1/B3) — the work loop is
orchestrated, not hook-driven, so this plan never touches it. Both plans can run in parallel.

---

## Граф зависимостей

```
T1  Stage1 ──► Stage2 ──┐
       │              ├──► Stage3 (work.md wiring)
       └──────────────┘
       └──────────────────► Stage5 (needs Stage4 + Stage1)
T2  Stage4 ─────────────────► Stage5
T3  Stage6 ─────────────────► Stage7
                            └► Stage9 (needs Stage8 + Stage6)
T4  Stage8 ─────────────────► Stage9

work.md single-owner chain: Stage3 → Stage5 → Stage7 → Stage9 (sequential edits to one file)
```

## Параллелизация
| Phase | Stages | Агенты |
|------|-------|--------|
| 1 | 1, 4, 6, 8 (independent new/edited scripts, distinct files) | dev-1, dev-2, dev-3, tester |
| 2 | 2 (after 1) | dev-1 |
| 3 | 3 → 5 → 7 → 9 (sequential, single owner of `commands/work.md`) | dev-1 (work.md owner) + tester |

## Потенциальные конфликты при merge
- **`commands/work.md`** — edited by Stages 3, 5, 7, 9 → **one owner**, land in order 3→5→7→9; each is an additive, distinct-section edit.
- **`tests/bats/test_mb_work_command_doc.bats`** — extended by Stages 3, 5, 7, 9 → same owner appends `@test` blocks sequentially.
- **`scripts/mb-work-review-parse.sh`** — only Stage 6 edits it; Stage 7/9 consume it via doc only (no code conflict).
- **`scripts/mb-work-budget.sh`** — only Stage 2 edits it.
- No conflict with I-087 (disjoint file sets, see table above).

## DoD (plan-level)
- [x] T1: `.work-state.json` durable cycle counter enforces `max_cycles` by exit 3; budget bound to `run_id`; both wired in work.md + resume.
- [x] T2: `mb-work-checkbox.sh` flips DoD only after `phase=done`; implementers forbidden to touch checkboxes; resume trusts state not checkboxes.
- [x] T3: `--external` parser normalizes "APPROVED+issues"→CHANGES_REQUESTED, maps codex schema, passes SKIPPED through; 5d uses it + one auto-retry.
- [x] T4: `mb-work-codex-preflight.sh` fail-safe health-check; loud `cross-model review SKIPPED` degradation + `--auto` confirmation; consumes `codex-reviewer` SKIPPED.
- [x] Every stage has a failing test committed BEFORE its implementation (TDD evidence in git history).
- [x] All new/edited shell: `shellcheck` clean, ≤400 lines, `+x` on new scripts, bash 3.2 + 5.x.
- [x] Fail-safe: a malformed/absent `.work-state.json` degrades to a no-op, never wedges a session; the only non-zero enforcement exit is cycle-exhausted (3).
- [x] Default behaviour unchanged where not opted in: strict review parse, no-`--run-id` budget path, and non-governed workflows stay byte-stable.
- [x] Backlog **I-093** registered; `progress.md` appended; `checklist.md` updated.

## Full verification
```bash
cd /Users/fockus/.claude/skills/memory-bank

# T1–T4 unit/contract
PATH="$PWD/.venv/bin:$PATH" pytest \
  tests/pytest/test_mb_work_state.py \
  tests/pytest/test_mb_work_budget.py \
  tests/pytest/test_mb_work_checkbox.py \
  tests/pytest/test_mb_work_review_parse.py \
  tests/pytest/test_mb_work_codex_preflight.py -q

# Doc-contract
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats

# Static analysis on every changed/new shell file
shellcheck \
  scripts/mb-work-state.sh scripts/mb-work-budget.sh scripts/mb-work-checkbox.sh \
  scripts/mb-work-review-parse.sh scripts/mb-work-codex-preflight.sh

# Executable bits + dual-shell smoke
test -x scripts/mb-work-state.sh && test -x scripts/mb-work-checkbox.sh && test -x scripts/mb-work-codex-preflight.sh
bash --version; /bin/bash -c 'echo bash3.2-path-ok'

# Full structured run (no regressions)
PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json
```

## Stage summary
| Stage | Theme | Type | Complexity | Depends | DoD |
|-------|-------|------|-----------|---------|-----|
| 1 | T1 durable loop-state | new script + pytest | M | — | ✅ |
| 2 | T1 budget run_id | edit + pytest | S | 1 | ✅ |
| 3 | T1 wire work.md | doc + bats | M | 1,2 | ✅ |
| 4 | T2 checkbox flip | new script + pytest | M | 1 | ✅ |
| 5 | T2 wire work.md | doc + bats | S | 4,1 | ✅ |
| 6 | T3 external parser | edit + pytest | M | — | ✅ |
| 7 | T3 wire work.md | doc + bats | S | 6 | ✅ |
| 8 | T4 codex preflight | new script + pytest | S | — | ✅ |
| 9 | T4 wire work.md | doc + bats | M | 8,6 | ✅ |

## Checklist (copy into checklist.md)
- ✅ I-093 S1 (T1): `mb-work-state.sh` durable loop-state + max_cycles exit-3 enforcement
- ✅ I-093 S2 (T1): bind `mb-work-budget.sh` to run_id (ignore orphaned budget)
- ✅ I-093 S3 (T1): wire durable state + budget run_id into `commands/work.md` + resume + hard-stops
- ✅ I-093 S4 (T2): `mb-work-checkbox.sh` deterministic flip gated on `.work-state.json phase=done`
- ✅ I-093 S5 (T2): forbid implementers editing checkboxes + state-based resume in `commands/work.md`
- ✅ I-093 S6 (T3): `mb-work-review-parse.sh --external` normalization + codex SKIPPED passthrough
- ✅ I-093 S7 (T3): wire external-reviewer `--external` + one auto-retry into `commands/work.md` 5d
- ✅ I-093 S8 (T4): `mb-work-codex-preflight.sh` fail-safe codex health-check
- ✅ I-093 S9 (T4): wire preflight + SKIPPED consumption + loud degradation into `commands/work.md` 5d
