#!/usr/bin/env bats
# Tests for scripts/mb-work-pivot.sh — strategic pivot decision + telemetry
# (work-loop-v2 design.md §5 "Strategic pivoting" / "Pivot decision",
# "Pivot dispatch", "Telemetry"; REQ-112/REQ-114).
#
# Contract under test:
#   consecutive_stagnant = count of consecutive stagnant trends (caller-supplied)
#   if consecutive_stagnant >= pivot_after_cycles (default 2):
#     mode = pivot_in_role
#     if current_cycle >= pivot_escalate_to_architect_on (default 4):
#       mode = pivot_via_architect
#   else:
#     mode = refine
#
# Telemetry: one JSONL line appended to <bank>/tmp/pivot-log.jsonl per pivot
# (mode != refine) when --item-id is given; refine writes nothing.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-work-pivot.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

decide() {
  # $1=consecutive-stagnant $2=cycle, remaining args passed through.
  local consecutive="$1" cycle="$2"
  shift 2
  run bash "$RUN" decide --mb "$BANK" --consecutive-stagnant "$consecutive" --cycle "$cycle" "$@"
}

pivot_log() {
  printf '%s/tmp/pivot-log.jsonl' "$BANK"
}

# ---- basics -------------------------------------------------------------

@test "mb-work-pivot.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "--help exits 0 and documents decide and prompt-prefix subcommands" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"decide"* ]]
  [[ "$output" == *"prompt-prefix"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus
  [ "$status" -eq 2 ]
}

@test "decide: missing --consecutive-stagnant/--cycle -> usage error, exit 2" {
  run bash "$RUN" decide --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "decide: non-numeric --consecutive-stagnant -> usage error, exit 2" {
  run bash "$RUN" decide --mb "$BANK" --consecutive-stagnant abc --cycle 1
  [ "$status" -eq 2 ]
}

# ---- decision table (default thresholds: after=2, escalate=4) -----------

@test "decide: consecutive_stagnant below threshold -> refine (N=0)" {
  decide 0 1
  [ "$status" -eq 0 ]
  [ "$output" = "refine" ]
}

@test "decide: consecutive_stagnant == threshold-1 -> refine (N=1)" {
  decide 1 1
  [ "$status" -eq 0 ]
  [ "$output" = "refine" ]
}

@test "decide: consecutive_stagnant == threshold, cycle below escalate -> pivot_in_role" {
  decide 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]
}

@test "decide: consecutive_stagnant == threshold, cycle == escalate-1 -> pivot_in_role" {
  decide 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]
}

@test "decide: consecutive_stagnant == threshold, cycle == escalate -> pivot_via_architect" {
  decide 2 4
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_via_architect" ]
}

@test "decide: consecutive_stagnant above threshold, cycle above escalate -> pivot_via_architect" {
  decide 3 5
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_via_architect" ]
}

@test "decide: consecutive_stagnant above threshold, cycle below escalate -> pivot_in_role" {
  decide 5 1
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]
}

# ---- telemetry ------------------------------------------------------------

@test "telemetry: refine writes NO pivot-log.jsonl" {
  decide 0 1 --item-id "item-1" --rationale "trying refine only"
  [ "$status" -eq 0 ]
  [ ! -f "$(pivot_log)" ]
}

@test "telemetry: pivot without --item-id writes no telemetry line" {
  decide 2 3
  [ "$status" -eq 0 ]
  [ ! -f "$(pivot_log)" ]
}

@test "telemetry: pivot_in_role with --item-id appends exactly one JSONL line" {
  decide 2 3 --item-id "item-42" --rationale "switch to a queue-based design"
  [ "$status" -eq 0 ]
  [ -f "$(pivot_log)" ]
  run wc -l < "$(pivot_log)"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '[:space:]')" = "1" ]
}

@test "telemetry: line is valid JSON with the 5 documented fields" {
  decide 2 4 --item-id "item-7" --rationale "rewrite as event sourcing"
  [ "$status" -eq 0 ]
  line=$(cat "$(pivot_log)")
  LINE="$line" python3 -c '
import json, os, sys
data = json.loads(os.environ["LINE"])
required = {"ts", "item_id", "cycle", "mode", "rationale_hash"}
missing = required - data.keys()
assert not missing, f"missing fields: {missing}"
assert data["item_id"] == "item-7"
assert data["cycle"] == 4
assert data["mode"] == "pivot_via_architect"
assert data["rationale_hash"].startswith("sha256:")
assert len(data["rationale_hash"]) == len("sha256:") + 64
'
}

