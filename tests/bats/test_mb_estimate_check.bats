#!/usr/bin/env bats
# estimate_check: — svp-interview-upgrade C1 size-estimate validator +
# the `#### Size triage` prompt contract (Task 3).
#
# Name convention: every @test starts with `estimate_check: ` (Eval red-anchor
# `not ok [0-9]+ estimate_check: `).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-estimate-check.sh"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("triage-cat-shell_scripts|mb_section|Size triage|shell_scripts.*15 000|shell_scripts|s/15 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-cat-prompt_changes|mb_section|Size triage|prompt_changes.*8 000|prompt_changes|s/8 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-cat-python_modules|mb_section|Size triage|python_modules.*25 000|python_modules|s/25 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-cat-test_files|mb_section|Size triage|test_files.*10 000|test_files|s/10 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-cat-docs_pages|mb_section|Size triage|docs_pages.*5 000|docs_pages|s/5 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-cat-external_integrations|mb_section|Size triage|external_integrations.*30 000|external_integrations|s/30 000/99 999/|REQ-008")
  MB_DISCUSS_CLAUSES+=("triage-child-interview|mb_section|Size triage|each accepted child receives its own.*interview|accepted child|s/receives its own follow-up interview/is deferred/|REQ-009")
  MB_DISCUSS_CLAUSES+=("triage-decline|mb_section|Size triage|user may decline the recommendation|recommendation|s/the user may decline the recommendation/the recommendation is mandatory/|REQ-009")
  MB_DISCUSS_CLAUSES+=("triage-registry|mb_section|Size triage|mb-idea.sh.*\\[SPEC:<group>\\]|mb-idea.sh|s/under a .\\[SPEC:<group>\\]. title prefix//|REQ-010")
  MB_DISCUSS_CLAUSES+=("triage-defer-or-mvp|mb_section|Size triage|defer it as its own child spec, or simplify it to an MVP|two choices|s/, or simplify it to an MVP inside the current topic//|REQ-021")
}

# _ctx <file> <total> <shell_subtotal>  — single-category valid frontmatter.
_ctx() {
  cat > "$1" <<EOF
---
topic: fix
estimated_tokens:
  total: $2
  breakdown:
    shell_scripts: {count: 1, unit_tokens: $3, subtotal: $3}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---

# Context
EOF
}

@test "estimate_check: the estimate validator script is present" {
  run assert_script_present scripts/mb-estimate-check.sh
  [ "$status" -eq 0 ]
}

@test "estimate_check: total under 900k → estimate=ok exit 0" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 850000 850000
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "estimate=ok spec.total=850000 spec_budget=1000000" ]
}

@test "estimate_check: total in [900k,1M] → estimate=near exit 0 advisory" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 950000 950000
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "estimate=near spec.total=950000 spec_budget=1000000" ]
}

@test "estimate_check: total over 1M → estimate=over exit 1" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 1050000 1050000
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "estimate=over spec.total=1050000 spec_budget=1000000" ]
}

@test "estimate_check: --spec-budget boundary matrix (near_lower=floor(b*9/10))" {
  local f="$BATS_TEST_TMPDIR/c.md"
  _ctx "$f" 449999 449999; run --separate-stderr "$SCRIPT" "$f" --spec-budget 500000
  [ "$status" -eq 0 ]; [ "$output" = "estimate=ok spec.total=449999 spec_budget=500000" ]
  _ctx "$f" 450000 450000; run --separate-stderr "$SCRIPT" "$f" --spec-budget 500000
  [ "$status" -eq 0 ]; [ "$output" = "estimate=near spec.total=450000 spec_budget=500000" ]
  _ctx "$f" 500000 500000; run --separate-stderr "$SCRIPT" "$f" --spec-budget 500000
  [ "$status" -eq 0 ]; [ "$output" = "estimate=near spec.total=500000 spec_budget=500000" ]
  _ctx "$f" 500001 500001; run --separate-stderr "$SCRIPT" "$f" --spec-budget 500000
  [ "$status" -eq 1 ]; [ "$output" = "estimate=over spec.total=500001 spec_budget=500000" ]
}

