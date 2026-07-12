---
type: fix
scope: mb-work-parallel-runs
created: 2026-07-04
status: done
priority: HIGH
complexity: L
backlog: I-094
---

# Fix: safe PARALLEL `/mb work` runs (per-run state+budget · claim-on-resolve · baseline-scoped diffs · concurrent core-file writes · Parallel-runs doc)

Makes it safe to drive **several `/mb work` runs concurrently from one Claude Code session** — either
multiple independent stages of one plan (intra-plan waves), or one plan per git worktree (inter-plan).
Today the loop is single-slot (`.work-state.json` / `.work-budget.json`), diffs are the bare working
tree, and there is no claim, so two runs corrupt each other's cycle counter/budget and the judge grades
foreign code.

Tracked as backlog **I-094** (bank max = I-093). Five themes (T1–T5), 10 bite-sized stages. All findings
below were **re-verified against the current code on 2026-07-04** (post-I-093 merge, 18 commits
`c46d9ac..82624b2` + `a040e17`).

## Goal

Move the four single-slot / contamination points of a `/mb work` run into per-run-isolated, claim-guarded,
baseline-scoped scripts, all **behind an `MB_WORK_PARALLEL` opt-in so the single-run default path stays
byte-identical**: (T1) per-run `.work-state/<run_id>.json` + `.work-budget/<run_id>.json` slots with a
source→run index and a claim exit-code; (T2) resolve skips foreign-claimed sources on empty-target and
warns on an explicit claimed target; (T3) `init` records a `baseline_ref` and verify/review diff against
`<baseline>..HEAD -- <files>` instead of the working tree, plus the "inter-plan ⇒ separate worktrees"
rule; (T4) a locked atomic-append helper for `progress.md` + the single-writer contract for core files;
(T5) a `commands/work.md` **Parallel runs** section (two patterns, sync/async spawn rule, report
delivery, optional self-claim pull).

## Scope

### Входит
- `scripts/mb-work-slots.sh` (NEW, sourced helper) — per-run slot-path resolution + source→run index, `MB_WORK_PARALLEL`-gated.
- `scripts/mb-work-state.sh` (EDIT) — consume slots helper; `--run-id` on every subcommand; `new-run-id`; `status --all`/`list`; claim **exit 4** + `--takeover`; record `baseline_ref` at init.
- `scripts/mb-work-budget.sh` (EDIT) — per-run `.work-budget/<run_id>.json` under `MB_WORK_PARALLEL`; default singleton unchanged.
- `scripts/mb-work-checkbox.sh` (EDIT) — read the per-run state slot via `--run-id`/`MB_WORK_PARALLEL`; default singleton unchanged.
- `scripts/mb-work-resolve.sh` (EDIT) — `--skip-claimed` for empty-target; stderr claim-note for an explicit foreign-claimed target.
- `scripts/mb-work-diff.sh` (NEW) — baseline-scoped diff helper: `git diff <baseline_ref>..HEAD -- <files>` for a run.
- `scripts/mb-work-progress-append.sh` (NEW) — locked, atomic, append-only writer for `progress.md`.
- `commands/work.md` (EDIT) — wire T1–T4 into steps 3/4/5c/5d/5g + resume + Hard-stops; add the **Parallel runs** section (T5).
- Tests: `tests/pytest/test_mb_work_slots.py`, `test_mb_work_diff.py`, `test_mb_work_progress_append.py` (NEW);
  extend `test_mb_work_state.py`, `test_mb_work_budget.py`, `test_mb_work_checkbox.py`, `test_mb_work_resolve.py`;
  extend `tests/bats/test_mb_work_command_doc.bats`.

### НЕ входит
- `hooks/mb-session-*`, `scripts/mb-session-*`, `session-end-autosave.sh`, `hooks/lib/session-common.sh`,
  `SKILL.md` — **explicitly not touched** (constraint). All doc changes stay in `commands/work.md`.
- The Task-dispatcher / worktree-fanout runtime (`mb-fanout.sh`, `mb-subinvoke-resolve.sh`, transports) —
  I-084 territory. This plan makes the **per-run bookkeeping** safe; it does not build a worktree manager.
  Inter-plan worktree parallelism is a documented **operating rule** here, not new orchestration code.
- Changing single-run default behaviour in any way without the `MB_WORK_PARALLEL` switch.
- Auto-merge / cherry-pick conflict resolution across worktrees (I-040), item-level sub-worktrees (I-036).
- Re-implementing the I-093 pieces (run_id-mismatch guard, cycle exit-3, checkbox gate) — this plan
  **layers physical per-run isolation under** them; the I-093 logic stays as a second safety net.

## Assumptions
- The `/mb work` loop is orchestrated by the code-agent following `commands/work.md`; the scripts are the
  deterministic backbone the orchestrator MUST call. Doc-contract bats lock the wiring in (mirroring the
  existing `test_mb_work_command_doc.bats` pattern), same as I-093.
- **Parallel isolation is opt-in via `MB_WORK_PARALLEL=1`.** Unset (the default) → the legacy singletons
  `<bank>/.work-state.json` / `<bank>/.work-budget.json` and today's behaviour, byte-identical. This is the
  required `MB_*` switch and the reason all 49 existing I-093 pytest + 22 bats stay green **with zero
  adaptation** (none of them set the env var; none route to a per-run dir).
- Inter-plan parallelism runs **one plan per git worktree**: worktrees have independent working dirs and
  independent git index files, so `.memory-bank/*.json`, `progress.md`, and `.git/index` are naturally
  per-worktree — no cross-run contention there. Per-run slots + baseline diffs are what make **intra-plan**
  (same worktree, several stages) safe.
- `run_id` is minted once per run (`mb-work-state.sh new-run-id`, or supplied `--run-id`) and threaded to
  state, budget, checkbox, and diff for that run's whole lifetime.
- All new/edited shell: `set -eu`, PyYAML-optional, atomic writes (`mktemp`→`mv`), bash 3.2 **and** 5.x
  (no `mapfile`, `declare -A`, `${var^^}`), shellcheck-clean, ≤400 lines. To keep `mb-work-state.sh` under
  400 after additions, the slot/index logic is **extracted into the sourced `mb-work-slots.sh`** (DRY;
  reused by budget/checkbox/resolve/diff).
- Fail-safe: a malformed/absent state or index file must never wedge a session — degrade to a no-op /
  singleton, not a crash. The intentional non-zero exits are cycle-exhausted (3, existing) and the new
  **claim-refused (4)**; both are enforcement, not failure.
- Next free backlog id verified = **I-094** (bank max across BACKLOG.md + progress.md + checklist.md = I-093).

## Verified findings (current code, 2026-07-04)
- **Single-slot state:** `mb-work-state.sh:66-71` `state_path()` → one `<bank>/.work-state.json`; `cmd_init`
  (`:97-160`, mv at `:158`) unconditionally overwrites — a second run zeroes the first run's `cycle`.
  `mb-work-checkbox.sh:71` reads the same singleton `"$bank/.work-state.json"`, so after run 2 inits, run 1's
  flip (`:95` gate `item_no` match) starts refusing (exit 1) because the state now describes run 2's item.
- **Single-slot budget:** `mb-work-budget.sh` builds `"$bank/.work-budget.json"` inline at `:102/140/173/250`;
  `cmd_check --run-id` on a foreign run → `require_matching_run_id` false → `:216-217` **exit 1 (warn, not stop)**,
  so run 2 runs with **no budget gate at all** (mb-fanout.sh:255 also reads this exact singleton — must stay).
- **Diff contamination:** `commands/work.md:356` feeds the verifier `Diff:\n<git diff output>` (bare working
  tree); `:363-377` (review) reuses the same diff. Two runs in one worktree see each other's edits → judge
  grades foreign code.
- **No claim:** `mb-work-resolve.sh:99-122` empty-target → first `mb-active-plans` link from `roadmap.md`;
  two runs resolve the **same** plan. Nothing consults an "is this plan already running" record.

## Риски
| Риск | Вероятность | Impact | Mitigation |
|------|-------------|--------|------------|
| Per-run slots break the 49 existing I-093 tests | Med | Regression | Gate ALL isolation behind `MB_WORK_PARALLEL`; default = singleton, byte-identical; new tests set the env var |
| Claim exit code clashes with usage/cycle exits | Med | Loop misreads a claim as usage error | Reserve a **distinct exit 4** (2=usage, 3=cycle-exhausted stay); document in work.md hard-stops |
| `mb-work-state.sh` exceeds the 400-line cap | Med | Cap violation | Extract slot/index into sourced `mb-work-slots.sh`; state.sh delta stays ≈50 lines |
| Corrupt source→run index wedges resolution | Low | Run can't start | Index reads are fail-safe: unreadable/missing → treat as "unclaimed", fall through to singleton/legacy |
| `baseline_ref` recorded outside a git repo | Med | diff helper errors | `init` records `""` when `git rev-parse HEAD` fails; diff helper with empty baseline → falls back to a scoped working-tree diff, never crashes |
| Baseline diff misses a run's real changes (wrong file list) | Med | Judge sees too little | Union of stage `Files:` ∩ changed-since-baseline; if `Files:` absent → full `<baseline>..HEAD` (still baseline-scoped, better than working-tree bare diff) |
| `progress.md` append lock deadlocks a run | Low | Halt | `mkdir` lock with TTL + owner-token stale-break, bounded `timeout`; on lock-timeout the helper degrades to a warning, never blocks the loop |
| Merge churn on `commands/work.md` (4 wiring stages) | High | Rebase pain | Single owner; land S7→S8→S9→S10 sequentially; each an additive distinct-section edit (I-093 precedent) |

---

<!-- mb-stage:1 -->
## Этап 1 (T1): `mb-work-slots.sh` (new) + per-run state/index/claim/baseline in `mb-work-state.sh`
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester для red)
**Файлы:** `scripts/mb-work-slots.sh` (создать, sourced helper), `scripts/mb-work-state.sh` (edit),
`tests/pytest/test_mb_work_slots.py` (создать, тесты FIRST), `tests/pytest/test_mb_work_state.py` (extend, тесты FIRST)

