"""Tests for community-summary retrieval (REQ-008, design §A5).

When a wiki ARTICLE lands in the top-3 final hits, ``run_search`` appends a
labeled ``community_files`` block listing the member files of that article's
community (capped at ≤10, stable order). No wiki / article ranked 4th-or-lower /
no packs file → exact no-op: the result dict is byte-identical to pre-change
(the ``community_files`` key is absent).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import community_expand as ce  # noqa: E402
from memory_bank_skill import semantic_search as ss  # noqa: E402

# ── fixtures ─────────────────────────────────────────────────────────


def _write_graph(mb: Path, nodes: list[dict]) -> None:
    cb = mb / "codebase"
    cb.mkdir(parents=True, exist_ok=True)
    lines = [{"type": "node", **n} for n in nodes]
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")


def _write_wiki(mb: Path, community_id: int, title_body: str) -> None:
    wiki = mb / "codebase" / "wiki"
    wiki.mkdir(parents=True, exist_ok=True)
    (wiki / f"community-{community_id}.md").write_text(title_body, encoding="utf-8")


def _write_packs(mb: Path, packs: list[dict]) -> None:
    (mb / "codebase" / ".wiki-packs.json").write_text(json.dumps(packs), encoding="utf-8")


# ── pure helper: load_community_files (mapping) ──────────────────────


def test_load_community_files_maps_article_id_to_members(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    _write_packs(mb, [{"community_id": 0, "files": ["auth.py", "login.py"]}])
    mapping = ce.load_community_files(mb / "codebase")
    assert mapping["wiki/community-0.md"] == ["auth.py", "login.py"]


def test_load_community_files_missing_packs_is_empty(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    assert ce.load_community_files(mb / "codebase") == {}


def test_load_community_files_malformed_is_empty(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    (mb / "codebase" / ".wiki-packs.json").write_text("{not json", encoding="utf-8")
    assert ce.load_community_files(mb / "codebase") == {}


def test_load_community_files_caps_and_sorts(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    members = [f"mod_{i:02d}.py" for i in range(15)]
    _write_packs(mb, [{"community_id": 3, "files": list(reversed(members))}])
    mapping = ce.load_community_files(mb / "codebase")
    files = mapping["wiki/community-3.md"]
    assert len(files) == 10  # capped at MAX_COMMUNITY_FILES
    assert files == sorted(members)[:10]  # stable, sorted order


# ── expand_hits: top-3 boundary + no-op rules ────────────────────────


def _wiki_hit(cid: int) -> dict:
    return {
        "id": f"wiki/community-{cid}.md",
        "file": f"wiki/community-{cid}.md",
        "score": 9.0,
        "kind": "wiki",
        "is_test": False,
    }


def _code_hit(name: str) -> dict:
    return {
        "id": f"{name}.py:f",
        "file": f"{name}.py",
        "score": 1.0,
        "kind": "function",
        "is_test": False,
    }


def test_expand_hits_article_in_top3_yields_block():
    hits = [_wiki_hit(0), _code_hit("a"), _code_hit("b")]
    mapping = {"wiki/community-0.md": ["auth.py", "login.py"]}
    blocks = ce.expand_hits(hits, mapping)
    assert blocks == [{"article": "wiki/community-0.md", "files": ["auth.py", "login.py"]}]


def test_expand_hits_article_below_top3_is_noop():
    # article ranked 4th — outside the top-3 window → no expansion.
    hits = [_code_hit("a"), _code_hit("b"), _code_hit("c"), _wiki_hit(0)]
    mapping = {"wiki/community-0.md": ["auth.py"]}
    assert ce.expand_hits(hits, mapping) == []


def test_expand_hits_no_mapping_is_noop():
    hits = [_wiki_hit(0)]
    assert ce.expand_hits(hits, {}) == []


def test_expand_hits_article_without_mapping_entry_is_noop():
    hits = [_wiki_hit(7)]
    mapping = {"wiki/community-0.md": ["auth.py"]}  # no entry for community 7
    assert ce.expand_hits(hits, mapping) == []


def test_expand_hits_non_article_hit_is_noop():
    hits = [_code_hit("a"), _code_hit("b")]
    mapping = {"wiki/community-0.md": ["auth.py"]}
    assert ce.expand_hits(hits, mapping) == []


# ── run_search integration ───────────────────────────────────────────


def _mb_with_wiki(tmp_path: Path) -> Path:
    """Graph + wiki article that BM25-matches 'authenticate' + packs with >10 members."""
    mb = tmp_path / ".memory-bank"
    _write_graph(
        mb,
        [
            {"kind": "function", "name": "authenticate_user", "file": "auth.py", "line": 1},
        ],
    )
    _write_wiki(mb, 0, "# Auth cluster\nauthenticate authenticate authenticate login session")
    members = [f"member_{i:02d}.py" for i in range(12)]
    _write_packs(mb, [{"community_id": 0, "files": members}])
    return mb


def test_run_search_expands_top_wiki_article(tmp_path: Path):
    mb = _mb_with_wiki(tmp_path)
    result = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    # wiki article must be in the top-3 to drive expansion
    top3_ids = [h["id"] for h in result["hits"][:3]]
    assert "wiki/community-0.md" in top3_ids
    assert "community_files" in result
    block = result["community_files"][0]
    assert block["article"] == "wiki/community-0.md"
    assert len(block["files"]) == 10  # capped
    assert block["files"] == sorted(f"member_{i:02d}.py" for i in range(12))[:10]


def test_run_search_no_wiki_is_byte_identical(tmp_path: Path):
    """No wiki dir → result has NO community_files key (byte-identical regression)."""
    mb = tmp_path / ".memory-bank"
    _write_graph(
        mb,
        [
            {"kind": "function", "name": "authenticate_user", "file": "auth.py", "line": 1},
            {"kind": "function", "name": "render_cart", "file": "cart.py", "line": 1},
        ],
    )
    result = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    assert "community_files" not in result
    assert set(result.keys()) == {
        "ok",
        "query",
        "backend",
        "corpus_size",
        "source_only",
        "hits",
        "warnings",
    }


def test_run_search_wiki_but_no_packs_is_noop(tmp_path: Path):
    """Wiki article present but no .wiki-packs.json → no expansion key."""
    mb = tmp_path / ".memory-bank"
    _write_graph(
        mb,
        [
            {"kind": "function", "name": "authenticate_user", "file": "auth.py", "line": 1},
        ],
    )
    _write_wiki(mb, 0, "# Auth cluster\nauthenticate authenticate login")
    result = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    assert "community_files" not in result


def test_run_search_expansion_is_deterministic(tmp_path: Path):
    mb = _mb_with_wiki(tmp_path)
    first = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    second = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    assert first == second
    assert first["community_files"] == second["community_files"]


def test_load_community_files_invalid_utf8_is_empty(tmp_path: Path) -> None:
    """Invalid UTF-8 bytes in .wiki-packs.json must fail open to {} (REQ-008)."""
    (tmp_path / ".wiki-packs.json").write_bytes(b'[{"community_id": 1, "files": ["a.py"]}\xff\xfe]')
    assert ce.load_community_files(tmp_path) == {}
