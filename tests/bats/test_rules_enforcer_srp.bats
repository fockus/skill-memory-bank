#!/usr/bin/env bats
# Tests for SRP (file size) check in scripts/mb-rules-check.sh.
#
# Contract (Stage 2 of plans/2026-04-21_refactor_agents-quality.md):
#   Usage: mb-rules-check.sh --files <file>[,<file>...] [--out json|human|both]
#   Severity policy (SRP):
#     - file > 300 lines                        → 1 violation per file
#     - 1 offending file                        → severity=WARNING
#     - ≥ 3 offending files                     → severity=CRITICAL (each)
#   Exclusions (no SRP hit): *.md, *.json, *.lock, *.svg, files under
#   vendor/, node_modules/, __pycache__/, any .*/, and generated files
#   matching `# GENERATED` marker on line 1.
#   JSON: {"violations":[{"rule":"solid/srp","severity":"WARNING|CRITICAL",
#   "file":"<path>","line":1,"excerpt":"<N> lines","rationale":"..."}, ...],
#   "stats":{"files_scanned":N,"checks_run":K,"duration_ms":N}}

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  command -v jq >/dev/null || skip "jq required"

  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

make_file() {
  local path="$1" lines="$2"
  mkdir -p "$(dirname "$path")"
  : > "$path"
  for ((i=1; i<=lines; i++)); do
    printf 'line %d\n' "$i" >> "$path"
  done
}

@test "srp: file of 350 lines → single violation with severity=WARNING" {
  make_file "src/big.py" 350
  run bash "$CHECK" --files "src/big.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations | length == 1'
  echo "$output" | jq -e '.violations[0].rule == "solid/srp"'
  echo "$output" | jq -e '.violations[0].severity == "WARNING"'
  echo "$output" | jq -e '.violations[0].file == "src/big.py"'
}

@test "srp: 250-line file → no violation" {
  make_file "src/small.py" 250
  run bash "$CHECK" --files "src/small.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 0'
}

@test "srp: exactly 300 lines → no violation (strictly greater-than threshold)" {
  make_file "src/edge.py" 300
  run bash "$CHECK" --files "src/edge.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 0'
}

@test "srp: three big files → all CRITICAL (cluster escalation)" {
  make_file "src/a.py" 310
  make_file "src/b.py" 320
  make_file "src/c.py" 330
  run bash "$CHECK" --files "src/a.py,src/b.py,src/c.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 3'
  echo "$output" | jq -e 'all(.violations[]; .severity == "CRITICAL")'
}

@test "srp: excluded extensions (.md, .json) ignored even when > 300 lines" {
  make_file "docs/big.md" 500
  make_file "data/fixtures.json" 400
  run bash "$CHECK" --files "docs/big.md,data/fixtures.json" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 0'
}

@test "srp: vendor/ path excluded" {
  make_file "vendor/huge.py" 800
  run bash "$CHECK" --files "vendor/huge.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 0'
}

@test "srp: generated marker on line 1 excluded" {
  mkdir -p src
  { echo "# GENERATED"; for i in {1..350}; do echo "row $i"; done; } > src/gen.py
  run bash "$CHECK" --files "src/gen.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 0'
}

@test "srp: stats.files_scanned == files passed" {
  make_file "src/a.py" 10
  make_file "src/b.py" 10
  run bash "$CHECK" --files "src/a.py,src/b.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stats.files_scanned == 2'
}
