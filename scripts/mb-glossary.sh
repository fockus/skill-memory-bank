#!/usr/bin/env bash
# mb-glossary.sh — deterministic upsert of a single glossary line
# (svp-interview-upgrade design C12, SVP-IU-002). REQ-017 is a file effect, so it
# lives in a script, not in a prompt `echo`. Term and definition are read from
# files (byte-safe, no quoting loss); the `<term> — <definition>` line is
# created/updated atomically, with `.memory-bank/glossary.md` created lazily on
# the first term.
#
# Usage:
#   mb-glossary.sh upsert --mb <bank> --term-file <file> --definition-file <file>
#
# The whole read → validate → atomic-replace cycle runs under the shared
# <bank>/.locks/glossary.lock (scripts/_lib.sh mb_lock_acquire, contract C6):
# without it concurrent upserts each read the same snapshot and the last
# os.replace silently dropped every competitor entry.
#
# stdout : glossary=created|updated|unchanged|conflict
# exit   : 0 created/updated/unchanged · 1 conflict (same term, different
#          definition — file left byte-identical, REQ-018) · 2 usage / I/O
#          (including invalid UTF-8 input and lock timeout — never 1, which is
#          reserved for a genuine definition conflict).

set -euo pipefail

# Resolve this script's own physical directory through its FULL symlink chain,
# so a symlinked invocation cannot make `source _lib.sh` pick up a neighbouring
# forgery (same hardening as mb-interview-artifact-check.sh).
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
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

LOCK_TIMEOUT="${MB_GLOSSARY_LOCK_TIMEOUT:-10}"
LOCK_TTL="${MB_GLOSSARY_LOCK_TTL:-120}"

_LOCK_DIR=""
_LOCK_TOKEN=""
# Release on EVERY exit path — success, validation reject, conflict, or signal.
_cleanup() {
  [ -n "$_LOCK_DIR" ] && mb_lock_release "$_LOCK_DIR" "$_LOCK_TOKEN" >/dev/null 2>&1 || true
}
# A signal handler that merely RETURNS resumes the script at the next command —
# with the lock it just released. `trap _cleanup EXIT INT TERM HUP` therefore
# unlocked the critical section and let the run carry on inside it, and a run
# killed before the critical section still ended at `exit "$rc"` = 0, telling
# its caller the term had been recorded (r5 review [4]). A signal must END the
# process: release, disarm EXIT so the release is not attempted twice, and exit
# with the conventional 128+signal status (same shape as
# mb-interview-artifact-write.sh).
_on_signal() {
  _cleanup
  trap - EXIT
  exit $((128 + $1))
}

usage_error() { printf 'error=usage\n' >&2; exit 2; }

SUB="${1:-}"
[ -n "$SUB" ] || usage_error
shift
[ "$SUB" = "upsert" ] || usage_error

MB=""
TERM_FILE=""
DEF_FILE=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) [ "$#" -ge 2 ] || usage_error; MB="$2"; shift ;;
    --term-file) [ "$#" -ge 2 ] || usage_error; TERM_FILE="$2"; shift ;;
    --definition-file) [ "$#" -ge 2 ] || usage_error; DEF_FILE="$2"; shift ;;
    *) usage_error ;;
  esac
  shift
done

[ -n "$MB" ] && [ -n "$TERM_FILE" ] && [ -n "$DEF_FILE" ] || usage_error
[ -d "$MB" ] || usage_error
[ -f "$TERM_FILE" ] && [ -r "$TERM_FILE" ] || usage_error
[ -f "$DEF_FILE" ] && [ -r "$DEF_FILE" ] || usage_error

mkdir -p "$MB/.locks" 2>/dev/null || { printf 'error=io\n' >&2; exit 2; }
_LOCK_DIR="$MB/.locks/glossary.lock"
if ! _LOCK_TOKEN="$(mb_lock_acquire "$_LOCK_DIR" "$LOCK_TIMEOUT" "$LOCK_TTL" 2>/dev/null)"; then
  _LOCK_DIR=""
  printf 'error=lock_timeout\n' >&2
  exit 2
fi
trap _cleanup EXIT
trap '_on_signal 2' INT
trap '_on_signal 15' TERM
trap '_on_signal 1' HUP

rc=0
python3 - "$MB" "$TERM_FILE" "$DEF_FILE" "$SCRIPT_DIR" <<'PY' || rc=$?
import os
import stat
import sys
import tempfile

mb, term_file, def_file, lib_dir = sys.argv[1:5]

# The mode-carrying publish is the ONE shared primitive, not a third hand-rolled
# copy of it: mb_fs_atomic resolves the target mode inside the same directory
# lock as the rename, which is what keeps a target created mid-write from being
# re-permissioned (r5 review [5]).
sys.path.insert(0, lib_dir)
from mb_fs_atomic import publish_path  # noqa: E402


