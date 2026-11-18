#!/usr/bin/env python3
"""Path guards for the OpenSpec adapter: topic slugs, bank containment, source paths.

Pure path checks with no file writes; ``mb_openspec_bank`` re-exports them.
"""

from __future__ import annotations

import os
import re
from pathlib import Path


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "change"


_TOPIC_SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def validate_topic_slug(topic: str) -> None:
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


def assert_within(base: Path, target: Path) -> None:
    """Hard guard (REQ-003, NFR-002): refuse to write outside ``base``."""
    base_r = base.resolve()
    target_r = target.resolve()
    try:
        target_r.relative_to(base_r)
    except ValueError as exc:
        raise RuntimeError(f"refusing to write outside {base_r}: {target_r}") from exc


def assert_topic_dir_not_symlink_escape(spec_dir: Path, specs_dir: Path) -> None:
    """Reject a ``specs/<topic>/`` that is itself a symlink escape (R3, Codex
    round-2 residual on F1).

    ``assert_within(mb_path, spec_dir)`` only guards the BANK root; a
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


def stable_source_path(change_dir: Path, mb_path: Path) -> str:
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


def resolve_stored_source(source: str, mb_path: Path) -> Path:
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
