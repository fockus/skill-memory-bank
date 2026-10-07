"""Parallel wave assignment for `/mb work` items (AGR-073).

Items are scanned in order. An item joins the current wave when it declares a
non-empty file set that is disjoint from every member of that wave and it does
not depend on any of them; otherwise it opens the next wave. An item without
declared files always gets a wave of its own, so plans without ``Files:``
lines run strictly one item per wave, exactly as before waves existed.

File sets: plan stages declare ``**Files:** a, b`` (backticks tolerated, HTML
comments ignored); spec tasks use their C1 ``**Scope:**`` (the ``**`` default
counts as undeclared). Dependencies: spec tasks use the parsed ``blocked_by``
(C1 default = previous task); plan stages only an explicit ``**Blocked-by:**``.
"""

from __future__ import annotations

import re

_FILES_RE = re.compile(r"^\s*\*\*Files:\*\*(.*)$", re.M | re.I)
_BLOCKED_RE = re.compile(r"^\s*\*\*Blocked-by:\*\*", re.M | re.I)
_COMMENT_RE = re.compile(r"<!--.*?-->")


def declared_files(item: dict) -> set[str]:
    """Return the item's declared file set (empty = undeclared)."""
    files: set[str] = set()
    for raw in _FILES_RE.findall(item.get("body", "")):
        for part in _COMMENT_RE.sub("", raw).split(","):
            path = part.strip().strip("`").strip()
            path = path[2:] if path.startswith("./") else path
            if path:
                files.add(path)
    if item.get("source") == "spec":
        files |= {s for s in item.get("scope") or [] if s != "**"}
    return files


def _deps(item: dict) -> set[str]:
    if item.get("source") == "spec" or _BLOCKED_RE.search(item.get("body", "")):
        return {str(ref) for ref in item.get("blocked_by") or []}
    return set()


def _overlap(a: str, b: str) -> bool:
    """Conservative path/glob overlap: equal, directory prefix, or glob prefix."""
    if "*" in a or "*" in b:
        pa, pb = a.split("*", 1)[0], b.split("*", 1)[0]
        return pa.startswith(pb) or pb.startswith(pa)
    da, db = a.rstrip("/") + "/", b.rstrip("/") + "/"
    return da.startswith(db) or db.startswith(da)


def assign_waves(items: list[dict]) -> list[int]:
    """Return a 1-based wave number per item, in input order."""
    waves: list[int] = []
    wave, members = 0, []  # members: (item_no, files) of the current wave
    for item in items:
        files = declared_files(item)
        joins = (
            bool(files)
            and bool(members)
            and not any(
                str(no) in _deps(item) or any(_overlap(f, g) for f in files for g in mfiles)
                for no, mfiles in members
            )
        )
        if not joins:
            wave, members = wave + 1, []
        members.append((item["item_no"], files or {"*"}))
        waves.append(wave)
    return waves
