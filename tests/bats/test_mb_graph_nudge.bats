#!/usr/bin/env bats
# Stage 10 — mb-graph-nudge.sh: non-blocking PreToolUse nudge toward the code
# graph, firing ONLY when the graph exists + is fresh, throttled 1×/session,
# off-switchable, fail-safe (always {} + exit 0 on any problem; never blocks).
#
# graph-semantic-adoption Stage 1 (nudge v2): the throttle is a COUNTER, not a
# one-shot marker — re-nudge every N structural calls (MB_GRAPH_NUDGE_EVERY,
# default 25) — the message carries the candidate symbol lifted from the actual
# grep pattern, and SessionStart:compact resets the counter.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-graph-nudge.sh"
  CWD="$(mktemp -d)"
  MB="$CWD/.memory-bank"
  mkdir -p "$MB/codebase" "$MB/.index"
}

teardown() {
  [ -n "${CWD:-}" ] && rm -rf "$CWD"
}

_graph() {  # $1 = generated_at ISO
  cat > "$MB/codebase/graph.json" <<EOF
{"type":"meta","generated_at":"$1","commit":null,"nodes":2,"edges":1}
{"type":"node","name":"x","file":"x.py"}
{"type":"node","name":"y","file":"y.py"}
{"type":"edge","src":"x.py","dst":"y","kind":"import"}
EOF
}

_fresh() { _graph "$(date -u +%Y-%m-%dT%H:%M:%SZ)"; }
_stale() { _graph "2020-01-01T00:00:00Z"; }

_run_hook() {  # $1 = stdin JSON
  printf '%s' "$1" | PATH="$REPO_ROOT/.venv/bin:$PATH" bash "$HOOK"
}

@test "nudge fires on Grep tool when graph is fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge fires on rtk grep Bash when graph is fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"rtk grep -rn foo src/\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge silent when graph absent" {
  rm -f "$MB/codebase/graph.json"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge on a stale graph offers a refresh instead of going silent" {
  # I-133: the old fresh-only gate silently dropped the nudge the moment the
  # graph went stale — the vicious circle that kept the graph unused. A stale
  # graph now yields an honest "stale → refresh" hint (still throttled).
  _stale
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale"* ]]
  [[ "$output" == *"graph --apply"* ]]
}

@test "nudge off-switch silences it" {
  _fresh
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}' | MB_GRAPH_NUDGE=off PATH=\"$REPO_ROOT/.venv/bin:\$PATH\" bash \"$HOOK\""
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge throttled on second call in same session" {
  _fresh
  export CLAUDE_SESSION_ID="sess-abc"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge fires on bare rg (recursive by default) when fresh" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"rg Foo\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mb-graph-query"* ]]
}

@test "nudge ignores non-structural Bash" {
  _fresh
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"ls -la\"}}"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

@test "nudge fail-safe on malformed stdin" {
  run _run_hook "not json at all {{{"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mb-graph-query"* ]]
}

# ── Stage 1 (nudge v2) ────────────────────────────────────────────────────────

_markers() { ls "$MB"/.index/.graph-nudge.* 2>/dev/null; }

@test "nudge repeats every N structural calls (re-nudge on the N+1-th)" {
  # DoD: a repeat is observable. With MB_GRAPH_NUDGE_EVERY=3 and 2N+1=7 calls
  # the contract nudges on calls 1, 4 (=N+1) and 7 (=2N+1) — the DoD's "2 nudges"
  # is the N+1 boundary; the third one is the same boundary hit again.
  _fresh
  export CLAUDE_SESSION_ID="sess-renudge"
  export MB_GRAPH_NUDGE_EVERY=3
  local i fired=""
  for i in 1 2 3 4 5 6 7; do
    out="$(_run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"resolve_target\"}}")"
    case "$out" in *mb-graph-query*) fired="$fired $i" ;; esac
  done
  [ "$fired" = " 1 4 7" ]
}

@test "nudge substitutes the symbol lifted from a grep pattern" {
  _fresh
  run _run_hook '{"tool_name":"Bash","cwd":"'"$CWD"'","tool_input":{"command":"grep -rn \"def resolve_target\" src/"}}'
  [ "$status" -eq 0 ]
  assert_substring "$output" "--symbol resolve_target"
}

@test "nudge substitutes the symbol from the Grep tool pattern" {
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"class WorkResolver\"}}"
  [ "$status" -eq 0 ]
  assert_substring "$output" "--symbol WorkResolver"
}

