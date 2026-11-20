"""The memory-bank rules block inside ``$HERMES_HOME/SOUL.md``: byte-exact, locked, atomic.

Writer contract for every writer of SOUL.md that follows it (soul-composer's subagents/orchestrator.py,
this plugin):

1. Lock: hold ``fcntl.flock(LOCK_EX)`` on ``<SOUL.md>.lock`` (same folder, a regular file of this user,
   mode 0600, see ``lock_path``; never deleted) from the read to the publication. Wait a bounded time
   (``LOCK_TIMEOUT``) and retry on a later run rather than block.
2. Read under the lock and keep the stat (device, inode, mtime_ns, size) of what was read; leave the file
   alone when it differs from what the new content was built from, or when it may not be written
   (read-only, owner or group that cannot be carried over).
3. Publish with an atomic name exchange (macOS ``renamex_np(RENAME_SWAP)``, Linux
   ``renameat2(RENAME_EXCHANGE)``), never ``os.replace``: Hermes' own SOUL editor saves with
   ``atomic_write_text`` and takes no lock, and a replace destroys a save landing just before it. The
   exchange leaves the displaced file at the temp name; when it is not the one read in step 2, exchange
   it straight back (the other save wins) and keep whatever then sits at the temp name — never delete it,
   because a writer that saves in place (Hermes' TUI ``write_text``) may have rewritten that inode between
   the two exchanges; log its path. Where no exchange exists, do not publish.

A SOUL.md whose whole first line is ``<!-- soul-composer: build <hex> -->`` belongs to soul-composer:
this plugin never writes it (REQ-005). The plugin renders its block before taking the lock.
"""

from __future__ import annotations

import ctypes
import errno
import logging
import os
import re
import stat
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

try:
    import fcntl
except ImportError:  # Windows: no flock, so no safe way to share SOUL.md with the composer
    fcntl = None

logger = logging.getLogger(__name__)

START, END = b"<!-- mb-rules:start -->", b"<!-- mb-rules:end -->"
BOM = b"\xef\xbb\xbf"
_HEADER = re.compile(rb"(?:\xef\xbb\xbf)?[ \t]*<!-- soul-composer: build [0-9a-f]+ -->[ \t]*\r?")
LOCK_TIMEOUT = 10.0  # seconds; a lock held longer leaves the sync to the next session start
_ANCHOR = b"Priority when instructions conflict"
# linux/fcntl.h, linux/fs.h; macOS sys/stdio.h
_AT_FDCWD, _RENAME_EXCHANGE, _RENAME_SWAP = -100, 2, 2
_NO_EXCHANGE = {errno.EINVAL, errno.ENOTSUP, errno.EOPNOTSUPP, errno.ENOSYS}


def lock_path(soul: Path) -> Path:
    return soul.with_name(soul.name + ".lock")


def composed(data: bytes) -> bool:
    """True when the whole first physical line is the soul-composer build header."""
    return bool(_HEADER.fullmatch(data.split(b"\n", 1)[0]))


def _on_own_line(data: bytes, at: int, marker: bytes) -> bool:
    after = data[at + len(marker) : at + len(marker) + 2]
    line_start = at == 0 or data[at - 1 : at] == b"\n" or (at == len(BOM) and data.startswith(BOM))
    return line_start and (after[:1] in (b"", b"\n") or after == b"\r\n")


def with_block(data: bytes, block: str) -> bytes | None:
    """*data* carrying *block*, every byte outside it kept; None when the markers are ambiguous.

    No markers: the block goes after the paragraph that starts with the conflict-priority rule, else at
    the end. Exactly one ordered start/end pair, each on its own line: the span between them is replaced.
    """
    newline = data.find(b"\n")
    eol = b"\r\n" if newline > 0 and data[newline - 1 : newline] == b"\r" else b"\n"
    new = block.encode("utf-8").replace(b"\n", eol)
    starts, ends = data.count(START), data.count(END)
    if starts == ends == 0:
        paragraphs = data.split(eol * 2)
        at = next(
            (i + 1 for i, para in enumerate(paragraphs) if para.startswith(_ANCHOR)),
            len(paragraphs),
        )
        return (eol * 2).join([*paragraphs[:at], new, *paragraphs[at:]])
    start, end = data.find(START), data.find(END)
    if (
        starts == ends == 1
        and start < end
        and _on_own_line(data, start, START)
        and _on_own_line(data, end, END)
    ):
        return data[:start] + new + data[end + len(END) :]
    return None


