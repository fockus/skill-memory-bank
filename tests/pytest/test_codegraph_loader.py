"""Tests for memory_bank_skill/codegraph_loader.py — canonical graph.json loader.

Single source of truth for parsing the JSON-Lines code graph. Splits records by
`type` into (nodes, edges); raises FileNotFoundError when absent and ValueError on
a malformed line (line number reported).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_loader as loader  # noqa: E402


def _write(path: Path, *lines: str) -> Path:
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def test_load_graph_splits_nodes_and_edges(tmp_path: Path):
    g = _write(
        tmp_path / "graph.json",
        '{"type": "node", "kind": "function", "name": "foo", "file": "a.py", "line": 1}',
        '{"type": "edge", "kind": "call", "src": "a.py:bar", "dst": "foo"}',
        '{"type": "node", "kind": "module", "name": "a.py", "file": "a.py", "line": 1}',
    )
    nodes, edges = loader.load_graph(g)
    assert len(nodes) == 2 and len(edges) == 1
    assert nodes[0]["name"] == "foo"
    assert edges[0]["kind"] == "call"


def test_load_graph_skips_blank_lines(tmp_path: Path):
    g = _write(
        tmp_path / "graph.json",
        '{"type": "node", "name": "x", "file": "x.py"}',
        "",
        "   ",
        '{"type": "edge", "src": "x.py", "dst": "y", "kind": "import"}',
    )
    nodes, edges = loader.load_graph(g)
    assert len(nodes) == 1 and len(edges) == 1


def test_load_graph_ignores_unknown_record_types(tmp_path: Path):
    g = _write(
        tmp_path / "graph.json",
        '{"type": "meta", "generated": "today"}',
        '{"type": "node", "name": "x", "file": "x.py"}',
    )
    nodes, edges = loader.load_graph(g)
    assert len(nodes) == 1 and edges == []


def test_load_graph_missing_file_raises(tmp_path: Path):
    with pytest.raises(FileNotFoundError):
        loader.load_graph(tmp_path / "nope.json")


def test_load_graph_malformed_line_raises_valueerror_with_line_number(tmp_path: Path):
    g = _write(
        tmp_path / "graph.json",
        '{"type": "node", "name": "ok", "file": "a.py"}',
        "{not valid json",
    )
    with pytest.raises(ValueError, match="line 2"):
        loader.load_graph(g)


def test_graph_query_core_delegates_to_loader(tmp_path: Path):
    """scripts/mb_graph_query_core.load_graph must keep its contract via delegation."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "mb_graph_query_core", REPO_ROOT / "scripts" / "mb_graph_query_core.py")
    gqc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gqc)
    g = _write(tmp_path / "graph.json", '{"type": "node", "name": "z", "file": "z.py"}')
    nodes, edges = gqc.load_graph(g)
    assert len(nodes) == 1 and edges == []
    with pytest.raises(FileNotFoundError):
        gqc.load_graph(tmp_path / "absent.json")
