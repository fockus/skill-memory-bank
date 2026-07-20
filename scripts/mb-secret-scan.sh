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
# Usage:  mb-secret-scan.sh --policy <transcript|brief-input> <file>|-
#
# `-` reads the payload from STDIN. A caller holding a payload in memory used to
# have to spill it to a mktemp file just to scan it, so the UNSCANNED bytes sat
# on disk for the duration and survived a crash between the write and the rm
# (svp-sdd-core r3 review [7]). Findings are reported against `<stdin>`.
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
  transcript|brief-input) ;;
  *) usage_error ;;
esac

# File inspection + pattern scan. Determinism per C5: readable regular file →
# NUL → magic container → non-UTF-8 → scannable.
python3 - "$FILE" "$IMPORT_PY" "$POLICY" 3<&0 <<'PY'
import os
import re
import sys

path = sys.argv[1]
import_py = sys.argv[2]
policy = sys.argv[3]
from_stdin = path == "-"
label = "<stdin>" if from_stdin else path


def unsupported(reason):
    sys.stdout.write("scan=unsupported\n")
    sys.stderr.write("%s:0:%s\n" % (label, reason))
    sys.exit(2)


if from_stdin:
    # Bytes only; never materialised anywhere on disk. fd 3 carries the caller's
    # stdin because fd 0 is this program text (heredoc).
    try:
        with os.fdopen(3, "rb", closefd=True) as fh:
            data = fh.read()
    except OSError:
        unsupported("unreadable")
else:
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

source_lines = text.split("\n")

# Matched over the WHOLE text, never line by line (r4 review [4]). The canonical
# APIKEY_RE contains `Bearer\s+<token>` and `\s` matches a NEWLINE, so a
# credential split across two lines was invisible to a per-line loop while the
# same regex over the full text found it — a transcript with `Authorization:
# Bearer` ending one line and the token beginning the next published with exit 0.
#
# line/column are derived from the match OFFSET so the existing
# `<file>:<line>:<kind>` contract is unchanged. A match that spans lines is
# attributed to the line it STARTS on: that is where the credential begins, and
# it is the line the brief-input pragma rules then key on — which is what lets
# whole-text matching compose with pragma_alone/pragma_inline without a new case.
_line_starts = [0]
_pos = 0
for _ln in source_lines[:-1]:
    _pos += len(_ln) + 1
    _line_starts.append(_pos)


def _line_col(offset):
    """1-based line and 0-based column for a character offset into `text`."""
    lo, hi = 0, len(_line_starts) - 1
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if _line_starts[mid] <= offset:
            lo = mid
        else:
            hi = mid - 1
    return lo + 1, offset - _line_starts[lo]


findings = []
for rx, kind in ((EMAIL_RE, "email"), (APIKEY_RE, "api_key")):
    for mo in rx.finditer(text):
        ln, col = _line_col(mo.start())
        findings.append((ln, col, kind))
findings.sort(key=lambda t: (t[0], t[1]))

# `brief-input` (svp-brief C5) is `transcript` plus ONE difference: it honours an
# explicit `<!-- mb-secret-ok -->` pragma. TWO CASES, and only these two:
#
#   * a pragma ALONE on its line shields the finding on the line below it — the
#     escape hatch for a finding you cannot annotate inline, e.g. inside a fence;
#   * a pragma written INLINE shields only the findings on its own line.
#
# An inline pragma therefore does NOT shield the next line, even though it is
# literally "the line above" it. The wider reading was the first implementation
# here and it is wrong in the direction that matters: this pragma suppresses
# SECRET-scan findings, so over-suppression leaks a credential while
# under-suppression merely costs somebody a second pragma. When the two readings
# differ that way, the tighter one wins.
#
# `<private>` still suppresses nothing under either policy — it guards
# index/search redaction, never the git write.
PRAGMA = "<!-- mb-secret-ok -->"
if policy == "brief-input":
    def pragma_inline(lineno):
        """The line carries a pragma anywhere on it."""
        return 1 <= lineno <= len(source_lines) and PRAGMA in source_lines[lineno - 1]

    def pragma_alone(lineno):
        """The line carries the pragma and NOTHING else."""
        return (1 <= lineno <= len(source_lines)
                and source_lines[lineno - 1].strip() == PRAGMA)

    findings = [
        f for f in findings
        if not (pragma_inline(f[0]) or pragma_alone(f[0] - 1))
    ]

if findings:
    for ln, _col, kind in findings:
        sys.stderr.write("%s:%s:%s\n" % (label, ln, kind))
    sys.stdout.write("scan=blocked\n")
    sys.exit(1)

sys.stdout.write("scan=clean\n")
sys.exit(0)
PY
