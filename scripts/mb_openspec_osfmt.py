#!/usr/bin/env python3
"""OpenSpec-side text: render a bank unit in OpenSpec syntax and splice it into a file.

Every splicer edits only the block it is given and returns the whole new file
text, so the bytes of every other unit stay exactly as OpenSpec wrote them
(AGR-105 Q3 A / Q4 C). REQ-IDs, ``**Covers:**`` lines and deterministic stub
scenarios never reach OpenSpec (Q2 B).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    from mb_openspec_spans import task_key
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_spans import task_key

_REQ_BULLET_RE = re.compile(r"^-\s+\*\*REQ-\d{3,}\*\*\s+\([^)]*\):\s*(?P<text>.*)$")
_STEP_RE = re.compile(r"^-\s+(?P<kw>GIVEN|WHEN|THEN|AND|BUT)\s+(?P<text>.*)$")
_DELTA_RE = re.compile(r"^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements[ \t]*$", re.MULTILINE)
_REQ_HEAD_RE = re.compile(r"^### Requirement: (.+?)[ \t]*$", re.MULTILINE)
_GROUP_RE = re.compile(r"^## (\d+)\.\s+(.+?)\s*$")
_ITEM_RE = re.compile(
    r"^(?P<prefix>\s*(?:[-*]\s*)?)(?:\[(?P<mark>[ xX])\](?P<gap>\s+))?(?P<text>\S.*?)\s*$"
)
STUB_SCENARIO = "(none provided)"


def scenario_lines(name: str, steps: list[tuple[str, str]]) -> list[str]:
    return ["", f"#### Scenario: {name}", *[f"- **{kw}** {text}" for kw, text in steps]]


def requirement_block(name: str, unit_text: str) -> str:
    """A bank requirement unit (bullet + scenarios) as an OpenSpec ``### Requirement:`` block."""
    text: list[str] = []
    scenarios: list[tuple[str, list[tuple[str, str]]]] = []
    state = "pre"
    for raw in unit_text.splitlines():
        line = raw.strip()
        bullet = _REQ_BULLET_RE.match(line)
        if bullet and state == "pre":
            text.append(bullet.group("text"))
            state = "text"
        elif line.startswith("### Scenario: "):
            scenarios.append((line[len("### Scenario: ") :].strip(), []))
            state = "scenario"
        elif state == "scenario" and (step := _STEP_RE.match(line)):
            scenarios[-1][1].append((step.group("kw"), step.group("text")))
        elif state == "text" and not line:
            state = "after"
        elif state == "text" and not line.startswith(("**Covers:**", "<!--")):
            text.append(line)
    out = [f"### Requirement: {name}", "\n".join(text)]
    for sname, steps in scenarios:
        if sname == STUB_SCENARIO and all(t == "not specified" for _kw, t in steps):
            continue
        out += scenario_lines(sname, steps)
    return "\n".join(out)


def removed_block(name: str, unit_text: str) -> str:
    reason = next(
        (
            ln.split("**Reason:**", 1)[1].strip()
            for ln in unit_text.splitlines()
            if "**Reason:**" in ln
        ),
        "",
    )
    return f"### Requirement: {name}\n**Reason**: {reason}"


def promote_headings(text: str) -> str:
    """Inverse of the importer's heading demotion for the OpenSpec design notes."""
    return re.sub(r"(?m)^#(#{1,6})(\s)", r"\1\2", text)


def replace_section(text: str, header: str, body: str) -> str:
    """Replace the body of a ``## <header>`` section, keeping the whitespace around it."""
    m = re.search(rf"^## {re.escape(header)}[ \t]*$", text, re.MULTILINE)
    if m is None:
        return text.rstrip("\n") + f"\n\n## {header}\n\n{body.strip()}\n"
    nxt = re.compile(r"^## ", re.MULTILINE).search(text, m.end())
    end = nxt.start() if nxt else len(text)
    region = text[m.end() : end]
    lead = region[: len(region) - len(region.lstrip())] or "\n\n"
    trail = region[len(region.rstrip()) :] or ("\n\n" if nxt else "\n")
    return text[: m.end()] + lead + body.strip() + trail + text[end:]


def _sections(text: str) -> list[tuple[str, int, int]]:
    heads = list(_DELTA_RE.finditer(text))
    return [
        (h.group(1).lower(), h.end(), heads[i + 1].start() if i + 1 < len(heads) else len(text))
        for i, h in enumerate(heads)
    ]


