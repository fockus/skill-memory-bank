#!/usr/bin/env python3
"""Parse plan stages and spec tasks into a unified WorkItem model.

Public API
----------
parse_work_items(path: pathlib.Path) -> list[WorkItem]
    Read a Markdown file that contains ``<!-- mb-stage:N -->`` or
    ``<!-- mb-task:N -->`` comment markers and return one :class:`WorkItem`
    per marker block.

CLI usage
---------
    python3 scripts/mb_work_items.py <path>

Emits one JSON object per line (JSON Lines) to stdout, one per WorkItem.
Keys are the dataclass field names; ``covers`` and ``dod_lines`` are lists.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import asdict, dataclass
from typing import Literal

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

_STAGE_RE = re.compile(r"<!--\s*mb-stage:(\d+)\s*-->")
_TASK_RE = re.compile(r"<!--\s*mb-task:(\d+)\s*-->")
_DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_")

_COVERS_RE = re.compile(r"^\*\*covers:\*\*\s*(.+)$", re.IGNORECASE)
_ROLE_RE = re.compile(r"^\*\*Role:\*\*\s*(\S+)", re.IGNORECASE)
# Accept a qualifier after DoD (the global rules call for "DoD (SMART)"):
# `**DoD:**`, `**DoD (SMART)**`, `**DoD**` all open the section.
_DOD_HEADING_RE = re.compile(r"^\*\*DoD\b", re.IGNORECASE)
_CHECKBOX_RE = re.compile(r"^- \[[ xX]\] .+")
_CHECKED_RE = re.compile(r"^- \[[xX]\] ")

# v2 task fields (C1 grammar) — bold-labelled lines inside a task/stage block.
# The value group is ``.*?`` (not ``.+?``) so an EXPLICITLY empty field still
# matches and is rejected as malformed rather than silently defaulting.
_STAGE_FIELD_RE = re.compile(r"^\*\*Stage:\*\*\s*(.*?)\s*$", re.IGNORECASE)
_BLOCKED_FIELD_RE = re.compile(r"^\*\*Blocked-by:\*\*\s*(.*?)\s*$", re.IGNORECASE)
_SCOPE_FIELD_RE = re.compile(r"^\*\*Scope:\*\*\s*(.*?)\s*$", re.IGNORECASE)
_EVAL_FIELD_RE = re.compile(r"^\*\*Eval:\*\*\s*(.*?)\s*$", re.IGNORECASE)
_BUDGET_FIELD_RE = re.compile(r"^\*\*Budget:\*\*\s*(.*?)\s*$", re.IGNORECASE)

_UINT_RE = re.compile(r"^\d+$")
_BLOCKED_LOCAL_RE = re.compile(r"^\d+$")
_BLOCKED_XSPEC_RE = re.compile(r"^[A-Za-z0-9._-]+#\d+$")
# Restricted-glob forbidden metacharacters (R3-004): ? [ ] { } and backslash.
_SCOPE_FORBIDDEN_RE = re.compile(r"[?\[\]{}\\]")

# Eval declaration (C1): "<cmd> — red: <prose>[; exit: <n>][; output~: <ERE>]"
# or "none[ — waiver: <reason>]". The separator is an em-dash (U+2014).
_EVAL_DASH = "—"
_EVAL_OUTPUT_RE = re.compile(r"output~:\s*(.*)$")
_EVAL_EXIT_RE = re.compile(r"(?:^|;)\s*exit:\s*(\d+)")
_EVAL_RED_RE = re.compile(r"red:\s*(.*?)\s*(?:;\s*(?:exit|output~):|$)")
_EVAL_WAIVER_RE = re.compile(r"waiver:\s*(.*)$")

_QA_SIGNALS = re.compile(r"\bpytest\b|\bunittest\b")
_IOS_SIGNALS = re.compile(r"\bswift\b|\bxcode\b|\biostest\b|\bxctest\b", re.IGNORECASE)
_ANDROID_SIGNALS = re.compile(r"\bandroid\b|\bkotlin\b|\bcompose\b|\bespresso\b", re.IGNORECASE)
_FRONTEND_SIGNALS = re.compile(r"\breact\b|\bvue\b|\bangular\b|\bhtml\b|\bcss\b", re.IGNORECASE)
_BACKEND_SIGNALS = re.compile(r"\bdjango\b|\bfastapi\b|\bflask\b|\bspring\b|\bsql\b", re.IGNORECASE)
_DEVOPS_SIGNALS = re.compile(
    r"\bdocker\b|\bkubernetes\b|\bterraform\b|\bci/cd\b|\bdeploy\b", re.IGNORECASE
)
_ARCHITECT_SIGNALS = re.compile(r"\badr\b|\barchitecture\b|\bdiagram\b|\berdoc\b", re.IGNORECASE)
_ANALYST_SIGNALS = re.compile(
    r"\bears\b|\brequirements?\b|\bspec\b|\btraceability\b", re.IGNORECASE
)


class MalformedTaskField(Exception):
    """A v2 task field violates the C1 grammar (Scope/Blocked-by/Stage/Budget).

    Distinct from the mixed-marker ``ValueError`` so the CLI can map it to
    exit code ``2`` (R3-004) while mixed markers stay exit ``1``.
    """


@dataclass(frozen=True)
class WorkItem:
    """A single parsed work unit from a plan stage or spec task file."""

    source: Literal["plan", "spec"]
    topic: str
    item_no: int
    kind: Literal["stage", "task"]
    heading: str
    body: str
    role: str
    agent: str
    status: Literal["pending", "in-progress", "done"]
    covers: tuple[str, ...]
    dod_lines: tuple[str, ...]
    # tasks.md v2 fields (C1/C2) — additive; legacy blocks resolve to defaults.
    stage: int
    blocked_by: tuple[str, ...]
    scope: tuple[str, ...]
    eval: dict | None
    budget: int
    # True when the body carried an explicit `**Role:**` line — consumers must
    # not re-route such an item through their own keyword heuristic.
    role_explicit: bool = False


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _derive_topic(path: pathlib.Path, source: Literal["plan", "spec"]) -> str:
    """Return topic string for the given file path and source type."""
    if source == "plan":
        stem = path.stem
        return _DATE_PREFIX_RE.sub("", stem)
    else:
        return path.parent.name


def _parse_covers(body: str) -> tuple[str, ...]:
    """Extract REQ IDs from ``**Covers:** ...`` line(s) in body."""
    for line in body.splitlines():
        m = _COVERS_RE.match(line.strip())
        if m:
            raw = m.group(1)
            ids = [v.strip().upper() for v in raw.split(",") if v.strip()]
            return tuple(ids)
    return ()


def _parse_explicit_role(body: str) -> str | None:
    """Return explicit role from ``**Role:** <name>`` line, or None."""
    for line in body.splitlines():
        m = _ROLE_RE.match(line.strip())
        if m:
            return m.group(1).strip()
    return None


def _autodetect_role(body: str) -> str:
    """Heuristically detect role from keywords in body text."""
    if _QA_SIGNALS.search(body):
        return "qa"
    if _IOS_SIGNALS.search(body):
        return "ios"
    if _ANDROID_SIGNALS.search(body):
        return "android"
    if _FRONTEND_SIGNALS.search(body):
        return "frontend"
    if _BACKEND_SIGNALS.search(body):
        return "backend"
    if _DEVOPS_SIGNALS.search(body):
        return "devops"
    if _ARCHITECT_SIGNALS.search(body):
        return "architect"
    if _ANALYST_SIGNALS.search(body):
        return "analyst"
    return "developer"


def _parse_int_field(raw: str, name: str) -> int:
    """Parse an integer-valued v2 field (Stage/Budget); malformed → exit 2."""
    value = raw.strip()
    if not _UINT_RE.match(value):
        raise MalformedTaskField(f"{name} must be a non-negative integer: {value!r}")
    return int(value)


def _parse_blocked_by(raw: str) -> tuple[str, ...]:
    """Parse ``Blocked-by`` CSV per C1: ``<n>`` | ``<topic>#<n>`` | ``none``."""
    value = raw.strip()
    if value.lower() == "none":
        return ()
    refs: list[str] = []
    for part in value.split(","):
        ref = part.strip()
        if ref == "":
            raise MalformedTaskField(f"empty Blocked-by element in {value!r}")
        if _BLOCKED_LOCAL_RE.match(ref) or _BLOCKED_XSPEC_RE.match(ref):
            refs.append(ref)
        else:
            raise MalformedTaskField(f"malformed Blocked-by reference: {ref!r}")
    return tuple(refs)


def _validate_scope_element(elem: str) -> None:
    """Validate one restricted-glob Scope element (C1 / R3-004)."""
    if elem == "":
        raise MalformedTaskField("empty Scope element")
    if elem.startswith("/"):
        raise MalformedTaskField(f"absolute path not allowed in Scope: {elem!r}")
    if "!" in elem:
        raise MalformedTaskField(f"negation not allowed in Scope: {elem!r}")
    if _SCOPE_FORBIDDEN_RE.search(elem):
        raise MalformedTaskField(f"forbidden metacharacter in Scope element: {elem!r}")
    for seg in elem.split("/"):
        if seg == "..":
            raise MalformedTaskField(f"'..' segment not allowed in Scope: {elem!r}")
        if seg == "":
            raise MalformedTaskField(f"empty path segment in Scope: {elem!r}")


def _parse_scope(raw: str) -> tuple[str, ...]:
    """Parse ``Scope`` CSV of repo-relative restricted-glob patterns (C1).

    A comma is a top-level separator only; a comma not followed by whitespace
    (or end of value) is a comma *within* an element and is malformed — there
    is no quoting/escaping (R3-004). Real scopes always separate with ", ".
    """
    value = raw.strip()
    if value == "":
        raise MalformedTaskField("empty Scope value")
    for i, ch in enumerate(value):
        if ch == "," and i + 1 < len(value) and not value[i + 1].isspace():
            raise MalformedTaskField(f"comma within Scope element: {value!r}")
    elements = tuple(part.strip() for part in value.split(","))
    for elem in elements:
        _validate_scope_element(elem)
    return elements


