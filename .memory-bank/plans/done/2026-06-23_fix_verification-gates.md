---
type: fix
scope: verification-gates
created: 2026-06-23
status: done
priority: HIGH
backlog: I-083
---

# Fix: Verification Gates Fail-Closed

Closes backlog item **I-083** from `reports/2026-06-23_codex-gpt5.5-skill-review.md` §04
(gaps). The `/mb done` verification gates can silently pass un-run or crashed
checks: the tests gate is fail-OPEN for runner crashes, malformed JSON, and bare
`tests_pass=null`, and the underlying test runner only knows Python+Go (so this
very repo's bats suite is never run by `/mb done`). CI also omits the tracked
`hooks/tests/*.bats` and large static-analysis surfaces.

## Goal

Make `/mb done` **fail-closed**: a gate must FAIL (not WARN/PASS) when the test
runner crashes, emits invalid JSON, or reports `tests_pass=null` without an
explicit `not_applicable=true`. Make the runner cover every stack this repo
actually uses (bats first), and surface the currently-unrun test + lint files in
CI. Net effect: a project that **today passes `/mb done` with red tests** must
**FAIL after the fix**.

## Reconciliation: current fail-open vs fail-closed (verified in code)

Read of `scripts/mb-done-gates.sh` (full) and `scripts/mb-test-run.sh` (full) on
2026-06-23 confirms the precise state. The earlier session-lifecycle note that
"error-rejection is present" was about the **rules / placeholders** gates, NOT
the tests gate.

| Gate / input | Code site | Current behaviour | Correct? |
| --- | --- | --- | --- |
| tests: runner exits non-zero (crash) | `mb-done-gates.sh:227` `out="$($runner_cmd 2>/dev/null \|\| true)"` | exit code discarded; parse yields `null` → treated as PASS-with-WARN | **FAIL-OPEN (bug)** |
| tests: runner emits invalid / empty JSON | `mb-done-gates.sh:228-242` parser → `null` | downgraded to PASS-with-WARN at `:261` | **FAIL-OPEN (bug)** |
| tests: `tests_pass=null` with NO `not_applicable` | `mb-done-gates.sh:261` `\|\| "$verdict" == "null"` | PASS-with-WARN | **FAIL-OPEN (bug)** |
| tests: `not_applicable=true` (real no-stack) | `mb-done-gates.sh:255,261` | PASS-with-WARN | correct — keep |
| tests: `tests_pass=false` | `mb-done-gates.sh:266` | FAIL | correct |
| rules: rules-check exits non-zero | `mb-done-gates.sh:298` `[[ "$rc" -ne 0 ]]` | FAIL | **fail-closed already** |
| placeholders: rules-check exits non-zero | `mb-done-gates.sh:319` `[[ "$rc" -ne 0 ]]` | FAIL | **fail-closed already** |

Runner side: `scripts/mb-test-run.sh` has **no** runner-level error field. The
`error_head` key at `:57-58` is per-failure metadata inside `failures[]`, not a
runner crash signal. Unsupported stacks (`bats`, `node`, `rust`, …) hit the
`*)` arm at `:191-193`, print a stderr warning, leave `tests_pass="null"`, and
`exit 0` (`:240`). `mb_detect_stack` in `_lib.sh:351` knows node/rust/java/etc.
but **never emits `bats`** (no manifest probe for `*.bats`), and `mb-test-run.sh`
has runners only for `python` (`:83`) and `go` (`:144`).

**Therefore the plan fixes only the three real fail-open inputs in the tests
gate (null/non-zero/invalid-JSON) plus the runner's stack coverage; it does NOT
touch the already-correct rules/placeholders rc checks.**

## Scope

### In scope
- `scripts/mb-done-gates.sh` — tests gate fail-closed for null / non-zero exit /
  invalid JSON, distinguishing real `not_applicable=true`.
- `scripts/mb-test-run.sh` — runner-level error signalling + bats stack support
  (+ explicit `test_command` override) so unsupported-but-present test suites are
  not silently skipped.
- `.github/workflows/test.yml` + `README.md` — run `hooks/tests/*.bats` and the
  `hooks/tests/*_test.py` pytest files; expand shellcheck/ruff targets.
  **`.github/workflows/` is a PROTECTED PATH (see Risks) — Stage 3 must NOT be
  applied without explicit user approval.**

### Out of scope
- The other I-082/I-084..I-086 findings (range-empty, agent-caps, security
  traversal). Separate plans.
- Rewriting per-stack output parsing for node/rust/java (Stage 2 adds a generic
  command path + bats; richer per-stack parsing is a follow-up backlog item).
- Touching the rules / placeholders gate logic (already fail-closed — see
  Reconciliation).

## Assumptions
- `python3`, `bash`, `git` available (already required by these scripts).
- bats is the canonical shell-test runner for this repo; the runner should detect
  it by presence of `*.bats` files under `tests/` or `hooks/tests/`.
- Existing stubs `MB_TEST_RUNNER_CMD` / `MB_RULES_CHECK_CMD` (used by
  `tests/bats/test_mb_done_gates.bats`) remain the deterministic seam for Stage 1.
- bash 3.2 (macOS default) and bash 5.x (CI ubuntu) must both pass — no `mapfile`,
  no `${var,,}` on bash 3.2, no associative arrays in new code.

## Risks

| Risk | Probability | Impact | Mitigation |
| --- | --- | --- | --- |
| `.github/workflows/` is protected — silent edit violates policy | High | High | Stage 3 is flagged; author edits ONLY after explicit user "go". Stages 1-2 land independently and are the BLOCKER fixes. |
| Making `null`→FAIL breaks legitimate no-stack repos (e.g. docs-only) | Medium | Medium | Keep `not_applicable=true` as the explicit PASS escape hatch; runner must emit it for genuinely test-less stacks. Add a regression test. |
| Expanded shellcheck/ruff surfaces new findings → red CI | High | Medium | Stage 3 budget includes fixing or deliberately-disabling (with inline justification) every newly surfaced finding before the workflow change is proposed. |
| bash 3.2 portability regressions in new runner code | Medium | High | Run the new bats locally on macOS bash 3.2; avoid 4.x-only builtins. |
| `bats` not installed in dev env → new runner tests skip | Low | Low | Guard with `command -v bats \|\| skip` exactly like existing contract bats. |

## Stages

<!-- mb-stage:1 -->
### Stage 1 — done-gates tests gate fail-closed (BLOCKER)

**Complexity:** M · **~5 min** · **Zависимости:** — · **Агент:** developer (TDD)
**Файлы:**
- modify `scripts/mb-done-gates.sh` (`run_tests_gate`, lines ~220-268)
- modify `tests/bats/test_mb_done_gates.bats` (add the failing cases FIRST)

**TDD — write these failing bats FIRST** (in `test_mb_done_gates.bats`, reuse the
existing `_make_test_runner_stub` / `MB_TEST_RUNNER_CMD` seam):

1. `test_done_tests_gate_runner_nonzero_exit_fails` — stub runner that prints a
   valid line then `exit 1`; assert the `tests` gate JSON is `"pass":false` and
   overall exit code is `2` (currently PASSes — RED).
2. `test_done_tests_gate_invalid_json_fails` — stub prints `not json at all`,
   exit 0; assert `tests` gate `"pass":false`, exit 2 (currently PASS — RED).
3. `test_done_tests_gate_empty_output_fails` — stub prints nothing, exit 0;
   assert `tests` gate `"pass":false`, exit 2 (currently PASS — RED).
4. `test_done_tests_gate_null_without_not_applicable_fails` — stub
   `{"stack":"python","tests_pass":null}` (no `not_applicable`); assert
   `"pass":false`, exit 2 (currently PASS-with-WARN — RED).
5. `test_done_tests_gate_null_with_not_applicable_passes` — stub
   `{"tests_pass":null,"not_applicable":true}`; assert `"pass":true`, exit 0
   (GREEN guard — must stay passing; protects docs-only repos).

**Реализация (`run_tests_gate`):**
- Capture the runner exit code: replace `out="$($runner_cmd 2>/dev/null || true)"`
  with a `set +e; out="$($runner_cmd 2>/dev/null)"; rc=$?; set -e` block so the
  crash signal is preserved.
- Add a `parse_ok` flag from the python parser: have the parser print a sentinel
  (e.g. `__noparse__`) when stdin contains no valid `{...}` line carrying a
  recognised key, distinct from a real `null` value.
- New decision order in `run_tests_gate`:
  1. `rc != 0` → `emit_gate "tests" "false" "runner exited rc=$rc"`.
  2. no parseable JSON object → `emit_gate "tests" "false" "runner output not valid JSON"`.
  3. `verdict == "true"` → PASS.
  4. `not_applicable == "true"` → PASS-with-WARN (keep current message).
  5. `verdict == "null"` (parseable, no `not_applicable`) →
     `emit_gate "tests" "false" "tests_pass=null without not_applicable"`.
  6. else (`verdict == "false"`) → FAIL.
- Keep emitting the structured JSON line in every branch (no behaviour change to
  `emit_gate`).

**DoD (SMART):**
- [x] 4 new RED→GREEN tests + 1 GREEN guard added to `test_mb_done_gates.bats`.
- [x] All 5 assert specific JSON `"pass"` values AND the process exit code (0 or 2).
- [x] `bash scripts/mb-done-gates.sh` exits 2 when the runner crashes / emits
      invalid JSON / reports bare `null`; exits 0 only on real PASS or
      `not_applicable=true`.
- [x] Existing `test_mb_done_gates.bats` cases stay green (no regression).
- [x] No new bash-4-only builtins (bash 3.2 portable).
- [x] `shellcheck -x scripts/mb-done-gates.sh` clean.

**Команды проверки:**
```bash
bats tests/bats/test_mb_done_gates.bats
shellcheck -x --source-path=scripts scripts/mb-done-gates.sh
```

**Edge cases:** runner prints WARN to stderr + valid JSON to stdout (must still
parse); runner prints multiple JSON lines (last `tests_pass` wins — current
parser already iterates); `not_applicable=true` together with `tests_pass=false`
(false wins — explicit failure beats not_applicable).

---

<!-- mb-stage:2 -->
### Stage 2 — test runner multi-stack incl. bats (BLOCKER)

**Complexity:** L · **~5 min** · **Зависимости:** — (parallel with Stage 1) · **Агент:** developer (TDD)
**Файлы:**
- modify `scripts/mb-test-run.sh` (stack detection + runners, lines ~64-194, exit at :240)
- modify `scripts/_lib.sh` `mb_detect_stack` (`:351`) and `mb_detect_test_cmd`
  (`:435`) to recognise `bats` — UNCONFIRMED whether to add `bats` as a primary
  stack vs a secondary signal; verify against `mb-metrics.sh` consumers before
  changing `mb_detect_stack` (it feeds metrics elsewhere). Safer default:
  detect bats INSIDE `mb-test-run.sh` without altering `mb_detect_stack`.
- new `tests/bats/test_test_runner_bats.bats`
- modify `tests/bats/test_test_runner_contract.bats` (unsupported-stack case)

**TDD — write these failing tests FIRST:**

1. `test_runner_bats_project_red_reports_false` — fixture dir with a single
   failing `*.bats` file; assert runner JSON `tests_pass == false`, `exit 0`
   (currently `stack=unknown`/`tests_pass=null` — RED). Guard with
   `command -v bats || skip`.
2. `test_runner_bats_project_green_reports_true` — fixture with a passing
   `*.bats`; assert `tests_pass == true`.
3. `test_runner_unsupported_stack_with_test_command_runs_it` — set
   `MB_TEST_COMMAND="false"` (or `--test-command false`) in a stack-less dir;
   assert `tests_pass == false`, NOT `null` (proves explicit override path).
4. `test_runner_no_tests_present_is_not_applicable` — genuinely empty dir; assert
   JSON includes `"not_applicable":true` and `tests_pass == null` (this is the
   escape hatch Stage 1 relies on — RED today: runner never emits
   `not_applicable`).
5. `test_runner_command_crash_reports_error` — `MB_TEST_COMMAND="exit 7"`; assert
   JSON carries a runner-error signal (`"runner_error":true` or `tests_pass:false`)
   so Stage 1's rc/JSON checks have something concrete to gate on.

**Реализация:**
- Add `--test-command <cmd>` flag + `MB_TEST_COMMAND` env: when set, run it
  verbatim in `$DIR`, map exit 0→`tests_pass=true`, non-zero→`false`. This is the
  generic, stack-agnostic path and the documented escape for unsupported stacks.
- Add `run_bats()`: detect `*.bats` under `$DIR/tests`, `$DIR/hooks/tests`, or
  `$DIR/**/*.bats` (bounded find, prune `node_modules`/`.git`); run
  `bats <files>`; parse the TAP/`ok`/`not ok` summary (`bats` prints
  `N tests, M failures`) into `TESTS_TOTAL`/`TESTS_FAILED`/`TESTS_PASS`.
- Emit `"not_applicable":true` in the JSON when, after detection, there are no
  tests AND no `--test-command` (replaces the silent `tests_pass=null` for the
  genuinely test-less case). Add `not_applicable` to `emit_json`.
- Keep `exit 0` always (the JSON, not the exit code, carries the verdict — Stage 1
  now reads both rc-of-runner and the JSON; the runner's OWN exit stays 0).
- Dispatch order in the `case "$STACK"`: if `*.bats` present → bats; else
  python/go as today; else if `MB_TEST_COMMAND` set → generic; else
  `not_applicable`.

**DoD (SMART):**
- [x] `run_bats` added; bats fixtures (red + green) under `tests/bats/fixtures/`.
- [x] Runner JSON gains `not_applicable` (boolean) and a runner-error signal.
- [x] 5 new tests in `test_test_runner_bats.bats`, all GREEN after impl.
- [x] `test_test_runner_contract.bats` updated: unsupported stack WITHOUT
      test_command → `not_applicable:true` (not a silent pass).
- [x] Existing `test_test_runner_{python,go,contract}.bats` stay green.
- [ ] bash 3.2 portable; `shellcheck -x scripts/mb-test-run.sh scripts/_lib.sh` clean.

**Команды проверки:**
```bash
bats tests/bats/test_test_runner_bats.bats tests/bats/test_test_runner_contract.bats \
     tests/bats/test_test_runner_python.bats tests/bats/test_test_runner_go.bats
shellcheck -x --source-path=scripts scripts/mb-test-run.sh
```

**Edge cases:** `bats` not in PATH (warn + `not_applicable`, never silent false);
both `*.bats` and `pyproject.toml` present (this repo — bats should run; document
precedence or run both and AND the verdicts); test_command with spaces/quotes
(run via `bash -c`); test_command that prints to stderr only.

---

<!-- mb-stage:3 -->
### Stage 3 — CI surface: hooks/tests + expanded static analysis (PROTECTED — NEEDS APPROVAL)

**Complexity:** M · **~5 min** · **Зависимости:** Stage 1, Stage 2 green · **Агент:** developer
**Файлы (PROTECTED — do NOT edit without explicit user "go"):**
- `.github/workflows/test.yml` (`:44-48` bats steps, `:74-81` lint steps)
- `README.md` (`:603` verification commands)

> **HARD GATE:** `.github/workflows/` is a protected path under both global and
> project rules (`mb-work-protected-check.sh`, quality-gate hook). This stage is
> drafted but **MUST NOT be applied until the user explicitly approves the
> workflow edit.** Stages 1-2 are the substantive BLOCKER fixes and ship without
> this stage. Present the diff and wait for "go".

**Задачи:**
1. Add a CI step `Run bats hook tests` → `bats hooks/tests/*.bats` (after the
   existing `tests/bats/` and `tests/e2e/` steps at `:44-48`).
2. Add `hooks/tests/*_test.py` to the pytest invocation (or a dedicated step):
   `python -m pytest hooks/tests/ tests/pytest/` — VERIFY coverage-fail-under
   still holds; hook pytest files use `_test.py` suffix, confirm pytest collects
   them (may need `python_files` config or explicit path).
3. Expand shellcheck targets at `:74-78` to include `hooks/lib/*.sh`,
   `adapters/*.sh`, and install scripts — UNCONFIRMED exact globs; enumerate via
   `git ls-files '*.sh'` and decide includes vs documented disables.
4. Expand ruff targets at `:81` from `settings/ tests/pytest/` to add
   `scripts/*.py`, `hooks/lib/*.py`, `memory_bank_skill/`.
5. Fix every newly surfaced shellcheck/ruff finding, OR add an inline
   `# shellcheck disable=...` / `# noqa:` with a one-line justification.
6. Update `README.md:603` verification block to list `bats hooks/tests/*.bats`
   and the expanded pytest/lint commands.

**DoD (SMART):**
- [x] User has explicitly approved the `.github/workflows/test.yml` edit.
- [x] `bats hooks/tests/*.bats` runs in CI and is green.
- [x] `hooks/tests/*_test.py` collected by pytest in CI and green.
- [x] `shellcheck -x hooks/lib/*.sh adapters/*.sh install.sh` → 0 findings (or
      every disable justified inline).
- [x] `ruff check scripts/ hooks/lib/ memory_bank_skill/ settings/ tests/pytest/`
      → 0 findings (or every `noqa` justified).
- [x] `README.md` verification commands match the CI steps exactly.

**Команды проверки (run locally before proposing the protected edit):**
```bash
bats hooks/tests/*.bats
python -m pytest hooks/tests/ tests/pytest/ -q
shellcheck -x $(git ls-files 'hooks/lib/*.sh' 'adapters/*.sh' 'scripts/*.sh') install.sh
ruff check scripts/ hooks/lib/ memory_bank_skill/ settings/ tests/pytest/
```

**Edge cases:** pytest path collision between `hooks/tests/` and `tests/pytest/`
(duplicate basenames → use `rootdir`/`--import-mode=importlib`); macOS CI runner
already in matrix (`:17`) — bats hook tests must pass on macOS bash 3.2 too;
shellcheck `--source-path` for `hooks/lib` sourced files.

---

## Verification (whole plan — proves the fix end-to-end)

**Before-fix demonstration (must show the bug):**
```bash
# Build a throwaway project whose tests are RED but pass /mb done today.
TMP=$(mktemp -d); mkdir -p "$TMP/.memory-bank" "$TMP/tests"
printf '#!/usr/bin/env bats\n@test "x" { false; }\n' > "$TMP/tests/red.bats"
# A) bats-only red project (Stage 2 target):
bash scripts/mb-done-gates.sh --dir "$TMP" --out json; echo "exit=$?"   # TODAY: exit 0 (BUG)
# B) crashed/invalid runner (Stage 1 target):
MB_TEST_RUNNER_CMD='bash -c "echo not-json; exit 1"' \
  bash scripts/mb-done-gates.sh --dir "$TMP" --out json; echo "exit=$?" # TODAY: exit 0 (BUG)
```

**After-fix expectation:**
- A) bats-only red project → `tests` gate `"pass":false`, **exit 2**.
- B) crashed/invalid runner → `tests` gate `"pass":false`, **exit 2**.
- Genuinely test-less dir (no `*.bats`, no test_command) → `not_applicable:true`,
  `tests` gate PASS-with-WARN, exit 0 (escape hatch preserved).

