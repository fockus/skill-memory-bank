#!/usr/bin/env python3
"""Per-project response / code-comment language — overrides the global install choice.

The override is a managed block at the top of the project's AGENTS.md (read natively by Codex,
OpenCode, Pi, Cursor) and CLAUDE.md (Claude Code). Every host loads project instructions after
its global ones and the block says it overrides the global rule, so no host needs a config
lookup. At the top of the file it also survives Codex's project-doc size cap.

Usage:
  mb-language.py set <lang> [--comments <lang>] [--project DIR]   lang: en ru es pt zh
  mb-language.py clear|off [--project DIR]
  mb-language.py show [--project DIR]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# The bundle's own package first — an older memory_bank_skill installed elsewhere must not win.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from memory_bank_skill._io import atomic_write  # noqa: E402
from memory_bank_skill._texttools import LANGUAGE_NAMES, resolve_language_strings  # noqa: E402

START = "<!-- mb-language:start -->"
END = "<!-- mb-language:end -->"
FILES = ("AGENTS.md", "CLAUDE.md")


def block(language: str, comments_language: str | None = None) -> str:
    rule = resolve_language_strings(language, comments_language).rule_short
    return (f"{START}\n> **Language (this project)** — {rule} "
            f"This overrides the global Memory Bank language rule.\n{END}\n")


def strip_block(text: str) -> str:
    start, end = text.find(START), text.find(END)
    if start == -1 or end < start:
        return text
    return (text[:start] + text[end + len(END):].lstrip("\n")).lstrip("\n")


def targets(project: Path) -> list[Path]:
    """AGENTS.md and CLAUDE.md, once each — CLAUDE.md is often a symlink to AGENTS.md."""
    seen: dict[Path, Path] = {}
    for name in FILES:
        path = project / name
        seen.setdefault(path.resolve(), path)
    return list(seen.values())


def set_language(project: Path, language: str, comments_language: str | None) -> list[Path]:
    written = []
    for path in targets(project):
        rest = strip_block(path.read_text(encoding="utf-8")) if path.exists() else ""
        atomic_write(path.resolve(), block(language, comments_language) + ("\n" + rest if rest else ""),
                     encoding="utf-8")
        written.append(path)
    return written


def clear_language(project: Path) -> list[Path]:
    cleared = []
    for path in targets(project):
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        rest = strip_block(text)
        if rest == text:
            continue
        if rest.strip():
            atomic_write(path.resolve(), rest, encoding="utf-8")
        else:
            path.unlink()  # the file held only our block — it was created by `set`
        cleared.append(path)
    return cleared


def current_rule(project: Path) -> str | None:
    for path in targets(project):
        if path.exists():
            text = path.read_text(encoding="utf-8")
            start, end = text.find(START), text.find(END)
            if start != -1 and end != -1:
                return text[start + len(START):end].strip()
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    set_p = sub.add_parser("set")
    set_p.add_argument("language", choices=sorted(LANGUAGE_NAMES))
    set_p.add_argument("--comments", choices=sorted(LANGUAGE_NAMES), default=None)
    for p in (set_p, sub.add_parser("clear", aliases=["off"]), sub.add_parser("show")):
        p.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args(argv)
    project = args.project.resolve()
    if not project.is_dir():
        print(f"mb-language: project directory not found: {project}", file=sys.stderr)
        return 1
    if args.command == "set":
        for path in set_language(project, args.language, args.comments):
            print(f"set {path}")
    elif args.command in ("clear", "off"):
        for path in clear_language(project):
            print(f"cleared {path}")
    else:
        print(current_rule(project) or "global (no project override)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
