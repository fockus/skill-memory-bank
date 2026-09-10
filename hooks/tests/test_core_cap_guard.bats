#!/usr/bin/env bats
# mb-core-cap-guard.sh — Stop hook enforcing the core-file line caps (AGR-043).
#
# Contract:
#   Runs `scripts/mb-core-cap.sh fix`. Still over cap → ONE `decision: block`
#   per session (marker `<bank>/.core-cap.nudged.<session_id>`); the next Stop
#   of the same session allows. `stop_hook_active: true` always allows (loop
#   guard). MB_CORE_CAP=off, no bank, no jq and any internal error allow: a cap
#   guard must never wedge a session.

load '../../tests/bats/lib/assert'

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/hooks/mb-core-cap-guard.sh"
  TMP="$(mktemp -d)"
  PROJ="$TMP/proj"
  BANK="$PROJ/.memory-bank"
  mkdir -p "$BANK"
  printf '# Progress\n' > "$BANK/progress.md"
  printf '# Checklist\n\n- ⬜ open\n' > "$BANK/checklist.md"
}

teardown() { [ -n "${TMP:-}" ] && rm -rf "$TMP"; }

# 103 undated lines — over the 60 cap and impossible for rotation to shrink.
_over_cap_status() {
  { printf '# Status\n\n## Current phase\n'
    local i
    for i in $(seq 1 100); do printf -- '- undated line %s\n' "$i"; done
  } > "$BANK/status.md"
}

@test "core-cap guard: over cap → one block JSON naming actualize --strict" {
  _over_cap_status
  run bash -c "printf '{\"session_id\":\"s1\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  assert_substring "$output" '"decision":"block"'
  assert_substring "$output" 'core-cap:'
  assert_substring "$output" 'actualize --strict'
  run bash -c "printf '%s' '$output' | jq -r '.reason'"
  assert_substring "$output" 'status.md 103/60'
}

@test "core-cap guard: the second Stop of the same session allows silently" {
  _over_cap_status
  run bash -c "printf '{\"session_id\":\"same\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  assert_substring "$output" '"decision":"block"'
  [ -f "$BANK/.core-cap.nudged.same" ]

  run bash -c "printf '{\"session_id\":\"same\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # A different session still gets its one block.
  run bash -c "printf '{\"session_id\":\"other\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  assert_substring "$output" '"decision":"block"'
}

@test "core-cap guard: stop_hook_active=true always allows (loop guard)" {
  _over_cap_status
  run bash -c "printf '{\"session_id\":\"s2\",\"cwd\":\"$PROJ\",\"stop_hook_active\":true}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_cmd bash -c "ls '$BANK'/.core-cap.nudged.* 2>/dev/null | grep -q ."
}

@test "core-cap guard: under cap → exit 0, no output, no marker" {
  printf '# Status\n\n## Current phase\n- one line\n' > "$BANK/status.md"
  run bash -c "printf '{\"session_id\":\"s3\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_cmd bash -c "ls '$BANK'/.core-cap.nudged.* 2>/dev/null | grep -q ."
}

@test "core-cap guard: MB_CORE_CAP=off allows and touches nothing" {
  _over_cap_status
  run bash -c "printf '{\"session_id\":\"s4\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | MB_CORE_CAP=off bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  refute_cmd bash -c "ls '$BANK'/.core-cap.nudged.* 2>/dev/null | grep -q ."
}

@test "core-cap guard: no bank / empty stdin / missing script → allow" {
  _over_cap_status
  # cwd without a bank
  mkdir -p "$TMP/bare"
  run bash -c "printf '{\"session_id\":\"s5\",\"cwd\":\"$TMP/bare\",\"stop_hook_active\":false}' | MB_PATH= bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # empty stdin
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # jq absent: a PATH farm with everything BUT jq. The contract is fail-open —
  # a cap guard that cannot read its input must never wedge the session.
  mkdir -p "$TMP/bin"
  for tool in bash python3 grep sed tr mktemp cat head tail rm wc dirname pwd env date cp mv ls basename awk find sort seq touch; do
    src="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$src" ] && ln -sf "$src" "$TMP/bin/$tool"
  done
  refute_cmd env PATH="$TMP/bin" command -v jq
  run env PATH="$TMP/bin" bash -c "printf '{\"session_id\":\"s6\",\"cwd\":\"$PROJ\",\"stop_hook_active\":false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  # python3 parses stdin and the hand-rolled JSON emitter still produces a
  # well-formed block — the jq-less path is a fallback, not a dead branch.
  assert_substring "$output" '"decision":"block"'
  assert_substring "$output" 'status.md 103/60'
}

@test "core-cap guard: replaces mb-checklist-autoprune.sh — gone from the tree and from install" {
  refute_file "$REPO_ROOT/hooks/mb-checklist-autoprune.sh"
  refute_grep -q -e 'mb-checklist-autoprune' "$REPO_ROOT/settings/hooks.json"
  refute_grep -qn -e 'mb-checklist-autoprune' "$REPO_ROOT/SKILL.md"
  # The replacement is registered as a Stop hook and is ON by default.
  assert_grep -q -e 'mb-core-cap-guard.sh' "$REPO_ROOT/settings/hooks.json"
  run bash -c "python3 -c \"import json;d=json.load(open('$REPO_ROOT/settings/hooks.json'));print(any('mb-core-cap-guard.sh' in h['command'] for g in d['Stop'] for h in g['hooks']))\""
  [ "$output" = "True" ]
}

@test "core-cap notice: SessionStart context carries one line only when over cap" {
  command -v jq >/dev/null || skip "jq required for the sessionStart payload"
  _over_cap_status
  ctx() { printf '{"workspace_roots":["%s"]}' "$PROJ" | bash "$REPO_ROOT/hooks/mb-session-start-context.sh" | jq -r '.additional_context'; }

  run ctx
  [ "$status" -eq 0 ]
  assert_substring "$output" '[core-cap] status.md 103/60, checklist.md 3/100 — /mb update --strict'

  printf '# Status\n\n## Current phase\n- small\n' > "$BANK/status.md"
  run ctx
  [ "$status" -eq 0 ]
  refute_substring "$output" '[core-cap]'
}
