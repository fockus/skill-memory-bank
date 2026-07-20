#!/usr/bin/env bats
# estimate_spec: — svp-sdd-core C3 spec-triple / candidate budget gate
# (`--spec` / `--tasks-file` modes of scripts/mb-estimate-check.sh, REQ-009).
#
# Name convention: every @test starts with `estimate_spec: ` and the
# `--tasks-file` cases carry the token `tasks_file` (Eval red-anchor
# `not ok [0-9]+ .*tasks_file`).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-estimate-check.sh"
  export LC_ALL=C
}

# _task <file> <id> <stage> <budget|->  — append one task block ('-' = no Budget).
_task() {
  local f="$1" id="$2" st="$3" b="$4"
  {
    printf '<!-- mb-task:%s -->\n' "$id"
    printf '## Task %s\n' "$id"
    printf '**Stage:** %s\n' "$st"
    [ "$b" = "-" ] || printf '**Budget:** %s\n' "$b"
    printf '<!-- /mb-task:%s -->\n' "$id"
  } >> "$f"
}

# _fm <file> <total> <stage-id:sum>...  — write estimated_tokens frontmatter.
_fm() {
  local f="$1" total="$2"; shift 2
  { printf -- '---\n'; printf 'estimated_tokens:\n'; printf '  total: %s\n' "$total"; printf '  stages:\n'
    local kv; for kv in "$@"; do printf '    "%s": %s\n' "${kv%%:*}" "${kv##*:}"; done
    printf -- '---\n'; } > "$f"
}

# ---- --tasks-file (candidate) mode ---------------------------------------

@test "estimate_spec: tasks_file candidate ok → spec=ok exit 0" {
  local f="$BATS_TEST_TMPDIR/t.md"
  _fm "$f" 300000 "1:180000" "2:120000"
  _task "$f" 1 1 90000; _task "$f" 2 1 90000; _task "$f" 3 2 120000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec=ok"* ]]
  [[ "$output" == *"task.1=90000"* ]]
  [[ "$output" == *"stage.1=180000"* ]]
  [[ "$output" == *"stage.2=120000"* ]]
  [[ "$output" == *"spec.total=300000"* ]]
  [[ "$output" == *"task_over=none"* ]]
  [[ "$output" == *"stage_over=none"* ]]
  [[ "$output" == *"legacy_missing=none"* ]]
}

@test "estimate_spec: tasks_file near band 900k–1M → spec=near exit 0" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 950000 "1:380000" "2:380000" "3:190000"
  _task "$f" 1 1 120000; _task "$f" 2 1 120000; _task "$f" 3 1 60000; _task "$f" 4 1 80000
  _task "$f" 5 2 120000; _task "$f" 6 2 120000; _task "$f" 7 2 60000; _task "$f" 8 2 80000
  _task "$f" 9 3 120000; _task "$f" 10 3 70000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec=near"* ]]
}

@test "estimate_spec: tasks_file candidate over 1M → spec=over exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; local total=0 i
  { printf -- '---\nestimated_tokens:\n  total: 1080000\n  stages:\n    "1": 360000\n    "2": 360000\n    "3": 360000\n---\n'; } > "$f"
  for i in 1 2 3;   do _task "$f" "$i" 1 120000; done
  for i in 4 5 6;   do _task "$f" "$i" 2 120000; done
  for i in 7 8 9;   do _task "$f" "$i" 3 120000; done
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec=over"* ]]
}

@test "estimate_spec: tasks_file task over 120k → task_over set, exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 250000 "1:250000"
  _task "$f" 1 1 130000; _task "$f" 2 1 120000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task_over=1"* ]]
}

@test "estimate_spec: tasks_file stage over 400k → stage_over set, exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 440000 "1:440000"
  _task "$f" 1 1 120000; _task "$f" 2 1 120000; _task "$f" 3 1 120000; _task "$f" 4 1 80000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stage_over=1"* ]]
}

@test "estimate_spec: tasks_file legacy task without Budget → legacy_missing + one warning" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 100000 "1:100000"
  _task "$f" 1 1 100000; _task "$f" 2 1 -
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy_missing=2"* ]]
  [[ "$output" != *"task.2="* ]]
  [ "$(printf '%s\n' "$stderr" | grep -c legacy_missing)" -eq 1 ]
}

@test "estimate_spec: tasks_file malformed Budget → exit 2, no key=value stdout" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf '<!-- mb-task:1 -->\n**Stage:** 1\n**Budget:** 100k\n<!-- /mb-task:1 -->\n' > "$f"
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 2 ]
  [[ "$output" != *"spec="* ]]
  [[ "$stderr" == *":malformed"* ]]
}

@test "estimate_spec: tasks_file frontmatter total mismatch → exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 999999 "1:100000"
  _task "$f" 1 1 100000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
}

@test "estimate_spec: tasks_file frontmatter stage mismatch → exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 200000 "1:999999" "2:100000"
  _task "$f" 1 1 100000; _task "$f" 2 2 100000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
}

