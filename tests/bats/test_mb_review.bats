#!/usr/bin/env bats
# Tests for scripts/mb-review.sh — the review-payload orchestrator entry point
# (reviewer-2.0 Task 1: REQ-100, REQ-102).
#
# This is a MINIMAL payload-shape smoke test. Full section-assembly behaviour
# (examples truncation, rotation, auto-finding post-validation) is covered by
# later reviewer-2.0 tasks' bats files (test_mb_review_payload_assembly.bats,
# test_mb_review_auto_finding_red.bats). Here we only assert:
#   - `--help` documents the contract
#   - `--emit-payload` never dispatches a reviewer / network / LLM call
#   - the 5 payload sections appear, in the fixed order from design.md §7
#   - `--input <case-dir>` drives the same code path deterministically
#     (needed later by the calibration suite, wired now)
#   - a value-taking flag given as the last arg with no value -> loud exit 2
#     (never a silent exit 1 -- see RULES.md usage-error contract)

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

section_order_ok() {
  # $1 = full payload text. Asserts all 5 headers appear in the fixed order.
  local text="$1"
  local l1 l2 l3 l4 l5
  l1=$(printf '%s\n' "$text" | grep -n '^## Plan context$' | head -1 | cut -d: -f1)
  l2=$(printf '%s\n' "$text" | grep -n '^## Diff$' | head -1 | cut -d: -f1)
  l3=$(printf '%s\n' "$text" | grep -n '^## Calibration examples (reference patterns — not part of current diff)$' | head -1 | cut -d: -f1)
  l4=$(printf '%s\n' "$text" | grep -n '^## Prior evidence (from mb-test-runner)$' | head -1 | cut -d: -f1)
  l5=$(printf '%s\n' "$text" | grep -n '^## Auto-generated findings (MUST INCLUDE)$' | head -1 | cut -d: -f1)
  [ -n "$l1" ] && [ -n "$l2" ] && [ -n "$l3" ] && [ -n "$l4" ] && [ -n "$l5" ] || return 1
  [ "$l1" -lt "$l2" ] && [ "$l2" -lt "$l3" ] && [ "$l3" -lt "$l4" ] && [ "$l4" -lt "$l5" ]
}

# $1 = full payload text. Returns (on stdout) everything from the
# "## Auto-generated findings (MUST INCLUDE)" header to EOF -- it is always
# the LAST rendered section, so this isolates the injected finding JSON from
# the "## Calibration examples" section, which legitimately contains its own
# reference "severity"/"category" JSON snippets and would otherwise make a
# bare substring match against the whole payload a tautology.
auto_findings_body() {
  printf '%s\n' "$1" | sed -n '/^## Auto-generated findings (MUST INCLUDE)$/,$p'
}

@test "mb-review.sh: script exists" {
  [ -f "$RUN" ]
}

@test "--help exits 0 and documents --emit-payload, --input, --mb" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--emit-payload"* ]]
  [[ "$output" == *"--input"* ]]
  [[ "$output" == *"--mb"* ]]
}

