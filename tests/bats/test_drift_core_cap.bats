#!/usr/bin/env bats
# mb-drift.sh check 17 `core_cap` — status.md / checklist.md past their LINE
# caps (60 / 100, AGR-043). The predecessor check measured status.md in bytes
# (24 KB) and stayed green on a rotated-but-still-223-line status.md, which is
# exactly the drift the cap is meant to catch.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"; DIR="$TMP"; MB="$DIR/.memory-bank"
  mkdir -p "$MB"
  for c in status roadmap checklist research backlog progress lessons; do
    printf '# %s\n' "$c" > "$MB/$c.md"
  done
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "core_cap: both core files within their line caps → ok" {
  run bash "$SCRIPT" "$DIR"
  assert_substring "$output" 'drift_check_core_cap=ok'
  refute_substring "$output" 'drift_check_status_size='
}

@test "core_cap: status.md over 60 lines → warn naming mb-core-cap.sh" {
  for i in $(seq 1 70); do printf -- '- line %s\n' "$i" >> "$MB/status.md"; done
  run bash "$SCRIPT" "$DIR"
  assert_substring "$output" 'drift_check_core_cap=warn'
  assert_substring "$output" 'mb-core-cap.sh'
}

@test "core_cap: a big status.md under 24 KB still warns — bytes were the wrong unit" {
  for i in $(seq 1 70); do printf -- '- x\n' >> "$MB/status.md"; done
  run bash -c "wc -c < '$MB/status.md'"
  [ "$(echo "$output" | tr -d ' ')" -lt 24576 ]
  run bash "$SCRIPT" "$DIR"
  assert_substring "$output" 'drift_check_core_cap=warn'
}

@test "core_cap: checklist.md over 100 lines is caught by the same check" {
  for i in $(seq 1 120); do printf -- '- ⬜ item %s\n' "$i" >> "$MB/checklist.md"; done
  run bash "$SCRIPT" "$DIR"
  assert_substring "$output" 'drift_check_core_cap=warn'
  assert_substring "$output" 'over=checklist'
  assert_substring "$output" 'checklist_cap=100'
}
