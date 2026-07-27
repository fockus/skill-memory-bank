#!/usr/bin/env bats
# artifact_write: — svp-interview-upgrade C11 deterministic file-effect writer,
# `install-plan` mode (Task 1). `publish-transcript` is added by Task 4.
# Proves the real target BEFORE/AFTER the call (atomic write; byte-identity on
# rejection) — a scanner "target unchanged" assertion alone doesn't prove
# production orchestration (SVP-IU-002).
#
# Name convention: every @test starts with `artifact_write: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-interview-artifact-write.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK/tmp"
  CAND="$BATS_TEST_TMPDIR/candidate.md"
  TARGET="$BANK/tmp/interview-plan-foo.md"
  # publish-transcript owns exactly one candidate path (r2 review [4]); the plan
  # path stays free-form because install-plan never consumes its candidate.
  TCAND="$BANK/tmp/interview-transcript-foo.candidate.md"
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

# A `cp` interposer that publishes its destination in TWO chunks and parks
# between them: it touches $1 (the "reader may look now" signal) and waits for
# $2 (the reader's ack) before writing the tail. Only destinations whose name
# contains $3 are chunked; anything else is delegated to the real cp, so the
# writer's other copies (candidate staging) run untouched.
#
# This is what makes the atomicity assertion DETERMINISTIC instead of a timing
# race: the reader is guaranteed to look while the publish is half-done.
_chunked_cp_interposer() {
  local dir="$1" signal="$2" ack="$3" match="$4" realcp
  realcp="$(command -v cp)"
  mkdir -p "$dir"
  cat > "$dir/cp" <<EOF
#!/usr/bin/env bash
dst="\${@: -1}"
case "\$dst" in
  *"$match"*) ;;
  *) exec "$realcp" "\$@" ;;
esac
src="\${@: -2:1}"
"$(command -v python3)" - "\$src" "\$dst" "$signal" "$ack" <<'PYEOF'
import os, sys, time
src, dst, signal, ack = sys.argv[1:5]
data = open(src, "rb").read()
half = max(1, len(data) // 2)
with open(dst, "wb") as fh:
    fh.write(data[:half]); fh.flush(); os.fsync(fh.fileno())
    open(signal, "w").close()
    for _ in range(1000):
        if os.path.exists(ack):
            break
        time.sleep(0.01)
    fh.write(data[half:]); fh.flush(); os.fsync(fh.fileno())
PYEOF
EOF
  chmod +x "$dir/cp"
}

@test "artifact_write: a concurrent reader never sees a half-written target" {
  # The `diff candidate target` test below is satisfied by a plain truncating
  # `cp candidate target`: once the call returns the bytes match, even though a
  # reader could observe an empty or half-written plan meanwhile (r5 review [7]).
  # Here the publish is parked mid-write and a reader looks: the only permitted
  # observations are the COMPLETE old file or the COMPLETE new one.
  local bin="$BATS_TEST_TMPDIR/bin-atomic"
  local signal="$BATS_TEST_TMPDIR/.publishing" ack="$BATS_TEST_TMPDIR/.looked"
  local old="$BATS_TEST_TMPDIR/old.md" new="$BATS_TEST_TMPDIR/new.md"
  local seen="$BATS_TEST_TMPDIR/seen.md"

  printf 'PRIOR PLAN CONTENT that is long enough to be split in half\n' > "$TARGET"
  cp "$TARGET" "$old"
  _valid_open_plan "$CAND"
  cp "$CAND" "$new"
  _chunked_cp_interposer "$bin" "$signal" "$ack" "interview-plan-foo"

  local rc=0 i=0
  PATH="$bin:$PATH" "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND" \
    >"$BATS_TEST_TMPDIR/out.atomic" 2>&1 &
  local bg=$!
  while [ ! -e "$signal" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$signal" ] || { echo "the cp interposer never ran"; kill "$bg" 2>/dev/null; false; }
  # Look at the target EXACTLY while the publish is parked mid-write.
  if [ -e "$TARGET" ]; then command cp "$TARGET" "$seen"; else : > "$seen"; fi
  : > "$ack"
  wait "$bg" || rc=$?

  [ "$rc" -eq 0 ] || { echo "install failed (rc=$rc): $(cat "$BATS_TEST_TMPDIR/out.atomic")"; false; }
  cmp -s "$seen" "$old" || cmp -s "$seen" "$new" \
    || { echo "a reader observed a torn target:"; cat "$seen"; false; }
  # ...and the publish still completed.
  cmp -s "$CAND" "$TARGET" || { echo "the final target is not the candidate"; false; }
}

@test "artifact_write: valid candidate atomically replaces an existing target" {
  printf 'stale content\n' > "$TARGET"
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  run diff "$CAND" "$TARGET"
  [ "$status" -eq 0 ]
}

@test "artifact_write: install-plan publishes the bytes it validated, not a later rewrite" {
  # install-plan opened the candidate PATH twice: once for the C8 check and once
  # for the copy. A second run rewriting that shared path in between made the
  # writer print artifact_write=installed with exit 0 over bytes nothing had
  # validated — the installed plan then failed the very same check (r5 [3]).
  #
  # `awk` is interposed because the checker parses with it: the rewrite lands
  # exactly when validation finishes, deterministically.
  local bin="$BATS_TEST_TMPDIR/bin-plan" swapped="$BATS_TEST_TMPDIR/.plan-swapped"
  local validated="$BATS_TEST_TMPDIR/validated.md"
  mkdir -p "$bin"
  _valid_open_plan "$CAND"
  cp "$CAND" "$validated"
  _broken_plan "$BATS_TEST_TMPDIR/broken-payload.md"

  local realawk; realawk="$(command -v awk)"
  cat > "$bin/awk" <<EOF
#!/usr/bin/env bash
rc=0
"$realawk" "\$@" || rc=\$?
if [ ! -e "$swapped" ]; then
  : > "$swapped"
  cp "$BATS_TEST_TMPDIR/broken-payload.md" "$CAND" 2>/dev/null || true
fi
exit \$rc
EOF
  chmod +x "$bin/awk"

  PATH="$bin:$PATH" run --separate-stderr "$SCRIPT" install-plan \
    --mb "$BANK" --topic foo --candidate "$CAND"
  [ -e "$swapped" ] || { echo "the awk interposer never fired"; false; }
  [ "$status" -eq 0 ] || { echo "install failed (status=$status): $stderr"; false; }
  [ "$output" = "artifact_write=installed kind=plan" ]
  cmp -s "$validated" "$TARGET" \
    || { echo "installed bytes are not the validated bytes:"; diff "$validated" "$TARGET" || true; false; }
  # The user-visible consequence: what got installed must itself pass the gate.
  run --separate-stderr "$REPO_ROOT/scripts/mb-interview-artifact-check.sh" plan "$TARGET"
  [ "$status" -eq 0 ] || { echo "the installed plan does not pass C8: $stderr"; false; }
}

@test "artifact_write: structurally broken candidate → exit 1, stdout empty, target unchanged" {
  printf 'PRIOR\n' > "$TARGET"
  local before="$BATS_TEST_TMPDIR/.before.$$"; cp "$TARGET" "$before"
  _broken_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cmp -s "$before" "$TARGET" || { echo "bytes changed"; false; }
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

# Permission bits, portable across BSD (macOS) and GNU stat.
_wmode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }

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
  _clean_transcript "$TCAND"
  # Snapshot the candidate first: publishing CONSUMES it (REQ-007 scrub), so the
  # published bytes are compared against the snapshot, not against the original.
  local expected="$BATS_TEST_TMPDIR/expected.md"
  cp "$TCAND" "$expected"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$TCAND"
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=transcript" ]
  [ -f "$tgt" ]
  run diff "$expected" "$tgt"
  [ "$status" -eq 0 ]
}

