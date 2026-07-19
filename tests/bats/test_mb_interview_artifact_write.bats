#!/usr/bin/env bats
# artifact_write: — svp-interview-upgrade C11 deterministic file-effect writer,
# `install-plan` mode (Task 1). `publish-transcript` is added by Task 4.
# Proves the real target BEFORE/AFTER the call (atomic write; byte-identity on
# rejection) — a scanner "target unchanged" assertion alone doesn't prove
# production orchestration (SVP-IU-002).
#
# Name convention: every @test starts with `artifact_write: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-interview-artifact-write.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK/tmp"
  CAND="$BATS_TEST_TMPDIR/candidate.md"
  TARGET="$BANK/tmp/interview-plan-foo.md"
}

_valid_open_plan() {
  cat > "$1" <<'EOF'
## Inherited decisions (do not re-ask)

- none

## Topics

- [ ] purpose
- [ ] edge cases

## Discovered mid-interview

- [ ] telemetry
EOF
}

_broken_plan() {
  cat > "$1" <<'EOF'
## Inherited decisions (do not re-ask)

- none

## Topics

* purpose

## Discovered mid-interview

- [ ] telemetry
EOF
}

@test "artifact_write: the writer script is present" {
  run assert_script_present scripts/mb-interview-artifact-write.sh
  [ "$status" -eq 0 ]
}

@test "artifact_write: valid candidate installs the plan (target appears)" {
  _valid_open_plan "$CAND"
  [ ! -e "$TARGET" ]
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=plan" ]
  [ -f "$TARGET" ]
  run diff "$CAND" "$TARGET"
  [ "$status" -eq 0 ]
}

@test "artifact_write: valid candidate atomically replaces an existing target" {
  printf 'stale content\n' > "$TARGET"
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  run diff "$CAND" "$TARGET"
  [ "$status" -eq 0 ]
}

@test "artifact_write: structurally broken candidate → exit 1, stdout empty, target unchanged" {
  printf 'PRIOR\n' > "$TARGET"
  local before; before="$(cat "$TARGET")"
  _broken_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(cat "$TARGET")" = "$before" ]
}

@test "artifact_write: broken candidate does not create a missing target" {
  [ ! -e "$TARGET" ]
  _broken_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ ! -e "$TARGET" ]
}

@test "artifact_write: missing --candidate → usage error exit 2" {
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
}

@test "artifact_write: unknown subcommand → usage error exit 2" {
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" frobnicate --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "artifact_write: unreadable candidate → usage error exit 2" {
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

# ─── publish-transcript mode (Task 4, C11) ───

_clean_transcript() {
  cat > "$1" <<'EOF'
# Interview transcript: foo (2026-07-17)

## Q&A

**Q1 (scope).** What is the scope?
**A1.** The scope is X → **D-01**. Отклонено: none

**Финальный гейт.** Anything to add?
**Ответ.** No.
EOF
}

@test "artifact_write: clean candidate publishes the transcript (git target appears)" {
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  [ ! -e "$tgt" ]
  _clean_transcript "$CAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=transcript" ]
  [ -f "$tgt" ]
  run diff "$CAND" "$tgt"
  [ "$status" -eq 0 ]
}

@test "artifact_write: candidate with a secret → exit 1, git target not created (R3-001)" {
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$CAND"
  # Secret placed inside <private> — must still block the git write.
  sed 's/The scope is X/The scope is <private>sk-ant-api03ABCDEFGHIJKLMNOP<\/private>/' "$CAND" > "$CAND.h"; mv "$CAND.h" "$CAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ ! -e "$tgt" ]
}

@test "artifact_write: broken-grammar candidate → exit 1, existing target byte-identical" {
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  printf 'PRIOR TRANSCRIPT\n' > "$tgt"
  local before; before="$(cat "$tgt")"
  printf '# Wrong header\n\nno q&a here\n' > "$CAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$(cat "$tgt")" = "$before" ]
}

@test "artifact_write: publish-transcript missing --candidate → usage error exit 2" {
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

# ─── topic path-traversal guard (R3-001) ───

@test "artifact_write: publish-transcript --topic ../../escaped → exit 2, nothing written outside bank" {
  _clean_transcript "$CAND"
  local outside="$BATS_TEST_TMPDIR/escaped-interview.md"
  rm -f "$outside"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic ../../escaped --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=topic" ]
  [ ! -e "$outside" ]
}

@test "artifact_write: install-plan --topic ../../escaped → exit 2, nothing written outside bank" {
  _valid_open_plan "$CAND"
  local outside="$BATS_TEST_TMPDIR/interview-plan-escaped.md"
  rm -f "$outside"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic ../../escaped --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=topic" ]
  [ ! -e "$outside" ]
}

@test "artifact_write: topic with a slash → exit 2 (rejected before any write)" {
  _clean_transcript "$CAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo/bar --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=topic" ]
  [ ! -e "$BANK/context/foo/bar-interview.md" ]
}

@test "artifact_write: topic with uppercase / double dash → exit 2" {
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic Foo --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=topic" ]
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic a--b --candidate "$CAND"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=topic" ]
}

@test "artifact_write: kebab-case multi-word topic still installs" {
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic svp-interview-upgrade --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=plan" ]
  [ -f "$BANK/tmp/interview-plan-svp-interview-upgrade.md" ]
}

@test "artifact_write: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
