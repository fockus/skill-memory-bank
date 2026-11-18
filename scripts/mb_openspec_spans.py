#!/usr/bin/env python3
"""Where each sync unit lives inside a bank file (AGR-105 unit model).

One parser serves both hashing (``mb_openspec_sync.bank_units``) and splicing
(``mb_openspec_splice``), so the text a unit is hashed by is exactly the text
a splice replaces. Spans index ``str.splitlines()`` lines; ``end`` is one past
the last non-blank line of the unit. Lines outside every span (headings,
Covers/Role, bank-added sections, task prose) are never touched by a splice.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    from mb_openspec_tasks import task_id
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_tasks import task_id

META_RE = re.compile(r"^<!-- openspec: .* -->$")
ANCHOR_RE = re.compile(r"^<!-- openspec-req: (?P<name>.*) -->$")
SCENARIO_MARK_RE = re.compile(r"^<!-- /?mb-scenario:\d+ -->$")
GROUP_MARKER_RE = re.compile(r"^<!-- mb-task:(?P<n>\S+) -->$")
GROUP_TITLE_RE = re.compile(r"^## Task (?P<n>\S+): (?P<title>.*)$")
ITEM_RE = re.compile(r"^- (?:\[(?P<mark>[ xX])\] )?(?P<text>.+)$")
REQ_HEADING_PREFIX = "### Requirement "
DESIGN_SECTIONS = {
    "Why": "proposal:why",
    "What Changes": "proposal:what-changes",
    "OpenSpec Design Notes": "design",
}
REMOVED_SECTION = "Removed scope"


@dataclass
class Span:
    """A unit's block: ``lines[start:end]``; ``body`` is the hashed text."""

    start: int
    end: int
    body: list[str] = field(default_factory=list)
    head: int = -1  # the heading line that owns the block (-1: none)
    checked: bool | None = None  # task items: the checkbox, None for a plain line
    group: str | None = None  # task items: the owning task group


def task_key(group: str, text: str) -> str:
    """``task:N.M`` for an item with an id, else ``task:<group>:<normalized text>``."""
    norm = " ".join(text.split())
    tid = task_id(norm)
    return f"task:{tid}" if tid else f"task:{group}:{norm}"


def trim_end(lines: list[str], start: int, end: int) -> int:
    while end > start and not lines[end - 1].strip():
        end -= 1
    return end


def _is_section_break(line: str) -> bool:
    return line.startswith("## ") or line.startswith("# ")


def _heading_before(lines: list[str], index: int) -> int:
    j = index - 1
    while j >= 0 and not lines[j].strip():
        j -= 1
    return j if j >= 0 and lines[j].startswith(REQ_HEADING_PREFIX) else -1


def requirement_spans(lines: list[str]) -> dict[str, Span]:
    """``req:<anchor>`` -> span from its meta line (or anchor) to the next unit/heading."""
    out: dict[str, Span] = {}
    for a, line in enumerate(lines):
        m = ANCHOR_RE.match(line)
        if not m:
            continue
        start = a - 1 if a > 0 and META_RE.match(lines[a - 1]) else a
        j = a + 1
        while j < len(lines):
            cur = lines[j]
            next_is_anchor = j + 1 < len(lines) and ANCHOR_RE.match(lines[j + 1])
            if ANCHOR_RE.match(cur) or cur.startswith(REQ_HEADING_PREFIX) or _is_section_break(cur):
                break
            if META_RE.match(cur) and next_is_anchor:
                break
            j += 1
        end = trim_end(lines, a + 1, j)
        out.setdefault(
            f"req:{m.group('name')}",
            Span(start, end, lines[a + 1 : j], _heading_before(lines, start)),
        )
    return out


def _removed_spans(lines: list[str], head: int, stop: int, out: dict[str, Span]) -> None:
    subs = [j for j in range(head + 1, stop) if lines[j].startswith("### ")]
    for n, j in enumerate(subs):
        sub_stop = subs[n + 1] if n + 1 < len(subs) else stop
        start = j - 1 if j - 1 > head and META_RE.match(lines[j - 1]) else j
        end = trim_end(lines, j + 1, sub_stop)
        if end > j + 1 and META_RE.match(lines[end - 1]):  # the next entry's meta line
            end = trim_end(lines, j + 1, end - 1)
        out.setdefault(
            f"removed:{lines[j][4:].strip()}", Span(start, end, lines[j + 1 : sub_stop], head)
        )


