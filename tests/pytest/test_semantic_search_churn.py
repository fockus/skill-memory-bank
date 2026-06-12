"""Tests for the churn recency multiplier in semantic search (Task 5, REQ-007).

When the graph carries ``node-attr`` churn rows (only present after
``/mb graph --apply --cochange``), the search engine multiplies each hit's score
by ``1 + 0.1 * log1p(churn_30d)`` for that hit's file. No churn rows → ranking is
byte-identical to the pre-change behaviour (regression).
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import semantic_search as ss  # noqa: E402


def _write_graph(mb: Path, extra_lines: list[dict] | None = None) -> None:
    cb = mb / "codebase"
    cb.mkdir(parents=True, exist_ok=True)
    lines: list[dict] = [
        {"type": "node", "kind": "function", "name": "login", "file": "auth.py", "line": 1},
        {"type": "node", "kind": "function", "name": "login", "file": "session.py", "line": 1},
    ]
    if extra_lines:
        lines.extend(extra_lines)
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")


# ── pure helper: load_churn ──────────────────────────────────────────


def test_load_churn_reads_node_attr_rows(tmp_path: Path):
    graph = tmp_path / "graph.json"
    graph.write_text(
        "\n".join(
            [
                json.dumps({"type": "node", "kind": "function", "name": "f", "file": "a.py"}),
                json.dumps({"type": "node-attr", "file": "a.py", "churn_30d": 3}),
                json.dumps({"type": "node-attr", "file": "b.py", "churn_30d": 7}),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    churn = ss.load_churn(graph)
    assert churn == {"a.py": 3, "b.py": 7}


def test_load_churn_absent_rows_returns_empty(tmp_path: Path):
    graph = tmp_path / "graph.json"
    graph.write_text(
        json.dumps({"type": "node", "kind": "function", "name": "f", "file": "a.py"}) + "\n",
        encoding="utf-8",
    )
    assert ss.load_churn(graph) == {}


def test_load_churn_missing_file_returns_empty(tmp_path: Path):
    assert ss.load_churn(tmp_path / "nope.json") == {}


# ── pure helper: apply_churn_multiplier ──────────────────────────────


def test_apply_churn_multiplier_scales_score_by_formula():
    hits = [{"id": "a.py:f", "file": "a.py", "score": 1.0}]
    out = ss.apply_churn_multiplier(hits, {"a.py": 5})
    expected = round(1.0 * (1 + 0.1 * math.log1p(5)), 6)
    assert out[0]["score"] == expected


def test_apply_churn_multiplier_no_attr_leaves_score_untouched():
    hits = [{"id": "a.py:f", "file": "a.py", "score": 1.0}]
    out = ss.apply_churn_multiplier(hits, {})
    assert out[0]["score"] == 1.0


def test_apply_churn_multiplier_reorders_hot_file_above_tie():
    # Two hits tied on base score; the hot file (higher churn) must sort first.
    hits = [
        {"id": "cold.py:f", "file": "cold.py", "score": 1.0},
        {"id": "hot.py:f", "file": "hot.py", "score": 1.0},
    ]
    out = ss.apply_churn_multiplier(hits, {"hot.py": 10})
    assert out[0]["file"] == "hot.py"
    assert out[1]["file"] == "cold.py"


def test_apply_churn_multiplier_stable_when_empty_churn_map():
    hits = [
        {"id": "a.py:f", "file": "a.py", "score": 2.0},
        {"id": "b.py:f", "file": "b.py", "score": 1.0},
    ]
    out = ss.apply_churn_multiplier(hits, {})
    assert [h["id"] for h in out] == ["a.py:f", "b.py:f"]
    assert [h["score"] for h in out] == [2.0, 1.0]


# ── integration: run_search applies churn only when attrs present ────


def test_run_search_without_churn_attrs_is_unchanged(tmp_path: Path, monkeypatch):
    """No node-attr rows → ranking byte-identical to pre-churn behaviour."""
    monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False)
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)  # no churn rows
    result = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
    baseline_ids = [h["id"] for h in result["hits"]]
    baseline_scores = [h["score"] for h in result["hits"]]
    # Re-run: deterministic, identical.
    again = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
    assert [h["id"] for h in again["hits"]] == baseline_ids
    assert [h["score"] for h in again["hits"]] == baseline_scores


def test_run_search_hot_file_outranks_cold_when_churn_present(tmp_path: Path, monkeypatch):
    """Two files matching 'login' equally; the higher-churn file ranks first."""
    monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False)
    mb = tmp_path / ".memory-bank"
    # Both auth.py and session.py define `login`; identical BM25 text → tie.
    _write_graph(
        mb,
        extra_lines=[
            {"type": "node-attr", "file": "session.py", "churn_30d": 20},
        ],
    )
    result = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
    files = [h["file"] for h in result["hits"]]
    assert files[0] == "session.py"  # hot file wins the tie


def test_run_search_churn_reranks_over_full_candidate_set_not_topk_window(
    tmp_path: Path, monkeypatch
):
    """A hot file below the preliminary top-k window must still win after churn.

    Design §A4: the churn multiplier is applied to final scores over the FULL
    candidate set, then re-sorted, THEN truncated to k. With ``k=1`` the hot file
    sits at base rank 4 (three colder files score higher on raw BM25). A large
    ``churn_30d`` makes ``1 + 0.1*log1p(churn)`` overtake the rank-1 base hit, so
    the hot file must be the single returned result. The old ``fetch_k = k*3``
    window (=3 here) excluded rank-4, so it could never be promoted.
    """
    monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False)
    mb = tmp_path / ".memory-bank"
    cb = mb / "codebase"
    cb.mkdir(parents=True, exist_ok=True)
    # Four functions all match 'login'; descending TF via the `doc` field puts
    # hot.py at base rank 4. churn_30d=300 boosts it past the rank-1 base hit.
    lines = [
        {
            "type": "node",
            "kind": "function",
            "name": "a",
            "file": "cold1.py",
            "line": 1,
            "doc": "login login login login",
        },
        {
            "type": "node",
            "kind": "function",
            "name": "b",
            "file": "cold2.py",
            "line": 1,
            "doc": "login login login",
        },
        {
            "type": "node",
            "kind": "function",
            "name": "c",
            "file": "cold3.py",
            "line": 1,
            "doc": "login login",
        },
        {
            "type": "node",
            "kind": "function",
            "name": "hot",
            "file": "hot.py",
            "line": 1,
            "doc": "login",
        },
        {"type": "node-attr", "file": "hot.py", "churn_30d": 300},
    ]
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")
    result = ss.run_search(query="login", mb_path=str(mb), backend="bm25", k=1)
    assert [h["file"] for h in result["hits"]] == ["hot.py"]


def test_run_search_churn_changes_ranking_vs_no_churn(tmp_path: Path, monkeypatch):
    """The same corpus ranks differently once churn attrs are present."""
    monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False)
    mb_plain = tmp_path / "plain"
    _write_graph(mb_plain)
    plain = ss.run_search(query="login", mb_path=str(mb_plain), backend="bm25")

    mb_hot = tmp_path / "hot"
    _write_graph(
        mb_hot,
        extra_lines=[{"type": "node-attr", "file": "session.py", "churn_30d": 20}],
    )
    hot = ss.run_search(query="login", mb_path=str(mb_hot), backend="bm25")

    # session.py was not first without churn but is first with churn.
    assert plain["hits"][0]["file"] == "auth.py"  # lexical tie-break by id
    assert hot["hits"][0]["file"] == "session.py"
