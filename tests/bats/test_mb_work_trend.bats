#!/usr/bin/env bats
# Tests for scripts/mb-work-trend.sh — the trend calculator + previous-verdict
# cache (work-loop-v2 design.md §5 "Strategic pivoting" / "Trend signal",
# REQ-111/REQ-114).
#
# Contract under test:
#   weighted_score(verdict) = 10*counts.blocker + 3*counts.major + 1*counts.minor
#   improving:  current < previous (strictly less)
#   stagnant:   |current - previous| <= 1 AND current > 0
#   regressing: current > previous
#   null:       first cycle (no previous) -- also the chosen output for the
#               0/0 "converged" edge (see scripts/mb-work-trend.sh comment).
#
# Cache: <bank>/tmp/last-verdict-<item-key>.json, item-key = sha256(plan|stage|item)
# (same directory/filename convention as scripts/mb-review.sh's
# last_verdict_cache_path, which is still inert -- see script header note on
# reconciling the two key derivations).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-work-trend.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

verdict_json() {
  # $1=blocker $2=major $3=minor -> a minimal normalized-verdict JSON blob
  # (the shape scripts/mb-work-review-parse.sh emits on stdout).
  local b="$1" m="$2" n="$3"
  printf '{"verdict":"CHANGES_REQUESTED","counts":{"blocker":%s,"major":%s,"minor":%s},"issues":[]}' "$b" "$m" "$n"
}

approved_json() {
  printf '{"verdict":"APPROVED","counts":{"blocker":0,"major":0,"minor":0},"issues":[]}'
}

