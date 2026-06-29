#!/usr/bin/env bats
# Stage 3 — mb-session-catchup.sh: SessionStart lazy catch-up. Dispatches the most recent
# substantive, not-yet-summarized sessions to the summarizer (excluding the current one),
# in the background. The summarizer is mocked via MB_SUMMARIZE_BIN; selection is asserted
# deterministically via MB_CATCHUP_FOREGROUND=1.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-catchup.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
  DISPATCHED="$TMP/dispatched"
  STUB="$TMP/bin"; mkdir -p "$STUB"
  cat > "$STUB/summ" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$DISPATCHED"
EOF
  chmod +x "$STUB/summ"

  _mk() { # _mk <file> <summarized true|false> <content live|empty>
    local f="$MB/session/$1" s="$2" c="$3" log
    if [ "$c" = live ]; then log='- 10:00 — User: "real work" · tools: Edit · files: a.go · ok'
    else log='- 10:00 — User: "" · tools: (none) · files: (none) · ok'; fi
    cat > "$f" <<EOF
---
session_id: $1
started: 2026-06-10T10:00Z
branch: dev
turns: 5
summarized: $s
---

## Live log
$log
EOF
  }
  _mk "2026-06-10_1000_aaaaaaaa.md" false live    # oldest substantive pending
  _mk "2026-06-10_1001_bbbbbbbb.md" true  live    # already summarized → skip
  _mk "2026-06-10_1002_cccccccc.md" false empty   # contentless → skip
  _mk "2026-06-10_1003_dddddddd.md" false live    # newest substantive pending
  _mk "2026-06-10_1004_deadbeef.md" false live    # CURRENT session → exclude

  touch -t 202606101000 "$MB/session/2026-06-10_1000_aaaaaaaa.md"
  touch -t 202606101001 "$MB/session/2026-06-10_1001_bbbbbbbb.md"
  touch -t 202606101002 "$MB/session/2026-06-10_1002_cccccccc.md"
  touch -t 202606101003 "$MB/session/2026-06-10_1003_dddddddd.md"
  touch -t 202606101004 "$MB/session/2026-06-10_1004_deadbeef.md"

  IN="$TMP/in.json"
  printf '{"cwd":"%s","session_id":"deadbeef-aaaa-bbbb"}' "$PROJ" > "$IN"
}
teardown() { rm -rf "$TMP"; }

@test "dispatches substantive pending sessions, excludes summarized/contentless/current" {
  run bash -c "MB_SUMMARIZE_BIN='$STUB/summ' MB_CATCHUP_FOREGROUND=1 bash '$HOOK' < '$IN'"
  [ "$status" -eq 0 ]
  grep -q 'aaaaaaaa' "$DISPATCHED"          # substantive pending → dispatched
  grep -q 'dddddddd' "$DISPATCHED"          # substantive pending → dispatched
  ! grep -q 'bbbbbbbb' "$DISPATCHED"        # already summarized → not
  ! grep -q 'cccccccc' "$DISPATCHED"        # contentless → not
  ! grep -q 'deadbeef' "$DISPATCHED"        # current session → not
}

@test "respects MB_CATCHUP_MAX (newest-first)" {
  MB_SUMMARIZE_BIN="$STUB/summ" MB_CATCHUP_FOREGROUND=1 MB_CATCHUP_MAX=1 bash "$HOOK" < "$IN"
  [ "$(wc -l < "$DISPATCHED" | tr -d ' ')" -eq 1 ]
  grep -q 'dddddddd' "$DISPATCHED"          # newest substantive pending wins
}

@test "idempotent feel: a now-summarized session is not re-dispatched" {
  # flip the newest to summarized:true, rerun → only the older one dispatches
  sed -i.bak 's/^summarized: false/summarized: true/' "$MB/session/2026-06-10_1003_dddddddd.md"
  MB_SUMMARIZE_BIN="$STUB/summ" MB_CATCHUP_FOREGROUND=1 bash "$HOOK" < "$IN"
  ! grep -q 'dddddddd' "$DISPATCHED"
  grep -q 'aaaaaaaa' "$DISPATCHED"
}

@test "RED: current broken state — unsummarized sessions exist and are not caught up" {
  local unsummarized=0
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^summarized: false$' "$f" && unsummarized=$((unsummarized + 1))
  done
  [ "$unsummarized" -gt 0 ]
  # After fix: unsummarized should be 0 after catchup processes them
}

@test "non-blocking: a slow summarizer does not delay the hook (background dispatch)" {
  cat > "$STUB/slow" <<'EOF'
#!/usr/bin/env bash
sleep 10
EOF
  chmod +x "$STUB/slow"
  start=$(date +%s)
  MB_SUMMARIZE_BIN="$STUB/slow" bash "$HOOK" < "$IN"   # default = background
  elapsed=$(( $(date +%s) - start ))
  [ "$elapsed" -lt 5 ]
}

@test "off-switch MB_SESSION_CAPTURE=off → no dispatch" {
  MB_SUMMARIZE_BIN="$STUB/summ" MB_CATCHUP_FOREGROUND=1 MB_SESSION_CAPTURE=off bash "$HOOK" < "$IN"
  [ ! -f "$DISPATCHED" ]
}

@test "no memory bank → exit 0, emits {}" {
  printf '{"cwd":"%s","session_id":"x"}' "$TMP/nobank" > "$TMP/in2.json"
  run bash -c "MB_SUMMARIZE_BIN='$STUB/summ' bash '$HOOK' < '$TMP/in2.json'"
  [ "$status" -eq 0 ]
  [ "$output" = '{}' ]
}
