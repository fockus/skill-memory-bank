#!/usr/bin/env python3
"""Publish planned bank writes of the OpenSpec adapter.

``write_topic`` writes one topic in the crash-safe order (F7, R1): design.md ->
backlog orphans -> tasks.md -> sidecar -> requirements.md (the hash) last.
``publish_topics`` is the batch-``sync`` transaction (REQ-036): it re-reads every
topic's triple under the bank lock, stages every new file as a temp file next to
its target, and only then renames them all; any failure before the renames
removes the temp files and leaves every topic untouched.
"""

from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path

try:
    import mb_openspec_bank as bank_io
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mb_openspec_bank as bank_io

from mb_fs_atomic import _target_mode
from mb_openspec_bank import Writer
from mb_openspec_sync import SIDECAR_NAME, Triple


def topic_files(spec_dir: Path, new: Triple, old: Triple | None, sidecar: str) -> list:
    """``(name, new text, prior text)`` in the crash-safe write order."""
    sidecar_path = spec_dir / SIDECAR_NAME
    old_sidecar = sidecar_path.read_text("utf-8") if old and sidecar_path.is_file() else None
    return [
        ("design.md", new[1], old[1] if old else None),
        ("tasks.md", new[2], old[2] if old else None),
        (SIDECAR_NAME, sidecar, old_sidecar),
        ("requirements.md", new[0], old[0] if old else None),
    ]


def write_topic(
    *,
    mb_path: Path,
    spec_dir: Path,
    topic: str,
    new: Triple,
    old: Triple | None,
    sidecar: str,
    orphans: list[str],
    source_hash: str,
    write: Writer,
) -> None:
    """Write the changed files of one topic in the crash-safe order."""
    for name, text, prior in topic_files(spec_dir, new, old, sidecar):
        if name == "tasks.md" and orphans:
            bank_io.append_orphans_to_backlog(mb_path, topic, orphans, source_hash, write=write)
        if text != prior:
            dest = spec_dir / name
            bank_io.assert_within(mb_path, dest)
            write(dest, text)


def publish_topics(pending: list[dict], write: Writer) -> None:
    """All-or-nothing publication of several topics' planned writes."""
    staged: list[tuple[Path, Path]] = []
    tag = uuid.uuid4().hex[:8]

    def stage(mb_path: Path, dest: Path, text: str) -> None:
        bank_io.assert_within(mb_path, dest)
        tmp = dest.with_name(f".{dest.name}.{tag}.staged")
        staged.append((tmp, dest))
        write(tmp, text)
        os.chmod(tmp, _target_mode(dest))  # keep the destination's mode, before any rename

    try:
        backlog: dict[Path, str] = {}
        for p in pending:
            if bank_io.read_prior_triple(p["spec_dir"]) != p["old"]:
                raise RuntimeError(f"{p['spec_dir']} changed during sync; nothing written")
            path = p["mb_path"] / "backlog.md"
            if p["orphans"]:
                current = backlog.get(path) or (path.read_text("utf-8") if path.is_file() else None)
                text = bank_io.backlog_with_orphans(
                    current, p["topic"], p["orphans"], p["source_hash"]
                )
                backlog[path] = text if text is not None else (current or "")
        for path, text in backlog.items():
            stage(path.parent, path, text)
        for p in pending:
            for name, text, prior in topic_files(p["spec_dir"], p["new"], p["old"], p["sidecar"]):
                if text != prior:
                    stage(p["mb_path"], p["spec_dir"] / name, text)
    except BaseException:
        for tmp, _dest in staged:
            tmp.unlink(missing_ok=True)
        raise
    for tmp, dest in staged:
        os.replace(tmp, dest)
