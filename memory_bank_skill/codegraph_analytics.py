"""Deterministic graph analytics for the Memory Bank code graph.

Pure functions over the graph dict produced by ``mb-codegraph.build_graph``
(``{"nodes": [...], "edges": [...]}``) — no I/O, no global state.

Ported from graphify's analytics, kept within Memory Bank's contract:
**deterministic, $0, no *required* dependency**. ``networkx`` is OPTIONAL — when
absent, community/betweenness functions return ``None`` and the report degrades
gracefully (mirrors the tree-sitter pattern in ``mb-codegraph.py``).

Two levels:
  * file-level graph (module clusters) → communities + cohesion + betweenness
  * symbol-level degree → god-node ranking split into modules vs symbols

The file-level graph resolves ``call``/``inherit``/``import`` edges to the file
that DEFINES the referenced symbol (best-effort, name-based — same limitation as
the rest of the code graph). Names defined in more than ``_MAX_DEFINING_FILES``
files are too ambiguous to attribute and are skipped to avoid hairball edges.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any

try:  # optional dependency — graceful degradation when absent
    import networkx as nx
    HAS_NETWORKX = True
except ImportError:  # pragma: no cover - exercised via monkeypatch in tests
    nx = None  # type: ignore[assignment]
    HAS_NETWORKX = False

_MAX_DEFINING_FILES = 8   # names defined in more files than this are too ambiguous
_SEED = 42                # determinism for Louvain + betweenness sampling
_TOP_GOD_NODES = 20
_TOP_COMMUNITIES = 15
_TOP_BRIDGES = 10
_BETWEENNESS_SAMPLE_THRESHOLD = 500  # approximate betweenness above this many nodes


def _short(name: str) -> str:
    """Last dotted segment without call parens: ``a.b.C`` → ``C``, ``m.f()`` → ``f``."""
    seg = name.split(".")[-1]
    return seg[:-2] if seg.endswith("()") else seg


def _src_file(edge: dict[str, Any]) -> str:
    """File portion of an edge ``src`` (``file`` or ``file:qualname``)."""
    src = edge.get("src", "")
    return src.split(":")[0] if ":" in src else src


# ═══════════════════════════════════════════════════════════════
# Degree (symbol-level) — matches the legacy _compute_degree semantics
# ═══════════════════════════════════════════════════════════════

def compute_degree(graph: dict[str, Any]) -> dict[str, int]:
    """Return ``{node_name: in+out degree}`` using name/suffix matching.

    Out-degree is attributed to the edge source (last ``:`` segment); in-degree to
    the first node whose name (or short name) matches the edge target.
    """
    degree: dict[str, int] = {}
    node_names = {n["name"] for n in graph["nodes"]}
    for e in graph["edges"]:
        src_key = e["src"].split(":")[-1] if ":" in e["src"] else e["src"]
        degree[src_key] = degree.get(src_key, 0) + 1
        dst = e["dst"]
        for name in node_names:
            short = name.split(".")[-1]
            if dst in (name, short) or dst.endswith(f".{short}"):
                degree[name] = degree.get(name, 0) + 1
                break
    return degree


# ═══════════════════════════════════════════════════════════════
# File-level graph
# ═══════════════════════════════════════════════════════════════

def _defining_files(graph: dict[str, Any]) -> dict[str, set[str]]:
    """Map a symbol short-name → set of files that DEFINE a function/class with it."""
    idx: dict[str, set[str]] = defaultdict(set)
    for n in graph["nodes"]:
        if n.get("kind") in ("function", "class"):
            idx[_short(n["name"])].add(n.get("file", ""))
    return idx


def build_file_graph(graph: dict[str, Any]) -> tuple[set[str], set[frozenset]]:
    """Resolve symbol edges into an undirected file-coupling graph.

    Returns ``(files, edges)`` where ``files`` is every file with a node and
    ``edges`` is a set of ``frozenset({file_a, file_b})`` pairs (no self-loops).
    """
    files = {n["file"] for n in graph["nodes"] if n.get("file")}
    defs = _defining_files(graph)
    edges: set[frozenset] = set()
    for e in graph["edges"]:
        sf = _src_file(e)
        if sf not in files:
            continue
        targets = defs.get(_short(e["dst"]), set())
        if not targets or len(targets) > _MAX_DEFINING_FILES:
            continue
        for tf in targets:
            if tf and tf != sf:
                edges.add(frozenset((sf, tf)))
    return files, edges


def _nx_file_graph(graph: dict[str, Any]):
    files, edges = build_file_graph(graph)
    G = nx.Graph()
    G.add_nodes_from(files)
    G.add_edges_from(tuple(e) for e in edges)
    return G


# ═══════════════════════════════════════════════════════════════
# Communities (optional networkx)
# ═══════════════════════════════════════════════════════════════

def detect_communities(graph: dict[str, Any]) -> dict[str, int] | None:
    """File → community id (``0`` = largest). ``None`` when networkx is unavailable.

    Uses Louvain modularity (deterministic via ``seed``). Community ids are stable:
    sorted by size descending, then by the alphabetically-first member.
    """
    if not HAS_NETWORKX:
        return None
    files, _ = build_file_graph(graph)
    if not files:
        return {}
    G = _nx_file_graph(graph)
    communities = nx.community.louvain_communities(G, seed=_SEED)
    ordered = sorted(communities, key=lambda c: (-len(c), sorted(c)[0]))
    mapping: dict[str, int] = {}
    for cid, members in enumerate(ordered):
        for f in members:
            mapping[f] = cid
    return mapping


def file_cohesion(edges: set[frozenset], community_files: list[str]) -> float:
    """Ratio of actual intra-community file-edges to the maximum possible (∈ [0, 1])."""
    n = len(community_files)
    if n < 2:
        return 1.0
    member = set(community_files)
    internal = sum(1 for e in edges if e <= member)
    max_possible = n * (n - 1) / 2
    return internal / max_possible if max_possible else 0.0


def file_betweenness(graph: dict[str, Any]) -> dict[str, float] | None:
    """File → betweenness centrality. ``None`` when networkx is unavailable.

    Bridge files (high score) are refactoring/risk hotspots — removing them
    fragments the module graph. Large graphs use sampled (approximate) betweenness.
    """
    if not HAS_NETWORKX:
        return None
    files, _ = build_file_graph(graph)
    if not files:
        return {}
    G = _nx_file_graph(graph)
    n = G.number_of_nodes()
    k = min(_BETWEENNESS_SAMPLE_THRESHOLD, n) if n > _BETWEENNESS_SAMPLE_THRESHOLD else None
    return nx.betweenness_centrality(G, k=k, seed=_SEED, normalized=True)


# ═══════════════════════════════════════════════════════════════
# God-node ranking (symbol-level) — split modules vs symbols
# ═══════════════════════════════════════════════════════════════

def split_god_nodes(
    graph: dict[str, Any],
    degree: dict[str, int],
    top_n: int = _TOP_GOD_NODES,
) -> dict[str, list[dict[str, Any]]]:
    """Rank nodes by degree, split into ``modules`` and ``symbols`` (functions/classes).

    Without the split, module-level hubs (test files accumulate every import/call)
    drown the real abstractions. Separating them surfaces both. Sorted by degree
    descending, ties broken by name for determinism; each list capped at ``top_n``.
    """
    lookup = {n["name"]: n for n in graph["nodes"]}
    ranked = sorted(degree.items(), key=lambda kv: (-kv[1], kv[0]))
    modules: list[dict[str, Any]] = []
    symbols: list[dict[str, Any]] = []
    for name, deg in ranked:
        node = lookup.get(name)
        kind = node.get("kind") if node else None
        row = {
            "name": name,
            "kind": kind or "?",
            "file": node.get("file", "?") if node else "?",
            "line": node.get("line", "?") if node else "?",
            "degree": deg,
        }
        bucket = modules if kind == "module" else symbols
        if len(bucket) < top_n:
            bucket.append(row)
    return {"modules": modules, "symbols": symbols}


# ═══════════════════════════════════════════════════════════════
# Markdown report
# ═══════════════════════════════════════════════════════════════

def _md_table(header: list[str], rows: list[list[str]]) -> list[str]:
    out = ["| " + " | ".join(header) + " |",
           "|" + "|".join("---" for _ in header) + "|"]
    out.extend("| " + " | ".join(str(c) for c in r) + " |" for r in rows)
    return out


def _community_rows(
    graph: dict[str, Any],
    communities: dict[str, int],
) -> list[list[str]]:
    _, fedges = build_file_graph(graph)
    members: dict[int, list[str]] = defaultdict(list)
    for f, cid in communities.items():
        members[cid].append(f)
    rows: list[list[str]] = []
    for cid in sorted(members, key=lambda c: (-len(members[c]), c))[:_TOP_COMMUNITIES]:
        files = members[cid]
        cohesion = file_cohesion(fedges, files)
        sample = ", ".join(sorted(files)[:3]) + (" …" if len(files) > 3 else "")
        rows.append([cid, len(files), f"{cohesion:.2f}", sample])
    return rows


def render_god_nodes_md(
    graph: dict[str, Any],
    communities: dict[str, int] | None = None,
    betweenness: dict[str, float] | None = None,
) -> str:
    """Render the god-nodes + analytics markdown report.

    Always includes Top modules / Top symbols. Adds Communities + Bridge files when
    ``communities`` is provided; otherwise notes that networkx unlocks them.
    """
    degree = compute_degree(graph)
    split = split_god_nodes(graph, degree)

    lines = [
        "# God nodes & code-graph analytics",
        "",
        "Automatically generated by `mb-codegraph.py`. High-degree nodes are "
        "decomposition candidates; bridge files and low-cohesion communities are "
        "refactoring hotspots.",
        "",
        "## Top symbols (functions / classes)",
        "",
    ]
    lines += _md_table(
        ["#", "Name", "Kind", "File:Line", "Degree"],
        [[i, f"`{r['name']}`", r["kind"], f"{r['file']}:{r['line']}", r["degree"]]
         for i, r in enumerate(split["symbols"], 1)],
    )
    lines += ["", "## Top modules (files)", ""]
    lines += _md_table(
        ["#", "Module", "Degree"],
        [[i, f"`{r['name']}`", r["degree"]] for i, r in enumerate(split["modules"], 1)],
    )

    if communities is not None:
        lines += ["", "## Communities (auto-detected module clusters)", "",
                  "_Cohesion = intra-cluster file-edge density (1.0 = fully coupled)._",
                  ""]
        lines += _md_table(
            ["Community", "Files", "Cohesion", "Sample"],
            _community_rows(graph, communities),
        )
        if betweenness:
            top = sorted(betweenness.items(), key=lambda kv: (-kv[1], kv[0]))
            top = [(f, s) for f, s in top if s > 0][:_TOP_BRIDGES]
            lines += ["", "## Bridge files (highest betweenness)", "",
                      "_Removing these fragments the module graph — refactor with care._",
                      ""]
            lines += _md_table(
                ["#", "File", "Betweenness"],
                [[i, f"`{f}`", f"{s:.3f}"] for i, (f, s) in enumerate(top, 1)],
            )
    else:
        lines += ["", "_Install `networkx` (optional) to unlock community detection "
                  "and betweenness (bridge) analysis._"]

    lines.append("")
    return "\n".join(lines)
