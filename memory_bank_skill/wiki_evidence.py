"""Deterministic per-community evidence packs for the `/mb wiki` LLM pass.

For each Louvain community (computed by ``codegraph_analytics``), gather the member
files, key symbols ranked by degree, and short code excerpts. This is the pure,
testable prep the command feeds to Haiku subagents — no LLM, no network here.
"""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path
from typing import Any

from memory_bank_skill import codegraph_analytics as cga

_MAX_FILES = 12
_MAX_EXCERPT_LINES = 40
_MAX_KEY_SYMBOLS = 10


def _within(candidate: Path, root: Path) -> bool:
    """True when ``candidate`` is inside ``root`` (containment guard for excerpt reads)."""
    try:
        candidate.relative_to(root)
        return True
    except ValueError:
        return False


def build_community_packs(
    nodes: list[dict[str, Any]],
    edges: list[dict[str, Any]],
    communities: dict[str, int] | None,
    code_root: Path | str,
    *,
    max_files: int = _MAX_FILES,
    max_excerpt_lines: int = _MAX_EXCERPT_LINES,
) -> list[dict[str, Any]]:
    """Return one pack per community: ``{community_id, files, key_symbols, excerpts}``."""
    if not communities:
        return []

    root = Path(code_root)
    root_resolved = root.resolve()
    degree = cga.compute_degree({"nodes": nodes, "edges": edges})

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
                key_symbols.append({
                    "name": n["name"],
                    "file": file_name,
                    "line": n.get("line", 0),
                    "degree": degree.get(n["name"], 0),
                })
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

        packs.append({
            "community_id": cid,
            "files": files,
            "key_symbols": key_symbols[:_MAX_KEY_SYMBOLS],
            "excerpts": excerpts,
        })
    return packs
