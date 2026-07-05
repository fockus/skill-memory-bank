#!/usr/bin/env bats
# Tests for adapters/cline.sh — Cline VS Code extension adapter.
#
# Contract:
#   adapters/cline.sh install [PROJECT_ROOT]
#   adapters/cline.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/.clinerules/memory-bank.md     — rules (Cline reads all *.md in dir)
#   <project>/.clinerules/hooks/before-tool.sh     — beforeToolExecution
#   <project>/.clinerules/hooks/after-tool.sh      — afterToolExecution (auto-capture)
#   <project>/.clinerules/hooks/on-notification.sh — onNotification (compact reminder)
#   <project>/.clinerules/.mb-manifest.json        — ownership tracking
#
# Cline has native shell-script hooks (.clinerules/hooks/ discovery).
# Events: beforeToolExecution, afterToolExecution, onNotification.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/cline.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "cline: install creates .clinerules/memory-bank.md with workflow section" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  grep -qi "memory bank" "$PROJECT/.clinerules/memory-bank.md"
  grep -qi "workflow" "$PROJECT/.clinerules/memory-bank.md"
}

@test "cline: install creates 3 executable hook scripts" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
  [ -x "$PROJECT/.clinerules/hooks/after-tool.sh" ]
  [ -x "$PROJECT/.clinerules/hooks/on-notification.sh" ]
}

# A16 (M-8): hook scripts (+ the rules file) used to be clobbered with a
# plain `>` redirect — no backup of a user-modified copy, and non-atomic (a
# crash mid-write would leave a truncated hook script that then fails/aborts
# on every tool call until manually fixed).
@test "cline: install backs up an existing user-modified hook script before overwriting (A16)" {
  mkdir -p "$PROJECT/.clinerules/hooks"
  cat > "$PROJECT/.clinerules/hooks/before-tool.sh" <<'EOF'
#!/usr/bin/env bash
# USER_CUSTOM_HOOK_MARKER
exit 0
EOF
  chmod +x "$PROJECT/.clinerules/hooks/before-tool.sh"

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  local hook="$PROJECT/.clinerules/hooks/before-tool.sh"
  [ -x "$hook" ]
  # Freshly generated (user customization is gone from the live file)...
  ! grep -q "USER_CUSTOM_HOOK_MARKER" "$hook"
  # ...but recoverable via a backup.
  local found=0
  for b in "$hook".pre-mb-backup.*; do
    [ -f "$b" ] && grep -q "USER_CUSTOM_HOOK_MARKER" "$b" && found=1
  done
  [ "$found" -eq 1 ]
}

@test "cline: install does not leave stray tmp files after writing hooks (A16 atomic write)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local stray
  stray=$(find "$PROJECT/.clinerules/hooks" -maxdepth 1 -type f \
    ! -name 'before-tool.sh' ! -name 'after-tool.sh' ! -name 'on-notification.sh' \
    ! -name '*.pre-mb-backup.*' | wc -l | tr -d ' ')
  [ "$stray" -eq 0 ]
}

@test "cline: install writes manifest with adapter=cline and event mappings" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.clinerules/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "cline"' "$m" >/dev/null
  jq -e '.files | length >= 4' "$m" >/dev/null
  jq -e '.hooks_events | index("beforeToolExecution")' "$m" >/dev/null
  jq -e '.hooks_events | index("afterToolExecution")' "$m" >/dev/null
}

@test "cline: install idempotent — 2x run works cleanly" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ -x "$PROJECT/.clinerules/hooks/before-tool.sh" ]
}

@test "cline: install fails if project root missing" {
  run_adapter install "/nonexistent/xyz"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Hook behavior
# ═══════════════════════════════════════════════════════════════

@test "cline: after-tool hook appends auto-capture to progress.md (idempotent per session)" {
  run_adapter install "$PROJECT"
  # Simulate Cline afterToolExecution event with sessionId
  local payload='{"sessionId":"cline-abc12345","toolName":"read_file"}'
  (cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/after-tool.sh)
  grep -q "Auto-capture.*cline-abc12345" "$PROJECT/.memory-bank/progress.md"

  # Second fire with same session → no duplicate
  (cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/after-tool.sh)
  local count
  count=$(grep -c "Auto-capture.*cline-abc12345" "$PROJECT/.memory-bank/progress.md")
  [ "$count" -eq 1 ]
}

@test "cline: after-tool hook noop if no .memory-bank/" {
  run_adapter install "$PROJECT"
  rm -rf "$PROJECT/.memory-bank"
  (cd "$PROJECT" && echo '{"sessionId":"x"}' | bash .clinerules/hooks/after-tool.sh)
  [ "$status" -eq 0 ] || true  # must not fail
}

@test "cline: before-tool hook blocks rm -rf command (exit non-zero)" {
  run_adapter install "$PROJECT"
  local payload='{"toolName":"execute_command","params":{"command":"rm -rf /"}}'
  local rc
  rc=$(cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/before-tool.sh >/dev/null 2>&1; echo $?)
  [ "$rc" -ne 0 ]
}

@test "cline: before-tool hook allows safe commands (exit 0)" {
  run_adapter install "$PROJECT"
  local payload='{"toolName":"execute_command","params":{"command":"ls"}}'
  local rc
  rc=$(cd "$PROJECT" && echo "$payload" | bash .clinerules/hooks/before-tool.sh >/dev/null 2>&1; echo $?)
  [ "$rc" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "cline: uninstall removes all our files and manifest" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.clinerules/memory-bank.md" ]
  [ ! -f "$PROJECT/.clinerules/hooks/before-tool.sh" ]
  [ ! -f "$PROJECT/.clinerules/.mb-manifest.json" ]
}

@test "cline: uninstall preserves user-owned .clinerules/*.md files" {
  run_adapter install "$PROJECT"
  echo "custom cline rules" > "$PROJECT/.clinerules/user-rules.md"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules/user-rules.md" ]
  [ ! -f "$PROJECT/.clinerules/memory-bank.md" ]
}

@test "cline: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — MB_PATH resolver-aware)
# ═══════════════════════════════════════════════════════════════

@test "cline: after-tool hook contains MB_PATH resolver tiering" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hook="$PROJECT/.clinerules/hooks/after-tool.sh"
  [ -f "$hook" ]
  # Must check MB_PATH env override before falling back to local path
  grep -q "MB_PATH" "$hook"
}

@test "cline: on-notification hook contains MB_PATH resolver tiering" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local hook="$PROJECT/.clinerules/hooks/on-notification.sh"
  [ -f "$hook" ]
  # Compact reminder must also resolve bank path via MB_PATH
  grep -q "MB_PATH" "$hook"
}

