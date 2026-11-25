#!/usr/bin/env python3
"""Build a bounded GraphRAG-lite evidence pack for code-understanding tasks."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":  # re-exec under an interpreter that can import the package
    # Explicit: `python3 -P` / `-I` / PYTHONSAFEPATH do not put the script dir on sys.path.
    scripts = Path(__file__).resolve().parent
    sys.path.insert(0, str(scripts))
    from _mb_skill_python import ensure_skill_python

    ensure_skill_python(__file__)
    if (scripts.parent / "memory_bank_skill").is_dir():
        sys.path.insert(1, str(scripts.parent))

from mb_code_context_core import build_evidence
from mb_project_rag_corpus import project_paths


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build a Memory Bank GraphRAG-lite code context evidence pack"
    )
    parser.add_argument("--query", required=True)
    parser.add_argument("--search-query", help="Search phrasing; --query stays the original question")
    parser.add_argument("--source-only", action="store_true", help="Recommend non-test files, one hit per file")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--mb-path", help="Bank location (default: MB_PATH or PROJECT_ROOT/.memory-bank)")
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
    warning = None
    try:
        project_root, mb_path = project_paths(project_root, Path(args.mb_path) if args.mb_path else None)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        # Git/registry discovery is optional for local graph and text lookups.
        warning = f"Project discovery unavailable: {exc}; searching the supplied directory."
        mb_path = Path(args.mb_path or os.getenv("MB_PATH") or project_root / ".memory-bank").resolve()
    semantic_path = Path(args.semantic_candidates).resolve() if args.semantic_candidates else None
    mode = "semantic" if args.semantic_only else args.mode
    # I-133: best-effort bounded graph catch-up so the evidence pack is built on
    # a current graph; any failure degrades to the stale graph, never breaks.
    try:
        from memory_bank_skill.codegraph_catchup import maybe_catchup

        maybe_catchup(mb_path / "codebase" / "graph.json", project_root)
    except Exception:
        pass
    payload = build_evidence(
        query=args.query,
        search_query=args.search_query,
        source_only=args.source_only,
        project_root=project_root,
        mb_path=mb_path,
        mode=mode,
        semantic_candidates_path=semantic_path,
        semantic_provider=args.semantic_provider,
    )
    if warning:
        payload["warnings"].append(warning)
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
