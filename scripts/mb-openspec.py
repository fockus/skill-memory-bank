#!/usr/bin/env python3
"""OpenSpec → Memory Bank one-way import adapter (T1-T3 core, T5 re-import,
T4 CLI dispatcher: list/status/sync).

Reads an OpenSpec change directory (``proposal.md`` + optional ``design.md`` +
delta specs ``specs/*/spec.md`` + ``tasks.md``) and writes a Memory Bank spec
triple under ``<bank>/specs/<topic>/``. The OpenSpec tree is never written to
(REQ-003) — every write is asserted to live under the resolved bank path
(NFR-002).

Usage:
    mb-openspec.py import <change_dir> [--as <topic>] [--mb <bank>]
    mb-openspec.py list   [--all] [--openspec <root>] [--mb <bank>]
    mb-openspec.py status <topic> [--mb <bank>]
    mb-openspec.py sync   [<topic>] [--mb <bank>]

Re-import (T5): when ``specs/<topic>/`` already has a requirements.md +
tasks.md from a prior import, they are read (read-only) and passed to
``convert()`` as ``prior_triple`` so REQ-NNN anchors are reused/re-anchored
(D-06, REQ-016/018) instead of renumbered by position, and
``merge_task_state()`` preserves `/mb work` check-state by task text
(REQ-016); any task that vanished from the source is appended to
``backlog.md`` instead of being silently dropped (REQ-017).

``list``/``status``/``sync`` (T4, REQ-001/015/019) discover OpenSpec changes
and drive drift detection from the ``openspec_source``/``openspec_hash``
frontmatter written by ``import`` (REQ-014): a change is ``imported`` when a
spec triple with a matching ``openspec_source`` exists and its stored hash
equals the source's current ``compute_source_hash``, ``drifted`` when the
hashes differ, and ``not-imported`` otherwise. ``sync`` re-imports a topic
only on hash drift (REQ-015) — a hash match is a pure no-op, no write at all.

``--normalize`` on ``import``/``sync`` (T6, REQ-007/008/010) fills LLM text
slots (EARS rewrite, missing scenario, Covers links) via
``mb_openspec_normalize``, cached by source-requirement hash; omitted (the
default) the write path is byte-identical to the pre-T6 deterministic-only
behaviour (NFR-001). See design.md D-03/D-04.

Exit codes:
    0 — command succeeded
    1 — change dir / bank / topic not found, or a write-guard violation
    2 — usage error
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mb_openspec_convert import convert, merge_task_state
from mb_openspec_parse import compute_source_hash, parse_change

_FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)

try:
    from memory_bank_skill._io import atomic_write
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill._io import atomic_write


def _slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "change"


_TOPIC_SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _validate_topic_slug(topic: str) -> None:
    """Reject any topic that is not a single safe path segment (F1, REQ-003/NFR-002).

    ``--as``/``sync``/``status`` topics flow straight into ``spec_dir = mb_path
    / "specs" / topic``; an unvalidated topic (``..``, ``../foo``, ``foo/bar``,
    a backslash, or a control character) can escape ``specs/`` entirely or
    nest where ``sync``/``list`` will never find it. A topic must match
    ``^[A-Za-z0-9][A-Za-z0-9._-]*$`` and contain no path separators.

    R3 (Codex round-2): the regex above still ALLOWS a trailing ``.`` (e.g.
    ``foo.``) — harmless on POSIX but a reserved/ambiguous segment on some
    filesystems and simply not a name anyone means to type; rejected
    explicitly rather than folded into the regex, to keep the regex's error
    message stable for every other case.
    """
    if topic in (".", ".."):
        raise RuntimeError(f"invalid topic: {topic!r} (must not be '.' or '..')")
    if "/" in topic or "\\" in topic:
        raise RuntimeError(f"invalid topic: {topic!r} (must not contain a path separator)")
    if any(ord(c) < 0x20 for c in topic):
        raise RuntimeError(f"invalid topic: {topic!r} (control characters are not allowed)")
    if not _TOPIC_SLUG_RE.match(topic):
        raise RuntimeError(f"invalid topic: {topic!r} (must match {_TOPIC_SLUG_RE.pattern})")
    if topic.endswith("."):
        raise RuntimeError(f"invalid topic: {topic!r} (must not end with '.')")


def _assert_within(base: Path, target: Path) -> None:
    """Hard guard (REQ-003, NFR-002): refuse to write outside ``base``."""
    base_r = base.resolve()
    target_r = target.resolve()
    try:
        target_r.relative_to(base_r)
    except ValueError as exc:
        raise RuntimeError(f"refusing to write outside {base_r}: {target_r}") from exc


def _assert_topic_dir_not_symlink_escape(spec_dir: Path, specs_dir: Path) -> None:
    """Reject a ``specs/<topic>/`` that is itself a symlink escape (R3, Codex
    round-2 residual on F1).

    ``_assert_within(mb_path, spec_dir)`` only guards the BANK root; a
    ``specs/<topic>`` entry that is itself a symlink pointing to some OTHER
    directory still lives (lexically) under the bank and passes that check.
    Likewise, the old ``spec_dir.parent.resolve() != specs_dir.resolve()``
    check resolves the *parent* (``specs_dir`` itself, unaffected by a
    symlinked CHILD) — it never notices that ``spec_dir`` itself is a
    symlink, since resolving a path's parent does not traverse into a
    symlinked last component. This guard checks ``spec_dir`` directly:
    refuse outright if it is a symlink (regardless of target), and refuse if
    its own resolved form does not land immediately under ``specs_dir``.
    Applied before ``import`` writes through a topic dir and before
    ``status``/``sync`` read one.
    """
    if spec_dir.is_symlink():
        raise RuntimeError(f"refusing to use a symlinked spec dir: {spec_dir}")
    if spec_dir.exists() and spec_dir.resolve().parent != specs_dir.resolve():
        raise RuntimeError(f"refusing to use a spec dir outside {specs_dir}: {spec_dir}")


def _stable_source_path(change_dir: Path, mb_path: Path) -> str:
    """A stable, non-leaking path to record in frontmatter (R5, Codex round-2).

    ``str(change_dir.resolve())`` writes an absolute filesystem path (e.g.
    ``/Users/<name>/...``) straight into a file that is normally committed to
    version control — it leaks the local username and isn't portable across
    clones/CI. Store a path relative to the Memory Bank root instead:
    ``os.path.relpath`` handles arbitrary ``../`` climbs, so this works
    whether the OpenSpec source lives under the bank, next to it, or
    elsewhere on the same filesystem. Falls back to the absolute path only
    when a relative path genuinely cannot be computed (``ValueError`` — e.g.
    two different drives on Windows).
    """
    change_r = change_dir.resolve()
    mb_r = mb_path.resolve()
    try:
        return os.path.relpath(change_r, mb_r)
    except ValueError:
        return str(change_r)


def _resolve_stored_source(source: str, mb_path: Path) -> Path:
    """Resolve a stored ``openspec_source`` value against the BANK path (R5).

    Never against the caller's current working directory — that is the whole
    point of F4/REQ-014/015 staying cwd-independent. A relative value (the
    new, R5-fixed form) is joined onto the resolved bank path; an absolute
    value (a legacy path stored before this fix, or the Windows
    cross-drive fallback) is used as-is.
    """
    p = Path(source)
    if p.is_absolute():
        return p
    return mb_path.resolve() / p


def _inject_frontmatter(requirements_md: str, source: str, source_hash: str) -> str:
    """Record the source change path + content hash (REQ-014)."""
    frontmatter = f"---\nopenspec_source: {source}\nopenspec_hash: {source_hash}\n---\n\n"
    return frontmatter + requirements_md


def _read_prior_triple(spec_dir: Path) -> tuple[str, str, str] | None:
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


def _orphan_backlog_marker(topic: str, source_hash: str) -> str:
    """The idempotency key for one orphan-append (R1, Codex round-2)."""
    return f"<!-- openspec-orphans: {topic}@{source_hash[:12]} -->"


def _append_orphans_to_backlog(
    mb_path: Path, topic: str, orphaned_task_lines: list[str], source_hash: str
) -> None:
    """REQ-017 — a previously-imported task that vanished from the OpenSpec
    source on re-import is never silently dropped; append it to
    ``backlog.md`` with a note instead of losing it.

    Idempotent (R1, Codex round-2): keyed by an HTML-comment marker
    ``<!-- openspec-orphans: <topic>@<hash12> -->``. If that exact marker is
    already present in ``backlog.md`` (e.g. a retried/re-run import for the
    same topic against the same source hash, after an earlier crash between
    this append and the later ``requirements.md`` write), the append is
    skipped entirely instead of duplicating the note.
    """
    backlog_path = mb_path / "backlog.md"
    _assert_within(mb_path, backlog_path)
    existing = backlog_path.read_text(encoding="utf-8") if backlog_path.is_file() else "# Backlog\n"
    marker = _orphan_backlog_marker(topic, source_hash)
    if marker in existing:
        return  # already recorded for this exact topic+source_hash -- idempotent retry
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
    atomic_write(backlog_path, existing + "\n".join(note_lines))


def run_import(
    *, change_dir: Path, mb_path: Path, topic: str | None, normalize: bool = False
) -> dict[str, object]:
    """Parse + convert + write one OpenSpec change into a Memory Bank spec triple.

    Re-import (T5): when ``specs/<topic>/`` already carries a triple from a
    prior import, it is read (read-only) and passed to ``convert()`` as
    ``prior_triple`` so REQ-NNN anchors are reused/re-anchored rather than
    renumbered by document position (D-06, REQ-016/018); ``merge_task_state``
    then preserves `/mb work` check-state by task text (REQ-016), and any
    task no longer present in the source is appended to ``backlog.md``
    instead of being silently dropped (REQ-017).

    ``normalize`` (T6, REQ-007/008/010): forwarded to ``convert()`` as-is;
    ``False`` (default) keeps the write path byte-identical to before T6
    (NFR-001).
    """
    change_dir = Path(change_dir)
    mb_path = Path(mb_path)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec change dir not found: {change_dir}")
    if not mb_path.is_dir():
        raise FileNotFoundError(f"memory bank not found: {mb_path}")

    ch = parse_change(change_dir)

    resolved_topic = topic or _slugify(ch.change_id)
    _validate_topic_slug(resolved_topic)
    specs_dir = mb_path / "specs"
    spec_dir = specs_dir / resolved_topic
    _assert_within(mb_path, spec_dir)
    _assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)

    prior_triple = _read_prior_triple(spec_dir)

    requirements_md, design_md, tasks_md = convert(
        ch,
        prior_triple=prior_triple,
        normalize=normalize,
        topic=resolved_topic,
        mb_path=mb_path,
    )

    orphaned_task_lines: list[str] = []
    if prior_triple is not None:
        tasks_md, orphaned_task_lines = merge_task_state(tasks_md, prior_triple[2])

    # Store a STABLE, bank-relative path (R5) -- never the raw resolved
    # absolute path, which would leak the local username into a normally
    # COMMITTED file. `status`/`sync` resolve it back against `mb_path`
    # (never the caller's cwd), preserving F4's cwd-independence.
    requirements_md = _inject_frontmatter(
        requirements_md, _stable_source_path(change_dir, mb_path), ch.source_hash
    )

    # Write order (F7/R1, Codex round-2, and the round-3 crash-consistency
    # fix): design.md -> append orphans to backlog.md (if any) -> tasks.md
    # (orphan-stripped) -> requirements.md (new hash) LAST.
    #
    # The orphan-to-backlog append MUST land before tasks.md is overwritten,
    # not after (the round-2 order had it the other way around). tasks.md is
    # the ONLY on-disk record of the prior task state (`_read_prior_triple`
    # reads it back on the next re-import): once it is overwritten with the
    # orphan-stripped content, that prior state is gone. A crash landing
    # between "tasks.md written" and "backlog.md appended" would then leave
    # a retry with nothing left to re-detect the orphan from -- the task is
    # lost silently and permanently (REQ-017 violation). Recording the
    # orphan in backlog.md FIRST closes that window: by the time tasks.md is
    # overwritten, the orphan already has a durable home.
    #
    # Every crash point remains safe:
    #   - before backlog.md lands: tasks.md/requirements.md are untouched,
    #     retry re-detects the same orphan from the still-intact prior
    #     tasks.md and re-attempts the (idempotent) backlog append.
    #   - after backlog.md lands, before tasks.md: orphan is already durable
    #     in backlog.md; retry re-detects the same orphan again (tasks.md
    #     still holds the old state) and the append is a no-op (idempotency
    #     marker keyed by topic+source_hash in `_append_orphans_to_backlog`).
    #   - after tasks.md, before requirements.md: orphan is already durable
    #     in backlog.md; requirements.md still carries the OLD hash, so a
    #     future `sync`/`status` sees "drifted" rather than wrongly treating
    #     the topic as up to date.
    # requirements.md is written LAST unconditionally (F7): a crash must
    # never leave the hash "current" while any sibling write (design/tasks/
    # backlog) is still outstanding.
    design_dest = spec_dir / "design.md"
    _assert_within(mb_path, design_dest)
    atomic_write(design_dest, design_md)

    if orphaned_task_lines:
        _append_orphans_to_backlog(mb_path, resolved_topic, orphaned_task_lines, ch.source_hash)

    tasks_dest = spec_dir / "tasks.md"
    _assert_within(mb_path, tasks_dest)
    atomic_write(tasks_dest, tasks_md)

    req_dest = spec_dir / "requirements.md"
    _assert_within(mb_path, req_dest)
    atomic_write(req_dest, requirements_md)

    return {
        "topic": resolved_topic,
        "spec_dir": str(spec_dir),
        "source_hash": ch.source_hash,
        "reimport": prior_triple is not None,
        "orphaned_tasks": len(orphaned_task_lines),
    }


# ---------------------------------------------------------------------------
# T4 — list / status / sync (REQ-001, REQ-015, REQ-019)
# ---------------------------------------------------------------------------


def _parse_frontmatter(text: str) -> dict[str, str]:
    """Parse the flat ``key: value`` frontmatter block written by
    ``_inject_frontmatter`` (``openspec_source``/``openspec_hash``, REQ-014).

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


