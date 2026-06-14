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

# Stub `python3`: return semantic JSON for a `search` subcommand, otherwise delegate
# to the real interpreter so the recall-index bridge still runs.
_stub_python3() {
  local json="$1" real; real="$(command -v python3)"; mkdir -p "$STUB"
  cat > "$STUB/python3" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "search" ] && { printf '%s\n' '$json'; exit 0; }; done
exec "$real" "\$@"
EOF
  chmod +x "$STUB/python3"
}

@test "hybrid: semantic + lexical hits are fused into one compact index (REQ-SM-024, REQ-001)" {
  STUB="$TMP/stub"
  _stub_python3 '[{"score":0.8,"source":"notes/semx.md","kind":"note","text":"semantic hit about kamal","anchor":"p0"}]'
  printf '# semx\nsemantic hit about kamal\n' > "$MB/notes/semx.md"
  run env PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=auto bash "$HOOK" kamal
  [ "$status" -eq 0 ]
  # Fused compact index: both the semantic-only entry and the lexical entry appear.
  echo "$output" | grep -q 'semx'
  echo "$output" | grep -q 'kamal deploy ssl'
  echo "$output" | grep -q ' · '
  # The semantic hit's one-line summary must carry its RELEVANT text, not just the stem.
  echo "$output" | grep -q 'semantic hit about kamal'
}

@test "MB_SEMANTIC=off → semantic content suppressed, lexical kept (REQ-SM-021)" {
  STUB="$TMP/stub"
  _stub_python3 '[{"score":0.8,"source":"notes/semx.md","kind":"note","text":"should not appear","anchor":"p0"}]'
  run env PATH="$STUB:$PATH" CLAUDE_PROJECT_DIR="$PROJ" MB_SEMANTIC=off bash "$HOOK" kamal
  [ "$status" -eq 0 ]
  [[ "$output" != *"should not appear"* ]]
  echo "$output" | grep -q 'kamal deploy ssl'
}
