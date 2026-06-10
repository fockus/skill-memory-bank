"""Discover sources, chunk, embed, and persist into the Store (incrementally)."""
from __future__ import annotations

import hashlib
import os
from pathlib import Path

from semantic_chunk import chunk_markdown, chunk_transcript
from semantic_embed import DEFAULT_MODEL, Embedder
from semantic_store import Store


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "ignore")).hexdigest()[:16]


def _transcript_dir(mb_root: Path):
    # ~/.claude/projects/<slug>/  where slug = project path with / and . → -
    proj = mb_root.parent
    slug = str(proj).replace("/", "-").replace(".", "-")
    cand = Path.home() / ".claude" / "projects" / slug
    return cand if cand.is_dir() else None


def _discover(mb_root: Path) -> list[tuple[str, str, str]]:
    """Return (abs_path, kind, source_id) for every indexable source."""
    items: list[tuple[str, str, str]] = []
    for sub, kind in (("session", "session"), ("notes", "note")):
        d = mb_root / sub
        if d.is_dir():
            for f in sorted(d.glob("*.md")):
                items.append((str(f), kind, f"{sub}/{f.name}"))
    if os.environ.get("MB_SEMANTIC_INDEX_TRANSCRIPTS", "1") != "0":
        td = _transcript_dir(mb_root)
        if td:
            for f in sorted(td.glob("*.jsonl")):
                items.append((str(f), "transcript", f"transcript/{f.name}"))
    return items


def index_sources(mb_root, index_dir, sources=None, full=False) -> dict:
    mb_root = Path(mb_root)
    model = os.environ.get("MB_SEMANTIC_MODEL", DEFAULT_MODEL)
    store = Store(index_dir)
    store.load()
    store.set_model(model)            # resets blocks if model changed
    emb = Embedder(model)

    discovered = _discover(mb_root)
    if sources:                       # restrict to explicit paths (SessionEnd incremental)
        want = set(sources)
        discovered = [d for d in discovered if d[0] in want or d[2] in want]

    indexed = 0
    for path, kind, sid in discovered:
        try:
            raw = Path(path).read_text(errors="ignore")
        except Exception:
            continue
        mtime = os.path.getmtime(path)
        sha = _sha(raw)
        if not full and not store.needs_reindex(sid, mtime, sha):
            continue
        chunks = (chunk_transcript(raw, sid) if kind == "transcript"
                  else chunk_markdown(raw, sid, kind))
        if not chunks:
            store.remove(sid)
            continue
        vectors = emb.embed([c["text"] for c in chunks])
        store.upsert(sid, mtime, sha, chunks, vectors)
        indexed += 1

    # Prune only on a full-corpus pass; an incremental (sources=…) call must not drop others.
    if not sources:
        store.prune(keep={d[2] for d in _discover(mb_root)})
    store.save()
    return {"indexed": indexed, "sources": len(store.sources())}


def prune_index(mb_root, index_dir) -> dict:
    mb_root = Path(mb_root)
    store = Store(index_dir)
    if not store.load():
        return {"pruned": 0}
    keep = {sid for _, _, sid in _discover(mb_root)}
    before = len(store.sources())
    store.prune(keep=keep)
    store.save()
    return {"pruned": before - len(store.sources())}
