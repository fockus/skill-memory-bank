#!/usr/bin/env python3
"""Per-unit OpenSpec sync state: the ``specs/<topic>/openspec-sync.json`` sidecar.

A *unit* (AGR-105, ``context/openspec-adapter.md`` § Unit model) is one
requirement (keyed by its anchor), one REMOVED entry, one task group ``N``,
one task item (keyed by its ``N.M`` id, else by group + text), proposal
``## Why`` / ``## What Changes``, or the OpenSpec ``design.md`` as a whole.
Per unit the sidecar stores ``os`` (hash of the raw OpenSpec text) and ``mb``
(hash of our rendering) as of the last sync; a task item also stores both
check-states. Covers/Role, bank-added design sections and task prose are not
units. Pure module: the caller (``mb-openspec.py``) does every write.
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

try:
    from mb_openspec_ids import assign_anchors
    from mb_openspec_model import OSChange
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_ids import assign_anchors
    from mb_openspec_model import OSChange

from mb_openspec_spans import (
    COVERS_PREFIX,
    META_RE,
    SCENARIO_MARK_RE,
    design_spans,
    req_id_of,
    requirement_spans,
    shared_scenarios,
    task_key,
    task_spans,
)

SIDECAR_NAME = "openspec-sync.json"
SIDECAR_FORMAT = 2  # 2: requirement text spans shared scenarios; a format-1 file is re-adopted

Triple = tuple[str, str, str]  # (requirements_md, design_md, tasks_md)

UNKNOWN = "unknown"  # a baseline hash that matches nothing: "this side moved, who knows how"


def unit_hash(text: str) -> str:
    """SHA-256 of a unit's text with trailing whitespace and edge blank lines ignored."""
    canonical = "\n".join(line.rstrip() for line in text.strip().splitlines())
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _clean(lines: list[str]) -> str:
    """Unit text without meta lines and positional scenario markers."""
    kept = [ln for ln in lines if not META_RE.match(ln) and not SCENARIO_MARK_RE.match(ln)]
    return "\n".join(kept).strip()


def _requirement_text(lines: list[str]) -> str:
    """A requirement unit's text: bullet and scenarios, wherever the scenarios sit.

    Blank lines, meta lines, scenario markers and ``**Covers:**`` lines are left
    out, so an inline scenario and a shared one covering the requirement hash alike.
    """
    return "\n".join(
        ln
        for ln in lines
        if ln.strip()
        and not META_RE.match(ln)
        and not SCENARIO_MARK_RE.match(ln)
        and not ln.startswith(COVERS_PREFIX)
    )


def os_units(ch: OSChange) -> dict[str, dict]:
    """Raw OpenSpec text (``os``) plus location metadata per unit key."""
    units: dict[str, dict] = {
        "proposal:why": {"os": ch.why},
        "proposal:what-changes": {"os": ch.what_changes},
    }
    if ch.design_md is not None:
        units["design"] = {"os": ch.design_md}
    for req, anchor in zip(ch.requirements, assign_anchors(ch.requirements), strict=True):
        raw = req.raw or req.text
        if anchor is None:
            units[f"removed:{req.name}"] = {"os": raw, "cap": req.capability, "name": req.name}
            continue
        req_entry = {"os": raw, "cap": req.capability, "kind": req.change_kind, "name": req.name}
        if req.renamed_from:
            req_entry["from"] = req.renamed_from
        units[f"req:{anchor}"] = req_entry
    for group in ch.task_groups:
        units[f"group:{group.number}"] = {"os": group.title}
        for checked, text in group.items:
            entry: dict[str, object] = {"os": text}
            if checked is not None:
                entry["os_checked"] = checked
            units.setdefault(task_key(group.number, text), entry)
    return units


def bank_units(triple: Triple) -> dict[str, dict]:
    """Our rendering (``mb`` text, plus ``mb_checked``) per unit key, read from a triple."""
    units: dict[str, dict] = {}
    req_lines = triple[0].splitlines()
    req_spans = requirement_spans(req_lines)
    shared = shared_scenarios(req_lines, req_spans)
    for key, span in req_spans.items():
        rid = req_id_of(span)
        extra = [ln for a, b, covers in shared if rid in covers for ln in req_lines[a:b]]
        units[key] = {"mb": _requirement_text(span.body + extra)}
    for key, span in design_spans(triple[1].splitlines()).items():
        units.setdefault(key, {"mb": _clean(span.body)})
    for key, span in task_spans(triple[2].splitlines()).items():
        entry: dict = {"mb": span.body[0]}
        if span.checked is not None:
            entry["mb_checked"] = span.checked
        units.setdefault(key, entry)
    return units


