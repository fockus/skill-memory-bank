#!/usr/bin/env python3
"""`/mb wiki` engine — deterministic prep for the LLM wiki + surprising-connections pass.

The LLM work itself runs as **host subagents** (Haiku per community, Sonnet for
cross-cutting links) orchestrated by `commands/wiki.md`. This script provides the
deterministic, testable verbs the command calls:

    plan          enumerate the planned subagent dispatch (dry-run; no LLM)
    packs         write per-community evidence packs → <mb>/codebase/.wiki-packs.json
    write-article write one community article (stdin → wiki/community-N.md)
    merge-edges   validate + merge Sonnet's semantic edges into graph.json (idempotent)
    index         write wiki/index.md from the packs file

Communities need networkx (via codegraph_analytics); without it, `plan` reports 0
communities and suggests installing it (graceful degradation).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill import codegraph_analytics as cga
    from memory_bank_skill import wiki_evidence as we
    from memory_bank_skill import wiki_store as wstore
    from memory_bank_skill.codegraph_loader import load_graph
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill import codegraph_analytics as cga
    from memory_bank_skill import wiki_evidence as we
    from memory_bank_skill import wiki_store as wstore
    from memory_bank_skill.codegraph_loader import load_graph

PACKS_FILE = ".wiki-packs.json"
EXIT_OK = 0
EXIT_MISSING_GRAPH = 3


def plan_dispatch(packs: list[dict[str, Any]]) -> dict[str, Any]:
    """Deterministic description of the subagent dispatch (no LLM is invoked)."""
    return {
        "communities": len(packs),
        "haiku_dispatches": [
            {"community_id": p["community_id"], "files": len(p.get("files", []))}
            for p in packs
        ],
        "sonnet_dispatches": 1 if packs else 0,
        "models": {"author": "haiku", "synthesizer": "sonnet"},
    }


def _prep(mb_path: str, src_root: str) -> tuple[Path, list[dict[str, Any]], dict | None]:
    mb = Path(mb_path)
    nodes, edges = load_graph(mb / "codebase" / "graph.json")
    communities = cga.detect_communities({"nodes": nodes, "edges": edges})
    packs = we.build_community_packs(nodes, edges, communities, src_root) if communities else []
    return mb, packs, communities


def _packs_path(mb: Path) -> Path:
    return mb / "codebase" / PACKS_FILE


def _cmd_plan(args: argparse.Namespace) -> int:
    mb, packs, communities = _prep(args.mb_path, args.src_root)
    plan = plan_dispatch(packs)
    if communities is None:
        plan["warning"] = "networkx not installed — no communities; run `pip3 install networkx`"
    if args.json:
        print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"communities={plan['communities']}")
        print(f"haiku_dispatches={len(plan['haiku_dispatches'])}")
        print(f"sonnet_dispatches={plan['sonnet_dispatches']}")
        if "warning" in plan:
            print(f"[warn] {plan['warning']}", file=sys.stderr)
    return EXIT_OK


def _cmd_packs(args: argparse.Namespace) -> int:
    mb, packs, _ = _prep(args.mb_path, args.src_root)
    out = _packs_path(mb)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(packs, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"packs={len(packs)} -> {out}")
    return EXIT_OK


def _cmd_write_article(args: argparse.Namespace) -> int:
    md = Path(args.file).read_text(encoding="utf-8") if args.file else sys.stdin.read()
    wiki_dir = Path(args.mb_path) / "codebase" / "wiki"
    path = wstore.write_article(wiki_dir, args.id, md)
    print(f"wrote {path}")
    return EXIT_OK


def _cmd_merge_edges(args: argparse.Namespace) -> int:
    raw = Path(args.edges).read_text(encoding="utf-8") if args.edges else sys.stdin.read()
    edges = wstore.validate_semantic_edges(raw)
    graph_path = Path(args.mb_path) / "codebase" / "graph.json"
    if not graph_path.is_file():
        print(f"[error] missing graph: {graph_path}", file=sys.stderr)
        return EXIT_MISSING_GRAPH
    added = wstore.merge_semantic_edges(graph_path, edges)
    print(f"semantic_edges_added={added}")
    return EXIT_OK


def _cmd_index(args: argparse.Namespace) -> int:
    mb = Path(args.mb_path)
    packs_path = _packs_path(mb)
    packs = json.loads(packs_path.read_text(encoding="utf-8")) if packs_path.is_file() else []
    idx = wstore.write_index(mb / "codebase" / "wiki", packs)
    print(f"wrote {idx}")
    return EXIT_OK


def _add_locator(sub: argparse.ArgumentParser) -> None:
    sub.add_argument("mb_path", nargs="?", default=".memory-bank")
    sub.add_argument("src_root", nargs="?", default=".")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Memory Bank wiki engine (deterministic prep)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_plan = sub.add_parser("plan", help="enumerate subagent dispatch (dry-run)")
    p_plan.add_argument("--json", action="store_true")
    _add_locator(p_plan)
    p_plan.set_defaults(func=_cmd_plan)

    p_packs = sub.add_parser("packs", help="write per-community evidence packs")
    _add_locator(p_packs)
    p_packs.set_defaults(func=_cmd_packs)

    p_article = sub.add_parser("write-article", help="write one community article (stdin)")
    p_article.add_argument("--id", type=int, required=True)
    p_article.add_argument("--file", default=None, help="read article md from file (else stdin)")
    p_article.add_argument("mb_path", nargs="?", default=".memory-bank")
    p_article.set_defaults(func=_cmd_write_article)

    p_merge = sub.add_parser("merge-edges", help="merge semantic edges into graph.json")
    p_merge.add_argument("--edges", default=None, help="read edges JSON from file (else stdin)")
    p_merge.add_argument("mb_path", nargs="?", default=".memory-bank")
    p_merge.set_defaults(func=_cmd_merge_edges)

    p_index = sub.add_parser("index", help="write wiki index.md from packs")
    p_index.add_argument("mb_path", nargs="?", default=".memory-bank")
    p_index.set_defaults(func=_cmd_index)

    args = parser.parse_args(argv[1:])
    try:
        return args.func(args)
    except FileNotFoundError as exc:
        print(f"[error] missing graph: {exc} (run /mb graph --apply)", file=sys.stderr)
        return EXIT_MISSING_GRAPH


if __name__ == "__main__":
    sys.exit(main(sys.argv))
