#!/usr/bin/env bats
# B4 — mb-drift.sh flags malformed or dangling `[SUPERSEDED: YYYY-MM-DD -> <ref>]`
# markers across the bank (notes/, lessons.md, progress.md, session/).
#
# Convention (design.md §B4 / agents/mb-manager.md / references/metadata.md):
#   append the new fact, mark the OLD one with
#   `[SUPERSEDED: YYYY-MM-DD -> notes/<file>#<heading>]` — never edit in place.
# Valid markers and zero markers are silent; malformed date, missing
# `-> <ref>`, or a dangling ref (target file absent) is a warning.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-drift.sh"
  TMP="$(mktemp -d)"; DIR="$TMP"; MB="$DIR/.memory-bank"
  mkdir -p "$MB/notes" "$MB/session"
  for c in status roadmap checklist research backlog progress lessons; do
    printf '# %s\n' "$c" > "$MB/$c.md"
  done
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

@test "no SUPERSEDED markers anywhere → supersedes ok, exit 0" {
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
  [ "$status" -eq 0 ]
}

@test "valid marker with existing ref target → supersedes ok" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '- old fact [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md#new-fact]\n' \
    >> "$MB/notes/2026-05-01_old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
}

@test "valid marker in lessons.md with existing ref → supersedes ok" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '### L-001: old [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md]\n' \
    >> "$MB/lessons.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
}

@test "valid leap-day marker (2024-02-29) → supersedes ok" {
  printf '# new fact\n' > "$MB/notes/2024-02-29_new.md"
  printf -- '- old [SUPERSEDED: 2024-02-29 -> notes/2024-02-29_new.md]\n' \
    >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
  [ "$status" -eq 0 ]
}

@test "malformed date (not YYYY-MM-DD) → supersedes warn, exit non-zero" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '- old [SUPERSEDED: 06/12/2026 -> notes/2026-06-12_new.md]\n' \
    >> "$MB/notes/2026-05-01_old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'malformed SUPERSEDED marker'
  [ "$status" -ne 0 ]
}

@test "missing '-> <ref>' arrow → supersedes warn" {
  printf -- '- old [SUPERSEDED: 2026-06-12]\n' >> "$MB/notes/2026-05-01_old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'malformed SUPERSEDED marker'
  [ "$status" -ne 0 ]
}

@test "dangling ref (target file does not exist) → supersedes warn" {
  printf -- '- old [SUPERSEDED: 2026-06-12 -> notes/does-not-exist.md#x]\n' \
    >> "$MB/notes/2026-05-01_old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'missing target'
  [ "$status" -ne 0 ]
}

@test "dangling ref in progress.md → supersedes warn" {
  printf -- '## 2026-06-12\n- old [SUPERSEDED: 2026-06-12 -> notes/gone.md]\n' \
    >> "$MB/progress.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'missing target'
  [ "$status" -ne 0 ]
}

@test "dangling ref in session/ → supersedes warn" {
  printf -- '- old [SUPERSEDED: 2026-06-12 -> notes/gone.md]\n' \
    > "$MB/session/2026-06-12.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'missing target'
  [ "$status" -ne 0 ]
}

# ── Calendar validation (blocker 1): impossible dates that pass the shape regex ──

@test "impossible date 2026-02-30 → supersedes warn (not a valid calendar date)" {
  printf '# new fact\n' > "$MB/notes/n.md"
  printf -- '- old [SUPERSEDED: 2026-02-30 -> notes/n.md]\n' >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'not a valid calendar date'
  [ "$status" -ne 0 ]
}

@test "impossible date 2026-04-31 (30-day month) → supersedes warn" {
  printf '# new fact\n' > "$MB/notes/n.md"
  printf -- '- old [SUPERSEDED: 2026-04-31 -> notes/n.md]\n' >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'not a valid calendar date'
  [ "$status" -ne 0 ]
}

@test "non-leap Feb 29 (2026-02-29) → supersedes warn" {
  printf '# new fact\n' > "$MB/notes/n.md"
  printf -- '- old [SUPERSEDED: 2026-02-29 -> notes/n.md]\n' >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'not a valid calendar date'
  [ "$status" -ne 0 ]
}

@test "century non-leap-year Feb 29 (1900-02-29) → supersedes warn" {
  printf '# new fact\n' > "$MB/notes/n.md"
  printf -- '- old [SUPERSEDED: 1900-02-29 -> notes/n.md]\n' >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'not a valid calendar date'
  [ "$status" -ne 0 ]
}

@test "400-year leap Feb 29 (2000-02-29) → supersedes ok" {
  printf '# new fact\n' > "$MB/notes/n.md"
  printf -- '- old [SUPERSEDED: 2000-02-29 -> notes/n.md]\n' >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
  [ "$status" -eq 0 ]
}

# ── Multiple markers per line (blocker 2): a 2nd dangling marker after a valid one ──

@test "valid marker followed by dangling marker on same line → supersedes warn" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '- a [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md] b [SUPERSEDED: 2026-06-12 -> notes/gone.md]\n' \
    >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'missing target'
  [ "$status" -ne 0 ]
}

@test "valid marker followed by malformed opener on same line → supersedes warn" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '- a [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md] dangling opener [SUPERSEDED: nope\n' \
    >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=warn'
  echo "$output" | grep -q 'malformed SUPERSEDED marker'
  [ "$status" -ne 0 ]
}

@test "two valid markers on same line → supersedes ok" {
  printf '# new fact\n' > "$MB/notes/2026-06-12_new.md"
  printf -- '- a [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md] b [SUPERSEDED: 2026-06-12 -> notes/2026-06-12_new.md]\n' \
    >> "$MB/notes/old.md"
  run bash "$SCRIPT" "$DIR"
  echo "$output" | grep -q 'drift_check_supersedes=ok'
  [ "$status" -eq 0 ]
}
