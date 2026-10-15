#!/usr/bin/env bats
# mb-qa-bug.sh — the QA bug registry <bank>/qa/bugs.md: monotonic BUG-NNN, four severities,
# dedupe of open bugs by title, status changes, severity-ordered listing, safe parallel adds.

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BUG="$REPO_ROOT/scripts/mb-qa-bug.sh"
  TMP="$(mktemp -d)"
  MB="$TMP/.memory-bank"
  mkdir -p "$MB"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "add creates the registry and returns BUG-001 with the stdin body" {
  run bash -c "printf -- '- Steps: open /login\n' | bash '$BUG' --mb '$MB' add major 'Login button does nothing'"
  [ "$status" -eq 0 ]
  [ "$output" = "BUG-001" ]
  grep -qx '### BUG-001 — Login button does nothing \[major, open, [0-9-]*\]' "$MB/qa/bugs.md"
  grep -qx -- '- Steps: open /login' "$MB/qa/bugs.md"
}

@test "ids are monotonic and never reused after a status change" {
  bash "$BUG" --mb "$MB" add low "Typo in footer" </dev/null
  bash "$BUG" --mb "$MB" set BUG-001 fixed
  run bash "$BUG" --mb "$MB" add critical "Checkout loses the cart" </dev/null
  [ "$output" = "BUG-002" ]
}

@test "same title while open returns the existing id and logs the repeat" {
  bash "$BUG" --mb "$MB" add medium "Avatar upload hangs" </dev/null
  run bash "$BUG" --mb "$MB" add medium "Avatar upload hangs" --run 2026-10-14_1200 </dev/null
  [ "$status" -eq 0 ]
  [ "$output" = "BUG-001" ]
  [ "$(grep -c '^### BUG-' "$MB/qa/bugs.md")" -eq 1 ]
  grep -qx -- '- Seen again: 2026-10-14_1200' "$MB/qa/bugs.md"
}

@test "same title after fixed opens a new bug (regression)" {
  bash "$BUG" --mb "$MB" add major "Search returns nothing" </dev/null
  bash "$BUG" --mb "$MB" set BUG-001 fixed
  run bash "$BUG" --mb "$MB" add major "Search returns nothing" </dev/null
  [ "$output" = "BUG-002" ]
}

@test "title with regex metacharacters is matched literally" {
  bash "$BUG" --mb "$MB" add low "Price shows [object Object]" </dev/null
  run bash "$BUG" --mb "$MB" add low "Price shows .*" </dev/null
  [ "$output" = "BUG-002" ]
}

@test "invalid severity and unknown id are rejected" {
  run bash "$BUG" --mb "$MB" add blocker "x" </dev/null
  [ "$status" -eq 2 ]
  run bash "$BUG" --mb "$MB" set BUG-404 fixed
  [ "$status" -eq 1 ]
  bash "$BUG" --mb "$MB" add low "y" </dev/null
  run bash "$BUG" --mb "$MB" set BUG-001 done
  [ "$status" -eq 2 ]
}

@test "list --open prints open bugs ordered critical to low" {
  bash "$BUG" --mb "$MB" add low "A low one" </dev/null
  bash "$BUG" --mb "$MB" add critical "A critical one" </dev/null
  bash "$BUG" --mb "$MB" add medium "A medium one" </dev/null
  bash "$BUG" --mb "$MB" add major "A fixed major" </dev/null
  bash "$BUG" --mb "$MB" set BUG-004 fixed
  run bash "$BUG" --mb "$MB" list --open
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "BUG-002 critical open A critical one" ]
  [ "${lines[1]}" = "BUG-003 medium open A medium one" ]
  [ "${lines[2]}" = "BUG-001 low open A low one" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "parallel adds get distinct ids" {
  for i in 1 2 3 4 5 6; do
    bash "$BUG" --mb "$MB" add low "Parallel bug $i" </dev/null >"$TMP/out$i" &
  done
  wait
  [ "$(cat "$TMP"/out* | sort -u | wc -l | tr -d ' ')" -eq 6 ]
  [ "$(grep -c '^### BUG-' "$MB/qa/bugs.md")" -eq 6 ]
}

# ── list --json: the normalized review shape the /mb work QA gate consumes (AGR-098) ──

_add() {  # <severity> <title> <body>
  printf '%b' "$3" | bash "$BUG" --mb "$MB" add "$1" "$2" >/dev/null
}

@test "list --json on an empty registry is APPROVED with zero counts" {
  run bash "$BUG" --mb "$MB" list --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "medium": 0, "minor": 0}, "issues": []}' ]
}

