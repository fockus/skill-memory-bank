"""Community-summary retrieval for semantic search (REQ-008, design §A5).

When a wiki ARTICLE scores in the top-3 final hits, the search engine appends a
labeled block of its community's member files (capped at ≤10, stable order) so
the caller gets the surrounding cluster, not just the summary article.

The authoritative article→member-files mapping lives in
``<mb>/codebase/.wiki-packs.json`` (written by ``mb-wiki.py packs``): a list of
``{"community_id": N, "files": [...]}``. An article hit's ``id`` is
``wiki/community-N.md`` (see ``semantic_search.build_corpus``), so the integer
``N`` joins the two.

Fail-open throughout: missing/malformed packs, an article outside the top-3, or
an article with no mapping entry all yield no expansion (exact no-op).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

#: Member files appended per article are capped here (design §A5).
MAX_COMMUNITY_FILES = 10
#: Only an article landing in the top-N final hits triggers expansion.
TOP_N = 3
_PACKS_FILE = ".wiki-packs.json"


def load_community_files(codebase_dir: Path | str) -> dict[str, list[str]]:
    """Map ``wiki/community-N.md`` → sorted, capped member files from the packs file.

    Reads ``<codebase_dir>/.wiki-packs.json`` (written by ``mb-wiki.py packs``).
    Each entry's ``files`` list is sorted for determinism and truncated to
    ``MAX_COMMUNITY_FILES``. Absent file, invalid JSON, or an unexpected shape →
    ``{}`` (fail-open — no wiki/packs means no expansion).
    """
    path = Path(codebase_dir) / _PACKS_FILE
    if not path.is_file():
        return {}
    try:
        with path.open(encoding="utf-8") as stream:
            packs = json.load(stream)
    except (json.JSONDecodeError, UnicodeDecodeError, OSError):
        return {}
    if not isinstance(packs, list):
        return {}

    mapping: dict[str, list[str]] = {}
    for pack in packs:
        if not isinstance(pack, dict):
            continue
        cid = pack.get("community_id")
        files = pack.get("files")
        # bool is an int subclass — reject it so ``True`` never poses as a community id.
        if isinstance(cid, bool) or not isinstance(cid, int) or not isinstance(files, list):
            continue
        names = sorted(f for f in files if isinstance(f, str) and f)
        if not names:
            continue
        mapping[f"wiki/community-{cid}.md"] = names[:MAX_COMMUNITY_FILES]
    return mapping


def expand_hits(
    hits: list[dict[str, Any]],
    community_files: dict[str, list[str]],
) -> list[dict[str, Any]]:
    """Return expansion blocks for wiki articles among the top-``TOP_N`` *hits*.

    A block is ``{"article": <hit id>, "files": [...]}`` for each ``kind == "wiki"``
    hit in the top-``TOP_N`` whose id has a mapping entry. Order follows hit rank;
    each article expands at most once. Empty mapping / no article in the window /
    article without a mapping entry → ``[]`` (exact no-op).
    """
    if not community_files:
        return []
    blocks: list[dict[str, Any]] = []
    seen: set[str] = set()
    for hit in hits[:TOP_N]:
        if hit.get("kind") != "wiki":
            continue
        article_id = str(hit.get("id", ""))
        if article_id in seen:
            continue
        files = community_files.get(article_id)
        if not files:
            continue
        seen.add(article_id)
        blocks.append({"article": article_id, "files": files})
    return blocks


def render_blocks_md(blocks: list[dict[str, Any]]) -> list[str]:
    """Render expansion *blocks* as markdown lines (human-readable half of §A5).

    Mirrors the machine-readable ``community_files`` structure: one labeled
    section per article followed by its member files. Empty list → no lines, so
    the no-wiki render stays byte-identical.
    """
    lines: list[str] = []
    for block in blocks:
        lines.append("")
        lines.append(f"## Community files for `{block['article']}`")
        lines.extend(f"- `{f}`" for f in block["files"])
    return lines