def _read(soul: Path) -> tuple[bytes, os.stat_result] | None:
    """(bytes, stat) of a regular, UTF-8 SOUL.md; None (with a warning) for anything else."""
    try:
        fd = os.open(soul, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None  # no SOUL.md: Hermes uses its built-in identity, which a rules-only file would replace
    except OSError as error:  # a symlink fails with ELOOP
        logger.warning(
            "memory-bank: rules sync skipped, %s unreadable: %s", soul, type(error).__name__
        )
        return None
    try:
        st = os.fstat(fd)  # before fdopen, which raises for a directory
        if not stat.S_ISREG(st.st_mode):
            logger.warning("memory-bank: rules sync skipped, %s is not a regular file", soul)
            return None
        file, fd = os.fdopen(fd, "rb"), -1
        with file:
            data = file.read()
    except OSError as error:
        logger.warning(
            "memory-bank: rules sync skipped, %s unreadable: %s", soul, type(error).__name__
        )
        return None
    finally:
        if fd >= 0:
            os.close(fd)
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        logger.warning("memory-bank: rules sync skipped, %s is not UTF-8", soul)
        return None
    return data, st


def _identity(st: os.stat_result) -> tuple[int, int, int, int]:
    return st.st_dev, st.st_ino, st.st_mtime_ns, st.st_size


@contextmanager
def _locked(soul: Path) -> Iterator[bool]:
    """Hold the shared lock; yields False when another writer kept it for LOCK_TIMEOUT seconds."""
    lock = lock_path(soul)
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
            raise PermissionError(errno.EPERM, "not a private lock file", str(lock))
        deadline = time.monotonic() + LOCK_TIMEOUT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    yield False
                    return
                time.sleep(0.05)
        yield True
    finally:
        os.close(fd)  # releases the lock; the file stays, so every writer keeps locking one inode


def _exchange(a: Path, b: Path) -> bool:
    """Swap the names *a* and *b* in one atomic step; False where the platform or file system cannot."""
    try:
        libc = ctypes.CDLL(None, use_errno=True)
        if sys.platform == "darwin":
            swap = libc.renamex_np
            swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
            done = swap(os.fsencode(a), os.fsencode(b), _RENAME_SWAP)
        else:
            swap = libc.renameat2
            swap.argtypes = [
                ctypes.c_int,
                ctypes.c_char_p,
                ctypes.c_int,
                ctypes.c_char_p,
                ctypes.c_uint,
            ]
            done = swap(_AT_FDCWD, os.fsencode(a), _AT_FDCWD, os.fsencode(b), _RENAME_EXCHANGE)
    except (OSError, AttributeError):  # no such libc call here
        return False
    if done == 0:
        return True
    code = ctypes.get_errno()
    if code in _NO_EXCHANGE:
        return False
    raise OSError(code, os.strerror(code), str(b))


def _carry_access(fd: int, before: os.stat_result) -> bool:
    """Give the open temp file SOUL.md's owner, group and mode; False when owner or group cannot be kept."""
    own = os.fstat(fd)
    if (own.st_uid, own.st_gid) != (before.st_uid, before.st_gid):
        try:
            os.fchown(fd, before.st_uid, before.st_gid)
        except PermissionError:
            return False
    os.fchmod(fd, stat.S_IMODE(before.st_mode))  # after fchown, which may clear setuid/setgid bits
    return True


def _publish(soul: Path, data: bytes, before: os.stat_result) -> None:
    """Swap a prepared copy in for *before*, the SOUL.md read under the lock. The swap leaves the file it
    displaced at the temp name: anything but *before* is a lockless writer's save (Hermes' SOUL editor
    uses atomic_write_text without the lock), so it is swapped straight back and the other save wins."""
    if not os.access(
        soul, os.W_OK
    ):  # a plain write would be refused: the folder's write bit is no licence
        logger.warning("memory-bank: rules sync skipped, %s is read-only", soul)
        return
    fd, name = tempfile.mkstemp(dir=soul.parent, prefix=f".{soul.name}.", suffix=".tmp")  # 0600
    tmp, keep = Path(name), False
    try:
        with os.fdopen(fd, "wb") as file:
            if not _carry_access(file.fileno(), before):
                logger.warning(
                    "memory-bank: rules sync skipped, %s owner or group cannot be kept", soul
                )
                return
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        if not _exchange(tmp, soul):
            logger.warning(
                "memory-bank: rules sync skipped, %s cannot be swapped atomically here", soul
            )
            return
        keep = (
            True  # from here the temp name may hold another writer's file: never delete it unseen
        )
        if _identity(os.lstat(tmp)) == _identity(before):
            keep = False
            return
        if not _exchange(tmp, soul):  # the first exchange worked, so this one only fails on a fault
            raise OSError(errno.EIO, "another writer's save could not be swapped back", str(tmp))
        # Never unlink after a swap-back: another writer (Hermes' TUI writes in place) may have
        # rewritten the inode now at the temp name between the two exchanges, so it stays on disk.
        keep = True
        logger.warning(
            "memory-bank: rules sync undone, %s was saved by another writer meanwhile; "
            "the displaced copy is kept at %s",
            soul,
            tmp,
        )
    finally:
        if not keep:
            tmp.unlink(missing_ok=True)


def sync(soul: Path, render: Callable[[], str]) -> bool:
    """Keep the rules block in a hand-written SOUL.md current; never raises for a bad file or render.
    False only when the lock stayed busy, so a later call should try again."""
    if fcntl is None:
        logger.warning("memory-bank: rules sync skipped, no file locking on this platform")
        return True
    snapshot = _read(soul)  # outside the lock, which the slow render must not hold
    if snapshot is None or composed(snapshot[0]):
        return True  # soul-composer built this SOUL and pulls render_soul_brick() itself
    try:
        block = render()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        logger.warning("memory-bank: rules sync skipped, render failed: %s", type(error).__name__)
        return True
    try:
        with _locked(soul) as held:
            if not held:
                logger.warning(
                    "memory-bank: rules sync postponed, %s is locked by another writer", soul
                )
                return False
            current = _read(soul)
            if current is None or current[0] != snapshot[0] or composed(current[0]):
                logger.warning("memory-bank: rules sync skipped, %s changed while rendering", soul)
                return True
            updated = with_block(current[0], block)
            if updated is None:
                logger.warning(
                    "memory-bank: rules sync skipped, %s has ambiguous mb-rules markers", soul
                )
            elif updated != current[0]:
                _publish(soul, updated, current[1])
    except OSError as error:
        logger.warning("memory-bank: rules sync failed: %s", error)
    return True
