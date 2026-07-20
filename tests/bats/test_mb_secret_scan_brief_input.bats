#!/usr/bin/env bats
# brief_scan: — svp-brief C5, the `brief-input` policy of the canonical
# secret-scan dispatcher (svp-interview-upgrade C5 owns the file, the dispatcher
# and the shared contract; this slice implements one policy inside it).
#
# The shared elements — script name, arguments, the stdout lines
# `scan=clean|scan=blocked|scan=unsupported`, the `email`/`api_key` labels,
# finding order by (line, column) and exits 0/1/2 — are asserted here as a
# CONSUMER contract. They are not redefined by this slice.
#
# `brief-input` differs from `transcript` in exactly one way: it honours the
# `<!-- mb-secret-ok -->` pragma. `<private>` suppresses nothing under either.
#
# Name convention (X-05, Eval red-anchor): every @test starts with `brief_scan: `.

bats_require_minimum_version 1.5.0
load 'lib/assert'
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-secret-scan.sh"
  SK="sk-ant-api03ABCDEFGHIJKLMNOP"
  SK2="sk-ant-api03QRSTUVWXYZ012345"
  EMAIL="alice@example.com"
  PRAGMA="<!-- mb-secret-ok -->"
}

@test "brief_scan: clean — a file with no credential is scan=clean exit 0" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'a paragraph about checkout\nno credentials at all\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
  [ "$stderr" = "" ]
}

@test "brief_scan: blocked — an api key is scan=blocked with file:line:api_key exit 1" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'line one\ntoken %s here\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:2:api_key" ]
}

@test "brief_scan: blocked — an email is labelled email" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'write to %s please\n' "$EMAIL" > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:1:email" ]
}

@test "brief_scan: private-does-not-suppress — a secret inside <private> still blocks" {
  # <private> guards index/search redaction, NEVER the git write. A brief input
  # wrapped in <private> that landed in briefs/<topic>/inputs/ would be
  # committed in full.
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'note <private>%s</private> end\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:1:api_key" ]
}

@test "brief_scan: pragma — suppresses ONLY the pragma'd finding, not the file" {
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf 'intro line\n'                       # 1
    printf '%s\n' "$PRAGMA"                     # 2 — pragma on its own line
    printf 'token %s here\n' "$SK"              # 3 — suppressed from above
    printf 'naked %s here\n' "$SK"              # 4 — NOT suppressed
    printf 'inline %s %s\n' "$SK2" "$PRAGMA"    # 5 — suppressed inline
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:4:api_key" ]
}

@test "brief_scan: pragma — an INLINE pragma shields ONLY its own line" {
  # The two-case rule (C5): a pragma ALONE on its line shields the line below,
  # an INLINE pragma shields only its own. Reading "the line immediately above"
  # to include an inline pragma would make one annotation clear two lines —
  # over-suppression, which in a secret scan is the error that leaks a
  # credential. The tighter reading is the contract.
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf 'inline %s %s\n' "$SK" "$PRAGMA"     # 1 — shielded, pragma is inline
    printf 'next %s line\n' "$SK2"              # 2 — NOT shielded by line 1
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:2:api_key" ]
}

@test "brief_scan: pragma — a pragma ALONE on its line shields the line below" {
  # The converse case, so the pair pins both halves of the rule rather than
  # only the one that was ambiguous.
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf '%s\n' "$PRAGMA"                     # 1 — pragma and nothing else
    printf 'next %s line\n' "$SK2"              # 2 — shielded by line 1
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
  [ "$stderr" = "" ]
}

@test "brief_scan: pragma — trailing whitespace still counts as alone on the line" {
  # `strip()`, not equality against the raw line: an editor that leaves a
  # trailing space would otherwise silently disarm the escape hatch, and the
  # user would see a block they cannot explain.
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf '  %s  \n' "$PRAGMA"                 # 1 — padded, still alone
    printf 'next %s line\n' "$SK2"              # 2 — shielded
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
  [ "$stderr" = "" ]
}

@test "brief_scan: pragma — a pragma with prose beside it does NOT shield below" {
  # The boundary between the two cases: text alongside the pragma makes it
  # inline, so it stops shielding the line below even with no finding of its own.
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf 'see the note %s\n' "$PRAGMA"        # 1 — inline, no finding here
    printf 'next %s line\n' "$SK2"              # 2 — NOT shielded
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:2:api_key" ]
}

@test "brief_scan: pragma — a file whose every finding is pragma'd is clean" {
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf '%s\n' "$PRAGMA"
    printf 'token %s here\n' "$SK"
    printf 'inline %s %s\n' "$EMAIL" "$PRAGMA"
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
  [ "$stderr" = "" ]
}

@test "brief_scan: pragma — a pragma two lines above does NOT suppress" {
  # Only the finding line and the line immediately above it count; a wider
  # window would let one pragma silently clear a whole document.
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf '%s\n' "$PRAGMA"
    printf 'an intervening line\n'
    printf 'token %s here\n' "$SK"
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:3:api_key" ]
}

