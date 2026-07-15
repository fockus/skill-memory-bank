#!/usr/bin/env python3
"""OpenSpec → Memory Bank one-way import adapter (T1-T3 core + T5 re-import).

Reads an OpenSpec change directory (``proposal.md`` + optional ``design.md`` +
delta specs ``specs/*/spec.md`` + ``tasks.md``) and writes a Memory Bank spec
triple under ``<bank>/specs/<topic>/``. The OpenSpec tree is never written to
(REQ-003) — every write is asserted to live under the resolved bank path
(NFR-002).

Usage:
    mb-openspec.py import <change_dir> [--as <topic>] [--mb <bank>]

Re-import (T5): when ``specs/<topic>/`` already has a requirements.md +
tasks.md from a prior import, they are read (read-only) and passed to
``convert()`` as ``prior_triple`` so REQ-NNN anchors are reused/re-anchored
(D-06, REQ-016/018) instead of renumbered by position, and
``merge_task_state()`` preserves `/mb work` check-state by task text
(REQ-016); any task that vanished from the source is appended to
``backlog.md`` instead of being silently dropped (REQ-017).

``list``/``sync``/``status`` (T4) and ``--normalize`` (T6) are deliberately
left as seams — see design.md.

Exit codes:
    0 — import succeeded
    1 — change dir / bank not found, or a write-guard violation
    2 — usage error
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mb_openspec_convert import convert, merge_task_state
from mb_openspec_parse import parse_change

try:
    from memory_bank_skill._io import atomic_write
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill._io import atomic_write


def _slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "change"


def _assert_within(base: Path, target: Path) -> None:
    """Hard guard (REQ-003, NFR-002): refuse to write outside ``base``."""
    base_r = base.resolve()
    target_r = target.resolve()
    try:
        target_r.relative_to(base_r)
    except ValueError as exc:
        raise RuntimeError(f"refusing to write outside {base_r}: {target_r}") from exc


def _inject_frontmatter(requirements_md: str, source: str, source_hash: str) -> str:
    """Record the source change path + content hash (REQ-014)."""
    frontmatter = f"---\nopenspec_source: {source}\nopenspec_hash: {source_hash}\n---\n\n"
    return frontmatter + requirements_md


def _read_prior_triple(spec_dir: Path) -> tuple[str, str, str] | None:
    """Read a previously-written spec triple for re-import (read-only, T5).

    ``None`` when this is a fresh import — a requirements.md/tasks.md pair
    must already exist under ``spec_dir`` for a re-import to engage.
    """
    req_path = spec_dir / "requirements.md"
    tasks_path = spec_dir / "tasks.md"
    if not req_path.is_file() or not tasks_path.is_file():
        return None
    design_path = spec_dir / "design.md"
    design_md = design_path.read_text(encoding="utf-8") if design_path.is_file() else ""
    return (
        req_path.read_text(encoding="utf-8"),
        design_md,
        tasks_path.read_text(encoding="utf-8"),
    )


def _append_orphans_to_backlog(
    mb_path: Path, topic: str, orphaned_task_lines: list[str], source_hash: str
) -> None:
    """REQ-017 — a previously-imported task that vanished from the OpenSpec
    source on re-import is never silently dropped; append it to
    ``backlog.md`` with a note instead of losing it."""
    backlog_path = mb_path / "backlog.md"
    _assert_within(mb_path, backlog_path)
    existing = backlog_path.read_text(encoding="utf-8") if backlog_path.is_file() else "# Backlog\n"
    if not existing.endswith("\n"):
        existing += "\n"
    note_lines = [
        "",
        f"## Orphaned OpenSpec tasks — {topic}",
        "",
        (
            f"_(previously imported into `specs/{topic}/tasks.md`; no longer present in "
            f"the OpenSpec source as of re-import hash `{source_hash[:12]}` — "
            "re-check before discarding.)_"
        ),
        "",
        *orphaned_task_lines,
        "",
    ]
    atomic_write(backlog_path, existing + "\n".join(note_lines))


def run_import(*, change_dir: Path, mb_path: Path, topic: str | None) -> dict[str, object]:
    """Parse + convert + write one OpenSpec change into a Memory Bank spec triple.

    Re-import (T5): when ``specs/<topic>/`` already carries a triple from a
    prior import, it is read (read-only) and passed to ``convert()`` as
    ``prior_triple`` so REQ-NNN anchors are reused/re-anchored rather than
    renumbered by document position (D-06, REQ-016/018); ``merge_task_state``
    then preserves `/mb work` check-state by task text (REQ-016), and any
    task no longer present in the source is appended to ``backlog.md``
    instead of being silently dropped (REQ-017).
    """
    change_dir = Path(change_dir)
    mb_path = Path(mb_path)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec change dir not found: {change_dir}")
    if not mb_path.is_dir():
        raise FileNotFoundError(f"memory bank not found: {mb_path}")

    ch = parse_change(change_dir)

    resolved_topic = topic or _slugify(ch.change_id)
    spec_dir = mb_path / "specs" / resolved_topic
    _assert_within(mb_path, spec_dir)

    prior_triple = _read_prior_triple(spec_dir)

    requirements_md, design_md, tasks_md = convert(
        ch, prior_triple=prior_triple, topic=resolved_topic, mb_path=mb_path
    )

    orphaned_task_lines: list[str] = []
    if prior_triple is not None:
        tasks_md, orphaned_task_lines = merge_task_state(tasks_md, prior_triple[2])

    requirements_md = _inject_frontmatter(requirements_md, str(change_dir), ch.source_hash)

    for name, content in (
        ("requirements.md", requirements_md),
        ("design.md", design_md),
        ("tasks.md", tasks_md),
    ):
        dest = spec_dir / name
        _assert_within(mb_path, dest)
        atomic_write(dest, content)

    if orphaned_task_lines:
        _append_orphans_to_backlog(mb_path, resolved_topic, orphaned_task_lines, ch.source_hash)

    return {
        "topic": resolved_topic,
        "spec_dir": str(spec_dir),
        "source_hash": ch.source_hash,
        "reimport": prior_triple is not None,
        "orphaned_tasks": len(orphaned_task_lines),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mb-openspec.py", description="OpenSpec -> Memory Bank one-way import adapter"
    )
    sub = parser.add_subparsers(dest="action", required=True)

    imp = sub.add_parser("import", help="Import one OpenSpec change into a Memory Bank spec triple")
    imp.add_argument("change_dir", help="Path to openspec/changes/<id>/")
    imp.add_argument(
        "--as", dest="topic", default=None, help="Target spec topic (default: change-id slug)"
    )
    imp.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")

    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])

    if args.action == "import":
        try:
            result = run_import(
                change_dir=Path(args.change_dir),
                mb_path=Path(args.mb_path),
                topic=args.topic,
            )
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"[error] {exc}", file=sys.stderr)
            return 1
        print(
            f"imported: {args.change_dir} -> specs/{result['topic']}/ "
            f"(hash={result['source_hash'][:12]})"
        )
        return 0

    print(f"[error] unknown action: {args.action}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
