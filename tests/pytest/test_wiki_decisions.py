"""Tests for the `## Decisions` section of wiki evidence packs (REQ-028).

Deterministic ($0 — no LLM): for each community, scan ``notes/`` and session
summaries for lines mentioning a member file's BASENAME, attribute the top-5
matched lines to the community, each carrying a source ref. Unrelated notes are
absent; an empty/missing ``notes/`` directory omits the section entirely
(fail-open, no error).
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import wiki_evidence as we  # noqa: E402


def _graph():
    nodes = [
        {"kind": "module", "name": "semantic_search.py", "file": "semantic_search.py", "line": 1},
        {"kind": "function", "name": "run_search", "file": "semantic_search.py", "line": 3},
    ]
    edges: list[dict] = []
    return nodes, edges


def _seed_bank(tmp_path: Path) -> tuple[Path, Path]:
    """Create a code root + a sibling memory bank with notes/ and session/."""
    code_root = tmp_path / "code"
    code_root.mkdir()
    (code_root / "semantic_search.py").write_text(
        "def run_search():\n    return 1\n", encoding="utf-8"
    )
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    (mb / "session").mkdir(parents=True)
    return code_root, mb


def test_matching_note_appears_in_decisions_with_ref(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    note = mb / "notes" / "2026-01-01_rrf.md"
    note.write_text(
        "# RRF rollout\n\n"
        "- `semantic_search.py` now fuses BM25 + embeddings via RRF.\n"
        "- Unrelated bullet about deployment.\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    decisions = packs[0]["decisions"]
    assert any("fuses BM25" in d["line"] for d in decisions)
    matched = next(d for d in decisions if "fuses BM25" in d["line"])
    assert matched["source"].endswith("notes/2026-01-01_rrf.md")


def test_unrelated_note_absent(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    (mb / "notes" / "2026-01-02_other.md").write_text(
        "# Landing site\n\n- We deployed the site via GitHub Pages.\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert packs[0]["decisions"] == []


def test_empty_notes_dir_omits_section(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    # notes/ and session/ exist but are empty
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert "decisions" not in packs[0]


def test_missing_notes_dir_no_error(tmp_path: Path):
    code_root = tmp_path / "code"
    code_root.mkdir()
    (code_root / "semantic_search.py").write_text("x = 1\n", encoding="utf-8")
    mb = tmp_path / ".memory-bank"  # never created
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert "decisions" not in packs[0]


def test_no_mb_root_keeps_legacy_packs(tmp_path: Path):
    """Existing call site (no mb_root) → no decisions key, byte-identical pack."""
    code_root = tmp_path / "code"
    code_root.mkdir()
    (code_root / "semantic_search.py").write_text("x = 1\n", encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root)
    assert "decisions" not in packs[0]


def test_decisions_capped_at_five(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    lines = "\n".join(f"- `semantic_search.py` decision number {i}." for i in range(8))
    (mb / "notes" / "2026-01-03_many.md").write_text(f"# Many\n\n{lines}\n", encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert len(packs[0]["decisions"]) == 5


def test_session_summary_lines_matched(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    # Real v2 schema: the `### Decisions` subsection lives under `## Summary`.
    (mb / "session" / "2026-06-09_1832_abc.md").write_text(
        "---\nsession_id: abc\n---\n\n"
        "## Summary\n"
        "### Decisions\n"
        "- Reworked semantic_search.py to fuse rankings.\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    decisions = packs[0]["decisions"]
    assert any("fuse rankings" in d["line"] for d in decisions)
    matched = next(d for d in decisions if "fuse rankings" in d["line"])
    assert "session/2026-06-09_1832_abc.md" in matched["source"]


def test_decisions_deterministic_across_runs(tmp_path: Path):
    code_root, mb = _seed_bank(tmp_path)
    (mb / "notes" / "2026-01-04_a.md").write_text(
        "- semantic_search.py alpha decision.\n", encoding="utf-8"
    )
    (mb / "notes" / "2026-01-04_b.md").write_text(
        "- semantic_search.py beta decision.\n", encoding="utf-8"
    )
    (mb / "session" / "2026-06-09_1900_z.md").write_text(
        "## Summary\n### Decisions\n- semantic_search.py gamma decision.\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    first = we.build_community_packs(
        nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb
    )[0]["decisions"]
    second = we.build_community_packs(
        nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb
    )[0]["decisions"]
    assert first == second


# ── Blocker 1: basename matching must be path/code-TOKEN bounded ──────────────
# A community file `io.py` must NOT match the unrelated token `scenario.py`
# (the substring "io.py" literally occurs inside "scenario.py").


def _io_graph():
    nodes = [
        {"kind": "module", "name": "io.py", "file": "io.py", "line": 1},
        {"kind": "function", "name": "read_io", "file": "io.py", "line": 3},
    ]
    return nodes, []


def _seed_io_bank(tmp_path: Path) -> tuple[Path, Path]:
    code_root = tmp_path / "code"
    code_root.mkdir()
    (code_root / "io.py").write_text("def read_io():\n    return 1\n", encoding="utf-8")
    mb = tmp_path / ".memory-bank"
    (mb / "notes").mkdir(parents=True)
    (mb / "session").mkdir(parents=True)
    return code_root, mb


def test_basename_substring_of_other_token_not_matched(tmp_path: Path):
    """`io.py` must not match a note line that only mentions `scenario.py`."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_scenario.md").write_text(
        "- Reworked scenario.py to add edge cases.\n", encoding="utf-8"
    )
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert packs[0]["decisions"] == []


