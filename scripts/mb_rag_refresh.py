"""Coalesce refreshes of one enrolled RAG index outside the requesting process."""

from __future__ import annotations

import contextlib
import fcntl
import os
import signal
import stat
import subprocess
import sys
import time
from pathlib import Path

if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))

from mb_project_rag import publication
from mb_rag_diagnosis import diagnose
from mb_rag_storage import WriterBusy, _existing_state, _key, _lock, _private_dir, _read, reap

import memory_bank_skill
from memory_bank_skill._io import atomic_write

QUIET = 120
COOLDOWN = 900
BUDGET = 180
_MANUAL = 20
_ACTION = "memory-bank rag update"
_DEFER = "Automatic refresh exceeded its budget or cannot reuse this index."


def _manual(directory: Path) -> bytes:
    try:
        fd = os.open(directory / "manual", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return b""
    with os.fdopen(fd, "rb") as marker:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("Invalid RAG refresh marker")
        return marker.read(128)


def _spawn(mode: str, root: Path, bank: Path, *, fds: tuple[int, ...] = ()) -> subprocess.Popen:
    # The child may run from a wheel's share/ or a source checkout, even with -P.
    package = Path(memory_bank_skill.__file__).resolve().parent.parent
    return subprocess.Popen(
        [sys.executable, "-B", "-P", str(Path(__file__).resolve()), mode, str(root), str(bank)],
        env={**os.environ, "PYTHONPATH": str(package)},
        cwd="/",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        pass_fds=fds,
    )


def _stale_details(
    root: Path, bank: Path, target: str, *, schedule: bool
) -> dict[str, str]:
    """Both lookup and status fail open; read-only inspection never claims the lease."""
    fallback = {"action": _ACTION, "reason": "Tracked source changed since the index was built."}
    try:
        directory = _private_dir(root, bank, "STATE", (_key(root, bank), "refresh"), schedule)
        if not directory.is_dir():
            return fallback
        if _manual(directory) == target.encode():
            return {"action": _ACTION, "refresh": "manual", "reason": _DEFER}
        if schedule:
            # Transfer the open file description: simultaneous sessions cannot fork
            # duplicate timers, and a crash releases the lease without PID probing.
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    pass  # The detached coordinator already owns this project.
                else:
                    _spawn("schedule", root, bank, fds=(fd,))
            finally:
                os.close(fd)
            return {"refresh": "scheduled", "reason": "Background project RAG refresh scheduled."}
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError):
        pass  # Refresh is optional; keep the stale status and the manual command.
    return fallback


def _inspection(root: Path, bank: Path) -> tuple[dict[str, str], str | None]:
    with publication(root, bank) as active:
        if active is None:
            return {}, None
        result = diagnose(active, root, bank)
        fingerprint = result.pop("fingerprint", None)
        return result, f"{active.generation.name}:{fingerprint}" if fingerprint else None


def published_status(root: Path, bank: Path, *, schedule: bool) -> dict[str, str]:
    result, target = _inspection(root, bank)
    if target is not None:
        result.update(_stale_details(root, bank, target, schedule=schedule))
    return result


def _target(root: Path, bank: Path, directory: Path) -> str | None:
    _, target = _inspection(root, bank)
    return target if target and _manual(directory) != target.encode() else None


def stale_lookup_message(root: Path, bank: Path) -> str:
    details = published_status(root, bank, schedule=True)
    action = details.get("action")
    return details.get("reason", "Project RAG selection changed during lookup.") + (
        f" Run `{action}`." if action else ""
    )


def _cleanup(root: Path, bank: Path) -> None:
    state = _existing_state(root, bank)
    if state is None:
        return
    writer = _private_dir(root, bank, "STATE", (state.name, "writer"), False)
    projects = _private_dir(root, bank, "CACHE", ("projects", state.name), False)
    # Another writer reaps this journal itself. Never touch its staging directory.
    with (
        contextlib.suppress(WriterBusy, FileNotFoundError),
        _lock(writer, fcntl.LOCK_EX | fcntl.LOCK_NB),
    ):
        reap(state, projects, _read(state))


def _bounded(root: Path, bank: Path) -> int:
    proc = _spawn("build", root, bank)
    try:
        return proc.wait(timeout=BUDGET)
    except subprocess.TimeoutExpired:
        # Includes model descendants even when the builder is stuck in native code.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGKILL)
        proc.wait()
        _cleanup(root, bank)
        return _MANUAL


def _coordinate(root: Path, bank: Path) -> None:
    directory = _private_dir(root, bank, "STATE", (_key(root, bank), "refresh"), False)
    started = directory / "started"
    with contextlib.suppress(OSError):
        os.nice(10)
    target = _target(root, bank, directory)
    while target is not None:
        delay = float(QUIET)
        try:
            age = max(0., time.time() - started.lstat().st_mtime)
            delay = max(delay, COOLDOWN - age)
        except FileNotFoundError:
            pass
        time.sleep(delay)
        confirmed = _target(root, bank, directory)
        if confirmed != target:
            target = confirmed
            continue
        atomic_write(started, "")
        result = _bounded(root, bank)
        if result == _MANUAL:
            atomic_write(directory / "manual", target)
        # An edit during publication needs another quiet window. A transient failure
        # on identical input waits for the next trigger rather than looping forever.
        current = _target(root, bank, directory)
        target = current if current != target else None


def _main(mode: str, root: Path, bank: Path) -> int:
    if mode == "schedule":
        _coordinate(root, bank)
    elif mode == "build":
        from mb_project_rag import ManualUpdateRequired, update

        # A healthy publication can be removed or damaged while the timer sleeps.
        if _inspection(root, bank)[1] is None:
            return 0
        try:
            update(root, bank, max_new_chunks=32)
        except ManualUpdateRequired:
            return _MANUAL
    else:
        raise ValueError("Unknown RAG worker mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])))
