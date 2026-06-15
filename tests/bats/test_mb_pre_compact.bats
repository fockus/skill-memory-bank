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
  # Stub spawns TWO levels of child using explicit bash -c subshells so each
  # process correctly records its OWN PID (not the parent's).
  # Tree structure: hook-worker (stub) → C1 (bash grandchild) → C2 (bash great-grandchild).
  # After hook times out, BOTH C1 and C2 must be dead — verified via kill -0 liveness.
  # With the buggy pkill-P-only implementation, killing the stub (direct worker) leaves
  # C1 alive, so C2 is never reached.  The correct recursive-BFS kill kills all levels.
  local pid_c1="$PROJECT/pid_c1"
  local pid_c2="$PROJECT/pid_c2"
  local stub="$PROJECT/deep-spawning-handoff.sh"
  # Use printf not heredoc to avoid quoting landmines with nested $$ expansions.
  printf '#!/usr/bin/env bash\n' > "$stub"
  printf '# Level 1: spawn a grandchild that spawns a great-grandchild.\n' >> "$stub"
  printf 'bash -c "echo \$\$ > %s; bash -c '"'"'echo \$\$ > %s; sleep 60'"'"' & sleep 60" &\n' \
    "$pid_c1" "$pid_c2" >> "$stub"
  printf 'sleep 60\n' >> "$stub"
  chmod +x "$stub"

  # Run hook with a 1s budget so it times out.
  run_hook_split MB_HANDOFF_SCRIPT="$stub" MB_PRECOMPACT_BUDGET=1
  [ "$status" -eq 0 ]
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]

  # Wait up to 2 s for the stub to write PID files (it has 1s budget + kill latency).
  local i=0
  while [ "$i" -lt 20 ] && { [ ! -f "$pid_c1" ] || [ ! -f "$pid_c2" ]; }; do
    sleep 0.1
    i=$(( i + 1 ))
  done

  local c1 c2
  c1="$(cat "$pid_c1" 2>/dev/null || true)"
  c2="$(cat "$pid_c2" 2>/dev/null || true)"

  # The test proves NOTHING unless both PIDs were actually captured.  Without these
  # hard assertions the kill -0 checks could be skipped (empty PID) and the test
  # would pass even if the deep-kill were broken — a tautological test.
  [ -n "$c1" ] || { echo "C1 PID never captured — test cannot prove deep kill" >&2; false; }
  [ -n "$c2" ] || { echo "C2 PID never captured — test cannot prove deep kill" >&2; false; }
  [[ "$c1" =~ ^[0-9]+$ ]] || { echo "C1 PID not numeric: '$c1'" >&2; false; }
  [[ "$c2" =~ ^[0-9]+$ ]] || { echo "C2 PID not numeric: '$c2'" >&2; false; }

  # Brief grace period for any remaining cleanup to propagate.
  sleep 0.3

  # Assert BOTH levels are dead (unconditional — PIDs are proven captured above).
  # kill -0 returns non-zero for a dead PID.
  ! kill -0 "$c1" 2>/dev/null || { echo "C1 (pid $c1) still alive — tree kill failed" >&2; false; }
  ! kill -0 "$c2" 2>/dev/null || { echo "C2 (pid $c2) still alive — deep grandchild not killed" >&2; false; }
}

@test "pre-compact: invalid MB_PRECOMPACT_BUDGET (non-numeric) → exit 0, WARN, never aborts" {
  # Non-numeric budget must NOT cause an arithmetic error under set -uo pipefail.
  # A broken hook would exit 127 (unbound-var) or exit 1 (arithmetic fail),
  # violating the never-block contract.  A correct hook validates first and
  # falls back to the default budget, staying on the exit-0 path.
  run_hook_split MB_HANDOFF_SCRIPT="$REPO_ROOT/scripts/mb-handoff.sh" MB_PRECOMPACT_BUDGET=abc
  [ "$status" -eq 0 ]
  # Must emit a WARN about the invalid budget value.
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]
}

@test "pre-compact: multi-line MB_PRECOMPACT_BUDGET → exit 0, WARN, never aborts" {
  # A multi-line value like $'1\nabc' would PASS a line-based grep -qE '^[0-9]+$'
  # (the first line "1" matches), then reach `$(( BUDGET * 100 ))` and abort under
  # set -uo pipefail.  Whole-string `case` validation must reject it and fall back
  # to the default budget, staying on the exit-0 path (never-block contract).
  local multiline=$'1\nabc'
  run_hook_split MB_HANDOFF_SCRIPT="$REPO_ROOT/scripts/mb-handoff.sh" MB_PRECOMPACT_BUDGET="$multiline"
  [ "$status" -eq 0 ]
  [[ "$stderr_text" == *"WARN"* ]] || [[ "$stderr_text" == *"warn"* ]]
}

@test "pre-compact: every pathological MB_PRECOMPACT_BUDGET → exit 0 (never aborts)" {
  # Exhaustive sweep over the input domain that could abort `$(( BUDGET * 100 ))`:
  #   - leading-zero octal (08, 09): all-digit but invalid octal → "value too great
  #     for base" → unbound `deadline` → abort.  Must normalize with 10#.
  #   - overflow (7+ digits): exceeds bash 64-bit arithmetic.  Must reject by length.
  #   - zero forms (0, 00): not a positive integer.
  # Each MUST stay on the exit-0 never-block path.  A valid budget (3) is the control.
  local v
  for v in 08 09 010 099999 0000 00 7654321 99999999999999999999 3; do
    run_hook_split MB_HANDOFF_SCRIPT="$REPO_ROOT/scripts/mb-handoff.sh" MB_PRECOMPACT_BUDGET="$v"
    [ "$status" -eq 0 ] || { echo "MB_PRECOMPACT_BUDGET='$v' aborted hook (status=$status)" >&2; false; }
  done
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
