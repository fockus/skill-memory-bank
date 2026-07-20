#!/usr/bin/env python3
"""Derive a brief.md variant from the canonical valid fixture (svp-brief T2/T1).

    mkbrief.py <src> <dst> [--fm-set K=V] [--fm-del K] [--fm-add K=V]
                           [--empty-body NAME] [--drop-section NAME]
                           [--dup-section NAME] [--pad N]

One canonical valid fixture plus a named mutation is how every invalid case in
test_mb_brief_validate.bats is built, so a case differs from `ok` in exactly the
property it is named after — a second hand-written fixture would drift and let a
test pass for a reason other than the one it claims.

Ops apply in a fixed order (frontmatter -> bodies -> sections -> pad) so a
combined fixture (diagnostics-order) is reproducible byte for byte.
"""

from __future__ import annotations

import argparse
from urllib.parse import quote


class MkbriefError(Exception):
    """A malformed request to the fixture deriver."""


def split_front(text: str) -> tuple[list[str], list[str]]:
    """Return (frontmatter-lines-without-fences, body-lines)."""
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        raise MkbriefError("source has no frontmatter")
    for i in range(1, len(lines)):
        if lines[i] == "---":
            return lines[1:i], lines[i + 1 :]
    raise MkbriefError("unterminated frontmatter")


def pct(name: str) -> str:
    """RFC 3986 percent-encoding with the unreserved safe set A-Za-z0-9-._~.

    `quote(safe="")` encodes everything outside exactly that set, so `/` and `#`
    are escaped too. The bats cases additionally pin the literal expected string
    (`a%20b%23c.md`), which is what actually holds the production encoder to
    this grammar rather than to whatever this helper happens to do.
    """
    return quote(name, safe="")


def join(front: list[str], body: list[str]) -> str:
    return "\n".join(["---"] + front + ["---"] + body)


def fm_key(line: str) -> str | None:
    if not line or line.startswith((" ", "\t", "#")):
        return None
    if ":" not in line:
        return None
    return line.split(":", 1)[0].strip()


def fm_block(front: list[str], key: str) -> tuple[int, int] | None:
    """Index range [start, end) of `key:` plus its indented continuation."""
    for i, line in enumerate(front):
        if fm_key(line) == key:
            j = i + 1
            while j < len(front) and front[j].startswith((" ", "\t")):
                j += 1
            return i, j
    return None


def section_bounds(body: list[str], name: str) -> tuple[int, int] | None:
    """Index range [heading, next-H2) of the FIRST `## <name>` heading."""
    head = "## " + name
    for i, line in enumerate(body):
        if line == head:
            j = i + 1
            while j < len(body) and not body[j].startswith("## "):
                j += 1
            return i, j
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--fm-set", action="append", default=[], metavar="K=V")
    ap.add_argument("--fm-del", action="append", default=[], metavar="K")
    ap.add_argument("--fm-add", action="append", default=[], metavar="K=V")
    ap.add_argument("--empty-body", action="append", default=[], metavar="NAME")
    ap.add_argument("--drop-section", action="append", default=[], metavar="NAME")
    ap.add_argument("--dup-section", action="append", default=[], metavar="NAME")
    ap.add_argument("--demote", action="append", default=[], metavar="NAME")
    ap.add_argument("--blank-after", action="append", default=[], metavar="NAME")
    ap.add_argument("--inputs", default=None, metavar="A,B")
    ap.add_argument("--attachments-raw", default=None, metavar="TEXT")
    ap.add_argument("--pad", type=int, default=0, metavar="N")
    args = ap.parse_args()

    with open(args.src, encoding="utf-8") as fh:
        front, body = split_front(fh.read())

    for spec in args.fm_set:
        key, _, value = spec.partition("=")
        span = fm_block(front, key)
        if span is None:
            raise MkbriefError("no such frontmatter key: " + key)
        front[span[0] : span[1]] = [key + ":" + (" " + value if value else "")]

    for key in args.fm_del:
        span = fm_block(front, key)
        if span is None:
            raise MkbriefError("no such frontmatter key: " + key)
        del front[span[0] : span[1]]

    for spec in args.fm_add:
        key, _, value = spec.partition("=")
        front.append(key + ":" + (" " + value if value else ""))

    for name in args.empty_body:
        span = section_bounds(body, name)
        if span is None:
            raise MkbriefError("no such section: " + name)
        body[span[0] : span[1]] = [
            "## " + name,
            "",
            "<!-- to be filled in -->",
            "",
        ]

    for name in args.dup_section:
        span = section_bounds(body, name)
        if span is None:
            raise MkbriefError("no such section: " + name)
        block = body[span[0] : span[1]]
        while block and block[-1] == "":
            block.pop()
        body.extend(block + [""])

    for name in args.drop_section:
        span = section_bounds(body, name)
        if span is None:
            raise MkbriefError("no such section: " + name)
        del body[span[0] : span[1]]

    if args.inputs is not None:
        names = [n for n in args.inputs.split(",") if n]
        span = fm_block(front, "inputs")
        if span is None:
            raise MkbriefError("no such frontmatter key: inputs")
        if names:
            front[span[0] : span[1]] = ["inputs:"] + ["  - inputs/" + n for n in names]
        else:
            front[span[0] : span[1]] = ["inputs: []"]

        span = section_bounds(body, "Attachments")
        if span is None:
            raise MkbriefError("no such section: Attachments")
        if names:
            rows = ["- [%s](inputs/%s)" % (n, pct(n)) for n in names]
        else:
            rows = ["- None"]
        body[span[0] : span[1]] = ["## Attachments"] + rows + [""]

    if args.attachments_raw is not None:
        span = section_bounds(body, "Attachments")
        if span is None:
            raise MkbriefError("no such section: Attachments")
        body[span[0] : span[1]] = ["## Attachments"] + args.attachments_raw.split("\n") + [""]

    for name in args.demote:
        span = section_bounds(body, name)
        if span is None:
            raise MkbriefError("no such section: " + name)
        body[span[0]] = "#" + body[span[0]]

    for name in args.blank_after:
        span = section_bounds(body, name)
        if span is None:
            raise MkbriefError("no such section: " + name)
        body.insert(span[0] + 1, "")

    text = join(front, body)
    if args.pad:
        lines = text.split("\n")
        trailing = 1 if lines and lines[-1] == "" else 0
        while len(lines) < args.pad:
            lines.insert(len(lines) - trailing, "- filler line for the size check")
        if len(lines) != args.pad:
            raise MkbriefError("cannot pad down to %d lines" % args.pad)
        text = "\n".join(lines)

    with open(args.dst, "w", encoding="utf-8") as fh:
        fh.write(text)
    return 0


if __name__ == "__main__":
    # A MkbriefError propagates: an unbuildable fixture must abort the test
    # loudly rather than hand back a file that differs from what was asked for.
    main()
