"""Unit tests for memory_bank_skill/consolidate.py — the LLM-free ``/mb consolidate``
engine extracted out of scripts/mb-consolidate.sh (tier1-graph-memory Task 12 fix #2).

The two load-bearing contracts are exercised mocklessly against pure functions:

  * :func:`split_progress` — a BYTE-PRESERVING partition of ``progress.md`` into
    ``(kept_text, moved_stubs_text)``. The regression here proves byte-identity on
    the cases the bats suite cannot reach cleanly through command substitution:
    no-final-newline, CRLF, non-ASCII (Cyrillic + emoji), backslashes, a fenced
    ``## ``-looking line inside a real entry, an exact-stub match vs. an impure
    block, a sid NOT in the archived set, and an empty / preamble-only file.
  * the PLAN helpers — ``files_touched`` (the modern ``· ok · +A/-B`` tail must NOT
    leak into the file list) and ``cluster_sessions`` (a chained cluster A&B&C where
    the full intersection is empty must still link all three via occurrence count).

The canonical stub bullets ``BULLET1`` / ``BULLET2`` are asserted byte-identical to
hooks/session-end-autosave.sh:98-99 so the splitter and the hook never drift apart.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import consolidate as cz  # noqa: E402

# ── The exact hook stub lines (hooks/session-end-autosave.sh:98-99). ──────────
B1 = cz.BULLET1
B2 = cz.BULLET2


def _stub_block(date: str, sid: str) -> str:
    """The canonical hook stub block exactly as session-end-autosave.sh emits it."""
    return f"## {date}\n\n### Auto-capture {date} (session {sid})\n{B1}\n{B2}\n"


# ─────────────────────────────────────────────────────────────────────────────
# split_progress — byte-preservation
# ─────────────────────────────────────────────────────────────────────────────
def test_bullets_match_session_end_autosave_hook_verbatim():
    """The two canonical bullets are byte-identical to the hook's emitted lines."""
    hook = (REPO_ROOT / "hooks" / "session-end-autosave.sh").read_text(encoding="utf-8")
    # The hook prints them via `printf -- '- ...\n'`; the literal text appears inline.
    assert B1 == "- Session ended without an explicit /mb done"
    assert B2 == (
        "- Summary auto-captured to session/ "
        "(searchable via /mb recall); core files were not actualized"
    )
    assert B1 in hook
    assert B2 in hook


def test_split_progress_no_final_newline_round_trips_byte_identical():
    real = "## 2026-06-12 (real)\n\n### Done\n- kept entry"  # NO trailing newline
    kept, moved = cz.split_progress(real, set())
    assert kept == real  # byte-for-byte, including the missing final newline
    assert moved == ""


def test_split_progress_crlf_terminators_preserved():
    real = "## 2026-06-12 (real)\r\n\r\n### Done\r\n- kept\r\n"
    stub = _stub_block("2026-01-02", "aaaaaaaa").replace("\n", "\r\n")
    kept, moved = cz.split_progress(real + stub, {"aaaaaaaa"})
    assert kept == real  # CRLF survives verbatim
    assert moved == stub


def test_split_progress_non_ascii_cyrillic_and_emoji_preserved():
    real = "## 2026-06-12 (правка 🚀 токен-лик)\n\n### Done\n- готово ✅\n"
    stub = _stub_block("2026-01-02", "aaaaaaaa")
    kept, moved = cz.split_progress(real + stub, {"aaaaaaaa"})
    assert kept == real
    assert moved == stub
    # Concatenating the two slices reproduces the input exactly (byte-identity).
    assert kept + moved == real + stub


def test_split_progress_backslashes_in_real_and_stub_preserved():
    real = "## 2026-06-12 (path C:\\Users\\x)\n\n### Done\n- regex \\d+ \\n literal\n"
    stub = _stub_block("2026-01-02", "aaaaaaaa")
    kept, moved = cz.split_progress(real + stub, {"aaaaaaaa"})
    assert kept == real
    assert moved == stub


def test_split_progress_exact_stub_match_moves_when_sid_archived():
    stub = _stub_block("2026-01-02", "aaaaaaaa")
    kept, moved = cz.split_progress(stub, {"aaaaaaaa"})
    assert kept == ""
    assert moved == stub


def test_split_progress_sid_not_in_archived_is_kept():
    stub = _stub_block("2026-01-02", "dddddddd")
    kept, moved = cz.split_progress(stub, {"aaaaaaaa"})  # dddddddd not consolidated
    assert kept == stub
    assert moved == ""


def test_split_progress_impure_block_with_extra_content_is_kept():
    impure = (
        "## 2026-01-04\n\n### Auto-capture 2026-01-04 (session eeeeeeee)\n"
        f"{B1}\n{B2}\n- Plus an extra hand-written line.\n"
    )
    kept, moved = cz.split_progress(impure, {"eeeeeeee"})
    assert kept == impure  # extra content → not a pure stub → never moves
    assert moved == ""


