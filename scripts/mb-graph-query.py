#!/usr/bin/env python3
"""Query Memory Bank code graph JSONL files."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from mb_graph_query_core import (
    EXIT_INVALID_INPUT,
    EXIT_MISSING_GRAPH,
    EXIT_NO_MATCH,
    EXIT_OK,
    error_payload,
    impact_payload,
    load_graph,
    neighbors_payload,
    print_json,
    tests_payload,
)
from mb_graph_query_render import markdown_explain, write_summary_files


def selector(args: argparse.Namespace) -> tuple[str | None, str | None]:
    symbol = getattr(args, "symbol", None)
    file_name = getattr(args, "file", None)
    if bool(symbol) == bool(file_name):
        raise ValueError("provide exactly one of --symbol or --file")
    return symbol, file_name


def add_common(parser: argparse.ArgumentParser, *, selector_required: bool = True) -> None:
    parser.add_argument("--graph", required=True, help="Path to .memory-bank/codebase/graph.json")
    parser.add_argument("--json", action="store_true", help="Emit JSON")
    if selector_required:
        group = parser.add_mutually_exclusive_group(required=False)
        group.add_argument("--symbol", help="Symbol name to query")
        group.add_argument("--file", help="File path to query")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Query Memory Bank graph.json JSONL files")
    sub = parser.add_subparsers(dest="command", required=True)

    for name in ("neighbors", "impact", "tests", "explain"):
        add_common(sub.add_parser(name))

    summary = sub.add_parser("summary")
    add_common(summary, selector_required=False)
    summary.add_argument(
        "--out-dir",
        required=True,
        help="Directory for GRAPH_SUMMARY.md, IMPACT_MAP.md, TEST_LINKS.md",
    )
    return parser


def run(args: argparse.Namespace) -> int:
    try:
        nodes, edges = load_graph(Path(args.graph))
    except FileNotFoundError as exc:
        print_json(error_payload("missing_graph", str(exc)))
        return EXIT_MISSING_GRAPH
    except ValueError as exc:
        print_json(error_payload("invalid_graph", str(exc)))
        return EXIT_INVALID_INPUT

    try:
        if args.command == "summary":
            written = write_summary_files(nodes, edges, Path(args.out_dir))
            payload = {"ok": True, "written": written, "nodes": len(nodes), "edges": len(edges)}
            if args.json:
                print_json(payload)
            else:
                print("\n".join(written))
            return EXIT_OK

        symbol, file_name = selector(args)
    except ValueError as exc:
        print_json(error_payload("invalid_input", str(exc)))
        return EXIT_INVALID_INPUT

    if args.command == "neighbors":
        payload = neighbors_payload(nodes, edges, symbol, file_name)
    elif args.command == "impact":
        payload = impact_payload(nodes, edges, symbol, file_name)
    elif args.command == "tests":
        payload = tests_payload(nodes, edges, symbol, file_name)
    elif args.command == "explain":
        payload = impact_payload(nodes, edges, symbol, file_name)
    else:
        print_json(error_payload("invalid_input", f"unknown command: {args.command}"))
        return EXIT_INVALID_INPUT

    if args.command == "explain" and not args.json:
        print(markdown_explain(payload))
    else:
        print_json(payload)
    return EXIT_OK if payload.get("ok") else EXIT_NO_MATCH


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
