#!/usr/bin/env bats
# mb_glossary: — svp-interview-upgrade C12 deterministic glossary upsert (Task 5).
# term/definition read from files; atomic write; conflict leaves the file
# byte-identical (REQ-018-compatible).
#
# Name convention: every @test starts with `mb_glossary: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-glossary.sh"
  BANK="$BATS_TEST_TMPDIR/bank"; mkdir -p "$BANK"
  GLOSS="$BANK/glossary.md"
  TF="$BATS_TEST_TMPDIR/term.txt"
  DF="$BATS_TEST_TMPDIR/def.txt"
}

_upsert() {
  printf '%s' "$1" > "$TF"
  printf '%s' "$2" > "$DF"
  "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
}

@test "mb_glossary: the upsert script is present" {
  run assert_script_present scripts/mb-glossary.sh
  [ "$status" -eq 0 ]
}

@test "mb_glossary: first term → glossary=created and file has term — definition" {
  [ ! -e "$GLOSS" ]
  run --separate-stderr _upsert "slice" "a child spec of a group"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=created" ]
  [ -f "$GLOSS" ]
  grep -q '^slice — a child spec of a group$' "$GLOSS"
}

@test "mb_glossary: same term + same definition → glossary=unchanged, file untouched" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "slice" "a child spec of a group"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=unchanged" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: same term + different definition → glossary=conflict exit 1, file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "slice" "a plan stage"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: another term → glossary=updated (appended)" {
  _upsert "slice" "a child spec of a group" >/dev/null
  run --separate-stderr _upsert "frontier" "the set of unblocked questions"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=updated" ]
  grep -q '^slice — a child spec of a group$' "$GLOSS"
  grep -q '^frontier — the set of unblocked questions$' "$GLOSS"
}

@test "mb_glossary: bad subcommand → usage error exit 2" {
  printf 'x' > "$TF"; printf 'y' > "$DF"
  run --separate-stderr "$SCRIPT" frob --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
}

