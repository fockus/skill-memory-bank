#!/usr/bin/env bats
# Tests for scripts/mb-flow-branch-sink.sh — per-branch result sinks + the
# fence-write-once discipline (dynamic-flow Task 12, open-Q2 / ADR-9 / REQ-DF-030).
#
# Contract under test:
#   - `write` mode: a SINGLE branch writes its JSON result to
#     `<bank>/.mb-flow/branch-<i>.json` (one file per index → parallel branches
#     never collide). Atomic (tmp + mv). Stateless w.r.t. other branches.
#   - A branch context can ONLY write its own per-branch sink; it MUST refuse to
#     touch the `<!-- mb-flow -->` fence (the fence is the initiator's job, never
#     a branch's — ADR-9 open-Q2).
#   - `fence` mode (initiator-only): aggregates `.mb-flow/branch-*.json` and writes
#     the `<!-- mb-flow -->` fence EXACTLY ONCE, serially, REUSING mb-flow-sync.sh
#     so content OUTSIDE the markers is byte-preserved (REQ-DF-030).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SINK="$REPO_ROOT/scripts/mb-flow-branch-sink.sh"
  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# ═══════════════════════════════════════════════════════════════
# Existence / help
# ═══════════════════════════════════════════════════════════════

@test "branch-sink: script exists and is executable" {
  [ -f "$SINK" ]
  [ -x "$SINK" ]
}

@test "branch-sink: --help exits 0 and documents the write/fence modes" {
  run bash "$SINK" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch-<i>.json"* ]]
}

# ═══════════════════════════════════════════════════════════════
# write mode — per-branch sinks, no collision
# ═══════════════════════════════════════════════════════════════

@test "branch-sink: write creates .mb-flow/branch-<i>.json with the given JSON" {
  run bash "$SINK" "$TMPBANK" write --index 0 --result '{"v":1}'
  [ "$status" -eq 0 ]
  [ -f "$TMPBANK/.mb-flow/branch-0.json" ]
  python3 -c '
import json,sys
o=json.load(open(sys.argv[1]))
assert o=={"v":1}, o
' "$TMPBANK/.mb-flow/branch-0.json"
}

@test "branch-sink: two branches write DISTINCT files (branch-0.json / branch-1.json), no clobber" {
  bash "$SINK" "$TMPBANK" write --index 0 --result '{"branch":0}'
  bash "$SINK" "$TMPBANK" write --index 1 --result '{"branch":1}'
  [ -f "$TMPBANK/.mb-flow/branch-0.json" ]
  [ -f "$TMPBANK/.mb-flow/branch-1.json" ]
  python3 -c '
import json
a=json.load(open("'"$TMPBANK"'/.mb-flow/branch-0.json"))
b=json.load(open("'"$TMPBANK"'/.mb-flow/branch-1.json"))
assert a=={"branch":0}, a
assert b=={"branch":1}, b
'
}

@test "branch-sink: two PARALLEL writes (background jobs) both land, no race/clobber" {
  ( bash "$SINK" "$TMPBANK" write --index 0 --result '{"p":0}' ) &
  ( bash "$SINK" "$TMPBANK" write --index 1 --result '{"p":1}' ) &
  wait
  [ -f "$TMPBANK/.mb-flow/branch-0.json" ]
  [ -f "$TMPBANK/.mb-flow/branch-1.json" ]
  python3 -c '
import json
assert json.load(open("'"$TMPBANK"'/.mb-flow/branch-0.json"))=={"p":0}
assert json.load(open("'"$TMPBANK"'/.mb-flow/branch-1.json"))=={"p":1}
'
}

@test "branch-sink: write --result-file reads the JSON from a file" {
  printf '{"from":"file"}' > "$TMPROOT/r.json"
  run bash "$SINK" "$TMPBANK" write --index 2 --result-file "$TMPROOT/r.json"
  [ "$status" -eq 0 ]
  python3 -c '
import json
assert json.load(open("'"$TMPBANK"'/.mb-flow/branch-2.json"))=={"from":"file"}
'
}

@test "branch-sink: write rejects non-JSON result loudly (non-zero), no file written" {
  run bash "$SINK" "$TMPBANK" write --index 0 --result 'not json'
  [ "$status" -ne 0 ]
  [ ! -f "$TMPBANK/.mb-flow/branch-0.json" ]
}

@test "branch-sink: write rejects non-strict JSON (NaN / Infinity), no file written" {
  # Python's json.load ACCEPTS NaN/Infinity by default, but those are not valid
  # per the JSON spec and break strict downstream readers — reject them.
  run bash "$SINK" "$TMPBANK" write --index 0 --result 'NaN'
  [ "$status" -ne 0 ]
  [ ! -f "$TMPBANK/.mb-flow/branch-0.json" ]
  run bash "$SINK" "$TMPBANK" write --index 1 --result '{"x":Infinity}'
  [ "$status" -ne 0 ]
  [ ! -f "$TMPBANK/.mb-flow/branch-1.json" ]
}

