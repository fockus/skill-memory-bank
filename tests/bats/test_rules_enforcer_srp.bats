#!/usr/bin/env bats
# Tests for SRP (file size) check in scripts/mb-rules-check.sh.
#
# Contract (Stage 2 of plans/2026-04-21_refactor_agents-quality.md):
#   Usage: mb-rules-check.sh --files <file>[,<file>...] [--out json|human|both]
#   Severity policy (SRP, canon in rules/RULES.md § SOLID):
#     - file > 300 lines                        → 1 violation per file, severity=WARNING
#     - with --base <ref>: the file was ≤ 300 lines (or absent) at <ref>
#       and is > 300 now, i.e. this change pushed it over → severity=CRITICAL
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
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then rm -rf "$TMPROOT"; fi
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

@test "srp: three big files without --base → WARNING each (size alone does not block)" {
  make_file "src/a.py" 310
  make_file "src/b.py" 320
  make_file "src/c.py" 330
  run bash "$CHECK" --files "src/a.py,src/b.py,src/c.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "solid/srp")) | length) == 3'
  echo "$output" | jq -e 'all(.violations[]; .severity == "WARNING")'
}

_git_base() {  # commit the current tree and print the ref
  git init -q . && git config user.email t@t.t && git config user.name t
  git add -A && git commit -qm base && git rev-parse HEAD
}

@test "srp --base: change pushes a file over the threshold → CRITICAL" {
  make_file "src/grow.py" 280
  base="$(_git_base)"
  make_file "src/grow.py" 320
  run bash "$CHECK" --files "src/grow.py" --base "$base" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations[0].rule == "solid/srp" and .violations[0].severity == "CRITICAL"'
}

@test "srp --base: new file created over the threshold → CRITICAL" {
  make_file "src/keep.py" 10
  base="$(_git_base)"
  make_file "src/new.py" 350
  run bash "$CHECK" --files "src/new.py" --base "$base" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations[0].severity == "CRITICAL"'
}

@test "srp --base: file already over the threshold at base → WARNING" {
  make_file "src/legacy.py" 400
  base="$(_git_base)"
  make_file "src/legacy.py" 420
  run bash "$CHECK" --files "src/legacy.py" --base "$base" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.violations[0].severity == "WARNING"'
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
