#!/usr/bin/env bash
# mb-secret-scan.sh — canonical secret-scan dispatcher (svp-interview-upgrade C5).
# Owned by this slice; the `transcript` policy is implemented here, `brief-input`
# by the S7 consumer (svp-brief) in this same file. Patterns are single-sourced
# from scripts/mb-import.py (EMAIL_RE / APIKEY_RE) — no second regex set.
#
# The `transcript` policy scans the RAW text INCLUDING content inside
# <private>…</private> and never honours the `<!-- mb-secret-ok -->` pragma
# (critical R3-001: <private> guards index/search, NOT git diff).
#
# Usage:  mb-secret-scan.sh --policy <transcript|brief-input> <file>
# stdout: exactly one of `scan=clean` | `scan=blocked` | `scan=unsupported`.
# stderr: blocked → one `<file>:<line>:<email|api_key>` per finding, ordered by
#         (line, column); the secret itself is never printed. unsupported → one
#         `<file>:0:<unreadable|binary|unsupported_type>`. Usage errors print
#         `error=usage`; an unimplemented policy prints `policy_not_implemented`.
# exit:   0 clean · 1 blocked · 2 unsupported / usage.

set -euo pipefail

# Physical self-directory through the FULL symlink chain: the detection
# patterns are loaded from the sibling mb-import.py, so resolving from a
# symlink's directory would let an attacker tree supply a neutered pattern set
# (same exploit class as the writer, REQ-007).
_mb_resolve_self_dir() {
  local src="$1" dir
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd)"
    src="$(readlink "$src")"
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  cd -P "$(dirname "$src")" 2>/dev/null && pwd
}
SCRIPT_DIR="$(_mb_resolve_self_dir "${BASH_SOURCE[0]}")"
IMPORT_PY="$SCRIPT_DIR/mb-import.py"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

POLICY=""
FILE=""
have_file=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --policy) [ "$#" -ge 2 ] || usage_error; POLICY="$2"; shift ;;
    --*) usage_error ;;
    *) [ "$have_file" -eq 0 ] || usage_error; FILE="$1"; have_file=1 ;;
  esac
  shift
done
[ -n "$POLICY" ] || usage_error
[ "$have_file" -eq 1 ] || usage_error

case "$POLICY" in
  transcript) ;;
  brief-input) printf 'policy_not_implemented\n' >&2; exit 2 ;;
  *) usage_error ;;
esac

# File inspection + pattern scan. Determinism per C5: readable regular file →
# NUL → magic container → non-UTF-8 → scannable.
python3 - "$FILE" "$IMPORT_PY" <<'PY'
import os
import re
import sys

path = sys.argv[1]
import_py = sys.argv[2]


def unsupported(reason):
    sys.stdout.write("scan=unsupported\n")
    sys.stderr.write("%s:0:%s\n" % (path, reason))
    sys.exit(2)


if not (os.path.isfile(path) and os.access(path, os.R_OK)):
    unsupported("unreadable")
try:
    with open(path, "rb") as fh:
        data = fh.read()
except OSError:
    unsupported("unreadable")

if b"\x00" in data:
    unsupported("binary")

magics = (b"%PDF-", b"PK\x03\x04", b"\x1f\x8b", b"7z\xbc\xaf\x27\x1c", b"\xfd7zXZ\x00", b"BZh")
for mg in magics:
    if data.startswith(mg):
        unsupported("unsupported_type")
if len(data) >= 262 and data[257:262] == b"ustar":
    unsupported("unsupported_type")

try:
    text = data.decode("utf-8")
except UnicodeDecodeError:
    unsupported("unsupported_type")


def load_re(name):
    # Read (do not import) mb-import.py: it runs main() at module scope.
    src = open(import_py, encoding="utf-8").read()
    m = re.search(name + r'\s*=\s*re\.compile\(\s*r"([^"]*)"', src)
    if not m:
        sys.stderr.write("error=usage\n")
        sys.exit(2)
    return re.compile(m.group(1))


EMAIL_RE = load_re("EMAIL_RE")
APIKEY_RE = load_re("APIKEY_RE")

findings = []
for i, line in enumerate(text.split("\n"), start=1):
    for mo in EMAIL_RE.finditer(line):
        findings.append((i, mo.start(), "email"))
    for mo in APIKEY_RE.finditer(line):
        findings.append((i, mo.start(), "api_key"))
findings.sort(key=lambda t: (t[0], t[1]))

if findings:
    for ln, _col, label in findings:
        sys.stderr.write("%s:%s:%s\n" % (path, ln, label))
    sys.stdout.write("scan=blocked\n")
    sys.exit(1)

sys.stdout.write("scan=clean\n")
sys.exit(0)
PY
