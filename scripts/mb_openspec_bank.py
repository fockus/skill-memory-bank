#!/usr/bin/env python3
"""Bank-side persistence for the OpenSpec adapter: frontmatter, triple IO, discovery.

Path guards live in ``mb_openspec_paths`` and are re-exported here.

Every function that writes takes the writer as ``write`` (``atomic_write`` in
production) so the CLI keeps one patchable seam for crash-consistency tests.
"""

from __future__ import annotations

import contextlib
import re
import sys
from collections.abc import Callable
from pathlib import Path

try:
    from mb_fs_atomic import _dir_lock
    from mb_openspec_paths import (
        assert_topic_dir_not_symlink_escape,
        assert_within,
        resolve_stored_source,
        slugify,
        stable_source_path,
        validate_topic_slug,
    )
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_fs_atomic import _dir_lock
    from mb_openspec_paths import (
        assert_topic_dir_not_symlink_escape,
        assert_within,
        resolve_stored_source,
        slugify,
        stable_source_path,
        validate_topic_slug,
    )

__all__ = [
    "assert_topic_dir_not_symlink_escape",
    "assert_within",
    "resolve_stored_source",
    "slugify",
    "stable_source_path",
    "validate_topic_slug",
]

Writer = Callable[[Path, str], None]
_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def inject_frontmatter(requirements_md: str, source: str, source_hash: str) -> str:
    """Record the source change path + content hash (REQ-014)."""
    frontmatter = f"---\nopenspec_source: {source}\nopenspec_hash: {source_hash}\n---\n\n"
    return frontmatter + requirements_md


def read_prior_triple(spec_dir: Path) -> tuple[str, str, str] | None:
    """Read a previously-written spec triple for re-import (read-only, T5).

    ``None`` when this is a fresh import — a requirements.md/tasks.md pair
    must already exist under ``spec_dir`` for a re-import to engage.
    """
    req_path = spec_dir / "requirements.md"
    tasks_path = spec_dir / "tasks.md"
    if not req_path.is_file() or not tasks_path.is_file():
        return None
    design_path = spec_dir / "design.md"
    design_md = design_path.read_text(encoding="utf-8") if design_path.is_file() else ""
    return (
        req_path.read_text(encoding="utf-8"),
        design_md,
        tasks_path.read_text(encoding="utf-8"),
    )


def orphan_backlog_marker(topic: str, source_hash: str) -> str:
    """The idempotency key for one orphan-append (R1, Codex round-2)."""
    return f"<!-- openspec-orphans: {topic}@{source_hash[:12]} -->"


def append_orphans_to_backlog(
    mb_path: Path, topic: str, orphaned_task_lines: list[str], source_hash: str, *, write: Writer
) -> None:
    """REQ-017 — a previously-imported task that vanished from the OpenSpec
    source on re-import is never silently dropped; append it to
    ``backlog.md`` with a note instead of losing it (idempotent, R1).
    """
    backlog_path = mb_path / "backlog.md"
    assert_within(mb_path, backlog_path)
    existing = backlog_path.read_text(encoding="utf-8") if backlog_path.is_file() else None
    text = backlog_with_orphans(existing, topic, orphaned_task_lines, source_hash)
    if text is not None:
        write(backlog_path, text)


def backlog_with_orphans(
    existing: str | None, topic: str, orphaned_task_lines: list[str], source_hash: str
) -> str | None:
    """``backlog.md`` text with the orphan note appended; ``None`` when nothing changes.

    Keyed by ``<!-- openspec-orphans: <topic>@<hash12> -->``: a retried import for
    the same topic and source hash never duplicates the note.
    """
    existing = "# Backlog\n" if existing is None else existing
    marker = orphan_backlog_marker(topic, source_hash)
    if marker in existing:
        return None
    if not existing.endswith("\n"):
        existing += "\n"
    note_lines = [
        "",
        marker,
        f"## Orphaned OpenSpec tasks — {topic}",
        "",
        (
            f"_(previously imported into `specs/{topic}/tasks.md`; no longer present in "
            f"the OpenSpec source as of re-import hash `{source_hash[:12]}` — "
            "re-check before discarding.)_"
        ),
        "",
        *orphaned_task_lines,
        "",
    ]
    return existing + "\n".join(note_lines)


