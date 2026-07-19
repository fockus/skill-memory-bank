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
  local cand="$BANK/tmp/interview-transcript-foo.candidate.md"
  local tgt="$BANK/context/foo-interview.md"
  mkdir -p "$BANK/context" "$BATS_TEST_TMPDIR/bin"
  _clean_transcript "$cand"
  sed 's/The scope is X/The scope is sk-ant-api03ABCDEFGHIJKLMNOP/' "$cand" > "$BATS_TEST_TMPDIR/payload.md"

  local realpy; realpy="$(command -v python3)"
  cat > "$BATS_TEST_TMPDIR/bin/python3" <<EOF
#!/usr/bin/env bash
prog="\$(mktemp)"; cat > "\$prog"
"$realpy" "\$prog" "\${@:2}"; rc=\$?
rm -f "\$prog"
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
  if [ -f "$tgt" ]; then
    ! grep -q 'sk-ant-api03ABCDEFGHIJKLMNOP' "$tgt" || { echo "published file carries the API key"; false; }
  fi
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

# ─── the dead legacy flag is gone (r3 review [8]) ───

@test "artifact_write: publish-transcript rejects --legacy-live-fixture as unknown" {
  # The writer claimed to support the flag, but it staged the candidate into a
  # private dir first and then handed THAT path to the checker, which only
  # honours the two frozen repository fixtures — so the branch always died with
  # legacy_fixture_forbidden after consuming the candidate. An option that can
  # never succeed is worse than no option: it is removed.
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