def find_requirement(text: str, name: str, kinds: set[str]) -> tuple[int, int] | None:
    """``(start, end)`` of the named block in a delta section of one of ``kinds``."""
    for kind, a, b in _sections(text):
        if kind not in kinds:
            continue
        heads = list(_REQ_HEAD_RE.finditer(text, a, b))
        for i, h in enumerate(heads):
            if h.group(1).strip() == name:
                end = heads[i + 1].start() if i + 1 < len(heads) else b
                return h.start(), h.start() + len(text[h.start() : end].rstrip())
    return None


def replace_block(text: str, span: tuple[int, int], block: str) -> str:
    return text[: span[0]] + block + text[span[1] :]


def delete_block(text: str, span: tuple[int, int]) -> str:
    end = span[1] + (len(text[span[1] :]) - len(text[span[1] :].lstrip()))
    out = text[: span[0]] + text[end:]
    return out.rstrip("\n") + "\n" if out.strip() else ""


def insert_requirement(text: str, kind: str, block: str) -> str:
    """Append ``block`` to the ``## <KIND> Requirements`` section, creating it if needed."""
    for section_kind, a, b in _sections(text):
        if section_kind == kind:
            end = a + len(text[a:b].rstrip())
            return text[:end] + "\n\n" + block + (text[end:] if text[end:] else "\n")
    base = text.rstrip("\n")
    return (base + "\n\n" if base else "") + f"## {kind.upper()} Requirements\n\n{block}\n"


def _group_regions(lines: list[str]) -> list[tuple[str, int, int]]:
    heads = [(i, m.group(1)) for i, ln in enumerate(lines) if (m := _GROUP_RE.match(ln))]
    return [
        (n, i, heads[k + 1][0] if k + 1 < len(heads) else len(lines))
        for k, (i, n) in enumerate(heads)
    ]


def _item_at(lines: list[str], key: str) -> int | None:
    for group, start, end in _group_regions(lines):
        for j in range(start + 1, end):
            m = _ITEM_RE.match(lines[j])
            if (
                m
                and not lines[j].lstrip().startswith("#")
                and task_key(group, m.group("text")) == key
            ):
                return j
    return None


def _render_item(old: str | None, text: str, checked: bool | None) -> str:
    m = _ITEM_RE.match(old or "") if old else None
    prefix = m.group("prefix") if m else "- "
    if checked is None:
        return f"{prefix}{text}"
    gap = m.group("gap") if m and m.group("gap") else " "
    return f"{prefix}[{'x' if checked else ' '}]{gap}{text}"


def edit_task(text: str, key: str, new_text: str | None, checked: bool | None) -> str | None:
    """Replace (``new_text``) or delete (``None``) one task line; ``None`` if not found."""
    lines = text.split("\n")
    at = _item_at(lines, key)
    if at is None:
        return None
    lines[at : at + 1] = [] if new_text is None else [_render_item(lines[at], new_text, checked)]
    return "\n".join(lines)


def add_task(text: str, group: str, item_text: str, checked: bool | None) -> str | None:
    lines = text.split("\n")
    region = next(((s, e) for n, s, e in _group_regions(lines) if n == group), None)
    if region is None:
        return None
    items = [
        j for j in range(region[0] + 1, region[1]) if lines[j].strip() and _ITEM_RE.match(lines[j])
    ]
    new = _render_item(None, item_text, checked)
    pos = items[-1] + 1 if items else region[0] + 1
    lines[pos:pos] = [new] if items else ["", new]
    return "\n".join(lines)


def set_group(
    text: str, group: str, title: str | None, items: list[tuple[bool | None, str]]
) -> str:
    """Retitle a group, delete it (``title=None``), or append it when it is missing."""
    lines = text.split("\n")
    region = next(((s, e) for n, s, e in _group_regions(lines) if n == group), None)
    if region is not None and title is not None:
        lines[region[0]] = f"## {group}. {title}"
        return "\n".join(lines)
    if region is not None:
        del lines[region[0] : region[1]]
        out = "\n".join(lines)
        return out if not out or out.endswith("\n") else out + "\n"
    if title is None:
        return text
    body = "\n".join(_render_item(None, t, c) for c, t in items)
    base = text.rstrip("\n")
    return (base + "\n\n" if base else "") + f"## {group}. {title}\n\n{body}\n"
