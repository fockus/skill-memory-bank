#!/usr/bin/env bats
# candidate_publish: — svp-sdd-core C4a deterministic candidate lifecycle
# (scripts/mb-sdd-candidate.sh, REQ-010/053, closes R3-002/R3-003).
#
# Name convention (X-05): every @test starts with `candidate_publish: ` so the
# Eval red-anchor `not ok [0-9]+ candidate_publish: ` is a positive named prefix
# (a run against a missing script yields a differently-named bats failure).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-sdd-candidate.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  TOPIC="demo"
  mkdir -p "$BANK/tmp/sdd/$TOPIC" "$BANK/specs/$TOPIC"
  CAND="$BANK/tmp/sdd/$TOPIC/tasks.candidate.md"
  FINAL="$BANK/specs/$TOPIC/tasks.md"
  printf 'CANDIDATE CONTENT\n' > "$CAND"
  printf 'ORIGINAL FINAL\n' > "$FINAL"
  # The bank is resolved, never inferred from the candidate path (review [6]).
  # Tests that omit --mb declare the active bank the ordinary way instead.
  export MB_PATH="$BANK"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# _estimate <spec> <task_over> <stage_over>  → path to an estimate verdict file.
_estimate() {
  local f="$TMP/estimate.txt"
  printf 'spec.total=100000\ntask_over=%s\nstage_over=%s\nspec=%s\nlegacy_missing=none\n' \
    "$2" "$3" "$1" > "$f"
  printf '%s\n' "$f"
}

_final_sum() { cksum < "$FINAL"; }

# ── happy path ───────────────────────────────────────────────────────────────

@test "candidate_publish: spec=ok no overflow → published, final replaced, candidate gone" {
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
  [ ! -e "$CAND" ]                              # candidate moved
  [ "$(cat "$FINAL")" = "CANDIDATE CONTENT" ]   # final == candidate bytes
}

@test "candidate_publish: spec=near → published" {
  local est; est="$(_estimate near none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
}

# ── override matrix (R3-003) ─────────────────────────────────────────────────

@test "candidate_publish: spec=over without override → blocked spec_overflow, final byte-identical" {
  local before; before="$(_final_sum)"
  local est; est="$(_estimate over none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate=blocked"* ]]
  [[ "$output" == *"reason=spec_overflow"* ]]
  [ "$(_final_sum)" = "$before" ]               # final untouched
  [ ! -e "$CAND" ]                              # candidate discarded
}

@test "candidate_publish: spec=over + --override user (no task/stage over) → published" {
  local est; est="$(_estimate over none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --override user --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
  [ "$(cat "$FINAL")" = "CANDIDATE CONTENT" ]
}

@test "candidate_publish: task_over set + --override user → blocked task_overflow (hard cap unbreakable)" {
  local before; before="$(_final_sum)"
  local est; est="$(_estimate ok 3 none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --override user
  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate=blocked"* ]]
  [[ "$output" == *"reason=task_overflow"* ]]
  [ "$(_final_sum)" = "$before" ]
}

@test "candidate_publish: stage_over set + --override user → blocked stage_overflow" {
  local before; before="$(_final_sum)"
  local est; est="$(_estimate ok none 2)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --override user --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=stage_overflow"* ]]
  [ "$(_final_sum)" = "$before" ]
}

@test "candidate_publish: combined task+stage over + --override user → blocked (task precedence)" {
  local est; est="$(_estimate over 3 2)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --override user
  [ "$status" -eq 1 ]
  [[ "$output" == *"candidate=blocked"* ]]
  [[ "$output" == *"reason=task_overflow"* ]]
}

# ── malformed / non-canonical → exit 2 ───────────────────────────────────────

@test "candidate_publish: malformed verdict (no spec=) → exit 2, final byte-identical" {
  local before; before="$(_final_sum)"
  printf 'task_over=none\nstage_over=none\n' > "$TMP/bad.txt"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$TMP/bad.txt"
  [ "$status" -eq 2 ]
  [ "$(_final_sum)" = "$before" ]
}

@test "candidate_publish: non-canonical --candidate path → exit 2" {
  local off="$TMP/wrong/tasks.candidate.md"; mkdir -p "$TMP/wrong"; printf 'x\n' > "$off"
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$off" --estimate-file "$est"
  [ "$status" -eq 2 ]
}

@test "candidate_publish: missing estimate file → exit 2" {
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$TMP/nope.txt"
  [ "$status" -eq 2 ]
}

# ── discard ──────────────────────────────────────────────────────────────────

@test "candidate_publish: discard removes candidate, final untouched" {
  local before; before="$(_final_sum)"
  run --separate-stderr "$SCRIPT" discard --topic "$TOPIC" --candidate "$CAND"
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=discarded"* ]]
  [ ! -e "$CAND" ]
  [ "$(_final_sum)" = "$before" ]
}

# ── path containment (blocker #3) ────────────────────────────────────────────

@test "candidate_publish: topic path-traversal is rejected → exit 2, nothing written outside bank" {
  mkdir -p "$BANK/tmp/sdd"
  local evil="$BANK/tmp/sdd/../../escaped/tasks.candidate.md"
  mkdir -p "$(dirname "$evil")"; printf 'EVIL\n' > "$evil"
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic '../../escaped' --candidate "$evil" --estimate-file "$est" --mb "$BANK"
  [ "$status" -eq 2 ]
  [ ! -e "$TMP/escaped/tasks.md" ]
}

