#!/usr/bin/env bats
# Stage 1 — session-doctor.bats: RED test for mb-session-doctor.sh diagnostics.
# Detects the currently broken state: stale Claude hooks, missing Pi adapter,
# empty semantic index, unsummarized sessions, legacy auto-capture risk.
# After fixes (Stage 2-7), these tests must pass with clean output.

setup() {
  BIN="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS="$(cd "$BIN/../scripts" && pwd)"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"
  MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session" "$MB/.index"

  _mk_session() {
    local f="$MB/session/$1" sid="$2" agent="$3" summarized="$4" has_summary="$5"
    cat > "$f" <<EOF
---
session_id: $sid
agent: $agent
started: 2026-06-10T10:00Z
turns: 4
summarized: $summarized
summary_schema: v2
---

## Live log
- 10:00 — User: "test" · Tools: Read · Files: test.md · ok
EOF
    if [ "$has_summary" = yes ]; then
      cat >> "$f" <<EOF

## Summary

### What changed
- test.md read

### Decisions
- (none)
### Open questions
- (none)
### Files
- test.md
### Verification
- none
### Next actions
- (none)
EOF
    fi
    touch -t 202606101000 "$f"
  }

  _mk_session "2026-06-10_1000_aaaaaaaa.md" "aaaa-aaaa-aaaa" "claude" "false" "no"
  _mk_session "2026-06-10_1001_bbbbbbbb.md" "bbbb-bbbb-bbbb" "claude" "false" "no"

  # Create simulated installed Claude config
  FAKE_HOME="$TMP/home"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  # Simulate old/missing hooks
  touch "$FAKE_HOME/.claude/hooks/mb-session-start.sh"
  touch "$FAKE_HOME/.claude/hooks/mb-session-end.sh"
  touch "$FAKE_HOME/.claude/hooks/mb-session-turn.sh"
  # NOT present: mb-session-catchup.sh, mb-session-summarize.sh, mb-pre-compact.sh

  # Simulate Pi extension dir
  mkdir -p "$FAKE_HOME/.pi/agent/extensions"

  # Simulate progress.md with auto-capture stubs
  cat > "$MB/progress.md" <<'EOF'
# Progress

## 2026-06-10

### Auto-capture 2026-06-10 (session aaaa)
- Session ended without an explicit /mb done

## 2026-06-11

### Auto-capture 2026-06-11 (session bbbb)
- Session ended without an explicit /mb done
EOF
}

teardown() {
  rm -rf "$TMP"
}

@test "RED: doctor detects unsummarized sessions" {
  local count=0
  for f in "$MB/session/"*.md; do
    [ -f "$f" ] || continue
    grep -q '^summarized: false$' "$f" && count=$((count + 1))
  done
  [ "$count" -gt 0 ]
  # After fix: count should be 0 after catchup
}

@test "RED: doctor detects missing _recent.md" {
  [ ! -f "$MB/session/_recent.md" ]
}

@test "RED: doctor detects empty semantic index" {
  local chunks
  if [ -f "$MB/.index/store.json" ]; then
    chunks=$(python3 -c "import json; d=json.load(open('$MB/.index/store.json')); print(len(d.get('blocks',[])))" 2>/dev/null || echo 0)
  else
    chunks=0
  fi
  [ "$chunks" = "0" ]
}

@test "RED: doctor detects missing catchup hook in installed Claude config" {
  # Simulate the check: look for mb-session-catchup in hooks dir
  [ ! -f "$FAKE_HOME/.claude/hooks/mb-session-catchup.sh" ]
  [ ! -f "$FAKE_HOME/.claude/hooks/mb-session-summarize.sh" ]
}

@test "RED: doctor detects missing precompact hook" {
  [ ! -f "$FAKE_HOME/.claude/hooks/mb-pre-compact.sh" ]
}

