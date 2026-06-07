#!/usr/bin/env bats
# Stage 6 — mb-recall.sh: ripgrep over session/ + notes/.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-recall.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes"
  printf '## session\n- User: "kamal deploy ssl" · tools: Bash\n' > "$MB/session/2026-06-06_1835_abc.md"
  printf '# flock locking note\nuse mkdir for portable locks\n' > "$MB/notes/2026-06-06_1900_lock.md"
}
teardown() { rm -rf "$TMP"; }

@test "recall finds match in session (REQ-SM-005)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK' kamal"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'kamal deploy ssl'
}

@test "recall finds match in notes (REQ-SM-005)" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK' mkdir"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'portable locks'
}

@test "recall no match → message, exit 0" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK' zzznotpresent"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no matches'
}

@test "empty query → usage, exit 0" {
  run bash -c "CLAUDE_PROJECT_DIR='$PROJ' bash '$HOOK'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'usage'
}

@test "unresolved MB → graceful message, exit 0" {
  mkdir -p "$TMP/nobank"
  run bash -c "CLAUDE_PROJECT_DIR='$TMP/nobank' bash '$HOOK' anything"
  [ "$status" -eq 0 ]
}

@test "hybrid: semantic section shown when CLI returns results, lexical kept (REQ-SM-024)" {
  STUB="$TMP/stub"; mkdir -p "$STUB"
  cat > "$STUB/python3" <<'EOF'
#!/usr/bin/env bash
echo '[{"score":0.8,"source":"notes/x.md","kind":"note","text":"semantic hit about kamal"}]'
EOF
  chmod +x "$STUB/python3"
  run env PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" kamal
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '## Semantic matches'
  echo "$output" | grep -q 'semantic hit about kamal'
  echo "$output" | grep -q '## Lexical matches'
  echo "$output" | grep -q 'kamal deploy ssl'
}

@test "MB_SEMANTIC=off → no semantic section, lexical only (REQ-SM-021)" {
  STUB="$TMP/stub"; mkdir -p "$STUB"
  cat > "$STUB/python3" <<'EOF'
#!/usr/bin/env bash
echo '[{"score":0.8,"source":"notes/x.md","kind":"note","text":"should not appear"}]'
EOF
  chmod +x "$STUB/python3"
  run env PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=off bash "$HOOK" kamal
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q '## Semantic matches'
  echo "$output" | grep -q 'kamal deploy ssl'
}
