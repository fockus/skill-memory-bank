#!/usr/bin/env bats
# Tests for scripts/mb-flow-verify.sh — THE firewall fan-out (dynamic-flow Task 5).
#
# This is the LOAD-BEARING test of the whole dynamic-flow spec. The fan-out is
# the SOLE exit-code authority (ADR-3 / REQ-DF-040/041/044/060):
#
#   exit 0  — every check is green or skipped AND the severity-gate passes.
#   exit 1  — at least one check is a clean red (ok:false raised the counts) and
#             the gate fails; stdout/stderr NAMES the breaching check + finding.
#   exit 2  — a check SCRIPT ITSELF broke: it exited non-zero, crashed, or emitted
#             output that is not parseable JSON. DISTINCT from a clean ok:false.
#
# The crux (ADR-3): a red check must NEVER be swallowed as exit 0, and a broken
# check must NEVER be mistaken for a clean fail.
#
# Determinism: checks are injected via `--check 'name=command'` so the exit
# trichotomy is exercised without depending on real lint/test/git outcomes.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VERIFY="$REPO_ROOT/scripts/mb-flow-verify.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
  BINDIR="$TMPROOT/bin"
  mkdir -p "$BINDIR"

  # A pipeline.yaml whose gate forbids ANY blocker/major/minor (strict, the
  # default). This makes the severity-gate deterministic for these tests.
  cat > "$TMPBANK/pipeline.yaml" <<'EOF'
review:
  severity_gate:
    blocker: 0
    major: 0
    minor: 0
EOF
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# Write an executable stub check that prints a fixed JSON body on stdout and
# exits with a given code. Usage: make_stub <name> <exit> <json-body>
make_stub() {
  local name="$1" code="$2" body="$3"
  local path="$BINDIR/$name.sh"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$body'
exit $code
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

# A canonical runner JSON object (always exit 0). $1=name $2=ok $3=finding-or-empty
runner_json() {
  local name="$1" ok="$2" finding="${3:-}"
  if [ -n "$finding" ]; then
    printf '{"name":"%s","ok":%s,"findings":["%s"]}' "$name" "$ok" "$finding"
  else
    printf '{"name":"%s","ok":%s,"findings":[]}' "$name" "$ok"
  fi
}

# ═══════════════════════════════════════════════════════════════
# Basic existence / help
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: script exists and is executable" {
  [ -f "$VERIFY" ]
  [ -x "$VERIFY" ]
}

@test "flow-verify: --help prints the 0/1/2 exit contract and exits 0" {
  run bash "$VERIFY" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"exit 0"* ]]
  [[ "$output" == *"exit 1"* ]]
  [[ "$output" == *"exit 2"* ]]
}

# ═══════════════════════════════════════════════════════════════
# exit 0 — all green / skipped, gate passes
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: all checks green → exit 0" {
  local g1 g2
  g1="$(make_stub greenA 0 "$(runner_json lint true)")"
  g2="$(make_stub greenB 0 "$(runner_json acceptance true)")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "lint=bash $g1" \
    --check "acceptance=bash $g2"
  [ "$status" -eq 0 ]
}

@test "flow-verify: a skip (ok:null) contributes 0 and does not flip the gate → exit 0" {
  local g1 sk
  g1="$(make_stub greenA 0 "$(runner_json lint true)")"
  sk="$(make_stub skipper 0 "$(runner_json acceptance null)")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "lint=bash $g1" \
    --check "acceptance=bash $sk"
  [ "$status" -eq 0 ]
  # The skip must register as a null in the per-check results, not a failure.
  [[ "$output" == *'"ok":null'* ]] || [[ "$output" == *'"ok": null'* ]]
}

@test "flow-verify: all skips → totals all zero → exit 0" {
  local sk1 sk2
  sk1="$(make_stub s1 0 "$(runner_json lint null)")"
  sk2="$(make_stub s2 0 "$(runner_json acceptance null)")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "lint=bash $sk1" \
    --check "acceptance=bash $sk2"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"blocker":0'* ]] || [[ "$output" == *'"blocker": 0'* ]]
}

