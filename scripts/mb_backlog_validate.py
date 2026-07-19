#!/usr/bin/env python3
"""Backlog metadata validation: REQ-007 brief gate + single-line safety.

Split out of mb_backlog_state_engine.py to keep that file under the 400-line
project gate after the round-2 hardening. Pure stdlib, no side effects on
import, so the rules are directly unit-testable and there is exactly ONE copy
of them for every backlog writer.
"""

from __future__ import annotations

import re

# REQ-007: a READY brief must be "behavioral and free of file paths and line
# numbers". The original guard was a single `\S+/\S+\.\w+`, i.e. a path had to
# carry a slash AND an extension at once — so `README.md`, `scripts/runner`,
# `./x`, `/etc/passwd` and `C:\dir\f.txt` all sailed through and REQ-007 was
# effectively unenforced for the most ordinary spellings (finding 1).
#
# Bare filenames are matched against a closed extension list rather than a
# generic `\.\w+`, so ordinary prose ("e.g.", "v1.2", a sentence period) is not
# misread as a filename.
_PATH_EXT = (
    r"(?:md|markdown|txt|rst|py|pyi|sh|bash|zsh|bats|js|jsx|mjs|cjs|ts|tsx|json|ya?ml"
    r"|toml|ini|cfg|conf|env|lock|log|csv|tsv|sql|html?|css|scss|xml|go|rs|rb|java|kt"
    r"|swift|c|h|cc|cpp|hpp|cs|php|pl|lua|r|ipynb|png|jpe?g|svg|pdf|zip|tar|gz)"
)

_PATH_PATTERNS = (
    # Absolute, ./relative, ../parent and ~/home paths.
    r"(?:^|[\s(\[\"'`])~?\.{0,2}/[^\s/]",
    # Windows drive path or any backslash-separated path.
    r"[A-Za-z]:\\",
    r"\\[^\s\\]",
    # Any slash-joined token: `scripts/runner`, `a/b/c`, `src/main.py`.
    r"[\w.-]+/[\w.-]+",
    # Bare filename with a known file extension: `README.md`, `setup.py`.
    r"(?:^|[\s(\[\"'`])[\w.-]+\." + _PATH_EXT + r"(?:$|[\s)\],.;:!?\"'`])",
)


def _looks_like_path(text):
    return any(re.search(p, text, re.IGNORECASE) for p in _PATH_PATTERNS)


def validate_brief(text):
    t = (text or "").strip()
    if not t:
        return (False, "missing brief")
    if re.search(r":\d+", t):
        return (False, "contains line number")
    if _looks_like_path(t):
        return (False, "contains file path")
    if not re.search(r"\b(should|shall|must)\b|когда|если", t, re.IGNORECASE):
        return (False, "missing brief")
    return (True, "")


# Single-line metadata is written verbatim as `**<Key>:** <value>` on ONE line.
# A CR/LF in the value therefore continues into the file as new lines, which is
# enough to forge a `### I-NNN — ... [PRIO, STATE, DATE]` header and invent a
# backlog entry (finding 2). The round-1 uniqueness gate reports the resulting
# `duplicate_id`, but that is the symptom — this is the injection itself.
_CONTROL_RE = re.compile(r"[\r\n\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def validate_single_line(value, field):
    """Return (ok, message) for a value destined for a one-line metadata block."""
    if value is None:
        return (True, "")
    m = _CONTROL_RE.search(value)
    if m:
        char = m.group(0)
        kind = "newline" if char in "\r\n" else "control character"
        return (
            False,
            f"code=invalid_metadata field={field} detail={kind} not allowed "
            "in a single-line metadata value",
        )
    return (True, "")