@test "artifact_write: candidate with a secret → exit 1, git target not created (R3-001)" {
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$TCAND"
  # Secret placed inside <private> — must still block the git write.
  sed 's/The scope is X/The scope is <private>sk-ant-api03ABCDEFGHIJKLMNOP<\/private>/' "$TCAND" > "$TCAND.h"; mv "$TCAND.h" "$TCAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$TCAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ ! -e "$tgt" ]
}

@test "artifact_write: broken-grammar candidate → exit 1, existing target byte-identical" {
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  printf 'PRIOR TRANSCRIPT\n' > "$tgt"
  local before="$BATS_TEST_TMPDIR/.before.$$"; cp "$tgt" "$before"
  printf '# Wrong header\n\nno q&a here\n' > "$TCAND"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$TCAND"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  cmp -s "$before" "$tgt" || { echo "bytes changed"; false; }
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
  _clean_transcript "$TCAND"
  sed 's/The scope is X/The scope is sk-ant-api03ABCDEFGHIJKLMNOP/' "$TCAND" > "$TCAND.h"; mv "$TCAND.h" "$TCAND"
  run --separate-stderr "$fake/mb-interview-artifact-write.sh" publish-transcript \
    --mb "$BANK" --topic foo --candidate "$TCAND"
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
  printf 'not a transcript at all\n' > "$TCAND"
  run --separate-stderr "$fake/mb-interview-artifact-write.sh" publish-transcript \
    --mb "$BANK" --topic foo --candidate "$TCAND"
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
  # r4 [12]: the candidate PATH being gone proves nothing once `claim` renames it
  # into staging — with _SCRUB_DIR cleanup deleted this test stayed green while
  # the credential sat in <bank>/tmp/.mb-iaw.*/staged.md. Assert on the whole
  # scratch dir and on the secret itself, not on one path.
  local leftover
  leftover="$(find "$BANK/tmp" -maxdepth 1 -name '.mb-iaw.*' 2>/dev/null)"
  [ -z "$leftover" ] || { echo "staging dir survived SIGTERM: $leftover"; false; }
  # Captured first, asserted once: a bare `grep` inside an `if` body is a
  # DIAGNOSTIC, not an assertion — its failure cannot fail the test.
  local hits
  hits="$(grep -rl 'sk-ant-api03ABCDEFGHIJKLMNOP' "$BANK" 2>/dev/null || true)"
  [ -z "$hits" ] || { echo "the credential is still under the bank: $hits"; false; }
}

