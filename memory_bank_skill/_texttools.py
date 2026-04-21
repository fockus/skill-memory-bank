"""Reusable text transforms for installer and maintenance scripts."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from memory_bank_skill._io import atomic_write


def strip_between_markers(text: str, start_marker: str, end_marker: str) -> str:
    """Remove all lines between marker lines, preserving surrounding content."""
    inside = False
    kept: list[str] = []
    for line in text.splitlines():
        if start_marker in line:
            inside = True
            continue
        if inside and end_marker in line:
            inside = False
            continue
        if not inside:
            kept.append(line)
    return "\n".join(kept).strip()


def strip_after_marker(text: str, marker: str) -> str:
    """Remove marker and everything after it."""
    if marker not in text:
        return text.rstrip()
    return text[: text.index(marker)].rstrip()


def localize_language_text(
    text: str,
    *,
    rule_full: str,
    rule_short: str,
    comments_language: str,
    after_marker: str = "",
) -> str:
    """Rewrite only the managed language statements inside the target text."""
    prefix = ""
    target = text
    if after_marker and after_marker in text:
        prefix, rest = text.split(after_marker, 1)
        prefix = prefix + after_marker
        target = rest

    target = re.sub(
        r"1\. \*\*[^*]+\*\*: .+",
        f"1. **Language**: {rule_full}",
        target,
    )
    target = re.sub(
        r"> \*\*[^*]+\*\* — .+",
        f"> **Language** — {rule_short}",
        target,
    )
    target = target.replace("comments in English", f"comments in {comments_language}")
    target = target.replace("comments in Russian", f"comments in {comments_language}")
    return prefix + target


def localize_file(
    path: str | Path,
    *,
    rule_full: str,
    rule_short: str,
    comments_language: str,
    after_marker: str = "",
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    updated = localize_language_text(
        target.read_text(encoding="utf-8"),
        rule_full=rule_full,
        rule_short=rule_short,
        comments_language=comments_language,
        after_marker=after_marker,
    )
    atomic_write(target, updated, encoding="utf-8")
    return True


def _write_or_delete(path: Path, text: str, *, delete_if_empty: bool) -> bool:
    normalized = text.strip()
    if normalized:
        atomic_write(path, normalized + "\n", encoding="utf-8")
        return True
    if delete_if_empty and path.exists():
        path.unlink()
        return False
    atomic_write(path, "", encoding="utf-8")
    return False


def strip_between_markers_file(
    path: str | Path,
    *,
    start_marker: str,
    end_marker: str,
    delete_if_empty: bool = True,
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    stripped = strip_between_markers(target.read_text(encoding="utf-8"), start_marker, end_marker)
    return _write_or_delete(target, stripped, delete_if_empty=delete_if_empty)


def strip_after_marker_file(
    path: str | Path,
    *,
    marker: str,
    delete_if_empty: bool = True,
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    stripped = strip_after_marker(target.read_text(encoding="utf-8"), marker)
    return _write_or_delete(target, stripped, delete_if_empty=delete_if_empty)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared text tools for memory-bank-skill")
    sub = parser.add_subparsers(dest="command", required=True)

    localize = sub.add_parser("localize-file")
    localize.add_argument("--path", required=True)
    localize.add_argument("--rule-full", required=True)
    localize.add_argument("--rule-short", required=True)
    localize.add_argument("--comments-language", required=True)
    localize.add_argument("--after-marker", default="")

    strip_after = sub.add_parser("strip-after-marker")
    strip_after.add_argument("--path", required=True)
    strip_after.add_argument("--marker", required=True)
    strip_after.add_argument("--keep-empty", action="store_true")

    strip_between = sub.add_parser("strip-between-markers")
    strip_between.add_argument("--path", required=True)
    strip_between.add_argument("--start-marker", required=True)
    strip_between.add_argument("--end-marker", required=True)
    strip_between.add_argument("--keep-empty", action="store_true")

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "localize-file":
        localize_file(
            args.path,
            rule_full=args.rule_full,
            rule_short=args.rule_short,
            comments_language=args.comments_language,
            after_marker=args.after_marker,
        )
        return 0
    if args.command == "strip-after-marker":
        strip_after_marker_file(
            args.path,
            marker=args.marker,
            delete_if_empty=not args.keep_empty,
        )
        return 0
    if args.command == "strip-between-markers":
        strip_between_markers_file(
            args.path,
            start_marker=args.start_marker,
            end_marker=args.end_marker,
            delete_if_empty=not args.keep_empty,
        )
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