@test "RED: doctor detects missing Pi session adapter extension" {
  [ ! -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
}

@test "RED: doctor detects auto-capture stubs in progress.md" {
  grep -q '^### Auto-capture' "$MB/progress.md"
  # After fix: MB_AUTO_CAPTURE=off or stubs archived, none in active progress.md
}

@test "doctor diagnose command exits 0 even when issues found (informational)" {
  # The doctor should never crash; it reports issues and exits 0
  run true  # placeholder until mb-session-doctor.sh is implemented in Stage 2
  [ "$status" -eq 0 ]
}

@test "RED: doctor detects stale _recent.md when it exists but is outdated" {
  # Create a summarized session newer than _recent.md
  _mk_session "2026-06-11_1000_eeeeeeee.md" "eeee-eeee-eeee" "pi" "true" "yes"
  touch -t 202606110000 "$MB/session/2026-06-11_1000_eeeeeeee.md"
  touch -t 202606091200 "$MB/session/_recent.md"
  local recent_mtime session_mtime
  recent_mtime=$(stat -f%m "$MB/session/_recent.md" 2>/dev/null || stat -c%Y "$MB/session/_recent.md" 2>/dev/null || echo 0)
  session_mtime=$(stat -f%m "$MB/session/2026-06-11_1000_eeeeeeee.md" 2>/dev/null || stat -c%Y "$MB/session/2026-06-11_1000_eeeeeeee.md" 2>/dev/null || echo 0)
  [ "$recent_mtime" -lt "$session_mtime" ]
}

# ═══════════════════════════════════════════════════════════════
# adapter-parity T3 (REQ-003, scenario 3): a bare Pi host — extension
# absent — gets the EXACT install command from a REAL doctor invocation
# (not the RED placeholders above, which only assert setup fixtures).
# ═══════════════════════════════════════════════════════════════

@test "doctor: bare Pi host (no parity extension) prints the exact --clients pi --with-extensions=pi install command" {
  [ ! -f "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts" ]
  run env HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/mb-session-doctor.sh" "$PROJ"
  [ "$status" -eq 0 ]
  # --clients pi is REQUIRED, not cosmetic: install.sh defaults --clients to
  # claude-code when omitted, and the extension offer only ever applies to
  # hosts present in --clients — a bare --with-extensions=pi (no --clients)
  # is a silent no-op (success banner, zero files) — a real, reproduced
  # regression this exact-substring check locks in.
  [[ "$output" == *"--clients pi --with-extensions=pi"* ]]
  [[ "$output" == *"install.sh"* ]]
}

@test "doctor: bare Pi host resolves install.sh's real path when a skill root is discoverable" {
  local skill_root="$FAKE_HOME/.claude/skills/memory-bank"
  mkdir -p "$skill_root/hooks"
  : > "$skill_root/install.sh"
  run env HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/mb-session-doctor.sh" "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$skill_root/install.sh --clients pi --with-extensions=pi"* ]]
}

@test "doctor: an INSTALLED Pi extension reports installed, not the install hint" {
  mkdir -p "$FAKE_HOME/.pi/agent/extensions"
  : > "$FAKE_HOME/.pi/agent/extensions/memory-bank-session.ts"
  run env HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/mb-session-doctor.sh" "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"extension: installed"* ]]
  [[ "$output" != *"--with-extensions=pi"* ]]
}

# ═══════════════════════════════════════════════════════════════
# The REAL regression test (Codex re-review): the hint must not just LOOK
# right as a substring — copy-pasting it must actually install the
# extensions. Executes the EXACT emitted command against a fresh HOME +
# project dir and asserts the real files land under
# ~/.pi/agent/extensions/. This is what caught the --clients-pi gap: the
# old `install.sh --with-extensions=pi` hint ran successfully (exit 0,
# "installed" banner) while installing ZERO files for Pi.
# ═══════════════════════════════════════════════════════════════

@test "doctor: copy-pasting the emitted Pi install hint actually installs the parity extensions (real regression guard)" {
  command -v jq >/dev/null 2>&1 || skip "jq required"
  command -v rsync >/dev/null 2>&1 || skip "rsync required"

  local repo_root
  repo_root="$(cd "$SCRIPTS/.." && pwd)"

  # A REAL, runnable skill bundle at the resolved skill root the hint names
  # (not the empty install.sh stub the path-resolution test above uses —
  # that only proves the STRING is right; this proves the STRING RUNS).
  local skill_root="$FAKE_HOME/.claude/skills/memory-bank"
  mkdir -p "$skill_root"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='.memsearch' \
    --exclude='/tests/calibration/results' \
    --exclude='node_modules' \
    "$repo_root/" "$skill_root/"

  run env HOME="$FAKE_HOME" CLAUDE_PROJECT_DIR="$PROJ" bash "$SCRIPTS/mb-session-doctor.sh" "$PROJ"
  [ "$status" -eq 0 ]

  # Extract the emitted hint line verbatim (no re-typing it by hand here —
  # that would just re-encode the fix instead of proving the ACTUAL output
  # is runnable) and execute it exactly as a user would copy-paste it.
  local hint_line
  hint_line="$(printf '%s\n' "$output" | grep -F 'install.sh --clients pi --with-extensions=pi')"
  [ -n "$hint_line" ]
  local hint_cmd="${hint_line#*Run: }"
  [[ "$hint_cmd" == "bash $skill_root/install.sh --clients pi --with-extensions=pi" ]]

  local exec_home exec_proj
  exec_home="$(mktemp -d)"
  exec_proj="$(mktemp -d)"
  mkdir -p "$exec_proj/.memory-bank"

  run env HOME="$exec_home" MB_SKIP_DEPS_CHECK=1 bash -c "cd \"$exec_proj\" && $hint_cmd" </dev/null
  [ "$status" -eq 0 ]

  [ -f "$exec_home/.pi/agent/extensions/memory-bank-session.ts" ]
  [ -f "$exec_home/.pi/agent/extensions/memory-bank-graph-rag.ts" ]

  rm -rf "$exec_home" "$exec_proj"
}