@test "artifact_write: install-plan does NOT consume the candidate" {
  # Only the credential-bearing transcript path owns candidate scrubbing; the
  # plan candidate stays put so the interview can resume from it.
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -eq 0 ]
  [ -f "$CAND" ]
}

# ─── the candidate is an OWNED, exact, regular path (r2 review [4]) ───

@test "artifact_write: the published target passed as its own --candidate is refused" {
  # Passing the live target as the candidate used to succeed, print
  # `artifact_write=installed`, and then let the EXIT scrub DELETE the published
  # transcript. The writer only ever owns the canonical candidate path.
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$tgt"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$tgt"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ -f "$tgt" ] || { echo "the writer destroyed the published target"; false; }
}

@test "artifact_write: a candidate outside <bank>/tmp is refused" {
  local out="$BATS_TEST_TMPDIR/elsewhere.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$out"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$out"
  [ "$status" -eq 2 ]
  [ ! -e "$BANK/context/foo-interview.md" ]
}

@test "artifact_write: a candidate under the wrong name in <bank>/tmp is refused" {
  local wrong="$BANK/tmp/not-the-candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$wrong"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$wrong"
  [ "$status" -eq 2 ]
  [ ! -e "$BANK/context/foo-interview.md" ]
}

@test "artifact_write: a SYMLINKED candidate is refused and its backing file is left intact" {
  # A blocked run used to unlink only the symlink, leaving the credential-bearing
  # backing file on disk while reporting the candidate consumed.
  local backing="$BANK/tmp/backing-raw.md" link="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  printf 'raw notes\nsk-ant-api03ABCDEFGHIJKLMNOP\n' > "$backing"
  ln -s "$backing" "$link"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$link"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ ! -e "$BANK/context/foo-interview.md" ]
  # Refused, so neither the link nor the file behind it was touched.
  [ -L "$link" ]
  [ -f "$backing" ]
}

# ─── cleanup is armed BEFORE validation (r2 review [5]) ───

_credential_candidate() {
  printf '# Interview transcript: foo (2026-07-17)\n\n## Q&A\n\nsk-ant-api03ABCDEFGHIJKLMNOP\n' > "$1"
}

@test "artifact_write: an invalid topic still consumes the credential candidate" {
  # The scrub used to be armed only after topic validation, so a run rejected on
  # `--topic Foo` left the raw credential readable under <bank>/tmp.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  _credential_candidate "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic Foo --candidate "$cand"
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived an invalid topic"; false; }
}

@test "artifact_write: an omitted topic still consumes the credential candidate" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  _credential_candidate "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --candidate "$cand"
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived a usage error"; false; }
}

@test "artifact_write: an unknown flag still consumes the credential candidate" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  _credential_candidate "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand" --bogus-flag
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived a flag usage error"; false; }
}

@test "artifact_write: an unknown flag BEFORE --candidate still consumes it" {
  # Flag order must not decide whether the credential is scrubbed.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  _credential_candidate "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --bogus-flag --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived a leading flag error"; false; }
}

# ─── the scanned bytes are the published bytes (r2 review [6]) ───

@test "artifact_write: a candidate mutated after the scan cannot publish a secret" {
  # TOCTOU: the scanner, the grammar checker and the final cp each used to open
  # the candidate PATH independently, so swapping the file after a clean scan
  # published a grammar-valid transcript carrying a live API key with exit 0.
  # `python3` is interposed on PATH so the swap lands exactly when the scan
  # returns — deterministic, not a timing race.
  #
  # r5 review [6]: asserting only "the target has no key" let an implementation
  # that simply REFUSES after the swap pass — it published nothing, and the
  # conditional `if [ -f "$tgt" ]` then asserted nothing at all. The contract is
  # stronger than "no secret": the bytes this writer CLAIMED must be the bytes
  # it publishes, so the run has to succeed and the target has to equal the
  # clean snapshot byte for byte.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context" "$BATS_TEST_TMPDIR/bin"
  _clean_transcript "$cand"
  local claimed="$BATS_TEST_TMPDIR/claimed.md"; cp "$cand" "$claimed"
  sed 's/The scope is X/The scope is sk-ant-api03ABCDEFGHIJKLMNOP/' "$cand" > "$BATS_TEST_TMPDIR/payload.md"

  # The interposer must forward BOTH shapes the writer uses: `python3 -` (the
  # scanner's here-doc program) and `python3 -c '<prog>'` (the atomic replace).
  # Consuming stdin for a `-c` call swallowed the writer's own stdin and skipped
  # the rename entirely, so the publication step never ran under this test — the
  # very step whose bytes are being certified.
  local realpy; realpy="$(command -v python3)"
  cat > "$BATS_TEST_TMPDIR/bin/python3" <<EOF
#!/usr/bin/env bash
rc=0
if [ "\$1" = "-" ]; then
  prog="\$(mktemp)"; cat > "\$prog"
  "$realpy" "\$prog" "\${@:2}" || rc=\$?
  rm -f "\$prog"
else
  "$realpy" "\$@" || rc=\$?
fi
if [ ! -e "$BATS_TEST_TMPDIR/.swapped" ]; then
  : > "$BATS_TEST_TMPDIR/.swapped"
  cp "$BATS_TEST_TMPDIR/payload.md" "$cand" 2>/dev/null || true
fi
exit \$rc
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/python3"

  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run --separate-stderr "$SCRIPT" \
    publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  # The scan must have actually run (the interposer fired), otherwise the test
  # would pass vacuously.
  [ -e "$BATS_TEST_TMPDIR/.swapped" ] || { echo "python3 interposer never fired"; false; }
  # The swap must be INERT, not fatal: the claimed bytes are published normally.
  [ "$status" -eq 0 ] || { echo "the swap broke the publication (status=$status): $stderr"; false; }
  [ "$output" = "artifact_write=installed kind=transcript" ]
  [ -f "$tgt" ] || { echo "nothing was published"; false; }
  cmp -s "$claimed" "$tgt" \
    || { echo "the published bytes are not the claimed bytes:"; diff "$claimed" "$tgt" || true; false; }
  # ...and, redundantly but explicitly, the swapped-in credential is not in it.
  refute_grep -q 'sk-ant-api03ABCDEFGHIJKLMNOP' "$tgt"
}

