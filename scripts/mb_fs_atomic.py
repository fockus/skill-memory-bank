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
import os
import stat
import tempfile


def _target_mode(path):
    """Mode the published file must end up with.

    An EXISTING file's mode is preserved verbatim — a bank deliberately locked
    down to 0600 must stay 0600, and guessing that a restrictive mode is
    "damage" would silently widen a file the user chose to protect. Repairing
    already-damaged permissions is a one-shot migration concern (I-145), not
    something a write path can infer. A NEW file gets the ordinary creation
    default (0666 masked by umask) rather than mkstemp's private 0600.
    """
    try:
        return stat.S_IMODE(os.stat(str(path)).st_mode)
    except FileNotFoundError:
        current = os.umask(0)
        os.umask(current)
        return 0o666 & ~current
    except OSError:
        return None


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
    mode = _target_mode(target)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".mb-atomic.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding=encoding, newline="") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        # Best-effort cleanup: the original file is already safe (untouched),
        # so a failure to remove the temp must not mask the real exception.
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise
