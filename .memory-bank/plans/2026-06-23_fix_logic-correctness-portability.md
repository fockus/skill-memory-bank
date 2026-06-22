---
type: fix
scope: logic-correctness-portability
created: 2026-06-23
status: queued
priority: MED
backlog: I-085
---

# Fix: Logic Correctness & Portability

Closes the logic-correctness and GNU/BSD-portability findings from
`reports/2026-06-23_codex-gpt5.5-skill-review.md` §01 / §02 / §04 (backlog I-085).

All findings were re-grounded against the live code on 2026-06-23 (line numbers
verified, see "Grounding" notes inline). Two known cross-references:
- **I-082 security hardening** (`plans/2026-06-23_fix_security-hardening.md`) Stage 2
  also edits `mb-work-resolve.sh` (Form 5 active-plan link, lines 109-115) and adds
  `mb_canonical_under` to `_lib.sh`. This plan's Stage 6 work-resolve fix edits a
  DIFFERENT region (Form 1 / Form 3, lines 124-154) for usability resolution — see
  Stage 6 merge note.
- **mtime helper** mirrors the already-shipped GNU/BSD-safe numeric-validated pattern
  in `hooks/mb-session-start-context.sh:73-83` and its regression tests in
  `tests/bats/test_mb_pre_compact.bats:67-81`.

## Goal

Eliminate three classes of defect that make the work spine and Dynamic-Flow router
either execute the wrong thing or break on Linux:

1. **Wrong-target execution (BLOCKER):** an in-bounds `--range N` that lands in a
   marker gap silently expands to the WHOLE plan.
2. **Router false-negatives & wrapper mis-parse (MAJOR):** lowercase contract files,
   untracked files, and comment-bearing / quoted wrapper frontmatter slip past gates.
3. **GNU/BSD portability (MAJOR/MINOR):** `base64 --decode` and BSD-first
   `stat -f %m` are broken on macOS BSD base64 and GNU stat respectively.

Every stage is TDD-first: the failing bats that proves the bug is written and run
RED before the fix, then driven to GREEN. Both `stat`/`base64` behaviours are
exercised so the portability fixes are real, not aspirational. No file is pushed
past 400 lines (several are already large — fixes extract helpers, not bulk).

## Stages

Order: BLOCKER first (Stage 1), then router false-negatives, wrapper parse, the two
`mb-conflicts.sh` portability/validation fixes, the centralized mtime helper, and
finally the two MINOR fanout/work-resolve usability fixes.

---

### Stage 1 — `--range N` marker-gap → whole-plan execution (BLOCKER)

**Grounding (verified 2026-06-23):**
- `scripts/mb-work-range.sh:151,169-175` — bounds check is `end > total` only; a gap
  index N where `1 <= N <= total` PASSES bounds, then the emit loop (173-175)
  prints NOTHING because no `s` in `stages` equals N.
- `scripts/mb-work-plan.sh:286-288` — `requested` parsed from range output; when
  EMPTY it falls back to `requested = sorted(items_by_no.keys())` → ALL items.
- `scripts/mb-work-plan.sh:150` — `STAGES_RAW=$(bash "$RANGE_SH" "$PLAN" --range "$RANGE")`.

**Repro:** a plan with markers `mb-stage:1`, `mb-stage:2`, `mb-stage:4` (gap at 3).
`mb-work-range.sh plan.md --range 3` → exit 0, empty stdout. `mb-work-plan.sh
--range 3` then emits ALL of stages 1,2,4.

**Files:**
- `tests/bats/test_mb_work_range.bats` (CREATE — RED first)
- `tests/bats/test_mb_work_plan_range.bats` (CREATE — RED first)
- `scripts/mb-work-range.sh` (EDIT — both `range_expr` blocks: plan mode lines
  153-176, phase mode lines 98-120)
- `scripts/mb-work-plan.sh` (EDIT — lines 285-288: only default-to-all when NO range
  was requested)

**Tasks:**
1. **RED** `tests/bats/test_mb_work_range.bats`:
   - `test_range_explicit_gap_index_exits_nonzero_with_diag` — plan with gap markers,
     `--range 3` → exit != 0 AND stderr contains the gap index.
   - `test_range_explicit_in_bounds_present_emits_only_that_index` — `--range 2` →
     stdout is exactly `2`, exit 0.
   - `test_range_omitted_emits_all_present_indices` — no `--range` → emits `1`,`2`,`4`.
2. **GREEN** `mb-work-range.sh`: after the emit loop, count emitted lines; when a
   range expr WAS supplied but zero existing indices fell inside it, write
   `[work-range] range <expr> resolves to no existing stage (present: 1,2,4)` to
   stderr and `sys.exit(1)`. Apply identically to BOTH the plan-mode python block
   (153-176) and the phase-mode python block (98-120) so both honour the contract.
3. **RED** `tests/bats/test_mb_work_plan_range.bats`:
   - `test_work_plan_gap_range_does_not_expand_to_all` — gap plan, `--range 3` →
     exit != 0; stdout has ZERO JSON Lines (no stage executed).
   - `test_work_plan_omitted_range_emits_all` — no range → JSON Lines for 1,2,4.
   - `test_work_plan_present_range_emits_single` — `--range 2` → exactly one JSON Line
     with `"stage_no": 2`.
4. **GREEN** `mb-work-plan.sh`: replace the silent fallback at 286-288. Pass an
   explicit "range requested" signal (the script already knows `RANGE`; thread it via
   a new env var `RANGE_REQUESTED=1/0`). When `requested` is empty AND
   `RANGE_REQUESTED==1` → `sys.stderr.write("[work-plan] range produced no
   stages\n"); sys.exit(1)`. Default-to-all ONLY when `RANGE_REQUESTED==0`. Also drop
   `|| true`-style swallowing: line 150 must propagate a non-zero range exit
   (`STAGES_RAW=$(bash "$RANGE_SH" "$PLAN" --range "$RANGE") || exit $?`).

**DoD (SMART):**
- [ ] `bats tests/bats/test_mb_work_range.bats` — ≥3 tests, all PASS.
- [ ] `bats tests/bats/test_mb_work_plan_range.bats` — ≥3 tests, all PASS.
- [ ] A gap `--range N` causes exit != 0 from BOTH scripts; ZERO JSON Lines emitted.
- [ ] An omitted range still emits all present indices (no regression).
- [ ] `shellcheck scripts/mb-work-range.sh scripts/mb-work-plan.sh` clean.
- [ ] `mb-work-plan.sh` and `mb-work-range.sh` each stay ≤400 lines.

**Edge cases:** all-gap plan (markers 2,4 only, request 1) → exit 1; request that is
`total+1` → existing out-of-bounds error (line 169) preserved; phase mode gap.

**Commands:**
```bash
bats tests/bats/test_mb_work_range.bats tests/bats/test_mb_work_plan_range.bats
shellcheck scripts/mb-work-range.sh scripts/mb-work-plan.sh
```

---

### Stage 2 — Flow-route false negatives: lowercase contract files + untracked files (MAJOR ×2)

**Grounding (verified 2026-06-23):**
- `scripts/mb-flow-route.sh:414-462` — floor case-globs match `*Interface*`,
  `*Contract*`, `*Protocol*`, `*ABC.*` (PascalCase) and dir forms, but NOT lowercase
  basenames: `src/user_interface.py`, `src/api_contract.py`, `src/user_protocol.py`,
  `src/user_abc.py` fall through (no `/interface.` segment, no capital). Confirmed.
- `scripts/mb-flow-route.sh:386-396` — auto changed-file list uses only
  `git diff --name-only` + `--cached`; untracked files are NOT included. A brand-new
  untracked `domain/User.py` or `contract.py` will not force the `arch` route.

**Files:**
- `tests/bats/test_mb_flow_route.bats` (EDIT — append RED cases; file already exists)
- `scripts/mb-flow-route.sh` (EDIT — case block 414-462 + changed-file assembly 386-396)

**Tasks:**
1. **RED** in `test_mb_flow_route.bats`:
   - `test_route_floor_lowercase_interface_basename_forces_arch` — `--changed
     src/user_interface.py` → route is `arch`, reason mentions interface.
   - `test_route_floor_lowercase_contract_basename_forces_arch` — `src/api_contract.py`.
   - `test_route_floor_lowercase_protocol_basename_forces_arch` — `src/user_protocol.py`.
   - `test_route_floor_lowercase_abc_basename_forces_arch` — `src/user_abc.py`.
   - `test_route_floor_includes_untracked_domain_file` — in a git repo, create an
     UNTRACKED `domain/New.py` (not added), run auto detection → route `arch`.
2. **GREEN (lowercase):** inside the `for file in "${changed[@]}"` loop, after the
   Windows-separator normalization (line 410), add a lowercased copy
   `lc="$(printf '%s' "$file" | tr '[:upper:]' '[:lower:]')"` and add `*interface*`,
   `*contract*`, `*protocol*`, `*abc*` substring globs matched against `$lc` (these
   are deliberately broad — false positives are ACCEPTABLE per ADR-4, false negatives
   are NOT). Keep the existing dir/PascalCase cases (they remain correct and
   reason-specific). Guard the broad `*abc*` glob so it does not over-match unrelated
   words by anchoring on `*_abc*`, `*abc.*`, `*/abc*` segments in addition.
3. **GREEN (untracked):** in the changed-file assembly (386-396) add a third producer
   `git -C "$repo" ls-files --others --exclude-standard 2>/dev/null` to the
   brace-group piped into `sort -u`, so untracked files join `diff` + `--cached`.

**DoD (SMART):**
- [ ] `bats tests/bats/test_mb_flow_route.bats` — ≥5 NEW tests added, all PASS, no
      pre-existing test regresses.
- [ ] `src/user_interface.py`, `src/api_contract.py`, `src/user_protocol.py`,
      `src/user_abc.py` each route to `arch` (verified by assertion on the route field).
- [ ] An untracked `domain/*` / contract file forces `arch` in auto mode.
- [ ] `shellcheck scripts/mb-flow-route.sh` clean.
- [ ] `mb-flow-route.sh` stays ≤400 lines net of the change? (CURRENTLY 553 lines —
      see Risks: this file is already over 400. The fix adds ≤15 lines; do NOT grow it
      further. Flag a separate refactor backlog item if it crosses a hard ceiling.)

**Edge cases:** `maindomain.py` / `abstract.py` must NOT falsely route arch — verify
the anchored `*abc*` globs don't catch `abstract`; a file named `Interface.py`
(already covered by `*Interface*`) must still route; mixed-case `User_Interface.py`.

**Commands:**
```bash
bats tests/bats/test_mb_flow_route.bats
shellcheck scripts/mb-flow-route.sh
```

---

### Stage 3 — Wrapper frontmatter parse: comment-aware + quote-aware (MAJOR)

**Grounding (verified 2026-06-23):**
- `scripts/mb-work-plan.sh:108-111` — `linked_spec` and `tasks` parsed with
  `^linked_spec:\s*(\S+)\s*$` / `^tasks:\s*(\S+)\s*$`. `tasks: 1-3 # comment` →
  trailing ` # comment` defeats `\s*$` so `tk` is None → `WRAPPER_RANGE` empty → at
  lines 144-146 RANGE is NOT overridden → ALL spec tasks run. Quoted
  `linked_spec: "specs/foo"` → `\S+` captures the literal quotes → `os.path.join`
  builds `…/"specs/foo"/tasks.md` → not found → exit 1 (loud, but wrong: a valid
  quoted scalar is rejected).

**Files:**
- `tests/bats/test_mb_work_plan_wrapper.bats` (CREATE — RED first)
- `scripts/mb-work-plan.sh` (EDIT — the `WRAPPER_INFO` python block, lines 94-135)

**Tasks:**
1. **RED** `tests/bats/test_mb_work_plan_wrapper.bats`:
   - `test_wrapper_tasks_with_trailing_comment_overrides_range` — wrapper plan with
     `tasks: 1-3 # only the first three` → emitted JSON Lines cover ONLY stages 1-3,
     not the whole spec.
   - `test_wrapper_quoted_linked_spec_resolves` — `linked_spec: "specs/foo"` (quoted)
     → resolves to `…/specs/foo/tasks.md` (exists) → stages emitted (exit 0).
   - `test_wrapper_single_quoted_linked_spec_resolves` — `linked_spec: 'specs/foo'`.
   - `test_wrapper_no_tasks_key_runs_all` — no `tasks:` line → all spec tasks (no
     regression).
2. **GREEN** in the `WRAPPER_INFO` python block: replace the two regexes with a
   comment-and-quote-aware scalar parser. For each frontmatter line matching
   `^(linked_spec|tasks):\s*(.*)$`, take the value, strip an unquoted trailing
   `#…` comment (a `#` that is NOT inside quotes), then `.strip()`, then strip a
   single matching pair of surrounding `"`/`'`. This is a minimal, dependency-free
   YAML-scalar reader (PyYAML is optional per the deps contract, so do NOT require
   it — keep stdlib). Reuse the existing resolution / not-found handling unchanged.

**DoD (SMART):**
- [ ] `bats tests/bats/test_mb_work_plan_wrapper.bats` — ≥4 tests, all PASS.
- [ ] `tasks: N-M # comment` correctly limits execution to N-M (NOT all tasks).
- [ ] Quoted (single & double) `linked_spec` resolves to the real tasks.md.
- [ ] Missing `tasks:` still runs all (documented behaviour preserved).
- [ ] `shellcheck scripts/mb-work-plan.sh` clean; file ≤400 lines.

**Edge cases:** value with a `#` inside quotes (`linked_spec: "specs/a#b"`) must NOT
be truncated; empty value after stripping a comment → treat as absent; `tasks:`
with only whitespace+comment → absent (run all).

**Commands:**
```bash
bats tests/bats/test_mb_work_plan_wrapper.bats
shellcheck scripts/mb-work-plan.sh
```

---

### Stage 4 — `mb-conflicts.sh`: portable base64 decode + finite threshold (MAJOR + MINOR)

**Grounding (verified 2026-06-23, line numbers RE-LOCATED):**
- `scripts/mb-conflicts.sh:342-343` — `BODY_A="$(printf '%s' "$eba" | base64 --decode
  2>/dev/null || true)"` (and `:343` for `BODY_B`). macOS BSD `base64` has NO
  `--decode` flag (it uses `-D`); `--decode` errors, `2>/dev/null` hides it, `|| true`
  yields EMPTY → the judge receives empty ENTRY A/B bodies and judges noise.
  (The recent bash-3.2 heredoc backtick fix is unrelated and untouched by this stage;
  the `b64encode` at 286-287 also stays as-is.)
- `scripts/mb-conflicts.sh:81-83` — `threshold = float(os.environ.get("MB_THRESHOLD",
  "0.3"))` inside `except ValueError: threshold = 0.3`. `float("nan")` /
  `float("inf")` PARSE fine (no ValueError), so `--threshold nan` is accepted and
  breaks every Jaccard comparison. The CLI presence check (lines 47-48) only ensures
  non-empty, not finite.

**Files:**
- `tests/bats/test_conflicts.bats` (EDIT — append RED cases; file exists)
- `scripts/mb-conflicts.sh` (EDIT — base64 decode lines 342-343; threshold parse 81-83)

**Tasks:**
1. **RED** in `test_conflicts.bats`:
   - `test_conflicts_judge_decodes_body_portably` — drive the judge path with a stub
     `$CLAUDE` that ECHOES back the prompt it received; assert the prompt contains the
     real ENTRY A / ENTRY B text (NOT empty). This fails today on BSD-style decode.
   - `test_conflicts_threshold_nan_rejected` — `--threshold nan` → exit 64.
   - `test_conflicts_threshold_inf_rejected` — `--threshold inf` → exit 64.
   - `test_conflicts_threshold_out_of_range_rejected` — `--threshold 1.5` and
     `--threshold -0.1` → exit 64.
   - `test_conflicts_threshold_valid_accepted` — `--threshold 0.4` → exit 0.
2. **GREEN (base64):** replace the two decode calls with a portable decode. Preferred:
   decode via Python stdlib in the existing python toolchain context, OR a shell
   helper `_b64_decode() { base64 -d 2>/dev/null || base64 -D 2>/dev/null; }` and
   REMOVE the `|| true` so a genuinely failed decode surfaces (the judge must never
   silently receive an empty body — if decode fails, skip that candidate with a
   diagnostic, matching the existing "NO VERDICT" graceful path).
3. **GREEN (threshold):** validate in BOTH places. In the python block (81-83): after
   parsing, `if not math.isfinite(threshold) or not (0.0 <= threshold <= 1.0):
   sys.stderr.write(...); sys.exit(64)`. Prefer to validate at the SHELL CLI layer
   (after lines 47-50) so a bad value fails before any work: a small `python3 -c`
   guard or a regex+range check that exits 64 on nan/inf/out-of-range.

**DoD (SMART):**
- [ ] `bats tests/bats/test_conflicts.bats` — ≥5 NEW tests, all PASS.
- [ ] Judge receives the ACTUAL entry bodies (verified via stub-CLAUDE echo) on the
      decode path; failed decode → candidate skipped with a diagnostic, NOT empty.
- [ ] `--threshold {nan,inf,1.5,-0.1}` each exit 64; `--threshold 0.4` exits 0.
- [ ] Fix works on both BSD (`-D`) and GNU (`-d`) base64 — test asserts on the
      decoded TEXT, not on a flag, so it passes on either platform.
- [ ] `shellcheck scripts/mb-conflicts.sh` clean; file ≤400 lines (currently 395 —
      keep the fix net-neutral or extract; do NOT cross 400).

**Edge cases:** body containing newlines/Unicode (round-trips through b64); empty
body (b64 of "" → "") must decode to "" without erroring; `--threshold 0` and
`--threshold 1` are valid (inclusive bounds).

**Commands:**
```bash
bats tests/bats/test_conflicts.bats
shellcheck scripts/mb-conflicts.sh
```

---

### Stage 5 — Centralized GNU/BSD numeric mtime helper across all call sites (MAJOR)

**Grounding (verified 2026-06-23):**
- `scripts/_lib.sh:66-73` `mb_mtime()` — BSD-first `stat -f%m || stat -c%Y || 0`.
- `scripts/mb-handoff.sh:36-38` `_mtime()` — BSD-first `stat -f %m || stat -c %Y`.
- `scripts/mb-flow-sync.sh:57-59` `_mtime()` — identical BSD-first duplicate.
- Call sites: `mb-compact.sh:51`, `mb-drift.sh:73,146,149`, `mb-flow-sync.sh:72`,
  `mb-handoff.sh:53,176`, `mb-migrate-structure.sh:41` (all via `_mtime`/`mb_mtime`).
- **Bug:** on GNU/Linux `stat -f` = `--file-system` and exits 0 printing non-numeric
  filesystem info, so `||` NEVER fires → a non-numeric string is returned, breaking
  the `$(( now - mtime ))` lock-age arithmetic. The CORRECT pattern already ships in
  `hooks/mb-session-start-context.sh:73-83` (validate `^[0-9]+$` per branch) with a
  regression test at `tests/bats/test_mb_pre_compact.bats:67-81` (GNU-first ordering).

**Files:**
- `tests/bats/test_mb_mtime_shim.bats` (CREATE — RED first; the stat-shim regression)
- `scripts/_lib.sh` (EDIT — replace `mb_mtime` body with validated GNU-first+BSD form)
- `scripts/mb-handoff.sh` (EDIT — delete local `_mtime`, route to `mb_mtime`)
- `scripts/mb-flow-sync.sh` (EDIT — delete local `_mtime`, route to `mb_mtime`)
- `scripts/mb-drift.sh` (EDIT — `_mtime` calls → `mb_mtime`)
- `scripts/mb-compact.sh`, `scripts/mb-migrate-structure.sh` (already use `mb_mtime` —
  verify they pick up the new body; no edit beyond confirming the source order)

**Tasks:**
1. **RED** `tests/bats/test_mb_mtime_shim.bats`:
   - `test_mb_mtime_returns_numeric_epoch_for_existing_file` — `mb_mtime` of a real
     file is `^[0-9]+$` and `> 0`.
   - `test_mb_mtime_returns_zero_for_missing_file` — missing path → `0`.
   - `test_mb_mtime_gnu_stat_shim_returns_numeric` — prepend a PATH shim where `stat`
     emulates GNU (`-f` prints verbose filesystem text + exit 0; `-c %Y` prints the
     epoch). Assert `mb_mtime` returns the EPOCH, not the filesystem text. This is the
     regression that the BSD-first form FAILS.
   - `test_mb_mtime_bsd_stat_shim_returns_numeric` — shim where `stat -f %m` prints
     the epoch and `-c` is unsupported; assert epoch returned.
   - `test_handoff_lock_age_arithmetic_survives_gnu_stat` — drive `mb-handoff.sh`'s
     lock-age path under the GNU shim; assert no arithmetic error (`integer expression
     expected`) and the lock TTL logic works.
2. **GREEN** `_lib.sh::mb_mtime`: rewrite to the validated form (mirror
   `mb-session-start-context.sh`). Try GNU first per the shipped test's documented
   ordering (`stat -c %Y` validated `^[0-9]+$`), else BSD (`stat -f %m` validated),
   else `0`. Keep the missing-file `[ -e ] → 0` guard. Single source of truth.
3. **GREEN** route all sites through it: delete `_mtime()` in `mb-handoff.sh` and
   `mb-flow-sync.sh` and replace internal `_mtime "$x"` calls with `mb_mtime "$x"`
   (both already `source _lib.sh`). Replace `_mtime` → `mb_mtime` in `mb-drift.sh`.
   Confirm `mb-compact.sh:51` / `mb-migrate-structure.sh:41` already call `mb_mtime`.

**DoD (SMART):**
- [ ] `bats tests/bats/test_mb_mtime_shim.bats` — ≥5 tests, all PASS, incl. the GNU
      and BSD `stat` shims (both behaviours explicitly exercised).
- [ ] Exactly ONE mtime implementation remains (`_lib.sh::mb_mtime`); `grep -rn
      '_mtime()' scripts/` returns nothing; no `stat -f %m` without numeric validation
      remains in `scripts/`.
- [ ] `mb_mtime` always returns `^[0-9]+$` (or `0`) on BOTH GNU and BSD.
- [ ] No call site regresses (handoff/flow-sync lock TTL, drift age) — green tests.
- [ ] `shellcheck` clean for every edited script; all ≤400 lines (note: `_lib.sh`=542,
      `mb-flow-sync.sh`=469 are ALREADY >400 — removing the duplicate `_mtime` SHRINKS
      `mb-flow-sync.sh`; do not add net lines to `_lib.sh`).

**Edge cases:** path with spaces; a directory (mtime of a dir is valid); symlink
(realpath not required here — `stat` of the link target is fine); both `stat`
variants absent (busybox) → `0` fallback, no crash.

**Commands:**
```bash
bats tests/bats/test_mb_mtime_shim.bats tests/bats/test_mb_handoff_actualize.bats tests/bats/test_mb_flow_sync.bats
shellcheck scripts/_lib.sh scripts/mb-handoff.sh scripts/mb-flow-sync.sh scripts/mb-drift.sh
grep -rn '_mtime()' scripts/   # expect no output
```

---

### Stage 6 — Fanout stderr capture + bank-relative work-resolve targets (MINOR ×2)

**Grounding (verified 2026-06-23):**
- `scripts/mb-fanout.sh:393` — `bash -c "$CMD" >"$out_file" 2>/dev/null` discards
  branch stderr; the aggregator (464-476) emits only `"error": f"exit {rc}"`, so a
  failed parallel branch loses the concrete error.
