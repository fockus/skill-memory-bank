#!/usr/bin/env python3
"""Line-range contents block for a long Markdown command file.

Usage:
  mb-doc-toc.py <file>           # rewrite the block between <!-- toc:start --> and <!-- toc:end -->
  mb-doc-toc.py --check <file>   # exit 1 when the block is stale

The block holds a read-whole-file line with the total line count and one `- L<start>–L<end> · <title>`
line per `## ` section after it, so an agent whose reader stops after the first lines can still read
every section by range. A test runs --check so the ranges cannot drift.
Exit: 0 ok · 1 stale (--check) · 2 usage or no markers.
"""

from __future__ import annotations

import sys
from pathlib import Path

START, END = "<!-- toc:start -->", "<!-- toc:end -->"


def _sections(lines: list[str], after: int) -> list[tuple[int, str]]:
    out, fence = [], False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fence = not fence
        elif not fence and i > after and line.startswith("## "):
            out.append((i, line[3:].strip()))
    return out


def render(text: str) -> str:
    lines = text.splitlines()
    if START not in lines or END not in lines:
        raise ValueError(f"no {START} … {END} markers")
    s, e = lines.index(START), lines.index(END)
    count = (
        len(_sections(lines, e)) + 1
    )  # the block's own size is fixed: one line per section + the read line
    lines[s + 1 : e] = [""] * count
    e = s + 1 + count
    heads = _sections(lines, e)
    ends = [i for i, _ in heads[1:]] + [len(lines)]
    body = [
        f"Read this file whole: {len(lines)} lines — one Read call, no offset or limit. Sections by line:"
    ]
    body += [f"- L{i + 1}–L{end} · {title}" for (i, title), end in zip(heads, ends, strict=True)]
    lines[s + 1 : e] = body
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    check = argv[:1] == ["--check"]
    paths = argv[1:] if check else argv
    if len(paths) != 1:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    path = Path(paths[0])
    text = path.read_text(encoding="utf-8")
    try:
        new = render(text)
    except ValueError as exc:
        print(f"mb-doc-toc: {path}: {exc}", file=sys.stderr)
        return 2
    if check:
        if new != text:
            print(
                f"mb-doc-toc: {path}: contents block is stale; run scripts/mb-doc-toc.py {path}",
                file=sys.stderr,
            )
            return 1
        return 0
    path.write_text(new, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
