"""Wiki article IO + safe merge of LLM "surprising connection" edges into graph.json.

The deterministic IO half of `/mb wiki`: write per-community articles + an index
(atomically), and merge the Sonnet subagent's semantic edges into ``graph.json``
defensively — malformed input is dropped, confidence is clamped to [0, 1], and the
merge is **idempotent** (re-running never duplicates or corrupts the graph).
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any

from memory_bank_skill._io import atomic_write
from memory_bank_skill.codegraph_loader import load_graph

# Per-article graph hash recorded in index.md as an HTML comment so it is invisible
# in rendered Markdown yet trivially parseable. Example:
#   <!-- mb-wiki-hash:7 sha256=ab12… -->
_HASH_LINE = re.compile(r"<!--\s*mb-wiki-hash:(\d+)\s+sha256=([0-9a-f]+)\s*-->")


def _candidate_files(
    dst: str, sym_to_files: dict[str, tuple[str, ...]], sorted_names: list[str]
) -> set[str]:
    """All files that may define the edge target ``dst`` (homonym-safe).

    Mirrors ``codegraph_rank._resolve_dst`` semantics but resolves to *every*
    defining file, never a single winner: exact ``dst == name`` first (a qualified
    name resolves to itself), else the short-name / dotted-suffix fallback over the
    *sorted* node names — accumulating ALL matching definitions, not the
    alphabetically-first only. Returns the union of candidate files (possibly empty).

    Resolving to a set rather than one file keeps membership order-independent: when
    a name is defined in several files, the relationship belongs to each of their
    communities, so none is silently dropped by graph-record ordering.
    """
    exact = sym_to_files.get(dst)
    if exact is not None:
        return set(exact)
    out: set[str] = set()
    for name in sorted_names:
        short = name.split(".")[-1]
        if dst == short or dst.endswith(f".{short}"):
            out.update(sym_to_files[name])
    return out


def _record_in_files(
    record: dict[str, Any],
    files: set[str],
    sym_to_files: dict[str, tuple[str, ...]],
    sorted_names: list[str],
) -> bool:
    """True when a graph record references any of ``files``.

    A node references a file via its ``file`` field. An edge references a file when
    either endpoint is that file (``"<file>"``), a symbol defined in it
    (``"<file>:symbol"``), or a bare/dotted symbol (``atomic_write``,
    ``pkg.io.atomic_write``) whose set of defining files — derived from the node
    multi-map — *intersects* ``files``. The intersection rule captures relationship
    edges targeting a member's symbol even when that symbol's name is a homonym
    defined in several files (no last-wins resolution), while leaving the community
    hash independent of graph-record order.
    """
    if record.get("file") in files:
        return True
    for endpoint in (record.get("src"), record.get("dst")):
        if not isinstance(endpoint, str):
            continue
        head = endpoint.split(":", 1)[0]
        if head in files:
            return True
        # Bare/dotted symbol endpoint (no "file:" prefix): resolve to ALL defining
        # files and include the edge when any of them is a member (intersection).
        if ":" not in endpoint and _candidate_files(endpoint, sym_to_files, sorted_names) & files:
            return True
    return False


def community_hash(
    nodes: list[dict[str, Any]],
    edges: list[dict[str, Any]],
    files: list[str],
) -> str:
    """Content hash of a community, derived from its member files' graph records.

    Collects every node/edge touching a member file, serialises each with sorted
    keys, then hashes the *sorted set* of those serialisations — so the result is
    order-independent and changes iff a member file's nodes or edges change.
    Records of unrelated files do not affect it (incremental-rebuild precision).

    Edges are matched not only by literal path endpoints but also by resolving a
    bare/dotted ``dst`` symbol back to its defining file(s). The symbol→files map is
    a deterministic MULTI-map (name → sorted tuple of every defining file), and an
    edge is a member record when that candidate set *intersects* the member set —
    never via a single last-wins winner. So a relationship change targeting a
    member's symbol marks the community stale even when the symbol name is a
    homonym, and the hash is identical for the same logical graph in any record
    order.
    """
    member = set(files)
    name_files: dict[str, set[str]] = {}
    for n in nodes:
        name, file = n.get("name"), n.get("file")
        if isinstance(name, str) and isinstance(file, str):
            name_files.setdefault(name, set()).add(file)
    sym_to_files = {name: tuple(sorted(fs)) for name, fs in name_files.items()}
    sorted_names = sorted(sym_to_files)
    serialised = sorted(
        json.dumps(rec, sort_keys=True, ensure_ascii=False)
        for rec in (*nodes, *edges)
        if _record_in_files(rec, member, sym_to_files, sorted_names)
    )
    digest = hashlib.sha256()
    for line in serialised:
        digest.update(line.encode("utf-8"))
        digest.update(b"\n")
    return digest.hexdigest()


def parse_index_hashes(source: Path | str) -> dict[int, str]:
    """Read recorded per-community hashes from an ``index.md`` path or its text.

    Returns ``{community_id: sha256_hex}``. A legacy index without hash comments —
    or a missing file — yields an empty mapping (caller treats that as "rebuild
    everything", the safe default).
    """
    if isinstance(source, Path):
        if not source.is_file():
            return {}
        text = source.read_text(encoding="utf-8")
    else:
        text = source
    return {int(cid): digest for cid, digest in _HASH_LINE.findall(text)}


def article_path(wiki_dir: Path | str, community_id: int) -> Path:
    return Path(wiki_dir) / f"community-{community_id}.md"


def write_article(wiki_dir: Path | str, community_id: int, md: str) -> Path:
    """Atomically write one community article. Returns its path."""
    path = article_path(wiki_dir, community_id)
    atomic_write(path, md if md.endswith("\n") else md + "\n")
    return path


def write_index(
    wiki_dir: Path | str,
    packs: list[dict[str, Any]],
    articles: list[Path] | None = None,
    *,
    hashes: dict[int, str] | None = None,
) -> Path:
    """Write ``index.md`` linking every community article. Returns its path.

    When ``hashes`` is supplied, each community line is followed by an HTML-comment
    hash marker (``<!-- mb-wiki-hash:N sha256=… -->``) the staleness check reads on
    the next ``/mb wiki``. Recording is idempotent: identical packs + hashes produce
    a byte-identical file.
    """
    hashes = hashes or {}
    lines = [
        "# Codebase wiki",
        "",
        "_Generated by `/mb wiki` — one article per detected community._",
        "",
    ]
    for pack in packs:
        cid = pack["community_id"]
        files = pack.get("files", [])
        sample = ", ".join(files[:3]) + (" …" if len(files) > 3 else "")
        lines.append(f"- [Community {cid}](community-{cid}.md) — {len(files)} files: {sample}")
        digest = hashes.get(cid)
        if digest:
            lines.append(f"  <!-- mb-wiki-hash:{cid} sha256={digest} -->")
    path = Path(wiki_dir) / "index.md"
    atomic_write(path, "\n".join(lines) + "\n")
    return path


def validate_semantic_edges(raw: Any) -> list[dict[str, Any]]:
    """Parse/validate LLM-produced edges. Drops malformed; clamps confidence ∈ [0, 1]."""
    items = raw
    if isinstance(raw, str):
        try:
            items = json.loads(raw)
        except json.JSONDecodeError:
            return []
    if not isinstance(items, list):
        return []

    out: list[dict[str, Any]] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        src = item.get("src")
        dst = item.get("dst")
        if not isinstance(src, str) or not isinstance(dst, str) or not src or not dst:
            continue
        raw_conf = item.get("confidence", 0.5)
        # Reject bool (json true/false) and non-finite (NaN/inf) → default; never emit
        # bare NaN/Infinity which would make graph.json invalid JSON.
        if isinstance(raw_conf, bool):
            confidence = 0.5
        else:
            try:
                confidence = float(raw_conf)
            except (TypeError, ValueError):
                confidence = 0.5
            if not math.isfinite(confidence):
                confidence = 0.5
        confidence = max(0.0, min(1.0, confidence))
        edge: dict[str, Any] = {
            "src": src,
            "dst": dst,
            "kind": "semantic",
            "confidence": round(confidence, 3),
        }
        rationale = item.get("rationale")
        if isinstance(rationale, str) and rationale:
            edge["rationale"] = rationale
        out.append(edge)
    return out


def merge_semantic_edges(graph_path: Path | str, edges: list[dict[str, Any]]) -> int:
    """Append unique ``semantic`` edges to graph.json (idempotent). Returns count added.

    Dedupe key is ``(src, dst)`` among existing ``semantic`` edges. The original file
    text is preserved; new edges are appended as JSON-Lines records.
    """
    path = Path(graph_path)
    _, existing = load_graph(path)  # raises FileNotFoundError if absent — caller ensures it exists
    seen = {(e.get("src"), e.get("dst")) for e in existing if e.get("kind") == "semantic"}

    appended: list[str] = []
    for edge in edges:
        key = (edge.get("src"), edge.get("dst"))
        if None in key or key in seen:
            continue
        seen.add(key)
        appended.append(json.dumps({"type": "edge", **edge}, ensure_ascii=False))

    if not appended:
        return 0
    # newline="" preserves existing line endings (CRLF stays CRLF) — the merge is a
    # pure append, never a whole-file newline rewrite. Use open() rather than
    # Path.read_text(newline=...): the latter only gained `newline` in Python 3.13
    # and this package supports 3.11+.
    with path.open(encoding="utf-8", newline="") as fh:
        raw = fh.read()
    if not raw.endswith(("\n", "\r")):
        raw += "\n"
    atomic_write(path, raw + "\n".join(appended) + "\n")
    return len(appended)