@test "mb_glossary: missing --definition-file → usage error exit 2" {
  printf 'x' > "$TF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: unreadable term file → usage error exit 2" {
  printf 'y' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$BATS_TEST_TMPDIR/nope.txt" --definition-file "$DF"
  [ "$status" -eq 2 ]
}

# ─── single-line contract guard (F7) ───

@test "mb_glossary: multiline term → usage error exit 2, nothing written" {
  [ ! -e "$GLOSS" ]
  printf 'alpha\nbeta' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: multiline definition → usage error exit 2, existing file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  printf 'frontier' > "$TF"; printf 'first\nsecond' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: empty term → usage error exit 2" {
  printf '' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: whitespace-only definition → usage error exit 2" {
  printf 'slice' > "$TF"; printf '   ' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: separator inside the term → usage error exit 2 (ambiguous key)" {
  printf 'a — b' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

# ─── raw CR/LF validated before normalization (cycle-2 major) ───

@test "mb_glossary: term with a trailing blank line (alpha\\n\\n) → usage exit 2, nothing written" {
  [ ! -e "$GLOSS" ]
  printf 'alpha\n\n' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: definition with a trailing blank line → usage exit 2, existing file byte-identical" {
  _upsert "slice" "a child spec of a group" >/dev/null
  local before; before="$(cat "$GLOSS")"
  printf 'frontier' > "$TF"; printf 'the frontier\n\n' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: carriage return in the definition → usage exit 2" {
  printf 'slice' > "$TF"; printf 'de\rf' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
}

@test "mb_glossary: a single terminal newline is tolerated (created)" {
  [ ! -e "$GLOSS" ]
  printf 'slice\n' > "$TF"; printf 'a child spec\n' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=created" ]
  grep -q '^slice — a child spec$' "$GLOSS"
}

# ─── concurrent upserts must not lose entries (review [4]) ───

# N concurrent upserts of distinct terms; each records its exit code. Sets
# $N_OK (upserts that reported success) and leaves the codes in $BANK/../rcs.
_concurrent_upserts() {
  local n="$1" i
  RC_DIR="$BATS_TEST_TMPDIR/rc"; mkdir -p "$RC_DIR"
  for i in $(seq 1 "$n"); do
    printf 'term%02d' "$i" > "$BATS_TEST_TMPDIR/t$i.txt"
    printf 'def%02d' "$i" > "$BATS_TEST_TMPDIR/d$i.txt"
  done
  for i in $(seq 1 "$n"); do
    (
      MB_GLOSSARY_LOCK_TIMEOUT="${MB_GLOSSARY_LOCK_TIMEOUT:-90}" \
        "$SCRIPT" upsert --mb "$BANK" \
          --term-file "$BATS_TEST_TMPDIR/t$i.txt" \
          --definition-file "$BATS_TEST_TMPDIR/d$i.txt" >/dev/null 2>&1
      printf '%d' "$?" > "$RC_DIR/$i"
    ) &
  done
  wait
}

@test "mb_glossary: concurrent upserts never lose a successful entry" {
  # Unlocked read-modify-replace: every racer read the same `existing` snapshot
  # and the last os.replace won, silently dropping its competitors (the review
  # repro: 30 successful calls, 26 lines on disk). The invariant that must hold
  # regardless of scheduling: an upsert that REPORTS success is on disk.
  local i rc n_ok=0 missing=""
  _concurrent_upserts 12
  for i in $(seq 1 12); do
    rc="$(cat "$RC_DIR/$i")"
    [ "$rc" -eq 0 ] || continue
    n_ok=$((n_ok + 1))
    grep -q "^term$(printf '%02d' "$i") — def$(printf '%02d' "$i")\$" "$GLOSS" \
      || missing="$missing term$(printf '%02d' "$i")"
  done
  [ -z "$missing" ] || { echo "upserts reported ok but lost:$missing"; cat "$GLOSS"; false; }
  # And no phantom entries: line count == number of successful upserts.
  [ "$(grep -c ' — ' "$GLOSS")" -eq "$n_ok" ]
}

@test "mb_glossary: with an adequate lock timeout every concurrent upsert succeeds" {
  local i rc n_ok=0
  _concurrent_upserts 12
  for i in $(seq 1 12); do
    rc="$(cat "$RC_DIR/$i")"
    [ "$rc" -eq 0 ] && n_ok=$((n_ok + 1))
  done
  [ "$n_ok" -eq 12 ] || { echo "only $n_ok/12 upserts succeeded"; false; }
  [ "$(grep -c ' — ' "$GLOSS")" -eq 12 ]
}

@test "mb_glossary: a contender that cannot take the lock fails loudly, never silently" {
  # Degradation must be an explicit exit 2 + diagnostic — NEVER exit 0 with a
  # dropped entry (that is the corruption mode this lock exists to prevent).
  # Exit 1 is reserved for a definition conflict, so it must not be used here.
  mkdir -p "$BANK/.locks/glossary.lock/owner.$$-held"
  printf 'slice' > "$TF"; printf 'a child spec' > "$DF"
  run --separate-stderr env MB_GLOSSARY_LOCK_TIMEOUT=1 MB_GLOSSARY_LOCK_TTL=3600 \
    "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=lock_timeout" ]
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: concurrent upserts of the SAME term stay single-line" {
  local i n
  printf 'slice' > "$TF"; printf 'a child spec' > "$DF"
  for i in $(seq 1 12); do
    "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF" >/dev/null 2>&1 &
  done
  wait
  n="$(grep -c '^slice — a child spec$' "$GLOSS")"
  [ "$n" -eq 1 ] || { echo "expected exactly 1 line, got $n"; cat "$GLOSS"; false; }
}

# ─── invalid UTF-8 is an I/O error, exit 2 (review [10], contract C12) ───

@test "mb_glossary: invalid UTF-8 in the term → exit 2, no traceback, nothing written" {
  # C12: exit 1 means CONFLICT. A UnicodeDecodeError escaping as exit 1 with a
  # Python traceback both breaks the exit contract and leaks internals.
  printf 'caf\xe9term' > "$TF"; printf 'a definition' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "error=usage" ]
  ! echo "$stderr" | grep -q 'Traceback'
  [ ! -e "$GLOSS" ]
}

@test "mb_glossary: invalid UTF-8 in the definition → exit 2, existing file byte-identical" {
  _upsert "slice" "a child spec"
  local before; before="$(cksum < "$GLOSS")"
  printf 'term2' > "$TF"; printf 'def\xff\xfe' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$stderr" = "error=usage" ]
  [ "$(cksum < "$GLOSS")" = "$before" ]
}

@test "mb_glossary: invalid UTF-8 in an existing glossary.md → exit 2, not a traceback" {
  printf 'bad\xe9line — x\n' > "$GLOSS"
  local before; before="$(cksum < "$GLOSS")"
  printf 'slice' > "$TF"; printf 'a child spec' > "$DF"
  run --separate-stderr "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  ! echo "$stderr" | grep -q 'Traceback'
  [ "$(cksum < "$GLOSS")" = "$before" ]
}

# ─── published file mode (I-145) ───

# Permission bits of <file>, portable across BSD (macOS) and GNU stat.
_mode() {
  stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"
}

@test "mb_glossary: a created glossary.md is readable, never mkstemp 0600" {
  # I-145: writers that publish through tempfile.mkstemp() + os.replace() without
  # carrying a mode leave the target at mkstemp's private 0600. This writer
  # publishes through open(), so a fresh file must land at the ordinary creation
  # default — locked down here so a future switch to mkstemp fails loudly.
  #
  # The umask is PINNED (r2 review [14]): the expected mode is 0666 & ~umask, so
  # under the umask 002 common on shared-group setups the correct production
  # result is 0664 and the bare `644` literal failed. Pinning keeps the assertion
  # exact while making it environment-independent; the umask-077 test below is
  # what proves the mode is computed rather than hardcoded.
  umask 022
  _upsert "slice" "a child spec"
  [ "$(_mode "$GLOSS")" = "644" ]
}