@test "cline: after-tool hook with MB_PATH env uses overridden bank location" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Create a global bank in a separate location
  local global_bank
  global_bank="$(mktemp -d)"
  echo '# Progress' > "$global_bank/progress.md"
  # Remove local .memory-bank so it would normally be a no-op
  rm -rf "$PROJECT/.memory-bank"
  # Fire hook with MB_PATH pointing to global bank (env passed to bash, not echo)
  # Use a short session ID so prefix truncation does not affect pattern matching
  local payload='{"sessionId":"cline-glbl1234","toolName":"read_file"}'
  (cd "$PROJECT" && printf '%s' "$payload" | MB_PATH="$global_bank" bash .clinerules/hooks/after-tool.sh)
  # SID "cline-glbl1234" → strip "cline-" → "glbl1234" → prefix "glbl1234"
  grep -q "Auto-capture.*cline-glbl1234" "$global_bank/progress.md"
  rm -rf "$global_bank"
}

# ═══════════════════════════════════════════════════════════════
# A8 (H-6): .clinerules as a plain FILE (Cline supports file or dir)
# ═══════════════════════════════════════════════════════════════

@test "cline: install handles .clinerules as a plain file (no crash, preserves user content)" {
  printf '# My existing cline rules\nUSER_RULE_MARKER\n' > "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules" ]
  grep -q "USER_RULE_MARKER" "$PROJECT/.clinerules"
  grep -qi "memory bank" "$PROJECT/.clinerules"
}

@test "cline: uninstall strips MB block from file-form .clinerules, keeps user content" {
  printf '# My existing cline rules\nUSER_RULE_MARKER\n' > "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.clinerules" ]
  grep -q "USER_RULE_MARKER" "$PROJECT/.clinerules"
  ! grep -qi "memory bank" "$PROJECT/.clinerules"
}

@test "cline: file-form re-install does not accumulate blank lines (whole-file idempotent)" {
  printf 'USER\n' > "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  a=$(wc -l < "$PROJECT/.clinerules")
  run_adapter install "$PROJECT"
  b=$(wc -l < "$PROJECT/.clinerules")
  [ "$a" = "$b" ]
}

@test "cline: file-form preserves a .clinerules symlink (writes through to target)" {
  printf 'USER_SHARED\n' > "$PROJECT/shared-rules.md"
  ln -s shared-rules.md "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -L "$PROJECT/.clinerules" ]
  grep -qi "memory bank" "$PROJECT/shared-rules.md"
  grep -q "USER_SHARED" "$PROJECT/shared-rules.md"
}

@test "cline: file-form install+uninstall is byte-exact for a file with trailing blank lines" {
  printf 'USER\n\n\n' > "$PROJECT/.clinerules"
  before=$(cksum < "$PROJECT/.clinerules")
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  after=$(cksum < "$PROJECT/.clinerules")
  [ "$before" = "$after" ]
}

@test "cline: file-form preserves a MULTI-HOP .clinerules symlink chain" {
  printf 'USER_SHARED\n' > "$PROJECT/real-target.md"
  ln -s real-target.md "$PROJECT/link2.md"
  ln -s link2.md "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -L "$PROJECT/.clinerules" ]
  [ -L "$PROJECT/link2.md" ]
  grep -qi "memory bank" "$PROJECT/real-target.md"
  grep -q "USER_SHARED" "$PROJECT/real-target.md"
}

@test "cline: file-form preserves the .clinerules file mode across rewrite" {
  printf 'USER\n' > "$PROJECT/.clinerules"
  chmod 664 "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  m=$(stat -f '%Lp' "$PROJECT/.clinerules" 2>/dev/null || stat -c '%a' "$PROJECT/.clinerules" 2>/dev/null)
  [ "$m" = "664" ]
}

# ═══════════════════════════════════════════════════════════════
# R2a-1: file-form backup safety-net + corrupted-marker data-safety
# ═══════════════════════════════════════════════════════════════

@test "cline: file-form takes a backup of .clinerules before rewriting" {
  printf 'USER_ORIG\n' > "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  found=0
  for b in "$PROJECT"/.clinerules.pre-mb-backup.*; do
    [ -f "$b" ] && grep -q USER_ORIG "$b" && found=1
  done
  [ "$found" = "1" ]
}

@test "cline: uninstall preserves user content after a corrupted (END-less) MB block" {
  printf 'USER_BEFORE\n' > "$PROJECT/.clinerules"
  run_adapter install "$PROJECT"
  grep -v "memory-bank-cline:end" "$PROJECT/.clinerules" > "$PROJECT/.tmp" && mv "$PROJECT/.tmp" "$PROJECT/.clinerules"
  printf 'USER_AFTER\n' >> "$PROJECT/.clinerules"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q "USER_BEFORE" "$PROJECT/.clinerules"
  grep -q "USER_AFTER" "$PROJECT/.clinerules"
}