@test "estimate_spec: tasks_file missing candidate → exit 2" {
  run --separate-stderr "$SCRIPT" --tasks-file "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
}

# ---- --spec (accepted) mode ----------------------------------------------

@test "estimate_spec: --spec resolves <bank>/specs/<topic>/tasks.md" {
  mkdir -p "$BATS_TEST_TMPDIR/bank/specs/demo"
  local f="$BATS_TEST_TMPDIR/bank/specs/demo/tasks.md"; _fm "$f" 100000 "1:100000"
  _task "$f" 1 1 100000
  run --separate-stderr "$SCRIPT" --spec demo --mb "$BATS_TEST_TMPDIR/bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec.total=100000"* ]]
}

@test "estimate_spec: --spec explicit spec-dir takes priority" {
  mkdir -p "$BATS_TEST_TMPDIR/dir"
  local f="$BATS_TEST_TMPDIR/dir/tasks.md"; _fm "$f" 90000 "1:90000"
  _task "$f" 1 1 90000
  run --separate-stderr "$SCRIPT" --spec "$BATS_TEST_TMPDIR/dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec=ok"* ]]
}

@test "estimate_spec: --spec unresolvable topic → exit 2" {
  run --separate-stderr "$SCRIPT" --spec no-such-topic --mb "$BATS_TEST_TMPDIR/bank"
  [ "$status" -eq 2 ]
}

# ---- stale final ignored (F-007) -----------------------------------------

@test "estimate_spec: stale final ignored — tasks_file reads exactly the passed file" {
  mkdir -p "$BATS_TEST_TMPDIR/bank/specs/demo"
  # Accepted (final) file is tiny.
  local fin="$BATS_TEST_TMPDIR/bank/specs/demo/tasks.md"; _fm "$fin" 10000 "1:10000"
  _task "$fin" 1 1 10000
  # Candidate (separate path) is huge.
  local cand="$BATS_TEST_TMPDIR/cand.md"
  { printf -- '---\nestimated_tokens:\n  total: 1080000\n  stages:\n    "1": 360000\n    "2": 360000\n    "3": 360000\n---\n'; } > "$cand"
  local i; for i in 1 2 3; do _task "$cand" "$i" 1 120000; done
  for i in 4 5 6; do _task "$cand" "$i" 2 120000; done
  for i in 7 8 9; do _task "$cand" "$i" 3 120000; done
  run --separate-stderr "$SCRIPT" --tasks-file "$cand"
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec=over"* ]]
  # And the accepted file is small → ok, proving the two are read independently.
  run --separate-stderr "$SCRIPT" --spec demo --mb "$BATS_TEST_TMPDIR/bank"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec=ok"* ]]
}

@test "estimate_spec: reverse stale — tiny candidate over big stale final" {
  mkdir -p "$BATS_TEST_TMPDIR/bank/specs/demo"
  local fin="$BATS_TEST_TMPDIR/bank/specs/demo/tasks.md"
  { printf -- '---\nestimated_tokens:\n  total: 1080000\n  stages:\n    "1": 1080000\n---\n'; } > "$fin"
  local i; for i in 1 2 3 4 5 6 7 8 9; do _task "$fin" "$i" 1 120000; done
  local cand="$BATS_TEST_TMPDIR/cand.md"; _fm "$cand" 50000 "1:50000"
  _task "$cand" 1 1 50000
  run --separate-stderr "$SCRIPT" --tasks-file "$cand"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec=ok"* ]]
}

# ---- mutual exclusion ----------------------------------------------------

@test "estimate_spec: tasks_file + --spec together → usage exit 2" {
  run --separate-stderr "$SCRIPT" --spec demo --tasks-file "$BATS_TEST_TMPDIR/x.md"
  [ "$status" -eq 2 ]
}

@test "estimate_spec: positional context + tasks_file together → usage exit 2" {
  local c="$BATS_TEST_TMPDIR/ctx.md"; printf '# ctx\n' > "$c"
  run --separate-stderr "$SCRIPT" "$c" --tasks-file "$BATS_TEST_TMPDIR/x.md"
  [ "$status" -eq 2 ]
}

# ---- S1 context-mode regression (byte-identical) -------------------------

@test "estimate_spec: positional context-file mode unchanged (S1 regression)" {
  local c="$BATS_TEST_TMPDIR/ctx.md"
  cat > "$c" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 850000
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 850000, subtotal: 850000}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$c"
  [ "$status" -eq 0 ]
  [ "$output" = "estimate=ok spec.total=850000 spec_budget=1000000" ]
}

# ---- Stage 0 is a real stage, subject to the cap (cycle-2 blocker) --------

@test "estimate_spec: tasks_file four Stage 0 tasks over 400k → stage.0 + stage_over, exit 1" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 480000 "0:480000"
  _task "$f" 1 0 120000; _task "$f" 2 0 120000; _task "$f" 3 0 120000; _task "$f" 4 0 120000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stage.0=480000"* ]]
  [[ "$output" == *"stage_over=0"* ]]
}

