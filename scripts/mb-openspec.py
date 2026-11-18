#!/usr/bin/env python3
"""OpenSpec <-> Memory Bank round-trip adapter (CLI).

Usage:
    mb-openspec.py import <change_dir> [--as <topic>] [--mb <bank>] [--normalize]
    mb-openspec.py list   [--all] [--openspec <root>] [--mb <bank>]
    mb-openspec.py status <topic> [--mb <bank>]
    mb-openspec.py sync   [<topic>] [--take openspec|bank] [--mb <bank>] [--normalize]
    mb-openspec.py export <topic> [--write] [--allow-delete] [--mb <bank>]
    mb-openspec.py export <topic> --new [--id <id>] [--cap <cap>] [--openspec <root>]
                          [--write] [--mb <bank>]

``import``/``sync`` write only the bank (REQ-003, NFR-002): the first import
renders the triple, every later write is a per-unit three-way merge against the
committed ``specs/<topic>/openspec-sync.json`` sidecar (AGR-105). Only
``export --write`` writes OpenSpec, and only inside ``openspec/changes/<id>/``.
The logic lives in the ``mb_openspec_*`` modules; this file parses arguments,
prints results, and owns the one writer seam (``atomic_write``).

Exit codes:
    0 — command succeeded (an export dry-run included)
    1 — change dir / bank / topic not found, a guard refused, OpenSpec moved
        since the last sync (export), or a sync conflict (nothing written)
    2 — usage error
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

if __name__ == "__main__":  # re-exec under an interpreter that can import the package
    # Explicit: `python3 -P` / `-I` / PYTHONSAFEPATH do not put the script dir on sys.path.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _mb_skill_python import ensure_skill_python

    ensure_skill_python(__file__)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mb_openspec_bank as bank_io  # noqa: E402
import mb_openspec_export as export_ops  # noqa: E402
import mb_openspec_export_new as export_new  # noqa: E402
import mb_openspec_listing as listing  # noqa: E402
import mb_openspec_ops as ops  # noqa: E402
from mb_openspec_merge import TAKE_CHOICES  # noqa: E402
from mb_openspec_parse import compute_source_hash  # noqa: E402

try:
    from memory_bank_skill._io import atomic_write
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill._io import atomic_write

__all__ = ["compute_source_hash", "run_import", "run_list", "run_status", "run_sync"]

_parse_frontmatter = bank_io.parse_frontmatter
_orphan_backlog_marker = bank_io.orphan_backlog_marker
run_list = listing.run_list
run_status = listing.run_status


def _write(path: Path, content: str) -> None:
    atomic_write(path, content)  # looked up at call time: tests patch this module's name


def _append_orphans_to_backlog(
    mb_path: Path, topic: str, lines: list[str], source_hash: str
) -> None:
    bank_io.append_orphans_to_backlog(mb_path, topic, lines, source_hash, write=_write)


def run_import(
    *, change_dir: Path, mb_path: Path, topic: str | None, normalize: bool = False
) -> dict[str, object]:
    with bank_io.bank_lock(Path(mb_path)):  # one OpenSpec bank write at a time
        return ops.run_import(
            change_dir=change_dir, mb_path=mb_path, topic=topic, normalize=normalize, write=_write
        )


def run_sync(
    *, mb_path: Path, topic: str | None, normalize: bool = False, take: str | None = None
) -> list[dict[str, object]]:
    with bank_io.bank_lock(Path(mb_path)):
        return ops.run_sync(
            mb_path=mb_path, topic=topic, normalize=normalize, take=take, write=_write
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mb-openspec.py", description="OpenSpec <-> Memory Bank round-trip adapter"
    )
    sub = parser.add_subparsers(dest="action", required=True)
    normalize_help = (
        "Fill LLM text slots (EARS rewrite/missing scenario/Covers), cached by source hash"
    )

    imp = sub.add_parser("import", help="Import one OpenSpec change into a Memory Bank spec triple")
    imp.add_argument("change_dir", help="Path to openspec/changes/<id>/")
    imp.add_argument(
        "--as", dest="topic", default=None, help="Target spec topic (default: change-id slug)"
    )
    imp.add_argument("--normalize", action="store_true", help=normalize_help)

    lst = sub.add_parser("list", help="List OpenSpec changes and their import status")
    lst.add_argument(
        "--all", dest="include_all", action="store_true", help="Include archived changes"
    )
    lst.add_argument(
        "--openspec", dest="openspec_root", default=".", help="Path containing openspec/"
    )

    st = sub.add_parser("status", help="Import status of one previously-imported topic")
    st.add_argument("topic", help="Target spec topic under specs/<topic>/")

    sy = sub.add_parser("sync", help="Three-way sync of OpenSpec changes into the bank")
    sy.add_argument("topic", nargs="?", default=None, help="Spec topic (default: every topic)")
    sy.add_argument(
        "--take", choices=TAKE_CHOICES, default=None, help="Resolve conflicts to one side"
    )
    sy.add_argument("--normalize", action="store_true", help=normalize_help)

    ex = sub.add_parser("export", help="Write bank changes back to the OpenSpec change (dry-run)")
    ex.add_argument("topic", help="Spec topic under specs/<topic>/")
    ex.add_argument("--write", action="store_true", help="Apply instead of printing the diff")
    ex.add_argument("--allow-delete", action="store_true", help="Also delete removed units")
    ex.add_argument("--new", action="store_true", help="Create a new change from a bank spec")
    ex.add_argument(
        "--id", dest="change_id", default=None, help="--new: change id (default: topic)"
    )
    ex.add_argument("--cap", default=None, help="--new: capability (default: topic)")
    ex.add_argument("--openspec", dest="openspec_root", default=None, help="--new: project root")

    for p in (imp, lst, st, sy, ex):
        p.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")
    return parser


def _joined(value: object) -> str:
    return ", ".join(str(v) for v in value) if isinstance(value, list) else ""


def _print_conflicts(r: dict[str, object]) -> None:
    topic = r["topic"]
    print(
        f"{topic}: [conflict] both sides changed these units since the last sync; nothing "
        f"written. Edit one side until they match, or run `sync {topic} --take openspec|bank`.",
        file=sys.stderr,
    )
    conflicts = r["conflicts"]
    assert isinstance(conflicts, list)
    for c in conflicts:
        print(f"  {c.key}\n    openspec: {c.openspec or '(deleted)'}", file=sys.stderr)
        print(f"    bank:     {c.bank or '(deleted)'}", file=sys.stderr)


def _print_sync_results(results: list[dict[str, object]]) -> int:
    """One line per topic; exit 1 when a conflict or an error left a topic unsynced."""
    rc = 0
    for r in results:
        action, topic = r["action"], r["topic"]
        if action == "conflict":
            rc = 1
            _print_conflicts(r)
            continue
        if action == "error":
            rc = 1
            print(f"{topic}: [error] {r['reason']}", file=sys.stderr)
            continue
        if action == "held":
            print(f"{topic}: held, nothing written (another topic has a conflict or an error)")
            continue
        if action == "up-to-date":
            line = f"{topic}: up to date"
        else:
            taken = _joined(r.get("taken"))
            line = f"{topic}: {'baseline adopted' if r.get('adopted') else 'synced'}"
            line += f" (from OpenSpec: {taken})" if taken else ""
        print(line)
        if r.get("candidates"):
            print(
                f"{topic}: bank ahead of OpenSpec: {_joined(r['candidates'])}; run `export {topic}`"
            )
    return rc


def _main_export(args: argparse.Namespace) -> int:
    with bank_io.bank_lock(Path(args.mb_path)):
        return _export_locked(args)


def _export_locked(args: argparse.Namespace) -> int:
    mb_path = Path(args.mb_path)
    if not args.new and (args.change_id or args.cap or args.openspec_root):
        print("[error] --id/--cap/--openspec need --new", file=sys.stderr)
        return 2
    if args.new:
        root = Path(args.openspec_root) if args.openspec_root else None
        return export_new.run_export_new(
            mb_path=mb_path,
            topic=args.topic,
            change_id=args.change_id,
            cap=args.cap,
            openspec_root=root,
            apply=args.write,
            write=_write,
        )
    return export_ops.run_export(
        mb_path=mb_path,
        topic=args.topic,
        apply=args.write,
        allow_delete=args.allow_delete,
        write=_write,
    )


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])
    mb_path = Path(args.mb_path)
    try:
        if args.action == "import":
            result = run_import(
                change_dir=Path(args.change_dir),
                mb_path=mb_path,
                topic=args.topic,
                normalize=args.normalize,
            )
            if result.get("action") == "conflict":
                _print_conflicts(result)
                return 1
            source_hash = str(result["source_hash"])
            print(
                f"imported: {args.change_dir} -> specs/{result['topic']}/ (hash={source_hash[:12]})"
            )
            return 0
        if args.action == "list":
            entries = run_list(
                mb_path=mb_path,
                openspec_root=Path(args.openspec_root),
                include_all=args.include_all,
            )
            if not entries:
                print("no OpenSpec changes found")
            for entry in entries:
                topic_suffix = f"  (topic: {entry['topic']})" if entry["topic"] else ""
                print(f"{entry['change_id']}\t{entry['status']}{topic_suffix}")
            return 0
        if args.action == "status":
            result = run_status(mb_path=mb_path, topic=args.topic)
            print(
                f"topic: {result['topic']}\nsource: {result['source']}\nstatus: {result['status']}"
            )
            return 0
        if args.action == "sync":
            if args.take and args.topic is None:
                print(
                    "[error] --take needs a topic: sync <topic> --take openspec|bank",
                    file=sys.stderr,
                )
                return 2
            results = run_sync(
                mb_path=mb_path, topic=args.topic, normalize=args.normalize, take=args.take
            )
            if not results:
                print("no imported topics to sync")
                return 0
            return _print_sync_results(results)
        return _main_export(args)
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"[error] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
