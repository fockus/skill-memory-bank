"""Numpy-backed vector store: per-source blocks, cosine search, incremental manifest."""
from __future__ import annotations
import json
import os
import numpy as np
from pathlib import Path


class Store:
    def __init__(self, index_dir):
        self.dir = Path(index_dir)
        self.model_name = None
        # source -> {"mtime": float, "sha": str, "meta": list[dict], "vectors": np.ndarray}
        self._blocks: dict[str, dict] = {}

    # ---- lifecycle ----
    def set_model(self, name: str):
        if self.model_name is not None and name != self.model_name:
            self._blocks = {}          # incompatible index → reset
        self.model_name = name

    def load(self) -> bool:
        vpath, mpath, man, mod = self._paths()
        if not (vpath.exists() and mpath.exists() and man.exists()):
            return False
        try:
            vectors = np.load(vpath)
            meta = [json.loads(l) for l in mpath.read_text().splitlines() if l.strip()]
            manifest = json.loads(man.read_text())
            self.model_name = mod.read_text().strip() if mod.exists() else None
        except Exception:
            return False
        dim = vectors.shape[1] if vectors.ndim == 2 else 0
        self._blocks = {}
        for src, info in manifest.items():
            rows = info.get("rows", [])
            self._blocks[src] = {
                "mtime": info["mtime"], "sha": info["sha"],
                "meta": [meta[i] for i in rows],
                "vectors": vectors[rows] if rows else np.zeros((0, dim), np.float32),
            }
        return True

    def save(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        vpath, mpath, man, mod = self._paths()
        rows_blocks, meta, manifest = [], [], {}
        cursor = 0
        for src in sorted(self._blocks):
            blk = self._blocks[src]
            n = len(blk["meta"])
            manifest[src] = {"mtime": blk["mtime"], "sha": blk["sha"],
                             "rows": list(range(cursor, cursor + n))}
            meta.extend(blk["meta"])
            if n:
                rows_blocks.append(np.asarray(blk["vectors"], np.float32))
            cursor += n
        matrix = np.vstack(rows_blocks) if rows_blocks else np.zeros((0, 0), np.float32)
        self._atomic_npy(vpath, matrix)
        self._atomic_text(mpath, "\n".join(json.dumps(m, ensure_ascii=False) for m in meta))
        self._atomic_text(man, json.dumps(manifest, ensure_ascii=False))
        self._atomic_text(mod, self.model_name or "")

    # ---- mutate ----
    def needs_reindex(self, source: str, mtime: float, sha: str) -> bool:
        blk = self._blocks.get(source)
        return not (blk and blk["sha"] == sha and blk["mtime"] == mtime)

    def upsert(self, source, mtime, sha, chunks, vectors):
        self._blocks[source] = {"mtime": mtime, "sha": sha,
                                "meta": list(chunks), "vectors": np.asarray(vectors, np.float32)}

    def remove(self, source):
        self._blocks.pop(source, None)

    def prune(self, keep: set):
        for src in [s for s in self._blocks if s not in keep]:
            del self._blocks[src]

    def sources(self) -> set:
        return set(self._blocks)

    # ---- query ----
    def search(self, qvec, top_k=5, min_score=0.35) -> list[dict]:
        flat_v, flat_m = [], []
        for blk in self._blocks.values():
            if len(blk["meta"]):
                flat_v.append(np.asarray(blk["vectors"], np.float32))
                flat_m.extend(blk["meta"])
        if not flat_v:
            return []
        matrix = np.vstack(flat_v)
        q = np.asarray(qvec, np.float32).reshape(-1)
        if matrix.shape[1] != q.shape[0]:
            return []
        scores = matrix @ q                       # vectors are L2-normalized → cosine
        order = np.argsort(-scores)[:top_k]
        out = []
        for i in order:
            sc = float(scores[int(i)])
            if sc < min_score:
                continue
            m = dict(flat_m[int(i)])
            m["score"] = round(sc, 4)
            out.append(m)
        return out

    def stats(self) -> dict:
        return {"chunks": sum(len(b["meta"]) for b in self._blocks.values()),
                "sources": len(self._blocks), "model": self.model_name}

    # ---- internals ----
    def _paths(self):
        return (self.dir / "vectors.npy", self.dir / "meta.jsonl",
                self.dir / "manifest.json", self.dir / "model.txt")

    def _atomic_npy(self, path: Path, matrix: np.ndarray):
        tmp = path.with_name(path.name + f".tmp{os.getpid()}")
        with open(tmp, "wb") as fh:
            np.save(fh, matrix, allow_pickle=False)
        os.replace(tmp, path)

    def _atomic_text(self, path: Path, text: str):
        tmp = path.with_name(path.name + f".tmp{os.getpid()}")
        tmp.write_text(text)
        os.replace(tmp, path)
