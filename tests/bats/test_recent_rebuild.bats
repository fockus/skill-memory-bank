#!/usr/bin/env bats
# A2 — mb-session-recent-rebuild.sh regenerates session/_recent.md from existing
# session files: newest-first, keeps MB_RECENT_KEEP that have a ## Summary,
# skips empty / summary-less ones, idempotent.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-session-recent-rebuild.sh"
  TMP="$(mktemp -d)"; MB="$TMP/.memory-bank"; SDIR="$MB/session"; mkdir -p "$SDIR"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

_session() { # $1=filename $2=branch $3=summary("" => none)
  {
    printf -- '---\nsession_id: %s\nbranch: %s\n---\n\n## Live log\n- x\n' "${1%.md}" "$2"
    if [ -n "$3" ]; then printf '\n## Summary\n%s\n' "$3"; fi
  } > "$SDIR/$1"
}

@test "keeps substantive newest-first, skips empty/no-summary" {
  _session "2026-06-01_1000_aaaaaaaa.md" dev ""                 # no summary
  _session "2026-06-02_1100_bbbbbbbb.md" dev "older summary text"
  _session "2026-06-03_1200_cccccccc.md" main "newer summary text"
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  R="$SDIR/_recent.md"; [ -f "$R" ]
  grep -q 'newer summary text' "$R"
  grep -q 'older summary text' "$R"
  ! grep -q 'aaaaaaaa' "$R"
  [ "$(grep -n 'cccccccc' "$R" | head -1 | cut -d: -f1)" -lt "$(grep -n 'bbbbbbbb' "$R" | head -1 | cut -d: -f1)" ]
  grep -qE '^## 2026-06-03 12:00 \(main\) — cccccccc' "$R"
}

@test "idempotent" {
  _session "2026-06-02_1100_bbbbbbbb.md" dev "summary one"
  bash "$SCRIPT" "$MB" >/dev/null; cp "$SDIR/_recent.md" "$TMP/a"
  bash "$SCRIPT" "$MB" >/dev/null; cp "$SDIR/_recent.md" "$TMP/b"
  diff "$TMP/a" "$TMP/b"
}

@test "respects MB_RECENT_KEEP" {
  _session "2026-06-01_1000_a1111111.md" dev "s1"
  _session "2026-06-02_1000_b2222222.md" dev "s2"
  _session "2026-06-03_1000_c3333333.md" dev "s3"
  run env MB_RECENT_KEEP=2 bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^## ' "$SDIR/_recent.md")" -eq 2 ]
}