# ─── the claim must freeze the BYTES, not just the name (r5 review [1]) ──────

@test "artifact_write: a write through an fd held across the claim never reaches the target" {
  # commands/discuss.md gives two concurrent runs the SAME candidate path, so a
  # second run can be holding that file open when this one claims it. `mv` moves
  # the NAME and keeps the inode, so the other run's fd still pointed at the
  # staged bytes: it appended a credential AFTER the clean secret scan and the
  # writer published the mutated inode with exit 0.
  #
  # The interleaving is forced, not raced: the holder opens the file before the
  # writer starts, and the interposed python3 releases it exactly when the scan
  # returns, then waits until the write has landed before the run continues.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context" "$BATS_TEST_TMPDIR/bin-fd"
  _clean_transcript "$cand"
  local claimed="$BATS_TEST_TMPDIR/claimed-fd.md"; cp "$cand" "$claimed"

  local opened="$BATS_TEST_TMPDIR/.fd-open"
  local scanned="$BATS_TEST_TMPDIR/.fd-scanned"
  local wrote="$BATS_TEST_TMPDIR/.fd-wrote"
  python3 - "$cand" "$opened" "$scanned" "$wrote" <<'PY' &
import os, sys, time
cand, opened, scanned, wrote = sys.argv[1:5]
fh = open(cand, "ab")                 # the other run's still-open handle
open(opened, "w").close()
for _ in range(3000):
    if os.path.exists(scanned):
        break
    time.sleep(0.01)
fh.write(b"\nsk-ant-api03ABCDEFGHIJKLMNOP\n")
fh.flush()
fh.close()
open(wrote, "w").close()
PY
  local holder=$!
  local i=0
  while [ ! -e "$opened" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$opened" ] || { echo "the holder never opened the candidate"; false; }

  local realpy; realpy="$(command -v python3)"
  cat > "$BATS_TEST_TMPDIR/bin-fd/python3" <<EOF
#!/usr/bin/env bash
rc=0
if [ "\$1" = "-" ]; then
  prog="\$(mktemp)"; cat > "\$prog"
  "$realpy" "\$prog" "\${@:2}" || rc=\$?
  rm -f "\$prog"
else
  "$realpy" "\$@" || rc=\$?
fi
if [ ! -e "$scanned" ]; then
  : > "$scanned"
  i=0
  while [ ! -e "$wrote" ] && [ "\$i" -lt 1000 ]; do sleep 0.01; i=\$((i + 1)); done
fi
exit \$rc
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin-fd/python3"

  PATH="$BATS_TEST_TMPDIR/bin-fd:$PATH" run --separate-stderr "$SCRIPT" \
    publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  wait "$holder" 2>/dev/null || true
  [ -e "$wrote" ] || { echo "the concurrent write never happened"; false; }

  [ "$status" -eq 0 ] || { echo "publication failed (status=$status): $stderr"; false; }
  [ -f "$tgt" ] || { echo "nothing was published"; false; }
  cmp -s "$claimed" "$tgt" \
    || { echo "the published bytes are not the claimed bytes:"; diff "$claimed" "$tgt" || true; false; }
  refute_grep -q 'sk-ant-api03ABCDEFGHIJKLMNOP' "$tgt"
}

@test "artifact_write: a signal before the claim does not delete another run's candidate" {
  # Cleanup owned a PATHNAME. Between arming it and claiming the file, a second
  # run replaced the candidate with its own — and this run's SIGTERM handler
  # then `rm -f`'d the newcomer (r5 review [1], second interleaving).
  #
  # `basename` is interposed to park the writer inside that exact window: the
  # scrub is armed (the arm loop has run) and the claim has not happened yet.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  local bin="$BATS_TEST_TMPDIR/bin-own" pidf="$BATS_TEST_TMPDIR/pid-own"
  local parked="$BATS_TEST_TMPDIR/.parked" go="$BATS_TEST_TMPDIR/.go"
  local other="$BATS_TEST_TMPDIR/other.md"
  mkdir -p "$BANK/context" "$bin"
  _credential_candidate "$cand"

  local realbn; realbn="$(command -v basename)"
  cat > "$bin/basename" <<EOF
#!/usr/bin/env bash
n=0
[ -f "$BATS_TEST_TMPDIR/.bn" ] && n=\$(cat "$BATS_TEST_TMPDIR/.bn")
n=\$((n + 1)); printf '%s' "\$n" > "$BATS_TEST_TMPDIR/.bn"
if [ "\$n" -eq 2 ]; then
  : > "$parked"
  i=0
  while [ ! -e "$go" ] && [ "\$i" -lt 1000 ]; do sleep 0.01; i=\$((i + 1)); done
fi
exec "$realbn" "\$@"
EOF
  chmod +x "$bin/basename"

  ( echo $BASHPID > "$pidf"
    exec env PATH="$bin:$PATH" "$SCRIPT" publish-transcript \
      --mb "$BANK" --topic foo --candidate "$cand" ) >/dev/null 2>&1 &
  local bg=$! i=0
  while [ ! -e "$parked" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$parked" ] || { kill "$bg" 2>/dev/null; echo "the writer never parked"; false; }

  # The OTHER run publishes its own candidate at the shared path, then this run
  # is killed while it still believes it owns that pathname.
  printf 'ANOTHER RUN CANDIDATE\n' > "$cand"
  cp "$cand" "$other"
  kill -TERM "$(cat "$pidf")" 2>/dev/null || true
  : > "$go"
  wait "$bg" 2>/dev/null || true

  [ -f "$cand" ] || { echo "the other run's candidate was deleted"; false; }
  cmp -s "$other" "$cand" || { echo "the other run's candidate was modified"; false; }
}

# ─── signal cleanup covers the install temp too (r2 review [7]) ───

@test "artifact_write: a signal between cp and mv leaves no readable draft copy" {
  # The trap used to scrub only the candidate, so a SIGTERM landing after the
  # atomic-install copy left `.foo-interview.md.<pid>.tmp` on disk holding the
  # complete transcript. `cp` is interposed on PATH to hit that exact window.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context" "$BATS_TEST_TMPDIR/bin2"
  _clean_transcript "$cand"

  local realcp; realcp="$(command -v cp)"
  cat > "$BATS_TEST_TMPDIR/bin2/cp" <<EOF
#!/usr/bin/env bash
"$realcp" "\$@"; rc=\$?
kill -TERM \$PPID 2>/dev/null
sleep 5
exit \$rc
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin2/cp"

  local rc=0
  PATH="$BATS_TEST_TMPDIR/bin2:$PATH" "$SCRIPT" publish-transcript \
    --mb "$BANK" --topic foo --candidate "$cand" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 143 ] || { echo "writer was not interrupted (rc=$rc)"; false; }
  local left; left="$(find "$BANK/context" -name '.*tmp' 2>/dev/null)"
  [ -z "$left" ] || { echo "orphan install temp left behind: $left"; false; }
}

@test "artifact_write: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ─── the writer deletes ONLY files it owns (r3 review [5]) ───

@test "artifact_write: a rejected wrong-name file in bank/tmp survives BYTE-IDENTICAL" {
  # Cleanup was armed for any regular non-symlink file inside <bank>/tmp before
  # the basename was checked, so `--candidate <bank>/tmp/notes.md` returned
  # error=candidate and DELETED the user's file on the way out.
  local user="$BANK/tmp/not-the-candidate.md" snap="$BATS_TEST_TMPDIR/snap.md"
  printf 'IMPORTANT USER NOTES\n' > "$user"
  cp "$user" "$snap"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$user"
  [ "$status" -eq 2 ]
  [ -f "$user" ] || { echo "the writer deleted a file it rejected"; false; }
  cmp -s "$snap" "$user" || { echo "the rejected file was modified"; false; }
}

@test "artifact_write: an unrelated bank/tmp file survives an invalid-topic rejection" {
  local user="$BANK/tmp/scratch-notes.md" snap="$BATS_TEST_TMPDIR/snap2.md"
  printf 'more user notes\n' > "$user"
  cp "$user" "$snap"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic Foo --candidate "$user"
  [ "$status" -eq 2 ]
  [ -f "$user" ]
  cmp -s "$snap" "$user"
}

@test "artifact_write: a candidate-SHAPED name is still consumed on an invalid topic" {
  # The r2 guarantee must survive the r3 narrowing: ownership is decided by the
  # canonical candidate NAME PATTERN, which does not need a valid topic.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  printf '# Interview transcript: foo (2026-07-17)\n\nsk-ant-api03ABCDEFGHIJKLMNOP\n' > "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic Foo --candidate "$cand"
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived an invalid topic"; false; }
}

# ─── the atomic-install temp cannot be hijacked (r3 review [6]) ───

@test "artifact_write: a planted symlink at the install temp cannot redirect the write" {
  # The temp was `.<target>.$$.tmp` — fully predictable — and `cp` writes THROUGH
  # an existing symlink. Planting it on a victim overwrote that victim, made the
  # target a symlink, and the writer still reported success.
  # `exec` preserves $$, so the wrapper publishes the exact PID the writer uses.
  local victim="$BATS_TEST_TMPDIR/victim.txt" pidf="$BATS_TEST_TMPDIR/pid"
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  printf 'PRECIOUS VICTIM\n' > "$victim"
  _clean_transcript "$cand"

  ( echo $BASHPID > "$pidf"; sleep 2
    exec "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand" ) \
    >"$BATS_TEST_TMPDIR/out" 2>&1 &
  local bg=$!
  while [ ! -s "$pidf" ]; do :; done
  ln -s "$victim" "$BANK/context/.foo-interview.md.$(cat "$pidf").tmp"
  wait "$bg" || true

  grep -q 'PRECIOUS VICTIM' "$victim" || { echo "victim was overwritten through the temp symlink"; false; }
  [ ! -L "$BANK/context/foo-interview.md" ] || { echo "published target is a symlink"; false; }
}

@test "artifact_write: install-plan's temp cannot be hijacked either" {
  local victim="$BATS_TEST_TMPDIR/victim2.txt" pidf="$BATS_TEST_TMPDIR/pid2"
  printf 'PRECIOUS PLAN VICTIM\n' > "$victim"
  _valid_open_plan "$CAND"

  ( echo $BASHPID > "$pidf"; sleep 2
    exec "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND" ) \
    >"$BATS_TEST_TMPDIR/out2" 2>&1 &
  local bg=$!
  while [ ! -s "$pidf" ]; do :; done
  ln -s "$victim" "$BANK/tmp/.interview-plan-foo.md.$(cat "$pidf").tmp"
  wait "$bg" || true

  grep -q 'PRECIOUS PLAN VICTIM' "$victim" || { echo "victim overwritten via install-plan temp"; false; }
  [ ! -L "$TARGET" ] || { echo "installed plan is a symlink"; false; }
}

@test "artifact_write: a published transcript keeps an ordinary readable mode" {
  # mktemp-based staging creates 0600; the published file must not inherit it.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  umask 022
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 0 ]
  [ "$(_wmode "$BANK/context/foo-interview.md")" = "644" ]
}