@test "mb-work-trend.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "--help exits 0 and documents key and compute subcommands" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"key"* ]]
  [[ "$output" == *"compute"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus
  [ "$status" -eq 2 ]
}

# ---- key subcommand ---------------------------------------------------------

@test "key: prints a 64-char lowercase hex sha256 digest" {
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 1
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
}

@test "key: deterministic for identical inputs" {
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 1
  first="$output"
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 1
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "key: differs when item_no differs (same plan/stage)" {
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 1
  first="$output"
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 2
  [ "$status" -eq 0 ]
  [ "$first" != "$output" ]
}

@test "key: differs when stage differs (same plan/item)" {
  run bash "$RUN" key --plan /p/plan.md --stage 3 --item 1
  first="$output"
  run bash "$RUN" key --plan /p/plan.md --stage 4 --item 1
  [ "$status" -eq 0 ]
  [ "$first" != "$output" ]
}

@test "key: differs when plan differs (same stage/item)" {
  run bash "$RUN" key --plan /p/plan-a.md --stage 3 --item 1
  first="$output"
  run bash "$RUN" key --plan /p/plan-b.md --stage 3 --item 1
  [ "$status" -eq 0 ]
  [ "$first" != "$output" ]
}

@test "key: missing required flag -> exit 2" {
  run bash "$RUN" key --plan /p/plan.md --stage 3
  [ "$status" -eq 2 ]
}

# ---- compute subcommand -----------------------------------------------------

@test "compute: first cycle (no previous cache) -> null, and stores the cache" {
  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --mb '$BANK' --item-key firstcycle"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [ -f "$BANK/tmp/last-verdict-firstcycle.json" ]
}

@test "compute: improving -- blocker(1) then major(1) (10 -> 3, strictly less)" {
  printf '%s' "$(verdict_json 1 0 0)" | bash "$RUN" compute --mb "$BANK" --item-key impkey >/dev/null

  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key impkey"
  [ "$status" -eq 0 ]
  [ "$output" = "improving" ]
}

@test "compute: stagnant -- |delta|<=1 with current>0 (major:1 -> major:1, 3 -> 3)" {
  printf '%s' "$(verdict_json 0 1 0)" | bash "$RUN" compute --mb "$BANK" --item-key stagkey >/dev/null

  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key stagkey"
  [ "$status" -eq 0 ]
  [ "$output" = "stagnant" ]
}

@test "compute: stagnant -- delta of 1 counts (minor:3 -> minor:4, 3 -> 4)" {
  printf '%s' "$(verdict_json 0 0 3)" | bash "$RUN" compute --mb "$BANK" --item-key stagkey2 >/dev/null

  run bash -c "printf '%s' '$(verdict_json 0 0 4)' | bash '$RUN' compute --mb '$BANK' --item-key stagkey2"
  [ "$status" -eq 0 ]
  [ "$output" = "stagnant" ]
}

@test "compute: regressing -- minor(1) then blocker(1) (1 -> 10, strictly more)" {
  printf '%s' "$(verdict_json 0 0 1)" | bash "$RUN" compute --mb "$BANK" --item-key regkey >/dev/null

  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --mb '$BANK' --item-key regkey"
  [ "$status" -eq 0 ]
  [ "$output" = "regressing" ]
}

@test "compute: 0/0 converged (APPROVED -> APPROVED) is documented as null, not stagnant/improving" {
  printf '%s' "$(approved_json)" | bash "$RUN" compute --mb "$BANK" --item-key zerokey >/dev/null

  run bash -c "printf '%s' '$(approved_json)' | bash '$RUN' compute --mb '$BANK' --item-key zerokey"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "compute: cache overwrite -- second compute sees the first cycle's verdict as previous" {
  printf '%s' "$(verdict_json 1 0 0)" | bash "$RUN" compute --mb "$BANK" --item-key chainkey >/dev/null

  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key chainkey"
  [ "$status" -eq 0 ]
  [ "$output" = "improving" ]

  # Third cycle: previous is now major:1 (score 3) from the second call above.
  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key chainkey"
  [ "$status" -eq 0 ]
  [ "$output" = "stagnant" ]
}

@test "compute: corrupt cache file degrades to null (never crashes)" {
  mkdir -p "$BANK/tmp"
  printf 'not-json-{{{' >"$BANK/tmp/last-verdict-corruptkey.json"

  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --mb '$BANK' --item-key corruptkey"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "compute: missing cache directory degrades to null (never crashes)" {
  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --mb '$BANK/does-not-exist-yet' --item-key freshkey"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}

@test "compute: --verdict-file is accepted as an alternative to stdin" {
  vfile="$BATS_TEST_TMPDIR/verdict.json"
  printf '%s' "$(verdict_json 1 0 0)" >"$vfile"
  run bash "$RUN" compute --mb "$BANK" --item-key filekey --verdict-file "$vfile"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
  [ -f "$BANK/tmp/last-verdict-filekey.json" ]
}

@test "compute: --no-store does not overwrite the cache for the next cycle" {
  printf '%s' "$(verdict_json 1 0 0)" | bash "$RUN" compute --mb "$BANK" --item-key nostorekey >/dev/null

  # This second call must NOT persist (its output would be "improving" but
  # --no-store means it must not become "previous" for the next call).
  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key nostorekey --no-store"
  [ "$status" -eq 0 ]
  [ "$output" = "improving" ]

  # Third call: previous must still be the FIRST cycle's blocker:1 (score 10),
  # not the second (no-store) call's major:1 (score 3).
  run bash -c "printf '%s' '$(verdict_json 0 1 0)' | bash '$RUN' compute --mb '$BANK' --item-key nostorekey"
  [ "$status" -eq 0 ]
  [ "$output" = "improving" ]
}

@test "compute: missing --mb -> exit 2" {
  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --item-key x"
  [ "$status" -eq 2 ]
}

@test "compute: missing --item-key -> exit 2" {
  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | bash '$RUN' compute --mb '$BANK'"
  [ "$status" -eq 2 ]
}

@test "compute: empty stdin and no --verdict-file -> exit 2" {
  run bash -c "printf '' | bash '$RUN' compute --mb '$BANK' --item-key emptykey"
  [ "$status" -eq 2 ]
}

@test "bash 3.2 (/bin/bash) clean: key and compute both run under macOS system bash" {
  run /bin/bash "$RUN" key --plan /p/plan.md --stage 1 --item 1
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]

  run bash -c "printf '%s' '$(verdict_json 1 0 0)' | /bin/bash '$RUN' compute --mb '$BANK' --item-key bash32key"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