def _iter_imported_topics(mb_path: Path) -> list[tuple[str, Path, dict[str, str]]]:
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
        fm = _parse_frontmatter(req_path.read_text(encoding="utf-8"))
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


def _change_status(
    change_dir: Path, imported_topics: list[tuple[str, Path, dict[str, str]]], mb_path: Path
) -> tuple[str, str | None]:
    """(status, topic) for one OpenSpec change dir against the known imported
    topics — ``not-imported`` / ``imported`` / ``drifted`` (REQ-019).

    ``source`` is resolved against ``mb_path`` (R5), not the caller's cwd —
    it may now be a bank-relative path written by the fixed
    ``_stable_source_path``, or a legacy absolute path from before that fix;
    ``_resolve_stored_source`` handles both.
    """
    change_r = change_dir.resolve()
    for topic, _topic_dir, fm in imported_topics:
        source = fm.get("openspec_source")
        if not source:
            continue
        try:
            if _resolve_stored_source(source, mb_path).resolve() != change_r:
                continue
        except OSError:
            continue
        current_hash = compute_source_hash(change_dir)
        status = "imported" if fm.get("openspec_hash") == current_hash else "drifted"
        return status, topic
    return "not-imported", None


def run_list(*, mb_path: Path, openspec_root: Path, include_all: bool) -> list[dict[str, object]]:
    """List OpenSpec changes with their import status (read-only, REQ-019)."""
    imported_topics = _iter_imported_topics(mb_path)
    results: list[dict[str, object]] = []
    for change_dir in discover_openspec_changes(openspec_root, include_archive=include_all):
        status, topic = _change_status(change_dir, imported_topics, mb_path)
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
    """Status of a single previously-imported topic (read-only, REQ-019)."""
    _validate_topic_slug(topic)
    specs_dir = mb_path / "specs"
    spec_dir = specs_dir / topic
    _assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
    req_path = spec_dir / "requirements.md"
    if not req_path.is_file():
        raise FileNotFoundError(f"topic not found or never imported: {topic}")
    fm = _parse_frontmatter(req_path.read_text(encoding="utf-8"))
    source = fm.get("openspec_source")
    stored_hash = fm.get("openspec_hash")
    if not source or not stored_hash:
        raise RuntimeError(f"topic '{topic}' has no openspec_source/openspec_hash frontmatter")
    change_dir = _resolve_stored_source(source, mb_path)
    if not change_dir.is_dir():
        raise FileNotFoundError(f"OpenSpec source no longer exists: {source}")
    current_hash = compute_source_hash(change_dir)
    status = "imported" if current_hash == stored_hash else "drifted"
    return {
        "topic": topic,
        "source": source,
        "status": status,
        "stored_hash": stored_hash,
        "current_hash": current_hash,
    }


