"""r5 review [5]: the shared publish primitive must not re-permission a target
that appeared while it was writing, and its resolve-mode → rename step must be
serialised against other writers in the same directory.

A NEW file rather than an edit of `test_s4_r3_data_safety.py`: that file belongs
to another zone/session, and the mode-preservation rules it already pins stay
exactly as they are.
"""

from __future__ import annotations

import fcntl
import os
import pathlib
import stat
import sys
import threading

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from mb_fs_atomic import atomic_write  # noqa: E402


def _mode(path) -> int:
    return stat.S_IMODE(os.stat(str(path)).st_mode)


def test_target_created_mid_write_keeps_its_own_mode(tmp_path, monkeypatch) -> None:
    """The interleaving from the review, made deterministic.

    Run A finds no target and (umask 022) intends 0644. Run B publishes the
    target at 0600 while A is still writing its temp file. A must not replace
    that 0600 file with a 0644 one — the mode is a property of the file that
    exists at rename time, not of the emptiness observed earlier.

    ``os.fsync`` is the hook because it runs after the temp file is written and
    before the publish, which is exactly the window that used to be open.
    """
    target = tmp_path / "bank.md"
    assert not target.exists()

    real_fsync = os.fsync

    def fsync_then_a_second_publisher(fd):  # type: ignore[no-untyped-def]
        real_fsync(fd)
        if not target.exists():
            previous = os.umask(0o077)
            try:
                with open(target, "w", encoding="utf-8") as fh:
                    fh.write("CONCURRENTLY PUBLISHED\n")
            finally:
                os.umask(previous)

    monkeypatch.setattr(os, "fsync", fsync_then_a_second_publisher)

    previous = os.umask(0o022)
    try:
        atomic_write(target, "NEW\n")
    finally:
        os.umask(previous)

    assert target.read_text(encoding="utf-8") == "NEW\n"
    assert _mode(target) == 0o600, "an existing 0600 target was widened"


def test_publish_waits_for_another_writer_holding_the_directory(tmp_path) -> None:
    """Two writers cannot interleave their mode-read/rename in one directory."""
    target = tmp_path / "bank.md"
    target.write_text("ORIGINAL\n", encoding="utf-8")
    os.chmod(target, 0o640)

    done = threading.Event()

    def writer() -> None:
        atomic_write(target, "NEW\n")
        done.set()

    lock_fd = os.open(str(tmp_path), os.O_RDONLY)
    fcntl.flock(lock_fd, fcntl.LOCK_EX)
    thread = threading.Thread(target=writer)
    thread.start()
    try:
        # Held elsewhere: the publish must not land. A generous window, since a
        # false PASS here would need the publish to be slower than 1.5 s.
        assert not done.wait(1.5), "the publish ignored a held directory lock"
        assert target.read_text(encoding="utf-8") == "ORIGINAL\n"
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)

    thread.join(timeout=10)
    assert done.is_set(), "the publish never completed after the lock was freed"
    assert target.read_text(encoding="utf-8") == "NEW\n"
    assert _mode(target) == 0o640