def build_sidecar(ch: OSChange, rendered: Triple) -> dict:
    """The sidecar for a bank triple that was rendered from ``ch`` (the sync baseline)."""
    os_side = os_units(ch)
    mb_side = bank_units(rendered)
    units: dict[str, dict] = {}
    for key in sorted(set(os_side) | set(mb_side)):
        os_entry = os_side.get(key, {})
        mb_entry = mb_side.get(key, {})
        entry = {k: v for k, v in os_entry.items() if k != "os"}
        entry["os"] = unit_hash(os_entry["os"]) if "os" in os_entry else None
        entry["mb"] = unit_hash(mb_entry["mb"]) if "mb" in mb_entry else None
        if "mb_checked" in mb_entry:
            entry["mb_checked"] = mb_entry["mb_checked"]
        units[key] = entry
    return {
        "format": SIDECAR_FORMAT,
        "change_id": ch.change_id,
        "openspec_hash": ch.source_hash,
        "units": units,
    }


def sidecar_text(data: dict) -> str:
    return json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def read_sidecar(spec_dir: Path) -> dict | None:
    """The parsed sidecar, or ``None`` when it is missing or unusable (never raises)."""
    path = Path(spec_dir) / SIDECAR_NAME
    if not path.is_file():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        data = None
    if (
        not isinstance(data, dict)
        or data.get("format") != SIDECAR_FORMAT
        or not isinstance(data.get("units"), dict)
    ):
        print(
            f"[warn] {path}: unreadable sync sidecar; a baseline will be adopted", file=sys.stderr
        )
        return None
    return data


def insert_meta_lines(bank_md: str, rendered_md: str) -> str:
    """Add the rendered meta line before each matching anchor/heading the bank lacks it for.

    Only inserts lines — never edits or removes bank text. A target line is
    matched together with its ``## `` section, so a demoted design-notes
    heading never picks up a Removed-scope meta line.
    """
    wanted: dict[tuple[str, str], str] = {}
    section = ""
    prev = ""
    for line in rendered_md.splitlines():
        if line.startswith("## "):
            section = line
        if META_RE.match(prev):
            wanted[(section, line)] = prev
        prev = line
    out: list[str] = []
    section = ""
    for line in bank_md.splitlines():
        if line.startswith("## "):
            section = line
        meta = wanted.get((section, line))
        if meta and not (out and META_RE.match(out[-1])):
            out.append(meta)
        out.append(line)
    return "\n".join(out) + ("\n" if bank_md.endswith("\n") else "")


def synthetic_sidecar(ch: OSChange, bank: Triple, rendered: Triple, *, stored_hash: str) -> dict:
    """A baseline for a topic with no usable sidecar (AGR-105 Q5 B: adopt, never guess).

    A unit equal in the bank and in the fresh rendering is the baseline. A
    differing unit is our edit when the stored ``openspec_hash`` still matches
    the source, and unknown on both sides (a conflict unless resolved) when the
    source moved. A RENAMED requirement the bank lacks was deferred by the
    pre-sidecar importer: its ``mb`` is ``None``, so the sync brings it in.
    A checkbox that differs while the source moved is unknown on both sides too.
    """
    data = build_sidecar(ch, rendered)
    ours, theirs, os_side = bank_units(bank), bank_units(rendered), os_units(ch)
    source_moved = stored_hash != ch.source_hash
    for key in sorted(set(ours) - set(theirs)):
        prose = key.startswith("task:") and "mb_checked" not in ours[key]
        if source_moved and not prose:
            data["units"][key] = {"os": UNKNOWN, "mb": UNKNOWN}
    for key, entry in data["units"].items():
        if key in theirs and key not in ours and os_side.get(key, {}).get("kind") == "renamed":
            entry["mb"] = None
            continue
        mine = ours.get(key)
        differs = mine is None or unit_hash(mine["mb"]) != entry.get("mb")
        if source_moved and differs and entry.get("os") != UNKNOWN:
            entry["os"] = entry["mb"] = UNKNOWN
        ticks = (mine or {}).get("mb_checked"), theirs.get(key, {}).get("mb_checked")
        if source_moved and None not in ticks and ticks[0] != ticks[1]:
            entry["os_checked"] = entry["mb_checked"] = UNKNOWN  # who ticked is unknown
    return data
