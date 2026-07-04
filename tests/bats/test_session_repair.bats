#!/usr/bin/env bats
# A7 — mb-session-repair.sh: move post-Summary turn-bullets back into `## Live log`, reset
# summarized=false (keep judged), verbatim backup, re-cap, idempotent, dry-run default.
# Plus mb-session-prune.sh byte-threshold repair-candidate flagging.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REPAIR="$REPO_ROOT/scripts/mb-session-repair.sh"
  PRUNE="$REPO_ROOT/scripts/mb-session-prune.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB/session"
  SF="$MB/session/2026-06-06_0900_deadbeef.md"
  cat > "$SF" <<'EOF'
---
session_id: deadbeef-1111
summarized: true
judged: true
---

## Live log
- 09:00 — User: "turn one" · tools: (none) · files: (none) · ok

## Summary
Summary text describing turn one only.
- 09:05 — User: "turn two" · tools: Edit · files: a.go · ok
- 09:06 — User: "turn three" · tools: Bash · files: b.go · ok
- 09:07 — User: "turn four" · tools: Read · files: c.go · ok
EOF
}
teardown() { rm -rf "$TMP"; }

@test "A7: --apply moves post-Summary bullets into Live log, none remain after Summary" {
  run bash "$REPAIR" --apply "$SF"
  [ "$status" -eq 0 ]
  sum_ln="$(grep -n '^## Summary' "$SF" | head -1 | cut -d: -f1)"
  [ -n "$sum_ln" ]
  # all three moved bullets still present, each BEFORE the Summary heading
  for t in "turn two" "turn three" "turn four"; do
    bl="$(grep -n "$t" "$SF" | head -1 | cut -d: -f1)"
    [ -n "$bl" ] && [ "$bl" -lt "$sum_ln" ]
  done
  # no turn-bullet remains after the Summary heading
  after="$(tail -n +"$((sum_ln + 1))" "$SF" | grep -cE '^- [0-9][0-9]:[0-9][0-9] ' || true)"
  [ "$after" -eq 0 ]
  # verbatim backup kept
  ls "$MB/session/archive/pre-repair/"*.md.* >/dev/null
}

@test "A7: repair resets summarized=false, leaves judged untouched" {
  bash "$REPAIR" --apply "$SF" >/dev/null
  grep -q '^summarized: false' "$SF"
  grep -q '^judged: true' "$SF"
}

@test "A7: repair is idempotent (second --apply is byte-identical)" {
  bash "$REPAIR" --apply "$SF" >/dev/null
  snap="$(cat "$SF")"
  bash "$REPAIR" --apply "$SF" >/dev/null
  [ "$(cat "$SF")" = "$snap" ]
}

@test "A7: dry-run (default) reports candidates and writes nothing" {
  before="$(cat "$SF")"
  run bash "$REPAIR" "$SF"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qi 'dry-run'
  [ "$(cat "$SF")" = "$before" ]
  [ ! -d "$MB/session/archive/pre-repair" ]
}

@test "A7: repair re-caps an over-long moved bullet (parity with A2)" {
  # append a giant post-Summary bullet
  printf -- '- 09:08 — User: "' >> "$SF"
  head -c 2000 /dev/zero | tr '\0' 'z' >> "$SF"
  printf '" · tools: Edit · files: d.go · ok\n' >> "$SF"
  bash "$REPAIR" --apply "$SF" >/dev/null
  # the giant bullet is capped: no single line exceeds ~610 chars
  maxlen="$(awk '{ if (length($0) > m) m = length($0) } END { print m+0 }' "$SF")"
  [ "$maxlen" -le 640 ]
}

@test "A7/sec: repair redacts secrets before the re-cap cut (no partial leak)" {
  # a post-Summary bullet carrying a raw secret must come out redacted, never split
  printf -- '- 09:08 — User: "leaked sk-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB here" · tools: Edit · files: d.go · ok\n' >> "$SF"
  bash "$REPAIR" --apply "$SF" >/dev/null
  if grep -q 'sk-B' "$SF"; then false; fi          # no raw secret fragment anywhere
  grep -q '\[REDACTED\]' "$SF"                       # replaced with the marker
}

@test "A7: no ## Summary → repair is a clean no-op (exit 0, unchanged)" {
  cat > "$SF" <<'EOF'
---
session_id: deadbeef-1111
summarized: false
---

## Live log
- 09:00 — User: "only turn" · tools: Edit · files: a.go · ok
EOF
  before="$(cat "$SF")"
  run bash "$REPAIR" --apply "$SF"
  [ "$status" -eq 0 ]
  [ "$(cat "$SF")" = "$before" ]
}

# --- prune byte-threshold repair-candidate flagging ---

@test "A7: prune flags a bloated file with post-Summary bullets as a repair candidate" {
  # a >40 KB file with a post-Summary turn-bullet
  bloat="$MB/session/2026-06-06_1000_11111111.md"
  { printf -- '---\nsession_id: aa\nsummarized: true\n---\n\n## Live log\n- 09:00 — User: "a" · tools: Edit · files: a.go · ok\n\n## Summary\ns\n- 09:05 — User: "'
    head -c 60000 /dev/zero | tr '\0' 'x'
    printf '" · tools: Edit · files: b.go · ok\n'; } > "$bloat"
  # a small clean substantive file (no post-Summary bullets)
  clean="$MB/session/2026-06-06_1001_22222222.md"
  cat > "$clean" <<'EOF'
---
session_id: bb
summarized: true
---

## Live log
- 09:00 — User: "small work" · tools: Edit · files: x.go · ok

## Summary
tidy summary
EOF
  run env CLAUDE_CODE_SESSION_ID= bash "$PRUNE" "$MB"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'repair-candidate: 2026-06-06_1000_11111111.md'
  if printf '%s\n' "$output" | grep -q 'repair-candidate: 2026-06-06_1001_22222222.md'; then false; fi
}