@test "nudge keeps the generic placeholder when no symbol can be lifted" {
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"^\\\\s*\\\\{\\\\}\"}}"
  [ "$status" -eq 0 ]
  assert_substring "$output" "--symbol <Name>"
}

@test "off-switch leaves no nudge marker behind" {
  _fresh
  export CLAUDE_SESSION_ID="sess-off"
  run bash -c "printf '%s' '{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}' | MB_GRAPH_NUDGE=off PATH=\"$REPO_ROOT/.venv/bin:\$PATH\" bash \"$HOOK\""
  [ "$status" -eq 0 ]
  refute_substring "$output" "mb-graph-query"
  [ -z "$(_markers)" ]
}

@test "non-structural Bash prints {} and creates no nudge marker" {
  _fresh
  export CLAUDE_SESSION_ID="sess-nonstruct"
  run _run_hook "{\"tool_name\":\"Bash\",\"cwd\":\"$CWD\",\"tool_input\":{\"command\":\"ls -la\"}}"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
  [ -z "$(_markers)" ]
}

@test "SessionStart:compact reset makes the next structural call nudge again" {
  _fresh
  export CLAUDE_SESSION_ID="sess-compact"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  assert_substring "$output" "mb-graph-query"
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  refute_substring "$output" "mb-graph-query"
  run bash -c "CLAUDE_PROJECT_DIR=\"$CWD\" PATH=\"$REPO_ROOT/.venv/bin:\$PATH\" bash \"$HOOK\" --reset </dev/null"
  [ "$status" -eq 0 ]
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}"
  assert_substring "$output" "mb-graph-query"
}

@test "the compact reset is wired in settings/hooks.json (SessionStart:compact)" {
  run jq -e '(.SessionStart // [])
             | map(select(.matcher == "compact"))
             | map(.hooks[].command)
             | map(select(test("mb-graph-nudge\\.sh --reset")))
             | length > 0' "$REPO_ROOT/settings/hooks.json"
  [ "$status" -eq 0 ]
}

# ── verify Stage 1, WARNING-1/2/4 — closed by the orchestrator ────────────────

@test "definition keyword wins over the last identifier (def)" {
  # `--symbol target` sends the agent to an empty answer and back to grep. The
  # identifier being DEFINED is the only useful one (verify Stage 1, WARNING-1).
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"def resolve_target(self, target)\"}}"
  [ "$status" -eq 0 ]
  refute_substring "$output" "--symbol target"
  assert_substring "$output" "--symbol resolve_target"
}

@test "definition keyword wins over the last identifier (class with a base)" {
  _fresh
  run _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"class WorkResolver(Base):\"}}"
  [ "$status" -eq 0 ]
  refute_substring "$output" "--symbol Base"
  assert_substring "$output" "--symbol WorkResolver"
}

@test "an unpersistable counter goes silent instead of nudging on every call" {
  # A read-only .index/ used to leave the counter stuck, so EVERY structural call
  # nudged AND spawned python — the stage's whole saving evaporated and the
  # context filled with hints (verify Stage 1, WARNING-2).
  _fresh
  rm -rf "$MB/.index"
  : > "$MB/.index-blocker"
  ln -sf "$MB/.index-blocker/nope" "$MB/.index" 2>/dev/null || true
  local nudges=0 i
  for i in 1 2 3 4; do
    if _run_hook "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}" \
        2>/dev/null | grep -q 'mb-graph-query'; then nudges=$((nudges + 1)); fi
  done
  rm -f "$MB/.index"
  [ "$nudges" -eq 0 ]
}

@test "a failed freshness gate does not park the counter at N" {
  # The counter used to be reset AFTER the gate, so a gate failure left it at N
  # and every later call re-spawned python (verify Stage 1, WARNING-4).
  _fresh
  local pycalls="$CWD/pycalls" fakebin="$CWD/fakebin"
  mkdir -p "$fakebin"
  printf '#!/usr/bin/env bash\necho x >> "%s"\nexit 1\n' "$pycalls" > "$fakebin/python3"
  chmod +x "$fakebin/python3"
  local i
  for i in 1 2 3 4 5 6; do
    printf '%s' "{\"tool_name\":\"Grep\",\"cwd\":\"$CWD\",\"tool_input\":{\"pattern\":\"foo\"}}" \
      | MB_GRAPH_NUDGE_EVERY=3 PATH="$fakebin:$PATH" bash "$HOOK" >/dev/null 2>&1
  done
  # 6 calls at N=3 must reach the gate twice (calls 1 and 4), not six times.
  [ "$(wc -l < "$pycalls" | tr -d ' ')" -le 2 ]
}
