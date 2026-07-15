#!/usr/bin/env python3
"""Read-only OpenSpec change parser.

``parse_change(change_dir)`` reads ``proposal.md``, an optional ``design.md``,
delta specs under ``specs/*/spec.md`` and ``tasks.md``, and returns a fully
populated :class:`OSChange`. Nothing is ever written here (REQ-003, NFR-002) —
this module only opens files for reading.

Parsing is defensive: an unrecognised/malformed marker is skipped with a
stderr warning rather than raising, so one broken section never aborts the
whole import (see design.md § Risks).
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

try:
    from mb_openspec_model import OSChange, OSRequirement, OSScenario, OSTaskGroup
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSChange, OSRequirement, OSScenario, OSTaskGroup

_SECTION2_RE = re.compile(r"^## (.+?)\s*$", re.MULTILINE)
_DELTA_SECTION_RE = re.compile(
    r"^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements\s*$", re.MULTILINE
)
_REQ_HEADER_RE = re.compile(r"^### Requirement: (.+?)\s*$", re.MULTILINE)
_SCENARIO_HEADER_RE = re.compile(r"^#### Scenario: (.+?)\s*$", re.MULTILINE)
_STEP_RE = re.compile(
    r"^\s*[-*]?\s*\*{0,2}(GIVEN|WHEN|THEN|AND|BUT)\b\*{0,2}\s*:?\s*(.*)$",
    re.IGNORECASE,
)
_REASON_RE = re.compile(r"^\*\*Reason\*\*:\s*(.+)$", re.IGNORECASE | re.MULTILINE)
_RENAME_FROM_RE = re.compile(
    r"^\s*-?\s*FROM:\s*`?(?:###\s*Requirement:\s*)?(.+?)`?\s*$",
    re.IGNORECASE | re.MULTILINE,
)
_RENAME_TO_RE = re.compile(
    r"^\s*-?\s*TO:\s*`?(?:###\s*Requirement:\s*)?(.+?)`?\s*$",
    re.IGNORECASE | re.MULTILINE,
)
_TASK_GROUP_RE = re.compile(r"^## (\d+)\.\s+(.+?)\s*$", re.MULTILINE)
_CHECKBOX_RE = re.compile(r"^\s*-\s*\[( |x|X)\]\s+(.+?)\s*$")


def _section(text: str, header: str) -> str:
    """Extract the body of a top-level ``## <header>`` section."""
    pattern = re.compile(rf"^## {re.escape(header)}\s*$", re.MULTILINE)
    m = pattern.search(text)
    if not m:
        return ""
    start = m.end()
    nxt = _SECTION2_RE.search(text, start)
    end = nxt.start() if nxt else len(text)
    return text[start:end].strip()


def _split_scenarios(block: str) -> tuple[list[OSScenario], str]:
    """Split a requirement body into (scenarios, prose-before-first-scenario)."""
    headers = list(_SCENARIO_HEADER_RE.finditer(block))
    if not headers:
        return [], block.strip()
    prose = block[: headers[0].start()].strip()
    scenarios: list[OSScenario] = []
    for idx, hm in enumerate(headers):
        name = hm.group(1).strip()
        start = hm.end()
        end = headers[idx + 1].start() if idx + 1 < len(headers) else len(block)
        sbody = block[start:end]
        steps: list[tuple[str, str]] = []
        for line in sbody.splitlines():
            sm = _STEP_RE.match(line)
            if sm:
                steps.append((sm.group(1).upper(), sm.group(2).strip()))
        scenarios.append(OSScenario(name=name, steps=steps))
    return scenarios, prose


def _parse_requirement_blocks(body: str, change_kind: str, spec_file: Path) -> list[OSRequirement]:
    headers = list(_REQ_HEADER_RE.finditer(body))
    reqs: list[OSRequirement] = []
    for idx, hm in enumerate(headers):
        name = hm.group(1).strip()
        start = hm.end()
        end = headers[idx + 1].start() if idx + 1 < len(headers) else len(body)
        block = body[start:end]
        scenarios, prose = _split_scenarios(block)
        reason = None
        if change_kind == "removed":
            rm = _REASON_RE.search(block)
            reason = rm.group(1).strip() if rm else None
            if reason is None:
                print(
                    f"[warn] {spec_file}: REMOVED requirement '{name}' has no **Reason**",
                    file=sys.stderr,
                )
        reqs.append(
            OSRequirement(
                name=name,
                text=prose,
                change_kind=change_kind,
                reason=reason,
                scenarios=scenarios,
            )
        )
    return reqs


