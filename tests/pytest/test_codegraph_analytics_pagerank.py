"""Tests for PageRank god-node ranking (REQ-005, REQ-006).

Contract additions to ``memory_bank_skill/codegraph_analytics`` (pure functions
over the graph dict ``{"nodes":[...], "edges":[...]}``):

  - compute_pagerank    → name-keyed PageRank score (alpha=0.85), rounded 4dp;
                          ``None`` when networkx is unavailable (graceful degrade)
  - split_god_nodes     → gains a ``pagerank`` per row when scores are supplied;
                          ranks by PageRank desc (degree secondary) when present
  - render_god_nodes_md → PageRank is the PRIMARY ranking column with networkx;
                          degree-only + install hint without it (scenario 5)

networkx is OPTIONAL: PageRank tests require it (``--extra codegraph`` in CI);
the no-networkx degrade path is asserted via monkeypatch and runs everywhere.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import codegraph_analytics as cga  # noqa: E402

requires_nx = pytest.mark.skipif(not cga.HAS_NETWORKX, reason="networkx not installed")


# ═══════════════════════════════════════════════════════════════
# Helpers (mirror test_codegraph_analytics.py builders)
# ═══════════════════════════════════════════════════════════════


def _module(file: str) -> dict:
    return {"kind": "module", "name": file, "file": file, "line": 1}


def _fn(file: str, name: str, line: int = 1) -> dict:
    return {"kind": "function", "name": name, "file": file, "line": line}


def _call(src_file: str, src_fn: str, dst: str) -> dict:
    return {"src": f"{src_file}:{src_fn}", "dst": dst, "kind": "call"}


def _transitive_authority_graph() -> dict:
    """A central ``core`` that everything depends on transitively.

    Shape (caller -> callee):
        h1..h5 -> mid                            (mid: 5 incoming hubs)
        mid    -> core                           (core inherits mid's authority)
        p1..p3 -> leaf                            (leaf: 3 direct low-authority callers)

    ``leaf`` has a high RAW in-degree (3 callers), but its callers are themselves
    authority-less leaves. ``core`` has in-degree 1, yet that one caller (``mid``)
    funnels the authority of five hubs into it — so PageRank ranks
    ``core`` above ``leaf``: transitive importance beats a high-degree leaf.
    """
    hubs = ("h1", "h2", "h3", "h4", "h5")
    peers = ("p1", "p2", "p3")
    files = (*hubs, *peers, "mid", "core", "leaf")
    nodes = []
    for f in files:
        nodes.append(_module(f"{f}.py"))
        nodes.append(_fn(f"{f}.py", f))
    edges = [_call(f"{h}.py", h, "mid") for h in hubs]
    edges.append(_call("mid.py", "mid", "core"))
    edges += [_call(f"{p}.py", p, "leaf") for p in peers]
    return {"nodes": nodes, "edges": edges}


# ═══════════════════════════════════════════════════════════════
# compute_pagerank
# ═══════════════════════════════════════════════════════════════


def test_compute_pagerank_none_without_networkx(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    assert cga.compute_pagerank(_transitive_authority_graph()) is None


@requires_nx
def test_compute_pagerank_empty_graph_is_empty():
    assert cga.compute_pagerank({"nodes": [], "edges": []}) == {}


@requires_nx
def test_compute_pagerank_transitive_node_beats_high_degree_leaf():
    pr = cga.compute_pagerank(_transitive_authority_graph())
    assert pr is not None
    # leaf has 4 incoming edges (highest raw in-degree); core has 1.
    # Transitive authority must still rank core above leaf.
    assert pr["core"] > pr["leaf"], pr


@requires_nx
def test_compute_pagerank_full_precision_scores():
    """Returned scores keep FULL precision — rounding is display-only.

    On large graphs the mean PR is ~1e-4, so 4dp rounding before sorting
    collapses almost every score to 0.0000/0.0001 and the ranking degenerates
    to the degree tie-break. The returned dict must therefore carry the
    unrounded float (issue 2).
    """
    pr = cga.compute_pagerank(_transitive_authority_graph())
    assert pr is not None
    # at least one score must retain precision finer than 4dp
    assert any(round(score, 4) != score for score in pr.values()), pr


@requires_nx
def test_compute_pagerank_normalized_sum_to_one():
    """Scores form a probability distribution: sum ≈ 1, none > 1 (issue 1)."""
    pr = cga.compute_pagerank(_transitive_authority_graph())
    assert pr is not None
    assert abs(sum(pr.values()) - 1.0) < 1e-6, sum(pr.values())
    assert all(score <= 1.0 for score in pr.values()), pr


@requires_nx
def test_compute_pagerank_homonyms_share_one_rank_node():
    """Same function name in two files → one rank node, scores still sum to ~1.

    Names are NOT unique across files; degree/_resolve_dst already name-match,
    so PageRank must collapse homonyms to a single identity rather than counting
    duplicates in ``n`` while deduping in the rank dict (issue 1).
    """
    nodes = [
        _module("a.py"),
        _fn("a.py", "dup"),
        _module("b.py"),
        _fn("b.py", "dup"),  # homonym in another file
        _module("c.py"),
        _fn("c.py", "caller"),
    ]
    edges = [_call("c.py", "caller", "dup")]
    graph = {"nodes": nodes, "edges": edges}
    pr = cga.compute_pagerank(graph)
    assert pr is not None
    # homonymous "dup" is a single rank node, normalization holds
    assert abs(sum(pr.values()) - 1.0) < 1e-6, sum(pr.values())
    assert all(score <= 1.0 for score in pr.values()), pr


@requires_nx
def test_compute_pagerank_qualified_dst_flows_to_exact_node():
    """A fully-qualified dst must route authority to its EXACT node, not a homonym.

    With import-aware binding (task 3) edges carry qualified dotted dsts like
    ``b.process``. Two definitions share the short name ``process``
    (``a.process`` / ``b.process``). A single-pass resolver that checks the
    suffix fallback (``dst.endswith('.process')``) before the exact match would
    bind ``dst='b.process'`` to the alphabetically-first ``a.process`` and
    misroute PageRank flow to the wrong homonym.

    Three callers funnel authority specifically into ``b.process``; ``a.process``
    has none. Exact resolution must therefore rank ``b.process`` strictly above
    ``a.process``.
    """
    nodes = [
        _module("a.py"),
        _fn("a.py", "a.process"),
        _module("b.py"),
        _fn("b.py", "b.process"),
        _module("c1.py"),
        _fn("c1.py", "c1"),
        _module("c2.py"),
        _fn("c2.py", "c2"),
        _module("c3.py"),
        _fn("c3.py", "c3"),
    ]
    # all callers target the qualified b.process — none target a.process
    edges = [_call(f"c{i}.py", f"c{i}", "b.process") for i in (1, 2, 3)]
    pr = cga.compute_pagerank({"nodes": nodes, "edges": edges})
    assert pr is not None
    assert pr["b.process"] > pr["a.process"], pr


@requires_nx
def test_compute_pagerank_deterministic_across_runs():
    graph = _transitive_authority_graph()
    first = cga.compute_pagerank(graph)
    second = cga.compute_pagerank(graph)
    assert first == second


# ═══════════════════════════════════════════════════════════════
# split_god_nodes — PageRank-aware ranking
# ═══════════════════════════════════════════════════════════════


@requires_nx
def test_split_god_nodes_ranks_by_pagerank_when_supplied():
    graph = _transitive_authority_graph()
    degree = cga.compute_degree(graph)
    pr = cga.compute_pagerank(graph)
    out = cga.split_god_nodes(graph, degree, pagerank=pr)
    sym_names = [r["name"] for r in out["symbols"]]
    # core (transitively important) ranks above leaf (high degree, low authority)
    assert sym_names.index("core") < sym_names.index("leaf")
    # every row carries its pagerank score for the primary column
    assert all("pagerank" in r for r in out["symbols"])


def test_split_god_nodes_ranks_on_unrounded_pagerank():
    """Sub-1e-4 PR difference still orders by true PR, not the degree tie-break.

    If split sorted on 4dp-rounded scores, two nodes whose PR differs below
    1e-4 (but above 1e-7) would tie and fall through to the degree key, flipping
    the order. Ranking must use the full-precision score (issue 2).
    """
    graph = {
        "nodes": [_fn("f.py", "hi"), _fn("f.py", "lo")],
        "edges": [],
    }
    # equal degree → without precise PR the tie-break is name ("hi" < "lo")
    degree = {"hi": 1, "lo": 1}
    pagerank = {"hi": 0.5000_2, "lo": 0.5000_9}  # diff 7e-5: below 1e-4, above 1e-7
    out = cga.split_god_nodes(graph, degree, pagerank=pagerank)
    sym_names = [r["name"] for r in out["symbols"]]
    # true PR says lo > hi, so lo must come first despite the degree/name tie
    assert sym_names == ["lo", "hi"], sym_names


def test_split_god_nodes_without_pagerank_falls_back_to_degree():
    graph = {
        "nodes": [_fn("f.py", f"s{i}") for i in range(5)],
        "edges": [],
    }
    degree = {f"s{i}": i for i in range(5)}
    out = cga.split_god_nodes(graph, degree, top_n=3)  # no pagerank kwarg
    assert [r["name"] for r in out["symbols"]] == ["s4", "s3", "s2"]


# ═══════════════════════════════════════════════════════════════
# render_god_nodes_md — PageRank primary, degree secondary
# ═══════════════════════════════════════════════════════════════


@requires_nx
def test_render_uses_pagerank_as_primary_column():
    graph = _transitive_authority_graph()
    pr = cga.compute_pagerank(graph)
    md = cga.render_god_nodes_md(graph, pagerank=pr)
    assert "PageRank" in md
    # degree is retained as a secondary column header
    assert "Degree" in md
    # symbols table lists core before leaf (PageRank order)
    assert md.index("`core`") < md.index("`leaf`")


def test_render_degree_only_with_install_hint_when_no_pagerank(monkeypatch):
    """Scenario 5: import networkx fails → degree ranking + one-line install hint."""
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    graph = _transitive_authority_graph()
    md = cga.render_god_nodes_md(graph, pagerank=None)
    assert "Top symbols" in md
    assert "Degree" in md
    # the PageRank *table column* is absent without networkx (degree-only headers)
    assert "| PageRank | Degree |" not in md
    assert "networkx" in md.lower()  # one-line install hint present


def test_render_god_nodes_md_deterministic(monkeypatch):
    """Two consecutive renders over the same graph are byte-identical (NFR-002)."""
    graph = _transitive_authority_graph()
    pr = cga.compute_pagerank(graph)  # None without networkx — still deterministic
    first = cga.render_god_nodes_md(graph, pagerank=pr)
    second = cga.render_god_nodes_md(graph, pagerank=pr)
    assert first == second


@requires_nx
def test_render_says_pagerank_not_personalized():
    """Honesty: the algorithm is plain PageRank — no 'Personalized' claim (issue 3)."""
    graph = _transitive_authority_graph()
    md = cga.render_god_nodes_md(graph, pagerank=cga.compute_pagerank(graph))
    assert "Personalized PageRank" not in md
    assert "PageRank" in md


def test_render_install_hint_says_pagerank_not_personalized(monkeypatch):
    """The degrade-path install hint also drops the 'Personalized' claim (issue 3)."""
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)
    graph = _transitive_authority_graph()
    md = cga.render_god_nodes_md(graph, pagerank=None)
    assert "Personalized PageRank" not in md
    assert "PageRank" in md


@requires_nx
def test_render_pagerank_column_uses_6dp_precision():
    """Display precision is 6dp so small scores stay distinguishable (issue 2)."""
    graph = _transitive_authority_graph()
    pr = cga.compute_pagerank(graph)
    md = cga.render_god_nodes_md(graph, pagerank=pr)
    # at least one PageRank cell shows 6 fractional digits (e.g. 0.123456)
    import re

    assert re.search(r"\| \d\.\d{6} \|", md), md


# ═══════════════════════════════════════════════════════════════
# Scenario 5 — subprocess degrade path (networkx ImportError)
# ═══════════════════════════════════════════════════════════════


def test_apply_degrades_to_install_hint_without_networkx(tmp_path):
    """End-to-end scenario 5: ``--apply`` with networkx unimportable.

    Runs ``mb-codegraph.py --apply`` in a fresh process whose import of
    ``networkx`` raises ImportError (a shim module earlier on ``sys.path``).
    The build must exit 0, write god-nodes.md with the one-line install hint,
    and NOT render a PageRank column (NFR-002 graceful degradation, REQ-005/006).
    """
    # Source tree to graph.
    src = tmp_path / "src"
    src.mkdir()
    (src / "mod.py").write_text(
        "def helper():\n    return 1\n\n\ndef caller():\n    return helper()\n",
        encoding="utf-8",
    )
    mb = tmp_path / ".memory-bank"
    mb.mkdir()

    # Shim that makes ``import networkx`` raise ImportError in the subprocess.
    shim_dir = tmp_path / "shim"
    shim_dir.mkdir()
    (shim_dir / "networkx.py").write_text(
        "raise ImportError('networkx disabled for scenario-5 test')\n",
        encoding="utf-8",
    )

    env = dict(os.environ)
    env["PYTHONPATH"] = os.pathsep.join(
        [str(shim_dir), str(REPO_ROOT), env.get("PYTHONPATH", "")]
    ).rstrip(os.pathsep)

    proc = subprocess.run(
        [
            sys.executable,
            str(REPO_ROOT / "scripts" / "mb-codegraph.py"),
            "--apply",
            str(mb),
            str(src),
        ],
        capture_output=True,
        text=True,
        env=env,
        cwd=str(tmp_path),
    )
    assert proc.returncode == 0, proc.stderr
    god_nodes = (mb / "codebase" / "god-nodes.md").read_text(encoding="utf-8")
    assert "networkx" in god_nodes.lower()  # install hint present
    assert "| PageRank | Degree |" not in god_nodes  # no PageRank column