def _read_text(path, code):
    # Invalid UTF-8 or an unreadable file is an INPUT/IO fault, not a conflict:
    # C12 reserves exit 1 for a definition conflict, so both must exit 2 — and
    # never as an uncaught UnicodeDecodeError traceback.
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (UnicodeError, OSError):
        sys.stderr.write("error=%s\n" % code)
        sys.exit(2)


raw_term = _read_text(term_file, "usage")
raw_definition = _read_text(def_file, "usage")

gloss = os.path.join(mb, "glossary.md")
sep = " — "  # space em-dash space


def _multiline(raw):
    # Validate the RAW bytes BEFORE any normalization: exactly one optional
    # terminal "\n" is tolerated; an interior newline, extra trailing blank
    # line, or any CR is a multi-line spill.
    if "\r" in raw:
        return True
    body = raw[:-1] if raw.endswith("\n") else raw
    return "\n" in body


term = raw_term.rstrip("\n")
definition = raw_definition.rstrip("\n")

# One glossary entry is exactly one line `<term> — <definition>`. Reject any
# input that would break that single-line contract BEFORE touching the file, so
# a rejected upsert leaves glossary.md byte-identical (REQ-017/018):
#   - a CR/LF spill in the raw term or definition (checked pre-normalization),
#   - empty / whitespace-only term or definition,
#   - the separator inside the term (ambiguous key on read-back).
if (
    _multiline(raw_term)
    or _multiline(raw_definition)
    or term.strip() == ""
    or definition.strip() == ""
    or sep in term
):
    sys.stderr.write("error=usage\n")
    sys.exit(2)

line = term + sep + definition + "\n"


def _io_error():
    sys.stderr.write("error=io\n")
    sys.exit(2)


def atomic_write(path, content):
    # The temp is created EXCLUSIVELY via mkstemp in the target directory.
    # `<glossary>.<pid>.tmp` + open(...,"w") was predictable AND followed a
    # planted symlink: the victim it pointed at was overwritten and glossary.md
    # itself was published as a symlink, with exit 0.
    #
    # The mode rule (I-145: an EXISTING glossary keeps its mode VERBATIM — a
    # restrictive mode is a deliberate lockdown, and widening is the direction
    # that cannot be undone once a secret has been exposed) now lives in exactly
    # ONE place, publish_path, which also resolves it inside the same lock as
    # the rename. Symlinks and non-regular targets are refused before this
    # function is reached AND again by publish_path.
    directory = os.path.dirname(path) or "."
    try:
        fd, tmp = tempfile.mkstemp(prefix=".glossary-", suffix=".tmp", dir=directory)
    except OSError:
        _io_error()
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(content)
        publish_path(tmp, path, refuse_irregular=True)
    except (UnicodeError, OSError):
        try:
            os.unlink(tmp)
        except OSError:
            pass
        _io_error()


# Symlinks are rejected outright, and existence is decided by LSTAT: a DANGLING
# link is invisible to os.path.exists(), so the writer used to take the "create"
# branch and replace the link with a regular file — the islink rejection right
# below never ran.
try:
    st = os.lstat(gloss)
except FileNotFoundError:
    st = None
except OSError:
    _io_error()

if st is None:
    atomic_write(gloss, line)
    sys.stdout.write("glossary=created\n")
    sys.exit(0)

if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
    _io_error()

existing = _read_text(gloss, "io")

# Validate the WHOLE glossary while the lock is held (REQ-018).
#
# The scan used to return at the FIRST row matching the term: a file holding
# both `term — first` and `term — conflicting` answered an upsert of
# `term/first` with `glossary=unchanged` and exit 0, so the contradictory
# definition was never challenged. Every entry row is inspected now, and any
# term appearing more than once makes the file ambiguous — that is an unresolved
# conflict for the interview to settle before more entries pile up around it.
#
# Rows without the separator are NOT entries (a hand-added heading or comment).
# They are left alone rather than rejected: they carry no term/definition claim,
# and failing on them would break existing banks for no safety gain.
counts = {}
matches = []
for row in existing.split("\n"):
    if row.strip() == "":
        continue
    idx = row.find(sep)
    if idx < 0:
        continue
    key = row[:idx]
    counts[key] = counts.get(key, 0) + 1
    if key == term:
        matches.append(row[idx + len(sep):])

if any(c > 1 for c in counts.values()):
    sys.stdout.write("glossary=conflict\n")
    sys.exit(1)

if matches:
    if all(v == definition for v in matches):
        sys.stdout.write("glossary=unchanged\n")
        sys.exit(0)
    sys.stdout.write("glossary=conflict\n")
    sys.exit(1)

if existing and not existing.endswith("\n"):
    existing += "\n"
atomic_write(gloss, existing + line)
sys.stdout.write("glossary=updated\n")
sys.exit(0)
PY

exit "$rc"
