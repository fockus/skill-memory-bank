"""Private RAG storage, publication pointers and crash-safe staging for one worktree."""

from __future__ import annotations

import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from pathlib import Path
from typing import NamedTuple

from memory_bank_skill._io import atomic_write

_MODULES = {"qwen3": "mb_rag_qmd", "perplexity": "mb_rag_pplx"}
_INIT = "run setup with `memory-bank rag init`"


class _Selection(NamedTuple):
    model: str
    generation: str
    fingerprint: str


class InvalidSelection(ValueError):
    """Re-running explicit setup can replace a malformed selection."""


class WriterBusy(RuntimeError):
    """A different setup, manual update or background update owns this worktree."""


def _xdg(base: str) -> Path:
    fallback = Path.home() / (".cache" if base == "CACHE" else ".local/state")
    return Path(os.environ.get(f"XDG_{base}_HOME") or fallback)


def _private_dir(root: Path, bank: Path, base: str, parts: Sequence[str], create: bool) -> Path:
    path = _xdg(base)
    if not path.is_absolute() or any(
        candidate.is_relative_to(p) for p in (root, bank) for candidate in (path, path.resolve())
    ):
        raise ValueError(f"XDG_{base}_HOME must be an absolute directory outside the project")
    path = path.resolve()
    for part in ("memory-bank-project-rag", *parts):
        path = path / part
        if path.is_symlink() or any(path.is_relative_to(p) for p in (root, bank)):
            raise ValueError("RAG storage must be a private directory outside the project")
        if create:
            path.mkdir(mode=0o700, parents=True, exist_ok=True)
        if path.exists():
            st = path.stat()
            if st.st_uid != os.getuid() or st.st_mode & 0o077 or not path.is_dir():
                raise ValueError(f"RAG storage must be owned by you and mode 0700: {path}")
    return path


def _key(root: Path, bank: Path) -> str:
    return hashlib.sha256(os.fsencode(root) + b"\0" + os.fsencode(bank)).hexdigest()


def _existing_state(root: Path, bank: Path) -> Path | None:
    key = _key(root, bank)
    try:
        (_xdg("STATE") / "memory-bank-project-rag" / key / "current.json").lstat()
    except FileNotFoundError:
        return None
    return _private_dir(root, bank, "STATE", (key,), False)


def _read(state: Path, *, repair: bool = False) -> _Selection | None:
    try:
        path = state / "current.json"
        info = path.lstat()
        if not stat.S_ISREG(info.st_mode):
            raise OSError("Expected a regular file for the RAG selection")
        if info.st_size > 4096:
            raise ValueError("invalid selection file")
        pointer = json.loads(path.read_bytes())
        model, generation, fingerprint = (
            pointer["model"],
            pointer["generation"],
            pointer["fingerprint"],
        )
        if (
            model not in _MODULES
            or not re.fullmatch("[0-9a-f]{32}", generation)
            or not re.fullmatch("[0-9a-f]{64}", fingerprint)
        ):
            raise ValueError("invalid fields")
    except FileNotFoundError:
        return None
    except (ValueError, TypeError, KeyError) as exc:
        if repair:
            return None
        raise InvalidSelection(f"Invalid RAG selection; {_INIT}") from exc
    return _Selection(model, generation, fingerprint)


@contextmanager
def _lock(directory: Path, mode: int) -> Iterator[None]:
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        try:
            fcntl.flock(fd, mode)
        except BlockingIOError as exc:
            raise WriterBusy("Another RAG writer is active; retry later") from exc
        yield
    finally:
        os.close(fd)


def reap(state: Path, projects: Path, current: _Selection | None) -> None:
    """After SIGKILL, only reap generations recorded by this state directory's writer."""
    journal = state / "pending-generations"
    try:
        names = journal.read_text().splitlines()
    except FileNotFoundError:
        return
    for name in names:
        if not re.fullmatch("[0-9a-f]{32}", name):
            raise ValueError("Invalid pending RAG generation")
        if not current or name != current.generation:
            abandoned = projects / name
            if abandoned.exists():
                shutil.rmtree(abandoned)
    journal.unlink()


@contextmanager
def stage(
    state: Path, projects: Path, previous: _Selection | None, active: _Selection
) -> Iterator[Path]:
    # A pointer swap may be interrupted before old generations are removed. Record both.
    names = [active.generation] + ([previous.generation] if previous else [])
    atomic_write(state / "pending-generations", "\n".join(names))
    try:
        index = projects / active.generation / "index"
        index.mkdir(parents=True, mode=0o700)
        yield index
    finally:
        reap(state, projects, _read(state, repair=True))
