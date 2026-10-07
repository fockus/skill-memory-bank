"""Carry the networkx-only sections of ``god-nodes.md`` across a networkx-less build.

``## Communities`` and ``## Bridge files`` need networkx. A rebuild under an
interpreter without it (the SessionStart catch-up runs under the system python)
used to drop them from the git-tracked report. Instead, the previous report's
blocks are carried over under a marker that names the build which COMPUTED them
(kept across repeated carries), minus files no longer in the graph. A build with
networkx recomputes them from scratch, so the marker never accumulates (I-225).
"""

from __future__ import annotations

import re
from typing import Any

_TAIL = "networkx is unavailable in this interpreter, so these sections were not recomputed."
_PRUNED = " Files no longer in the graph were removed from these rows."
_MARKER_RE = re.compile(
    r"^_Carried over from (?P<src>.+?): "
    + re.escape(_TAIL)
    + r"(?P<pruned>"
    + re.escape(_PRUNED)
    + r")?_$"
)
_DEFAULT_SOURCE = "an earlier build"
_CARRIED_HEADINGS = ("## Communities", "## Bridge files")
# The networkx install hint follows the carried blocks in a networkx-less report;
# it is re-emitted by the renderer, so it terminates a block like a heading does.
_HINT_PREFIX = "_Install `networkx`"
_ROW_RE = re.compile(r"^\| (?P<cells>.+) \|$")


def source_from_meta(meta: dict[str, Any] | None) -> str | None:
    """Describe the build stamped in a ``graph.json`` meta row (``None`` if unknown)."""
    if not meta:
        return None
    commit, at = meta.get("commit"), meta.get("generated_at")
    if commit and at:
        return f"the build of commit {commit} at {at}"
    if at:
        return f"the build at {at}"
    return f"the build of commit {commit}" if commit else None


def _prune_row(line: str, heading: str, live: set[str]) -> tuple[str | None, bool]:
    """Drop files absent from ``live`` from one table row → (new row or None, pruned?)."""
    m = _ROW_RE.match(line)
    if not m or line.startswith("|---"):
        return line, False
    cells = m.group("cells").split(" | ")
    if heading.startswith("## Bridge files") and len(cells) == 3:
        name = cells[1].strip("`")
        if name != "File" and name not in live:
            return None, True
        return line, False
    if len(cells) != 4 or not cells[1].isdigit():
        return line, False
    more = cells[3].endswith(" …")
    files = cells[3].removesuffix(" …").split(", ")
    kept = [f for f in files if f.strip("`") in live]
    if len(kept) == len(files):
        return line, False
    # ponytail: the sample shows ≤3 members, so a gone file hidden behind "…" is
    # not subtracted; exact counts come back with the next networkx build.
    count = int(cells[1]) - (len(files) - len(kept))
    if count <= 0 or (not kept and not more):
        return None, True
    sample = ", ".join(kept) + (" …" if more else "")
    return "| " + " | ".join([cells[0], str(count), cells[2], sample.strip()]) + " |", True


def _renumber_bridges(body: list[str]) -> list[str]:
    n, out = 0, []
    for line in body:
        m = _ROW_RE.match(line)
        cells = m.group("cells").split(" | ") if m else []
        if len(cells) == 3 and cells[0].isdigit():
            n += 1
            line = "| " + " | ".join([str(n), *cells[1:]]) + " |"
        out.append(line)
    return out


def _render_block(block: list[str], source: str | None, live: set[str] | None) -> list[str]:
    heading, body, src, pruned = block[0], [], None, False
    for line in block[1:]:
        marker = _MARKER_RE.match(line)
        if marker:
            src, pruned = marker.group("src"), bool(marker.group("pruned"))
            continue
        if live is not None:
            line, dropped = _prune_row(line, heading, live)
            pruned |= dropped
            if line is None:
                continue
        body.append(line)
    if heading.startswith("## Bridge files"):
        body = _renumber_bridges(body)
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    # A carried block keeps the source it was computed in, never the stamp of an
    # intermediate networkx-less build.
    note = f"_Carried over from {src or source or _DEFAULT_SOURCE}: {_TAIL}{_PRUNED if pruned else ''}_"
    return ["", heading, "", note, "", *body]


def carried_sections(
    previous_md: str | None, source: str | None = None, live_files: set[str] | None = None
) -> list[str]:
    """Return report lines for the carried blocks (empty when there is nothing to carry).

    A block runs from its heading to the next ``## `` heading or the networkx
    install hint (exclusive). ``source`` names the build that computed the
    blocks when the previous report was itself a networkx build; ``live_files``
    (the current graph's files) prunes rows naming deleted files.
    """
    if not previous_md:
        return []
    out: list[str] = []
    block: list[str] | None = None
    for line in [*previous_md.splitlines(), "## "]:
        if line.startswith(("## ", _HINT_PREFIX)):
            if block:
                out += _render_block(block, source, live_files)
            block = [line] if line.startswith(_CARRIED_HEADINGS) else None
        elif block is not None:
            block.append(line)
    return out
