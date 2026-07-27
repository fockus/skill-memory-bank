#!/usr/bin/env python3
"""One atomic file-publish primitive, shared by the S4 writers.

Extracted after round-2 finding 5: ``mb_roadmap_render.atomic_write`` carried
the file mode across the rename, ``mb_backlog_state_engine.write_atomic`` did
not, and a backlog transition therefore silently re-permissioned a shared bank
from 0644 to mkstemp's 0600. Two hand-rolled copies of the same subtle
primitive is exactly how one of them drifts, so there is now only one.

Pure stdlib, no side effects on import.
"""

from __future__ import annotations

import contextlib
import fcntl
import os
import stat
import tempfile


@contextlib.contextmanager
def _dir_lock(directory):
    """Serialise the resolve-mode → rename step of every writer in ``directory``.

    ``flock`` on the DIRECTORY's own descriptor: no lock file is created, so
    there is nothing to leave behind, nothing to reclaim, and no stale-lock path
    that could race the very thing it repairs — the kernel drops the lock when
    the descriptor closes, including on a crash or a signal.

    Best effort by design. A read-only directory, or a filesystem without
    working ``flock``, yields WITHOUT the lock rather than refusing to publish:
    losing the serialisation degrades to the pre-lock behaviour, while refusing
    would lose the write itself.
    """
    fd = -1
    try:
        fd = os.open(directory, os.O_RDONLY)
        fcntl.flock(fd, fcntl.LOCK_EX)
    except OSError:
        if fd >= 0:
            with contextlib.suppress(OSError):
                os.close(fd)
            fd = -1
    try:
        yield fd >= 0
    finally:
        if fd >= 0:
            with contextlib.suppress(OSError):
                os.close(fd)


def _target_mode(path):
    """Mode the published file must end up with.

    An EXISTING file's mode is preserved verbatim — a bank deliberately locked
    down to 0600 must stay 0600, and guessing that a restrictive mode is
    "damage" would silently widen a file the user chose to protect. Repairing
    already-damaged permissions is a one-shot migration concern (I-145), not
    something a write path can infer. A NEW file gets the ordinary creation
    default (0666 masked by umask) rather than mkstemp's private 0600.

    ONLY FileNotFoundError means "new file". Every other OSError (a transient
    EIO, an EACCES on the parent directory) propagates: swallowing it returned
    None, and the publish then went ahead and renamed mkstemp's private 0600
    temp file over an existing 0664 bank file, silently narrowing permissions
    the user never asked to change (R3-008). The caller unlinks its temp file on
    the way out, so a stat failure still leaves the target's bytes and mode
    exactly as they were.
    """
    try:
        return stat.S_IMODE(os.stat(str(path)).st_mode)
    except FileNotFoundError:
        current = os.umask(0)
        os.umask(current)
        return 0o666 & ~current


def publish_path(tmp, target, refuse_irregular=False):
    """Rename ``tmp`` over ``target``, carrying the mode ``target`` must have.

    The mode is resolved HERE — inside the lock, immediately before the rename —
    and not when the caller started writing its temp file. Reading it early left
    a whole write's worth of window in between: a publisher that found no target
    computed 0644 from its umask, another publisher created the file at 0600
    meanwhile, and the first one then replaced that 0600 file with a 0644 one.
    Nobody asked for the widening and no writer ever observed the mode it
    produced (r5 review [5]).

    ``refuse_irregular`` additionally raises when the target exists and is not a
    plain file — a symlink or directory there means the caller is about to
    publish somewhere it never intended.
    """
    tmp = str(tmp)
    target = str(target)
    directory = os.path.dirname(os.path.abspath(target)) or "."
    with _dir_lock(directory):
        if refuse_irregular:
            try:
                st = os.lstat(target)
            except FileNotFoundError:
                st = None
            if st is not None and (stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode)):
                raise OSError("refusing to publish over a non-regular target")
        os.chmod(tmp, _target_mode(target))
        os.replace(tmp, target)


def atomic_write(path, text, encoding="utf-8"):
    """Publish ``text`` to ``path`` atomically, preserving the file mode.

    Writes a sibling temp file in the SAME directory (so ``os.replace`` stays a
    same-filesystem rename), flushes and fsyncs it, then renames over the
    target. A plain ``write_text`` truncates the target first, so an ENOSPC or a
    kill mid-write leaves the file empty or half-written. The temp file is
    removed on any failure, leaving the original untouched.
    """
    target = str(path)
    directory = os.path.dirname(os.path.abspath(target)) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".mb-atomic.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding, newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        publish_path(tmp, target)
    except BaseException:
        # Best-effort cleanup: the original file is already safe (untouched),
        # so a failure to remove the temp must not mask the real exception.
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise
