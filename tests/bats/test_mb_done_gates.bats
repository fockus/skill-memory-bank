#!/usr/bin/env bats
# Stage 3 (handoff-v2 §5) — scripts/mb-done-gates.sh mandatory /mb done gate set.
#
# The gate runner executes three independent checks in sequence, each emitting a
# structured JSON line to stdout:
#   1. tests           — dispatch the test runner; capture tests_pass.
#                        not_applicable (no stack) counts as PASS with a WARN.
#   2. rules           — scripts/mb-rules-check.sh on the working tree; CRITICAL = fail.
#   3. placeholders    — scripts/mb-rules-check.sh --placeholders-only; any hit = fail.
#
# Only REQUIRED gates (from done_gates.required config) affect exit code + force
# summary. All gate JSON lines are always emitted.
#
# Exit 0 only if all REQUIRED gates pass; otherwise exit 2. --force requires
# --reason "<one-line>" (no CR/LF); a forced run with failures appends a NOTE to
# progress.md and stores the failure JSON under tmp/, then exits 0.
#
# Stubs: MB_TEST_RUNNER_CMD / MB_RULES_CHECK_CMD keep the suite deterministic.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-done-gates.sh"

  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB"
  STUBS="$TMP/stubs"
  mkdir -p "$STUBS"

  printf '# Progress\n' > "$MB/progress.md"

  TODAY="$(date +%Y-%m-%d)"
}

teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

# ── stub builders ────────────────────────────────────────────────────────────

# A test-runner stub that prints a JSON line with a chosen tests_pass value.
# $1 = true | false | null  ; $2 (optional) = extra JSON key e.g. not_applicable=true
_make_test_runner_stub() {
  local verdict="$1"
  local extra="${2:-}"
  cat > "$STUBS/test-runner.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '{"stack":"python","tests_pass":${verdict}${extra:+,$extra}}\n'
EOF
  chmod +x "$STUBS/test-runner.sh"
}

# A rules-check stub. Modes:
#   clean        — exit 0, no violations.
#   critical     — emit a CRITICAL violation, exit 1.
#   tdd_critical — emit a CRITICAL tdd/delta violation when --diff-files is
#                  passed (used to prove MAJOR #3 fix); exit 0 when no diff.
#   ph_clean     — for --placeholders-only: exit 0.
#   ph_hit       — for --placeholders-only: exit 1 with a hit.
_make_rules_stub() {
  local mode="$1"
  cat > "$STUBS/rules-check.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mode="$mode"
placeholders=0
has_diff=0
for a in "\$@"; do
  [ "\$a" = "--placeholders-only" ] && placeholders=1
  [[ "\$a" == --diff-files* ]] && has_diff=1
done

if [ "\$placeholders" -eq 1 ]; then
  case "\$mode" in
    ph_hit)
      printf '{"violations":[{"rule":"no-placeholders","severity":"CRITICAL","file":"x.sh"}]}\n'
      exit 1 ;;
    *)
      printf '{"violations":[]}\n'
      exit 0 ;;
  esac
fi

case "\$mode" in
  critical)
    printf '{"violations":[{"rule":"solid/srp","severity":"CRITICAL","file":"x.sh"}]}\n'
    exit 1 ;;
  tdd_critical)
    if [ "\$has_diff" -eq 1 ]; then
      printf '{"violations":[{"rule":"tdd/delta","severity":"CRITICAL","file":"x.sh"}]}\n'
      exit 1
    fi
    printf '{"violations":[]}\n'
    exit 0 ;;
  *)
    printf '{"violations":[]}\n'
    exit 0 ;;
esac
EOF
  chmod +x "$STUBS/rules-check.sh"
}

# Run the gate runner with stubs wired in. Extra args pass through.
run_gates() {
  run env \
    MB_TEST_RUNNER_CMD="bash $STUBS/test-runner.sh" \
    MB_RULES_CHECK_CMD="bash $STUBS/rules-check.sh" \
    bash "$SCRIPT" --mb "$MB" "$@"
}

# ═══════════════════════════════════════════════════════════════
# Happy path
# ═══════════════════════════════════════════════════════════════

@test "done-gates: all gates pass → exit 0" {
  _make_test_runner_stub true
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 0 ]
}

@test "done-gates: passing run emits one JSON line per gate" {
  _make_test_runner_stub true
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"gate":"tests"'
  echo "$output" | grep -q '"gate":"rules"'
  echo "$output" | grep -q '"gate":"placeholders"'
}

@test "done-gates: clean placeholders gate → passes with pass:true" {
  _make_test_runner_stub true
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"gate":"placeholders".*"pass":true'
}

# ═══════════════════════════════════════════════════════════════
# Failure without --force — exact exit 2
# ═══════════════════════════════════════════════════════════════

@test "done-gates: failing tests gate WITHOUT --force → EXACT exit 2" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 2 ]
}

@test "done-gates: CRITICAL rules violation WITHOUT --force → EXACT exit 2" {
  _make_test_runner_stub true
  _make_rules_stub critical
  run_gates
  [ "$status" -eq 2 ]
}