- `scripts/mb-work-resolve.sh:124-154` — Form 1 (`[ -f "$TARGET" ]`) resolves only
  CWD-relative paths; a BANK-relative target like `specs/dynamic-flow/tasks.md` (the
  exact form roadmap/status expose) fails Form 1, is not found by Form 2 substring
  search in `plans/`, then Form 3 sanitizes the slashed string as a TOPIC → wrong
  path. Confirmed.

**CROSS-REFERENCE (I-082):** `plans/2026-06-23_fix_security-hardening.md` Stage 2 edits
`mb-work-resolve.sh:109-115` (Form 5, active-plan link) and ADDS `mb_canonical_under`
to `_lib.sh`. THIS stage edits Form 1 / Form 3 (124-154) — a different region — for
usability. **Merge note:** if I-082 lands first, REUSE its `mb_canonical_under
"$BANK" "$BANK/$TARGET"` helper here to canonicalize the bank-relative candidate and
reject `..`/escapes; if THIS lands first, add a local `[ -f "$BANK/$TARGET" ]` guard
restricted to `plans/` and `specs/` prefixes, and leave a TODO-free note for I-082 to
upgrade it to `mb_canonical_under`. Do NOT duplicate or weaken the traversal guard.

**Files:**
- `tests/bats/test_mb_fanout.bats` (EDIT — append RED case; file exists)
- `tests/bats/test_mb_work_resolve.bats` (CREATE — RED first)
- `scripts/mb-fanout.sh` (EDIT — spawn line 393 + aggregator error marker 464-476)
- `scripts/mb-work-resolve.sh` (EDIT — add bank-relative resolution before Form 3)

**Tasks:**
1. **RED** in `test_mb_fanout.bats`:
   - `test_fanout_failed_branch_includes_stderr_snippet` — a branch whose CMD writes
     a distinctive string to stderr then exits 1; assert the aggregate error marker
     for that branch contains a TRUNCATED snippet of that stderr (not just `exit 1`).
2. **GREEN** `mb-fanout.sh`: change line 393 to `2>"$err_file"` (where
   `err_file="$WORKDIR/err.$i"`). In the aggregator, when `rc != 0`, read `err.<i>`
   (bytes, defensive like `out.<i>`), truncate to a bounded length (e.g. 500 chars),
   and set `"error": f"exit {rc}: {snippet}"`. Keep exit-code authority and the
   strict-JSON contract intact (snippet is json.dumps-escaped).
3. **RED** `tests/bats/test_mb_work_resolve.bats`:
   - `test_work_resolve_bank_relative_spec_tasks` — from a CWD that is NOT the bank,
     `mb-work-resolve.sh specs/<topic>/tasks.md --mb "$BANK"` (exists) → prints the
     absolute path under `$BANK/specs/<topic>/tasks.md`, exit 0.
   - `test_work_resolve_bank_relative_plan` — `plans/<file>.md` resolves under bank.
   - `test_work_resolve_bank_relative_rejects_traversal` — `../../etc/passwd` → exit
     != 0 (no out-of-bank read). [If I-082 helper present, asserts via it.]
4. **GREEN** `mb-work-resolve.sh`: after Form 1 / Form 2 and BEFORE Form 3 topic
   sanitization (line ~148), add a guarded bank-relative branch: when `$TARGET`
   starts with `plans/` or `specs/`, resolve against `$BANK` (via `mb_canonical_under`
   if available, else `[ -f "$BANK/$TARGET" ]` with a `..`/absolute reject), and on a
   real file print its absolute path and exit 0. This keeps Form 3 as the fallback for
   bare topics.

**DoD (SMART):**
- [ ] `bats tests/bats/test_mb_fanout.bats` — new test PASS; failed-branch error marker
      includes a truncated stderr snippet; aggregate is still strict-valid JSON.
- [ ] `bats tests/bats/test_mb_work_resolve.bats` — ≥3 tests, all PASS.
- [ ] `specs/<topic>/tasks.md` and `plans/<file>.md` resolve relative to BANK from any
      CWD; traversal (`..`, absolute) is rejected.
