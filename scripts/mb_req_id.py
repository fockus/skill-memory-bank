#!/usr/bin/env python3
"""Shared REQ-ID grammar for Memory Bank spec tooling.

This module is the single source of truth for how requirement identifiers are
recognised across ``mb-traceability-gen.sh``, ``mb-spec-validate.sh`` and
``mb-ears-validate.sh``. Centralising the grammar here is what lets every spec
tool understand the same ID schemes consistently — before this module each
script carried its own ``REQ-(\\d{3,})`` regex and silently disagreed.

Grammar
-------
A REQ-ID is ``REQ-<scheme>`` where ``<scheme>`` is an optional UPPERCASE project
segment followed by a 3+ digit number::

    REQ-001        bare numeric (the original form)
    REQ-RS-008     prefixed per-feature scheme (RS = rich-streaming)
    REQ-IC-003     prefixed per-feature scheme (IC = interactive-clarify)

The number stays the discriminator; the optional segment lets a project
namespace requirements per spec without colliding with another spec's REQ-NNN.

Definition vs. mention
----------------------
``find_definitions`` only registers a REQ that is *declared* on a list-bullet or
heading line (the documented ``- REQ-NNN:`` / ``- **REQ-NNN**`` / ``### REQ-NNN``
forms). A REQ named mid-sentence — e.g. a cross-reference ``(REQ-015)`` — is a
*mention*, not a definition, and is ignored. ``extract_req_ids`` is the opposite:
it pulls every *referenced* id out of free-form text (plan covers, prose), with
the project's ``REQ-RS-002/003`` slash-shorthand expanded.

Public API
----------
canon(token)            -> canonical "REQ-..." (underscores→dashes, upper, trimmed)
find_definitions(text)  -> list[str]  ids defined on a bullet/heading line
extract_req_ids(text)   -> list[str]  every referenced id, slash-shorthand expanded
find_test_ids(text)     -> list[str]  ids referenced by a test file (identifier/prose)

Regexes (exported for callers that need raw matching):
EARS_REQ_LINE_RE        -> match a bold-bullet REQ line, group(1) = scheme
COVERS_TOKEN_RE         -> full-string covers token, optional ``spec:`` qualifier
"""

from __future__ import annotations

import re

# The scheme body: an optional UPPERCASE segment (e.g. ``RS-``), then 3+ digits.
# Digits are ASCII-only ([0-9], not \d) — REQ numbers are ASCII by definition, so
# a Unicode-digit token (REQ-１２３) is never a REQ-ID.
_SCHEME = r"(?:[A-Z][A-Z0-9]*-)?[0-9]{3,}"

# A *definition*: a REQ at the head of a TOP-LEVEL list bullet or a heading. The
# bold markers are optional so both ``- REQ-001:`` and ``- **REQ-RS-001**``
# register. Anchoring to a column-0 bullet/heading marker excludes both mid-line
# mentions and nested (indented) cross-reference sub-bullets — only a top-level
# requirement declaration counts.
_DEFINITION_RE = re.compile(
    r"^(?:[-*+]|#{1,6})[ \t]+\*{0,2}REQ-(" + _SCHEME + r")\b",
    re.MULTILINE,
)

# A bare *reference* anywhere in prose, with optional ``/NNN`` slash-shorthand
# tails that reuse the leading prefix (``REQ-RS-002/003`` → 002 + 003).
_REFERENCE_RE = re.compile(r"\bREQ-" + _SCHEME + r"(?:/[0-9]{3,})*\b")

# A *test* reference: dash OR underscore separators, case-insensitive, so a
# pytest identifier ``test_..._req_rs_008`` and a docstring ``REQ-RS-002/011``
# both resolve. Slash tails are supported as in references. The boundaries are
# lookarounds that EXCLUDE letters/digits but ALLOW ``_`` — a pytest identifier
# embeds the id between underscores (``test_REQ_001_works``), where ``\b`` fails
# because ``_`` is itself a word character.
_TEST_REF_RE = re.compile(
    r"(?<![A-Za-z0-9])REQ[-_](?:[A-Za-z][A-Za-z0-9]*[-_])?[0-9]{3,}(?:/[0-9]{3,})*(?![A-Za-z0-9])",
    re.IGNORECASE,
)

# An EARS requirement line: a bold REQ bullet (``- **REQ-NNN** ...``). group(1)
# captures the scheme so the caller can rebuild ``REQ-<scheme>``.
EARS_REQ_LINE_RE = re.compile(r"^[ \t]*-[ \t]+\*\*REQ-(" + _SCHEME + r")\*\*")

# A covers token (whole-string): an optional ``spec-name:`` qualifier + a REQ-ID.
COVERS_TOKEN_RE = re.compile(r"^(?:[A-Za-z0-9_.-]+:)?REQ-" + _SCHEME + r"$")


def canon(token: str) -> str:
    """Normalise a raw token to canonical ``REQ-...`` form.

    Underscores become dashes (so a pytest identifier ``req_rs_008`` maps onto
    the spec's ``REQ-RS-008``) and the whole token is upper-cased and trimmed.
    """
    return token.strip().replace("_", "-").upper()


def _expand_slash(token: str) -> list[str]:
    """Expand a ``REQ-RS-002/003``-style token into individual canonical ids.

    Trailing ``/NNN`` groups reuse the leading prefix (everything up to and
    including the last separator before the base number).
    """
    parts = token.split("/")
    base = parts[0]
    sep = max(base.rfind("-"), base.rfind("_"))
    prefix = base[: sep + 1]
    return [canon(base)] + [canon(prefix + tail) for tail in parts[1:]]


def _dedupe(ids: list[str]) -> list[str]:
    """Drop duplicates while preserving first-seen order."""
    seen: set[str] = set()
    out: list[str] = []
    for i in ids:
        if i not in seen:
            seen.add(i)
            out.append(i)
    return out


def find_definitions(text: str) -> list[str]:
    """Return REQ-IDs *defined* on a bullet/heading line, in document order.

    Mid-line mentions (cross-references like ``(REQ-015)``) are excluded — only
    a REQ at the head of a list item or heading counts as a definition.
    """
    return _dedupe(["REQ-" + m.group(1) for m in _DEFINITION_RE.finditer(text)])


def extract_req_ids(text: str) -> list[str]:
    """Return every REQ-ID *referenced* in free-form text, slash-shorthand expanded.

    Handles parentheticals and surrounding prose (``REQ-RS-004 (rating fields)``)
    and the ``REQ-RS-002/003`` shorthand. Used for plan/task ``Covers`` fields and
    inline coverage markers.
    """
    ids: list[str] = []
    for m in _REFERENCE_RE.finditer(text):
        ids.extend(_expand_slash(m.group(0)))
    return _dedupe(ids)


def find_test_ids(text: str) -> list[str]:
    """Return canonical REQ-IDs referenced by a test file's content.

    Recognises both the pytest identifier form (``test_..._req_rs_008`` /
    ``test_REQ_001_*``) and the docstring/prose form (``REQ-RS-002/011``).
    """
    ids: list[str] = []
    for m in _TEST_REF_RE.finditer(text):
        ids.extend(_expand_slash(m.group(0)))
    return _dedupe(ids)
