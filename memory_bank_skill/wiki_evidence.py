"""Deterministic per-community evidence packs for the `/mb wiki` LLM pass.

For each Louvain community (computed by ``codegraph_analytics``), gather the member
files, key symbols ranked by degree, and short code excerpts. This is the pure,
testable prep the command feeds to Haiku subagents — no LLM, no network here.
"""

from __future__ import annotations

import re
from collections import defaultdict
from pathlib import Path
from typing import Any

from memory_bank_skill import codegraph_analytics as cga

_MAX_FILES = 12
_MAX_EXCERPT_LINES = 40
_MAX_KEY_SYMBOLS = 10
_MAX_DECISIONS = 5
_DECISION_DIRS = ("notes", "session")

# A basename counts as a real mention only when it sits on a path/code TOKEN
# boundary: the char before is start-of-line, whitespace, a path separator, or
# a backtick (NOT a word char or dot — so `io.py` never matches inside
# `scenario.py`); the char after must not be a word char (`io.pyc`) nor a dot
# that starts a longer dotted token (`io.py.bak`) — but a sentence-final period
# (`fixed io.py.`) is a legitimate mention and stays matchable.
_LEADING_BOUNDARY = "(?:^|[\\s/\\\\`])"
_TRAILING_BOUNDARY = "(?!\\w)(?!\\.\\w)"


def _within(candidate: Path, root: Path) -> bool:
    """True when ``candidate`` is inside ``root`` (containment guard for excerpt reads)."""
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def _session_summary_lines(text: str) -> list[str]:
    """Return the decision-bearing lines of a session schema-v2 summary.

    Scans ONLY the ``## Summary`` body (so the frontmatter and the ``## Live
    log`` — both of which routinely echo file basenames — are excluded) and
    drops the ``### Files`` subsection, whose lines are a bare path list, not
    decisions. A session file without a ``## Summary`` yields no lines.
    """
    lines: list[str] = []
    in_summary = False
    in_files = False
    for raw in text.splitlines():
        stripped = raw.strip()
        if stripped.startswith("## "):
            # A top-level heading toggles the summary scope on/off.
            in_summary = stripped == "## Summary"
            in_files = False
            continue
        if not in_summary:
            continue
        if stripped.startswith("### "):
            # The ``### Files`` subsection is a path list — never a decision.
            in_files = stripped == "### Files"
            continue
        if in_files:
            continue
        if stripped:
            lines.append(stripped)
    return lines


def _decision_lines(mb_root: Path) -> list[tuple[str, str]] | None:
    """Read ``notes/`` + ``session/`` decision lines as ``(source_ref, line)`` pairs.

    ``notes/`` files are curated content, so they are scanned whole-file.
    ``session/`` files are machine-generated, so only their ``## Summary`` body
    is scanned (frontmatter, ``## Live log`` and the ``### Files`` path list are
    excluded — see :func:`_session_summary_lines`).

    ``source_ref`` is the POSIX-style path relative to ``mb_root`` (e.g.
    ``notes/2026-01-01_rrf.md``). Returns ``None`` when no decision-source file
    was read at all (missing/empty dirs) so the caller can omit the section;
    returns ``[]`` when files exist but yield no content lines.
    """
    candidates: list[tuple[str, str]] | None = None
    for sub in _DECISION_DIRS:
        directory = mb_root / sub
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.md")):
            if not path.is_file():
                continue
            if candidates is None:
                candidates = []
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            ref = f"{sub}/{path.name}"
            if sub == "session":
                for line in _session_summary_lines(text):
                    candidates.append((ref, line))
            else:
                for raw in text.splitlines():
                    line = raw.strip()
                    if line:
                        candidates.append((ref, line))
    return candidates