@test "candidate_publish: candidate from another bank via --mb is rejected → exit 2, target byte-identical" {
  local other="$TMP/other/.memory-bank"
  mkdir -p "$other/tmp/sdd/$TOPIC"; printf 'FROM_OTHER\n' > "$other/tmp/sdd/$TOPIC/tasks.candidate.md"
  local before; before="$(_final_sum)"
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" \
    --candidate "$other/tmp/sdd/$TOPIC/tasks.candidate.md" --estimate-file "$est" --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$(_final_sum)" = "$before" ]
}

# ── bank resolution + symlink containment (S2 review [6]/[7]) ────────────────

@test "candidate_publish: without --mb the active bank is resolved, a foreign candidate is rejected" {
  local foreign="$TMP/foreign"
  mkdir -p "$foreign/tmp/sdd/$TOPIC"
  printf 'FOREIGN\n' > "$foreign/tmp/sdd/$TOPIC/tasks.candidate.md"
  local est; est="$(_estimate ok none none)"
  # cwd carries an active bank ($TMP/.memory-bank); the candidate names another.
  unset MB_PATH
  cd "$TMP" || return 1
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" \
    --candidate "$foreign/tmp/sdd/$TOPIC/tasks.candidate.md" --estimate-file "$est"
  [ "$status" -eq 2 ]
  [ ! -e "$foreign/specs/$TOPIC/tasks.md" ]
}

@test "candidate_publish: without --mb a candidate inside the resolved active bank still publishes" {
  local est; est="$(_estimate ok none none)"
  unset MB_PATH
  cd "$TMP" || return 1
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
  [ "$(cat "$FINAL")" = "CANDIDATE CONTENT" ]
}

@test "candidate_publish: symlinked specs/<topic> cannot redirect publish outside the bank → exit 2" {
  local victim="$TMP/victim"; mkdir -p "$victim"; printf 'VICTIM\n' > "$victim/tasks.md"
  rm -rf "${BANK:?}/specs/$TOPIC"
  ln -s "$victim" "$BANK/specs/$TOPIC"
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$(cat "$victim/tasks.md")" = "VICTIM" ]
  [ -e "$CAND" ]
}

@test "candidate_publish: symlinked tasks.md inside specs/<topic> is not followed on publish → exit 2" {
  local victim="$TMP/victim"; mkdir -p "$victim"; printf 'VICTIM\n' > "$victim/tasks.md"
  rm -f "$FINAL"
  ln -s "$victim/tasks.md" "$FINAL"
  local est; est="$(_estimate ok none none)"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$est" --mb "$BANK"
  [ "$status" -eq 2 ]
  [ "$(cat "$victim/tasks.md")" = "VICTIM" ]
}

# ── strict C3 grammar (blocker #8) ───────────────────────────────────────────

@test "candidate_publish: unknown verdict key → exit 2, final byte-identical" {
  local before; before="$(_final_sum)"
  printf 'spec=ok\ntask_over=none\nstage_over=none\nunknown_key=spoof\n' > "$TMP/bad.txt"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$TMP/bad.txt"
  [ "$status" -eq 2 ]
  [ -e "$CAND" ]                    # candidate not consumed
  [ "$(_final_sum)" = "$before" ]
}

@test "candidate_publish: duplicate verdict key → exit 2" {
  printf 'spec=ok\nspec=near\ntask_over=none\nstage_over=none\n' > "$TMP/dup.txt"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$TMP/dup.txt"
  [ "$status" -eq 2 ]
}

@test "candidate_publish: full valid C3 grammar (task.N/stage.N/spec.total) → published" {
  printf 'task.1=100\nstage.1=100\nspec.total=100\ntask_over=none\nstage_over=none\nspec=ok\nlegacy_missing=none\n' > "$TMP/full.txt"
  run --separate-stderr "$SCRIPT" publish --topic "$TOPIC" --candidate "$CAND" --estimate-file "$TMP/full.txt" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
}

# ── static analysis ──────────────────────────────────────────────────────────

@test "candidate_publish: shellcheck (style) clean" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -S style "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ── round-2 review [14]: the documented --force gate is enforced ─────────────

@test "candidate_publish: publish over an EXISTING spec triple is refused without --force" {
  # commands/sdd.md documents "--force — overwrite an existing spec triple
  # (refuses without it)"; publish used to rename straight over it.
  # setup() already wrote an accepted FINAL ("ORIGINAL FINAL").
  local before; before="$(_final_sum)"
  run bash "$SCRIPT" publish --topic "$TOPIC" \
    --candidate "$CAND" --estimate-file "$(_estimate ok none none)" --mb "$BANK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=spec_exists"* ]]
  # the accepted triple must be byte-identical afterwards
  [ "$(_final_sum)" = "$before" ]
}

@test "candidate_publish: publish over an existing spec triple succeeds WITH --force" {
  run bash "$SCRIPT" publish --topic "$TOPIC" \
    --candidate "$CAND" --estimate-file "$(_estimate ok none none)" --mb "$BANK" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"candidate=published"* ]]
  grep -q 'CANDIDATE CONTENT' "$FINAL"
}

@test "candidate_publish: every @test name carries the declared red-anchor prefix" {
  # The anchor is only load-bearing if it matches EVERY test: two --force tests
  # were named `candidate: `, so a regression confined to the force gate would
  # never match `not ok [0-9]+ candidate_publish: ` and would be dismissed as a
  # foreign failure (r3 review [9]).
  local bad
  bad="$(grep -E '^@test ' "$BATS_TEST_FILENAME" \
        | grep -vE '^@test "candidate_publish: ' || true)"
  [ -z "$bad" ] || { echo "tests outside the declared red anchor:"; echo "$bad"; false; }
}
