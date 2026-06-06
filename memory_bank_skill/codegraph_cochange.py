"""Git co-change file edges for the Memory Bank code graph (opt-in).

Files that change together across commits are coupled regardless of static
imports/calls — a deterministic, $0 signal derived purely from ``git log``. This
is information the AST/tree-sitter graph cannot see (e.g. a config file and the
code that reads it, a test and its subject).

Public surface (consumed by ``mb-codegraph.py``):
    ``co_change_edges`` · ``render_cochange_section``
    ``parse_git_log`` · ``count_pairs`` (pure, exported for testing)

Gracefully degrades to ``[]`` outside a git repo or when ``git`` is absent —
never raises. ``git`` is already a required Memory Bank dependency, so this adds
no new requirement.
"""

from __future__ import annotations

import subprocess
from collections import Counter
from itertools import combinations
from pathlib import Path
from typing import Any

_WINDOW = 200               # commits scanned (most recent)
_MIN_SHARED = 2             # a pair needs ≥2 shared commits to be an edge
_MAX_FILES_PER_COMMIT = 25  # commits touching more files are bulk noise → skipped
_MAX_PAIRS = 100            # cap edges emitted (highest weight kept)
_TOP_DISPLAY = 20           # rows in the markdown section
_NUL = "\x00"


def parse_git_log(raw: str) -> list[set[str]]:
    """Split ``git log --name-only --format=%x00`` output into per-commit file-sets.

    Each commit is introduced by a NUL record marker; file names follow on their
    own lines. Empty / whitespace-only records are dropped.
    """
    commits: list[set[str]] = []
    for record in raw.split(_NUL):
        files = {line.strip() for line in record.splitlines() if line.strip()}
        if files:
            commits.append(files)
    return commits


def count_pairs(
    commits: list[set[str]],
    known_files: set[str],
    *,
    min_shared: int = _MIN_SHARED,
    max_files_per_commit: int = _MAX_FILES_PER_COMMIT,
    max_pairs: int = _MAX_PAIRS,
) -> list[tuple[str, str, int]]:
    """Co-occurrence pair counts → ``[(file_a, file_b, weight)]``.

    Filters: bulk commits (> ``max_files_per_commit`` total changed files) are
    skipped; only files present in ``known_files`` (graph nodes) are paired.
    Deterministic order: weight desc, then lexical. Capped at ``max_pairs``.
    """
    known = set(known_files)
    counter: Counter[tuple[str, str]] = Counter()
    for files in commits:
        if len(files) > max_files_per_commit:
            continue
        relevant = sorted(f for f in files if f in known)
        if len(relevant) < 2:
            continue
        for a, b in combinations(relevant, 2):
            counter[(a, b)] += 1
    pairs = [(a, b, n) for (a, b), n in counter.items() if n >= min_shared]
    pairs.sort(key=lambda t: (-t[2], t[0], t[1]))
    return pairs[:max_pairs]


def _git_log(src_root: Path, window: int) -> str | None:
    """Run ``git log`` for ``window`` commits. Returns None when git unavailable."""
    try:
        result = subprocess.run(
            ["git", "-C", str(src_root), "log", "--no-merges", "--name-only",
             "-n", str(window), "--format=%x00"],
            capture_output=True, text=True, timeout=60, check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def _git_toplevel(src_root: Path) -> Path | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(src_root), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return None
    if result.returncode != 0:
        return None
    return Path(result.stdout.strip())


def _reroot(commits: list[set[str]], prefix: str) -> list[set[str]]:
    """Strip ``prefix/`` from git-toplevel-relative paths → src_root-relative.

    Paths outside ``prefix`` are dropped; they cannot belong to the scanned
    src_root and therefore cannot match a graph node.
    """
    if not prefix:
        return commits
    head = prefix + "/"
    out: list[set[str]] = []
    for files in commits:
        out.append({f[len(head):] for f in files if f.startswith(head)})
    return out


def co_change_edges(
    src_root: Path | str,
    known_files: set[str],
    *,
    window: int = _WINDOW,
    min_shared: int = _MIN_SHARED,
    max_files_per_commit: int = _MAX_FILES_PER_COMMIT,
    max_pairs: int = _MAX_PAIRS,
) -> list[dict[str, Any]]:
    """Deterministic git co-change edges for files present in the graph.

    Returns ``[{"src": a, "dst": b, "kind": "co_change", "weight": n}]`` with
    ``a < b``. Empty when ``src_root`` is not in a git repo or git is missing.
    """
    root = Path(src_root)
    raw = _git_log(root, window)
    if raw is None:
        return []
    commits = parse_git_log(raw)
    toplevel = _git_toplevel(root)
    if toplevel is not None:
        try:
            prefix = root.resolve().relative_to(toplevel.resolve()).as_posix()
        except ValueError:
            prefix = ""
        if prefix and prefix != ".":
            commits = _reroot(commits, prefix)
    pairs = count_pairs(
        commits, known_files,
        min_shared=min_shared,
        max_files_per_commit=max_files_per_commit,
        max_pairs=max_pairs,
    )
    return [{"src": a, "dst": b, "kind": "co_change", "weight": n} for a, b, n in pairs]


def render_cochange_section(edges: list[dict[str, Any]]) -> str:
    """Markdown section for ``god-nodes.md`` listing the top co-changing pairs."""
    lines = [
        "## Co-changing file pairs (git history)",
        "",
        "_Files that change together across commits — coupling the static graph misses._",
        "",
    ]
    if not edges:
        lines.append("_No co-change signal (need ≥2 shared commits)._")
        return "\n".join(lines)
    header = ["#", "File A", "File B", "Commits together"]
    lines.append("| " + " | ".join(header) + " |")
    lines.append("|" + "|".join("---" for _ in header) + "|")
    for i, e in enumerate(edges[:_TOP_DISPLAY], 1):
        lines.append(f"| {i} | `{e['src']}` | `{e['dst']}` | {e['weight']} |")
    return "\n".join(lines)
