#!/usr/bin/env bats
# Tests for scripts/mb-bank-lint.sh — S4 Task 4 (design.md C5): 16 codes, format,
# determinism, read-only. Red-anchor: names start with `bank_lint: `.

bats_require_minimum_version 1.5.0

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LINT="$REPO_ROOT/scripts/mb-bank-lint.sh"
  SYNC="$REPO_ROOT/scripts/mb-roadmap-sync.sh"
  TMPROOT="$(mktemp -d)"
  BANK="$TMPROOT/my bank/.memory-bank"
  mkdir -p "$BANK/plans" "$BANK/specs/alpha"
  printf '# Roadmap\n\n<!-- mb-roadmap-auto -->\n<!-- /mb-roadmap-auto -->\n' > "$BANK/roadmap.md"
  mkspec alpha grp '{impact: 8, confidence: 9, ease: 7}' true
  mkplan clean-plan '{impact: 5, confidence: 5, ease: 5}' true
  printf '# Backlog\n\n## Ideas\n\n### I-001 — fine idea [MED, NEW, 2026-04-01]\n\n## Out of scope\n\n## ADR\n' > "$BANK/backlog.md"
  bash "$SYNC" "$BANK" >/dev/null 2>&1
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

# mkspec <topic> <group> <ice|""> <confirmed|""> [extra frontmatter lines...]
mkspec() {
  local topic="$1" group="$2" ice="$3" conf="$4"; shift 4
  mkdir -p "$BANK/specs/$topic"
  {
    printf -- '---\ntopic: %s\n' "$topic"
    [ -n "$group" ] && printf 'group: %s\n' "$group"
    [ -n "$ice" ] && printf 'ice: %s\n' "$ice"
    [ -n "$conf" ] && printf 'ice_confirmed: %s\n' "$conf"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf 'status: ready\n---\n# Requirements\n'
  } > "$BANK/specs/$topic/requirements.md"
}

# mkplan <name> <ice|""> <confirmed|""> [extra lines...]
mkplan() {
  local name="$1" ice="$2" conf="$3"; shift 3
  {
    printf -- '---\ntype: feature\ntopic: %s\nstatus: queued\n' "$name"
    [ -n "$ice" ] && printf 'ice: %s\n' "$ice"
    [ -n "$conf" ] && printf 'ice_confirmed: %s\n' "$conf"
    for l in "$@"; do printf '%s\n' "$l"; done
    printf 'depends_on: []\nparallel_safe: false\nlinked_specs: []\ncreated: 2026-01-01\n---\n# Plan\n'
  } > "$BANK/plans/2026-01-01_feature_$name.md"
}

# Re-sync first so only the case under test is stale; NOSYNC=1 keeps the roadmap stale.
lint() {
  [ -n "${NOSYNC:-}" ] || bash "$SYNC" "$BANK" >/dev/null 2>&1 || true
  run --separate-stderr bash "$LINT" "$@" --mb "$BANK"
}
has_code() { [[ "$output" == *"code=$1 "* ]]; }

