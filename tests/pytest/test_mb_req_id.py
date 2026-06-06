"""Contract tests for scripts/mb_req_id.py — the shared REQ-ID grammar.

`mb_req_id` is the single source of truth for how Memory Bank spec tooling
recognises requirement identifiers. A REQ-ID is ``REQ-<scheme>`` where
``<scheme>`` is an optional UPPERCASE project segment (``RS``, ``IC``, ``AUTH``,
…) followed by a 3+ digit number::

    REQ-001        bare numeric (the original form)
    REQ-RS-008     prefixed per-feature scheme
    REQ-IC-003

Public API exercised here:
    canon(token)            -> canonical "REQ-..." (underscores→dashes, upper)
    find_definitions(text)  -> ids DEFINED on a bullet/heading line (anchored)
    extract_req_ids(text)   -> every referenced id, slash-shorthand expanded
    find_test_ids(text)     -> ids referenced by test files (identifier or prose)
    EARS_REQ_LINE_RE        -> match a bold-bullet REQ line, capturing its scheme
    COVERS_TOKEN_RE         -> full-string covers token (optional spec qualifier)
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "scripts" / "mb_req_id.py"


def _load():
    spec = importlib.util.spec_from_file_location("mb_req_id", MODULE_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rq = _load()


# ── canon ────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("REQ-001", "REQ-001"),
        ("req-001", "REQ-001"),
        ("REQ_RS_008", "REQ-RS-008"),
        ("req_rs_008", "REQ-RS-008"),
        ("  REQ-RS-008  ", "REQ-RS-008"),
    ],
)
def test_canon_normalises_separator_and_case(raw: str, expected: str) -> None:
    assert rq.canon(raw) == expected


# ── find_definitions (Bug A scheme + Bug B definition-vs-mention) ─────────────


def test_find_definitions_supports_prefixed_scheme() -> None:
    text = "- **REQ-RS-001** (event-driven): When X, the system shall Y.\n"
    assert rq.find_definitions(text) == ["REQ-RS-001"]


def test_find_definitions_accepts_plain_bullet_and_heading_and_bold() -> None:
    text = (
        "- REQ-001: plain bullet form.\n"
        "- **REQ-002** (ubiquitous): bold bullet form.\n"
        "### REQ-003 heading form\n"
    )
    assert rq.find_definitions(text) == ["REQ-001", "REQ-002", "REQ-003"]


def test_find_definitions_ignores_mid_line_cross_reference() -> None:
    """A REQ mentioned in prose (e.g. ``(REQ-015)``) is NOT a definition.

    This is the phantom-row bug: ``assistant-rich-streaming`` cross-references
    the legacy ``REQ-015`` invariant, which must not register as one of its own
    requirements.
    """
    text = (
        "- **REQ-RS-013** (state-driven): While streaming to Telegram, the system\n"
        "  shall throttle edits, preserving the single-edited-message invariant (REQ-015).\n"
    )
    assert rq.find_definitions(text) == ["REQ-RS-013"]
    assert "REQ-015" not in rq.find_definitions(text)


def test_find_definitions_does_not_treat_covers_line_as_definition() -> None:
    text = "**Covers:** REQ-RS-001, REQ-RS-002\n"
    assert rq.find_definitions(text) == []


def test_find_definitions_dedupes_preserving_order() -> None:
    text = "- **REQ-002** a\n- **REQ-001** b\n- **REQ-002** c\n"
    assert rq.find_definitions(text) == ["REQ-002", "REQ-001"]


def test_find_definitions_ignores_nested_indented_bullet_cross_reference() -> None:
    """A cross-reference written as a NESTED (indented) sub-bullet under a
    requirement must not register as a definition of the current spec — only
    top-level requirement bullets/headings count. Closes the residual phantom
    path where ``  - REQ-015: legacy`` would otherwise create a phantom row.
    """
    text = (
        "- **REQ-RS-013** (state-driven): While streaming, the system shall throttle.\n"
        "  - REQ-015: legacy single-edited-message invariant (cross-ref, not ours)\n"
    )
    assert rq.find_definitions(text) == ["REQ-RS-013"]


def test_scheme_rejects_unicode_digits() -> None:
    """REQ numbers are ASCII by definition — a Unicode-digit id is not a REQ-ID,
    so it must not register as a definition or a reference (no non-canonical rows).
    """
    assert rq.find_definitions("- **REQ-１２３** (ubiquitous): The system shall X.") == []
    assert rq.extract_req_ids("REQ-１２３") == []
    assert rq.find_test_ids("test_req_１２３_x") == []


# ── extract_req_ids (Bug C: slash-shorthand + parentheticals in covers) ───────


def test_extract_req_ids_expands_slash_shorthand_with_scheme() -> None:
    assert rq.extract_req_ids("REQ-RS-002/003") == ["REQ-RS-002", "REQ-RS-003"]


def test_extract_req_ids_expands_bare_numeric_slash_shorthand() -> None:
    assert rq.extract_req_ids("REQ-009/010") == ["REQ-009", "REQ-010"]


def test_extract_req_ids_strips_parentheticals_and_prose() -> None:
    covers = "REQ-RS-004 (rating/highlight fields), REQ-RS-007 (catalogue URL shape), §2/§3 of design."
    assert rq.extract_req_ids(covers) == ["REQ-RS-004", "REQ-RS-007"]


def test_extract_req_ids_handles_three_way_slash() -> None:
    assert rq.extract_req_ids("REQ-RS-005/006/007 (real prices/URLs)") == [
        "REQ-RS-005",
        "REQ-RS-006",
        "REQ-RS-007",
    ]


def test_extract_req_ids_dedupes_preserving_order() -> None:
    assert rq.extract_req_ids("REQ-RS-002, REQ-RS-002, REQ-RS-001") == [
        "REQ-RS-002",
        "REQ-RS-001",
    ]


# ── find_test_ids (identifier form + docstring slash form, case-insensitive) ──


def test_find_test_ids_matches_pytest_identifier_form() -> None:
    assert rq.find_test_ids("def test_shared_semaphore_req_rs_008():") == ["REQ-RS-008"]


def test_find_test_ids_matches_legacy_underscore_numeric() -> None:
    assert rq.find_test_ids("def test_REQ_001_works(): pass") == ["REQ-001"]


def test_find_test_ids_expands_docstring_slash_shorthand() -> None:
    assert rq.find_test_ids('"""REQ-RS-002/011: a delta reaches on_event."""') == [
        "REQ-RS-002",
        "REQ-RS-011",
    ]


# ── EARS_REQ_LINE_RE + COVERS_TOKEN_RE ───────────────────────────────────────


def test_ears_req_line_re_captures_prefixed_scheme() -> None:
    m = rq.EARS_REQ_LINE_RE.match("- **REQ-RS-008** (state-driven): While X, shall Y.")
    assert m is not None
    assert "REQ-" + m.group(1) == "REQ-RS-008"


def test_ears_req_line_re_ignores_non_bold_bullet() -> None:
    assert rq.EARS_REQ_LINE_RE.match("- REQ-001: plain bullet, not an EARS line") is None


@pytest.mark.parametrize(
    "token,ok",
    [
        ("REQ-001", True),
        ("REQ-RS-008", True),
        ("billing-spine:REQ-007", True),
        ("REQ-RS-008 (note)", False),
        ("§3 of design", False),
    ],
)
def test_covers_token_re_full_string_match(token: str, ok: bool) -> None:
    assert bool(rq.COVERS_TOKEN_RE.match(token)) is ok
