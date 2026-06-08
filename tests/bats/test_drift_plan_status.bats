#!/usr/bin/env bats
# A5 — mb-drift.sh flags plans whose frontmatter `status:` is outside the
# canonical vocabulary (queued / in_progress / done / blocked).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"; DIR="$TMP"; MB="$DIR/.memory-bank"
  mkdir -p "$MB/plans/done"
  for c in status roadmap checklist research backlog progress lessons; do
    printf '# %s\n' "$c" > "$MB/$c.md"
  done
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "non-canonical status: → plan_status warn" {
  printf -- '---\ntype: feature\nstatus: active\n---\n# p\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_status=warn'
}

@test "canonical status: → plan_status ok" {
  printf -- '---\ntype: feature\nstatus: in_progress\n---\n# p\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_status=ok'
}

@test "no status: key → not flagged" {
  printf -- '---\ntype: feature\n---\n# p\n' > "$MB/plans/p.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_plan_status=ok'
}