@test "artifact_write: replacing an existing target preserves its mode" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md" tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context"
  printf 'PRIOR\n' > "$tgt"; chmod 600 "$tgt"
  _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 0 ]
  [ "$(_wmode "$tgt")" = "600" ]
}

@test "artifact_write: a target that appears mid-publish is not re-permissioned" {
  # r5 review [5]: the mode was resolved BEFORE the copy and applied AFTER it.
  # With no target yet, a run under umask 022 computed 0644 — and then replaced
  # the 0600 file a concurrent publisher had created in the meantime, widening
  # permissions nobody asked to change. `cp` is interposed so the publish parks
  # in exactly that window instead of racing it.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  local tgt="$BANK/context/foo-interview.md"
  local bin="$BATS_TEST_TMPDIR/bin-mode"
  local parked="$BATS_TEST_TMPDIR/.mode-parked" go="$BATS_TEST_TMPDIR/.mode-go"
  mkdir -p "$BANK/context" "$bin"
  _clean_transcript "$cand"

  local realcp; realcp="$(command -v cp)"
  cat > "$bin/cp" <<EOF
#!/usr/bin/env bash
dst="\${@: -1}"
case "\$dst" in
  *foo-interview*)
    if [ ! -e "$parked" ]; then
      : > "$parked"
      i=0
      while [ ! -e "$go" ] && [ "\$i" -lt 1000 ]; do sleep 0.01; i=\$((i + 1)); done
    fi ;;
