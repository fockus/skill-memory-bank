#!/usr/bin/env python3
"""``list`` and ``status``: read-only OpenSpec import status (REQ-019, OQ-3)."""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import mb_openspec_bank as bank_io
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mb_openspec_bank as bank_io

from mb_openspec_parse import compute_source_hash


def _change_status(change_dir: Path, topics: list, mb_path: Path) -> tuple[str, str | None]:
    change_r = change_dir.resolve()
    for topic, _topic_dir, fm in topics:
        source = fm.get("openspec_source")
        try:
            if not source or bank_io.resolve_stored_source(source, mb_path).resolve() != change_r:
                continue
        except OSError:
            continue
        current = compute_source_hash(change_dir)
        return ("imported" if fm.get("openspec_hash") == current else "drifted"), topic
    return "not-imported", None


def run_list(*, mb_path: Path, openspec_root: Path, include_all: bool) -> list[dict[str, object]]:
    """OpenSpec changes with their import status (read-only, REQ-019, OQ-3)."""
    topics = bank_io.iter_imported_topics(mb_path)
    results: list[dict[str, object]] = []
    for change_dir in bank_io.discover_openspec_changes(openspec_root, include_archive=include_all):
        status, topic = _change_status(change_dir, topics, mb_path)
        results.append(
            {
                "change_id": change_dir.name,
                "path": str(change_dir),
                "status": status,
                "topic": topic,
            }
        )
    return results


def run_status(*, mb_path: Path, topic: str) -> dict[str, object]:
    """Status of one imported topic (read-only, REQ-019)."""
    _spec_dir, fm, change_dir = bank_io.load_topic(mb_path, topic)
    current = compute_source_hash(change_dir)
    stored = fm["openspec_hash"]
    return {
        "topic": topic,
        "source": fm["openspec_source"],
        "status": "imported" if current == stored else "drifted",
        "stored_hash": stored,
        "current_hash": current,
    }