def design_spans(lines: list[str]) -> dict[str, Span]:
    """Proposal/design sections by their body, Removed-scope entries by their block."""
    out: dict[str, Span] = {}
    heads = [i for i, line in enumerate(lines) if line.startswith("## ")]
    for n, i in enumerate(heads):
        stop = heads[n + 1] if n + 1 < len(heads) else len(lines)
        title = lines[i][3:].strip()
        if title in DESIGN_SECTIONS:
            start = i + 1
            while start < stop and not lines[start].strip():
                start += 1
            out.setdefault(
                DESIGN_SECTIONS[title],
                Span(start, trim_end(lines, start, stop), lines[i + 1 : stop], i),
            )
        elif title == REMOVED_SECTION:
            _removed_spans(lines, i, stop, out)
    return out


def task_spans(lines: list[str]) -> dict[str, Span]:
    """``group:N`` -> its block (``head`` = title line); task items -> their line."""
    out: dict[str, Span] = {}
    markers = [(i, m.group("n")) for i, ln in enumerate(lines) if (m := GROUP_MARKER_RE.match(ln))]
    for n, (i, group) in enumerate(markers):
        stop = markers[n + 1][0] if n + 1 < len(markers) else len(lines)
        title_at, title = -1, ""
        for j in range(i + 1, stop):
            cur = lines[j]
            tm = GROUP_TITLE_RE.match(cur)
            if title_at < 0 and tm and tm.group("n") == group:
                title_at, title = j, tm.group("title").strip()
                continue
            if _is_section_break(cur):
                stop = j
                break
            im = ITEM_RE.match(cur) if title_at >= 0 else None
            if im:
                mark = im.group("mark")
                checked = None if mark is None else mark.lower() == "x"
                key = task_key(group, im.group("text"))
                out.setdefault(key, Span(j, j + 1, [im.group("text").strip()], -1, checked, group))
        if title_at >= 0:
            out[f"group:{group}"] = Span(i, trim_end(lines, i, stop), [title], title_at)
    return out


_SCENARIO_OPEN_RE = re.compile(r"^<!-- mb-scenario:\d+ -->$")
_SCENARIO_CLOSE_RE = re.compile(r"^<!-- /mb-scenario:\d+ -->$")
_REQ_ID_RE = re.compile(r"^-\s+\*\*(REQ-\d{3,})\*\*")
COVERS_PREFIX = "**Covers:**"


def req_id_of(span: Span) -> str | None:
    return next((m.group(1) for ln in span.body if (m := _REQ_ID_RE.match(ln))), None)


def shared_scenarios(lines: list[str], spans: dict[str, Span]) -> list[tuple[int, int, list[str]]]:
    """``(start, end, covered REQ-IDs)`` of each mb-scenario block outside every requirement
    span — e.g. a bank-authored ``## Scenarios`` section. Such a block belongs to every
    requirement its ``**Covers:**`` names (hashing, splicing and export alike)."""
    inside = [(s.start, s.end) for s in spans.values()]
    out: list[tuple[int, int, list[str]]] = []
    i = 0
    while i < len(lines):
        if not _SCENARIO_OPEN_RE.match(lines[i]) or any(a <= i < b for a, b in inside):
            i += 1
            continue
        j = i + 1
        while (
            j < len(lines)
            and not _SCENARIO_OPEN_RE.match(lines[j])
            and not _is_section_break(lines[j])
        ):
            j += 1
            if _SCENARIO_CLOSE_RE.match(lines[j - 1]):
                break
        covers = [
            rid
            for ln in lines[i:j]
            if ln.startswith(COVERS_PREFIX)
            for rid in re.findall(r"REQ-\d{3,}", ln)
        ]
        out.append((i, trim_end(lines, i, j), covers))
        i = j
    return out