**Confirmed gap:** `mb-work-state.sh:66-71` returns one singleton; `cmd_init:97-160` overwrites it, so a
second concurrent run destroys the first's cycle counter. No per-run store, no claim, no baseline exists
(`grep -rl 'work-state/\|by-source\|baseline_ref\|MB_WORK_PARALLEL' scripts` → empty).

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_slots.py` (source the helper via a tiny bash harness, or call a
   thin `--print-slot` probe added to state.sh):
   - `test_state_slot_singleton_when_parallel_off_no_runid` — no `MB_WORK_PARALLEL`, no run_id → `<bank>/.work-state.json`.
   - `test_state_slot_perrun_when_parallel_on` — `MB_WORK_PARALLEL=1`, run_id `r1` → `<bank>/.work-state/r1.json`.
   - `test_index_set_get_del_roundtrip` — set source→run, get returns run_id, del clears it.
   - `test_index_get_missing_is_failsafe_empty` — get on absent/corrupt index → empty string, exit 0.
2. **Test FIRST** extend `tests/pytest/test_mb_work_state.py` (keep all 9 existing green — none set the env var):
   - `test_parallel_init_writes_perrun_slot` — `MB_WORK_PARALLEL=1 init plans/a.md 1 --run-id r1` → `<bank>/.work-state/r1.json` exists; singleton `.work-state.json` absent.
   - `test_two_parallel_runs_have_independent_cycles` — init r1 (`--max-cycles 2`) + init r2; `cycle --run-id r1` twice, `cycle --run-id r2` once → r1.cycle==2, r2.cycle==1 (no cross-talk).
   - `test_init_records_baseline_ref_in_git_repo` — in a git repo, `init` state has `baseline_ref == rev-parse HEAD`.
   - `test_init_baseline_ref_empty_outside_repo` — non-repo `tmp_path` → `baseline_ref == ""`, exit 0 (fail-safe).
   - `test_init_claim_refused_exit_4` — `MB_WORK_PARALLEL=1`: init r1 for `plans/a.md`; init r2 for the **same** source (r1 still `in-progress`) → **exit 4**, stderr `already claimed by run r1`, r2 slot NOT written.
   - `test_init_takeover_overrides_claim` — same as above but r2 passes `--takeover` → exit 0, index now points at r2.
   - `test_init_claim_free_after_done` — r1 `done`; init r2 same source → exit 0 (finished run does not hold the claim).
   - `test_status_all_lists_every_run` — two live runs → `status --all` prints a JSON array with both run_ids/sources (fail-safe: skips corrupt slots).
   - `test_new_run_id_prints_unique` — `new-run-id` prints a non-empty uuid, no file written.
3. **Implement** `scripts/mb-work-slots.sh` (sourced, no shebang-main): `mbw_parallel_on`,
   `mbw_state_slot <bank> <run_id>`, `mbw_budget_slot <bank> <run_id>`, `mbw_source_hash <source>`
   (stable, python `hashlib`), `mbw_index_set/get/del <bank> <source> [run_id]` (index at
   `<bank>/.work-state/by-source/<hash>`; symlink or one-line file → run_id). All reads fail-safe.
4. **Implement** `scripts/mb-work-state.sh` deltas (source `mb-work-slots.sh`; keep ≤400 by moving path logic out):
   - `state_path()` → `mbw_state_slot "$bank" "$run_id"`; add `--run-id` (falls back to `$MB_WORK_RUN_ID`) to **every** subcommand.
   - `new-run-id` subcommand (print uuid, no write).
   - `init`: when `mbw_parallel_on`, write `.work-state/<run_id>.json` + `mbw_index_set`; record `baseline_ref` (`git rev-parse HEAD` or `""`); if source already indexed to a live (`phase != done`) foreign run → **exit 4** unless `--takeover`. Default (parallel off): singleton overwrite exactly as today (no exit 4).
   - `status --all` / `list`: enumerate `.work-state/*.json` (+ singleton) → JSON array, fail-safe.

### DoD
- [ ] `MB_WORK_PARALLEL=1` routes state to `<bank>/.work-state/<run_id>.json`; unset → singleton `.work-state.json` (byte-identical to today).
- [ ] Two parallel runs keep independent `cycle` counters (no cross-talk); claim on an already-live source → **exit 4** (`--takeover` overrides; a `done` run frees the claim).
- [ ] `init` records `baseline_ref` (HEAD in a repo, `""` outside — fail-safe); `status --all` lists every live run.
- [ ] All 9 existing `test_mb_work_state.py` tests stay green **unchanged**.
- [ ] Тесты: 4 (slots) + 9 (state new) pytest green; `shellcheck` clean; both files ≤400 lines; `+x` on state.sh; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_slots.py tests/pytest/test_mb_work_state.py -q
shellcheck scripts/mb-work-slots.sh scripts/mb-work-state.sh
awk 'END{print NR}' scripts/mb-work-state.sh   # must be <=400
/bin/bash -c 'bash scripts/mb-work-state.sh -h >/dev/null && echo bash3.2-ok'
```
### Edge cases
- Parallel off + explicit `--run-id` → still singleton (isolation is env-gated, not run-id-gated) — this is exactly what keeps I-093's `--run-id` budget/state tests green.
- Re-init of the **same** run_id for the next item → allowed (re-arm), never exit 4.
- Corrupt index entry → treated as unclaimed (fail-safe), init proceeds.
- `by-source/` dir missing → created on demand; `clear`/`done`-of-run removes the index entry.

---

<!-- mb-stage:2 -->
## Этап 2 (T1): `mb-work-budget.sh` — per-run slot under `MB_WORK_PARALLEL`
**Complexity:** S · **~4 мин** · **Зависимости:** Этап 1 (slots helper) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-budget.sh` (edit), `tests/pytest/test_mb_work_budget.py` (extend, тесты FIRST)

**Confirmed gap:** every `cmd_*` builds `"$bank/.work-budget.json"` inline (`:102/140/173/250`); a foreign
run_id makes `cmd_check` warn-not-stop (`:216-217`), so a second run has no real budget gate. mb-fanout.sh:255
reads the same singleton, so the default path must not move.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_budget.py` (keep all 13 existing green — none set the env var):
   - `test_parallel_budget_writes_perrun_slot` — `MB_WORK_PARALLEL=1 init 100000 --run-id r1` → `<bank>/.work-budget/r1.json`; singleton absent.
   - `test_two_parallel_budgets_are_independent` — `MB_WORK_PARALLEL=1`: init r1 100000 + init r2 100000; `add 90000 --run-id r1`; `check --run-id r2` → exit 0 (r2 untouched at 0%), `check --run-id r1` → warn/stop per r1 only.
   - `test_parallel_check_own_run_stops_correctly` — r1 spent past `stop_at` → `check --run-id r1` exit 2 (a real gate, unlike today's warn-not-stop across runs).
   - `test_default_singleton_path_unchanged` — no env var → still `<bank>/.work-budget.json` (mb-fanout compat).
2. **Implement**: route every state-path build through `mbw_budget_slot "$bank" "$run_id"` (source slots helper).
   Under `MB_WORK_PARALLEL` → `.work-budget/<run_id>.json`; unset → singleton. Keep the existing run_id-mismatch
   guard as the in-file second layer (now rarely hit because slots are physically separate). Preserve all
   0/1/2 exit semantics and the additive `run_id=` status field.

### DoD
- [ ] `MB_WORK_PARALLEL=1` gives each run its own `.work-budget/<run_id>.json`; two runs' budgets never interfere.
- [ ] A parallel run's own `check` STOPs at `stop_at` (exit 2) — a real gate, not the old cross-run warn-not-stop.
- [ ] Default (env unset) path is byte-identical: `<bank>/.work-budget.json` (mb-fanout.sh:255 still resolves).
- [ ] All 13 existing `test_mb_work_budget.py` tests stay green **unchanged**.
- [ ] Тесты: 4 new + 13 existing pytest green; `shellcheck` clean; file ≤400 lines.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_budget.py -q
shellcheck scripts/mb-work-budget.sh
```
### Edge cases
- Parallel off + `--run-id` → singleton + existing mismatch guard (keeps I-093 S2 tests green).
- `status`/`clear` under parallel target the per-run slot; `clear` removes only that run's budget.

---

<!-- mb-stage:3 -->
## Этап 3 (T1): `mb-work-checkbox.sh` — flip gated on the per-run state slot
**Complexity:** S · **~4 мин** · **Зависимости:** Этап 1 · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-checkbox.sh` (edit), `tests/pytest/test_mb_work_checkbox.py` (extend, тесты FIRST)

**Confirmed gap:** `mb-work-checkbox.sh:71` reads the singleton `"$bank/.work-state.json"`; under two runs
this describes whichever inited last, so the first run's legitimate flip is refused (`:95` item_no gate).

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_checkbox.py` (keep all 7 existing green — none set the env var):
   - `test_parallel_flip_reads_own_run_slot` — `MB_WORK_PARALLEL=1`: r1 done for item 2, r2 in-progress for item 3; `flip <plan> 2 --run-id r1` → flips (reads r1 slot), not refused.
   - `test_parallel_flip_refused_on_foreign_run_state` — `flip <plan> 2 --run-id r2` (r2 is on item 3, in-progress) → exit 1 refuse (no cross-run flip).
   - `test_default_singleton_flip_unchanged` — env unset → reads `.work-state.json` exactly as today.
2. **Implement**: accept `--run-id` (fallback `$MB_WORK_RUN_ID`); resolve the state file via
   `mbw_state_slot "$bank" "$run_id"` (source slots helper) instead of the hard-coded singleton. Gate logic
   (`phase==done` AND `item_no` match) unchanged. Default path byte-identical.

### DoD
- [ ] Under `MB_WORK_PARALLEL`, `flip --run-id R` reads `<bank>/.work-state/<R>.json`; a run only flips its own item.
- [ ] Default (env unset) flip reads the singleton exactly as today (7 existing tests green unchanged).
- [ ] Тесты: 3 new + 7 existing pytest green; `shellcheck` clean; ≤400 lines; `+x`; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_checkbox.py -q
shellcheck scripts/mb-work-checkbox.sh
test -x scripts/mb-work-checkbox.sh
```
### Edge cases
- No `.work-state/<R>.json` for the given run → fail-safe refuse (exit 1), never a blind flip (mirrors existing missing-state refusal).
- Spec-task source (`tasks.md` `mb-task:N`) flips the same way — marker-block scoping unchanged.

---

<!-- mb-stage:4 -->
## Этап 4 (T3): `scripts/mb-work-diff.sh` — baseline-scoped diff for a run
**Complexity:** M · **~5 мин** · **Зависимости:** Этап 1 (reads `baseline_ref`) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-diff.sh` (создать, `+x`), `tests/pytest/test_mb_work_diff.py` (создать, тесты FIRST)

**Confirmed gap:** `commands/work.md:356` gives the verifier the bare working-tree `git diff`; nothing scopes
it to a run's baseline or the item's files, so a co-running run's edits leak into the judged diff.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_diff.py` (build a throwaway git repo in `tmp_path`):
   - `test_diff_scopes_to_baseline_and_files` — commit baseline; init run (records baseline_ref); modify `a.txt` + `b.txt`; `mb-work-diff.sh --run-id r1 --files "a.txt"` → diff shows only `a.txt`, not `b.txt`.
   - `test_diff_excludes_foreign_run_changes` — files changed by "another run" (`c.txt`) are absent when `--files "a.txt"` given.
   - `test_diff_name_only_mode` — `--name-only --files "a.txt b.txt"` → lists exactly those changed paths.
   - `test_diff_empty_baseline_falls_back_scoped` — run with `baseline_ref==""` (non-repo init) → `--files "a.txt"` diffs the working tree scoped to `a.txt`, exit 0 (never crash).
   - `test_diff_no_files_uses_full_baseline_range` — no `--files` → `git diff <baseline>..HEAD` (baseline-scoped, all paths), exit 0.
2. **Implement** `scripts/mb-work-diff.sh --run-id R [--files "p1 p2"] [--baseline REF] [--name-only] [--mb <path>]`:
   - Resolve the run's state slot (via slots helper), read `baseline_ref` (or `--baseline` override).
   - Non-empty baseline → `git diff [--name-only] <baseline> -- <files>` (files optional; **single-arg form**:
     baseline↔working-tree, так ревью на 5c/5d видит и закоммиченную, и ещё не закоммиченную работу этапа —
     коммит в цикле происходит только на 5g. *Amendment 2026-07-05: заменена двухточечная `<baseline>..HEAD`,
     которая не видела uncommitted-правки и давала пустой диф на review.*)
   - Empty baseline → `git diff [--name-only] -- <files>` (working-tree, scoped). Always exit 0 on a valid repo;
     absent git / not a repo → print empty + a one-line stderr note, exit 0 (fail-safe).

### DoD
- [ ] Diff is scoped to changes since `<baseline_ref>` (committed **and** working-tree) and, when `--files` is given, to exactly those paths (foreign-run edits excluded).
- [ ] `--name-only` and `--baseline` overrides work; empty baseline degrades to a scoped working-tree diff, never crashes.
- [ ] Тесты: 5 pytest green; `shellcheck` clean; ≤400 lines; `+x`; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_diff.py -q
shellcheck scripts/mb-work-diff.sh
test -x scripts/mb-work-diff.sh
```
### Edge cases
- `--files` naming a path unchanged since baseline → empty diff for it (correct, not an error).
- Renamed/deleted files under `--files` → standard `git diff -- <path>` semantics; no special-casing.
- Baseline commit no longer reachable (rebased) → git errors captured, empty output + stderr note, exit 0.

---

<!-- mb-stage:5 -->
## Этап 5 (T2): `mb-work-resolve.sh` — skip foreign-claimed sources; warn on explicit claimed target
**Complexity:** S · **~4 мин** · **Зависимости:** Этап 1 (source→run index) · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-resolve.sh` (edit), `tests/pytest/test_mb_work_resolve.py` (extend, тесты FIRST)

**Confirmed gap:** `mb-work-resolve.sh:99-122` empty-target returns the first `mb-active-plans` link with no
awareness of a live run on it; two runs grab the same plan.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_resolve.py` (keep existing green — none set the env var):
   - `test_empty_target_skips_claimed_plan` — `MB_WORK_PARALLEL=1 --skip-claimed`: roadmap lists plan A then B; A indexed to a live run → resolve returns B.
   - `test_empty_target_all_claimed_exits_1` — both A and B claimed by live runs → exit 1, stderr `all active plans claimed`.
   - `test_explicit_claimed_target_warns_but_resolves` — explicit path A claimed by run r1 → exit 0, path printed, stderr `claimed by run r1; pass --takeover`.
   - `test_skip_claimed_off_by_default` — no `--skip-claimed` / no env → resolution byte-identical to today (existing tests unchanged).
2. **Implement**: add `--skip-claimed` (only honored under `MB_WORK_PARALLEL`): in the empty-target branch,
   filter out links whose source is indexed to a live foreign run (via `mbw_index_get`); pick the first
   unclaimed; all claimed → exit 1. For an explicit target that resolves to a claimed source, print the path
   (exit 0) plus a stderr claim-note (the hard gate stays `mb-work-state.sh init` exit 4). Default path unchanged.

### DoD
- [ ] Empty-target with `--skip-claimed` returns the first **unclaimed** active plan; all-claimed → exit 1.
- [ ] Explicit claimed target → exit 0 + path + stderr claim-note (`pass --takeover`); enforcement stays in state.init exit 4.
- [ ] Without `--skip-claimed`/env, resolution is byte-identical to today (existing resolve tests green unchanged).
- [ ] Тесты: 4 new + existing pytest green; `shellcheck` clean; file ≤400 lines.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_resolve.py -q
shellcheck scripts/mb-work-resolve.sh
```
### Edge cases
- Index unreadable → treat every plan as unclaimed (fail-safe), behave as today.
- A source claimed by a run whose slot says `phase==done` → NOT claimed (finished), selectable.

---

<!-- mb-stage:6 -->
## Этап 6 (T4): `scripts/mb-work-progress-append.sh` — locked atomic append-only writer
**Complexity:** M · **~5 мин** · **Зависимости:** — · **Агент:** developer (+ tester)
**Файлы:** `scripts/mb-work-progress-append.sh` (создать, `+x`), `tests/pytest/test_mb_work_progress_append.py` (создать, тесты FIRST)

**Confirmed gap:** the loop appends to `progress.md` by free-form edit (`commands/work.md` 5d/end-of-run);
under intra-plan self-claim there is no single-writer primitive, so two appends can interleave/clobber.

### Задачи
1. **Test FIRST** `tests/pytest/test_mb_work_progress_append.py`:
   - `test_append_adds_entry_to_progress` — append `"### NOTE x"` → `progress.md` ends with it; prior content preserved.
   - `test_append_is_append_only` — a second append never rewrites/removes the first (both present, in order).
   - `test_concurrent_appends_do_not_interleave` — launch N=8 background appends → file has exactly N well-formed entries, none truncated/merged (lock works).
   - `test_append_creates_file_if_missing` — no `progress.md` → created with the entry.
   - `test_lock_timeout_degrades_to_warn_exit_0` — pre-hold the lock past TTL-less timeout → helper warns and exits 0 (never wedges the loop).
2. **Implement** `scripts/mb-work-progress-append.sh --text "..." | --file <src> [--mb <path>]`:
   - Acquire a `mkdir`-based lock `<bank>/.work-progress.lock` with an owner-token + bounded `timeout` and
     TTL stale-break (mirror the `mb-handoff.sh` owner-token pattern, do NOT touch session-common.sh).
   - Append atomically (read → temp `mktemp` with the appended block → `mv` over `progress.md`), release lock.
   - Fail-safe: lock-timeout / write error → stderr warn, exit 0.

### DoD
- [ ] Append is append-only (never rewrites prior entries) and atomic (`mktemp`→`mv`).
- [ ] Concurrent appends are serialized by an owner-token `mkdir` lock — 8 parallel appends yield 8 intact entries.
- [ ] Lock-timeout / error degrades to a warning + exit 0 (never blocks a run).
- [ ] Тесты: 5 pytest green; `shellcheck` clean; ≤400 lines; `+x`; bash 3.2 + 5.x.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" pytest tests/pytest/test_mb_work_progress_append.py -q
shellcheck scripts/mb-work-progress-append.sh
test -x scripts/mb-work-progress-append.sh
```
### Edge cases
- Stale lock from a crashed writer (owner-token PID gone + TTL passed) → broken safely, then acquired.
- Empty `--text` → usage exit 2 (nothing appended).
- Bank on a read-only FS → warn + exit 0, never a traceback.

---

<!-- mb-stage:7 -->
## Этап 7 (T1 wire): parallel state+budget+claim into `commands/work.md`
**Complexity:** M · **~5 мин** · **Зависимости:** Этап 1, 2, 3 · **Агент:** developer (+ tester)
**Файлы:** `commands/work.md` (edit — steps 4, 5f, 5g, resume, Hard-stops, Underlying scripts),
`tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** `commands/work.md:298-304` mints one run_id and threads only budget; nothing documents
`MB_WORK_PARALLEL`, per-run slots, `new-run-id`, claim exit-4, or `status --all`.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`, grep-on-doc):
   - doc mentions `MB_WORK_PARALLEL` and per-run `.work-state/<run_id>.json` / `.work-budget/<run_id>.json`.
   - doc says a parallel run mints its id via `mb-work-state.sh new-run-id` and threads `--run-id` to state, budget, checkbox.
   - doc says `mb-work-state.sh init` returns **exit 4** (claimed) and the loop must stop (or pass `--takeover`).
   - doc's Hard-stops table lists the claim-refused (exit 4) trigger.
   - doc's resume section reads `mb-work-state.sh status --all` to enumerate live parallel runs.
2. **Edit** `commands/work.md`: in step 4 document the parallel opt-in (`export MB_WORK_PARALLEL=1`,
   `RUN_ID=$(bash scripts/mb-work-state.sh new-run-id)`, `init … --run-id "$RUN_ID"`, thread `--run-id`
   to budget/checkbox/cycle/done); handle `init` exit 4 (claimed → stop unless `--takeover`); add a
   Hard-stops row; extend the resume section with `status --all`; list the new/edited scripts in
   Underlying scripts. Keep the single-run instructions intact as the default.

### DoD
- [ ] Doc documents `MB_WORK_PARALLEL`, per-run slots, `new-run-id`, `--run-id` threading, and claim exit-4 handling.
- [ ] Hard-stops table has a claim-refused (exit 4) row; resume section uses `status --all`.
- [ ] Single-run instructions remain the documented default (no behaviour change without the env var).
- [ ] Тесты: 5 new bats `@test` green; existing `test_mb_work_command_doc.bats` green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- Non-parallel run: doc must state the env var is off by default and everything behaves as I-093.
- `--takeover` documented as the explicit override for a stale/abandoned claim.

---

<!-- mb-stage:8 -->
## Этап 8 (T2+T3 wire): baseline diff + claim-aware resolve + worktree rule into `commands/work.md`
**Complexity:** M · **~5 мин** · **Зависимости:** Этап 7, 4, 5 · **Агент:** developer (work.md owner) (+ tester)
**Файлы:** `commands/work.md` (edit — resolve preamble, 5c/5d diff, new worktree rule),
`tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** `commands/work.md:356` uses the bare working-tree diff; nothing documents baseline
scoping, `--skip-claimed`, or the inter-plan-worktree rule.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc's 5c/5d build the verify/review diff with `mb-work-diff.sh --run-id … --files …` (not a bare `git diff`).
   - doc says the file list = the stage's `Files:` ∩ changed-since-baseline (fallback: full `git diff <baseline>` — single-arg form per Amendment 2026-07-05, видит и uncommitted).
   - doc's resolve step passes `--skip-claimed` under `MB_WORK_PARALLEL` for empty-target.
   - doc states the rule: **inter-plan parallel is supported ONLY in separate git worktrees (one per plan)**; **intra-plan parallel = independent stages + a single owner per shared file**.
2. **Edit** `commands/work.md`: replace the 5c/5d `<git diff output>` with the `mb-work-diff.sh` invocation
   and describe the file-list assembly; add `--skip-claimed` to the resolve step under the env var; add a
   short **worktree rule** paragraph (why worktrees give independent working tree + index, so `progress.md`
   and `.git/index` don't contend across plans).

### DoD
- [ ] 5c/5d use `mb-work-diff.sh` (baseline+files scoped); the file-list rule is documented.
- [ ] Resolve uses `--skip-claimed` under `MB_WORK_PARALLEL`; the inter-plan-worktree / intra-plan-single-owner rule is stated.
- [ ] Тесты: 4 new bats `@test` green; existing doc tests green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- In-model single-run diff still works: `mb-work-diff.sh` with the singleton run/baseline behaves like a scoped `git diff`.
- Ensemble review reuses the same baseline diff for every aspect reviewer (consistency).

---

<!-- mb-stage:9 -->
## Этап 9 (T4 wire): concurrent core-file write contract into `commands/work.md`
**Complexity:** S · **~4 мин** · **Зависимости:** Этап 8, 6 · **Агент:** developer (work.md owner) (+ tester)
**Файлы:** `commands/work.md` (edit — 5g / end-of-run / resume), `tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** the doc appends to `progress.md`/`checklist.md` as prose edits; no single-writer contract
for concurrent runs.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc says `progress.md` appends go through `mb-work-progress-append.sh` (locked, append-only) under parallel runs.
   - doc says `checklist.md` is flipped **only** by `mb-work-checkbox.sh` (single-writer; reaffirms I-093).
   - doc states the durable progress source during a run is the **checkboxes + `.work-state`**, while `TaskUpdate` is **ephemeral** (UI only, not the source of truth).
2. **Edit** `commands/work.md`: add a short "Concurrent core-file writes" note — `progress.md` via the
   append helper, `checklist.md` via checkbox only, `TaskUpdate` ephemeral vs durable checkboxes/state;
   add both scripts to Underlying scripts.

### DoD
- [ ] Doc mandates `mb-work-progress-append.sh` for `progress.md` and checkbox-only for `checklist.md` under parallel runs.
- [ ] Doc states durable = checkboxes/`.work-state`; `TaskUpdate` = ephemeral.
- [ ] Тесты: 3 new bats `@test` green; existing doc tests green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- Single-run mode: the append helper is still safe to use (no contention), but prose-edit remains acceptable — doc says "required under parallel, recommended always".
- Worktree mode: `progress.md` is per-worktree, so cross-plan appends can't contend anyway (doc notes this).

---

<!-- mb-stage:10 -->
## Этап 10 (T5): `commands/work.md` — "Parallel runs" section
**Complexity:** M · **~5 мин** · **Зависимости:** Этап 9 · **Агент:** developer (work.md owner) (+ tester)
**Файлы:** `commands/work.md` (edit — new "Parallel runs" section), `tests/bats/test_mb_work_command_doc.bats` (extend, тесты FIRST)

**Confirmed gap:** no section explains the two supported parallel patterns, the sync/async spawn rule, the
background report-delivery contract (`a040e17`), or the optional self-claim pull mode.

### Задачи
1. **Test FIRST** `tests/bats/test_mb_work_command_doc.bats` (new `@test`):
   - doc has a "Parallel runs" section naming both patterns: **intra-plan waves** and **inter-plan worktrees**.
   - doc's spawn rule: **sync** dispatch when the next step depends on the result; **async** (background) only for truly independent waves.
   - doc says async/background agents MUST deliver their final report via `SendMessage` (or `<bank>/.reports/`) per the agent contract — else only an idle notification reaches the lead.
   - doc describes an optional **self-claim pull** mode: publish all tasks BEFORE spawning; agents self-claim via `mb-work-state.sh init … --run-id` (exit 4 = taken); single-writer for conflicting files.
2. **Edit** `commands/work.md`: add the "Parallel runs" section — the two patterns with when-to-use, the
   sync-vs-async spawn rule, the mandatory report-delivery contract (reference the agent `SendMessage` /
   `.reports/` behavior from `a040e17`, do not restate agent files), and the optional self-claim pull mode
   (publish-before-spawn, self-claim via init exit-4, single-owner for shared files). Cross-link the T1–T4
   mechanisms already documented above.

### DoD
- [ ] "Parallel runs" section documents both patterns (intra-plan waves, inter-plan worktrees) with when-to-use.
- [ ] Sync/async spawn rule + mandatory background report delivery (SendMessage/`.reports/`) documented.
- [ ] Optional self-claim pull mode (publish→spawn→self-claim via exit-4, single-writer) documented.
- [ ] Тесты: 4 new bats `@test` green; full `test_mb_work_command_doc.bats` green.

### Команды проверки
```bash
cd /Users/fockus/.claude/skills/memory-bank
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats
```
### Edge cases
- Self-claim race: two agents init the same source → the loser gets exit 4 and picks the next task (no double-work).
- A crashed async agent leaves a live claim → `--takeover` (documented in Этап 7) frees it.

---

## Zones of non-contact (constraints)
This plan owns the **`/mb work` per-run bookkeeping** surface. It does **not** touch (per the brief):
`hooks/mb-session-*`, `scripts/mb-session-*`, `session-end-autosave.sh`, `hooks/lib/session-common.sh`,
`SKILL.md`. All documentation lands in `commands/work.md`. The owner-token lock pattern in
`mb-work-progress-append.sh` is a **fresh implementation** (mirroring `mb-handoff.sh`'s idea), not an edit
to `session-common.sh::sc_lock`.

---

## Граф зависимостей

```
T1  Этап1 (slots+state) ──┬──► Этап2 (budget)   ──┐
                          ├──► Этап3 (checkbox) ──┤
                          ├──► Этап4 (diff, T3) ──┤
                          └──► Этап5 (resolve,T2)─┤
T4  Этап6 (progress-append, independent) ─────────┤
                                                   ▼
                    work.md single-owner chain:  Этап7 ──► Этап8 ──► Этап9 ──► Этап10
                    (Этап7←1,2,3) (Этап8←7,4,5) (Этап9←8,6) (Этап10←9)
```

## Параллелизация
| Фаза | Этапы | Агенты |
|------|-------|--------|
| 1 | 1, 6 (independent new files) | dev-1 (slots+state), dev-2 (progress-append), tester |
| 2 | 2, 3, 4, 5 (all depend only on Этап 1's slots helper; distinct files) | dev-1, dev-2, dev-3, tester |
| 3 | 7 → 8 → 9 → 10 (sequential, single owner of `commands/work.md`) | dev-1 (work.md owner) + tester |

## Потенциальные конфликты при merge
- **`commands/work.md`** — edited by Этапы 7, 8, 9, 10 → **one owner**, land in order 7→8→9→10; each an additive distinct-section edit.
- **`tests/bats/test_mb_work_command_doc.bats`** — extended by Этапы 7, 8, 9, 10 → same owner appends `@test` blocks sequentially.
- **`scripts/mb-work-slots.sh`** — created in Этап 1; only **sourced** (never edited) by Этапы 2, 3, 4, 5 → no code conflict.
- **`scripts/mb-work-state.sh`** — only Этап 1 edits it. **`mb-work-budget.sh`** — only Этап 2. **`mb-work-checkbox.sh`** — only Этап 3. **`mb-work-resolve.sh`** — only Этап 5. No overlap.
- No contact with the constrained session/SKILL surface (see Zones of non-contact).

## DoD (plan-level)
- [ ] T1: per-run `.work-state/<run_id>.json` + `.work-budget/<run_id>.json` isolate concurrent runs; source→run index + claim **exit 4** + `--takeover`; `status --all`; all `MB_WORK_PARALLEL`-gated.
- [ ] T2: resolve `--skip-claimed` avoids double-claiming a plan on empty-target; explicit claimed target warns.
- [ ] T3: `baseline_ref` recorded at init; verify/review diff via `mb-work-diff.sh` (single-arg `git diff <baseline> -- <files>`, видит и uncommitted — Amendment 2026-07-05); inter-plan-worktree rule documented.
- [ ] T4: `mb-work-progress-append.sh` locked atomic append; checklist-via-checkbox single-writer; durable=checkboxes/state, TaskUpdate ephemeral.
- [ ] T5: `commands/work.md` "Parallel runs" section (two patterns, sync/async spawn, report delivery, self-claim pull).
- [ ] Every stage has a failing test committed BEFORE its implementation (TDD evidence in git history: red→green).
- [ ] **Back-compat hard gate:** with `MB_WORK_PARALLEL` unset, all 49 existing I-093 pytest + 22 bats stay green **unchanged**; default state/budget/checkbox/resolve paths byte-identical (mb-fanout.sh:255 still resolves the singleton budget).
- [ ] All new/edited shell: `shellcheck` clean, ≤400 lines, `+x` on new scripts, bash 3.2 + 5.x; `mb-work-state.sh` stays ≤400 via the extracted slots helper.
- [ ] Fail-safe: corrupt/absent slot or index degrades to a no-op / singleton, never wedges a session; the only new enforcement exit is claim-refused (4).
- [ ] Backlog **I-094** registered; `progress.md` appended; `checklist.md` updated.

## Full verification
```bash
cd /Users/fockus/.claude/skills/memory-bank

# New + extended unit/contract
PATH="$PWD/.venv/bin:$PATH" pytest \
  tests/pytest/test_mb_work_slots.py \
  tests/pytest/test_mb_work_state.py \
  tests/pytest/test_mb_work_budget.py \
  tests/pytest/test_mb_work_checkbox.py \
  tests/pytest/test_mb_work_resolve.py \
  tests/pytest/test_mb_work_diff.py \
  tests/pytest/test_mb_work_progress_append.py -q

# Doc-contract
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_mb_work_command_doc.bats

# Static analysis on every changed/new shell file
shellcheck \
  scripts/mb-work-slots.sh scripts/mb-work-state.sh scripts/mb-work-budget.sh \
  scripts/mb-work-checkbox.sh scripts/mb-work-resolve.sh scripts/mb-work-diff.sh \
  scripts/mb-work-progress-append.sh

# 400-line cap + executable bits + dual-shell smoke
for f in scripts/mb-work-slots.sh scripts/mb-work-state.sh scripts/mb-work-budget.sh \
         scripts/mb-work-checkbox.sh scripts/mb-work-resolve.sh scripts/mb-work-diff.sh \
         scripts/mb-work-progress-append.sh; do awk -v F="$f" 'END{if(NR>400)print F" OVER 400: "NR}' "$f"; done
test -x scripts/mb-work-diff.sh && test -x scripts/mb-work-progress-append.sh

# Back-compat sweep — full suite must be green with MB_WORK_PARALLEL unset
PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json
```

## Stage summary
| Stage | Theme | Type | Complexity | Depends | DoD |
|-------|-------|------|-----------|---------|-----|
| 1 | T1 slots+state+index+claim+baseline | new + edit + pytest | M | — | ⬜ |
| 2 | T1 budget per-run slot | edit + pytest | S | 1 | ⬜ |
| 3 | T1 checkbox per-run slot | edit + pytest | S | 1 | ⬜ |
| 4 | T3 baseline diff helper | new + pytest | M | 1 | ⬜ |
| 5 | T2 claim-aware resolve | edit + pytest | S | 1 | ⬜ |
| 6 | T4 locked progress append | new + pytest | M | — | ⬜ |
| 7 | T1 wire work.md | doc + bats | M | 1,2,3 | ⬜ |
| 8 | T2+T3 wire work.md | doc + bats | M | 7,4,5 | ⬜ |
| 9 | T4 wire work.md | doc + bats | S | 8,6 | ⬜ |
| 10 | T5 Parallel-runs section | doc + bats | M | 9 | ⬜ |

## Checklist (copy into checklist.md)
- ⬜ I-094 S1 (T1): `mb-work-slots.sh` + per-run state/index/claim(exit4)/baseline in `mb-work-state.sh`
- ⬜ I-094 S2 (T1): `mb-work-budget.sh` per-run `.work-budget/<run_id>.json` under `MB_WORK_PARALLEL`
- ⬜ I-094 S3 (T1): `mb-work-checkbox.sh` flip gated on the per-run state slot
- ⬜ I-094 S4 (T3): `mb-work-diff.sh` baseline-scoped diff for a run
- ⬜ I-094 S5 (T2): `mb-work-resolve.sh` skip foreign-claimed sources + explicit-claim warn
- ⬜ I-094 S6 (T4): `mb-work-progress-append.sh` locked atomic append-only writer
- ⬜ I-094 S7 (T1 wire): parallel state+budget+claim into `commands/work.md`
- ⬜ I-094 S8 (T2+T3 wire): baseline diff + claim-aware resolve + worktree rule into `commands/work.md`
- ⬜ I-094 S9 (T4 wire): concurrent core-file write contract into `commands/work.md`
- ⬜ I-094 S10 (T5): `commands/work.md` "Parallel runs" section
</content>
</invoke>
