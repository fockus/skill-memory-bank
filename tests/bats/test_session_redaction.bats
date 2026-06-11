#!/usr/bin/env bats
# sc_redact_secrets (hooks/lib/session-common.sh) — shell-side secret redaction
# for session capture. Keep the pattern set in sync with hooks/lib/redact.py.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=/dev/null
  . "$REPO_ROOT/hooks/lib/session-common.sh"
}

@test "redacts OpenRouter sk-or key" {
  out="$(printf 'auth failed: sk-or-v1-a1b2c3d4a1b2c3d4a1b2c3d4 rejected' | sc_redact_secrets)"
  [[ "$out" != *"sk-or-v1-a1b2"* ]]
  [[ "$out" == *"[REDACTED]"* ]]
  [[ "$out" == *"auth failed:"* ]]
}

@test "redacts Anthropic and OpenAI style sk- keys" {
  out="$(printf 'sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx and sk-proj-Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9Z9' | sc_redact_secrets)"
  [[ "$out" != *"sk-ant-"* ]]
  [[ "$out" != *"sk-proj-"* ]]
}

@test "redacts GitHub ghp_ token" {
  out="$(printf 'token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA used' | sc_redact_secrets)"
  [[ "$out" != *"ghp_AAAA"* ]]
  [[ "$out" == *"[REDACTED]"* ]]
}

@test "redacts AWS AKIA key and Slack xoxb token" {
  out="$(printf 'AKIAIOSFODNN7EXAMPLE / xoxb-1234567890-abcdefghijklm' | sc_redact_secrets)"
  [[ "$out" != *"AKIAIOSFODNN7EXAMPLE"* ]]
  [[ "$out" != *"xoxb-"* ]]
}

@test "keeps env var name, hides value" {
  out="$(printf 'export OPENROUTER_API_KEY=sk-or-v1-deadbeefdeadbeefdeadbeef' | sc_redact_secrets)"
  [[ "$out" == *"OPENROUTER_API_KEY="* ]]
  [[ "$out" != *"deadbeef"* ]]
}

@test "keeps Bearer prefix, hides token" {
  out="$(printf 'Authorization: Bearer abcdef1234567890abcdef1234567890' | sc_redact_secrets)"
  [[ "$out" == *"Bearer [REDACTED]"* ]]
  [[ "$out" != *"abcdef1234567890"* ]]
}

@test "leaves benign text untouched" {
  src='the skill-memory-bank repo: run /mb work my-feature and git push'
  out="$(printf '%s' "$src" | sc_redact_secrets)"
  [ "$out" = "$src" ]
}

@test "mb-session-turn.sh writes [REDACTED] instead of the key from user text" {
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB"
  # minimal transcript: one user turn whose text carries a fake OpenRouter key
  cat > "$TMP/transcript.jsonl" <<'EOF'
{"type":"user","uuid":"u-1","message":{"role":"user","content":"please use sk-or-v1-a1b2c3d4a1b2c3d4a1b2c3d4 for the call"}}
EOF
  printf '{"session_id":"feedbeef-0000-0000-0000-000000000000","cwd":"%s","transcript_path":"%s"}' \
    "$TMP" "$TMP/transcript.jsonl" \
    | bash "$REPO_ROOT/hooks/mb-session-turn.sh"
  sf="$(find "$MB/session" -name '*.md' | head -1)"
  [ -n "$sf" ]
  run grep -c "sk-or-v1-a1b2" "$sf"
  [ "$output" = "0" ]
  grep -q "\[REDACTED\]" "$sf"
  rm -rf "$TMP"
}

@test "MB_REDACT_SECRETS=off disables redaction" {
  out="$(printf 'key sk-or-v1-a1b2c3d4a1b2c3d4a1b2c3d4' | MB_REDACT_SECRETS=off sc_redact_secrets)"
  [[ "$out" == *"sk-or-v1-a1b2c3d4"* ]]
}