@test "bank_lint: clean bank exits 0 with empty stdout" {
  lint all
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bank_lint: finding line follows the documented grammar" {
  mkplan no-ice-plan "" ""
  lint roadmap
  [[ "$output" =~ ^severity=warning\ code=no_ice\ file=\".*\"\ line=[0-9]+\ detail=\".*\"$ ]]
}

@test "bank_lint: no_ice is a warning and keeps exit 0" {
  mkplan no-ice-plan "" ""
  lint roadmap
  [ "$status" -eq 0 ]
  has_code no_ice
}

@test "bank_lint: ice_unconfirmed warning for valid unconfirmed ice" {
  mkplan unconf '{impact: 2, confidence: 3, ease: 4}' ""
  lint roadmap
  [ "$status" -eq 0 ]
  has_code ice_unconfirmed
}

@test "bank_lint: orphan_group warning for a fence group without a spec" {
  python3 - "$BANK/roadmap.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("<!-- /mb-roadmap-auto -->", "## Group: ghost\n\n<!-- /mb-roadmap-auto -->", 1)
open(p, "w", encoding="utf-8").write(s)
PY
  NOSYNC=1 lint roadmap
  has_code orphan_group
  [[ "$output" == *"ghost"* ]]
}

@test "bank_lint: duplicate_pin warning for two members of one group" {
  mkspec beta grp '{impact: 1, confidence: 1, ease: 1}' true 'pin: 3'
  mkspec alpha grp '{impact: 8, confidence: 9, ease: 7}' true 'pin: 3'
  bash "$SYNC" "$BANK" >/dev/null 2>&1
  lint roadmap
  has_code duplicate_pin
}

@test "bank_lint: legacy_state warning names the target and the migrator and keeps exit 0" {
  printf '\n### I-002 — old [MED, OPEN, 2026-04-02]\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 0 ]
  has_code legacy_state
  [[ "$output" == *"mb-backlog-migrate.sh"* && "$output" == *"TRIAGED"* ]]
}

@test "bank_lint: invalid_ice error for malformed, block-style and plain-int values" {
  for v in '{impact: 11, confidence: 5, ease: 5}' '432' '{impact: 5, confidence: 5}' '{impact: 5, impact: 5, ease: 5}'; do
    mkplan bad-ice "$v" ""
    lint roadmap
    [ "$status" -eq 1 ]
    has_code invalid_ice
  done
}

@test "bank_lint: invalid_ice_confirmed error" {
  mkplan bad-conf '{impact: 5, confidence: 5, ease: 5}' "yes"
  lint roadmap
  [ "$status" -eq 1 ]
  has_code invalid_ice_confirmed
}

@test "bank_lint: invalid_pin error" {
  mkplan bad-pin '{impact: 5, confidence: 5, ease: 5}' true 'pin: 0'
  lint roadmap
  [ "$status" -eq 1 ]
  has_code invalid_pin
}

@test "bank_lint: invalid_group error" {
  mkspec gamma 'Bad_Group' '{impact: 5, confidence: 5, ease: 5}' true
  lint roadmap
  [ "$status" -eq 1 ]
  has_code invalid_group
}

@test "bank_lint: invalid_blocked_by error" {
  mkspec delta grp '{impact: 5, confidence: 5, ease: 5}' true 'blocked_by: [Bad Slug]'
  lint roadmap
  [ "$status" -eq 1 ]
  has_code invalid_blocked_by
}

@test "bank_lint: progress_mismatch error when the roadmap block is stale" {
  mkplan late-plan '{impact: 5, confidence: 5, ease: 5}' true
  NOSYNC=1 lint roadmap
  [ "$status" -eq 1 ]
  has_code progress_mismatch
}

@test "bank_lint: invalid_state error for a token outside machine and legacy table" {
  printf '\n### I-002 — weird [MED, BOGUS, 2026-04-02]\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 1 ]
  has_code invalid_state
}

@test "bank_lint: ready_without_brief error for a v2 READY entry" {
  printf '\n### I-002 — v2 ready [MED, READY, 2026-04-02]\n**Type:** IDEA\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 1 ]
  has_code ready_without_brief
}

@test "bank_lint: wontfix_without_reason error for a v2 WONTFIX entry" {
  printf '\n### I-002 — v2 closed [MED, WONTFIX, 2026-04-02]\n**Type:** IDEA\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 1 ]
  has_code wontfix_without_reason
}

@test "bank_lint: grandfather — legacy READY without Brief and legacy WONTFIX without Reason are not flagged" {
  printf '\n### I-002 — legacy ready [MED, READY, 2026-04-02]\n\n### I-003 — legacy closed [MED, WONTFIX, 2026-04-03]\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 0 ]
  refute_substring "$output" "ready_without_brief"
  refute_substring "$output" "wontfix_without_reason"
}

@test "bank_lint: parent_cycle error for a missing parent and for a loop" {
  printf '\n### I-002 — orphan [MED, NEW, 2026-04-02]\n**Parent:** I-777\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 1 ]
  has_code parent_cycle
  printf '\n### I-003 — a [MED, NEW, 2026-04-03]\n**Parent:** I-004\n\n### I-004 — b [MED, NEW, 2026-04-04]\n**Parent:** I-003\n' >> "$BANK/backlog.md"
  lint backlog
  [[ "$output" == *"I-003->I-004->I-003"* ]]
}

@test "bank_lint: duplicate_id error lists every duplicated id with its heading lines" {
  printf '\n### I-002 — first [MED, NEW, 2026-04-02]\n\n### I-001 — again [MED, NEW, 2026-04-03]\n\n### I-002 — second [MED, NEW, 2026-04-04]\n' >> "$BANK/backlog.md"
  lint backlog
  [ "$status" -eq 1 ]
  has_code duplicate_id
  [[ "$output" == *'code=duplicate_id file=".memory-bank/backlog.md" line=5 detail="I-001 appears 2 times: lines 5, 13"'* ]]
  [[ "$output" == *'code=duplicate_id file=".memory-bank/backlog.md" line=11 detail="I-002 appears 2 times: lines 11, 15"'* ]]
}

@test "bank_lint: unknown section argument exits 2" {
  run --separate-stderr bash "$LINT" bogus --mb "$BANK"
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$LINT" --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "bank_lint: path with spaces and quotes unicode in titles are JSON-encoded" {
  mkplan "my plan" "" ""
  printf '\n### I-002 — café "q" [MED, BOGUS, 2026-04-02]\n' >> "$BANK/backlog.md"
  lint all
  [[ "$output" == *'file=".memory-bank/plans/2026-01-01_feature_my plan.md"'* ]]
  [[ "$output" == *'café \"q\"'* ]]
}

@test "bank_lint: output is deterministic and ordered by file then line then code" {
  mkplan zz-plan "" ""
  mkplan aa-plan "" ""
  printf '\n### I-002 — x [MED, BOGUS, 2026-04-02]\n### I-003 — y [MED, OPEN, 2026-04-03]\n' >> "$BANK/backlog.md"
  lint all
  first="$output"
  lint all
  [ "$output" = "$first" ]
  sorted=$(printf '%s\n' "$output" | sed -E 's/^severity=[a-z]+ code=([a-z_]+) file=("[^"]*") line=([0-9]+) .*/\2 \3 \1/' | LC_ALL=C sort -t' ' -k1,1 -k2,2n -k3,3 -c 2>&1; echo $?)
  [ "${sorted##*$'\n'}" = "0" ] || [ "$sorted" = "0" ]
}

@test "bank_lint: lint never modifies the bank" {
  mkplan late-plan "" ""
  printf '\n### I-002 — x [MED, BOGUS, 2026-04-02]\n' >> "$BANK/backlog.md"
  before=$(find "$BANK" -type f -exec cksum {} + | sort)
  NOSYNC=1 lint all
  after=$(find "$BANK" -type f -exec cksum {} + | sort)
  [ "$before" = "$after" ]
}
