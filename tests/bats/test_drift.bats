#!/usr/bin/env bats
# Tests for scripts/mb-drift.sh — 8 deterministic checkers without AI.
#
# Output contract: key=value on stdout, warnings on stderr.
#   - drift_warnings=N (final count)
#   - drift_check_<name>=ok|warn per checker
# Exit: 0 if drift_warnings=0, otherwise 1.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DRIFT="$REPO_ROOT/scripts/mb-drift.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB/notes" "$MB/plans/done" "$MB/reports"
  # Baseline core-file contents — clean unless a test changes them.
  : > "$MB/STATUS.md"
  : > "$MB/checklist.md"
  : > "$MB/plan.md"
  : > "$MB/progress.md"
  : > "$MB/lessons.md"
  : > "$MB/RESEARCH.md"
  : > "$MB/BACKLOG.md"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Run drift, capturing stdout/stderr and exit code.
run_drift() {
  local target="${1:-$PROJECT}"
  local raw
  raw=$(bash "$DRIFT" "$target" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Overall contract — smoke
# ═══════════════════════════════════════════════════════════════

@test "drift: clean bank → drift_warnings=0 exit 0" {
  run_drift
  [ "$status" -eq 0 ]
  [[ "$output" == *"drift_warnings=0"* ]]
}

@test "drift: output format — key=value parses lexically" {
  run_drift
  # All key=value lines must be parseable (no weird chars)
  echo "$output" | grep -E '^[a-z_][a-z0-9_]*=[^[:space:]]*$' | head -1
}

@test "drift: missing .memory-bank/ → fails fast with hint" {
  NOBANK="$(mktemp -d)"
  run_drift "$NOBANK"
  [ "$status" -ne 0 ]
  [[ "$output" == *".memory-bank"* ]] || [[ "$output" == *"not found"* ]]
  rm -rf "$NOBANK"
}

# ═══════════════════════════════════════════════════════════════
# Checker 1: path — file references exist
# ═══════════════════════════════════════════════════════════════

@test "drift[path]: reference to existing note → no warning" {
  echo "note-stub" > "$MB/notes/2026-04-20_test.md"
  echo "See notes/2026-04-20_test.md" > "$MB/checklist.md"
  run_drift
  [[ "$output" == *"drift_check_path=ok"* ]]
}

@test "drift[path]: reference to missing note → warning path" {
  echo "See notes/missing.md" > "$MB/checklist.md"
  run_drift
  [[ "$output" == *"drift_check_path=warn"* ]]
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Checker 2: staleness — core files stay fresh
# ═══════════════════════════════════════════════════════════════

@test "drift[staleness]: recent core files → no warning" {
  echo "fresh" > "$MB/STATUS.md"
  run_drift
  [[ "$output" == *"drift_check_staleness=ok"* ]]
}

@test "drift[staleness]: STATUS.md mtime >30 days → warning staleness" {
  echo "stale" > "$MB/STATUS.md"
  old=$(( $(date +%s) - 40 * 86400 ))
  touch -t "$(date -r "$old" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$old" +%Y%m%d%H%M.%S)" "$MB/STATUS.md"
  run_drift
  [[ "$output" == *"drift_check_staleness=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 3: script-coverage — `bash scripts/X.sh` references existing
# ═══════════════════════════════════════════════════════════════

@test "drift[script-coverage]: existing bash scripts/foo.sh → no warning" {
  mkdir -p "$PROJECT/scripts"
  : > "$PROJECT/scripts/foo.sh"
  echo "bash scripts/foo.sh" > "$MB/plan.md"
  run_drift
  [[ "$output" == *"drift_check_script_coverage=ok"* ]]
}

@test "drift[script-coverage]: reference missing bash scripts/gone.sh → warning" {
  echo "bash scripts/gone.sh" > "$MB/plan.md"
  run_drift
  [[ "$output" == *"drift_check_script_coverage=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 4: dependency — documented Python version matches pyproject
# ═══════════════════════════════════════════════════════════════

@test "drift[dependency]: no project deps file → skip check (ok)" {
  # Clean project without pyproject/package.json — checker skips as ok.
  echo "Python 3.12" > "$MB/STATUS.md"
  run_drift
  [[ "$output" == *"drift_check_dependency=ok"* ]] || [[ "$output" == *"drift_check_dependency=skip"* ]]
}

@test "drift[dependency]: STATUS Python 3.11 vs pyproject 3.12 → warning" {
  cat > "$PROJECT/pyproject.toml" <<'EOF'
[project]
name = "foo"
requires-python = ">=3.12"
EOF
  echo "# STATUS" > "$MB/STATUS.md"
  echo "Stack: Python 3.11" >> "$MB/STATUS.md"
  run_drift
  [[ "$output" == *"drift_check_dependency=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 5: cross-file — numeric consistency across MB files
# ═══════════════════════════════════════════════════════════════

@test "drift[cross-file]: same test count in STATUS and checklist → no warning" {
  echo "Tests: 163 bats green" > "$MB/STATUS.md"
  echo "**Summary**: 163 bats green" > "$MB/checklist.md"
  run_drift
  [[ "$output" == *"drift_check_cross_file=ok"* ]]
}

@test "drift[cross-file]: test counts differ — STATUS=163 vs checklist=100 → warning" {
  echo "Tests: 163 bats green" > "$MB/STATUS.md"
  echo "**Summary**: 100 bats green" > "$MB/checklist.md"
  run_drift
  [[ "$output" == *"drift_check_cross_file=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 6: index-sync — index.json mtime vs notes/*.md
# ═══════════════════════════════════════════════════════════════

@test "drift[index-sync]: fresh index.json newer than notes → no warning" {
  echo "note" > "$MB/notes/2026-04-20_a.md"
  sleep 1
  echo '{"notes":[]}' > "$MB/index.json"
  run_drift
  [[ "$output" == *"drift_check_index_sync=ok"* ]]
}

@test "drift[index-sync]: note newer than index.json → warning" {
  echo '{"notes":[]}' > "$MB/index.json"
  sleep 1
  echo "note" > "$MB/notes/2026-04-20_b.md"
  run_drift
  [[ "$output" == *"drift_check_index_sync=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 7: command — `make X` / `npm run X` references exist
# ═══════════════════════════════════════════════════════════════

@test "drift[command]: npm run test references valid package.json → no warning" {
  cat > "$PROJECT/package.json" <<'EOF'
{"name":"x","scripts":{"test":"jest"}}
EOF
  echo "Run: npm run test" > "$MB/plan.md"
  run_drift
  [[ "$output" == *"drift_check_command=ok"* ]]
}

@test "drift[command]: npm run nonexistent → warning" {
  cat > "$PROJECT/package.json" <<'EOF'
{"name":"x","scripts":{"test":"jest"}}
EOF
  echo "Run: npm run nonexistent-script" > "$MB/plan.md"
  run_drift
  [[ "$output" == *"drift_check_command=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Checker 8: frontmatter — notes YAML is valid
# ═══════════════════════════════════════════════════════════════

@test "drift[frontmatter]: valid frontmatter → no warning" {
  cat > "$MB/notes/2026-04-20_good.md" <<'EOF'
---
type: note
tags: [auth, bug]
importance: high
---

body here
EOF
  run_drift
  [[ "$output" == *"drift_check_frontmatter=ok"* ]]
}

@test "drift[frontmatter]: unterminated YAML fence → warning" {
  cat > "$MB/notes/2026-04-20_bad.md" <<'EOF'
---
type: note
tags: [unclosed
EOF
  # No closing --- → parser cannot parse it.
  run_drift
  [[ "$output" == *"drift_check_frontmatter=warn"* ]]
}

# ═══════════════════════════════════════════════════════════════
# Aggregation — broken fixture smoke
# ═══════════════════════════════════════════════════════════════

@test "drift: broken fixture — ≥5 warning categories" {
  # Combination of errors — use existing tests/fixtures/broken-mb/
  # if present, otherwise synthesize inline.
  FIXTURE="$REPO_ROOT/tests/fixtures/broken-mb"
  if [ -d "$FIXTURE" ]; then
    run_drift "$FIXTURE"
  else
    # Inline: at least 5 kinds of drift.
    echo "See notes/missing.md" > "$MB/checklist.md"                                      # path
    old=$(( $(date +%s) - 40 * 86400 ))
    touch -t "$(date -r "$old" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$old" +%Y%m%d%H%M.%S)" "$MB/STATUS.md" # staleness
    echo "bash scripts/gone.sh" >> "$MB/plan.md"                                          # script-coverage
    echo "Tests: 5 green" > "$MB/STATUS.md"
    echo "Tests: 999 green" > "$MB/progress.md"                                           # cross-file
    printf -- '---\ntype: note\ntags: [broken\n' > "$MB/notes/2026-04-20_x.md"           # frontmatter
    run_drift
  fi

  # At least 5 warnings.
  warnings=$(echo "$output" | grep -oE 'drift_warnings=[0-9]+' | head -1 | cut -d= -f2)
  [ "${warnings:-0}" -ge 5 ]
  [ "$status" -ne 0 ]
}