@test "estimate_check: invalid --spec-budget (0/neg/non-int) → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 1000 1000
  run --separate-stderr "$SCRIPT" "$f" --spec-budget 0
  [ "$status" -eq 2 ]; [ -z "$output" ]; [ "$stderr" = "error=usage" ]
  run --separate-stderr "$SCRIPT" "$f" --spec-budget -5
  [ "$status" -eq 2 ]; [ "$stderr" = "error=usage" ]
  run --separate-stderr "$SCRIPT" "$f" --spec-budget 1.5
  [ "$status" -eq 2 ]; [ "$stderr" = "error=usage" ]
}

@test "estimate_check: unknown flag → usage error, stdout empty" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 1000 1000
  run --separate-stderr "$SCRIPT" "$f" --bogus
  [ "$status" -eq 2 ]; [ -z "$output" ]; [ "$stderr" = "error=usage" ]
}

@test "estimate_check: unreadable input → <file>:0:unreadable exit 2" {
  run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]; [ -z "$output" ]
  [ "$stderr" = "$BATS_TEST_TMPDIR/nope.md:0:unreadable" ]
}

@test "estimate_check: missing estimated_tokens → estimate=missing exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf -- '---\ntopic: fix\n---\n\n# Context\n' > "$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "estimate=missing spec.total=0 spec_budget=1000000" ]
  [ "$stderr" = "$f:0:estimated_tokens:missing" ]
}

@test "estimate_check: subtotal mismatch → estimate=malformed exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 20
  breakdown:
    shell_scripts: {count: 2, unit_tokens: 10, subtotal: 999}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed spec.total='
  echo "$stderr" | grep -q ':shell_scripts:malformed$'
}

@test "estimate_check: total != sum → estimate=malformed field total" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 123 850000
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':total:malformed$'
}

@test "estimate_check: missing category key → estimate=malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 0
  breakdown:
    shell_scripts: {count: 0, unit_tokens: 0, subtotal: 0}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':python_modules:malformed$'
}

@test "estimate_check: rubric lists all six breakdown categories" {
  for c in triage-cat-shell_scripts triage-cat-prompt_changes triage-cat-python_modules \
           triage-cat-test_files triage-cat-docs_pages triage-cat-external_integrations; do
    run assert_clause "$DISCUSS" "$c"
    [ "$status" -eq 0 ]
    run assert_clause_load_bearing "$DISCUSS" "$c"
    [ "$status" -eq 0 ]
  done
}

@test "estimate_check: triage promises a follow-up interview per accepted child" {
  run assert_clause "$DISCUSS" triage-child-interview
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" triage-child-interview
  [ "$status" -eq 0 ]
}

@test "estimate_check: triage lets the user decline the recommendation" {
  run assert_clause "$DISCUSS" triage-decline
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" triage-decline
  [ "$status" -eq 0 ]
}

@test "estimate_check: triage registers deferred specs via mb-idea.sh with [SPEC:<group>]" {
  run assert_clause "$DISCUSS" triage-registry
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" triage-registry
  [ "$status" -eq 0 ]
}

@test "estimate_check: spec-sized branch offers defer-or-MVP" {
  run assert_clause "$DISCUSS" triage-defer-or-mvp
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" triage-defer-or-mvp
  [ "$status" -eq 0 ]
}

# ─── strict C1 frontmatter schema (blocker F4) ───

@test "estimate_check: estimated_tokens only in the body (no frontmatter) → missing" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
# Some doc without frontmatter

estimated_tokens:
  total: 100
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "estimate=missing spec.total=0 spec_budget=1000000" ]
  [ "$stderr" = "$f:0:estimated_tokens:missing" ]
}

@test "estimate_check: estimated_tokens only after the first frontmatter closes → missing" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
---

estimated_tokens:
  total: 100
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "estimate=missing spec.total=0 spec_budget=1000000" ]
}

@test "estimate_check: unknown breakdown category → estimate=malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 100
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
    unexpected: {count: 5, unit_tokens: 9999, subtotal: 49995}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':unexpected:malformed$'
}

@test "estimate_check: duplicated category key → estimate=malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 10
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 10, subtotal: 10}
    shell_scripts: {count: 1, unit_tokens: 10, subtotal: 10}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':shell_scripts:malformed$'
}

@test "estimate_check: breakdown header missing → estimate=malformed field breakdown" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 100
  shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':breakdown:malformed$'
}

