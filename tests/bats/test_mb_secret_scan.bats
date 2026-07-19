#!/usr/bin/env bats
# secret_scan: — svp-interview-upgrade C5 secret-scan dispatcher, `transcript`
# policy (Task 4). Patterns single-sourced from scripts/mb-import.py
# (EMAIL_RE / APIKEY_RE). `<private>` and `<!-- mb-secret-ok -->` never suppress
# a finding under the transcript policy (critical R3-001).
#
# Name convention: every @test starts with `secret_scan: ` (Eval red-anchor).

bats_require_minimum_version 1.5.0
load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-secret-scan.sh"
  SK="sk-ant-api03ABCDEFGHIJKLMNOP"
  EMAIL="alice@example.com"
}

@test "secret_scan: the scanner script is present" {
  run assert_script_present scripts/mb-secret-scan.sh
  [ "$status" -eq 0 ]
}

@test "secret_scan: clean file → scan=clean exit 0" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'nothing secret here\njust prose\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
}

@test "secret_scan: api key → scan=blocked + <file>:<line>:api_key exit 1" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'line one\ntoken %s here\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:2:api_key" ]
}

@test "secret_scan: email → scan=blocked + <file>:<line>:email" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'contact %s now\n' "$EMAIL" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$stderr" = "$f:1:email" ]
}

@test "secret_scan: email + api key across lines → two stderr lines by (line,col)" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'a %s\nb %s\n' "$EMAIL" "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | sed -n 1p)" = "$f:1:email" ]
  [ "$(printf '%s\n' "$stderr" | sed -n 2p)" = "$f:2:api_key" ]
}

@test "secret_scan: two findings on one line → two lines ordered by column" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf '%s and %s\n' "$EMAIL" "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | sed -n 1p)" = "$f:1:email" ]
  [ "$(printf '%s\n' "$stderr" | sed -n 2p)" = "$f:1:api_key" ]
}

@test "secret_scan: the secret value is never printed" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'k %s\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  ! printf '%s%s' "$output" "$stderr" | grep -q "$SK"
}

@test "secret_scan: secret inside <private> is still blocked (R3-001, raw scan)" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'note <private>%s</private> end\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
  [ "$stderr" = "$f:1:api_key" ]
}

@test "secret_scan: transcript policy ignores the mb-secret-ok pragma" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf '%s <!-- mb-secret-ok -->\n' "$SK" > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]
}

@test "secret_scan: missing file → unsupported/unreadable exit 2" {
  run --separate-stderr "$SCRIPT" --policy transcript "$BATS_TEST_TMPDIR/nope.md"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$BATS_TEST_TMPDIR/nope.md:0:unreadable" ]
}

@test "secret_scan: NUL byte → unsupported/binary exit 2" {
  local f="$BATS_TEST_TMPDIR/c.bin"; printf 'a\000b clean\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$f:0:binary" ]
}

@test "secret_scan: PDF magic → unsupported/unsupported_type exit 2" {
  local f="$BATS_TEST_TMPDIR/c.pdf"; printf '%%PDF-1.4 body\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 2 ]
  [ "$output" = "scan=unsupported" ]
  [ "$stderr" = "$f:0:unsupported_type" ]
}

@test "secret_scan: ZIP/OOXML magic → unsupported/unsupported_type" {
  local f="$BATS_TEST_TMPDIR/c.docx"; printf 'PK\003\004rest\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 2 ]
  [ "$stderr" = "$f:0:unsupported_type" ]
}

@test "secret_scan: gzip magic → unsupported/unsupported_type" {
  local f="$BATS_TEST_TMPDIR/c.gz"; printf '\037\213rest\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 2 ]
  [ "$stderr" = "$f:0:unsupported_type" ]
}

@test "secret_scan: invalid UTF-8 (non-container) → unsupported/unsupported_type" {
  local f="$BATS_TEST_TMPDIR/c.dat"; printf '\377\376plain text\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 2 ]
  [ "$stderr" = "$f:0:unsupported_type" ]
}

@test "secret_scan: readable UTF-8 without NUL is scannable (not unsupported)" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'Привет — обычный UTF-8 текст\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "scan=clean" ]
}