@test "done-gates: placeholder hit WITHOUT --force → EXACT exit 2" {
  _make_test_runner_stub true
  _make_rules_stub ph_hit
  run_gates
  [ "$status" -eq 2 ]
}

@test "done-gates: failure without force does NOT mutate progress.md" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 2 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: non-forced failure does NOT write a tmp/ failure JSON" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 2 ]
  run bash -c "ls '$MB/tmp/done-gate-failure-'*.json 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #1 — required list is honoured
# Non-required gate failures do NOT trigger exit 2
# ═══════════════════════════════════════════════════════════════

@test "done-gates: #1 non-required placeholders gate fails → exit 0 (only rules required)" {
  _make_test_runner_stub true
  _make_rules_stub ph_hit
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [no_critical_violations]
  allow_force: true
EOF
  run_gates
  # placeholders fails but is NOT in required → overall exit 0
  [ "$status" -eq 0 ]
}

@test "done-gates: #1 all three JSON lines still emitted even when gate not required" {
  _make_test_runner_stub true
  _make_rules_stub ph_hit
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [no_critical_violations]
  allow_force: true
EOF
  run_gates
  echo "$output" | grep -q '"gate":"tests"'
  echo "$output" | grep -q '"gate":"rules"'
  echo "$output" | grep -q '"gate":"placeholders"'
}

@test "done-gates: #1 non-required tests gate fails → exit 0 (only no_placeholders required)" {
  _make_test_runner_stub false
  _make_rules_stub clean
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [no_placeholders]
  allow_force: true
EOF
  run_gates
  [ "$status" -eq 0 ]
}

@test "done-gates: #1 required gate fails → still exit 2 (non-required passing irrelevant)" {
  _make_test_runner_stub true
  _make_rules_stub critical
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [no_critical_violations]
  allow_force: true
EOF
  run_gates
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #2 — fail-closed: unparseable project pipeline.yaml
# ═══════════════════════════════════════════════════════════════

@test "done-gates: #2 unparseable project pipeline.yaml → --force rejected (fail closed)" {
  _make_test_runner_stub false
  _make_rules_stub clean
  # Write invalid YAML so the parser fails
  printf 'done_gates:\n  allow_force: !!binary |\n  : not valid yaml at all\n{{{bad}}}' \
    > "$MB/pipeline.yaml"
  run_gates --force --reason "sneaky bypass"
  [ "$status" -ne 0 ]
}

@test "done-gates: #2 unparseable project pipeline.yaml → no progress.md mutation" {
  _make_test_runner_stub false
  _make_rules_stub clean
  printf 'done_gates:\n  allow_force: !!binary |\n  : not valid yaml at all\n{{{bad}}}' \
    > "$MB/pipeline.yaml"
  run_gates --force --reason "sneaky bypass"
  [ "$status" -ne 0 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: #2 no project pipeline.yaml (default) → allow_force=true (open)" {
  # No project pipeline.yaml → default applies → force allowed
  _make_test_runner_stub false
  _make_rules_stub clean
  [ ! -f "$MB/pipeline.yaml" ]
  run_gates --force --reason "default allows force"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #3 — --diff-files passed to mb-rules-check.sh
# tdd/delta check keys off DIFF_FILES — without it the check never fires
# ═══════════════════════════════════════════════════════════════

@test "done-gates: #3 --diff-files forwarded → tdd/delta CRITICAL triggers rules gate fail" {
  _make_test_runner_stub true
  # tdd_critical mode: only fails when --diff-files is present
  _make_rules_stub tdd_critical
  run_gates
  [ "$status" -eq 2 ]
}

@test "done-gates: #3 rules gate JSON line still emitted on tdd/delta fail" {
  _make_test_runner_stub true
  _make_rules_stub tdd_critical
  run_gates
  echo "$output" | grep -q '"gate":"rules"'
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #4 — placeholder scan self-exemption
# tests/ paths and the deny-list definition line (pragma) must NOT self-trip
# ═══════════════════════════════════════════════════════════════

@test "done-gates: #4 .bats test fixture with TODO marker is exempt from placeholder scan" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/tests/test_fixture.bats"
  mkdir -p "$TMP/tests"
  printf '#!/usr/bin/env bats\n# TODO: add more cases\n@test "x" { true; }\n' > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -eq 0 ]
}

@test "done-gates: #4 tests/ path with FIXME is exempt" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/tests/helpers.sh"
  mkdir -p "$TMP/tests"
  printf '#!/usr/bin/env bash\n# FIXME: stub\n' > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -eq 0 ]
}

@test "done-gates: #4 lib line with pragma (allow-placeholder) is exempt" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/src/lib.sh"
  mkdir -p "$TMP/src"
  printf "#!/usr/bin/env bash\nDENY_DEFAULT='TODO,FIXME' # mb-rules-check: allow-placeholder\necho ok\n" > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -eq 0 ]
}

@test "done-gates: #4 real .sh source with TODO (no pragma, not in tests/) STILL fails" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/src/real.sh"
  mkdir -p "$TMP/src"
  printf '#!/usr/bin/env bash\n# TODO: implement me\n' > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -ne 0 ]
}

