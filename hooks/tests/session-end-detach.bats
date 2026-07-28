#!/usr/bin/env bats
# The detach introduced by 61d922c: mb-session-end.sh must return immediately and
# finish the summariser/judge work in a background child.
#
# This behaviour had no test of its own, and that gap is exactly how it silently
# broke 22 assertions across four files: every one of them read the session file
# straight after invoking the hook, which now returns before the file is written.
# Two properties are asserted here, because either alone can pass while the
# feature is broken — a hook that returns fast and never finishes the work looks
# identical to a working one until the next session reads the artefact.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-end.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  command -v jq >/dev/null || skip "jq required"

  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes" "$TMP/bin"
  cp "$FIX/transcript-two-turns.jsonl" "$TMP/t.jsonl"

  SF="$MB/session/2026-06-06_1835_af0a3685.md"
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript: $TMP/t.jsonl
started: 2026-06-06T18:35Z
branch: dev
turns: 1
summarized: false
---

## Live log
- 18:36 — User: "fix the flaky upload test" · tools: Edit · files: src/upload.py
EOF

  # A summariser stub that is SLOW on purpose: without it a fast machine could
  # finish the child before the parent returns, and the timing assertion would
  # pass even if the hook ran synchronously.
  cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null 2>&1 || true
sleep 2
printf '%s\n' \
'### What changed
- Fixed the flaky upload test in src/upload.py

### Decisions
- (none)

### Open questions
- (none)

### Files
- src/upload.py'
EOF
  chmod +x "$TMP/bin/claude"

  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8"}' "$PROJ" > "$TMP/in.json"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

@test "session-end detach: the hook returns before the slow summariser finishes" {
  local started ended elapsed
  started=$(date +%s)
  run bash -c "CLAUDE='$TMP/bin/claude' MB_SESSION_JUDGE=off bash '$HOOK' < '$TMP/in.json'"
  ended=$(date +%s)
  [ "$status" -eq 0 ]

  elapsed=$((ended - started))
  # The stub sleeps 2s. Returning in under that proves the parent did not wait.
  [ "$elapsed" -lt 2 ]
}

@test "session-end detach: the detached child still writes the summary" {
  run bash -c "CLAUDE='$TMP/bin/claude' MB_SESSION_JUDGE=off bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]

  # Returning fast is only half the contract: the work must actually land.
  local waited=0
  while [ "$waited" -lt 30 ]; do
    grep -q "^summarized: true$" "$SF" && break
    sleep 1
    waited=$((waited + 1))
  done

  grep -q "^summarized: true$" "$SF"
  grep -q "^## Summary$" "$SF"
  grep -q "Fixed the flaky upload test" "$SF"
}

@test "session-end detach: the re-entry guard runs the work in-process (no second fork)" {
  # With the guard set the hook must do the work itself — this is the seam the
  # other session-end suites rely on to stay deterministic.
  run bash -c "MB_SESSION_END_DETACHED=1 CLAUDE='$TMP/bin/claude' MB_SESSION_JUDGE=off bash '$HOOK' < '$TMP/in.json'"
  [ "$status" -eq 0 ]

  # No polling: if the guard forked, this read would race and fail.
  grep -q "^summarized: true$" "$SF"
  grep -q "^## Summary$" "$SF"
}
