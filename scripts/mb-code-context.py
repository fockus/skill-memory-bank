#!/usr/bin/env python3
"""Build a bounded GraphRAG-lite evidence pack for code-understanding tasks."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from mb_code_context_core import build_evidence


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build a Memory Bank GraphRAG-lite code context evidence pack"
    )
    parser.add_argument("--query", required=True)
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--mb-path", default=".memory-bank")
    parser.add_argument("--mode", choices=["auto", "graph", "semantic"], default="auto")
    parser.add_argument(
        "--semantic-only",
        action="store_true",
        help="Alias for --mode semantic; bypass graph/text fallback by explicit request",
    )
    parser.add_argument("--semantic-provider", choices=["none", "unavailable"], default="none")
    parser.add_argument(
        "--semantic-candidates", help="JSON file with {'candidates': [{'file': ...}]}"
    )
    parser.add_argument("--json", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])
    project_root = Path(args.project_root).resolve()
    mb_path = Path(args.mb_path).resolve()
    semantic_path = Path(args.semantic_candidates).resolve() if args.semantic_candidates else None
    mode = "semantic" if args.semantic_only else args.mode
    payload = build_evidence(
        query=args.query,
        project_root=project_root,
        mb_path=mb_path,
        mode=mode,
        semantic_candidates_path=semantic_path,
        semantic_provider=args.semantic_provider,
    )
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"code_context: {args.query}")
        for file_name in payload["recommended_next_reads"]:
            print(f"- {file_name}")
        for warning in payload["warnings"]:
            print(f"WARN: {warning}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
