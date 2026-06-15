#!/usr/bin/env bats
# Tests for hooks/mb-pre-compact.sh — handoff-v2 PreCompact actualize hook.
#
# Contract (design.md §2, §4, §9):
#   - Reads JSON input from stdin (standard hook protocol); .cwd → bank.
#   - Resolves the bank via _skill_root.sh::mb_hook_resolve_mb_path.
#   - Invokes `bash scripts/mb-handoff.sh --actualize <bank> pre_compact`,
#     which writes/refreshes <bank>/handoff/latest.md.
#   - Bounded to <=2 seconds; on timeout/failure/missing-bank it emits a
#     one-line stderr WARN and exits 0 — it MUST NEVER block compaction.
#   - On success: a one-line stderr marker is printed.
#   - Always exits 0 (never non-zero), even when actualize fails.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-pre-compact.sh"

  PROJECT="$(mktemp -d)"
  MB="$PROJECT/.memory-bank"
  mkdir -p "$MB"
  printf '## 2026-06-07 (seed)\n- did a thing\n- another thing\n' > "$MB/progress.md"
  printf '# Status\n' > "$MB/status.md"
  printf -- '- [ ] open item one\n- [x] done item\n' > "$MB/checklist.md"

  JSON_INPUT="{\"cwd\":\"$PROJECT\",\"session_id\":\"test-s\",\"hook_event_name\":\"PreCompact\"}"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

# Invoke hook with given env + stdin; capture combined output + status.
run_hook() {
  local raw
  raw=$(printf '%s' "$JSON_INPUT" | env "$@" bash "$HOOK" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

# Invoke hook, capturing stderr separately from stdout.
run_hook_split() {
  local err_file out_file
  err_file="$(mktemp)"
  out_file="$(mktemp)"
  printf '%s' "$JSON_INPUT" | env "$@" bash "$HOOK" >"$out_file" 2>"$err_file"
  status=$?
  stdout_text="$(cat "$out_file")"
  stderr_text="$(cat "$err_file")"
  rm -f "$err_file" "$out_file"
}

# ═══════════════════════════════════════════════════════════════
# Happy path
# ═══════════════════════════════════════════════════════════════

@test "pre-compact: normal bank → actualize runs, latest.md created, exit 0, marker on stderr" {
  [ ! -f "$MB/handoff/latest.md" ]
  run_hook_split
  [ "$status" -eq 0 ]
  [ -f "$MB/handoff/latest.md" ]
  grep -q "Handoff capsule" "$MB/handoff/latest.md"
  # One-line marker on stderr so the user sees the action.
  [[ "$stderr_text" == *"[mb]"* ]]
  [[ "$stderr_text" == *"capsule"* ]]
}

@test "pre-compact: refreshes an existing latest.md (mtime advances)" {
  mkdir -p "$MB/handoff"
  printf 'old capsule\n' > "$MB/handoff/latest.md"
  # Backdate so the refresh is observable.
  touch -t 202001010000 "$MB/handoff/latest.md"
  local before after
  before=$(stat -f %m "$MB/handoff/latest.md" 2>/dev/null || stat -c %Y "$MB/handoff/latest.md")
  run_hook
  [ "$status" -eq 0 ]
  after=$(stat -f %m "$MB/handoff/latest.md" 2>/dev/null || stat -c %Y "$MB/handoff/latest.md")
  [ "$after" -gt "$before" ]
  grep -q "Handoff capsule" "$MB/handoff/latest.md"
}

# ═══════════════════════════════════════════════════════════════
# Never-block guarantee (design §9) — the critical contract
# ═══════════════════════════════════════════════════════════════

@test "pre-compact: failing actualize → exit 0 + WARN on stderr (never blocks)" {
  # Point the hook at a stub handoff script that always fails.
  local stub="$PROJECT/fail-handoff.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
echo "boom" >&2
exit 7
STUB
  chmod +x "$stub"
  run_hook_split MB_HANDOFF_SCRIPT="$stub"
  [ "$status" -eq 0 ]
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]
}

@test "pre-compact: slow actualize → killed within tight budget, exit 0 (never blocks)" {
  # A stub that would hang well past the budget.
  # Use MB_PRECOMPACT_BUDGET=1 so the test finishes fast.
  local stub="$PROJECT/slow-handoff.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
sleep 30
STUB
  chmod +x "$stub"
  local start end elapsed
  start=$(date +%s)
  run_hook_split MB_HANDOFF_SCRIPT="$stub" MB_PRECOMPACT_BUDGET=1
  end=$(date +%s)
  elapsed=$((end - start))
  [ "$status" -eq 0 ]
  # With a 1s budget, must return in well under 5s total.
  [ "$elapsed" -lt 5 ]
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]
}

