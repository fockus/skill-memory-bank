"""Tests for memory_bank_skill/codegraph_analytics.py — deterministic graph analytics.

Contract (pure functions over the graph dict {"nodes":[...], "edges":[...]} that
mb-codegraph.build_graph returns):

  - compute_degree      → name-keyed in+out degree (matches legacy _compute_degree)
  - build_file_graph    → (files, undirected file-edge pairs) resolving call/inherit
                          edges to the file that DEFINES the target symbol
  - detect_communities  → file -> community id (0 = largest); None without networkx
  - file_cohesion       → intra-community edge density in [0, 1]
  - file_betweenness    → file -> betweenness; None without networkx
  - split_god_nodes     → {"modules": [...], "symbols": [...]} ranked by degree
  - render_god_nodes_md → markdown report (graceful without networkx)

networkx is an OPTIONAL dependency — graceful degradation is part of the contract.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import codegraph_analytics as cga  # noqa: E402

# ═══════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════

def _module(file: str) -> dict:
    return {"kind": "module", "name": file, "file": file, "line": 1}


def _fn(file: str, name: str, line: int = 1) -> dict:
    return {"kind": "function", "name": name, "file": file, "line": line}


def _cls(file: str, name: str, line: int = 1) -> dict:
    return {"kind": "class", "name": name, "file": file, "line": line}


def _call(src_file: str, src_fn: str, dst: str) -> dict:
    return {"src": f"{src_file}:{src_fn}", "dst": dst, "kind": "call"}


def _two_cluster_graph() -> dict:
    """Cluster A = a1/a2/a3 (call triangle), cluster B = b1/b2/b3, one bridge a1->b1."""
    nodes, edges = [], []
    for f in ("a1", "a2", "a3", "b1", "b2", "b3"):
        nodes.append(_module(f"{f}.py"))
        nodes.append(_fn(f"{f}.py", f"fn_{f}"))
    # triangle A
    edges += [_call("a1.py", "fn_a1", "fn_a2"),
              _call("a2.py", "fn_a2", "fn_a3"),
              _call("a3.py", "fn_a3", "fn_a1")]
    # triangle B
    edges += [_call("b1.py", "fn_b1", "fn_b2"),
              _call("b2.py", "fn_b2", "fn_b3"),
              _call("b3.py", "fn_b3", "fn_b1")]
    # bridge
    edges += [_call("a1.py", "fn_a1", "fn_b1")]
    return {"nodes": nodes, "edges": edges}


# ═══════════════════════════════════════════════════════════════
# compute_degree
# ═══════════════════════════════════════════════════════════════

def test_compute_degree_counts_in_and_out():
    graph = {
        "nodes": [_module("hub.py"), _fn("hub.py", "hub"),
                  _module("a.py"), _fn("a.py", "a")],
        "edges": [_call("a.py", "a", "hub")],
    }
    degree = cga.compute_degree(graph)
    # out-degree attributed to caller symbol, in-degree to callee node name
    assert degree["hub"] >= 1
    assert degree["a"] >= 1


def test_compute_degree_empty_graph_is_empty():
    assert cga.compute_degree({"nodes": [], "edges": []}) == {}


# ═══════════════════════════════════════════════════════════════
# build_file_graph
# ═══════════════════════════════════════════════════════════════

def test_build_file_graph_links_caller_to_definer_file():
    graph = {
        "nodes": [_module("a.py"), _fn("a.py", "fa"),
                  _module("b.py"), _fn("b.py", "fb")],
        "edges": [_call("a.py", "fa", "fb")],
    }
    files, fedges = cga.build_file_graph(graph)
    assert {"a.py", "b.py"} <= files
    assert frozenset(("a.py", "b.py")) in fedges


def test_build_file_graph_skips_self_loops():
    graph = {
        "nodes": [_module("a.py"), _fn("a.py", "fa"), _fn("a.py", "ga")],
        "edges": [_call("a.py", "fa", "ga")],  # same file
    }
    _, fedges = cga.build_file_graph(graph)
    assert fedges == set()


def test_build_file_graph_skips_external_unresolved_target():
    graph = {
        "nodes": [_module("a.py"), _fn("a.py", "fa")],
        "edges": [_call("a.py", "fa", "os.path.join")],  # not defined in project
    }
    _, fedges = cga.build_file_graph(graph)
    assert fedges == set()


def test_build_file_graph_skips_overambiguous_names():
    # `common` defined in 9 files → too ambiguous to resolve to one coupling edge
    nodes = [_module("caller.py"), _fn("caller.py", "c")]
    for i in range(9):
        nodes.append(_module(f"d{i}.py"))
        nodes.append(_fn(f"d{i}.py", "common"))
    graph = {"nodes": nodes, "edges": [_call("caller.py", "c", "common")]}
    _, fedges = cga.build_file_graph(graph)
    assert fedges == set()


# ═══════════════════════════════════════════════════════════════
# detect_communities  (optional networkx)
# ═══════════════════════════════════════════════════════════════

@pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")
def test_detect_communities_groups_dense_clusters():
    mapping = cga.detect_communities(_two_cluster_graph())
    assert mapping is not None
    # each cluster's files share one community id
    assert mapping["a1.py"] == mapping["a2.py"] == mapping["a3.py"]
    assert mapping["b1.py"] == mapping["b2.py"] == mapping["b3.py"]
    # the two clusters are distinct communities
    assert mapping["a1.py"] != mapping["b1.py"]


@pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")
def test_detect_communities_ids_largest_first():
    # cluster A has 3 files, cluster B has 2 → A should be community 0
    nodes, edges = [], []
    for f in ("a1", "a2", "a3", "b1", "b2"):
        nodes += [_module(f"{f}.py"), _fn(f"{f}.py", f"fn_{f}")]
    edges += [_call("a1.py", "fn_a1", "fn_a2"), _call("a2.py", "fn_a2", "fn_a3"),
              _call("a3.py", "fn_a3", "fn_a1"), _call("b1.py", "fn_b1", "fn_b2"),
              _call("b2.py", "fn_b2", "fn_b1")]
    mapping = cga.detect_communities({"nodes": nodes, "edges": edges})
    assert mapping["a1.py"] == 0  # largest community gets id 0


def test_detect_communities_none_without_networkx(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    assert cga.detect_communities(_two_cluster_graph()) is None


# ═══════════════════════════════════════════════════════════════
# file_cohesion
# ═══════════════════════════════════════════════════════════════

def test_file_cohesion_full_clique_is_one():
    edges = {frozenset(("a", "b")), frozenset(("b", "c")), frozenset(("a", "c"))}
    assert cga.file_cohesion(edges, ["a", "b", "c"]) == pytest.approx(1.0)


def test_file_cohesion_no_internal_edges_is_zero():
    edges = {frozenset(("a", "x"))}  # x not in community
    assert cga.file_cohesion(edges, ["a", "b", "c"]) == pytest.approx(0.0)


def test_file_cohesion_single_file_is_one():
    assert cga.file_cohesion(set(), ["solo"]) == pytest.approx(1.0)


# ═══════════════════════════════════════════════════════════════
# file_betweenness  (optional networkx)
# ═══════════════════════════════════════════════════════════════

@pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")
def test_file_betweenness_bridge_files_rank_highest():
    bt = cga.file_betweenness(_two_cluster_graph())
    assert bt is not None
    # a1 and b1 are the bridge endpoints — every cross-cluster path crosses them
    bridge = min(bt["a1.py"], bt["b1.py"])
    others = max(bt["a2.py"], bt["a3.py"], bt["b2.py"], bt["b3.py"])
    assert bridge > others


def test_file_betweenness_none_without_networkx(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    assert cga.file_betweenness(_two_cluster_graph()) is None


# ═══════════════════════════════════════════════════════════════
# split_god_nodes
# ═══════════════════════════════════════════════════════════════

def test_split_god_nodes_separates_modules_from_symbols():
    graph = {
        "nodes": [_module("big.test.py"), _fn("svc.py", "handle"), _cls("svc.py", "Service")],
        "edges": [],
    }
    degree = {"big.test.py": 50, "handle": 10, "Service": 8}
    out = cga.split_god_nodes(graph, degree, top_n=20)
    mod_names = {r["name"] for r in out["modules"]}
    sym_names = {r["name"] for r in out["symbols"]}
    assert "big.test.py" in mod_names
    assert {"handle", "Service"} <= sym_names
    assert "big.test.py" not in sym_names


def test_split_god_nodes_sorted_desc_and_capped():
    nodes = [_fn("f.py", f"s{i}") for i in range(30)]
    degree = {f"s{i}": i for i in range(30)}
    out = cga.split_god_nodes({"nodes": nodes, "edges": []}, degree, top_n=5)
    syms = out["symbols"]
    assert len(syms) == 5
    assert [r["name"] for r in syms] == ["s29", "s28", "s27", "s26", "s25"]


# ═══════════════════════════════════════════════════════════════
# render_god_nodes_md
# ═══════════════════════════════════════════════════════════════

def test_render_contains_module_and_symbol_sections():
    graph = {
        "nodes": [_module("hub.py"), _fn("hub.py", "hub"),
                  _module("a.py"), _fn("a.py", "a")],
        "edges": [_call("a.py", "a", "hub")],
    }
    md = cga.render_god_nodes_md(graph)
    assert "Top symbols" in md
    assert "Top modules" in md
    assert "hub" in md


@pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")
def test_render_includes_communities_when_available():
    graph = _two_cluster_graph()
    communities = cga.detect_communities(graph)
    betweenness = cga.file_betweenness(graph)
    md = cga.render_god_nodes_md(graph, communities=communities, betweenness=betweenness)
    assert "Communities" in md
    assert "Bridge files" in md


def test_render_notes_missing_networkx(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    md = cga.render_god_nodes_md(_two_cluster_graph(), communities=None, betweenness=None)
    assert "networkx" in md.lower()
    assert "Top symbols" in md  # core report still renders