- [ ] No overlap/conflict with I-082 traversal guard (cross-ref note honoured).
- [ ] `shellcheck scripts/mb-fanout.sh scripts/mb-work-resolve.sh` clean; both ≤400
      lines (note: `mb-fanout.sh`=549 ALREADY >400 — the change adds ≤8 lines; do not
      grow further; flag refactor backlog if a hard ceiling is crossed).

**Edge cases:** bank-relative target that does NOT exist → fall through to Form 3 /
existing not-found error (no silent success); fanout branch with EMPTY stderr → marker
is just `exit {rc}` (no trailing colon noise); very long stderr → bounded snippet.

**Commands:**
```bash
bats tests/bats/test_mb_fanout.bats tests/bats/test_mb_work_resolve.bats
shellcheck scripts/mb-fanout.sh scripts/mb-work-resolve.sh
```

---

## Verification

Run after each stage (RED → GREEN) and once at the end:

```bash
# Stage-scoped (see each stage's Commands block)
bats tests/bats/test_mb_work_range.bats tests/bats/test_mb_work_plan_range.bats \
     tests/bats/test_mb_work_plan_wrapper.bats tests/bats/test_mb_flow_route.bats \
     tests/bats/test_conflicts.bats tests/bats/test_mb_mtime_shim.bats \
     tests/bats/test_mb_fanout.bats tests/bats/test_mb_work_resolve.bats \
     tests/bats/test_mb_handoff_actualize.bats tests/bats/test_mb_flow_sync.bats

# Full bats + pytest regression (no other surface regressed)
bats tests/bats/

# Static analysis on every edited script
shellcheck scripts/mb-work-range.sh scripts/mb-work-plan.sh scripts/mb-flow-route.sh \
           scripts/mb-conflicts.sh scripts/_lib.sh scripts/mb-handoff.sh \
           scripts/mb-flow-sync.sh scripts/mb-drift.sh scripts/mb-fanout.sh \
           scripts/mb-work-resolve.sh

# Invariants
grep -rn '_mtime()' scripts/          # expect: no output (single mtime impl)
grep -rn 'base64 --decode' scripts/   # expect: no output (portable decode only)
```

CI note (separate from this plan but relevant): `tests/bats/` is run in CI; new test
files land there so they are exercised. Several edited scripts exceed the 400-line
soft ceiling already (`mb-flow-route.sh` 553, `mb-fanout.sh` 549, `_lib.sh` 542,
`mb-flow-sync.sh` 469) — see Risks; no stage may grow them, and Stage 5 SHRINKS
`mb-flow-sync.sh` by removing a duplicate helper.

## DoD

- [ ] Stage 1: gap `--range N` exits non-zero from both scripts; never expands to all.
- [ ] Stage 2: lowercase interface/contract/protocol/abc basenames + untracked
      domain/contract files force the `arch` route.
- [ ] Stage 3: wrapper `tasks:` with trailing comment limits execution; quoted
      `linked_spec` resolves.
- [ ] Stage 4: `mb-conflicts.sh` decodes bodies on BSD+GNU base64; non-finite /
      out-of-range threshold exits 64.
- [ ] Stage 5: single validated GNU/BSD `mb_mtime`; all call sites routed; GNU-stat
      regression test green; no unvalidated `stat -f %m` remains.
- [ ] Stage 6: fanout error markers carry a stderr snippet; bank-relative
      `specs/*`/`plans/*` targets resolve (with traversal rejected).
- [ ] Every new/edited test file PASSES; `bats tests/bats/` fully green.
- [ ] `shellcheck` clean for all 10 edited scripts.
- [ ] No edited script grows past 400 lines; the four already-over-400 files are not
      enlarged (Stage 5 shrinks one).
- [ ] No placeholders, no `|| true` masking of the fixed failure paths, no TODO.
- [ ] I-085 marked resolved in backlog; cross-reference to I-082 recorded so the two
      `mb-work-resolve.sh` edits merge without conflict.