# ─── exact six direct breakdown keys + exact map fields (cycle-2 blocker) ───

@test "estimate_check: six valid categories plus an unknown scalar → malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 100
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
    surprise: 42
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':surprise:malformed$'
}

@test "estimate_check: category map with 'discount' instead of 'count' → malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 50
  breakdown:
    shell_scripts: {discount: 5, unit_tokens: 10, subtotal: 50}
    prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
    test_files: {count: 0, unit_tokens: 0, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$stderr" | grep -q ':shell_scripts:malformed$'
}

@test "estimate_check: categories nested under an unknown wrapper → malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 100
  breakdown:
    wrapper:
      shell_scripts: {count: 1, unit_tokens: 100, subtotal: 100}
      prompt_changes: {count: 0, unit_tokens: 0, subtotal: 0}
      python_modules: {count: 0, unit_tokens: 0, subtotal: 0}
      test_files: {count: 0, unit_tokens: 0, subtotal: 0}
      docs_pages: {count: 0, unit_tokens: 0, subtotal: 0}
      external_integrations: {count: 0, unit_tokens: 0, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':wrapper:malformed$'
}

@test "estimate_check: --mb is rejected in positional context mode (usage exit 2)" {
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 1000 1000
  run --separate-stderr "$SCRIPT" "$f" --mb "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
}

# ─── duplicate estimate keys are ambiguous, never valid (review [11]) ───

@test "estimate_check: duplicate total: keys → malformed, not silently last-wins" {
  # A later `total:` overwrote the earlier one, so `total: 1` + `total: 0` with
  # a zero breakdown reported estimate=ok — an ambiguous frontmatter silently
  # resolved in favour of whichever line came last.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 1
  total: 0
  breakdown:
    shell_scripts: {count: 0, unit_tokens: 15000, subtotal: 0}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':total:malformed$'
}

@test "estimate_check: duplicate total: keys report the DUPLICATE line" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 0
  total: 0
  breakdown:
    shell_scripts: {count: 0, unit_tokens: 15000, subtotal: 0}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  # Line 4 is the second `total:` — even two IDENTICAL values are ambiguous.
  echo "$stderr" | grep -q ':4:total:malformed$'
}

@test "estimate_check: duplicate breakdown: keys → malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 0
  breakdown:
    shell_scripts: {count: 0, unit_tokens: 15000, subtotal: 0}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
  breakdown:
    shell_scripts: {count: 9, unit_tokens: 15000, subtotal: 135000}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':breakdown:malformed$'
}

@test "estimate_check: a single total: + single breakdown: still validates" {
  # Guard against over-correction: the ordinary well-formed case stays ok.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
estimated_tokens:
  total: 30000
  breakdown:
    shell_scripts: {count: 2, unit_tokens: 15000, subtotal: 30000}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^estimate=ok'
}

@test "estimate_check: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ─── strict frontmatter shape (r2 review [11]) ───
#
# The parser searched DESCENDANTS of `estimated_tokens:` for `total:` /
# `breakdown:` at any depth, and silently took the FIRST of several top-level
# sections. Both let an unintended document validate as estimate=ok.

@test "estimate_check: a WRAPPED estimated_tokens block is malformed, not ok" {
  # `estimated_tokens.wrapper.total/breakdown` used to return estimate=ok.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  wrapper:
    total: 30000
    breakdown:
      shell_scripts: {count: 2, unit_tokens: 15000, subtotal: 30000}
      prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
      python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
      test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
      docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
      external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
}

@test "estimate_check: a DUPLICATE estimated_tokens section is malformed, not ok" {
  # A valid zero-valued first section followed by a second over-budget one used
  # to report estimate=ok on the first and ignore the second entirely.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 0
  breakdown:
    shell_scripts: {count: 0, unit_tokens: 15000, subtotal: 0}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
estimated_tokens:
  total: 99999999
  breakdown:
    garbage: nope
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
}

@test "estimate_check: an unknown key beside total/breakdown is malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 15000
  surprise: 42
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 15000, subtotal: 15000}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
}

@test "estimate_check: a nested child under a breakdown category is malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 15000
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 15000, subtotal: 15000}
      extra: 1
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
}

# ─── exact integer arithmetic (r2 review [16]) ───