esac
exec "$realcp" "\$@"
EOF
  chmod +x "$bin/cp"

  [ ! -e "$tgt" ]
  ( umask 022
    exec env PATH="$bin:$PATH" "$SCRIPT" publish-transcript \
      --mb "$BANK" --topic foo --candidate "$cand" ) >/dev/null 2>&1 &
  local bg=$! i=0
  while [ ! -e "$parked" ] && [ "$i" -lt 1000 ]; do sleep 0.01; i=$((i + 1)); done
  [ -e "$parked" ] || { kill "$bg" 2>/dev/null; echo "the publish never parked"; false; }

  # Somebody else publishes the target first, deliberately locked down.
  ( umask 077; printf 'CONCURRENTLY PUBLISHED\n' > "$tgt" )
  [ "$(_wmode "$tgt")" = "600" ] || { echo "fixture is wrong: $(_wmode "$tgt")"; false; }
  : > "$go"
  wait "$bg" || true

  [ "$(_wmode "$tgt")" = "600" ] \
    || { echo "the publish widened an existing target to $(_wmode "$tgt")"; false; }
}

# ─── the dead legacy flag is gone (r3 review [8]) ───

@test "artifact_write: publish-transcript rejects --legacy-live-fixture as unknown" {
  # OPEN CONTRACT MISMATCH (r4 review [9]) — flagged to the orchestrator, not
  # resolved here. design.md C11 still documents this flag on publish-transcript
  # and requires it be forwarded to the C8 check; round 3 removed it from the
  # writer as unimplementable. Proven unimplementable, not merely inconvenient:
  # the writer stages the candidate into a private dir, and the checker honours
  # the legacy relaxation ONLY for two canonical repository fixture paths — the
  # identical bytes under any staging path return legacy_fixture_forbidden. To
  # forward it you would have to weaken exactly the whitelist that stops a
  # publication candidate borrowing the weaker grammar.
  #
  # So the fix is a ONE-LINE SPEC EDIT: drop `[--legacy-live-fixture]` from C11
  # (design.md:428 and the forwarding clause at :434). Until the spec is
  # corrected this test pins the SHIPPED behaviour and is knowingly at odds with
  # C11; the guard below keeps the whitelist itself from being weakened in the
  # meantime, which is the invariant that holds under either resolution.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo \
    --candidate "$cand" --legacy-live-fixture
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ] || { echo "expected a usage error, got: $stderr"; false; }
}