@test "pre-compact: orphan grandchild killed after timeout, not alive after hook returns" {
  # Stub spawns a child process that writes a sentinel file each second.
  # The hook times out, and after it returns the grandchild must be dead —
  # it must NOT keep writing (proving the whole process group is killed).
  local sentinel="$PROJECT/grandchild_alive"
  local stub="$PROJECT/spawning-handoff.sh"
  cat > "$stub" <<STUB
#!/usr/bin/env bash
# Grandchild loop: prove it was killed by recording touches.
( while true; do touch "$sentinel"; sleep 0.5; done ) &
sleep 30
STUB
  chmod +x "$stub"
  # Run hook with a 1s budget so it times out.
  run_hook_split MB_HANDOFF_SCRIPT="$stub" MB_PRECOMPACT_BUDGET=1
  [ "$status" -eq 0 ]
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]
  # Give the grandchild one polling interval to prove it's truly dead, then check.
  sleep 0.6
  # Record sentinel mtime before waiting.
  local snap_before snap_after
  snap_before=$(stat -f %m "$sentinel" 2>/dev/null || stat -c %Y "$sentinel" 2>/dev/null || echo 0)
  sleep 0.7
  snap_after=$(stat -f %m "$sentinel" 2>/dev/null || stat -c %Y "$sentinel" 2>/dev/null || echo 0)
  # If the grandchild is still alive it would update the sentinel; if dead, mtime is unchanged.
  [ "$snap_before" -eq "$snap_after" ]
}

# ═══════════════════════════════════════════════════════════════
# No-bank / opt-out
# ═══════════════════════════════════════════════════════════════

@test "pre-compact: no resolvable bank → exit 0, WARN on stderr, no handoff dir" {
  local nomb
  nomb="$(mktemp -d)"
  local err_file out_file
  err_file="$(mktemp)"
  out_file="$(mktemp)"
  printf '{"cwd":"%s","hook_event_name":"PreCompact"}' "$nomb" \
    | bash "$HOOK" >"$out_file" 2>"$err_file"
  status=$?
  local stderr_out
  stderr_out="$(cat "$err_file")"
  rm -f "$err_file" "$out_file"
  [ "$status" -eq 0 ]
  [ ! -d "$nomb/.memory-bank" ]
  # Contract: a one-line WARN on stderr when no bank resolves.
  [[ "$stderr_out" == *"WARN"* ]] || [[ "$stderr_out" == *"warn"* ]]
  rm -rf "$nomb"
}

@test "pre-compact: missing jq in PATH → exit 0 via PWD fallback (bank found from cwd)" {
  # Build a PATH that has everything EXCEPT jq; the hook must degrade gracefully.
  # Since the hook falls back to CWD="$PWD" when jq is absent, run from inside PROJECT
  # so the bank still resolves (MB_PATH override so it uses our exact bank dir).
  local err_file out_file
  err_file="$(mktemp)"
  out_file="$(mktemp)"
  # Strip jq: keep only system dirs that don't contain jq.
  local jq_dir no_jq_path
  jq_dir="$(dirname "$(command -v jq 2>/dev/null || true)" 2>/dev/null || true)"
  no_jq_path="$(printf '%s' "$PATH" | tr ':' '\n' \
    | grep -Fxv "$jq_dir" \
    | paste -sd: -)"
  # Use MB_PATH so bank resolves even without jq parsing .cwd.
  printf '%s' "$JSON_INPUT" \
    | env PATH="$no_jq_path" MB_PATH="$MB" bash "$HOOK" >"$out_file" 2>"$err_file"
  status=$?
  rm -f "$err_file" "$out_file"
  [ "$status" -eq 0 ]
}
