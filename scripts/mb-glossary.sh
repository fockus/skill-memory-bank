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
trap _cleanup EXIT INT TERM HUP

rc=0
python3 - "$MB" "$TERM_FILE" "$DEF_FILE" <<'PY' || rc=$?
import os
import stat
import sys

mb, term_file, def_file = sys.argv[1:4]


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


def _default_mode():
    # Exactly what a plain open() would have produced: 0666 masked by the
    # umask. Computed, never a hardcoded 0644, so a deliberately strict
    # environment is not silently widened.
    current = os.umask(0)
    os.umask(current)
    return 0o666 & ~current


def _target_mode(path):
    # Mode the published file must end up with (I-145).
    #
    # An EXISTING glossary keeps its mode VERBATIM. mb-glossary.sh is the only
    # writer of glossary.md and never produces 0600 — it publishes through
    # open(), not tempfile.mkstemp() — so a restrictive mode on this file is a
    # deliberate lockdown, not mkstemp damage. Guessing "damage" and widening it
    # would silently unprotect a file the user chose to protect, and widening is
    # the direction that cannot be undone once a secret has been exposed.
    # Repairing already-damaged banks is the one-shot I-145 migration, not this
    # write path's job (same rule as scripts/mb_fs_atomic.py).
    try:
        return stat.S_IMODE(os.stat(path).st_mode)
    except FileNotFoundError:
        return _default_mode()
    except OSError:
        return None


def atomic_write(path, content):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    # Resolve the mode BEFORE the write: after os.replace the original is gone.
    mode = _target_mode(path)
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(content)
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except (UnicodeError, OSError):
        # Never leave the sibling temp behind on a failed write.
        try:
            os.unlink(tmp)
        except OSError:
            pass
        sys.stderr.write("error=io\n")
        sys.exit(2)


if not os.path.exists(gloss):
    atomic_write(gloss, line)
    sys.stdout.write("glossary=created\n")
    sys.exit(0)

if not os.path.isfile(gloss) or os.path.islink(gloss):
    sys.stderr.write("error=io\n")
    sys.exit(2)

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