@test "done-gates: #4 rules-check lib itself does NOT self-trip (deny-list definition line has pragma)" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local lib="$REPO_ROOT/scripts/mb_rules_check_lib.sh"
  run bash "$rc" --placeholders-only --files "$lib"
  [ "$status" -eq 0 ]
}

@test "done-gates: #4 done-gates.sh itself does NOT self-trip (usage-comment exempt by tests/pragma or comment)" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local gsh="$REPO_ROOT/scripts/mb-done-gates.sh"
  run bash "$rc" --placeholders-only --files "$gsh"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Force semantics (with exit-exact assertions)
# ═══════════════════════════════════════════════════════════════

@test "done-gates: failing gates WITH --force --reason → EXACT exit 0" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason "shipping a hotfix"
  [ "$status" -eq 0 ]
}

@test "done-gates: forced run appends NOTE line under today's heading in progress.md" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason "shipping a hotfix"
  [ "$status" -eq 0 ]
  run grep -F "## $TODAY" "$MB/progress.md"
  [ "$status" -eq 0 ]
  run grep -F "### NOTE: /mb done --force — gates failed" "$MB/progress.md"
  [ "$status" -eq 0 ]
  run grep -F "shipping a hotfix" "$MB/progress.md"
  [ "$status" -eq 0 ]
}

@test "done-gates: forced run writes failure-detail JSON under tmp/" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason "shipping a hotfix"
  [ "$status" -eq 0 ]
  run bash -c "ls '$MB/tmp/done-gate-failure-'*.json"
  [ "$status" -eq 0 ]
}

@test "done-gates: forced run with valid gates does NOT append a NOTE" {
  _make_test_runner_stub true
  _make_rules_stub clean
  run_gates --force --reason "no failures here"
  [ "$status" -eq 0 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: --force WITHOUT --reason → EXACT exit 2" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force
  [ "$status" -eq 2 ]
}

@test "done-gates: --force without --reason does NOT mutate progress.md" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force
  [ "$status" -eq 2 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: --force with empty --reason → EXACT exit 2" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason ""
  [ "$status" -eq 2 ]
}

@test "done-gates: --reason as final arg with no value → EXACT exit 2" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason
  [ "$status" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# MAJOR #6 — newline injection in --reason rejected
# ═══════════════════════════════════════════════════════════════

@test "done-gates: #6 --reason with embedded newline → EXACT exit 2, no progress.md mutation" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason $'safe prefix\n## fake heading'
  [ "$status" -eq 2 ]
  run grep -c "fake heading" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: #6 --reason with embedded CR → EXACT exit 2, no progress.md mutation" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason $'line1\rline2'
  [ "$status" -eq 2 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: #6 newline-reason does NOT write a failure JSON file" {
  _make_test_runner_stub false
  _make_rules_stub clean
  run_gates --force --reason $'good\n## injected'
  [ "$status" -eq 2 ]
  run bash -c "ls '$MB/tmp/done-gate-failure-'*.json 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# allow_force: false
# ═══════════════════════════════════════════════════════════════

@test "done-gates: allow_force=false in config → --force EXACT exit 2" {
  _make_test_runner_stub false
  _make_rules_stub clean
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [tests_pass, no_critical_violations, no_placeholders]
  allow_force: false
EOF
  run_gates --force --reason "trying to force"
  [ "$status" -eq 2 ]
  run grep -c "gates failed" "$MB/progress.md"
  [ "$output" -eq 0 ]
}

@test "done-gates: allow_force=true explicit in config → --force honored" {
  _make_test_runner_stub false
  _make_rules_stub clean
  cat > "$MB/pipeline.yaml" <<'EOF'
done_gates:
  enabled: true
  required: [tests_pass, no_critical_violations, no_placeholders]
  allow_force: true
EOF
  run_gates --force --reason "explicit allow"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# not_applicable tests gate (no stack)
# ═══════════════════════════════════════════════════════════════

@test "done-gates: tests gate not_applicable (no stack) → treated as PASS" {
  _make_test_runner_stub null '"not_applicable":true'
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 0 ]
}

@test "done-gates: not_applicable tests gate logs a WARN" {
  _make_test_runner_stub null '"not_applicable":true'
  _make_rules_stub clean
  run_gates
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "warn"
}

# ═══════════════════════════════════════════════════════════════
# Placeholder deny-list — real invocations (no stubs)
# ═══════════════════════════════════════════════════════════════

@test "done-gates: real --placeholders-only flag scans for TODO and fails" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/dirty.sh"
  printf '#!/usr/bin/env bash\n# TODO: finish this\n' > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -ne 0 ]
}

@test "done-gates: real --placeholders-only flag passes on clean source" {
  local rc="$REPO_ROOT/scripts/mb-rules-check.sh"
  local f="$TMP/clean.sh"
  printf '#!/usr/bin/env bash\necho hello\n' > "$f"
  run bash "$rc" --placeholders-only --files "$f"
  [ "$status" -eq 0 ]
}