@test "branch-sink: write rejects a non-integer index loudly (non-zero)" {
  run bash "$SINK" "$TMPBANK" write --index abc --result '{}'
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Branch context MUST NOT write the fence (ADR-9 open-Q2 guard)
# ═══════════════════════════════════════════════════════════════

@test "branch-sink: a branch (write mode) NEVER touches status.md / the mb-flow fence" {
  printf '# Status\n\nsome durable line\n' > "$TMPBANK/status.md"
  before="$(cat "$TMPBANK/status.md")"
  run bash "$SINK" "$TMPBANK" write --index 0 --result '{"v":1}'
  [ "$status" -eq 0 ]
  after="$(cat "$TMPBANK/status.md")"
  # status.md is byte-identical; no fence markers were added by a branch.
  [ "$before" = "$after" ]
  [[ "$after" != *"mb-flow"* ]]
}

@test "branch-sink: an explicit fence-write request in write mode is REFUSED (non-zero)" {
  run bash "$SINK" "$TMPBANK" write --index 0 --result '{}' --fence
  [ "$status" -ne 0 ]
  [[ "$output" == *"branch"* ]]
}

@test "branch-sink: fence mode is REFUSED from a BRANCH context (MB_FANOUT_BRANCH_INDEX set), fence not written" {
  # The open-Q2 contract: a branch may NEVER write the fence. mb-fanout exports
  # MB_FANOUT_BRANCH_INDEX into every branch — so a branch invoking `fence`
  # DIRECTLY (bypassing the `write --fence` guard) must still be refused, or two
  # branches could race the fence. This closes the structural bypass.
  printf '# Status\n\ndurable\n' > "$TMPBANK/status.md"
  bash "$SINK" "$TMPBANK" write --index 0 --result '{"v":1}'
  run env MB_FANOUT_BRANCH_INDEX=0 bash "$SINK" "$TMPBANK" fence --route arch --gate PASS
  [ "$status" -ne 0 ]
  # The fence was NOT written by the branch.
  ! grep -q '<!-- mb-flow -->' "$TMPBANK/status.md"
}

@test "branch-sink: fence mode from the INITIATOR (no branch index) still works" {
  # Regression guard for the branch-context refusal above: the initiator (which
  # has NO MB_FANOUT_BRANCH_INDEX) must still write the fence normally.
  printf '# Status\n' > "$TMPBANK/status.md"
  bash "$SINK" "$TMPBANK" write --index 0 --result '{"v":1}'
  run env -u MB_FANOUT_BRANCH_INDEX bash "$SINK" "$TMPBANK" fence --route arch --gate PASS
  [ "$status" -eq 0 ]
  grep -q '<!-- mb-flow -->' "$TMPBANK/status.md"
}

# ═══════════════════════════════════════════════════════════════
# fence mode — initiator writes the fence ONCE, byte-preserving outside
# ═══════════════════════════════════════════════════════════════

@test "branch-sink: fence mode writes the mb-flow fence ONCE and preserves content outside it" {
  printf '# Status\n\ndurable header line\n' > "$TMPBANK/status.md"
  bash "$SINK" "$TMPBANK" write --index 0 --result '{"branch":0}'
  bash "$SINK" "$TMPBANK" write --index 1 --result '{"branch":1}'
  run bash "$SINK" "$TMPBANK" fence --route fanout-synthesize --gate PASS
  [ "$status" -eq 0 ]
  # The fence exists exactly once.
  local opens
  opens="$(grep -c '<!-- mb-flow -->' "$TMPBANK/status.md")"
  [ "$opens" -eq 1 ]
  # Content outside the fence is byte-preserved.
  grep -q "durable header line" "$TMPBANK/status.md"
  grep -q "route: fanout-synthesize" "$TMPBANK/status.md"
}

@test "branch-sink: fence mode is idempotent — re-running with same inputs keeps one fence" {
  printf '# Status\n' > "$TMPBANK/status.md"
  bash "$SINK" "$TMPBANK" write --index 0 --result '{"v":1}'
  bash "$SINK" "$TMPBANK" fence --route arch --gate PASS
  bash "$SINK" "$TMPBANK" fence --route arch --gate PASS
  local opens
  opens="$(grep -c '<!-- mb-flow -->' "$TMPBANK/status.md")"
  [ "$opens" -eq 1 ]
}

@test "branch-sink: fence mode never opens goal.md for writing (durable-only, REQ-DF-031)" {
  printf '# Goal\n\n## Acceptance criteria\n- [ ] x\n' > "$TMPBANK/goal.md"
  before="$(cat "$TMPBANK/goal.md")"
  bash "$SINK" "$TMPBANK" write --index 0 --result '{}'
  bash "$SINK" "$TMPBANK" fence --route research --gate PASS
  after="$(cat "$TMPBANK/goal.md")"
  [ "$before" = "$after" ]
}