def _mentions_basename(line: str, basenames: set[str]) -> bool:
    """True when ``line`` names a basename on a path/code-token boundary.

    Guards against unbounded substring hits: ``io.py`` must NOT match inside the
    unrelated token ``scenario.py`` (or ``io.pyc``). A basename counts only when
    flanked by a leading boundary (start-of-line, whitespace, ``/``, ``\\`` or a
    backtick) and a trailing non-word, non-dot boundary.
    """
    for name in basenames:
        pattern = _LEADING_BOUNDARY + re.escape(name) + _TRAILING_BOUNDARY
        if re.search(pattern, line):
            return True
    return False


def _match_decisions(
    candidates: list[tuple[str, str]], basenames: set[str]
) -> list[dict[str, str]]:
    """Return up to ``_MAX_DECISIONS`` lines mentioning any file basename.

    Deterministic: candidates keep their source-then-file-order, each line is
    matched at most once, and the first ``_MAX_DECISIONS`` matches are kept.
    """
    matched: list[dict[str, str]] = []
    for ref, line in candidates:
        if _mentions_basename(line, basenames):
            matched.append({"line": line, "source": ref})
            if len(matched) >= _MAX_DECISIONS:
                break
    return matched


def build_community_packs(
    nodes: list[dict[str, Any]],
    edges: list[dict[str, Any]],
    communities: dict[str, int] | None,
    code_root: Path | str,
    *,
    max_files: int = _MAX_FILES,
    max_excerpt_lines: int = _MAX_EXCERPT_LINES,
    mb_root: Path | str | None = None,
) -> list[dict[str, Any]]:
    """Return one pack per community.

    Each pack is ``{community_id, files, key_symbols, excerpts}``; when ``mb_root``
    is supplied and at least one ``notes/``/``session/`` file is present, the pack
    also carries a ``decisions`` list (REQ-028) of lines mentioning the community's
    file basenames, each with a ``source`` ref. Without ``mb_root`` the pack is
    byte-identical to the legacy shape.
    """
    if not communities:
        return []

    root = Path(code_root)
    root_resolved = root.resolve()
    degree = cga.compute_degree({"nodes": nodes, "edges": edges})

    decision_candidates: list[tuple[str, str]] | None = None
    if mb_root is not None:
        decision_candidates = _decision_lines(Path(mb_root))

    members: dict[int, list[str]] = defaultdict(list)
    for file_name, cid in communities.items():
        members[cid].append(file_name)

    symbols_by_file: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for n in nodes:
        if n.get("kind") in ("function", "class"):
            symbols_by_file[str(n.get("file", ""))].append(n)

    packs: list[dict[str, Any]] = []
    for cid in sorted(members):
        files = sorted(members[cid])
        key_symbols: list[dict[str, Any]] = []
        for file_name in files:
            for n in symbols_by_file.get(file_name, []):
                key_symbols.append(
                    {
                        "name": n["name"],
                        "file": file_name,
                        "line": n.get("line", 0),
                        "degree": degree.get(n["name"], 0),
                    }
                )
        key_symbols.sort(key=lambda s: (-s["degree"], s["file"], s["name"]))

        excerpts: dict[str, str] = {}
        for file_name in files[:max_files]:
            candidate = (root / file_name).resolve()
            if not _within(candidate, root_resolved):
                continue  # absolute path / `../` escape — never read outside code_root
            lines: list[str] = []
            try:
                with candidate.open(encoding="utf-8", errors="replace") as handle:
                    for i, line in enumerate(handle):
                        if i >= max_excerpt_lines:
                            break  # bounded read — never slurp a huge file
                        lines.append(line.rstrip("\r\n"))
            except OSError:
                continue
            excerpts[file_name] = "\n".join(lines)

        pack: dict[str, Any] = {
            "community_id": cid,
            "files": files,
            "key_symbols": key_symbols[:_MAX_KEY_SYMBOLS],
            "excerpts": excerpts,
        }
        if decision_candidates is not None:
            basenames = {Path(f).name for f in files}
            pack["decisions"] = _match_decisions(decision_candidates, basenames)
        packs.append(pack)
    return packs