@test "brief_scan: pragma — the transcript policy still ignores it (no cross-talk)" {
  # Proves the pragma is scoped to this policy and did not leak into S1's.
  local f="$BATS_TEST_TMPDIR/c.md"
  printf '%s %s\n' "$SK" "$PRAGMA" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:1:api_key" ]
}

@test "brief_scan: finding-order — findings ascend by (line, column)" {
  local f="$BATS_TEST_TMPDIR/c.md"
  {
    printf 'contact %s and use %s now\n' "$EMAIL" "$SK"
    printf 'second %s line\n' "$EMAIL"
  } > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  local expected
  expected="$(printf '%s\n%s\n%s' "$f:1:email" "$f:1:api_key" "$f:2:email")"
  [ "$stderr" = "$expected" ]
}

@test "brief_scan: secret-never-printed — the credential value appears in no stream" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'token %s and %s\n' "$SK" "$EMAIL" > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  refute_substring "$output" "$SK"
  refute_substring "$stderr" "$SK"
  refute_substring "$output" "$EMAIL"
  refute_substring "$stderr" "$EMAIL"
}

@test "brief_scan: unsupported — a NUL byte makes the file binary, exit 2" {
  local f="$BATS_TEST_TMPDIR/bin.dat"
  printf 'PK\000\001binary payload\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$f:0:binary" ]
}

@test "brief_scan: unsupported — an unreadable file is unreadable, not clean" {
  local f="$BATS_TEST_TMPDIR/noread.md"
  printf 'token %s\n' "$SK" > "$f"
  chmod 000 "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  chmod 644 "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$f:0:unreadable" ]
}

@test "brief_scan: unsupported — a PDF container is unsupported_type, never clean" {
  # Scenario 1 uses a UTF-8 PRD.md precisely because a binary container cannot
  # be inspected in MVP; a clean verdict here would be a silent copy.
  local f="$BATS_TEST_TMPDIR/doc.pdf"
  printf '%%PDF-1.7\nstream stuff\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$f:0:unsupported_type" ]
}

@test "brief_scan: usage — an unknown policy is a usage error, not a clean verdict" {
  local f="$BATS_TEST_TMPDIR/c.md"
  printf 'nothing here\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-inputs "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "" ]
  [ "$stderr" = "error=usage" ]
}

# ── pattern parity with the canonical source (scripts/mb-import.py) ──────────

_scanner_copy() {
  mkdir -p "$1"
  cp "$SCRIPT" "$1/mb-secret-scan.sh"
  cp "$REPO_ROOT/scripts/mb-import.py" "$1/mb-import.py"
  chmod +x "$1/mb-secret-scan.sh"
}

@test "brief_scan: pattern-parity — neutering the canonical APIKEY_RE stops the block" {
  local d="$BATS_TEST_TMPDIR/copy1" f="$BATS_TEST_TMPDIR/copy1/t.md"
  _scanner_copy "$d"
  printf 'key %s here\n' "$SK" > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]

  python3 - "$d/mb-import.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    r'r"\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})\b"',
    r'r"ZZZ_NEVER_MATCHES_ANYTHING_ZZZ"')
open(p, "w", encoding="utf-8").write(s)
PY
  assert_grep -q 'ZZZ_NEVER_MATCHES_ANYTHING_ZZZ' "$d/mb-import.py"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$output" = "scan=clean" ]
}

@test "brief_scan: pattern-parity — widening the canonical APIKEY_RE starts the block" {
  # The converse direction, so the test cannot pass by the policy simply
  # failing open on a pattern file it never read.
  local d="$BATS_TEST_TMPDIR/copy2" f="$BATS_TEST_TMPDIR/copy2/t.md"
  _scanner_copy "$d"
  printf 'a perfectly ordinary sentence about pineapples\n' > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$output" = "scan=clean" ]

  python3 - "$d/mb-import.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    r'r"\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})\b"',
    r'r"pineapples"')
open(p, "w", encoding="utf-8").write(s)
PY

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  assert_grep -q ':api_key$' <(printf '%s\n' "$stderr")
}

@test "brief_scan: pattern-parity — the EMAIL_RE is single-sourced too" {
  local d="$BATS_TEST_TMPDIR/copy3" f="$BATS_TEST_TMPDIR/copy3/t.md"
  _scanner_copy "$d"
  printf 'write to person@example.com please\n' > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$status" -eq 1 ]
  assert_grep -q ':email$' <(printf '%s\n' "$stderr")

  python3 - "$d/mb-import.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    r'r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"',
    r'r"ZZZ_NO_EMAIL_ZZZ"')
open(p, "w", encoding="utf-8").write(s)
PY

  run --separate-stderr "$d/mb-secret-scan.sh" --policy brief-input "$f"
  [ "$output" = "scan=clean" ]
}

@test "brief_scan: shellcheck and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
