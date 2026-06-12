"""PageRank ranking for the Memory Bank code graph (symbol-level).

Split out of ``codegraph_analytics`` to keep that module under the project's
400-line gate. Pure functions over the graph dict
(``{"nodes": [...], "edges": [...]}``) — no I/O, no global state, **no optional
dependency**: this module is pure stdlib math.

The networkx gate (the documented analytics toggle, consistent with
communities/betweenness) lives in ONE place — the ``codegraph_analytics`` façade.
This module is always importable; callers that need graceful degradation check
``cga.HAS_NETWORKX`` before invoking it.

The score is computed with a pure-stdlib power iteration so the optional
``codegraph`` install stays light — no numpy/scipy. The result is deterministic
for a fixed graph (sorted nodes, sorted edge iteration, fixed iteration order,
no RNG), so two runs over the same ``graph.json`` produce byte-identical
god-nodes output (NFR-002). Scores keep FULL precision; rounding is display-only
(handled at render time).

Homonymous symbols (the same short name defined in more than one file) share a
single rank node — consistent with how degree/``_resolve_dst`` already name-match.
The rank distribution is therefore normalized over UNIQUE names (∑ score ≈ 1).
"""

from __future__ import annotations

from typing import Any

_PAGERANK_ALPHA = 0.85  # standard damping factor; deterministic for a fixed graph
_PAGERANK_MAX_ITER = 100  # networkx default; convergence well before this
_PAGERANK_TOL = 1.0e-6  # networkx default L1 convergence tolerance
# Edge kinds that carry directional caller→callee authority for PageRank.
_RANK_EDGE_KINDS = ("call", "import", "inherit")


def _resolve_dst(dst: str, sorted_names: list[str], name_set: frozenset[str]) -> str | None:
    """Resolve an edge target to a node name, exact match first (two-pass).

    Pass 1 — exact ``dst == name`` via the precomputed ``name_set`` (O(1), and
    deterministic since a qualified name resolves to itself). This guards against
    import-aware qualified dsts (``pkg.mod.func``): a homonymous short name must
    never shadow an exact hit. Pass 2 (only when no exact match) — the short-name
    / suffix fallback over the *sorted* list, so an ambiguous short name binds to
    the alphabetically-first definition deterministically. ``name_set`` removes
    the per-edge O(N) scan for the common exact-match case.
    """
    if dst in name_set:
        return dst
    for name in sorted_names:
        short = name.split(".")[-1]
        if dst == short or dst.endswith(f".{short}"):
            return name
    return None


def _resolved_edges(graph: dict[str, Any], sorted_names: list[str]) -> set[tuple[str, str]]:
    """Directed (caller, callee) symbol pairs from call/import/inherit edges."""
    directed: set[tuple[str, str]] = set()
    name_set = frozenset(sorted_names)
    for e in graph["edges"]:
        if e.get("kind") not in _RANK_EDGE_KINDS:
            continue
        src = e["src"]
        src_key = src.split(":")[-1] if ":" in src else src
        dst_name = _resolve_dst(e["dst"], sorted_names, name_set)
        if dst_name is None or dst_name == src_key:
            continue
        directed.add((src_key, dst_name))
    return directed


def _power_iteration_pagerank(
    nodes: list[str], edges: set[tuple[str, str]], alpha: float
) -> dict[str, float]:
    """Deterministic, dependency-free PageRank via power iteration.

    Equivalent to ``nx.pagerank`` (same alpha, dangling-mass redistribution and
    L1 tolerance) but pure stdlib — avoids pulling numpy/scipy into the optional
    ``codegraph`` install. ``nodes`` is the sorted set of UNIQUE names and edge
    iteration is sorted, so accumulation order is fixed and the result is
    byte-identical across runs / processes (NFR-002), independent of
    ``PYTHONHASHSEED``.
    """
    n = len(nodes)
    out_links: dict[str, list[str]] = {name: [] for name in nodes}
    for src, dst in sorted(edges):  # sorted → fixed float-accumulation order (NFR-002)
        if src in out_links:  # ignore edges from symbols with no node (defensive)
            out_links[src].append(dst)
    rank = {name: 1.0 / n for name in nodes}
    base = (1.0 - alpha) / n
    for _ in range(_PAGERANK_MAX_ITER):
        prev = rank
        nxt = {name: base for name in nodes}
        dangling = alpha * sum(prev[name] for name in nodes if not out_links[name]) / n
        for name in nodes:
            targets = out_links[name]
            if not targets:
                continue
            share = alpha * prev[name] / len(targets)
            for dst in targets:
                nxt[dst] += share
        for name in nodes:
            nxt[name] += dangling
        err = sum(abs(nxt[name] - prev[name]) for name in nodes)
        rank = nxt
        if err < n * _PAGERANK_TOL:
            break
    return rank


def compute_pagerank(graph: dict[str, Any]) -> dict[str, float]:
    """Symbol-level PageRank over the directed call/import/inherit graph.

    Edges run caller→callee (the source symbol depends on the target), so score
    flows toward foundational definitions: a node imported/called transitively by
    many hubs outranks a high-degree leaf whose callers are themselves trivial.

    Pure math, no gate: callers (``codegraph_analytics.compute_pagerank``) decide
    whether to call this based on ``HAS_NETWORKX``. Names are deduped to UNIQUE
    identities first (homonyms across files share one rank node, matching the
    name-based degree/edge resolution), so ``n == len(unique)`` and the returned
    scores form a normalized distribution (∑ ≈ 1, none > 1). FULL precision is
    preserved — rounding is display-only. Nodes/edges are sorted before iterating,
    so two runs over the same ``graph.json`` are byte-identical.
    """
    sorted_names = sorted({n["name"] for n in graph["nodes"]})
    if not sorted_names:
        return {}
    directed = _resolved_edges(graph, sorted_names)
    return _power_iteration_pagerank(sorted_names, directed, _PAGERANK_ALPHA)
