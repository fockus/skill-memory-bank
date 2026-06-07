#!/usr/bin/env bats
# Task 6 — mb-semantic-recall.sh: UserPromptSubmit semantic injection (fail-safe).
# Hermetic: uses an isolated tmp Memory Bank WITHOUT a .venv, so the hook falls back to
# the stubbed `python3` in PATH (a real .venv/bin/python would otherwise shadow the stub).

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-semantic-recall.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/notes"
  STUB="$TMP/stub"; mkdir -p "$STUB"
}
teardown() { rm -rf "$TMP"; }

@test "MB_SEMANTIC=off → empty object, exit 0" {
  run env MB_SEMANTIC=off bash "$HOOK" <<< '{"prompt":"hi","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "MB_CAPTURE_SUBPROCESS set → exit 0 noop" {
  run env MB_CAPTURE_SUBPROCESS=1 bash "$HOOK" <<< '{"prompt":"hi","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "empty prompt → empty object" {
  run env MB_SEMANTIC=auto bash "$HOOK" <<< '{"prompt":"","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "injects Relevant Memory when CLI returns matches" {
  cat > "$STUB/python3" <<'EOF'
#!/usr/bin/env bash
echo '[{"score":0.9,"source":"notes/a.md","kind":"note","text":"kamal proxy host"}]'
EOF
  chmod +x "$STUB/python3"
  run env PATH="$STUB:$PATH" MB_SEMANTIC=auto bash "$HOOK" <<< '{"prompt":"deploy","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Relevant Memory"* ]]
  [[ "$output" == *"kamal proxy host"* ]]
}

@test "empty results → empty object" {
  cat > "$STUB/python3" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
  chmod +x "$STUB/python3"
  run env PATH="$STUB:$PATH" MB_SEMANTIC=auto bash "$HOOK" <<< '{"prompt":"zzz","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}
