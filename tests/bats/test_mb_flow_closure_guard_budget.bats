#!/usr/bin/env bats
# Hard time budget for the closure guard (MB_FLOW_VERIFY_BUDGET).
#
# The firewall's default check set runs the project's whole test suite. On a
# real repo that is minutes, and a Stop hook that waits for it wedges the
# session ("running stop hooks…" forever). A budget overrun is an
# infrastructure fault like any other and resolves to ALLOW — the guard's
# documented fail-safe — while the firewall's process GROUP is killed so its
# child runners (pytest/bats) do not outlive the hook.
#
# Same STUB-firewall setup as test_mb_flow_closure_guard_cache.bats: the real
# verify lives at a fixed sibling path and cannot be stubbed in-place.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROJ="$(mktemp -d)"
  MARK="$(mktemp)"; : > "$MARK"
  (
    cd "$PROJ"
    git init -q; git config user.email t@t; git config user.name t
    mkdir -p .memory-bank/tmp scripts hooks
    # Stub firewall: spawns a long-lived child (like the real fan-out does),
    # records its pid, then sleeps past any sane budget.
    cat > scripts/mb-flow-verify.sh <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$MARK.argv"
sleep "\${MB_FV_SLEEP:-30}" &
echo \$! > "$MARK"
wait
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
  [ -n "$MARK" ] && rm -f "$MARK" "$MARK.argv"
}

@test "gate: the Stop path skips the whole-suite tests check" {
  # `tests` runs the project's entire suite (minutes). A Stop hook that waits
  # for it is the wedge this budget/skip pair exists to prevent — the other four
  # default checks take under a second and still produce a real verdict.
  bash -c 'printf "%s" "$1" | MB_FV_RC=0 MB_FV_SLEEP=0 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD" >/dev/null 2>&1
  run cat "$MARK.argv"
  [[ "$output" == *"--skip tests"* ]]
}

@test "gate: MB_FLOW_VERIFY_SKIP overrides which checks the Stop path drops" {
  bash -c 'printf "%s" "$1" | MB_FV_RC=0 MB_FV_SLEEP=0 MB_FLOW_VERIFY_SKIP=lint MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD" >/dev/null 2>&1
  run cat "$MARK.argv"
  [[ "$output" == *"--skip lint"* ]]
  [[ "$output" != *"tests"* ]]
}

@test "gate: MB_FLOW_VERIFY_SKIP= (empty) runs the full default set" {
  bash -c 'printf "%s" "$1" | MB_FV_RC=0 MB_FV_SLEEP=0 MB_FLOW_VERIFY_SKIP= MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD" >/dev/null 2>&1
  run cat "$MARK.argv"
  [[ "$output" != *"--skip"* ]]
}

@test "budget: a firewall slower than the budget does not wedge the stop" {
  start=$(date +%s)
  run bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=30 MB_FLOW_VERIFY_BUDGET=2 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  elapsed=$(( $(date +%s) - start ))
  [ "$status" -eq 0 ]
  # Returned on budget, not on the firewall's own 30s.
  [ "$elapsed" -lt 15 ]
  # Fail-safe: an uncertifiable verdict allows, it never blocks.
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "budget: overrun kills the firewall's child processes" {
  # A long sleep, so the child cannot exit on its own within the assertion
  # window — only the guard's process-group kill can end it.
  start=$(date +%s)
  bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=120 MB_FLOW_VERIFY_BUDGET=2 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD" >/dev/null 2>&1
  [ $(( $(date +%s) - start )) -lt 15 ]
  child="$(cat "$MARK" 2>/dev/null || true)"
  [ -n "$child" ]
  sleep 1
  # A bare kill of the wrapper leaves this `sleep` running; the process-group
  # kill is what actually reclaims it.
  run kill -0 "$child"
  [ "$status" -ne 0 ]
}

@test "budget: overrun says so instead of silently certifying closure" {
  run bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=30 MB_FLOW_VERIFY_BUDGET=2 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"systemMessage"* ]]
  [[ "$output" == *"budget"* ]]
}

@test "budget: an overrun verdict is not cached" {
  bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=30 MB_FLOW_VERIFY_BUDGET=2 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD" >/dev/null 2>&1
  [ ! -s "$PROJ/.memory-bank/tmp/flow-verify-cache" ]
}

@test "budget: a red inside the budget still blocks" {
  run bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=0 MB_FLOW_VERIFY_BUDGET=20 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "budget: a green inside the budget still allows" {
  run bash -c 'printf "%s" "$1" | MB_FV_RC=0 MB_FV_SLEEP=0 MB_FLOW_VERIFY_BUDGET=20 MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "budget: MB_FLOW_VERIFY_BUDGET=off restores the unbounded wait" {
  start=$(date +%s)
  run bash -c 'printf "%s" "$1" | MB_FV_RC=1 MB_FV_SLEEP=3 MB_FLOW_VERIFY_BUDGET=off MB_PATH="$2" bash "$3"' \
    _ "$STDIN" "$PROJ/.memory-bank" "$GUARD"
  elapsed=$(( $(date +%s) - start ))
  [ "$status" -eq 0 ]
  [ "$elapsed" -ge 3 ]
  [[ "$output" == *'"decision":"block"'* ]]
}
