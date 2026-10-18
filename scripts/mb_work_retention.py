#!/usr/bin/env python3
"""Private bounded I/O for opt-in copies of the existing work-state JSON.

Declaration, Eval and ADaPT validation belong to mb-work-state's existing helpers.
"""

from __future__ import annotations

import json
import os
import re
import secrets
import stat
import sys
from collections.abc import Iterator
from contextlib import contextmanager, suppress
from pathlib import Path

LIMIT = 1024 * 1024
RECORDS = 256
DIRECTORY = ".work-completed"


def entry_count(fd: int) -> int:
    count = 0
    with os.scandir(fd) as entries:
        for _ in entries:
            count += 1
            if count > RECORDS:
                raise ValueError("retention record limit")
        return count


@contextmanager
def directory(path: Path) -> Iterator[int]:
    if not path.is_absolute() or ".." in path.parts or len(path.parts) > 128:
        raise ValueError("unsafe directory")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


def regular(fd: int, *, private: bool) -> None:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_size > LIMIT or info.st_nlink != 1:
        raise ValueError("unsafe or oversized state file")
    if private and (info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600):
        raise ValueError("state file must be owned and private (0600)")


def read(fd: int, name: str) -> bytes | None:
    try:
        file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    except FileNotFoundError:
        return None
    try:
        regular(file, private=True)
        with os.fdopen(file, "rb", closefd=False) as stream:
            data = stream.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise ValueError("state input limit")
        return data
    finally:
        os.close(file)


def state(data: bytes, run_id: str) -> dict:
    value = json.loads(data)
    if not isinstance(value, dict) or value.get("run_id") != run_id:
        raise ValueError("state run identity mismatch")
    if not isinstance(value.get("item_no"), int) or not isinstance(value.get("source"), str):
        raise ValueError("state source/item identity missing")
    source = value.get("source_path")
    if not isinstance(source, str):
        raise ValueError("state source path missing")
    if source:
        path = Path(source)
        if not path.is_absolute() or ".." in path.parts:
            raise ValueError("unsafe source path")
        try:
            with directory(path.parent) as parent:
                file = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
                try:
                    regular(file, private=False)
                finally:
                    os.close(file)
        except FileNotFoundError:
            # The existing NOFILE gate, not this I/O layer, classifies an absent surface.
            return value
    return value


@contextmanager
def completed(bank: Path, *, create: bool) -> Iterator[int]:
    with directory(bank) as parent:
        if create:
            with suppress(FileExistsError):
                os.mkdir(DIRECTORY, 0o700, dir_fd=parent)
        fd = os.open(DIRECTORY, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        try:
            info = os.fstat(fd)
            if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
                raise ValueError("retention directory must be owned and private (0700)")
            entry_count(fd)
            yield fd
        finally:
            os.close(fd)


def operate(action: str, bank: Path, run_id: str, live: str = "") -> None:
    if ".." in bank.parts or (live and ".." in Path(live).parts):
        raise ValueError("unsafe state locator")
    bank = Path(os.path.abspath(bank))
    live = os.path.abspath(live) if live else ""
    if (os.environ.get("MB_WORK_RETAIN_STATE") != "1"
            or os.environ.get("MB_WORK_RETAIN_BANK") != str(bank)
            or os.environ.get("MB_WORK_RUN_ID") != run_id
            or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", run_id)):
        raise ValueError("native bank/run identity mismatch")
    with directory(bank) as bank_fd:
        if os.fstat(bank_fd).st_uid != os.getuid():
            raise ValueError("retention bank must be owned")
    name = f"{run_id}.json"
    if action in {"guard", "snapshot"}:
        expected = Path(live)
        if expected not in {bank / ".work-state" / name, bank / ".work-state.json"}:
            raise ValueError("state slot identity mismatch")
        try:
            with directory(expected.parent) as fd:
                raw = read(fd, expected.name)
        except FileNotFoundError:
            raw = None
        if raw is not None:
            state(raw, run_id)
        if action == "snapshot":
            sys.stdout.write(raw.decode() if raw is not None else "{}\n")
        return
    raw = sys.stdin.buffer.read(LIMIT + 1) if action == "store" else None
    if raw is not None:
        if len(raw) > LIMIT:
            raise ValueError("state input limit")
        state(raw, run_id)
    try:
        with completed(bank, create=action == "store") as fd:
            previous = read(fd, name)
            if previous is not None:
                state(previous, run_id)
            if action == "read":
                sys.stdout.write(previous.decode() if previous is not None else "{}\n")
            elif action == "drop":
                if previous is not None:
                    os.unlink(name, dir_fd=fd)
            elif action == "store":
                assert raw is not None
                if previous is None and entry_count(fd) >= RECORDS:
                    raise ValueError("retention record limit; remove obsolete completed records")
                temporary = f".{run_id}.{secrets.token_hex(8)}"
                file = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
                try:
                    os.fchmod(file, 0o600)
                    with os.fdopen(file, "wb") as output:
                        output.write(raw)
                        output.flush()
                        os.fsync(output.fileno())
                    os.replace(temporary, name, src_dir_fd=fd, dst_dir_fd=fd)
                    os.fsync(fd)
                finally:
                    with suppress(FileNotFoundError):
                        os.unlink(temporary, dir_fd=fd)
            else:
                raise ValueError("unknown retention I/O action")
    except FileNotFoundError:
        if action == "read":
            print("{}")
        elif action != "drop":
            raise


if __name__ == "__main__":
    try:
        operate(sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    except (OSError, ValueError) as exc:
        print(f"[work-state] retention refused: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