def run_sync(
    *, mb_path: Path, topic: str | None, normalize: bool = False
) -> list[dict[str, object]]:
    """Re-import only topics whose source hash drifted (REQ-015).

    A hash match is a pure no-op: no file is read for writing, no
    ``run_import`` call happens. No ``topic`` syncs every previously-imported
    topic found under ``mb_path/specs/``.

    ``normalize`` (T6) is forwarded to each ``run_import`` call it triggers.
    """
    specs_dir = mb_path / "specs"
    if topic is not None:
        _validate_topic_slug(topic)
        spec_dir = specs_dir / topic
        _assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
        req_path = spec_dir / "requirements.md"
        if not req_path.is_file():
            raise FileNotFoundError(f"topic not found or never imported: {topic}")
        topics = [topic]
    else:
        topics = [name for name, _dir, _fm in _iter_imported_topics(mb_path)]

    results: list[dict[str, object]] = []
    for t in topics:
        spec_dir = specs_dir / t
        try:
            _assert_topic_dir_not_symlink_escape(spec_dir, specs_dir)
        except RuntimeError as exc:
            results.append({"topic": t, "action": "error", "reason": str(exc)})
            continue
        req_path = spec_dir / "requirements.md"
        fm = _parse_frontmatter(req_path.read_text(encoding="utf-8"))
        source = fm.get("openspec_source")
        stored_hash = fm.get("openspec_hash")
        if not source or not stored_hash:
            results.append(
                {"topic": t, "action": "error", "reason": "missing openspec source/hash"}
            )
            continue
        change_dir = _resolve_stored_source(source, mb_path)
        if not change_dir.is_dir():
            results.append({"topic": t, "action": "error", "reason": f"source missing: {source}"})
            continue
        current_hash = compute_source_hash(change_dir)
        if current_hash == stored_hash:
            results.append({"topic": t, "action": "up-to-date"})
            continue
        run_import(change_dir=change_dir, mb_path=mb_path, topic=t, normalize=normalize)
        results.append({"topic": t, "action": "re-imported"})
    return results


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mb-openspec.py", description="OpenSpec -> Memory Bank one-way import adapter"
    )
    sub = parser.add_subparsers(dest="action", required=True)

    imp = sub.add_parser("import", help="Import one OpenSpec change into a Memory Bank spec triple")
    imp.add_argument("change_dir", help="Path to openspec/changes/<id>/")
    imp.add_argument(
        "--as", dest="topic", default=None, help="Target spec topic (default: change-id slug)"
    )
    imp.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")
    imp.add_argument(
        "--normalize",
        action="store_true",
        help="Fill LLM text slots (EARS rewrite/missing scenario/Covers), cached by "
        "source-requirement hash (T6, REQ-007/008/010); omit for the deterministic-only path",
    )

    lst = sub.add_parser("list", help="List OpenSpec changes and their import status")
    lst.add_argument(
        "--all", dest="include_all", action="store_true", help="Include archived changes (OQ-3)"
    )
    lst.add_argument(
        "--openspec", dest="openspec_root", default=".", help="Path containing openspec/changes/"
    )
    lst.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")

    st = sub.add_parser("status", help="Import status of one previously-imported topic")
    st.add_argument("topic", help="Target spec topic under specs/<topic>/")
    st.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")

    sy = sub.add_parser("sync", help="Re-import topics whose OpenSpec source hash drifted")
    sy.add_argument(
        "topic", nargs="?", default=None, help="Target spec topic (default: sync every topic)"
    )
    sy.add_argument("--mb", dest="mb_path", default=".memory-bank", help="Memory Bank path")
    sy.add_argument(
        "--normalize",
        action="store_true",
        help="Fill LLM text slots on any topic re-imported by this sync (T6); omit for the "
        "deterministic-only path",
    )

    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])

    if args.action == "import":
        try:
            result = run_import(
                change_dir=Path(args.change_dir),
                mb_path=Path(args.mb_path),
                topic=args.topic,
                normalize=args.normalize,
            )
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"[error] {exc}", file=sys.stderr)
            return 1
        print(
            f"imported: {args.change_dir} -> specs/{result['topic']}/ "
            f"(hash={result['source_hash'][:12]})"
        )
        return 0

    if args.action == "list":
        entries = run_list(
            mb_path=Path(args.mb_path),
            openspec_root=Path(args.openspec_root),
            include_all=args.include_all,
        )
        if not entries:
            print("no OpenSpec changes found")
            return 0
        for entry in entries:
            topic_suffix = f"  (topic: {entry['topic']})" if entry["topic"] else ""
            print(f"{entry['change_id']}\t{entry['status']}{topic_suffix}")
        return 0

    if args.action == "status":
        try:
            result = run_status(mb_path=Path(args.mb_path), topic=args.topic)
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"[error] {exc}", file=sys.stderr)
            return 1
        print(f"topic: {result['topic']}")
        print(f"source: {result['source']}")
        print(f"status: {result['status']}")
        return 0

    if args.action == "sync":
        try:
            results = run_sync(
                mb_path=Path(args.mb_path), topic=args.topic, normalize=args.normalize
            )
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"[error] {exc}", file=sys.stderr)
            return 1
        if not results:
            print("no imported topics to sync")
            return 0
        for r in results:
            if r["action"] == "up-to-date":
                print(f"{r['topic']}: up to date")
            elif r["action"] == "re-imported":
                print(f"{r['topic']}: re-imported (source hash drifted)")
            else:
                print(f"{r['topic']}: [warn] {r['reason']}", file=sys.stderr)
        return 0

    print(f"[error] unknown action: {args.action}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