@test "flow-verify: emits structured JSON summary on exit 0" {
  local g1
  g1="$(make_stub greenA 0 "$(runner_json lint true)")"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $g1"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"blocker"'* ]]
  [[ "$output" == *'"major"'* ]]
  [[ "$output" == *'"minor"'* ]]
  [[ "$output" == *'"checks"'* ]] || [[ "$output" == *'"results"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# exit 1 — clean red, gate fails, breach is NAMED
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: one blocker (acceptance red) → exit 1 and NAMES the breach" {
  local red green
  red="$(make_stub acc 0 "$(runner_json acceptance false 'criterion X unmet')")"
  green="$(make_stub lt 0 "$(runner_json lint true)")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "acceptance=bash $red" \
    --check "lint=bash $green"
  [ "$status" -eq 1 ]
  # The breaching check name AND its finding text must appear so the repair
  # loop knows what to fix (REQ-DF-044/060).
  [[ "$output" == *"acceptance"* ]]
  [[ "$output" == *"criterion X unmet"* ]]
}

@test "flow-verify: a clean ok:false from a runner → exit 1, NOT 2 (the ADR-3 distinction)" {
  local red
  red="$(make_stub lt 0 "$(runner_json lint false 'F401 unused import')")"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $red"
  # ok:false with exit 0 is a clean fail → exit 1, never broke (2).
  [ "$status" -eq 1 ]
  [[ "$output" == *"lint"* ]]
  [[ "$output" == *"F401 unused import"* ]]
}

@test "flow-verify: a red result never prints a done/success signal (REQ-DF-044)" {
  local red
  red="$(make_stub acc 0 "$(runner_json acceptance false 'unmet')")"
  run bash "$VERIFY" "$TMPBANK" --check "acceptance=bash $red"
  [ "$status" -eq 1 ]
  # No success vocabulary on a red exit.
  [[ "$output" != *"FINISHED"* ]]
  [[ "$output" != *"DONE"* ]]
  [[ "$(printf '%s' "$output" | tr 'A-Z' 'a-z')" != *" done"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Severity normalization correctness
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: lint red maps to MAJOR (not blocker) — counts are exact" {
  local red
  red="$(make_stub lt 0 "$(runner_json lint false 'E501')")"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $red"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"blocker":0'* ]] || [[ "$output" == *'"blocker": 0'* ]]
  [[ "$output" == *'"major":1'* ]] || [[ "$output" == *'"major": 1'* ]]
}

@test "flow-verify: acceptance red maps to BLOCKER — counts are exact" {
  local red
  red="$(make_stub acc 0 "$(runner_json acceptance false 'unmet')")"
  run bash "$VERIFY" "$TMPBANK" --check "acceptance=bash $red"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"blocker":1'* ]] || [[ "$output" == *'"blocker": 1'* ]]
}

@test "flow-verify: a major-only finding does not become a blocker" {
  local red
  red="$(make_stub lt 0 "$(runner_json lint false 'msg')")"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $red"
  [ "$status" -eq 1 ]
  # blocker must stay 0 — a lint fail must not silently escalate.
  [[ "$output" == *'"blocker":0'* ]] || [[ "$output" == *'"blocker": 0'* ]]
}

@test "flow-verify: diff_scope red maps to BLOCKER (ADR-4 backstop)" {
  local red
  red="$(make_stub ds 0 "$(runner_json diff_scope false 'domain/foo.py out of scope')")"
  run bash "$VERIFY" "$TMPBANK" --check "diff_scope=bash $red"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"blocker":1'* ]] || [[ "$output" == *'"blocker": 1'* ]]
  [[ "$output" == *"domain/foo.py out of scope"* ]]
}

# ═══════════════════════════════════════════════════════════════
# exit 2 — a check script ITSELF broke
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: a check that exits non-zero → exit 2 (broke, not fail)" {
  local broke green
  # Runner contract is exit 0 ALWAYS; a non-zero exit means it crashed.
  broke="$(make_stub bk 3 "$(runner_json lint true)")"
  green="$(make_stub gt 0 "$(runner_json acceptance true)")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "lint=bash $broke" \
    --check "acceptance=bash $green"
  [ "$status" -eq 2 ]
  [[ "$output" == *"lint"* ]]
}

@test "flow-verify: a check that emits non-JSON → exit 2 (unparseable, broke)" {
  local broke
  broke="$(make_stub bk 0 'this is not json at all')"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $broke"
  [ "$status" -eq 2 ]
  [[ "$output" == *"lint"* ]]
}

@test "flow-verify: a check whose JSON lacks the ok field → exit 2 (malformed, broke)" {
  local broke
  broke="$(make_stub bk 0 '{"name":"lint","findings":[]}')"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $broke"
  [ "$status" -eq 2 ]
}

@test "flow-verify: a missing check command → exit 2 (broke)" {
  run bash "$VERIFY" "$TMPBANK" --check "lint=$BINDIR/does-not-exist.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"lint"* ]]
}

@test "flow-verify: broke (2) takes precedence over a clean red (1)" {
  local broke red
  broke="$(make_stub bk 5 'garbage')"
  red="$(make_stub rd 0 "$(runner_json acceptance false 'unmet')")"
  run bash "$VERIFY" "$TMPBANK" \
    --check "lint=bash $broke" \
    --check "acceptance=bash $red"
  # A broken check is a louder failure than a clean red — never collapse to 1
  # (and certainly never to 0).
  [ "$status" -eq 2 ]
}

@test "flow-verify: a broken check is NEVER swallowed as exit 0" {
  local broke
  broke="$(make_stub bk 2 'not-json')"
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $broke"
  [ "$status" -ne 0 ]
  [ "$status" -eq 2 ]
}

@test "flow-verify: an inline check that calls exit cannot hijack the firewall exit code" {
  # Checks are run via eval. A check command that calls `exit` INLINE (not in a
  # child process) must NOT escape the firewall's 0/1/2 authority — its non-zero
  # exit has to be captured and mapped to broke (exit 2), exactly like a child
  # process exiting non-zero. The firewall is the SOLE exit-code authority; an
  # `exit 3` leaking straight to the caller would defeat that contract.
  local jf="$TMPROOT/inline-evil.json" gf="$TMPROOT/good.json"
  printf '%s' "$(runner_json lint true)" > "$jf"
  printf '%s' "$(runner_json good true)" > "$gf"
  run bash "$VERIFY" "$TMPBANK" \
    --check "good=cat '$gf'" \
    --check "evil=cat '$jf'; exit 3"
  [ "$status" -ne 3 ]
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Phase selection / build-skip
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: --phase is accepted and informational (does not error)" {
  local g1
  g1="$(make_stub greenA 0 "$(runner_json lint true)")"
  run bash "$VERIFY" "$TMPBANK" --phase implement --check "lint=bash $g1"
  [ "$status" -eq 0 ]
}

@test "flow-verify: unknown flag → exit 2 (usage error)" {
  run bash "$VERIFY" "$TMPBANK" --bogus
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# Default check set — the real runners must wire cleanly (no BROKE)
# ═══════════════════════════════════════════════════════════════
#
# These guard against a reused check (e.g. mb-test-run.sh, whose JSON carries
# `tests_pass`, NOT the {name,ok,findings} runner shape) being wired raw and
# mis-flagged as BROKE. The default `tests` adapter must normalize it.

@test "flow-verify: default set on an unknown-stack bank with a MET goal → exit 0 (no BROKE)" {
  # An isolated temp dir that is NOT a python/go project: mb-test-run.sh reports
  # tests_pass=null (unknown stack) → the adapter maps it to a skip, not a BROKE.
  local prj="$TMPROOT/prj"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 0 ]
  # The tests check must be a clean skip, never a broke.
  [[ "$output" != *'"name":"tests","ok":null,"severity":null,"findings":[],"status":"broke"'* ]]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

@test "flow-verify: default set on a bank with an UNMET goal → exit 1, names the unmet criterion" {
  local prj="$TMPROOT/prj2"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [ ] still pending criterion
EOF
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 1 ]
  [[ "$output" == *"still pending criterion"* ]]
  [[ "$output" == *'"verdict":"fail"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Independent-review fixes — the tests adapter must not swallow a
# broken reused runner; default checks must be scoped to the bank's
# project; an unexpected gate exit code is broke, not a clean fail.
# ═══════════════════════════════════════════════════════════════

# A clean git project bank: a [x] goal so every default check EXCEPT `tests`
# resolves to skip/pass (empty git diff, unknown stack, no scope). Isolates the
# tests adapter under test.
setup_clean_project() {
  local prj="$1"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  git -C "$prj" init -q
  git -C "$prj" -c user.email=t@t -c user.name=t add -A
  git -C "$prj" -c user.email=t@t -c user.name=t commit -q -m init
}

# A fake mb-test-run.sh: prints a fixed body and exits with a given code,
# ignoring its args. Usage: make_testrun_stub <exit> <json-body>
make_testrun_stub() {
  local code="$1" body="$2"
  local p="$BINDIR/fake-testrun.sh"
  cat > "$p" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$body'
exit $code
EOF
  chmod +x "$p"
  printf '%s' "$p"
}

@test "flow-verify: tests adapter — a crashing test runner is BROKE not a skip (exit 2)" {
  local prj="$TMPROOT/tr_crash" stub
  setup_clean_project "$prj"
  stub="$(make_testrun_stub 3 '{"tests_pass":null}')"
  export MB_TEST_RUN_BIN="$stub"
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tests"* ]]
}

@test "flow-verify: tests adapter — malformed runner JSON is BROKE not a skip (exit 2)" {
  local prj="$TMPROOT/tr_malf" stub
  setup_clean_project "$prj"
  stub="$(make_testrun_stub 0 'not json at all')"
  export MB_TEST_RUN_BIN="$stub"
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 2 ]
}

@test "flow-verify: tests adapter — runner JSON missing tests_pass is BROKE (exit 2)" {
  local prj="$TMPROOT/tr_miss" stub
  setup_clean_project "$prj"
  stub="$(make_testrun_stub 0 '{"stack":"python"}')"
  export MB_TEST_RUN_BIN="$stub"
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 2 ]
}

@test "flow-verify: tests adapter — a valid tests_pass:null is a clean SKIP (exit 0, not broke)" {
  local prj="$TMPROOT/tr_null" stub
  setup_clean_project "$prj"
  stub="$(make_testrun_stub 0 '{"stack":"unknown","tests_pass":null}')"
  export MB_TEST_RUN_BIN="$stub"
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

@test "flow-verify: default checks are scoped to the bank's project, not the caller cwd" {
  local prj="$TMPROOT/scoped"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  git -C "$prj" init -q
  printf 'value = 1\n' > "$prj/app.py"
  git -C "$prj" -c user.email=t@t -c user.name=t add -A
  git -C "$prj" -c user.email=t@t -c user.name=t commit -q -m init
  # Plant an unexempted TODO in a tracked file → it shows in `git diff`.
  printf 'value = 2  # TODO: real placeholder\n' >> "$prj/app.py"
  # Invoke from a FOREIGN cwd (a clean non-git temp dir). no_todo must STILL
  # catch the planted TODO because it is scoped to the bank's project root, not
  # this cwd. Pre-fix, no_todo ran in cwd → empty diff → skip → false exit 0.
  cd "$TMPROOT"
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TODO"* ]] || [[ "$output" == *"no_todo"* ]]
}

@test "flow-verify: a severity-gate that itself breaks (missing) is BROKE not a clean fail (exit 2)" {
  local g
  g="$(make_stub gg 0 "$(runner_json lint true)")"
  export MB_SEVERITY_GATE="$TMPROOT/no-such-gate.sh"
  # All checks green → counts zero → we REACH the gate; the gate binary is
  # missing → 127. That is neither 0 nor 1, so it must be broke (exit 2), never
  # collapse into the clean-fail (exit 1) branch.
  run bash "$VERIFY" "$TMPBANK" --check "lint=bash $g"
  [ "$status" -eq 2 ]
  [[ "$output" == *"gate"* ]] || [[ "$output" == *'"verdict":"broke"'* ]]
}

@test "flow-verify: a GLOBAL-storage bank scopes checks via .mb-config project_root, not the bank parent" {
  # Simulate global storage (mb-init-bank.sh --storage=global): the bank lives
  # away from the repo and records the real repo path as project_root in
  # .mb-config. The bank PARENT is NOT the project, so $MB_PATH/.. would mis-scope.
  local bank="$TMPROOT/global/projects/abc123/.memory-bank"
  local repo="$TMPROOT/realrepo"
  mkdir -p "$bank" "$repo"
  cp "$TMPBANK/pipeline.yaml" "$bank/pipeline.yaml"
  cat > "$bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  printf 'storage_mode=global\nproject_root=%s\n' "$repo" > "$bank/.mb-config"
  git -C "$repo" init -q
  printf 'value = 1\n' > "$repo/app.py"
  git -C "$repo" -c user.email=t@t -c user.name=t add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
  # Plant an unexempted TODO in a tracked file (shows in git diff).
  printf 'value = 2  # TODO: real placeholder\n' >> "$repo/app.py"
  # Invoke from a foreign cwd. no_todo must scope to $repo via .mb-config, NOT
  # the bank parent (which is a non-git dir → would skip → false exit 0).
  cd "$TMPROOT"
  run bash "$VERIFY" "$bank"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TODO"* ]] || [[ "$output" == *"no_todo"* ]]
}

@test "flow-verify: default checks survive an install path containing spaces (eval quoting)" {
  # Copy the whole scripts/ bundle under a path WITH A SPACE so SCRIPT_DIR has a
  # space, then run the copied firewall against a clean bank. The default check
  # command strings are eval'd; an unquoted $SCRIPT_DIR splits on the space → a
  # default check breaks → exit 2 on a clean bank. Properly quoted → exit 0.
  mkdir -p "$TMPROOT/with space"
  cp -R "$REPO_ROOT/scripts" "$TMPROOT/with space/scripts"
  local spaced="$TMPROOT/with space/scripts/mb-flow-verify.sh"
  local prj="$TMPROOT/clean_spaced"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  git -C "$prj" init -q
  git -C "$prj" -c user.email=t@t -c user.name=t add -A
  git -C "$prj" -c user.email=t@t -c user.name=t commit -q -m init
  run bash "$spaced" "$prj/.memory-bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

@test "flow-verify: a LOCAL bank with a .mb-config (no project_root) still emits a verdict, not a set-e abort" {
  local prj="$TMPROOT/local_cfg"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  # A real local bank (mb-init-bank.sh --storage=local) writes .mb-config with
  # only storage_mode/lang — NO project_root. The project_root grep must be
  # non-fatal under `set -euo pipefail`; otherwise the firewall aborts silently
  # (exit 1, empty stdout) instead of emitting a verdict.
  printf 'storage_mode=local\nlang=en\n' > "$prj/.memory-bank/.mb-config"
  git -C "$prj" init -q
  git -C "$prj" -c user.email=t@t -c user.name=t add -A
  git -C "$prj" -c user.email=t@t -c user.name=t commit -q -m init
  run bash "$VERIFY" "$prj/.memory-bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

@test "flow-verify: default checks survive install AND project paths with shell metacharacters (eval %q safety)" {
  # A path with a space AND a literal `$`: escaped double-quoting alone would let
  # the eval second-parse expand `$x` (→ wrong path → broke); only %q-escaping
  # keeps every interpolated path literal. Covers SCRIPT_DIR and PROJECT_ROOT.
  local base="$TMPROOT/we ird\$x"
  mkdir -p "$base"
  cp -R "$REPO_ROOT/scripts" "$base/scripts"
  local prj="$base/proj"
  mkdir -p "$prj/.memory-bank"
  cp "$TMPBANK/pipeline.yaml" "$prj/.memory-bank/pipeline.yaml"
  cat > "$prj/.memory-bank/goal.md" <<'EOF'
# Goal
Ship it.

## Acceptance criteria

- [x] all done
EOF
  git -C "$prj" init -q
  git -C "$prj" -c user.email=t@t -c user.name=t add -A
  git -C "$prj" -c user.email=t@t -c user.name=t commit -q -m init
  run bash "$base/scripts/mb-flow-verify.sh" "$prj/.memory-bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

# ═══════════════════════════════════════════════════════════════
# Firewall is its OWN exit authority — never inherits the work-loop's
# "review is opt-in → PASS no-op" semantics (mb-work-severity-gate.sh).
# ═══════════════════════════════════════════════════════════════

@test "flow-verify: a bank whose pipeline.yaml has NO review gate still fails a clean red (exit 1)" {
  # mb-work-severity-gate.sh returns a PASS no-op when the resolved pipeline.yaml
  # declares no review.severity_gate (review is opt-in). The firewall must NOT
  # inherit that: it is the SOLE closure authority, so a clean red (ok:false →
  # blocker) MUST still exit 1 regardless of whether a review policy exists.
  local nogate="$TMPROOT/nogate"
  mkdir -p "$nogate/.memory-bank"
  cat > "$nogate/.memory-bank/pipeline.yaml" <<'EOF'
# A valid pipeline.yaml with NO review.severity_gate anywhere.
workflow:
  default: simple
EOF
  local red
  red="$(make_stub acc 0 "$(runner_json acceptance false 'criterion X unmet')")"
  run bash "$VERIFY" "$nogate/.memory-bank" --check "acceptance=bash $red"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict":"fail"'* ]]
}

@test "flow-verify: all-green still exits 0 when the bank's default workflow requires reviewer approval" {
  # The firewall is a closure gate, NOT a code review: it sends raw counts with no
  # reviewer verdict. Forcing a strict --gate must NOT drag in the work-loop's
  # approval_required policy — otherwise an all-green run on a governed bank would
  # wrongly exit 1 (severity-gate: "approval_required=true but verdict=<missing>").
  local apv="$TMPROOT/approval"
  mkdir -p "$apv/.memory-bank"
  cat > "$apv/.memory-bank/pipeline.yaml" <<'EOF'
workflow:
  default: gov
workflows:
  gov:
    loop:
      approval_required: true
      severity_gate: {blocker: 0, major: 0, minor: 0}
EOF
  local green
  green="$(make_stub gt 0 "$(runner_json lint true)")"
  run bash "$VERIFY" "$apv/.memory-bank" --check "lint=bash $green"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict":"pass"'* ]]
}

@test "flow-verify: _shq makes a leading tilde eval-safe (bash 3.2 printf %q gap)" {
  # On /bin/bash 3.2 (macOS), printf '%q' '~/x' emits '~/x' UNESCAPED; eval would
  # then tilde-expand it to $HOME/x — the firewall could read the wrong bank. The
  # _shq helper must backslash-prefix a leading tilde so eval keeps it literal,
  # while leaving normal metacharacter-laden paths round-tripping intact. Extract
  # the helper and exercise the exact eval boundary the fan-out uses.
  local probe="$BINDIR/shq_probe.sh"
  {
    sed -n '/^_shq() {/,/^}/p' "$VERIFY"
    echo 'q="$(_shq "$1")"'
    echo "eval \"printf '%s' \$q\""
  } > "$probe"
  [ -s "$probe" ]
  # Run on /bin/bash specifically to pin the 3.2 %q-tilde behavior.
  run /bin/bash "$probe" '~/bank'
  [ "$status" -eq 0 ]
  [ "$output" = '~/bank' ]
  # A path with a space round-trips intact.
  run /bin/bash "$probe" '/a b/c'
  [ "$status" -eq 0 ]
  [ "$output" = '/a b/c' ]
  # A path with a literal $ is not expanded.
  run /bin/bash "$probe" '/x$HOME/y'
  [ "$status" -eq 0 ]
  [ "$output" = '/x$HOME/y' ]
}