**Suite:**
```bash
bats tests/bats/test_mb_done_gates.bats \
     tests/bats/test_test_runner_bats.bats \
     tests/bats/test_test_runner_contract.bats \
     tests/bats/test_test_runner_python.bats \
     tests/bats/test_test_runner_go.bats
shellcheck -x --source-path=scripts scripts/mb-done-gates.sh scripts/mb-test-run.sh scripts/_lib.sh
# Stage 3 only after approval:
bats hooks/tests/*.bats && python -m pytest hooks/tests/ tests/pytest/ -q
```

## DoD (plan-level)

- [x] Stage 1: tests gate FAILS for runner non-zero exit, invalid/empty JSON, and
      bare `tests_pass=null`; PASSes only on real pass or `not_applicable=true`.
- [x] Stage 2: runner detects/runs bats, honours `--test-command`/`MB_TEST_COMMAND`,
      emits `not_applicable` + a runner-error signal; no silent `null` for
      present-but-unsupported suites.
- [x] Before/after demo: a red bats-only project FLIPS from `/mb done` exit 0 →
      exit 2.
- [x] Stage 3 drafted; `.github/workflows/test.yml` + README edits applied ONLY
      after explicit user approval (protected path).
- [ ] All new + existing bats/pytest green on bash 3.2 (macOS) and 5.x (CI).
- [ ] `shellcheck` + `ruff` clean on all touched files.
- [ ] No placeholders; files ≤400 lines (`mb-done-gates.sh` is 419 today — keep
      the tests-gate change net-neutral or extract a helper to stay ≤400;
      UNCONFIRMED — measure after edit and split if over).
- [ ] `progress.md` NOTE appended; `checklist.md` updated; backlog I-083 resolved.

## Checklist (copy into checklist.md)
- ⬜ I-083 Stage 1: done-gates tests gate fail-closed (null / non-zero / invalid JSON)
- ⬜ I-083 Stage 2: test-runner multi-stack incl. bats + `--test-command` + `not_applicable`
- ⬜ I-083 Stage 3: CI surface — hooks/tests + expanded static analysis (PROTECTED, needs approval)
