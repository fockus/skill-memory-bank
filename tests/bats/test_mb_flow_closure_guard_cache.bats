#!/usr/bin/env bats
# Light-mode verdict cache for the closure guard (MB_FLOW_VERIFY_CACHE).
# The firewall's verdict is a pure function of the working tree, so an unchanged
# tree may reuse the prior exit code instead of re-running the full (slow) check
# suite on every Stop. These tests use a self-contained git-backed project with a
# STUB firewall (a copy of the guard placed alongside a scripts/mb-flow-verify.sh
# that counts its invocations) — the real verify lives at a fixed sibling path and
# cannot be stubbed in-place.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROJ="$(mktemp -d)"
  RUNS="$(mktemp)"; : > "$RUNS"
  (
    cd "$PROJ"
    git init -q; git config user.email t@t; git config user.name t
    mkdir -p .memory-bank/tmp scripts hooks
    cat > scripts/mb-flow-verify.sh <<EOF
#!/usr/bin/env bash
echo x >> "$RUNS"
exit "\${MB_FV_RC:-1}"
EOF
    chmod +x scripts/mb-flow-verify.sh
    cp "$REPO_ROOT/hooks/mb-flow-closure-guard.sh" hooks/
    : > hooks/_skill_root.sh
    echo goal > .memory-bank/goal.md
    echo committed > tracked.txt
    git add -A; git commit -qm init
  )
  GUARD="$PROJ/hooks/mb-flow-closure-guard.sh"
  STDIN="$(printf '{"stop_hook_active":false,"cwd":"%s"}' "$PROJ")"
}

teardown() {
  [ -n "$PROJ" ] && rm -rf "$PROJ"
  [ -n "$RUNS" ] && rm -f "$RUNS"
}

_run_guard() { # $1 = MB_FV_RC for the stub; extra env inherited
  printf '%s' "$STDIN" | MB_FV_RC="$1" MB_PATH="$PROJ/.memory-bank" bash "$GUARD" >/dev/null 2>&1
}
_runs() { wc -l < "$RUNS" | tr -d ' '; }

@test "cache: unchanged tree reuses the verdict (firewall not re-run)" {
  _run_guard 1; [ "$(_runs)" -eq 1 ]   # miss
  _run_guard 1; [ "$(_runs)" -eq 1 ]   # hit
  _run_guard 1; [ "$(_runs)" -eq 1 ]   # hit
}

@test "cache: any tree change busts the cache and re-runs" {
  _run_guard 1; [ "$(_runs)" -eq 1 ]
  echo more > "$PROJ/newfile.txt"       # untracked change
  _run_guard 1; [ "$(_runs)" -eq 2 ]    # miss
  _run_guard 1; [ "$(_runs)" -eq 2 ]    # hit again
}

@test "cache: MB_FLOW_VERIFY_CACHE=off always runs the firewall" {
  printf '%s' "$STDIN" | MB_FV_RC=1 MB_FLOW_VERIFY_CACHE=off MB_PATH="$PROJ/.memory-bank" bash "$GUARD" >/dev/null 2>&1
  printf '%s' "$STDIN" | MB_FV_RC=1 MB_FLOW_VERIFY_CACHE=off MB_PATH="$PROJ/.memory-bank" bash "$GUARD" >/dev/null 2>&1
  [ "$(_runs)" -eq 2 ]
}

@test "cache: a cached RED verdict still blocks the stop" {
  _run_guard 1                          # populate cache with rc=1 (red)
  run bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_PATH="$2" bash "$3"' _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]] || [[ "$output" == *'block'* ]]
}

@test "cache: the scratch cache file itself does not perturb the signature" {
  _run_guard 1; [ "$(_runs)" -eq 1 ]
  [ -f "$PROJ/.memory-bank/tmp/flow-verify-cache" ]   # cache written under scratch
  _run_guard 1; [ "$(_runs)" -eq 1 ]                  # still a hit despite the new scratch file
}