def test_split_progress_fence_aware_inner_heading_not_a_boundary():
    """A ``## ``-looking line inside a fenced code block in a REAL entry must NOT be
    treated as a block boundary that could split the entry into a stub-shaped slice."""
    real = (
        "## 2026-06-12 (real)\n\n```\n"
        "## 2026-01-02\n"  # looks like a date heading but is INSIDE a fence
        f"### Auto-capture 2026-01-02 (session aaaaaaaa)\n{B1}\n{B2}\n"
        "```\n\n- still part of the real entry\n"
    )
    stub = _stub_block("2026-01-03", "bbbbbbbb")
    kept, moved = cz.split_progress(real + stub, {"aaaaaaaa", "bbbbbbbb"})
    assert kept == real  # the fenced pseudo-stub is NOT extracted
    assert moved == stub  # only the genuine top-level stub moves


def test_split_progress_empty_file_is_byte_identical():
    kept, moved = cz.split_progress("", {"aaaaaaaa"})
    assert kept == ""
    assert moved == ""


def test_split_progress_preamble_only_file_is_byte_identical():
    preamble = "# Progress Log\n\nSome intro text, no headings yet.\n"
    kept, moved = cz.split_progress(preamble, {"aaaaaaaa"})
    assert kept == preamble
    assert moved == ""


def test_split_progress_mixed_keeps_real_moves_only_archived_stub():
    real = "## 2026-06-12 (real)\n\n### Done\n- kept\n"
    stub_a = _stub_block("2026-01-02", "aaaaaaaa")  # archived → moves
    stub_d = _stub_block("2026-06-11", "dddddddd")  # not archived → kept
    text = real + stub_a + stub_d
    kept, moved = cz.split_progress(text, {"aaaaaaaa"})
    assert kept == real + stub_d
    assert moved == stub_a
    # Reorder-only invariant: kept + moved is a byte-permutation of the blocks.
    assert kept + moved == real + stub_d + stub_a


# ─────────────────────────────────────────────────────────────────────────────
# files_touched — the modern ` · ok · +A/-B` tail must NOT leak into the list
# ─────────────────────────────────────────────────────────────────────────────
def test_files_touched_ignores_outcome_and_diffstat_tail():
    raw = (
        "## Live log\n"
        '- 10:00 — User: "fix" · tools: Edit,Bash · files: scripts/mb-foo.py · ok · +12/-3\n'
    )
    assert cz.files_touched(raw) == {"scripts/mb-foo.py"}


def test_files_touched_multiple_files_split_on_comma():
    raw = '## Live log\n- 11:00 — User: "x" · tools: Edit · files: a.py, b.py · err(1) · +1/-0\n'
    assert cz.files_touched(raw) == {"a.py", "b.py"}


def test_files_touched_reads_schema_v2_files_section():
    raw = "## Summary\n### Files\n- src/app.py\n- src/lib.py\n### Decisions\n- (none)\n"
    assert cz.files_touched(raw) == {"src/app.py", "src/lib.py"}


def test_files_touched_none_marker_is_excluded():
    raw = '## Live log\n- 09:00 — User: "y" · tools: Read · files: (none)\n'
    assert cz.files_touched(raw) == set()


# ─────────────────────────────────────────────────────────────────────────────
# cluster_sessions — chained cluster via occurrence-count shared files
# ─────────────────────────────────────────────────────────────────────────────
def _sess(name: str, files: set[str], tokens: set[str] | None = None) -> cz.Session:
    return cz.Session(Path(f"/x/{name}.md"), f"{name}.md", name[-8:], files, tokens or set())


def test_cluster_chained_via_shared_files_with_empty_full_intersection():
    """A&B share X, B&C share Y → all three cluster even though X∩Y∩Z = ∅."""
    a = _sess("2026-01-01_1000_aaaaaaaa", {"X"})
    b = _sess("2026-01-02_1000_bbbbbbbb", {"X", "Y"})
    c = _sess("2026-01-03_1000_cccccccc", {"Y"})
    windowed = [a, b, c]
    clusters = cz.cluster_sessions(windowed)
    # Exactly one cluster containing all three indices.
    assert len(clusters) == 1
    (members,) = clusters.values()
    assert sorted(members) == [0, 1, 2]


def test_recurring_files_uses_occurrence_count_not_intersection():
    """X (in A,B) and Y (in B,C) both recur (>=2) though the 3-way intersection is empty."""
    a = _sess("2026-01-01_1000_aaaaaaaa", {"X"})
    b = _sess("2026-01-02_1000_bbbbbbbb", {"X", "Y"})
    c = _sess("2026-01-03_1000_cccccccc", {"Y"})
    assert cz._recurring([a, b, c], "files") == ["X", "Y"]


def test_cluster_unrelated_sessions_do_not_link():
    a = _sess("2026-01-01_1000_aaaaaaaa", {"X"}, {"alpha", "beta", "gamma"})
    b = _sess("2026-01-02_1000_bbbbbbbb", {"Z"}, {"delta", "epsilon", "zeta"})
    clusters = cz.cluster_sessions([a, b])
    # No shared file, no lexical overlap → two singleton clusters.
    assert sorted(len(v) for v in clusters.values()) == [1, 1]


def test_cluster_links_on_lexical_overlap_above_threshold():
    # Identical token sets → Jaccard 1.0 > 0.2 → linked even with no shared files.
    toks = {"token", "leak", "extractor"}
    a = _sess("2026-01-01_1000_aaaaaaaa", set(), toks)
    b = _sess("2026-01-02_1000_bbbbbbbb", set(), set(toks))
    clusters = cz.cluster_sessions([a, b])
    assert len(clusters) == 1
