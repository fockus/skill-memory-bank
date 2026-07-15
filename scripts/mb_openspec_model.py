#!/usr/bin/env python3
"""Dataclasses shared by the OpenSpec adapter's parser and converter.

Shapes mirror `.memory-bank/specs/openspec-adapter/design.md` § Interfaces.
Stdlib only — no OpenSpec/Memory Bank IO happens here, these are pure data
carriers.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class OSScenario:
    """One ``#### Scenario: <name>`` block.

    ``steps`` preserves keyword order as written, e.g.
    ``[("WHEN", "..."), ("THEN", "...")]``. GIVEN/AND/BUT are accepted too.
    """

    name: str
    steps: list[tuple[str, str]] = field(default_factory=list)


@dataclass
class OSRequirement:
    """One ``### Requirement: <name>`` body, tagged with its delta section."""

    name: str
    text: str
    change_kind: str  # "added" | "modified" | "removed" | "renamed"
    reason: str | None = None  # REMOVED only (`**Reason**:`)
    renamed_from: str | None = None  # RENAMED only (the `FROM:` name)
    scenarios: list[OSScenario] = field(default_factory=list)


@dataclass
class OSTaskGroup:
    """One ``## N. <Group>`` section parsed from ``tasks.md``."""

    number: str
    title: str
    # (True/False, text) for a checkbox item; (None, text) for a non-checkbox
    # line, which REQ-013 still imports as plain checklist text + a warning.
    items: list[tuple[bool | None, str]] = field(default_factory=list)


@dataclass
class OSChange:
    """A parsed OpenSpec change directory — read-only, never written to."""

    change_id: str
    why: str
    what_changes: str
    design_md: str | None
    requirements: list[OSRequirement] = field(default_factory=list)
    task_groups: list[OSTaskGroup] = field(default_factory=list)
    source_hash: str = ""