@contextlib.contextmanager
def bank_lock(mb_path: Path):
    """Hold one exclusive lock on ``<bank>/specs`` for a whole OpenSpec bank write.

    Reuses ``mb_fs_atomic._dir_lock`` (``flock`` on the directory descriptor: no
    lock file, released by the kernel on exit or crash). A second ``import``,
    ``sync`` or ``export`` waits until the first finishes.
    """
    specs = Path(mb_path) / "specs"
    if not Path(mb_path).is_dir():
        yield  # the operation itself reports the missing bank; nothing can be written
        return
    specs.mkdir(exist_ok=True)
    with _dir_lock(str(specs if specs.is_dir() else mb_path)) as locked:
        if not locked:
            raise RuntimeError(f"cannot take the OpenSpec bank lock on {mb_path}; nothing written")
        yield


def parse_frontmatter(text: str) -> dict[str, str]:
    """Parse the flat ``key: value`` frontmatter block written by
    ``inject_frontmatter`` (``openspec_source``/``openspec_hash``, REQ-014).

    Read-only, best-effort: an absent/malformed block yields ``{}`` rather
    than raising, so `list`/`status`/`sync` degrade to "not-imported" instead
    of crashing on a hand-edited requirements.md.
    """
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict[str, str] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def iter_imported_topics(mb_path: Path) -> list[tuple[str, Path, dict[str, str]]]:
    """Every ``specs/<topic>/`` that carries ``openspec_source`` frontmatter,
    i.e. every topic previously produced by ``import`` (read-only)."""
    specs_dir = mb_path / "specs"
    out: list[tuple[str, Path, dict[str, str]]] = []
    if not specs_dir.is_dir():
        return out
    for topic_dir in sorted(p for p in specs_dir.iterdir() if p.is_dir()):
        req_path = topic_dir / "requirements.md"
        if not req_path.is_file():
            continue
        fm = parse_frontmatter(req_path.read_text(encoding="utf-8"))
        if "openspec_source" not in fm:
            continue
        out.append((topic_dir.name, topic_dir, fm))
    return out


def discover_openspec_changes(openspec_root: Path, *, include_archive: bool) -> list[Path]:
    """Enumerate ``<openspec_root>/openspec/changes/*`` (read-only, REQ-019).

    ``changes/archive/**`` is skipped unless ``include_archive`` (OQ-3) — each
    direct child of ``archive/`` is itself an archived change directory
    (``archive/YYYY-MM-DD-<name>/``).
    """
    changes_dir = Path(openspec_root) / "openspec" / "changes"
    if not changes_dir.is_dir():
        return []
    out: list[Path] = []
    for child in sorted(p for p in changes_dir.iterdir() if p.is_dir()):
        if child.name == "archive":
            if include_archive:
                out.extend(sorted(p for p in child.iterdir() if p.is_dir()))
            continue
        out.append(child)
    return out


def set_frontmatter_hash(requirements_md: str, source: str, source_hash: str) -> str:
    """Record ``openspec_source``/``openspec_hash``, replacing an existing pair."""
    m = _FRONTMATTER_RE.match(requirements_md)
    if m is None:
        return inject_frontmatter(requirements_md, source, source_hash)
    kept = [
        ln
        for ln in m.group(1).splitlines()
        if not ln.startswith(("openspec_source:", "openspec_hash:"))
    ]
    block = "\n".join([*kept, f"openspec_source: {source}", f"openspec_hash: {source_hash}"])
    return f"---\n{block}\n---\n" + requirements_md[m.end() :]


def load_topic(mb_path: Path, topic: str) -> tuple[Path, dict[str, str], Path]:
    """``(spec_dir, frontmatter, change_dir)`` of an imported topic, after every guard."""
    validate_topic_slug(topic)
    specs_dir = mb_path / "specs"
    spec_dir = specs_dir / topic
    assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
    req_path = spec_dir / "requirements.md"
    if not req_path.is_file():
        raise FileNotFoundError(f"topic not found or never imported: {topic}")
    fm = parse_frontmatter(req_path.read_text(encoding="utf-8"))
    source = fm.get("openspec_source")
    if not source or not fm.get("openspec_hash"):
        raise RuntimeError(f"topic '{topic}' has no openspec_source/openspec_hash frontmatter")
    change_dir = resolve_stored_source(source, mb_path)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec source no longer exists: {source}")
    return spec_dir, fm, change_dir