def _strip_code_span(value: str) -> str:
    """Strip ONE outer Markdown code-span (`` `…` ``) pair, keeping the inside.

    Eval lines are authored byte-identical to their ``design.md`` declarations,
    which wrap the command and the ``output~:`` ERE in inline code spans (CPR-D).
    Consumers (C6/C8) execute the command and compile the ERE, so the backticks
    must not survive into ``cmd``/``output_re``. Only the single outermost pair
    is removed; nested/internal backticks are preserved untouched.
    """
    if len(value) >= 2 and value[0] == "`" and value[-1] == "`":
        return value[1:-1]
    return value


def _parse_eval(raw: str) -> dict | None:
    """Parse an ``Eval`` declaration into ``{cmd, red, exit, output_re, waiver}``.

    Lenient by design: anchor/red presence is enforced by the validator (T2),
    not the parser. An explicitly empty field is malformed (exit 2).
    """
    value = raw.strip()
    if value == "":
        raise MalformedTaskField("empty Eval value")
    if value.lower() == "none":
        return {"cmd": "none", "red": None, "exit": None, "output_re": None, "waiver": None}

    if _EVAL_DASH in value:
        left, right = value.split(_EVAL_DASH, 1)
        cmd = left.strip()
        annotation = right.strip()
    else:
        cmd = value
        annotation = ""

    if cmd.lower() == "none":
        wm = _EVAL_WAIVER_RE.search(annotation)
        waiver = wm.group(1).strip() if wm else None
        return {"cmd": "none", "red": None, "exit": None, "output_re": None, "waiver": waiver}

    red: str | None = None
    exit_code: int | None = None
    output_re: str | None = None
    if annotation:
        om = _EVAL_OUTPUT_RE.search(annotation)
        if om:
            output_re = _strip_code_span(om.group(1).strip())
        em = _EVAL_EXIT_RE.search(annotation)
        if em:
            exit_code = int(em.group(1))
        rm = _EVAL_RED_RE.search(annotation)
        if rm:
            red = rm.group(1).strip()
    return {
        "cmd": _strip_code_span(cmd),
        "red": red,
        "exit": exit_code,
        "output_re": output_re,
        "waiver": None,
    }


def _parse_v2_fields(
    body: str, default_blocked: tuple[str, ...]
) -> tuple[int, tuple[str, ...], tuple[str, ...], dict | None, int]:
    """Extract the C1 v2 fields from a block body, applying C1 defaults."""
    stage = 1
    blocked_by = default_blocked
    scope: tuple[str, ...] = ("**",)
    eval_obj: dict | None = None
    budget = 120000

    for raw_line in body.splitlines():
        line = raw_line.strip()
        if not line.startswith("**"):
            continue
        m = _STAGE_FIELD_RE.match(line)
        if m:
            stage = _parse_int_field(m.group(1), "Stage")
            continue
        m = _BUDGET_FIELD_RE.match(line)
        if m:
            budget = _parse_int_field(m.group(1), "Budget")
            continue
        m = _BLOCKED_FIELD_RE.match(line)
        if m:
            blocked_by = _parse_blocked_by(m.group(1))
            continue
        m = _SCOPE_FIELD_RE.match(line)
        if m:
            scope = _parse_scope(m.group(1))
            continue
        m = _EVAL_FIELD_RE.match(line)
        if m:
            eval_obj = _parse_eval(m.group(1))
            continue

    return stage, blocked_by, scope, eval_obj, budget


def _parse_dod(body: str) -> tuple[tuple[str, ...], Literal["pending", "in-progress", "done"]]:
    """Parse DoD checkbox lines and return (dod_lines, status)."""
    lines = body.splitlines()
    in_dod = False
    checkbox_lines: list[str] = []

    for line in lines:
        if _DOD_HEADING_RE.match(line.strip()):
            in_dod = True
            continue
        if in_dod:
            stripped = line.strip()
            # Stop when we hit a new bold-heading section (** prefix) that isn't a checkbox
            if stripped.startswith("**") and not _CHECKBOX_RE.match(stripped):
                break
            if _CHECKBOX_RE.match(stripped):
                checkbox_lines.append(stripped)

    if not checkbox_lines:
        return (), "pending"

    checked_count = sum(1 for ln in checkbox_lines if _CHECKED_RE.match(ln))
    total = len(checkbox_lines)

    if checked_count == total:
        status: Literal["pending", "in-progress", "done"] = "done"
    elif checked_count > 0:
        status = "in-progress"
    else:
        status = "pending"

    return tuple(checkbox_lines), status