@test "mb_glossary: create honours the umask instead of hardcoding a mode" {
  # Proves the default is computed (0666 & ~umask), not a literal 0644 — a
  # hardcoded constant would silently widen a deliberately strict environment.
  umask 077
  _upsert "slice" "a child spec"
  [ "$(_mode "$GLOSS")" = "600" ]
}

@test "mb_glossary: an update preserves a deliberate group-writable 0664" {
  # The real defect in this script: os.replace() published the temp file's own
  # mode, so a shared team bank at 0664 silently dropped to 0644 on every write.
  _upsert "slice" "a child spec"
  chmod 664 "$GLOSS"
  _upsert "frontier" "the unblocked question set"
  [ "$(_mode "$GLOSS")" = "664" ] || { echo "mode became $(_mode "$GLOSS"), expected 664"; false; }
  grep -q '^frontier — the unblocked question set$' "$GLOSS"
}

@test "mb_glossary: an update preserves a deliberate 0600 without widening it" {
  # mb-glossary.sh is the ONLY writer of glossary.md and never produces 0600,
  # so a restrictive mode here is a deliberate lockdown — not mkstemp damage.
  # Silently widening it would unprotect a file the user chose to protect.
  _upsert "slice" "a child spec"
  chmod 600 "$GLOSS"
  _upsert "frontier" "the unblocked question set"
  [ "$(_mode "$GLOSS")" = "600" ] || { echo "mode became $(_mode "$GLOSS"), expected 600"; false; }
}

@test "mb_glossary: a rejected upsert leaves the mode untouched" {
  _upsert "slice" "a child spec"
  chmod 640 "$GLOSS"
  printf 'bad\nterm' > "$TF"; printf 'x' > "$DF"
  run "$SCRIPT" upsert --mb "$BANK" --term-file "$TF" --definition-file "$DF"
  [ "$status" -eq 2 ]
  [ "$(_mode "$GLOSS")" = "640" ]
}

@test "mb_glossary: a conflicting upsert leaves the mode untouched" {
  _upsert "slice" "a child spec"
  chmod 640 "$GLOSS"
  run "$SCRIPT" upsert --mb "$BANK" --term-file <(printf 'slice') --definition-file <(printf 'a different meaning')
  [ "$(_mode "$GLOSS")" = "640" ]
}

@test "mb_glossary: no .tmp sibling survives a successful write" {
  _upsert "slice" "a child spec"
  _upsert "frontier" "the unblocked question set"
  run find "$BANK" -name '*.tmp'
  [ -z "$output" ] || { echo "temp files left: $output"; false; }
}

@test "mb_glossary: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

# ─── a pre-existing contradiction is never silently hidden (r2 review [13]) ───
#
# The row scan returned at the FIRST matching term, so a glossary already
# holding `term — first` AND `term — conflicting` answered an upsert of
# `term/first` with `glossary=unchanged` and exit 0 — the contradictory second
# definition was never challenged, violating REQ-018.

@test "mb_glossary: a duplicate term with a DIFFERENT definition is reported as conflict" {
  printf 'slice — a child spec\nslice — a plan stage\n' > "$GLOSS"
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "slice" "a child spec"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: the conflict is found even when the matching row comes first" {
  # The exact reproduction: the requested definition matches row 1, so the old
  # code exited `unchanged` before ever seeing the contradiction on row 2.
  printf 'term — first\nterm — conflicting\n' > "$GLOSS"
  run --separate-stderr _upsert "term" "first"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
}

@test "mb_glossary: the conflict is found when the matching row comes last" {
  printf 'term — conflicting\nterm — first\n' > "$GLOSS"
  run --separate-stderr _upsert "term" "first"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
}

@test "mb_glossary: a duplicated term row is rejected even for an unrelated upsert" {
  # The whole glossary is validated under the lock, so an ambiguous file cannot
  # keep accumulating entries around the contradiction.
  printf 'term — first\nterm — conflicting\n' > "$GLOSS"
  local before; before="$(cat "$GLOSS")"
  run --separate-stderr _upsert "frontier" "the set of unblocked questions"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
  [ "$(cat "$GLOSS")" = "$before" ]
}

@test "mb_glossary: an exactly duplicated row is still ambiguous → conflict" {
  printf 'term — first\nterm — first\n' > "$GLOSS"
  run --separate-stderr _upsert "term" "first"
  [ "$status" -eq 1 ]
  [ "$output" = "glossary=conflict" ]
}

@test "mb_glossary: a clean multi-term glossary still upserts normally" {
  # The whole-file validation must not reject ordinary well-formed glossaries.
  printf 'slice — a child spec\nfrontier — unblocked questions\n' > "$GLOSS"
  run --separate-stderr _upsert "gate" "a blocking check"
  [ "$status" -eq 0 ]
  [ "$output" = "glossary=updated" ]
  grep -q '^gate — a blocking check$' "$GLOSS"
}