@test "estimate_check: a huge inconsistent product is malformed, not silently over" {
  # count 9007199254740993 * 1 != subtotal 9007199254740992, but awk's doubles
  # rounded both to the same value and accepted the inconsistency as over-budget.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 9007199254740992
  breakdown:
    shell_scripts: {count: 9007199254740993, unit_tokens: 1, subtotal: 9007199254740992}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q 'shell_scripts:malformed'
}

@test "estimate_check: a huge CONSISTENT product stays exact and reports over" {
  # The converse: exact big-integer arithmetic must still accept a correct
  # product rather than rejecting everything large.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 9007199254740993
  breakdown:
    shell_scripts: {count: 9007199254740993, unit_tokens: 1, subtotal: 9007199254740993}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "estimate=over spec.total=9007199254740993 spec_budget=1000000" ]
}

@test "estimate_check: a huge total inconsistent with an exact sum is malformed" {
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 9007199254740992
  breakdown:
    shell_scripts: {count: 1, unit_tokens: 9007199254740993, subtotal: 9007199254740993}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---

# Context
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '^estimate=malformed'
  echo "$stderr" | grep -q ':total:malformed'
}

# ─── breakdown must be a real map (r3 review [19]) ───

@test "estimate_check: a SCALAR value on breakdown: is malformed" {
  # The direct key's value was stored but never shape-checked, so
  # `breakdown: definitely-not-a-map` with six indented rows returned ok.
  local f="$BATS_TEST_TMPDIR/c.md"
  cat > "$f" <<'EOF'
---
topic: fix
estimated_tokens:
  total: 15000
  breakdown: definitely-not-a-map
    shell_scripts: {count: 1, unit_tokens: 15000, subtotal: 15000}
    prompt_changes: {count: 0, unit_tokens: 8000, subtotal: 0}
    python_modules: {count: 0, unit_tokens: 25000, subtotal: 0}
    test_files: {count: 0, unit_tokens: 10000, subtotal: 0}
    docs_pages: {count: 0, unit_tokens: 5000, subtotal: 0}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
---
body
EOF
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ] || { echo "scalar breakdown accepted: $output"; false; }
  echo "$output" | grep -q '^estimate=malformed'
}

@test "estimate_check: a scalar on total: is still read as a value" {
  # Guard the converse: `total:` legitimately carries a scalar.
  local f="$BATS_TEST_TMPDIR/c.md"; _ctx "$f" 850000 850000
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 0 ]
}

# ─── sparse ids must not drive a dense scan (r3 review [20]) ───

@test "estimate_check: a huge task id completes promptly" {
  # The aggregation looped 1..maxid, so a single `mb-task:999999999` block spun
  # for minutes on a two-line file.
  local d="$BATS_TEST_TMPDIR/spec"; mkdir -p "$d"
  printf '# Tasks\n\n<!-- mb-task:999999999 -->\n### T\n**Budget:** 1000\n**Stage:** 1\n<!-- /mb-task:999999999 -->\n' > "$d/tasks.md"
  local start end
  start="$(date +%s)"
  run --separate-stderr "$SCRIPT" --tasks-file "$d/tasks.md"
  end="$(date +%s)"
  [ "$((end - start))" -lt 10 ] || { echo "took $((end - start))s for one task"; false; }
  echo "$output" | grep -q 'task.999999999=1000'
}

@test "estimate_check: sparse stage ids complete promptly and aggregate correctly" {
  local d="$BATS_TEST_TMPDIR/spec2"; mkdir -p "$d"
  printf '# Tasks\n\n<!-- mb-task:1 -->\n### A\n**Budget:** 100\n**Stage:** 900000\n<!-- /mb-task:1 -->\n\n<!-- mb-task:2 -->\n### B\n**Budget:** 200\n**Stage:** 1\n<!-- /mb-task:2 -->\n' > "$d/tasks.md"
  local start end
  start="$(date +%s)"
  run --separate-stderr "$SCRIPT" --tasks-file "$d/tasks.md"
  end="$(date +%s)"
  [ "$((end - start))" -lt 10 ] || { echo "took $((end - start))s"; false; }
  echo "$output" | grep -q 'stage.1=200'
  echo "$output" | grep -q 'stage.900000=100'
  echo "$output" | grep -q 'spec.total=300'
}
