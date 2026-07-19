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
# stdout : glossary=created|updated|unchanged|conflict
# exit   : 0 created/updated/unchanged · 1 conflict (same term, different
#          definition — file left byte-identical, REQ-018) · 2 usage / I/O.

set -euo pipefail

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

python3 - "$MB" "$TERM_FILE" "$DEF_FILE" <<'PY'
import os
import sys

mb, term_file, def_file = sys.argv[1:4]

raw_term = open(term_file, encoding="utf-8").read()
raw_definition = open(def_file, encoding="utf-8").read()

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


def atomic_write(path, content):
    tmp = "%s.%d.tmp" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.replace(tmp, path)


if not os.path.exists(gloss):
    atomic_write(gloss, line)
    sys.stdout.write("glossary=created\n")
    sys.exit(0)

if not os.path.isfile(gloss) or os.path.islink(gloss):
    sys.exit(2)

with open(gloss, encoding="utf-8") as fh:
    existing = fh.read()

for row in existing.split("\n"):
    idx = row.find(sep)
    if idx >= 0 and row[:idx] == term:
        if row[idx + len(sep):] == definition:
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