def _parse_renamed_block(body: str, spec_file: Path) -> list[OSRequirement]:
    froms = _RENAME_FROM_RE.findall(body)
    tos = _RENAME_TO_RE.findall(body)
    if not froms or not tos or len(froms) != len(tos):
        print(
            f"[warn] {spec_file}: malformed RENAMED Requirements block, skipped",
            file=sys.stderr,
        )
        return []
    out: list[OSRequirement] = []
    for old_name, new_name in zip(froms, tos, strict=True):
        out.append(
            OSRequirement(
                name=new_name.strip(),
                text=f"Renamed from '{old_name.strip()}' to '{new_name.strip()}'.",
                change_kind="renamed",
                renamed_from=old_name.strip(),
            )
        )
    return out


def _parse_delta_spec(spec_file: Path) -> list[OSRequirement]:
    text = spec_file.read_text(encoding="utf-8")
    out: list[OSRequirement] = []
    sections = list(_DELTA_SECTION_RE.finditer(text))
    for idx, m in enumerate(sections):
        kind_word = m.group(1)
        start = m.end()
        end = sections[idx + 1].start() if idx + 1 < len(sections) else len(text)
        body = text[start:end]
        if kind_word == "RENAMED":
            out.extend(_parse_renamed_block(body, spec_file))
            continue
        out.extend(_parse_requirement_blocks(body, kind_word.lower(), spec_file))
    return out


def _parse_tasks(text: str) -> list[OSTaskGroup]:
    headers = list(_TASK_GROUP_RE.finditer(text))
    groups: list[OSTaskGroup] = []
    for idx, hm in enumerate(headers):
        number = hm.group(1)
        title = hm.group(2).strip()
        start = hm.end()
        end = headers[idx + 1].start() if idx + 1 < len(headers) else len(text)
        block = text[start:end]
        items: list[tuple[bool | None, str]] = []
        for raw_line in block.splitlines():
            line = raw_line.rstrip()
            if not line.strip():
                continue
            cm = _CHECKBOX_RE.match(line)
            if cm:
                checked = cm.group(1).lower() == "x"
                items.append((checked, cm.group(2)))
                continue
            stripped = line.strip()
            if stripped.startswith(("-", "*")):
                text_only = stripped.lstrip("-* ").strip()
                print(
                    f"[warn] non-checkbox task line in group {number}: {text_only!r}",
                    file=sys.stderr,
                )
                items.append((None, text_only))
        groups.append(OSTaskGroup(number=number, title=title, items=items))
    return groups


def _source_files(change_dir: Path) -> list[Path]:
    """Every file this parser reads, in a stable (sorted) order (REQ-014)."""
    candidates: list[Path] = []
    for name in ("proposal.md", "design.md", "tasks.md"):
        f = change_dir / name
        if f.is_file():
            candidates.append(f)
    specs_dir = change_dir / "specs"
    if specs_dir.is_dir():
        candidates.extend(specs_dir.glob("*/spec.md"))
    return sorted(candidates, key=lambda p: p.relative_to(change_dir).as_posix())


def compute_source_hash(change_dir: Path) -> str:
    """SHA256 over the change's source files, path + content, sorted order."""
    h = hashlib.sha256()
    for f in _source_files(change_dir):
        rel = f.relative_to(change_dir).as_posix()
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        h.update(f.read_bytes())
        h.update(b"\0")
    return h.hexdigest()


def parse_change(change_dir: Path) -> OSChange:
    """Parse an OpenSpec change directory into an :class:`OSChange` (read-only)."""
    change_dir = Path(change_dir)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec change dir not found: {change_dir}")

    why = ""
    what_changes = ""
    proposal_path = change_dir / "proposal.md"
    if proposal_path.is_file():
        proposal_text = proposal_path.read_text(encoding="utf-8")
        why = _section(proposal_text, "Why")
        what_changes = _section(proposal_text, "What Changes")
    else:
        print(f"[warn] {change_dir}: missing proposal.md", file=sys.stderr)

    design_path = change_dir / "design.md"
    design_md = design_path.read_text(encoding="utf-8") if design_path.is_file() else None

    requirements: list[OSRequirement] = []
    specs_dir = change_dir / "specs"
    if specs_dir.is_dir():
        for spec_file in sorted(specs_dir.glob("*/spec.md")):
            requirements.extend(_parse_delta_spec(spec_file))

    tasks_path = change_dir / "tasks.md"
    task_groups: list[OSTaskGroup] = []
    if tasks_path.is_file():
        task_groups = _parse_tasks(tasks_path.read_text(encoding="utf-8"))

    return OSChange(
        change_id=change_dir.name,
        why=why,
        what_changes=what_changes,
        design_md=design_md,
        requirements=requirements,
        task_groups=task_groups,
        source_hash=compute_source_hash(change_dir),
    )