@test "artifact_write: the writer no longer mentions --legacy-live-fixture" {
  ! grep -q 'legacy-live-fixture' "$SCRIPT" \
    || { echo "the dead flag is still referenced in the writer"; false; }
}

@test "artifact_write: the CHECKER keeps the flag for its frozen fixtures" {
  # Removing it from the writer must not remove it from the validator, where it
  # is genuinely used by the two live regression fixtures.
  grep -q 'legacy-live-fixture' "$REPO_ROOT/scripts/mb-interview-artifact-check.sh"
}

# ─── the title must name the topic being published (r3 review [23]) ───

@test "artifact_write: a transcript whose title names another topic is rejected" {
  # The checker validated the title's SHAPE and date but never its topic, so a
  # candidate titled `foo` published cleanly as context/bar-interview.md.
  local cand="$BANK/tmp/interview-transcript-bar.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"          # titled "foo"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic bar --candidate "$cand"
  [ "$status" -eq 1 ] || { echo "mismatched title published (status=$status)"; false; }
  [ ! -e "$BANK/context/bar-interview.md" ] || { echo "target created anyway"; false; }
  echo "$stderr" | grep -q ':missing_title$'
}

@test "artifact_write: a matching title still publishes" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"          # titled "foo"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 0 ]
  [ -f "$BANK/context/foo-interview.md" ]
}

# ═══ r4 [1]: the target LEAF must be a plain file, never a directory/symlink ══

@test "artifact_write: a target that is a SYMLINK to an outside dir is refused" {
  # `mv tmp target` where target is a symlink to a directory MOVES THE TEMP INTO
  # that directory: the full transcript landed outside the bank, context/ stayed
  # empty, and the writer still printed artifact_write=installed with exit 0.
  local outside="$BATS_TEST_TMPDIR/outside"; mkdir -p "$outside" "$BANK/context"
  ln -s "$outside" "$BANK/context/foo-interview.md"
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"; _clean_transcript "$cand"

  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -ne 0 ] || { echo "symlinked target reported success: $output"; false; }
  [ -z "$(ls -A "$outside")" ] || { echo "wrote outside the bank: $(ls -A "$outside")"; false; }
  [ -L "$BANK/context/foo-interview.md" ] || { echo "the symlink was replaced"; false; }
}

@test "artifact_write: a target that is a DIRECTORY is refused" {
  mkdir -p "$BANK/context/foo-interview.md"
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"; _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -ne 0 ] || { echo "directory target reported success"; false; }
  [ -d "$BANK/context/foo-interview.md" ]
  [ -z "$(ls -A "$BANK/context/foo-interview.md")" ] || { echo "wrote into the directory"; false; }
}

@test "artifact_write: install-plan refuses a symlinked target too" {
  local outside="$BATS_TEST_TMPDIR/outside2"; mkdir -p "$outside"
  ln -s "$outside" "$TARGET"
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo --candidate "$CAND"
  [ "$status" -ne 0 ] || { echo "symlinked plan target reported success"; false; }
  [ -z "$(ls -A "$outside")" ] || { echo "plan written outside the bank"; false; }
}

# ═══ r4 [2]: only THIS topic's candidate is ever deleted ════════════════════

@test "artifact_write: a topic mismatch leaves the OTHER topic's candidate intact" {
  # `--topic foo --candidate ...-bar.candidate.md` returned error=candidate and
  # deleted bar's candidate: reproducible data loss from an over-broad pattern.
  local bar="$BANK/tmp/interview-transcript-bar.candidate.md"
  _clean_transcript "$bar"
  local snap="$BATS_TEST_TMPDIR/bar.snap"; cp "$bar" "$snap"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --candidate "$bar"
  [ "$status" -eq 2 ]
  [ -f "$bar" ] || { echo "another topic's candidate was deleted"; false; }
  cmp -s "$snap" "$bar" || { echo "another topic's candidate was modified"; false; }
}

@test "artifact_write: an INVALID topic still consumes the candidate it was handed" {
  # The r2 guarantee survives the r4 narrowing: with no valid topic the exact
  # name cannot be computed, and the caller explicitly handed us this file.
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  printf '# t\n\nsk-ant-api03ABCDEFGHIJKLMNOP\n' > "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic Foo --candidate "$cand"
  [ "$status" -eq 2 ]
  [ ! -e "$cand" ] || { echo "credential candidate survived an invalid topic"; false; }
}

# ═══ r4 [3]: a repeated singleton flag is refused, and still cleans up ══════