def test_basename_as_bare_token_matched(tmp_path: Path):
    """`fixed io.py today` — whitespace-bounded token — matches."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_bare.md").write_text("- fixed io.py today\n", encoding="utf-8")
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert any("fixed io.py today" in d["line"] for d in packs[0]["decisions"])


def test_basename_in_path_matched(tmp_path: Path):
    """`scripts/io.py refactored` — path-separator-bounded — matches."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_path.md").write_text(
        "- scripts/io.py refactored for clarity\n", encoding="utf-8"
    )
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert any("scripts/io.py" in d["line"] for d in packs[0]["decisions"])


def test_basename_with_extra_suffix_not_matched(tmp_path: Path):
    """`io.py` must NOT match the longer token `io.pyc` (trailing boundary)."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_suffix.md").write_text(
        "- Cleaned up the io.pyc cache files.\n", encoding="utf-8"
    )
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert packs[0]["decisions"] == []


def test_basename_in_backticks_matched(tmp_path: Path):
    """`` `io.py` `` — backtick-bounded — matches."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_tick.md").write_text(
        "- `io.py` now streams chunks\n", encoding="utf-8"
    )
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert any("now streams chunks" in d["line"] for d in packs[0]["decisions"])


def test_basename_at_line_start_matched(tmp_path: Path):
    """A line beginning with the basename (start-of-line boundary) matches."""
    code_root, mb = _seed_io_bank(tmp_path)
    (mb / "notes" / "2026-01-05_start.md").write_text("io.py was rewritten\n", encoding="utf-8")
    nodes, edges = _io_graph()
    packs = we.build_community_packs(nodes, edges, {"io.py": 0}, code_root, mb_root=mb)
    assert any("io.py was rewritten" in d["line"] for d in packs[0]["decisions"])


# ── Blocker 2: session/ scans only the Summary, never Live log / frontmatter / Files ──


def test_session_files_subsection_path_not_a_decision(tmp_path: Path):
    """A `### Files` path-list line is NOT a decision; the real decision below is."""
    code_root, mb = _seed_bank(tmp_path)
    (mb / "session" / "2026-06-09_2000_files.md").write_text(
        "---\n"
        "session_id: files\n"
        "started: 2026-06-09T20:00Z\n"
        "---\n\n"
        "## Live log\n"
        '- 20:00 — User: "work" · files: semantic_search.py\n\n'
        "## Summary\n"
        "### What changed\n"
        "Touched the searcher.\n"
        "### Decisions\n"
        "- Chose RRF for semantic_search.py fusion.\n"
        "### Files\n"
        "semantic_search.py\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    decisions = packs[0]["decisions"]
    lines = [d["line"] for d in decisions]
    assert "Chose RRF for semantic_search.py fusion." in [line.lstrip("- ") for line in lines]
    # The bare path-list line under ### Files must never surface as a decision.
    assert "semantic_search.py" not in lines


def test_session_frontmatter_and_live_log_basename_not_matched(tmp_path: Path):
    """A basename only in frontmatter / Live log (no Summary mention) → no decisions."""
    code_root, mb = _seed_bank(tmp_path)
    (mb / "session" / "2026-06-09_2010_noise.md").write_text(
        "---\n"
        "session_id: semantic_search.py-ish\n"
        "transcript: /x/semantic_search.py.jsonl\n"
        "---\n\n"
        "## Live log\n"
        '- 20:10 — User: "x" · files: semantic_search.py\n\n'
        "## Summary\n"
        "### What changed\n"
        "Unrelated landing-page tweak.\n"
        "### Decisions\n"
        "- Switched the footer to flexbox.\n",
        encoding="utf-8",
    )
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert packs[0]["decisions"] == []


def test_basename_at_sentence_end_with_period_matches(tmp_path: Path):
    """`fixed semantic_search.py.` mentions the basename — terminal punctuation must not hide it."""
    code_root, mb = _seed_bank(tmp_path)
    note = mb / "notes" / "2026-01-02_fix.md"
    note.write_text("We fixed semantic_search.py.\n", encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert any("fixed semantic_search.py" in d["line"] for d in packs[0].get("decisions", []))


def test_basename_with_dotted_suffix_not_matched(tmp_path: Path):
    """`semantic_search.py.bak` is a different artifact — a dotted suffix must NOT match."""
    code_root, mb = _seed_bank(tmp_path)
    note = mb / "notes" / "2026-01-02_fix.md"
    note.write_text("Restored semantic_search.py.bak from backup.\n", encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"semantic_search.py": 0}, code_root, mb_root=mb)
    assert packs[0].get("decisions", []) == []