@test "estimate_spec: tasks_file Stage 0 within cap emits stage.0 and stays ok" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 200000 "0:200000"
  _task "$f" 1 0 100000; _task "$f" 2 0 100000
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stage.0=200000"* ]]
  [[ "$output" == *"stage_over=none"* ]]
}

# ---- strict frontmatter integers (cycle-2 major) -------------------------

@test "estimate_spec: tasks_file frontmatter total 100junk → malformed exit 2" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf -- '---\nestimated_tokens:\n  total: 100junk\n  stages:\n    "1": 100\n---\n' > "$f"
  _task "$f" 1 1 100
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *":malformed"* ]]
}

@test "estimate_spec: tasks_file frontmatter stage 100junk → malformed exit 2" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf -- '---\nestimated_tokens:\n  total: 100\n  stages:\n    "1": 100junk\n---\n' > "$f"
  _task "$f" 1 1 100
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *":malformed"* ]]
}

@test "estimate_spec: tasks_file negative frontmatter total → malformed exit 2" {
  local f="$BATS_TEST_TMPDIR/t.md"
  printf -- '---\nestimated_tokens:\n  total: -5\n  stages:\n    "1": 100\n---\n' > "$f"
  _task "$f" 1 1 100
  run --separate-stderr "$SCRIPT" --tasks-file "$f"
  [ "$status" -eq 2 ]
}

# ---- per-mode flag rejection (cycle-2 major) -----------------------------

@test "estimate_spec: --spec-budget is rejected in spec/candidate mode (usage exit 2)" {
  local f="$BATS_TEST_TMPDIR/t.md"; _fm "$f" 100000 "1:100000"
  _task "$f" 1 1 100000
  run --separate-stderr "$SCRIPT" --tasks-file "$f" --spec-budget 500000
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
}

@test "estimate_spec: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run shellcheck -x -S error "$REPO_ROOT/scripts/mb-estimate-lib.sh"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ─── r4 [13]: task/stage IDs stay exact above 2^53 ─────────────────────────

@test "estimate_check_spec: task IDs above 2^53 do not collapse into one" {
  # awk coerces via double, so 9007199254740992 and ...93 became the SAME id:
  # the pair printed one id twice and stage/spec totals doubled one budget
  # (400 instead of 300). The 999999999 fixture was below the precision cliff.
  local d="$BATS_TEST_TMPDIR/s13"; mkdir -p "$d"
  printf '# Tasks\n\n<!-- mb-task:9007199254740992 -->\n### A\n**Budget:** 100\n**Stage:** 1\n<!-- /mb-task:9007199254740992 -->\n\n<!-- mb-task:9007199254740993 -->\n### B\n**Budget:** 200\n**Stage:** 1\n<!-- /mb-task:9007199254740993 -->\n' > "$d/tasks.md"
  run --separate-stderr "$SCRIPT" --tasks-file "$d/tasks.md"
  echo "$output" | grep -q 'task.9007199254740992=100' \
    || { echo "first id lost or wrong: $output"; false; }
  echo "$output" | grep -q 'task.9007199254740993=200' \
    || { echo "second id collapsed into the first: $output"; false; }
  echo "$output" | grep -q 'spec.total=300' \
    || { echo "totals wrong (a budget was double-counted): $output"; false; }
  echo "$output" | grep -q 'stage.1=300' \
    || { echo "stage sum wrong: $output"; false; }
}

@test "estimate_check_spec: stage IDs above 2^53 stay distinct" {
  local d="$BATS_TEST_TMPDIR/s13b"; mkdir -p "$d"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n### A\n**Budget:** 100\n**Stage:** 9007199254740992\n<!-- /mb-task:1 -->\n\n<!-- mb-task:2 -->\n### B\n**Budget:** 200\n**Stage:** 9007199254740993\n<!-- /mb-task:2 -->\n' > "$d/tasks.md"
  run --separate-stderr "$SCRIPT" --tasks-file "$d/tasks.md"
  echo "$output" | grep -q 'stage.9007199254740992=100' || { echo "stage 1 wrong: $output"; false; }
  echo "$output" | grep -q 'stage.9007199254740993=200' || { echo "stage 2 collapsed: $output"; false; }
}

@test "estimate_check_spec: ordinary small IDs still sort ascending" {
  local d="$BATS_TEST_TMPDIR/s13c"; mkdir -p "$d"
  printf '# Tasks\n\n<!-- mb-task:10 -->\n### A\n**Budget:** 10\n**Stage:** 1\n<!-- /mb-task:10 -->\n\n<!-- mb-task:2 -->\n### B\n**Budget:** 20\n**Stage:** 1\n<!-- /mb-task:2 -->\n' > "$d/tasks.md"
  run --separate-stderr "$SCRIPT" --tasks-file "$d/tasks.md"
  # numeric order, not lexicographic: task.2 must precede task.10
  local order; order="$(printf '%s\n' "$output" | grep -oE '^task\.[0-9]+' | tr '\n' ' ')"
  [ "$order" = "task.2 task.10 " ] || { echo "wrong id order: $order"; false; }
}
