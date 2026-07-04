"""Canonical loader for the Memory Bank code graph (``graph.json``, JSON Lines).

Single source of truth for parsing ``<mb>/codebase/graph.json`` into
``(nodes, edges)`` split by record ``type``. Raises ``FileNotFoundError`` when the
file is absent and ``ValueError`` (with the offending line number) on a malformed
line. Callers that prefer warnings over exceptions — e.g. code-context evidence
packs — wrap this and translate the exceptions.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

JsonObj = dict[str, Any]


def load_graph(path: Path) -> tuple[list[JsonObj], list[JsonObj]]:
    """Parse a JSON-Lines graph file → ``(nodes, edges)``.

    Blank lines and records whose ``type`` is neither ``node`` nor ``edge`` are
    ignored. Order is preserved.
    """
    if not path.is_file():
        raise FileNotFoundError(str(path))

    nodes: list[JsonObj] = []
    edges: list[JsonObj] = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                record = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"line {line_number}: {exc.msg}") from exc
            record_type = record.get("type")
            if record_type == "node":
                nodes.append(record)
            elif record_type == "edge":
                edges.append(record)
    return nodes, edges


def read_meta(path: Path) -> JsonObj | None:
    """Return the graph's freshness stamp (the leading ``meta`` row) or ``None``.

    Reads only the FIRST non-blank line: if it parses to a JSON object with
    ``type == "meta"`` the record is returned, otherwise ``None``. Any error
    (missing file, malformed line) fails open to ``None`` — freshness checks must
    never raise on a legacy or truncated graph.
    """
    try:
        with path.open(encoding="utf-8") as stream:
            for line in stream:
                stripped = line.strip()
                if not stripped:
                    continue
                record = json.loads(stripped)
                if isinstance(record, dict) and record.get("type") == "meta":
                    return record
                return None
    except (OSError, json.JSONDecodeError):
        return None
    return None
