#!/usr/bin/env bats
# Stage 5 — mb-session-prune.sh: archive contentless session stubs (dry-run default,
# archive-not-delete, never touch substantive / _recent / current session, idempotent).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-session-prune.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/session"
  _stub() {  # contentless
    cat > "$MB/session/$1" <<EOF
---
session_id: $1
summarized: false
---

## Live log
- 10:00 — User: "" · tools: (none) · files: (none) · ok
EOF
  }
  _real() {  # substantive
    cat > "$MB/session/$1" <<EOF
---
session_id: $1
summarized: false
---

## Live log
- 10:00 — User: "real work" · tools: Edit · files: a.go · ok
EOF
  }
  _stub "2026-06-10_1000_aaaaaaaa.md"
  _stub "2026-06-10_1001_bbbbbbbb.md"
  _real "2026-06-10_1002_cccccccc.md"
  printf '# recent\n' > "$MB/session/_recent.md"
}
teardown() { rm -rf "$TMP"; }

@test "dry-run lists stubs and writes nothing (default)" {
  run bash "$SCRIPT" "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub: 2026-06-10_1000_aaaaaaaa.md"* ]]
  [[ "$output" == *"stubs=2"* ]]
  [[ "$output" == *"substantive_kept=1"* ]]
  # nothing moved
  [ -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
  [ ! -d "$MB/session/archive" ]
}

@test "--apply archives only stubs, keeps substantive + _recent" {
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [ ! -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
  [ ! -f "$MB/session/2026-06-10_1001_bbbbbbbb.md" ]
  [ -f "$MB/session/archive/stubs/2026-06-10_1000_aaaaaaaa.md" ]   # archived verbatim
  [ -f "$MB/session/2026-06-10_1002_cccccccc.md" ]                 # substantive kept
  [ -f "$MB/session/_recent.md" ]                                  # _recent kept
}

@test "current session (CLAUDE_CODE_SESSION_ID) is never pruned even if contentless" {
  run env CLAUDE_CODE_SESSION_ID="aaaaaaaa-1111-2222" bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [ -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]   # excluded by sid8
  [ ! -f "$MB/session/2026-06-10_1001_bbbbbbbb.md" ] # other stub still archived
}

@test "idempotent: second --apply archives nothing more" {
  bash "$SCRIPT" --apply "$MB"
  run bash "$SCRIPT" --apply "$MB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stubs=0"* ]]
}

@test "--apply --hard deletes instead of archiving" {
  run bash "$SCRIPT" --apply --hard "$MB"
  [ "$status" -eq 0 ]
  [ ! -f "$MB/session/2026-06-10_1000_aaaaaaaa.md" ]
  [ ! -d "$MB/session/archive" ]
}
