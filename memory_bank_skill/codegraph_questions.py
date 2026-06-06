"""Deterministic "suggested questions" for the Memory Bank code graph.

Generated purely from the graph structure and the analytics layer (god-nodes,
bridge files, communities, co-change) — **no LLM, no IO, $0**. graphify produces
these with an LLM; we don't need to, because we already compute the signals.

Each question is a dict ``{kind, text, evidence, command?}``. Families are built
in a fixed order and each is internally sorted by evidence (descending) then text,
so output is fully deterministic.
"""

from __future__ import annotations

from collections import defaultdict
from typing import Any

from memory_bank_skill import codegraph_analytics as cga

_TOP_N = 12          # overall cap
_TOP_GOD = 5
_TOP_BRIDGE = 3
_TOP_COMMUNITY = 3
_TOP_COCHANGE = 4


def _god_node_questions(graph: dict[str, Any]) -> list[dict[str, Any]]:
    degree = cga.compute_degree(graph)
    split = cga.split_god_nodes(graph, degree)
    out: list[dict[str, Any]] = []
    for row in split["symbols"]:
        # Skip orphan symbols (edge target with no defining node) — noisy "?" suggestions.
        if row.get("kind") == "?" or row.get("file") in ("?", ""):
            continue
        out.append({
            "kind": "god_node",
            "text": (f"What depends on `{row['name']}` ({row['file']})? "
                     f"It has the highest fan-in/out (degree {row['degree']}) — "
                     f"a change here ripples widely."),
            "evidence": float(row["degree"]),
            "command": f"mb-graph-query.py impact {cga._short(row['name'])}",
        })
        if len(out) >= _TOP_GOD:
            break
    return out


def _bridge_questions(betweenness: dict[str, float] | None) -> list[dict[str, Any]]:
    if not betweenness:
        return []
    ranked = sorted(betweenness.items(), key=lambda kv: (-kv[1], kv[0]))
    ranked = [(f, s) for f, s in ranked if s > 0][:_TOP_BRIDGE]
    return [{
        "kind": "bridge",
        "text": (f"`{f}` is a bridge file (betweenness {s:.3f}) — what fragments if "
                 f"you refactor or remove it?"),
        "evidence": s,
    } for f, s in ranked]


def _community_questions(communities: dict[str, int] | None) -> list[dict[str, Any]]:
    if not communities:
        return []
    members: dict[int, list[str]] = defaultdict(list)
    for file_name, cid in communities.items():
        members[cid].append(file_name)
    out: list[dict[str, Any]] = []
    for cid in sorted(members, key=lambda c: (-len(members[c]), c)):
        files = sorted(members[cid])
        if len(files) < 2:
            continue
        sample = ", ".join(files[:3]) + (" …" if len(files) > 3 else "")
        out.append({
            "kind": "community",
            "text": (f"Cluster {cid} ({len(files)} files: {sample}) — is this one "
                     f"cohesive responsibility, or should it be split?"),
            "evidence": float(len(files)),
        })
        if len(out) >= _TOP_COMMUNITY:
            break
    return out


def _co_change_questions(graph: dict[str, Any]) -> list[dict[str, Any]]:
    cc = [(e["src"], e["dst"], float(e.get("weight", 0)))
          for e in graph["edges"] if e.get("kind") == "co_change"]
    if not cc:
        return []
    try:
        _, file_edges = cga.build_file_graph(graph)
    except Exception:  # noqa: BLE001 — analytics is best-effort here
        file_edges = set()
    out: list[dict[str, Any]] = []
    for a, b, w in sorted(cc, key=lambda t: (-t[2], t[0], t[1]))[:_TOP_COCHANGE]:
        linked = frozenset((a, b)) in file_edges
        note = ("and are structurally linked too" if linked
                else "but have no import/call link between them")
        out.append({
            "kind": "co_change",
            "text": (f"`{a}` & `{b}` change together ({int(w)} commits) {note} — "
                     f"is that coupling intended?"),
            "evidence": w,
        })
    return out


def suggest_questions(
    graph: dict[str, Any],
    *,
    communities: dict[str, int] | None = None,
    betweenness: dict[str, float] | None = None,
    top_n: int = _TOP_N,
) -> list[dict[str, Any]]:
    """Return deterministic exploration questions derived from the graph + analytics."""
    questions: list[dict[str, Any]] = []
    questions += _god_node_questions(graph)
    questions += _bridge_questions(betweenness)
    questions += _community_questions(communities)
    questions += _co_change_questions(graph)
    return questions[:top_n]


def render_questions_md(questions: list[dict[str, Any]]) -> str:
    """Render the suggested-questions markdown section for ``god-nodes.md``."""
    lines = [
        "## Suggested questions",
        "",
        "_Auto-generated from the graph structure — starting points for exploring "
        "this codebase._",
        "",
    ]
    if not questions:
        lines.append("_Not enough graph signal yet (run `/mb graph --apply` first)._")
        return "\n".join(lines)
    for i, q in enumerate(questions, 1):
        lines.append(f"{i}. {q['text']}")
        if q.get("command"):
            lines.append(f"   ↳ `{q['command']}`")
    return "\n".join(lines)
