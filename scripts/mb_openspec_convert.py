#!/usr/bin/env python3
"""Deterministic converter — :class:`OSChange` → Memory Bank spec-triple strings.

``convert()`` never touches disk; it only returns three Markdown strings
(requirements.md, design.md, tasks.md). The format is a fixed skeleton
(headers, ``- **REQ-NNN**``, ``<!-- openspec-req: ... -->``,
``<!-- mb-task:N -->``) — 100% template-driven, no LLM involvement in this
core path (REQ-002, REQ-006, REQ-009, D-04).

``prior_triple`` (anchor reuse across re-import, D-06) and ``normalize`` (LLM
slot filling, D-03/D-04) are accepted for interface stability but are seams
reserved for T5/T6 — this core path always renders the deterministic
skeleton.
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


def anchor_safe(name: str) -> str:
    """Neutralize HTML-comment delimiters inside a value placed in a comment.

    A source requirement name may itself contain `-->` (closes the comment
    early) or `<!--` (opens a nested one) — adversarial/malformed OpenSpec
    input must not be able to forge extra markers (e.g. a fake
    `<!-- mb-task:99 -->`) or leave dangling `-->` text in the output
    (REQ-005). The transform is reversible/non-lossy (HTML-entity-escape the
    delimiter sequences only) and canonical: T5's `anchor_map()` MUST apply
    this same transform to OpenSpec names before matching against anchors
    emitted here, or re-import lookups will miss (see design.md D-06).
    """
    return name.replace("<!--", "&lt;!--").replace("-->", "--&gt;")


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


def _build_requirements(ch: OSChange) -> str:
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
    for req in ch.requirements:
        if req.change_kind == "removed":
            continue  # becomes a design.md "Removed scope" note instead (REQ-004)
        if req.change_kind == "renamed":
            print(
                f"[warn] RENAMED requirement '{req.name}' deferred to re-import (T5); "
                "not emitted in this import",
                file=sys.stderr,
            )
            continue
        req_no += 1
        req_id = f"REQ-{req_no:03d}"
        text_line = _flatten(req.text) or "(no requirement text provided)"
        pattern = _classify_pattern(text_line)
        safe_name = anchor_safe(req.name)
        if safe_name != req.name:
            print(
                f"[warn] requirement name contains comment delimiters; "
                f"neutralized in anchor: '{req.name}'",
                file=sys.stderr,
            )
        # Use the neutralized name everywhere it lands in the emitted Markdown
        # (heading + anchor) — a raw `<!-- mb-task:N -->`-shaped name would be
        # a forged marker regardless of which line it appears on.
        lines.append(f"### Requirement {req_no}: {safe_name}")
        lines.append("")
        lines.append(f"<!-- openspec-req: {safe_name} -->")
        lines.append(f"- **{req_id}** ({pattern}): {text_line}")
        lines.append("")
        scenarios = req.scenarios
        if not scenarios:
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
        lines.append("## OpenSpec Design Notes")
        lines.append("")
        lines.append(_demote_headings(ch.design_md.strip()))
        lines.append("")

    removed = [r for r in ch.requirements if r.change_kind == "removed"]
    if removed:
        lines.append("## Removed scope")
        lines.append("")
        for r in removed:
            lines.append(f"### {r.name}")
            lines.append("")
            lines.append(f"**Reason:** {r.reason or '(no reason recorded)'}")
            lines.append("")

    renamed = [r for r in ch.requirements if r.change_kind == "renamed"]
    if renamed:
        lines.append("## Deferred renames (re-import required)")
        lines.append("")
        for r in renamed:
            lines.append(
                f"- `{r.renamed_from}` -> `{r.name}` — anchor move handled on re-import (T5)."
            )
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def _build_tasks(ch: OSChange) -> str:
    lines = [
        f"# Tasks: {ch.change_id}",
        "",
        f"> Imported from OpenSpec change `{ch.change_id}` tasks.md.",
        "",
    ]
    if not ch.task_groups:
        lines.append("_(no tasks.md found in the source change)_")
        return "\n".join(lines).rstrip() + "\n"

    for group in ch.task_groups:
        lines.append(f"<!-- mb-task:{group.number} -->")
        lines.append(f"## Task {group.number}: {group.title}")
        lines.append("")
        lines.append("**Covers:** N/A")
        lines.append("**Role:** backend")
        lines.append("")
        for checked, item_text in group.items:
            if checked is None:
                lines.append(f"- {item_text}")
            else:
                mark = "x" if checked else " "
                lines.append(f"- [{mark}] {item_text}")
        lines.append("")

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
) -> tuple[str, str, str]:
    """Convert a parsed OpenSpec change into (requirements_md, design_md, tasks_md).

    Pure function — returns strings only, never writes to disk (REQ-003).
    ``prior_triple``/``normalize`` are accepted for interface stability but are
    unused seams: anchor reuse across re-import is T5, ``--normalize`` LLM
    slot-filling is T6. This core path always emits the deterministic skeleton.
    """
    del prior_triple, normalize
    requirements_md = _build_requirements(ch)
    design_md = _build_design(ch)
    tasks_md = _build_tasks(ch)
    _run_ears_warn(requirements_md, ch.change_id)
    return requirements_md, design_md, tasks_md
