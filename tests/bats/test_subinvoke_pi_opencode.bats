#!/usr/bin/env bats
# dynamic-flow T13: Pi/OpenCode adapters declare their sub-invoke command, the
# fan-out runs through them, and an unresolvable sub-invoke degrades to a
# sequential run with a stderr WARN instead of a usage error.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FANOUT="$REPO_ROOT/scripts/mb-fanout.sh"
  RESOLVE="$REPO_ROOT/scripts/mb-subinvoke-resolve.sh"
  TMPBANK="$(mktemp -d)"
  STUBS="$(mktemp -d)"
  PROJ="$(mktemp -d)"
  unset MB_SUBINVOKE_CMD MB_SUBINVOKE_MODEL
}

teardown() { rm -rf "$TMPBANK" "$STUBS" "$PROJ"; }

# A stub agent CLI that records its prompt (last arg) as a JSON object.
make_stub() {
  cat > "$STUBS/$1" <<'STUB'
#!/usr/bin/env bash
python3 -c 'import json,sys;a=sys.argv[1:];p=a[a.index("-p")+1] if "-p" in a and a[a.index("-p")+1:a.index("-p")+2] and not a[a.index("-p")+1].startswith("-") else a[-1];print(json.dumps({"prompt":p}))' "$@"
STUB
  chmod +x "$STUBS/$1"
}

@test "pi adapter: subinvoke declares the resolver's pi template" {
  run bash "$REPO_ROOT/adapters/pi.sh" subinvoke "$PROJ"
  [ "$status" -eq 0 ]
  [ "$output" = "$(MB_AGENT=pi bash "$RESOLVE" --agent pi)" ]
  [[ "$output" == *'$MB_FANOUT_PROMPT'* ]]
}

@test "opencode adapter: subinvoke declares the resolver's opencode template" {
  run bash "$REPO_ROOT/adapters/opencode.sh" subinvoke "$PROJ"
  [ "$status" -eq 0 ]
  [ "$output" = "$(bash "$RESOLVE" --agent opencode)" ]
  [[ "$output" == *"opencode run"* ]]
}

@test "adapter subinvoke ignores an inherited MB_SUBINVOKE_CMD override" {
  MB_SUBINVOKE_CMD="echo hijack" run bash "$REPO_ROOT/adapters/pi.sh" subinvoke "$PROJ"
  [ "$status" -eq 0 ]
  [[ "$output" == "pi -p"* ]]
}

@test "fanout: MB_AGENT=pi fans out through a stub pi binary" {
  make_stub pi
  MB_AGENT=pi PATH="$STUBS:$PATH" run bash "$FANOUT" "$TMPBANK" --branch alpha --branch beta
  [ "$status" -eq 0 ]
  [[ "$output" == *'"count": 2'* || "$output" == *'"count":2'* ]]
  [[ "$output" == *alpha* && "$output" == *beta* ]]
}

@test "fanout: MB_AGENT=opencode fans out through a stub opencode binary" {
  make_stub opencode
  MB_AGENT=opencode PATH="$STUBS:$PATH" run bash "$FANOUT" "$TMPBANK" --branch alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *alpha* ]]
}

@test "fanout: unresolvable sub-invoke runs sequentially with a WARN, not a usage error" {
  make_stub claude
  MB_AGENT=totally-unknown PATH="$STUBS:$PATH" run bash "$FANOUT" "$TMPBANK" --branch one --branch two
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"sequential"* ]]
  [[ "$output" == *one* && "$output" == *two* ]]
}
