#!/usr/bin/env bats
# A3 — mb-compact.sh archives stale session/*.md (older than threshold) to
# session/archive/, never touching _recent.md or fresh sessions. Idempotent.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-compact.sh"
  TMP="$(mktemp -d)"; MB="$TMP/.memory-bank"; SDIR="$MB/session"
  mkdir -p "$SDIR" "$MB/notes" "$MB/plans/done"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

_sess() { # $1=filename $2=summary
  printf -- '---\nsession_id: %s\nbranch: dev\n---\n\n## Live log\n- x\n\n## Summary\n%s\n' "${1%.md}" "$2" > "$SDIR/$1"
}

@test "dry-run reports stale session candidate without moving" {
  _sess "2026-01-01_1000_oldold00.md" "old summary"
  touch -t 202601011000 "$SDIR/2026-01-01_1000_oldold00.md"
  run bash "$SCRIPT" --dry-run "$MB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'sessions_candidates=1'
  [ -f "$SDIR/2026-01-01_1000_oldold00.md" ]
  [ ! -d "$SDIR/archive" ]
}

@test "apply archives stale, keeps fresh + _recent.md" {
  _sess "2026-01-01_1000_oldold00.md" "old summary"
  _sess "2026-06-08_1000_freshfr0.md" "fresh summary"
  printf '## recent\nbody\n' > "$SDIR/_recent.md"
  touch -t 202601011000 "$SDIR/2026-01-01_1000_oldold00.md"
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [ -f "$SDIR/archive/2026-01-01_1000_oldold00.md" ]
  [ ! -f "$SDIR/2026-01-01_1000_oldold00.md" ]
  [ -f "$SDIR/2026-06-08_1000_freshfr0.md" ]
  [ -f "$SDIR/_recent.md" ]
}

@test "idempotent re-apply finds nothing new" {
  _sess "2026-01-01_1000_oldold00.md" "old summary"
  touch -t 202601011000 "$SDIR/2026-01-01_1000_oldold00.md"
  bash "$SCRIPT" --apply "$MB" >/dev/null
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'sessions_candidates=0'
}
