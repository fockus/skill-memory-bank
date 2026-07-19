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

# Directory names that make a `<dir>/<name>` token a path rather than prose.
# `input/output` and `read/write` are ordinary behavioural phrasing; `scripts/`
# or `src/` in front of a name is not (R3-010).
_PATH_DIR = (
    r"(?:scripts?|src|tests?|lib|libs|docs?|bin|app|apps|config|conf|etc|usr|var|tmp|home"
    r"|node_modules|dist|build|target|vendor|pkg|cmd|internal|api|assets|public|static"
    r"|templates|migrations|fixtures|examples|packages|modules|components|utils|core"
    r"|\.\w[\w.-]*)"
)

_PATH_PATTERNS = (
    # Absolute, ./relative, ../parent and ~/home paths.
    r"(?:^|[\s(\[\"'`])~?\.{0,2}/[^\s/]",
    # Windows drive path or any backslash-separated path.
    r"[A-Za-z]:\\",
    r"\\[^\s\\]",
    # A slash-joined token whose LAST segment carries a known file extension:
    # `src/main.py`, `a/b/notes.md`.
    r"[\w.-]+/[\w.-]*\." + _PATH_EXT + r"(?:$|[\s)\],;:!?\"'`])",
    # A slash-joined token rooted at a recognisable directory: `scripts/runner`.
    r"(?:^|[\s(\[\"'`])" + _PATH_DIR + r"/[\w.-]+",
    # Three or more slash-joined segments is a path in any dialect: `a/b/c`.
    r"[\w.-]+/[\w.-]+/[\w.-]+",
    # Bare filename with a known file extension: `README.md`, `setup.py`.
    r"(?:^|[\s(\[\"'`])[\w.-]+\." + _PATH_EXT + r"(?:$|[\s)\],.;:!?\"'`])",
)

# A line reference in prose, not just the `file:42` spelling. `the parser must
# retry at line 42` sailed through the old `:\d+` guard and reached READY with a
# line number in it, so REQ-007's DoD was only half enforced (R4-002).
_LINE_NUM_PATTERNS = (
    r":\d+",
    r"\b(?:lines?|строк[аиеу]?|стр)\b\.?\s*:?\s*№?\s*\d+",
    r"#L\d+\b",
)

# `word/word` is DEFAULT-DENY: a two-segment slash token is a relative path
# unless both halves are ordinary paired vocabulary. R3-010 fixed the opposite
# over-blocking bug by allowing every `word/word`, which then let the plain
# relative path `custom/runner` through (R4-002). An explicit allow-list keeps
# `input/output` working without reopening that hole; an unlisted pair is
# refused with a message that says exactly what to do.
_CONCEPT_WORDS = frozenset(
    ["input", "output", "read", "write", "request", "response", "on", "off", "client", "server", "start", "stop", "pass", "fail", "true", "false", "yes", "no", "success", "failure", "get", "set", "put", "post", "open", "close", "push", "pull", "encode", "decode", "serialize", "deserialize", "key", "value", "name", "min", "max", "in", "out", "up", "down", "before", "after", "sender", "receiver", "producer", "consumer", "publish", "subscribe", "sync", "async", "create", "delete", "insert", "update", "select", "enable", "disable", "accept", "reject", "allow", "deny", "lock", "unlock", "login", "logout", "begin", "end", "first", "last", "left", "right", "row", "column", "parent", "child", "head", "tail", "hit", "miss", "send", "recv", "retry"]
)

_TWO_SEGMENT_RE = re.compile(r"(?:^|[\s(\[\"'`])([\w.-]+)/([\w.-]+)(?=$|[\s)\],.;:!?\"'`])")


def _unlisted_slash_pair(text):
    """A `word/word` token whose halves are not both conceptual vocabulary."""
    for left, right in _TWO_SEGMENT_RE.findall(text):
        if left.lower() not in _CONCEPT_WORDS or right.lower() not in _CONCEPT_WORDS:
            return True
    return False


def _looks_like_path(text):
    if any(re.search(p, text, re.IGNORECASE) for p in _PATH_PATTERNS):
        return True
    return _unlisted_slash_pair(text)


def validate_brief(text):
    t = (text or "").strip()
    if not t:
        return (False, "missing brief")
    if any(re.search(p, t, re.IGNORECASE) for p in _LINE_NUM_PATTERNS):
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
