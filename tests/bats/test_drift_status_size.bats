#!/usr/bin/env bats
# mb-drift.sh check 17 `status_size` — status.md past the rotation threshold
# (24 KB) is a warning that names mb-status-rotate.sh; under it is ok.

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

@test "status.md under 24 KB → status_size ok" {
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_status_size=ok'
}

@test "status.md over 24 KB → status_size warn naming mb-status-rotate.sh" {
  head -c 24577 /dev/zero | tr '\0' 'x' >> "$MB/status.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_status_size=warn'
  echo "$output" | grep -q 'mb-status-rotate.sh'
}
