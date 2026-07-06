#!/usr/bin/env bats
# Security: <private> blocks must not reach session files or summary source.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-turn.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"
  mkdir -p "$PROJ/.memory-bank"
  # shellcheck source=hooks/lib/session-common.sh
  . "$BIN/lib/session-common.sh"
}

teardown() { rm -rf "$TMP"; }

@test "session_turn: strips private before persist" {
  cat > "$TMP/private.jsonl" <<'JSONL'
{"type":"user","uuid":"u-1","message":{"content":[{"type":"text","text":"hello <private>SECRET-XYZ</private> world"}]}}
JSONL
  printf '{"cwd":"%s","session_id":"af0a3685-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}'     "$PROJ" "$TMP/private.jsonl" > "$TMP/in.json"
  bash "$HOOK" < "$TMP/in.json"
  sf="$(ls "$PROJ/.memory-bank/session/"*.md)"
  grep -q '\[PRIVATE\]' "$sf"
  ! grep -q 'SECRET-XYZ' "$sf"
}

@test "summary_src: strips private blocks" {
  sf="$PROJ/.memory-bank/session/2026-06-06_1200_af0a3685.md"
  mkdir -p "$PROJ/.memory-bank/session"
  cat > "$sf" <<'MD'
---
session_id: af0a3685-3ee9-4db8
---
## Live log
- 12:00 — User: "see <private>HIDDEN</private> ok" · tools: Read · files:  · ok
MD
  run bash -c ". '$BIN/lib/session-common.sh'; sc_build_summary_src '$sf'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PRIVATE]"* ]]
  [[ ! "$output" == *"HIDDEN"* ]]
}

@test "session_turn: still redacts api key" {
  cat > "$TMP/key.jsonl" <<'JSONL'
{"type":"user","uuid":"u-2","message":{"content":[{"type":"text","text":"use sk-abcdefghijklmnopqrstuvwxyz1234567890"}]}}
JSONL
  printf '{"cwd":"%s","session_id":"b1b1b1b1-3ee9-4db8","transcript_path":"%s","stop_hook_active":false}'     "$PROJ" "$TMP/key.jsonl" > "$TMP/keyin.json"
  bash "$HOOK" < "$TMP/keyin.json"
  sf="$(ls "$PROJ/.memory-bank/session/"*b1b1b1b1*.md 2>/dev/null || ls "$PROJ/.memory-bank/session/"*.md | tail -1)"
  grep -q '\[REDACTED\]' "$sf"
  ! grep -q 'sk-abcdefghijklmnopqrstuvwxyz1234567890' "$sf"
}
