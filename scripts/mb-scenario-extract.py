#!/usr/bin/env python3
"""Extract GIVEN/WHEN/THEN acceptance scenarios into a normalized test-plan.

Scenarios are an OPT-IN, additive layer on top of EARS requirements. They live
in a spec's ``requirements.md`` (or any Markdown file) inside marker blocks that
mirror the ``<!-- mb-task:N -->`` convention::

    <!-- mb-scenario:1 -->
    ### Scenario: Account lockout after repeated failures
    **Covers:** REQ-006

    - GIVEN an account with N failed attempts within the lockout window
    - WHEN another authentication attempt is made
    - THEN the system locks further attempts for the cooldown period
    - AND an audit event is recorded
    <!-- /mb-scenario:1 -->

The closing ``<!-- /mb-scenario:N -->`` is optional; a block runs until the next
``<!-- mb-scenario:M -->`` marker or end of file.

Each scenario becomes one machine-readable test-plan item. ``/mb work`` and
``/mb plan`` feed these to qa/dev agents, who write one real test per scenario in
the project's own stack (Go, TS, ...). The scenario list — not generated code —
is the source of truth, so the layer stays language-agnostic.

Public API
----------
parse_scenarios(path) -> list[Scenario]
validate_scenarios(scenarios) -> list[str]   # structural problems, empty = ok

CLI
---
    python3 scripts/mb-scenario-extract.py <path>              # JSON Lines (test-plan)
    python3 scripts/mb-scenario-extract.py --validate <path>   # exit 1 + messages if malformed

Exit codes:
    0 — parsed (or validated clean)
    1 — --validate found malformed scenarios (messages on stderr)
    2 — usage error / file not found
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import asdict, dataclass

_SCENARIO_RE = re.compile(r"<!--\s*mb-scenario:(\d+)\s*-->")
_CLOSE_RE = re.compile(r"<!--\s*/\s*mb-scenario:\d+\s*-->")
_HEADING_RE = re.compile(r"^#{1,6}\s*Scenario:\s*(.+?)\s*$", re.IGNORECASE)
_COVERS_RE = re.compile(r"^\*\*covers:\*\*\s*(.+)$", re.IGNORECASE)
# A step bullet: optional "- ", then a GIVEN/WHEN/THEN/AND/BUT keyword.
_STEP_RE = re.compile(
    r"^\s*[-*]?\s*\*{0,2}(GIVEN|WHEN|THEN|AND|BUT)\b\*{0,2}\s*[:]?\s*(.*)$",
    re.IGNORECASE,
)
_SLUG_RE = re.compile(r"[^a-z0-9]+")


@dataclass(frozen=True)
class Scenario:
    """One acceptance scenario parsed from a spec."""

    scenario_no: int
    name: str
    covers: tuple[str, ...]
    given: tuple[str, ...]
    when: tuple[str, ...]
    then: tuple[str, ...]
    extra: tuple[str, ...]  # AND/BUT continuation steps
    test_id: str


def _slug(text: str) -> str:
    s = _SLUG_RE.sub("_", text.strip().lower()).strip("_")
    return s or "scenario"


def _parse_block(no: int, block: str) -> Scenario:
    name = ""
    covers: list[str] = []
    given: list[str] = []
    when: list[str] = []
    then: list[str] = []
    extra: list[str] = []

    for raw in block.splitlines():
        line = raw.strip()
        if not line:
            continue
        if not name:
            mh = _HEADING_RE.match(line)
            if mh:
                name = mh.group(1).strip()
                continue
        mc = _COVERS_RE.match(line)
        if mc:
            covers = [v.strip().upper() for v in mc.group(1).split(",") if v.strip()]
            continue
        ms = _STEP_RE.match(line)
        if ms:
            kw = ms.group(1).upper()
            text = ms.group(2).strip()
            if kw == "GIVEN":
                given.append(text)
            elif kw == "WHEN":
                when.append(text)
            elif kw == "THEN":
                then.append(text)
            else:  # AND / BUT — continuation of the most recent clause
                extra.append(text)

    first_req = covers[0] if covers else "REQ-NA"
    test_id = f"{first_req}__{_slug(name)}" if name else f"{first_req}__scenario_{no}"

    return Scenario(
        scenario_no=no,
        name=name,
        covers=tuple(covers),
        given=tuple(given),
        when=tuple(when),
        then=tuple(then),
        extra=tuple(extra),
        test_id=test_id,
    )


def parse_scenarios(path: pathlib.Path) -> list[Scenario]:
    """Parse ``<!-- mb-scenario:N -->`` blocks from a Markdown file."""
    text = path.read_text(encoding="utf-8")
    if not _SCENARIO_RE.search(text):
        return []

    parts = _SCENARIO_RE.split(text)
    # parts = [preamble, no1, block1, no2, block2, ...]
    scenarios: list[Scenario] = []
    pair_count = (len(parts) - 1) // 2
    for i in range(pair_count):
        no = int(parts[1 + i * 2])
        block = parts[2 + i * 2]
        # Drop a trailing close marker and anything after it within the block.
        m_close = _CLOSE_RE.search(block)
        if m_close:
            block = block[: m_close.start()]
        scenarios.append(_parse_block(no, block))
    return scenarios


def validate_scenarios(scenarios: list[Scenario]) -> list[str]:
    """Return a list of structural problems; empty list means all well-formed."""
    problems: list[str] = []
    for s in scenarios:
        label = f"scenario {s.scenario_no}"
        if not s.name:
            problems.append(f"{label} missing '### Scenario: <name>' heading")
        if not s.covers:
            problems.append(f"{label} missing '**Covers:** REQ-...' field")
        if not s.given:
            problems.append(f"{label} ({s.name or '?'}) missing a GIVEN step")
        if not s.when:
            problems.append(f"{label} ({s.name or '?'}) missing a WHEN step")
        if not s.then:
            problems.append(f"{label} ({s.name or '?'}) missing a THEN step")
    return problems


def _to_dict(s: Scenario) -> dict:
    d = asdict(s)
    for key in ("covers", "given", "when", "then", "extra"):
        d[key] = list(d[key])
    return d


def main() -> None:
    args = sys.argv[1:]
    validate = False
    if args and args[0] == "--validate":
        validate = True
        args = args[1:]
    if len(args) != 1:
        print("Usage: mb-scenario-extract.py [--validate] <path>", file=sys.stderr)
        sys.exit(2)

    path = pathlib.Path(args[0])
    if not path.exists():
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(2)

    scenarios = parse_scenarios(path)

    if validate:
        problems = validate_scenarios(scenarios)
        for p in problems:
            print(f"[scenario] {p}", file=sys.stderr)
        sys.exit(1 if problems else 0)

    for s in scenarios:
        print(json.dumps(_to_dict(s), ensure_ascii=False))


if __name__ == "__main__":
    main()
