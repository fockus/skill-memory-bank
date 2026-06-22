#!/usr/bin/env bats
# Stage 1 — mb-settings-ensure-timeout.py: surgically add a per-command `timeout` to the
# SessionEnd `mb-session-end.sh` hook so the Haiku summary is not SIGKILLed at the default
# ~60s SessionEnd window (observed: 76s for a 64-turn Live log). Format-preserving + idempotent.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"        # skill root
  TOOL="$BIN/scripts/mb-settings-ensure-timeout.py"
  TMP="$(mktemp -d)"
  SETTINGS="$TMP/settings.json"
  # Minimal settings with a SessionEnd block lacking any timeout + a sentinel to prove
  # the rest of the file is left untouched.
  cat > "$SETTINGS" <<'EOF'
{
  "sentinelKeep": "do-not-touch",
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/mb-session-end.sh # [memory-bank-skill]"
          },
          {
            "type": "command",
            "command": "~/.claude/hooks/session-end-autosave.sh # [memory-bank-skill]"
          }
        ]
      }
    ]
  }
}
EOF
}
teardown() { rm -rf "$TMP"; }

@test "adds timeout=240 to the mb-session-end SessionEnd hook (REQ-Stage1)" {
  run python3 "$TOOL" "$SETTINGS" 240
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS"   # valid JSON
  t="$(jq '.hooks.SessionEnd[0].hooks[] | select(.command|test("mb-session-end")) | .timeout' "$SETTINGS")"
  [ "$t" -ge 180 ]
}

@test "leaves session-end-autosave untouched (no timeout)" {
  python3 "$TOOL" "$SETTINGS" 240
  t="$(jq '.hooks.SessionEnd[0].hooks[] | select(.command|test("autosave")) | .timeout' "$SETTINGS")"
  [ "$t" = "null" ]
}

@test "preserves the rest of the file (sentinel + command intact)" {
  python3 "$TOOL" "$SETTINGS" 240
  grep -q '"sentinelKeep": "do-not-touch"' "$SETTINGS"
  grep -q 'mb-session-end.sh # \[memory-bank-skill\]' "$SETTINGS"
}

@test "idempotent: second run does not duplicate or change the timeout" {
  python3 "$TOOL" "$SETTINGS" 240
  first="$(cat "$SETTINGS")"
  run python3 "$TOOL" "$SETTINGS" 240
  [ "$status" -eq 0 ]
  [ "$(cat "$SETTINGS")" = "$first" ]
  # exactly one timeout key under SessionEnd
  [ "$(jq '[.hooks.SessionEnd[0].hooks[] | select(.timeout!=null)] | length' "$SETTINGS")" -eq 1 ]
}

@test "missing settings file → non-zero, no crash" {
  run python3 "$TOOL" "$TMP/nope.json" 240
  [ "$status" -ne 0 ]
}

@test "supports bare hooks fragment shape (top-level SessionEnd, as in settings/hooks.json)" {
  FRAG="$TMP/frag.json"
  cat > "$FRAG" <<'EOF'
{
  "SessionEnd": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "~/.claude/hooks/mb-session-end.sh # [memory-bank-skill]"
        }
      ]
    }
  ]
}
EOF
  run python3 "$TOOL" "$FRAG" 240
  [ "$status" -eq 0 ]
  t="$(jq '.SessionEnd[0].hooks[] | select(.command|test("mb-session-end")) | .timeout' "$FRAG")"
  [ "$t" -ge 180 ]
}
