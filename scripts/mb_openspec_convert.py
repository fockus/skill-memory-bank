#!/usr/bin/env python3
"""Deterministic converter — :class:`OSChange` → Memory Bank spec-triple strings.

``convert()`` returns three Markdown strings (requirements.md, design.md,
tasks.md) and never writes to disk; it shells out read-only to
``mb-ears-validate.sh`` (warn-mode EARS check) and ``mb-req-next-id.sh``
(REQ-ID allocation on re-import), and touches the normalize cache only when
``normalize=True``. The format is a fixed skeleton (headers, ``- **REQ-NNN**``,
anchors, ``<!-- mb-task:N -->``) — never LLM-generated (REQ-002/006/009, D-04).

``prior_triple`` reuses anchored REQ-IDs and re-anchors RENAMED deltas (D-06,
REQ-016/018; see ``mb_openspec_ids``). ``normalize`` fills only text slots,
cached by source-requirement hash, with deterministic fallbacks (REQ-008/010);
``normalize=False`` is byte-identical to the pre-T6 path (NFR-001). Task
check-state merging is :func:`merge_task_state` (``mb_openspec_tasks``); the
anchor helpers and it are re-exported here for existing callers.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    from mb_openspec_model import OSChange, OSScenario
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSChange, OSScenario

from mb_openspec_ids import (
    _IdAllocator,
    _prior_requirement_index,
    anchor_map,
    anchor_safe,
    assign_anchors,
    meta_line,
)
from mb_openspec_normalize import (
    LlmDispatch,
    NormalizeCache,
    normalize_requirement,
    scenario_from_slot,
)
from mb_openspec_tasks import build_tasks, merge_task_state, task_id

__all__ = [
    "anchor_map",
    "anchor_safe",
    "assign_anchors",
    "convert",
    "merge_task_state",
    "meta_line",
    "task_id",
]

_TRIGGER_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"^when\b", re.IGNORECASE), "event-driven"),
    (re.compile(r"^while\b", re.IGNORECASE), "state-driven"),
    (re.compile(r"^where\b", re.IGNORECASE), "optional"),
    (re.compile(r"^if\b", re.IGNORECASE), "unwanted"),
)


def _flatten(text: str) -> str:
    """Collapse a (possibly multi-line) requirement body into one line."""
    return " ".join(text.split())


def _classify_pattern(text: str) -> str:
    """Auto-classify the EARS pattern from the leading trigger word (REQ-009)."""
    stripped = text.strip()
    for pattern, name in _TRIGGER_PATTERNS:
        if pattern.match(stripped):
            return name
    return "ubiquitous"


def _empty_scenario_stub() -> OSScenario:
    """Deterministic fallback for a requirement with zero scenarios."""
    return OSScenario(
        name="(none provided)",
        steps=[("WHEN", "not specified"), ("THEN", "not specified")],
    )


def _render_scenario(no: int, req_id: str, scenario: OSScenario) -> list[str]:
    lines = [
        f"<!-- mb-scenario:{no} -->",
        f"### Scenario: {scenario.name}",
        f"**Covers:** {req_id}",
        "",
    ]
    for keyword, text in scenario.steps:
        lines.append(f"- {keyword} {text}".rstrip())
    lines.append(f"<!-- /mb-scenario:{no} -->")
    lines.append("")
    return lines


def _build_requirements(
    ch: OSChange,
    prior_map: dict[str, str] | None,
    prior_index: dict[str, tuple[str, str, str]],
    allocator: _IdAllocator | None,
    *,
    normalize: bool = False,
    normalize_cache: NormalizeCache | None = None,
    llm: LlmDispatch | None = None,
) -> str:
    """Render the requirements skeleton.

    A fresh import (no ``prior_map``) numbers requirements in document order
    (NFR-001 golden). A re-import reuses an anchored REQ-ID (D-06), moves a
    RENAMED anchor keeping its ID and prior text (D-07), and allocates the next
    ID for a new name. Each anchor follows its :func:`meta_line` (AGR-105).
    ``normalize`` fills text/scenario/covers slots, never for a RENAMED entry.
    """
    lines = [
        f"# Requirements: {ch.change_id}",
        "",
        f"> Imported from OpenSpec change `{ch.change_id}` — see design.md for Why/What Changes.",
        "> Deterministic skeleton (T2) — REQ-IDs assigned in document order; "
        "`--normalize` (T6) fills text slots.",
        "",
        "## Requirements (EARS)",
        "",
    ]
    req_no = 0
    scenario_no = 0
    for req, anchor_name in zip(ch.requirements, assign_anchors(ch.requirements), strict=True):
        if anchor_name is None:
            continue  # REMOVED becomes a design.md "Removed scope" note instead (REQ-004)

        req_id: str | None = None
        text_line = _flatten(req.text) or "(no requirement text provided)"
        slots: dict[str, object] | None = None
        if normalize and req.change_kind != "renamed" and normalize_cache is not None:
            slots = normalize_requirement(req, cache=normalize_cache, llm=llm)
            slot_text = slots.get("text")
            if isinstance(slot_text, str) and slot_text.strip():
                text_line = slot_text

        if req.change_kind == "renamed":
            # A rename keeps the ID and text of whichever anchor already exists:
            # the FROM name (rename not seen yet) or the TO name (seen before).
            # A pure rename carries no new body text (D-07).
            for key in (anchor_safe(req.renamed_from or ""), anchor_name):
                if key in prior_index:
                    req_id, _pattern, text_line = prior_index[key]
                    break
        elif anchor_name != anchor_safe(req.name):
            print(
                f"[warn] duplicate requirement name '{req.name}'; "
                f"anchor disambiguated to '{anchor_name}'",
                file=sys.stderr,
            )
        if req_id is None and prior_map is not None:
            req_id = prior_map.get(anchor_name)
            if req_id is None:
                assert allocator is not None
                req_id = allocator.allocate()

        req_no += 1
        if req_id is None:
            req_id = f"REQ-{req_no:03d}"  # fresh import: sequential document order
        pattern = _classify_pattern(text_line)
        safe_name = anchor_safe(req.name)
        if safe_name != req.name:
            print(
                f"[warn] requirement name contains comment delimiters; "
                f"neutralized in anchor: '{req.name}'",
                file=sys.stderr,
            )
        # The heading stays readable (no disambiguation suffix); the anchor
        # carries the disambiguated name. Both are neutralized by anchor_safe.
        lines += [f"### Requirement {req_no}: {safe_name}", "", meta_line(req)]
        lines += [
            f"<!-- openspec-req: {anchor_name} -->",
            f"- **{req_id}** ({pattern}): {text_line}",
        ]
        covers = slots.get("covers") if slots else None
        if covers:
            lines.append(f"**Covers:** {', '.join(str(c) for c in covers)}")
        lines.append("")
        scenarios = req.scenarios
        if not scenarios:
            generated = slots.get("scenario") if slots else None
            if generated:
                scenarios = [scenario_from_slot(generated)]
            else:
                print(
                    f"[warn] requirement '{req.name}' has no scenarios; using a deterministic stub",
                    file=sys.stderr,
                )
                scenarios = [_empty_scenario_stub()]
        for scenario in scenarios:
            scenario_no += 1
            lines.extend(_render_scenario(scenario_no, req_id, scenario))
    return "\n".join(lines).rstrip() + "\n"


def _demote_headings(text: str) -> str:
    """Demote every Markdown heading one level (nests under a parent section)."""
    return re.sub(r"(?m)^(#{1,5})(\s)", r"#\1\2", text)


def _build_design(ch: OSChange) -> str:
    lines = [
        f"# Design: {ch.change_id}",
        "",
        "## Why",
        "",
        ch.why or "(not provided)",
        "",
        "## What Changes",
        "",
        ch.what_changes or "(not provided)",
        "",
    ]
    if ch.design_md:
        lines += ["## OpenSpec Design Notes", "", _demote_headings(ch.design_md.strip()), ""]

    removed = [r for r in ch.requirements if r.change_kind == "removed"]
    if removed:
        lines += ["## Removed scope", ""]
        for r in removed:
            lines += [meta_line(r), f"### {r.name}", ""]
            lines += [f"**Reason:** {r.reason or '(no reason recorded)'}", ""]

    return "\n".join(lines).rstrip() + "\n"


def _run_ears_warn(requirements_md: str, change_id: str) -> None:
    """Warn-mode EARS validation over the emitted requirements (REQ-020).

    Never aborts the import — warnings are surfaced to stderr only.
    """
    script = Path(__file__).with_name("mb-ears-validate.sh")
    if not script.is_file():
        return
    try:
        proc = subprocess.run(
            ["bash", str(script), "-"],
            input=requirements_md,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return
    for line in proc.stderr.splitlines():
        if line.strip():
            print(f"[warn][ears:{change_id}] {line}", file=sys.stderr)


def convert(
    ch: OSChange,
    prior_triple: tuple[str, str, str] | None = None,
    normalize: bool = False,
    *,
    topic: str | None = None,
    mb_path: str | Path | None = None,
    llm: LlmDispatch | None = None,
) -> tuple[str, str, str]:
    """Convert a parsed OpenSpec change into (requirements_md, design_md, tasks_md).

    Never writes to disk (REQ-003). ``prior_triple`` enables anchor reuse
    (D-06, REQ-018); its tasks.md is unused here (see :func:`merge_task_state`).
    ``normalize`` fills LLM text slots cached by source-requirement hash with
    deterministic fallbacks (REQ-008/010); ``llm`` overrides the dispatcher in
    tests.
    """
    prior_map: dict[str, str] | None = None
    prior_index: dict[str, tuple[str, str, str]] = {}
    allocator: _IdAllocator | None = None
    if prior_triple is not None:
        prior_index = _prior_requirement_index(prior_triple[0])
        prior_map = {name: info[0] for name, info in prior_index.items()}
        allocator = _IdAllocator(prior_map, topic, mb_path)

    normalize_cache = NormalizeCache(mb_path) if normalize else None
    requirements_md = _build_requirements(
        ch,
        prior_map,
        prior_index,
        allocator,
        normalize=normalize,
        normalize_cache=normalize_cache,
        llm=llm,
    )
    if normalize_cache is not None:
        normalize_cache.flush()
    design_md = _build_design(ch)
    tasks_md = build_tasks(ch)
    _run_ears_warn(requirements_md, ch.change_id)
    return requirements_md, design_md, tasks_md
