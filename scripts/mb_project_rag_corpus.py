"""Inventory and chunk the *working copies* of Git-tracked project source files."""

from __future__ import annotations

import errno
import hashlib
import os
import re
import shutil
import stat
import subprocess
import sys
from collections.abc import Iterator
from contextlib import ExitStack
from itertools import groupby
from pathlib import Path

from memory_bank_skill.private import redact_private_lines

_EXTENSIONS = {
    ".py",
    ".pyi",
    ".go",
    ".rs",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
    ".ts",
    ".tsx",
    ".java",
    ".kt",
    ".kts",
    ".scala",
    ".swift",
    ".c",
    ".cc",
    ".cpp",
    ".cxx",
    ".h",
    ".hh",
    ".hpp",
    ".cs",
    ".fs",
    ".fsx",
    ".rb",
    ".php",
    ".lua",
    ".ex",
    ".exs",
    ".erl",
    ".hrl",
    ".clj",
    ".hs",
    ".ml",
    ".mli",
    ".m",
    ".mm",
    ".sql",
    ".dart",
    ".vue",
    ".svelte",
    ".html",
    ".css",
    ".scss",
    ".sh",
    ".bash",
    ".zsh",
    ".fish",
    ".bats",
    ".r",
    ".jl",
    ".groovy",
    ".pl",
    ".pm",
    ".zig",
    ".sol",
    ".proto",
}
_EXCLUDED = {
    "wiki",
    "llm-wiki",
    "notes",
    "docs",
    "node_modules",
    "vendor",
    "venv",
    "__pycache__",
    "dist",
    "build",
    "target",
}
_SENSITIVE = re.compile(r"secret|credential|private[._-]?key|^id_(rsa|ed25519)|\.env(?:\.|$)")
_DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
_MAX_SOURCE = 2 * 1024 * 1024
Row = tuple[str, int, int]


class NotWorktree(ValueError):
    """Git confirmed there is no worktree at this location."""


def _git(root: Path, *args: str) -> bytes:
    # Discovery needs neither optional index writes nor a project-provided fsmonitor.
    git = shutil.which("git", path=os.defpath)
    if not git:
        raise RuntimeError("Project code RAG requires a system Git installation")
    proc = subprocess.run(
        [git, "--no-optional-locks", "-c", "core.fsmonitor=false", "-C", root, *args],
        env={**{k: v for k, v in os.environ.items() if not k.startswith("GIT_")}, "LC_ALL": "C"},
        capture_output=True,
    )
    if proc.returncode:
        if b"not a git repository" in proc.stderr or b"must be run in a work tree" in proc.stderr:
            raise NotWorktree("Project code RAG requires a Git worktree")
        raise ValueError("Project code RAG requires a readable Git worktree")
    return proc.stdout


def project_paths(
    directory: Path, mb_path: Path | None = None, *, require_git: bool = False
) -> tuple[Path, Path]:
    """Resolve lifecycle and search against the same worktree and registered bank."""
    try:
        raw = _git(directory, "rev-parse", "--show-toplevel").removesuffix(b"\n")
        root = Path(os.fsdecode(raw)).resolve()
    except NotWorktree:
        if require_git:
            raise
        root = directory.resolve()  # Retain non-Git text search; enrollment checks eligibility.
    if mb_path is not None:
        return root, mb_path.resolve()
    if override := os.getenv("MB_PATH"):
        return root, (root / override).resolve()
    bank = root / ".memory-bank"
    if not bank.is_dir() and (os.getenv("MB_AGENT") or (root / ".claude-workspace").is_file()):
        # Run the shipped resolver, not a script or interpreter from the indexed checkout.
        lib = Path(__file__).resolve().with_name("_lib.sh")
        output = subprocess.check_output(
            ["/bin/bash", "-c", 'source "$1"; mb_resolve_path', "rag", lib],
            cwd=root,
            env={
                "PATH": os.defpath,
                "HOME": str(Path.home()),
                "PYTHONSAFEPATH": "1",
                "MB_PYTHON": sys.executable,
                "MB_AGENT": os.getenv("MB_AGENT", ""),
                "CODEX_HOME": os.getenv("CODEX_HOME", ""),
            },
        )
        bank = root / os.fsdecode(output.removesuffix(b"\n"))
    return root, bank.resolve()


def _tracked(root: Path, bank: Path) -> Iterator[Path]:
    for entry in _git(root, "ls-files", "--stage", "-z", "--", ".").split(b"\0"):
        if not entry:
            continue
        header, raw = entry.split(b"\t", 1)
        mode, _, stage = header.split()
        if stage != b"0" or mode not in (b"100644", b"100755"):
            continue
        try:
            path = Path(raw.decode("utf-8"))
        except UnicodeDecodeError:
            continue
        if (
            path.is_absolute()
            or path.suffix.lower() not in _EXTENSIONS
            or (root / path).is_relative_to(bank)
            or any(
                p.startswith(".") or p.lower() in _EXCLUDED or _SENSITIVE.search(p.lower())
                for p in path.parts
            )
        ):
            continue
        yield path


def has_tracked_source(root: Path, bank: Path) -> bool:
    """An onboarding check needs only the index names, not the source contents."""
    return next(_tracked(root, bank), None) is not None


def _chunks(path: str, text: str, docs: list[tuple[str, str]], rows: list[Row]) -> None:
    text = "\n".join(redact_private_lines(text))
    line = 1
    for start in range(0, len(text), 2400):
        body = text[start : start + 2400]
        if body.strip():
            rows.append((path, line, line + body.rstrip("\n").count("\n")))
            docs.append((str(len(docs)), f"{path}\n{body}"))
        line += body.count("\n")


def inventory(
    root: Path, bank: Path, *, read: bool = False
) -> tuple[str, list[tuple[str, str]], list[Row]]:
    """Stat-only on query; no content hashing or embedding of uncommitted changes."""
    fingerprint = hashlib.sha256()
    docs: list[tuple[str, str]] = []
    rows: list[Row] = []
    with ExitStack() as base:
        root_fd = os.open(root, _DIR)
        base.callback(os.close, root_fd)
        for parent, group in groupby(_tracked(root, bank), key=lambda p: p.parent):
            with ExitStack() as stack:
                fd = root_fd
                try:
                    # Anchor each lookup to a real directory; never follow a replaced parent.
                    for part in parent.parts:
                        fd = os.open(part, _DIR, dir_fd=fd)
                        stack.callback(os.close, fd)
                except OSError as exc:
                    if exc.errno in {errno.ENOENT, errno.ENOTDIR, errno.ELOOP}:
                        continue
                    raise
                for path in group:
                    try:
                        info = os.stat(path.name, dir_fd=fd, follow_symlinks=False)
                    except FileNotFoundError:
                        continue  # Tracked, deleted from the working copy.
                    if not stat.S_ISREG(info.st_mode) or info.st_size > _MAX_SOURCE:
                        continue
                    signature = (info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
                    fingerprint.update(f"{path}\0{signature}\0".encode())
                    if not read:
                        continue
                    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                    with os.fdopen(os.open(path.name, flags, dir_fd=fd), "rb") as source:
                        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                            raise RuntimeError(f"Source changed during RAG update: {path}")
                        raw = source.read(_MAX_SOURCE + 1)
                    if b"\0" not in raw and len(raw) <= _MAX_SOURCE:
                        try:
                            _chunks(str(path), raw.decode("utf-8"), docs, rows)
                        except UnicodeDecodeError:
                            continue
    return fingerprint.hexdigest(), docs, rows
