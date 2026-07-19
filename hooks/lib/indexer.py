"""Discover sources, chunk, (optionally) embed, and persist the recall index.

I-132 discipline: every write goes through a non-blocking flock — concurrent
callers skip instead of stacking. The default BM25 branch is fully numpy-free
(meta.jsonl + manifest.json only; a stale vectors.npy is deleted), so the
per-prompt catch-up path imports nothing heavier than stdlib + the chunker.
The embeddings branch is opt-in, lazy-imports numpy/fastembed, and holds the
machine-wide model singleton lock, so at most one model-loading process can
exist per machine.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

from semantic_chunk import chunk_markdown, chunk_transcript

BM25_MODEL = "__bm25__"  # model.txt sentinel: chunk-only index, no vectors

_SKIPPED_LOCKED = {"indexed": 0, "sources": 0, "skipped": "locked"}


def _sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8", "ignore")).hexdigest()[:16]


def _transcript_dir(mb_root: Path):
    # ~/.claude/projects/<slug>/  where slug = project path with / and . → -
    proj = mb_root.parent
    slug = str(proj).replace("/", "-").replace(".", "-")
    cand = Path.home() / ".claude" / "projects" / slug
    return cand if cand.is_dir() else None


def _discover(mb_root: Path) -> list[tuple[str, str, str]]:
    """Return (abs_path, kind, source_id) for every indexable source.

    Durable decision files (agreements, progress) are first-class recall
    sources. Raw transcripts are opt-in (MB_SEMANTIC_INDEX_TRANSCRIPTS=1):
    session summaries already distill them, and unbounded transcript corpora
    are what made reindexers eat gigabytes (I-132).
    """
    items: list[tuple[str, str, str]] = []
    for fname, kind in (("agreements.md", "agreement"), ("progress.md", "progress")):
        f = mb_root / fname
        if f.is_file():
            items.append((str(f), kind, fname))
    for sub, kind in (("session", "session"), ("notes", "note")):
        d = mb_root / sub
        if d.is_dir():
            for f in sorted(d.glob("*.md")):
                items.append((str(f), kind, f"{sub}/{f.name}"))
    if os.environ.get("MB_SEMANTIC_INDEX_TRANSCRIPTS", "0") == "1":
        td = _transcript_dir(mb_root)
        if td:
            for f in sorted(td.glob("*.jsonl")):
                items.append((str(f), "transcript", f"transcript/{f.name}"))
    return items


def index_sources(mb_root, index_dir, sources=None, full=False, backend=None) -> dict:
    from searcher import model_lock_path, resolve_backend, try_lock  # no cycle at load time

    index_dir = Path(index_dir)
    with try_lock(index_dir / ".write.lock") as got:
        if not got:
            return dict(_SKIPPED_LOCKED)
        if resolve_backend(backend) == "embeddings":
            with try_lock(model_lock_path()) as got_model:
                if not got_model:
                    return dict(_SKIPPED_LOCKED)
                return _index_embeddings(Path(mb_root), index_dir, sources, full)
        return _index_bm25(Path(mb_root), index_dir, sources, full)


def prune_index(mb_root, index_dir) -> dict:
    """Drop index entries whose sources are gone. Locked; backend-aware."""
    from searcher import try_lock

    index_dir = Path(index_dir)
    with try_lock(index_dir / ".write.lock") as got:
        if not got:
            return {"pruned": 0, "skipped": "locked"}
        keep = {sid for _, _, sid in _discover(Path(mb_root))}
        if _read_model(index_dir) != BM25_MODEL:
            return _prune_embeddings(index_dir, keep)
        blocks = _load_meta_state(index_dir)
        if not blocks:
            return {"pruned": 0}
        before = len(blocks)
        blocks = {s: b for s, b in blocks.items() if s in keep}
        _save_meta_state(index_dir, blocks)
        return {"pruned": before - len(blocks)}


# ---- BM25 branch: numpy-free meta store ----


def _read_model(index_dir: Path) -> str:
    try:
        return (index_dir / "model.txt").read_text().strip()
    except OSError:
        return ""


def _load_meta_state(index_dir: Path) -> dict:
    """manifest + flat meta rows → {source: {mtime, sha, meta}}; {} when absent/corrupt."""
    try:
        manifest = json.loads((index_dir / "manifest.json").read_text())
        lines = (index_dir / "meta.jsonl").read_text().splitlines()
        meta = [json.loads(line) for line in lines if line.strip()]
        blocks = {}
        for src, info in manifest.items():
            blocks[src] = {
                "mtime": info["mtime"],
                "sha": info["sha"],
                "meta": [meta[i] for i in info.get("rows", [])],
            }
        return blocks
    except Exception:
        return {}


def _save_meta_state(index_dir: Path, blocks: dict) -> None:
    index_dir.mkdir(parents=True, exist_ok=True)
    meta, manifest, cursor = [], {}, 0
    for src in sorted(blocks):
        blk = blocks[src]
        n = len(blk["meta"])
        manifest[src] = {
            "mtime": blk["mtime"],
            "sha": blk["sha"],
            "rows": list(range(cursor, cursor + n)),
        }
        meta.extend(blk["meta"])
        cursor += n
    _atomic_text(
        index_dir / "meta.jsonl", "\n".join(json.dumps(m, ensure_ascii=False) for m in meta)
    )
    _atomic_text(index_dir / "manifest.json", json.dumps(manifest, ensure_ascii=False))
    _atomic_text(index_dir / "model.txt", BM25_MODEL)
    # Stale cosine data must not survive a backend switch — rows no longer align.
    (index_dir / "vectors.npy").unlink(missing_ok=True)


def _atomic_text(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + f".tmp{os.getpid()}")
    tmp.write_text(text)
    os.replace(tmp, path)


def _index_bm25(mb_root: Path, index_dir: Path, sources, full) -> dict:
    blocks = _load_meta_state(index_dir) if _read_model(index_dir) == BM25_MODEL else {}
    discovered = _discover(mb_root)
    if sources:  # restrict to explicit paths (incremental)
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
        blk = blocks.get(sid)
        if not full and blk and blk["sha"] == sha and blk["mtime"] == mtime:
            continue
        chunks = (
            chunk_transcript(raw, sid) if kind == "transcript" else chunk_markdown(raw, sid, kind)
        )
        if not chunks:
            blocks.pop(sid, None)
            continue
        blocks[sid] = {"mtime": mtime, "sha": sha, "meta": list(chunks)}
        indexed += 1

    # Prune only on a full-corpus pass; an incremental (sources=…) call must not drop others.
    if not sources:
        keep = {d[2] for d in _discover(mb_root)}
        blocks = {s: b for s, b in blocks.items() if s in keep}
    _save_meta_state(index_dir, blocks)
    return {"indexed": indexed, "sources": len(blocks)}


# ---- embeddings branch: opt-in, lazy heavy imports, model singleton held ----


def _index_embeddings(mb_root: Path, index_dir: Path, sources, full) -> dict:
    from semantic_embed import DEFAULT_MODEL, Embedder
    from semantic_store import Store

    model = os.environ.get("MB_SEMANTIC_MODEL", DEFAULT_MODEL)
    store = Store(index_dir)
    store.load()
    store.set_model(model)  # resets blocks if model (or backend) changed
    emb = Embedder(model)

    discovered = _discover(mb_root)
    if sources:  # restrict to explicit paths (incremental)
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
        chunks = (
            chunk_transcript(raw, sid) if kind == "transcript" else chunk_markdown(raw, sid, kind)
        )
        if not chunks:
            store.remove(sid)
            continue
        store.upsert(sid, mtime, sha, chunks, emb.embed([c["text"] for c in chunks]))
        indexed += 1

    if not sources:
        store.prune(keep={d[2] for d in _discover(mb_root)})
    store.save()
    return {"indexed": indexed, "sources": len(store.sources())}


def _prune_embeddings(index_dir: Path, keep: set) -> dict:
    from semantic_store import Store

    store = Store(index_dir)
    if not store.load():
        return {"pruned": 0}
    before = len(store.sources())
    store.prune(keep=keep)
    store.save()
    return {"pruned": before - len(store.sources())}
