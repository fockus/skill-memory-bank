#!/usr/bin/env bats
# Stage 3 (graph-semantic-adoption) — SessionStart fires a BACKGROUND bounded
# graph catch-up. I-131: no synchronous heavy work in lifecycle hooks, so the
# hook must return immediately while the catch-up keeps running detached.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-session-start.sh"
  command -v jq >/dev/null || skip "jq required"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"; MB="$PROJ/.memory-bank"
  mkdir -p "$MB/session"
  printf '## x\nbody\n' > "$MB/session/_recent.md"
  MARKER="$TMP/catchup.args"
  export MARKER
  FAKEBIN="$TMP/bin"; mkdir -p "$FAKEBIN"
}
teardown() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }

_graph() {
  mkdir -p "$MB/codebase"
  cat > "$MB/codebase/graph.json" <<'EOF'
{"type":"meta","generated_at":"2020-01-01T00:00:00Z","commit":null,"nodes":2,"edges":1}
{"type":"node","name":"x","file":"x.py"}
{"type":"node","name":"y","file":"y.py"}
{"type":"edge","src":"x.py","dst":"y","kind":"import"}
EOF
}

# Fake python3: records the catchup argv into $MARKER, then behaves as told.
# $1 = shell snippet run after the marker is written (e.g. `sleep 5`).
_stub_python3() {
  cat > "$FAKEBIN/python3" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *" catchup "*)
    printf '%s\n' "\$*" > "\$MARKER"
    $1
    exit 0 ;;
esac
exit 0
EOF
  chmod +x "$FAKEBIN/python3"
}

# Bounded poll for the marker (NOT a blind sleep): returns as soon as it lands.
_await_marker() {
  for _ in $(seq 1 50); do
    [ -s "$MARKER" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "session-start spawns a graph catch-up when graph.json exists" {
  _graph
  _stub_python3 'sleep 5'
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  [ "$status" -eq 0 ]
  _await_marker
  grep -q 'mb-graph-query.py' "$MARKER"
  grep -q 'catchup' "$MARKER"
  grep -q -- "--graph $MB/codebase/graph.json" "$MARKER"
}

@test "session-start returns in under a second while the catch-up keeps running" {
  _graph
  _stub_python3 'sleep 5'
  t0="$(date +%s)"
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  t1="$(date +%s)"
  [ "$status" -eq 0 ]
  [ "$((t1 - t0))" -lt 2 ]
  # the catch-up really was dispatched (and is still sleeping in the background)
  _await_marker
}

@test "MB_GRAPH_CATCHUP=off spawns no catch-up" {
  _graph
  _stub_python3 ''
  run env PATH="$FAKEBIN:$PATH" MB_GRAPH_CATCHUP=off CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  [ "$status" -eq 0 ]
  if _await_marker; then false; fi
}

@test "absent graph.json spawns no catch-up (first build stays manual)" {
  mkdir -p "$MB/codebase"   # the dir exists, the graph does not — the guard is the only gate
  _stub_python3 ''
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  [ "$status" -eq 0 ]
  if _await_marker; then false; fi
}

@test "catch-up outcome is recorded, not swallowed (budget-exceeded stays visible)" {
  _graph
  _stub_python3 'printf %s\\\\n "{\"result\":\"timed_out\",\"budget\":30.0}"'
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  [ "$status" -eq 0 ]
  _await_marker
  log="$MB/codebase/.graph-catchup.log"
  for _ in $(seq 1 50); do [ -s "$log" ] && break; sleep 0.1; done
  grep -q 'timed_out' "$log"
}

@test "catch-up output never leaks into the SessionStart JSON" {
  _graph
  _stub_python3 'printf %s\\\\n "{\"result\":\"refreshed\"}"'
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null
}

@test "an unwritable codebase dir leaves the hook silent on stderr (outer redirect)" {
  # The outer `( … & ) >/dev/null 2>&1` is NOT belt-and-braces: without it the
  # failing log redirect writes ~200 bytes of "Permission denied" to the hook's
  # stderr. Mutation "drop only the outer redirect" left all other cases green,
  # so this line had no test at all (verify Stage 3, WARNING-2).
  _graph
  _stub_python3 ''
  chmod 555 "$MB/codebase"
  # `run … 2>file` would redirect RUN's stderr, not the hook's — the hook's would
  # still land in $output and leave `[ ! -s hook.err ]` vacuous (I-147). Redirect
  # inside the child instead. Single quotes are deliberate: $1/$@ must expand there.
  # shellcheck disable=SC2016
  run env PATH="$FAKEBIN:$PATH" CLAUDE_PROJECT_DIR="$PROJ" bash -c \
    'exec 2>"$1"; shift; bash "$@"' _ "$TMP/hook.err" "$HOOK"
  chmod 755 "$MB/codebase"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName=="SessionStart"' >/dev/null
  # `[ ]` last on purpose: a failing bracket mid-body does not abort under this
  # bash/bats, so a trailing assertion would swallow it (I-147 vacuity class).
  [ ! -s "$TMP/hook.err" ]
}
