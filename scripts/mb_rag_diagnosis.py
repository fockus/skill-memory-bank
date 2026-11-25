"""Side-effect-free health check shared by RAG status, retrieval and background updates."""

from __future__ import annotations

import json
import os
import stat
from pathlib import Path

from mb_project_rag import Publication, check_provider, check_qmd_paths
from mb_project_rag_corpus import inventory


def _present(
    base: Path, name: str, prefix: bytes = b"", *, size: int | None = None, empty_manifest: bool = False
) -> bool:
    path = base / name
    if not path.resolve().is_relative_to(base):
        raise ValueError(f"Unexpected symlink in private RAG store: {name}")
    try:
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or not info.st_size:
            return False
        if size is not None and info.st_size != size:
            return False
        if not os.access(path, os.R_OK):
            raise PermissionError(f"Cannot read RAG artifact: {name}")
        if not prefix:
            return True
        with path.open("rb") as stream:
            if path.suffix != ".json":
                return stream.read(len(prefix)) == prefix
            if empty_manifest:
                return stream.read(3) == b"[]"
            # Bound manifest inspection independently of the number of indexed chunks.
            if info.st_size > 4096:
                start = stream.read(len(prefix))
                stream.seek(-1, os.SEEK_END)
                return start == prefix and stream.read(1) == b"]"
            try:
                rows = json.load(stream)
            except ValueError:
                return False
            if not isinstance(rows, list) or not rows:
                return False
            if name == "rows.json":
                return all(
                    isinstance(row, list)
                    and len(row) == 3
                    and isinstance(row[0], str)
                    and isinstance(row[1], int)
                    and isinstance(row[2], int)
                    and 0 < row[1] <= row[2]
                    for row in rows
                )
            return all(isinstance(row, str) and row.isdecimal() for row in rows)
    except FileNotFoundError:
        return False


def diagnose(active: Publication, root: Path, bank: Path) -> dict[str, str]:
    """Return a fingerprint only for an intact, stale publication."""
    # Provider shims hold the pinned filenames. Neither imports an embedding runtime.
    check_provider(active.model)
    indexes: tuple[tuple[str, bytes], ...]
    if active.model == "qwen3":
        import mb_rag_qmd as qmd

        weights_ready = _present(active.cache, qmd._MODEL, b"GGUF", size=qmd._MODEL_BYTES)
        indexes = (("index/code.sqlite", b"SQLite format 3\0"),)
    else:
        import mb_rag_pplx as pplx

        weights = (
            "pplx-venv/pyvenv.cfg",
            "pplx-venv/bin/python",
            *(f"{pplx._MODEL}/{name}" for name in pplx._FILES),
        )
        weights_ready = all(_present(active.cache, name) for name in weights)
        indexes = (("index/pplx.npy", b"\x93NUMPY"), ("index/pplx-ids.json", b'["'))
    result = {"status": "broken", "model": active.model}
    if not weights_ready:
        return {
            **result,
            "reason": "Missing or invalid model or runtime files.",
            "action": f"memory-bank rag init --model {active.model}",
        }
    # Deleting the last source publishes genuinely empty rows and content hashes.
    empty = _present(active.generation, "hashes.json", b"[", size=2, empty_manifest=True)
    if not all(
        _present(active.generation, name, sig, empty_manifest=empty)
        for name, sig in (("rows.json", b"[["), *indexes)
    ):
        return {
            **result,
            "reason": "Missing or invalid published index.",
            "action": "memory-bank rag update",
        }
    if active.model == "qwen3":
        # This checks executable paths and pinned package metadata, without running Node.
        check_qmd_paths(root, bank)
        try:
            qmd._runtime()
        except AttributeError as exc:
            raise ValueError(
                "Invalid QMD package metadata; check the system QMD installation."
            ) from exc
    elif not os.access(pplx._runtime(active.cache), os.X_OK):
        return {**result, "reason": "Perplexity's private Python is not executable."}
    fingerprint = inventory(root, bank)[0]
    if fingerprint != active.fingerprint:
        return {"status": "stale", "model": active.model, "fingerprint": fingerprint}
    return {"status": "ready", "model": active.model}
