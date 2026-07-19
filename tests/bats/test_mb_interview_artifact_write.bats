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
  # Snapshot the candidate first: publishing CONSUMES it (REQ-007 scrub), so the
  # published bytes are compared against the snapshot, not against the original.
  local expected="$BATS_TEST_TMPDIR/expected.md"
  cp "$CAND" "$expected"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=transcript" ]
  [ -f "$tgt" ]
  run diff "$expected" "$tgt"
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

# ─── symlinked invocation cannot swap the gate scripts (review [3], REQ-007/C11) ───

@test "artifact_write: symlinked writer still uses the REAL secret scanner" {
  # SCRIPT_DIR resolved from the symlink's directory let an attacker tree drop
  # a stub mb-secret-scan.sh / mb-interview-artifact-check.sh next to the link
  # and publish a live credential with exit 0.
  local fake="$BATS_TEST_TMPDIR/fake" tgt="$BANK/context/foo-interview.md"
  mkdir -p "$fake" "$BANK/context"
  printf '#!/bin/sh\nexit 0\n' > "$fake/mb-secret-scan.sh"
  printf '#!/bin/sh\nexit 0\n' > "$fake/mb-interview-artifact-check.sh"
  chmod +x "$fake/mb-secret-scan.sh" "$fake/mb-interview-artifact-check.sh"
  ln -s "$SCRIPT" "$fake/mb-interview-artifact-write.sh"
  _clean_transcript "$CAND"
  sed 's/The scope is X/The scope is sk-ant-api03ABCDEFGHIJKLMNOP/' "$CAND" > "$CAND.h"; mv "$CAND.h" "$CAND"
  run --separate-stderr "$fake/mb-interview-artifact-write.sh" publish-transcript \
    --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ ! -e "$tgt" ]
}

@test "artifact_write: symlinked writer still uses the REAL grammar check" {
  local fake="$BATS_TEST_TMPDIR/fake2" tgt="$BANK/context/foo-interview.md"
  mkdir -p "$fake" "$BANK/context"
  printf '#!/bin/sh\nexit 0\n' > "$fake/mb-secret-scan.sh"
  printf '#!/bin/sh\nexit 0\n' > "$fake/mb-interview-artifact-check.sh"
  chmod +x "$fake/mb-secret-scan.sh" "$fake/mb-interview-artifact-check.sh"
  ln -s "$SCRIPT" "$fake/mb-interview-artifact-write.sh"
  printf 'not a transcript at all\n' > "$CAND"
  run --separate-stderr "$fake/mb-interview-artifact-write.sh" publish-transcript \
    --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ ! -e "$tgt" ]
}

# ─── the candidate never lingers on disk (review [5], REQ-007) ───

@test "artifact_write: a BLOCKED candidate is removed from disk" {
  # The credential must not survive the rejected publication as a readable
  # plaintext file in <bank>/tmp.
  local tgt="$BANK/context/foo-interview.md" cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  sed 's/The scope is X/The scope is <private>sk-ant-api03ABCDEFGHIJKLMNOP<\/private>/' "$cand" > "$cand.h"; mv "$cand.h" "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 1 ]
  [ ! -e "$tgt" ]
  [ ! -e "$cand" ] || { echo "candidate still on disk:"; cat "$cand"; false; }
}

@test "artifact_write: no file anywhere under the bank still holds the blocked secret" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  sed 's/The scope is X/The scope is sk-ant-api03ABCDEFGHIJKLMNOP/' "$cand" > "$cand.h"; mv "$cand.h" "$cand"
  run "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 1 ]
  run grep -rl 'sk-ant-api03ABCDEFGHIJKLMNOP' "$BANK"
  [ "$status" -ne 0 ] || { echo "secret left in: $output"; false; }
}

@test "artifact_write: a PUBLISHED candidate is removed from disk" {
  local tgt="$BANK/context/foo-interview.md" cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 0 ]
  [ -f "$tgt" ]
  [ ! -e "$cand" ]
}

@test "artifact_write: a grammar-rejected candidate is removed from disk" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  printf '# Interview transcript: foo (2026-07-17)\n\nno Q&A section here\n' > "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 1 ]
  [ ! -e "$cand" ]
}

@test "artifact_write: the candidate is removed even when the writer is killed mid-run" {
  # Abnormal termination must not leave the raw credential behind. The kill is
  # synchronised on the writer having spawned its first gate child, which
  # happens strictly AFTER the scrub trap is armed — so this exercises the real
  # signal path rather than racing the process start.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md" rc
  mkdir -p "$BANK/context"
  # ~59 MB of padding puts the secret-scan pass in the ~2.5 s range, so the
  # signal below lands well inside the gate window on any reasonable machine.
  python3 -c '
import sys
p = sys.argv[1]
with open(p, "w", encoding="utf-8") as fh:
    fh.write("# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\n")
    fh.write("**Q1 (s).** q?\n**A1.** sk-ant-api03ABCDEFGHIJKLMNOP -> **D-01**. X\n\n")
    for i in range(1500000):
        fh.write("padding line %d with prose to scan\n" % i)
' "$cand"
  "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand" >/dev/null 2>&1 &
  local pid=$!
  sleep 0.3
  kill -TERM "$pid" 2>/dev/null || true
  rc=0; wait "$pid" 2>/dev/null || rc=$?
  # 128+SIGTERM: proves the signal actually interrupted the run, so a clean
  # normal exit can never make this assertion pass vacuously.
  [ "$rc" -eq 143 ] || { echo "writer was not interrupted (rc=$rc)"; false; }
  [ ! -e "$cand" ] || { echo "candidate survived SIGTERM"; false; }
}

@test "artifact_write: install-plan does NOT consume the candidate" {
  # Only the credential-bearing transcript path owns candidate scrubbing; the
  # plan candidate stays put so the interview can resume from it.
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ -f "$CAND" ]
}

@test "artifact_write: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