@test "artifact_write: a duplicated --candidate is refused AND scrubs the owned one" {
  local sec="$BANK/tmp/interview-transcript-foo.candidate.md"
  printf 'raw\nsk-ant-api03ABCDEFGHIJKLMNOP\n' > "$sec"
  printf 'user notes\n' > "$BANK/tmp/notes.md"
  local snap="$BATS_TEST_TMPDIR/notes.snap"; cp "$BANK/tmp/notes.md" "$snap"

  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo \
    --candidate "$sec" --candidate "$BANK/tmp/notes.md"
  [ "$status" -eq 2 ]
  # Exit 2 alone is not attributable — the second path is unowned anyway. The
  # refusal must be the DUPLICATE-flag rule.
  [ "$stderr" = "error=usage" ] || { echo "not refused as a usage error: $stderr"; false; }
  [ ! -e "$sec" ] || { echo "credential candidate survived a duplicated flag"; false; }
  cmp -s "$snap" "$BANK/tmp/notes.md" || { echo "the unowned file was touched"; false; }
}

@test "artifact_write: a duplicated --topic is refused" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"; _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo --topic bar --candidate "$cand"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ] || { echo "not refused as a usage error: $stderr"; false; }
}

@test "artifact_write: a duplicated --mb is refused" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"; _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --mb "$BANK" --topic foo --candidate "$cand"
  [ "$status" -eq 2 ]
}

@test "artifact_write: the legacy relaxation stays limited to the frozen fixtures" {
  # The invariant that survives either resolution of the C11 mismatch above: the
  # same bytes under a non-fixture path must never earn the weaker grammar.
  local copy="$BATS_TEST_TMPDIR/staged-copy.md"
  cp "$REPO_ROOT/.memory-bank/context/svp-interview-upgrade-interview.md" "$copy"
  run --separate-stderr "$REPO_ROOT/scripts/mb-interview-artifact-check.sh" \
    transcript "$copy" --require-inherited --legacy-live-fixture
  [ "$status" -eq 2 ]
  echo "$stderr" | grep -q ':legacy_fixture_forbidden$'
  # ...while the frozen fixture itself still passes, so this is a path check and
  # not simply a broken flag.
  run --separate-stderr "$REPO_ROOT/scripts/mb-interview-artifact-check.sh" \
    transcript "$REPO_ROOT/.memory-bank/context/svp-interview-upgrade-interview.md" \
    --require-inherited --legacy-live-fixture
  [ "$status" -eq 0 ]
}

# ═══ r5 review [2]: the installed plan must be citable by digest ════════════
#
# `<bank>/tmp/interview-plan-<topic>.md` is per-TOPIC, so two `/mb discuss` runs
# on one topic write to the same file. The run that installs a plan needs a
# handle on the bytes IT installed, so that the close gate later can prove the
# plan it validates is still that one instead of the competing run's.

_sha256() {
  MB_F="$1" python3 -c 'import hashlib, os, sys
h = hashlib.sha256()
with open(os.environ["MB_F"], "rb") as fh:
    for chunk in iter(lambda: fh.read(65536), b""):
        h.update(chunk)
sys.stdout.write(h.hexdigest())'
}

@test "artifact_write: install-plan --print-digest reports the installed bytes" {
  _valid_open_plan "$CAND"
  run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" --topic foo \
    --candidate "$CAND" --print-digest
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=plan digest=$(_sha256 "$CAND")" ] \
    || { echo "unexpected stdout: $output"; false; }
  # The digest must be checkable against the file the gate will read.
  [ "$(_sha256 "$TARGET")" = "$(_sha256 "$CAND")" ]
}

@test "artifact_write: the digest is the SNAPSHOT's even if the candidate is rewritten" {
  # Same interposed-awk window as the validated-bytes test: whatever the other
  # run does to the candidate path, the digest must name what was installed.
  local bin="$BATS_TEST_TMPDIR/bin-pd"; mkdir -p "$bin"
  _valid_open_plan "$CAND"
  local installed; installed="$(_sha256 "$CAND")"
  _broken_plan "$BATS_TEST_TMPDIR/pd-payload.md"

  local realawk; realawk="$(command -v awk)"
  cat > "$bin/awk" <<EOF
#!/usr/bin/env bash
rc=0
"$realawk" "\$@" || rc=\$?
if [ ! -e "$BATS_TEST_TMPDIR/.pd-swapped" ]; then
  : > "$BATS_TEST_TMPDIR/.pd-swapped"
  cp "$BATS_TEST_TMPDIR/pd-payload.md" "$CAND" 2>/dev/null || true
fi
exit \$rc
EOF
  chmod +x "$bin/awk"

  PATH="$bin:$PATH" run --separate-stderr "$SCRIPT" install-plan --mb "$BANK" \
    --topic foo --candidate "$CAND" --print-digest
  [ -e "$BATS_TEST_TMPDIR/.pd-swapped" ] || { echo "the awk interposer never fired"; false; }
  [ "$status" -eq 0 ]
  [ "$output" = "artifact_write=installed kind=plan digest=$installed" ] \
    || { echo "the digest does not name the installed bytes: $output"; false; }
  [ "$(_sha256 "$TARGET")" = "$installed" ]
}

@test "artifact_write: --print-digest is refused on publish-transcript" {
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  mkdir -p "$BANK/context"
  _clean_transcript "$cand"
  run --separate-stderr "$SCRIPT" publish-transcript --mb "$BANK" --topic foo \
    --candidate "$cand" --print-digest
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ] || { echo "expected a usage error, got: $stderr"; false; }
}