@test "telemetry: rationale_hash is deterministic for the same rationale" {
  decide 2 3 --item-id "item-a" --rationale "same rationale text"
  [ "$status" -eq 0 ]
  first_hash=$(python3 -c '
import json
print(json.loads(open("'"$(pivot_log)"'").readlines()[-1])["rationale_hash"])
')
  rm -f "$(pivot_log)"

  decide 2 3 --item-id "item-b" --rationale "same rationale text"
  [ "$status" -eq 0 ]
  second_hash=$(python3 -c '
import json
print(json.loads(open("'"$(pivot_log)"'").readlines()[-1])["rationale_hash"])
')

  [ "$first_hash" = "$second_hash" ]
}

@test "telemetry: pivot with no --rationale still writes a valid, deterministic hash" {
  decide 2 4 --item-id "item-c"
  [ "$status" -eq 0 ]
  first_hash=$(python3 -c '
import json
print(json.loads(open("'"$(pivot_log)"'").readlines()[-1])["rationale_hash"])
')
  rm -f "$(pivot_log)"

  decide 2 4 --item-id "item-d"
  [ "$status" -eq 0 ]
  second_hash=$(python3 -c '
import json
print(json.loads(open("'"$(pivot_log)"'").readlines()[-1])["rationale_hash"])
')

  [ "$first_hash" = "$second_hash" ]
  [[ "$first_hash" == sha256:* ]]
}

@test "telemetry: two pivots for the same item append two separate lines" {
  decide 2 3 --item-id "item-multi" --rationale "first pivot"
  [ "$status" -eq 0 ]
  decide 2 4 --item-id "item-multi" --rationale "second pivot"
  [ "$status" -eq 0 ]
  run wc -l < "$(pivot_log)"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d '[:space:]')" = "2" ]
}

# ---- pipeline-key overrides -----------------------------------------------

@test "pipeline override: pivot_after_cycles: 3 in project pipeline.yaml moves the boundary" {
  cat > "$BANK/pipeline.yaml" <<'EOF'
review:
  pivot_after_cycles: 3
  pivot_escalate_to_architect_on: 4
EOF
  decide 2 1
  [ "$status" -eq 0 ]
  [ "$output" = "refine" ]

  decide 3 1
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]
}

@test "pipeline override: pivot_escalate_to_architect_on: 5 moves the escalation boundary" {
  cat > "$BANK/pipeline.yaml" <<'EOF'
review:
  pivot_after_cycles: 2
  pivot_escalate_to_architect_on: 5
EOF
  decide 2 4
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]

  decide 2 5
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_via_architect" ]
}

@test "pipeline override: unparseable project pipeline.yaml falls back to defaults" {
  printf 'review:\n  pivot_after_cycles: !!binary |\n  : not valid yaml at all\n{{{bad}}}' \
    > "$BANK/pipeline.yaml"
  decide 2 3
  [ "$status" -eq 0 ]
  [ "$output" = "pivot_in_role" ]
}

# ---- prompt-prefix ---------------------------------------------------------

@test "prompt-prefix: pivot_in_role contains 'Discard it' and 'Pivot rationale' markers" {
  run bash "$RUN" prompt-prefix --mode pivot_in_role --stagnant 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discard it"* ]]
  [[ "$output" == *"Pivot rationale"* ]]
}

@test "prompt-prefix: pivot_via_architect also documents the two-step escalation" {
  run bash "$RUN" prompt-prefix --mode pivot_via_architect --stagnant 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"Discard it"* ]]
  [[ "$output" == *"Pivot rationale"* ]]
  [[ "$output" == *"mb-architect"* ]]
}

@test "prompt-prefix: invalid --mode -> usage error, exit 2" {
  run bash "$RUN" prompt-prefix --mode bogus --stagnant 2
  [ "$status" -eq 2 ]
}
