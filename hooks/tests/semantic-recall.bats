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

# Stub `python3`: return semantic JSON for a `search` subcommand, otherwise delegate
# to the real interpreter so the recall-index bridge (compact render) still runs.
_stub_python3() {
  local json="$1" real; real="$(command -v python3)"
  cat > "$STUB/python3" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "search" ] && { printf '%s\n' '$json'; exit 0; }; done
exec "$real" "\$@"
EOF
  chmod +x "$STUB/python3"
}

@test "injects the COMPACT Relevant Memory form when CLI returns matches" {
  body='kamal proxy host stored in keyring — then a very long trailing remainder padded out well past any summary cap so the index never carries the FORBIDDENTAILMARKER token verbatim into the prompt context window at all not even once here'
  printf '# a\n%s\n' "$body" > "$MB/notes/a.md"
  _stub_python3 '[{"score":0.9,"source":"notes/a.md","kind":"note","text":"'"$body"'","anchor":"p0"}]'
  run env PATH="$STUB:$PATH" MB_SEMANTIC=auto bash "$HOOK" <<< '{"prompt":"deploy","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Relevant Memory"* ]]
  # Compact form: the stable id (human-readable slug + short hash, anchor :p0), the
  # ' · ' separator, AND the relevant summary text.
  [[ "$output" =~ a-[0-9a-f]+:p0 ]]
  [[ "$output" == *" · "* ]]
  [[ "$output" == *"kamal proxy host"* ]]
  # Full chunk bodies are NOT injected verbatim — only the summarised compact line.
  [[ "$output" != *"FORBIDDENTAILMARKER"* ]]
}

@test "empty results → empty object" {
  _stub_python3 '[]'
  run env PATH="$STUB:$PATH" MB_SEMANTIC=auto bash "$HOOK" <<< '{"prompt":"zzz","cwd":"'"$PROJ"'"}'
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}
