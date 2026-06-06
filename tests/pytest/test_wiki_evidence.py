"""Tests for memory_bank_skill/wiki_evidence.py — deterministic per-community packs.

The pure prep the `/mb wiki` command feeds to Haiku subagents: for each detected
community, the member files, key symbols (by degree), and short code excerpts.
No LLM, no network.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import wiki_evidence as we  # noqa: E402


def _graph():
    nodes = [
        {"kind": "module", "name": "auth.py", "file": "auth.py", "line": 1},
        {"kind": "function", "name": "login", "file": "auth.py", "line": 3},
        {"kind": "module", "name": "cart.py", "file": "cart.py", "line": 1},
        {"kind": "class", "name": "Cart", "file": "cart.py", "line": 2},
    ]
    edges = [{"src": "cart.py:Cart", "dst": "login", "kind": "call"}]
    return nodes, edges


def test_build_packs_one_per_community(tmp_path: Path):
    (tmp_path / "auth.py").write_text("def login():\n    return 1\n", encoding="utf-8")
    (tmp_path / "cart.py").write_text("class Cart:\n    pass\n", encoding="utf-8")
    nodes, edges = _graph()
    communities = {"auth.py": 0, "cart.py": 1}
    packs = we.build_community_packs(nodes, edges, communities, tmp_path)
    assert len(packs) == 2
    assert packs[0]["community_id"] == 0
    assert packs[0]["files"] == ["auth.py"]


def test_pack_has_key_symbols_and_excerpts(tmp_path: Path):
    (tmp_path / "auth.py").write_text("def login():\n    return 1\n", encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"auth.py": 0}, tmp_path)
    pack = packs[0]
    assert any(s["name"] == "login" for s in pack["key_symbols"])
    assert "auth.py" in pack["excerpts"] and "def login" in pack["excerpts"]["auth.py"]


def test_empty_communities_yields_no_packs(tmp_path: Path):
    nodes, edges = _graph()
    assert we.build_community_packs(nodes, edges, {}, tmp_path) == []
    assert we.build_community_packs(nodes, edges, None, tmp_path) == []


def test_missing_excerpt_file_is_skipped_not_crash(tmp_path: Path):
    nodes, edges = _graph()
    # no files written → excerpts empty, no exception
    packs = we.build_community_packs(nodes, edges, {"auth.py": 0}, tmp_path)
    assert packs[0]["excerpts"] == {}


def test_excerpt_truncated_to_max_lines(tmp_path: Path):
    body = "\n".join(f"line{i}" for i in range(100)) + "\n"
    (tmp_path / "auth.py").write_text(body, encoding="utf-8")
    nodes, edges = _graph()
    packs = we.build_community_packs(nodes, edges, {"auth.py": 0}, tmp_path,
                                     max_excerpt_lines=5)
    assert packs[0]["excerpts"]["auth.py"].count("\n") <= 4


# ── review-fix: path containment ─────────────────────────────────────

def test_excerpt_refuses_path_traversal(tmp_path: Path):
    code_root = tmp_path / "code"
    code_root.mkdir()
    secret = tmp_path / "SECRET.txt"
    secret.write_text("TOP SECRET", encoding="utf-8")
    nodes = [{"kind": "module", "name": "../SECRET.txt", "file": "../SECRET.txt", "line": 1}]
    packs = we.build_community_packs(nodes, [], {"../SECRET.txt": 0}, code_root)
    # the traversal path is refused → its content never leaks into the pack
    assert "TOP SECRET" not in str(packs[0]["excerpts"])
    assert packs[0]["excerpts"] == {}


def test_excerpt_refuses_absolute_path(tmp_path: Path):
    code_root = tmp_path / "code"
    code_root.mkdir()
    outside = tmp_path / "outside.txt"
    outside.write_text("LEAK", encoding="utf-8")
    abs_path = str(outside)
    nodes = [{"kind": "module", "name": abs_path, "file": abs_path, "line": 1}]
    packs = we.build_community_packs(nodes, [], {abs_path: 0}, code_root)
    assert "LEAK" not in str(packs[0]["excerpts"])