@test "no --emit-payload and no --help -> usage error, exit 2, no crash" {
  run bash "$RUN" --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "--emit-payload --input <case-dir>: red-test case shows all 5 sections in fixed order" {
  CASE="$BATS_TEST_TMPDIR/case-red"
  mkdir -p "$CASE"
  cat >"$CASE/case.json" <<'JSON'
{"case_id": "SMOKE-001-red", "description": "smoke case with a failing test"}
JSON
  printf 'src/app.py\n' >"$CASE/files-touched.txt"
  cat >"$CASE/diff.patch" <<'DIFF'
diff --git a/src/app.py b/src/app.py
index 111..222 100644
--- a/src/app.py
+++ b/src/app.py
@@ -1 +1 @@
-old
+new
DIFF
  cat >"$CASE/prior-tests.json" <<'JSON'
{"schema_version": 1, "run_id": "2026-01-01T00:00:00Z-abcdef", "stack_detected": "python", "touched_files_sha": "sha256:irrelevant-in-input-mode", "tests_pass": false, "counts": {"passed": 2, "failed": 1, "skipped": 0}, "coverage": {}, "failures": ["test_app_returns_ok"], "elapsed_sec": 1.2}
JSON

  run bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK"
  [ "$status" -eq 0 ]
  section_order_ok "$output"
  [[ "$output" == *"SMOKE-001-red"* ]]
  [[ "$output" == *"new"* ]]
  [[ "$output" == *"test_app_returns_ok"* ]]
  # REQ-103 injection: red evidence must force a blocker "tests" finding
  # ahead of the LLM reviewer -- not just any auto-generated section, and
  # not a match against the "## Calibration examples" section, which also
  # legitimately contains reference "severity": "blocker" JSON snippets.
  [[ "$output" == *"## Auto-generated findings (MUST INCLUDE)"* ]]
  local findings_body
  findings_body="$(auto_findings_body "$output")"
  [[ "$findings_body" == *'"severity": "blocker"'* ]]
  [[ "$findings_body" == *'"category": "tests"'* ]]
  [[ "$findings_body" == *'"auto_generated": true'* ]]
}

@test "--emit-payload --input <case-dir>: green-test case omits the auto-findings section" {
  CASE="$BATS_TEST_TMPDIR/case-green"
  mkdir -p "$CASE"
  cat >"$CASE/case.json" <<'JSON'
{"case_id": "SMOKE-002-green", "description": "smoke case, all tests passing"}
JSON
  printf 'src/app.py\n' >"$CASE/files-touched.txt"
  printf 'diff --git a/src/app.py b/src/app.py\n' >"$CASE/diff.patch"
  cat >"$CASE/prior-tests.json" <<'JSON'
{"schema_version": 1, "run_id": "2026-01-01T00:00:00Z-abcdef", "stack_detected": "python", "touched_files_sha": "sha256:irrelevant", "tests_pass": true, "counts": {"passed": 3, "failed": 0, "skipped": 0}, "coverage": {}, "failures": [], "elapsed_sec": 0.5}
JSON

  run bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Plan context"* ]]
  [[ "$output" == *"## Diff"* ]]
  [[ "$output" == *"## Calibration examples"* ]]
  [[ "$output" == *"## Prior evidence"* ]]
  [[ "$output" != *"## Auto-generated findings"* ]]
}

@test "--emit-payload --input <case-dir>: never touches network/LLM (pure stdout, deterministic across runs)" {
  CASE="$BATS_TEST_TMPDIR/case-det"
  mkdir -p "$CASE"
  printf 'src/app.py\n' >"$CASE/files-touched.txt"
  printf 'diff\n' >"$CASE/diff.patch"

  run bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK"
  first="$output"
  run bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK"
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "--emit-payload --input <case-dir>: missing prior-tests.json degrades gracefully (no crash)" {
  CASE="$BATS_TEST_TMPDIR/case-no-prior"
  mkdir -p "$CASE"
  printf 'src/app.py\n' >"$CASE/files-touched.txt"
  printf 'diff\n' >"$CASE/diff.patch"

  run bash "$RUN" --emit-payload --input "$CASE" --mb "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Prior evidence"* ]]
}

@test "--emit-payload real path (no --input): degrades gracefully outside a git repo" {
  NOGIT="$BATS_TEST_TMPDIR/no-git-cwd"
  mkdir -p "$NOGIT"
  run bash -c "cd '$NOGIT' && bash '$RUN' --emit-payload --mb '$BANK'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"## Plan context"* ]]
  [[ "$output" == *"## Diff"* ]]
  [[ "$output" == *"## Calibration examples"* ]]
  [[ "$output" == *"## Prior evidence"* ]]
}

@test "value flag as the last arg with no value -> exit 2 with a non-empty stderr message (never a silent exit 1)" {
  run --separate-stderr bash "$RUN" --emit-payload --input
  [ "$status" -eq 2 ]
  [ -n "$stderr" ]
}

@test "--emit-payload real path: touched-file diff reflects an actual git repo's uncommitted change" {
  command -v git >/dev/null || skip "git required"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  printf 'line1\n' >"$REPO/file.txt"
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm init
  printf 'line1\nline2\n' >"$REPO/file.txt"

  run bash -c "cd '$REPO' && bash '$RUN' --emit-payload --mb '$BANK'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line2"* ]]
}
