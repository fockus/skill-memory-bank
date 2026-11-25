#!/usr/bin/env python3
"""Inspect, set up or refresh the optional project code index."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

if __name__ == "__main__":
    sys.dont_write_bytecode = True
    scripts = Path(__file__).resolve().parent
    sys.path.insert(0, str(scripts))
    from _mb_skill_python import ensure_skill_python

    ensure_skill_python(__file__)
    if (scripts.parent / "memory_bank_skill").is_dir():
        sys.path.insert(1, str(scripts.parent))

MODELS = ("qwen3", "perplexity")

def status(directory: Path, mb_path: Path | None, *, auto_refresh: bool = False) -> dict[str, str]:
    from mb_project_rag import InvalidSelection
    from mb_project_rag_corpus import NotWorktree, has_tracked_source, project_paths

    try:
        root, bank = project_paths(directory, mb_path, require_git=True)
        from mb_rag_refresh import published_status

        if result := published_status(root, bank, schedule=auto_refresh):
            return result
        if has_tracked_source(root, bank):
            return {"status": "unconfigured", "action": "memory-bank rag init"}
        return {"status": "not_applicable"}
    except NotWorktree:
        return {"status": "not_applicable"}
    except InvalidSelection as exc:
        return {"status": "broken", "reason": str(exc), "action": "memory-bank rag init"}
    except (OSError, RuntimeError, ValueError, ImportError, subprocess.SubprocessError) as exc:
        # Permissions, unsafe paths, an unavailable runtime, etc. are not a stale index.
        return {"status": "broken", "reason": str(exc)}


def _message(result: dict[str, str]) -> str:
    label = result["status"]
    text = {
        "unconfigured": "Optional local code index: choose qwen3 (QMD) or perplexity (ONNX Q4).",
        "ready": f"Use the {result.get('model')} project index for code search.",
        "stale": result.get("reason", "Tracked source changed since the index was built."),
        "broken": result.get("reason", "The project index is unavailable."),
        "not_applicable": "No Git worktree with tracked source to index.",
    }[label]
    action = result.get("action")
    return f"{label}: {text}" + (f" From the project, run: {action}" if action else "")


def main() -> int:
    parser = argparse.ArgumentParser(prog="memory-bank rag", description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    init = actions.add_parser("init", help="Download the selected model and build a project index")
    init.add_argument("--model", choices=MODELS, help="Choose a model without a prompt")
    update = actions.add_parser("update", help="Refresh the index using the configured model")
    inspect = actions.add_parser("status", help="Inspect the project index (read-only by default)")
    inspect.add_argument("--json", action="store_true", help="Emit machine-readable status")
    inspect.add_argument(
        "--auto-refresh", action="store_true", help="Schedule a bounded stale-index refresh"
    )
    for action in (init, update, inspect):
        action.add_argument("--project-root", type=Path, default=Path.cwd())
        action.add_argument(
            "--mb-path",
            type=Path,
            help="Override MB_PATH or the project's resolved Memory Bank location",
        )
    args = parser.parse_args()
    if args.action == "status":
        result = status(args.project_root, args.mb_path, auto_refresh=args.auto_refresh)
        print(json.dumps(result) if args.json else _message(result))
        return 0
    if args.action == "init" and args.model is None:
        if sys.stdin.isatty():
            prompt = (
                "Download qwen3 (QMD) or perplexity (0.6B ONNX Q4)? "
                "Type the model name, or press Enter to cancel: "
            )
            try:
                args.model = input(prompt).strip().lower()
            except (EOFError, KeyboardInterrupt):
                args.model = None
        if not args.model or args.model == "cancel":
            print("No model selected; nothing changed. Use --model qwen3 or --model perplexity.")
            return 0
        if args.model not in MODELS:
            parser.error("choose qwen3 or perplexity")

    if not args.project_root.is_dir():
        parser.error(f"project directory not found: {args.project_root}")
    try:
        import mb_project_rag
        from mb_project_rag_corpus import project_paths

        root, bank = project_paths(args.project_root, args.mb_path)
        if args.action == "init":
            mb_project_rag.setup(root, bank, args.model)
        else:
            mb_project_rag.update(root, bank)
    except Exception as exc:
        print(f"Project RAG {args.action} failed: {exc}", file=sys.stderr)
        return 1
    print(f"Project code index is ready for {root}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