@test "list --json maps severities, counts them and points at scenario and step" {
  _add low "Footer typo" '- Scenario: footer.md, step 1\n- Run: r1\n'
  _add critical "Login returns 500" '- Scenario: login.md, step 2\n- Run: r1\n'
  _add medium "Slow search" '- Run: r1\n'
  run bash "$BUG" --mb "$MB" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["verdict"] == "CHANGES_REQUESTED", d
assert d["counts"] == {"blocker": 1, "major": 0, "medium": 1, "minor": 1}, d
first = d["issues"][0]
assert first == {"severity": "blocker", "category": "qa", "file": "login.md", "line": 2,
                 "message": "BUG-002 Login returns 500", "fix": ""}, first
assert [i["severity"] for i in d["issues"]] == ["blocker", "medium", "minor"], d
assert d["issues"][1]["file"] == "qa/bugs.md" and d["issues"][1]["line"] == 0, d'
}

@test "list --json --open --run keeps open bugs filed or seen again in that run" {
  _add major "Seen in r1 only" '- Run: r1\n'
  _add major "Seen in r2" '- Run: r2\n'
  _add critical "Fixed in r2" '- Run: r2\n'
  bash "$BUG" --mb "$MB" set BUG-003 fixed
  bash "$BUG" --mb "$MB" add major "Seen in r1 only" --run r2 </dev/null >/dev/null
  run bash "$BUG" --mb "$MB" list --json --open --run r2
  printf '%s' "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert [i["message"] for i in d["issues"]] == ["BUG-001 Seen in r1 only", "BUG-002 Seen in r2"], d
assert d["counts"]["major"] == 2 and d["counts"]["blocker"] == 0, d'
  run bash "$BUG" --mb "$MB" list --json --run r9
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["issues"]))')" = "0" ]
}

@test "list --json passes review-parse and drives the severity gate" {
  local GATE_ARGS=(--gate '{"blocker":0,"major":0,"medium":1000000,"minor":1000000}')
  _add medium "Slow search" ''
  _add low "Footer typo" ''
  bash "$BUG" --mb "$MB" list --json --open | bash "$REPO_ROOT/scripts/mb-work-review-parse.sh" >/dev/null
  run bash -c "bash '$BUG' --mb '$MB' list --json --open | bash '$REPO_ROOT/scripts/mb-work-severity-gate.sh' --mb '$MB' --counts-stdin $(printf '%q ' "${GATE_ARGS[@]}")"
  [ "$status" -eq 0 ]
  _add critical "Checkout loses the cart" ''
  bash "$BUG" --mb "$MB" list --json --open | bash "$REPO_ROOT/scripts/mb-work-review-parse.sh" >/dev/null
  run bash -c "bash '$BUG' --mb '$MB' list --json --open | bash '$REPO_ROOT/scripts/mb-work-severity-gate.sh' --mb '$MB' --counts-stdin $(printf '%q ' "${GATE_ARGS[@]}")"
  [ "$status" -eq 1 ]
}

# ── gate: one deterministic QA gate for /mb work §5c2 (open bugs of one run vs qa.gate) ──

@test "gate on an empty registry passes" {
  run bash "$BUG" --mb "$MB" gate --run r1
  [ "$status" -eq 0 ]
}

@test "gate fails on an open critical of that run" {
  _add critical "Login returns 500" '- Run: r1\n'
  run bash "$BUG" --mb "$MB" gate --run r1
  [ "$status" -eq 1 ]
}

@test "gate passes with only medium and low open by default" {
  _add medium "Slow search" '- Run: r1\n'
  _add low "Footer typo" '- Run: r1\n'
  run bash "$BUG" --mb "$MB" gate --run r1
  [ "$status" -eq 0 ]
}

@test "gate that names medium fails on an open medium" {
  _add medium "Slow search" '- Run: r1\n'
  run bash "$BUG" --mb "$MB" gate --run r1 --gate '{"critical":0,"major":0,"medium":0}'
  [ "$status" -eq 1 ]
}

@test "gate ignores bugs of another run and fixed bugs" {
  _add critical "Seen in r2" '- Run: r2\n'
  _add critical "Fixed in r1" '- Run: r1\n'
  bash "$BUG" --mb "$MB" set BUG-002 fixed
  run bash "$BUG" --mb "$MB" gate --run r1
  [ "$status" -eq 0 ]
}

@test "gate rejects bad gate JSON, an unknown key and a missing run" {
  run bash "$BUG" --mb "$MB" gate --run r1 --gate '{critical:0'
  [ "$status" -eq 2 ]
  run bash "$BUG" --mb "$MB" gate --run r1 --gate '{"blocker":0}'
  [ "$status" -eq 2 ]
  run bash "$BUG" --mb "$MB" gate --run r1 --gate '{"major":-1}'
  [ "$status" -eq 2 ]
  run bash "$BUG" --mb "$MB" gate
  [ "$status" -eq 2 ]
}
