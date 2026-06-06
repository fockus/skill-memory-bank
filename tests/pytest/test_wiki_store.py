"""Tests for memory_bank_skill/wiki_store.py — wiki IO + semantic-edge merge.

Article/index writing (atomic) and the safe merge of LLM-produced "surprising
connection" edges into graph.json: malformed input is dropped, confidence clamped,
and merging is idempotent so re-running `/mb wiki` never duplicates or corrupts.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_loader as loader  # noqa: E402
from memory_bank_skill import wiki_store as wstore  # noqa: E402

# ── validate_semantic_edges ──────────────────────────────────────────

def test_validate_accepts_well_formed_edges():
    raw = [{"src": "a.py", "dst": "b.py", "confidence": 0.8, "rationale": "both parse config"}]
    out = wstore.validate_semantic_edges(raw)
    assert out == [{"src": "a.py", "dst": "b.py", "kind": "semantic",
                    "confidence": 0.8, "rationale": "both parse config"}]


def test_validate_drops_malformed_and_clamps_confidence():
    raw = [
        {"src": "a.py"},                                  # missing dst → dropped
        {"src": "a.py", "dst": "b.py", "confidence": 5},  # clamp → 1.0
        {"dst": "c.py"},                                  # missing src → dropped
        "garbage",                                        # not a dict → dropped
    ]
    out = wstore.validate_semantic_edges(raw)
    assert len(out) == 1
    assert out[0]["confidence"] == 1.0


def test_validate_parses_json_string():
    raw = json.dumps([{"src": "a.py", "dst": "b.py", "confidence": 0.5}])
    out = wstore.validate_semantic_edges(raw)
    assert out and out[0]["kind"] == "semantic"


def test_validate_bad_json_string_returns_empty():
    assert wstore.validate_semantic_edges("{not json") == []


# ── merge_semantic_edges ─────────────────────────────────────────────

def _seed_graph(tmp_path: Path) -> Path:
    g = tmp_path / "graph.json"
    g.write_text(
        '{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}\n'
        '{"type": "edge", "kind": "call", "src": "a.py:f", "dst": "g"}\n',
        encoding="utf-8")
    return g


def test_merge_adds_semantic_edges(tmp_path: Path):
    g = _seed_graph(tmp_path)
    edges = [{"src": "a.py", "dst": "b.py", "kind": "semantic", "confidence": 0.7}]
    added = wstore.merge_semantic_edges(g, edges)
    assert added == 1
    nodes, all_edges = loader.load_graph(g)
    assert any(e.get("kind") == "semantic" for e in all_edges)
    assert len(nodes) == 1  # original node intact


def test_merge_is_idempotent(tmp_path: Path):
    g = _seed_graph(tmp_path)
    edges = [{"src": "a.py", "dst": "b.py", "kind": "semantic", "confidence": 0.7}]
    assert wstore.merge_semantic_edges(g, edges) == 1
    assert wstore.merge_semantic_edges(g, edges) == 0  # second time: no dupes


def test_merge_keeps_graph_valid_jsonlines(tmp_path: Path):
    g = _seed_graph(tmp_path)
    wstore.merge_semantic_edges(g, [{"src": "x", "dst": "y", "kind": "semantic"}])
    # loader must still parse without error
    nodes, edges = loader.load_graph(g)
    assert nodes and edges


# ── article / index IO ───────────────────────────────────────────────

def test_write_article_round_trip(tmp_path: Path):
    wiki = tmp_path / "wiki"
    p = wstore.write_article(wiki, 3, "# Community 3\nstuff")
    assert p == wstore.article_path(wiki, 3)
    assert "Community 3" in p.read_text(encoding="utf-8")


def test_write_index_lists_communities(tmp_path: Path):
    wiki = tmp_path / "wiki"
    packs = [{"community_id": 0, "files": ["a.py", "b.py"], "key_symbols": [], "excerpts": {}}]
    idx = wstore.write_index(wiki, packs)
    text = idx.read_text(encoding="utf-8")
    assert "community-0.md" in text and "Community 0" in text


# ── review-fix regressions ───────────────────────────────────────────

def test_validate_rejects_nan_and_inf_confidence():
    out = wstore.validate_semantic_edges([
        {"src": "a", "dst": "b", "confidence": float("nan")},
        {"src": "c", "dst": "d", "confidence": float("inf")},
        {"src": "e", "dst": "f", "confidence": float("-inf")},
    ])
    assert [e["confidence"] for e in out] == [0.5, 0.5, 0.5]
    # serialises to valid JSON (no bare NaN/Infinity)
    json.loads(json.dumps(out))


def test_validate_treats_bool_confidence_as_default():
    out = wstore.validate_semantic_edges([{"src": "a", "dst": "b", "confidence": True}])
    assert out[0]["confidence"] == 0.5


def test_merge_preserves_crlf_line_endings(tmp_path: Path):
    g = tmp_path / "graph.json"
    g.write_bytes(
        b'{"type": "node", "kind": "function", "name": "f", "file": "a.py", "line": 1}\r\n'
        b'{"type": "edge", "kind": "call", "src": "a.py:f", "dst": "g"}\r\n')
    wstore.merge_semantic_edges(g, [{"src": "a.py", "dst": "b.py", "kind": "semantic"}])
    data = g.read_bytes()
    assert b"\r\n" in data  # existing CRLF lines preserved (no full-file rewrite)
    # graph still parses
    nodes, edges = loader.load_graph(g)
    assert nodes and any(e.get("kind") == "semantic" for e in edges)
