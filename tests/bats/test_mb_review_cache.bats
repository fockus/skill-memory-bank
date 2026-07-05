#!/usr/bin/env bats
# Tests for scripts/mb-review-cache.sh TTL cache contract (reviewer-2.0 Task 1,
# design.md §5 "Hit/miss algorithm" + §8 test_mb_review_cache).
#
# Cache file: <mb>/tmp/last-tests.json
#   HIT  when: file exists AND schema_version==1 AND touched_files_sha matches
#              AND now() - parse(run_id timestamp) < ttl (default 600s)
#   MISS otherwise (missing file, sha mismatch, schema mismatch, TTL expiry)
#
# Subcommands under test:
#   write --mb <bank> --sha <sha> [--run-id <id>] < evidence-json
#   check --mb <bank> --sha <sha> [--ttl <sec>]      -> stdout HIT|MISS, exit 0|1
#   clear --mb <bank>                                 -> removes cache file

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-review-cache.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

cache_file() {
  printf '%s/tmp/last-tests.json' "$BANK"
}

write_green() {
  # $1 = sha, $2 = optional run_id override
  local sha="$1" run_id="${2:-}"
  local args=(write --mb "$BANK" --sha "$sha")
  [ -n "$run_id" ] && args+=(--run-id "$run_id")
  printf '{"tests_pass": true, "counts": {"passed": 3, "failed": 0, "skipped": 0}}' \
    | bash "$RUN" "${args[@]}"
}

@test "mb-review-cache.sh: --help exits 0 and mentions check" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"check"* ]]
}

@test "write: creates <mb>/tmp/last-tests.json with schema_version 1" {
  run write_green "sha256:abc123"
  [ "$status" -eq 0 ]
  [ -f "$(cache_file)" ]
  run bash -c "python3 -c \"import json; d=json.load(open('$(cache_file)')); print(d['schema_version'])\""
  [ "$output" = "1" ]
}

@test "check: sha stability across re-runs with identical inputs -> HIT both times" {
  write_green "sha256:stable-sha"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:stable-sha"
  [ "$status" -eq 0 ]
  [ "$output" = "HIT" ]
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:stable-sha"
  [ "$status" -eq 0 ]
  [ "$output" = "HIT" ]
}

@test "check: sha mismatch -> MISS" {
  write_green "sha256:one-sha"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:different-sha"
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "check: no cache file at all -> MISS" {
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:whatever"
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "check: TTL expiry (old run_id timestamp) -> MISS even though sha matches" {
  write_green "sha256:aged-sha" "2000-01-01T00:00:00Z-aaaaaa"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:aged-sha" --ttl 600
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "check: fresh run_id within TTL -> HIT" {
  now_run_id=$(python3 -c "import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ') + '-abcdef')")
  write_green "sha256:fresh-sha" "$now_run_id"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:fresh-sha" --ttl 600
  [ "$status" -eq 0 ]
  [ "$output" = "HIT" ]
}

@test "check: custom short TTL expires an otherwise-fresh cache" {
  # Build a run_id 30 seconds old and check against a 5-second TTL -> MISS.
  run_id=$(python3 -c "
import datetime
ts = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(seconds=30)
print(ts.strftime('%Y-%m-%dT%H:%M:%SZ') + '-abcdef')
")
  write_green "sha256:short-ttl-sha" "$run_id"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:short-ttl-sha" --ttl 5
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "check: schema_version mismatch -> MISS" {
  mkdir -p "$BANK/tmp"
  cat >"$(cache_file)" <<JSON
{"schema_version": 2, "run_id": "2026-01-01T00:00:00Z-abcdef", "touched_files_sha": "sha256:x", "tests_pass": true, "counts": {"passed": 1, "failed": 0, "skipped": 0}, "coverage": {}, "failures": [], "elapsed_sec": 1}
JSON
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:x" --ttl 600
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "check: missing schema_version field -> MISS" {
  mkdir -p "$BANK/tmp"
  cat >"$(cache_file)" <<JSON
{"run_id": "2026-01-01T00:00:00Z-abcdef", "touched_files_sha": "sha256:x", "tests_pass": true}
JSON
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:x" --ttl 600
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "clear: removes the cache file idempotently (--refresh-tests support)" {
  write_green "sha256:to-be-cleared"
  [ -f "$(cache_file)" ]
  run bash "$RUN" clear --mb "$BANK"
  [ "$status" -eq 0 ]
  [ ! -f "$(cache_file)" ]
  # Clearing again (already absent) must not error.
  run bash "$RUN" clear --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "clear then check -> forced MISS even with a sha that previously HIT" {
  write_green "sha256:refresh-me"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:refresh-me"
  [ "$output" = "HIT" ]
  bash "$RUN" clear --mb "$BANK"
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha "sha256:refresh-me"
  [ "$status" -eq 1 ]
  [ "$output" = "MISS" ]
}

@test "write: rejects evidence JSON missing boolean tests_pass" {
  run bash -c "printf '{\"counts\": {}}' | bash '$RUN' write --mb '$BANK' --sha sha256:bad"
  [ "$status" -eq 2 ]
}

@test "check: a value flag as the last arg with no value -> exit 2 with a non-empty stderr message (never a silent exit 1)" {
  run --separate-stderr bash "$RUN" check --mb "$BANK" --sha
  [ "$status" -eq 2 ]
  [ -n "$stderr" ]
}
