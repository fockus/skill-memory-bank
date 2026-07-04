#!/usr/bin/env bats
# Stage 2 — mb-session-summarize.sh: the extracted Haiku summarizer (shared by SessionEnd and
# the SessionStart lazy catch-up). claude is mocked. Mirrors session-end-summary.bats so the
# behaviour is proven identical after the DRY extraction.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$BIN/mb-session-summarize.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
  SF="$MB/session/2026-06-06_1835_af0a3685.md"
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript: $TMP/none.jsonl
started: 2026-06-06T18:35Z
branch: dev
turns: 6
summarized: false
---

## Live log
- 18:36 — User: "do real work please" · tools: Edit,Bash · files: a.go · ok · +10/-2
EOF
  STUB="$TMP/bin"; mkdir -p "$STUB"
  CALLS="$TMP/calls"
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
echo call >> "$CALLS"
cat > /dev/null
echo "MOCK SUMMARY: user asked, work done"
EOF
  chmod +x "$STUB/claude"
  CLAUDE="$STUB/claude"
}
teardown() { rm -rf "$TMP"; }

@test "summary written, _recent updated, summarized=true (extracted summarizer)" {
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' '$SF'"
  [ "$status" -eq 0 ]
  grep -q '## Summary' "$SF"
  grep -q 'MOCK SUMMARY' "$SF"
  grep -q 'summarized: true' "$SF"
  grep -q 'af0a3685' "$MB/session/_recent.md"
  grep -q 'MOCK SUMMARY' "$MB/session/_recent.md"
}

@test "idempotent: second run does not re-summarize" {
  bash -c "CLAUDE='$CLAUDE' bash '$HOOK' '$SF'"
  bash -c "CLAUDE='$CLAUDE' bash '$HOOK' '$SF'"
  [ "$(grep -c '## Summary' "$SF")" -eq 1 ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
}

@test "empty-session guard: contentless Live log → no claude call, no summary" {
  cat > "$SF" <<EOF
---
session_id: af0a3685-3ee9-4db8
transcript: $TMP/none.jsonl
started: 2026-06-06T18:35Z
branch: dev
turns: 1
summarized: false
---

## Live log
- 18:36 — User: "" · tools: (none) · files: (none) · ok
EOF
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' '$SF'"
  [ "$status" -eq 0 ]
  ! grep -q '## Summary' "$SF"
  [ ! -f "$CALLS" ]
}

@test "missing claude → exit 0, no summary, summarized stays false" {
  run bash -c "CLAUDE='$TMP/nope' bash '$HOOK' '$SF'"
  [ "$status" -eq 0 ]
  ! grep -q '## Summary' "$SF"
  grep -q 'summarized: false' "$SF"
}

@test "missing session file → exit 0, no crash" {
  run bash -c "CLAUDE='$CLAUDE' bash '$HOOK' '$TMP/gone.md'"
  [ "$status" -eq 0 ]
}

# --- A6: lower the default summarizer input window to 60000 chars ---

# Seed a session file whose `## Live log` has real content and exceeds any window,
# so sc_build_summary_src takes the Live-log path and hits the final size cap.
_seed_big_livelog() {
  printf -- '---\nsession_id: x\ntranscript: /none\nsummarized: false\n---\n\n## Live log\n- 00:00 — User: "' > "$1"
  head -c 120000 /dev/zero | tr '\0' 'x' >> "$1"
  printf '" · tools: Edit · files: a.go · ok\n' >> "$1"
}

@test "A6: default summary window is 60000 with truncation marker" {
  sf="$TMP/big.md"; _seed_big_livelog "$sf"
  unset MB_SUMMARY_MAX_CHARS
  . "$BIN/lib/session-common.sh"
  src="$(sc_build_summary_src "$sf")"
  [ "${#src}" -le 60050 ]                 # 60000 cap + short marker overhead
  printf '%s' "$src" | grep -q '…\[transcript truncated for summary\]…'
}

@test "A6: MB_SUMMARY_MAX_CHARS override restores a larger window" {
  sf="$TMP/big.md"; _seed_big_livelog "$sf"
  . "$BIN/lib/session-common.sh"
  src="$( export MB_SUMMARY_MAX_CHARS=200000; sc_build_summary_src "$sf" )"
  [ "${#src}" -gt 60050 ]                 # 120K content fits a 200K window → not cut
  if printf '%s' "$src" | grep -q 'transcript truncated'; then false; fi
}