def _extract_heading(block_text: str) -> str:
    """Return the first non-empty line of the block (the heading line)."""
    for line in block_text.splitlines():
        stripped = line.strip()
        if stripped:
            # Strip leading '#' characters and whitespace for the heading value
            return stripped.lstrip("#").strip()
    return ""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_work_items(path: pathlib.Path) -> list[WorkItem]:
    """Parse a Markdown file and return one :class:`WorkItem` per marker block.

    Parameters
    ----------
    path:
        Absolute or relative path to a ``.md`` file. The file is read as
        UTF-8. An empty file or a file with no ``<!-- mb-stage:N -->`` /
        ``<!-- mb-task:N -->`` markers returns an empty list.

    Raises
    ------
    ValueError
        If the file contains both ``<!-- mb-stage:N -->`` and
        ``<!-- mb-task:N -->`` markers (mixed format).
    """
    text = path.read_text(encoding="utf-8")

    has_stage = bool(_STAGE_RE.search(text))
    has_task = bool(_TASK_RE.search(text))

    if has_stage and has_task:
        raise ValueError(
            f"mixed marker types in {path}: file contains both "
            "<!-- mb-stage:N --> and <!-- mb-task:N --> markers"
        )

    if not has_stage and not has_task:
        return []

    source: Literal["plan", "spec"]
    kind: Literal["stage", "task"]
    marker_re: re.Pattern[str]

    if has_stage:
        source = "plan"
        kind = "stage"
        marker_re = _STAGE_RE
    else:
        source = "spec"
        kind = "task"
        marker_re = _TASK_RE

    topic = _derive_topic(path, source)

    # Split on markers, keeping the marker text so we can capture item_no
    parts = marker_re.split(text)
    # parts = [pre-text, no1, block1, no2, block2, ...]
    # marker_re has one capture group → split interleaves numbers and blocks

    items: list[WorkItem] = []
    # parts[0] is preamble before first marker; skip it
    # parts[1::2] are the captured group (item numbers)
    # parts[2::2] are the content blocks following each marker
    pair_count = (len(parts) - 1) // 2
    prev_no: int | None = None
    for i in range(pair_count):
        item_no = int(parts[1 + i * 2])
        block = parts[2 + i * 2]

        heading = _extract_heading(block)
        body = block.strip()

        covers = _parse_covers(body)
        explicit_role = _parse_explicit_role(body)
        role = explicit_role if explicit_role is not None else _autodetect_role(body)
        agent = f"mb-{role}"
        dod_lines, status = _parse_dod(body)

        # C1 default for Blocked-by is the previous block; empty for the first.
        default_blocked: tuple[str, ...] = () if prev_no is None else (str(prev_no),)
        stage, blocked_by, scope, eval_obj, budget = _parse_v2_fields(body, default_blocked)

        items.append(
            WorkItem(
                source=source,
                topic=topic,
                item_no=item_no,
                kind=kind,
                heading=heading,
                body=body,
                role=role,
                agent=agent,
                status=status,
                covers=covers,
                dod_lines=dod_lines,
                stage=stage,
                blocked_by=blocked_by,
                scope=scope,
                eval=eval_obj,
                budget=budget,
                role_explicit=explicit_role is not None,
            )
        )
        prev_no = item_no

    return items


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def _work_item_to_dict(item: WorkItem) -> dict:
    """Convert WorkItem to a JSON-serialisable dict (tuples → lists)."""
    d = asdict(item)
    d["covers"] = list(d["covers"])
    d["dod_lines"] = list(d["dod_lines"])
    d["blocked_by"] = list(d["blocked_by"])
    d["scope"] = list(d["scope"])
    return d


def main() -> None:
    """CLI: print one JSON object per line to stdout."""
    if len(sys.argv) != 2:
        print("Usage: mb_work_items.py <path>", file=sys.stderr)
        sys.exit(1)

    path = pathlib.Path(sys.argv[1])
    if not path.exists():
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    try:
        items = parse_work_items(path)
    except MalformedTaskField as exc:
        print(f"Error: malformed task field: {exc}", file=sys.stderr)
        sys.exit(2)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    for item in items:
        print(json.dumps(_work_item_to_dict(item), ensure_ascii=False))


if __name__ == "__main__":
    main()