@test "secret_scan: --policy brief-input → policy_not_implemented exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'clean\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy brief-input "$f"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "policy_not_implemented" ]
}

@test "secret_scan: unknown policy → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'clean\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy bogus "$f"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "secret_scan: missing --policy → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'clean\n' > "$f"
  run --separate-stderr "$SCRIPT" "$f"
  [ "$status" -eq 2 ]
}

@test "secret_scan: two files → usage error exit 2" {
  local f="$BATS_TEST_TMPDIR/c.md"; printf 'clean\n' > "$f"
  run --separate-stderr "$SCRIPT" --policy transcript "$f" "$f"
  [ "$status" -eq 2 ]
}

# ─── single-sourcing is proven BEHAVIOURALLY (r2 review [10]) ───
#
# The old test was `grep -q 'mb-import.py' "$SCRIPT"`: hardcoding a divergent
# regex set in the scanner while keeping an mb-import.py comment still passed it,
# so it certified nothing. These mutate the canonical source in an isolated copy
# and prove the scanner's behaviour follows it.

_scanner_copy() {
  # $1 = destination dir. Copies the scanner next to its canonical pattern
  # source, exactly as they are laid out in the bundle.
  mkdir -p "$1"
  cp "$SCRIPT" "$1/mb-secret-scan.sh"
  cp "$REPO_ROOT/scripts/mb-import.py" "$1/mb-import.py"
  chmod +x "$1/mb-secret-scan.sh"
}

@test "secret_scan: NEUTERING the canonical APIKEY_RE makes the scanner stop blocking" {
  # If the scanner carried its own copy of the regex, the key would still be
  # found and this would stay `blocked`.
  local d="$BATS_TEST_TMPDIR/copy1" f="$BATS_TEST_TMPDIR/copy1/t.md"
  _scanner_copy "$d"
  printf 'key sk-ant-api03ABCDEFGHIJKLMNOP here\n' > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ]

  # Controlled mutation of the SOURCE OF TRUTH only.
  python3 - "$d/mb-import.py" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    r'r"\b(?:sk-(?:ant-)?[A-Za-z0-9_-]{16,}|Bearer\s+[A-Za-z0-9._-]{16,}|gh[pousr]_[A-Za-z0-9]{20,})\b"',
    r'r"ZZZ_NEVER_MATCHES_ANYTHING_ZZZ"')
open(p, "w", encoding="utf-8").write(s)
PY
  grep -q 'ZZZ_NEVER_MATCHES_ANYTHING_ZZZ' "$d/mb-import.py"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
  [ "$output" = "scan=clean" ] || { echo "scanner ignored the canonical pattern source"; false; }
}

@test "secret_scan: WIDENING the canonical APIKEY_RE makes the scanner start blocking" {
  # The converse direction, so the test cannot pass by the scanner simply
  # failing open on a broken pattern file.
  local d="$BATS_TEST_TMPDIR/copy2" f="$BATS_TEST_TMPDIR/copy2/t.md"
  _scanner_copy "$d"
  printf 'a perfectly ordinary sentence about pineapples\n' > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
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

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
  [ "$status" -eq 1 ]
  [ "$output" = "scan=blocked" ] || { echo "scanner did not follow the widened pattern"; false; }
  echo "$stderr" | grep -q ':api_key$'
}

@test "secret_scan: the EMAIL_RE is single-sourced too" {
  local d="$BATS_TEST_TMPDIR/copy3" f="$BATS_TEST_TMPDIR/copy3/t.md"
  _scanner_copy "$d"
  printf 'write to person@example.com please\n' > "$f"

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
  [ "$status" -eq 1 ]
  echo "$stderr" | grep -q ':email$'

  python3 - "$d/mb-import.py" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace(
    r'r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"',
    r'r"ZZZ_NO_EMAIL_ZZZ"')
open(p, "w", encoding="utf-8").write(s)
PY

  run --separate-stderr "$d/mb-secret-scan.sh" --policy transcript "$f"
  [ "$output" = "scan=clean" ] || { echo "EMAIL_RE is not read from mb-import.py"; false; }
}

@test "secret_scan: shellcheck (error severity) and bash -n clean" {
  run shellcheck -x -S error "$SCRIPT"
  [ "$status" -eq 0 ]
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
