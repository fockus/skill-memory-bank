"""Opt-in Perplexity ONNX Q4 provider. Only prepare() uses the network."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import venv
from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.request import urlopen

if TYPE_CHECKING:
    import numpy as np
    from numpy.typing import NDArray

_REVISION = "2c4d510dd4a732063c31a0f70193e35067b51fd8"
_MODEL = f"pplx-embed-v1-0.6b-{_REVISION}"
_URL = f"https://huggingface.co/perplexity-ai/pplx-embed-v1-0.6b/resolve/{_REVISION}"
_FILES = {
    "onnx/model_q4.onnx": "4fa24bd4b52fe1f5d09e777c24fb18bd5539a9e4d5adc328d318f26afd14f7de",
    "onnx/model_q4.onnx_data": "ce29c8d68888a0fc83a2dad08f156c4689445babddfec8581c76e0e49125fae8",
    "tokenizer.json": "c6fb5c5bbba5fa5f8332edfb6d8aa67bd7fb3d75365b1765f108201698eaebf5",
    "config.json": "f7865547ecc1c077c5b1f83913fb9816a6586c676ccf3e0f7f00105a1b0c1c6c",
}
_DEPS = ("numpy==2.4.6", "onnxruntime==1.31.1", "tokenizers==0.23.3")
_DIM = 1024


def _outside_project(path: Path) -> Path:
    resolved = path.resolve()
    for parent in (resolved, *resolved.parents):
        if (parent / ".git").exists() or (parent / ".memory-bank").is_dir():
            raise ValueError(f"Perplexity needs a user runtime outside the project: {path}")
    return resolved


def _runtime(cache: Path) -> Path:
    venv = _outside_project(cache) / "pplx-venv"
    python = venv / "bin" / "python"
    if venv.is_symlink() or python.parent.is_symlink() or not python.resolve().is_relative_to(venv):
        raise ValueError(f"Expected a private Perplexity venv outside the project: {venv}")
    return python


def _fetch(url: str, dest: Path, digest: str) -> None:
    if dest.is_file():
        with dest.open("rb") as existing:
            if hashlib.file_digest(existing, "sha256").hexdigest() == digest:
                return
    dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as out:
        partial = Path(out.name)
    try:
        with urlopen(url, timeout=90) as response, partial.open("wb") as stream:
            shutil.copyfileobj(response, stream, length=1 << 20)
        with partial.open("rb") as stream:
            if hashlib.file_digest(stream, "sha256").hexdigest() != digest:
                raise ValueError(f"Incorrect SHA-256 for {dest.name}; retry Perplexity setup")
        partial.replace(dest)
    finally:
        partial.unlink(missing_ok=True)


def prepare(cache: Path) -> None:
    """Install CPU wheels in the user cache and verify only the selected Q4 artifacts."""
    cache = cache.expanduser().resolve()
    python = _runtime(cache)
    env_dir = python.parent.parent
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not (env_dir / "pyvenv.cfg").is_file() or not python.is_file():
        venv.EnvBuilder(with_pip=True, symlinks=False).create(env_dir)
    subprocess.run(
        [
            python,
            "-I",
            "-m",
            "pip",
            "--isolated",
            "--require-virtualenv",
            "--disable-pip-version-check",
            "install",
            "--only-binary=:all:",
            *_DEPS,
        ],
        check=True,
        cwd=cache,
        stdout=sys.stderr,
        env={**os.environ, "PIP_CONFIG_FILE": os.devnull},
    )
    for name, digest in _FILES.items():
        _fetch(f"{_URL}/{name}", cache / _MODEL / name, digest)


def _run(action: str, index: Path, payload: object, cache: Path, k: int = 0) -> str:
    cache = cache.expanduser().resolve()
    python = _runtime(cache)
    if not (python.parent.parent / "pyvenv.cfg").is_file() or not python.is_file():
        raise RuntimeError("Perplexity runtime missing; run project RAG setup first")
    model = cache / _MODEL
    if any(not (model / name).is_file() for name in _FILES):
        raise RuntimeError("Perplexity Q4 model missing; run project RAG setup first")
    proc = subprocess.run(
        [python, "-I", "-B", Path(__file__).resolve(), action, index.resolve(), model, str(k)],
        cwd=cache,
        input=json.dumps(payload),
        text=True,
        stdout=subprocess.PIPE,
        check=True,
    )
    return proc.stdout


def build(index: Path, docs: list[tuple[str, str]], cache: Path) -> None:
    """Build inside the caller's private generation, without installing or downloading."""
    _run("build", index, docs, cache)


def refresh(
    index: Path,
    docs: list[tuple[str, str]],
    cache: Path,
    old: Path,
    reuse: list[int | None],
    max_new_chunks: int | None = None,
) -> bool:
    if max_new_chunks is not None and reuse.count(None) > max_new_chunks:
        return False
    return json.loads(_run("refresh", index, [docs, str(old), reuse], cache)) is True


def search(index: Path, query: str, k: int, cache: Path) -> list[str]:
    """Read a published generation; only document IDs leave the worker."""
    return json.loads(_run("search", index, query, cache, k)) if k > 0 else []


def _encoder(model: Path) -> Callable[[list[str]], NDArray[np.float32]]:
    import numpy as np
    import onnxruntime as ort
    from tokenizers import Tokenizer

    ort.disable_telemetry_events()
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(
        str(model / "onnx/model_q4.onnx"),
        options,
        providers=["CPUExecutionProvider"],
    )
    tokenizer = Tokenizer.from_file(str(model / "tokenizer.json"))
    tokenizer.enable_truncation(max_length=2048)
    pad = 151643

    def encode(texts: list[str]) -> NDArray[np.float32]:
        tokens = [tokenizer.encode(text).ids or [pad] for text in texts]
        ids = np.full((len(texts), max(map(len, tokens))), pad, dtype=np.int64)
        mask = np.zeros_like(ids)
        for i, row in enumerate(tokens):
            ids[i, : len(row)] = row
            mask[i, : len(row)] = 1
        vectors = np.asarray(
            session.run(["pooler_output"], {"input_ids": ids, "attention_mask": mask})[0],
            dtype=np.float32,
        )
        norms = np.linalg.norm(vectors, axis=1, keepdims=True)
        if not np.isfinite(norms).all() or (norms == 0).any():
            raise ValueError("Perplexity returned an invalid embedding")
        return vectors / norms

    return encode


def _build(
    index: Path,
    docs: list[tuple[str, str]],
    model: Path,
    old: Path | None = None,
    reuse: list[int | None] | None = None,
) -> bool:
    import numpy as np

    previous = None
    if old is not None:
        try:
            ids = json.loads((old / "pplx-ids.json").read_bytes())
            previous = np.load(old / "pplx.npy", allow_pickle=False, mmap_mode="r")
            if (
                not isinstance(ids, list)
                or not isinstance(previous, np.ndarray)
                or previous.shape != (len(ids), _DIM)
                or previous.dtype != np.float32
                or reuse is None
                or any(i is not None and not 0 <= i < len(ids) for i in reuse)
            ):
                return False
        except (FileNotFoundError, ValueError, EOFError):
            return False

    matrix = np.lib.format.open_memmap(
        index / "pplx.npy",
        mode="w+",
        dtype=np.float32,
        shape=(len(docs), _DIM),
    )
    missing: dict[str, list[int]] = {}
    for i, (_, text) in enumerate(docs):
        src = reuse[i] if reuse is not None else None
        if previous is not None and src is not None:
            matrix[i] = previous[src]
        else:
            missing.setdefault(text, []).append(i)
    if missing:
        embed = _encoder(model)
        order = sorted(missing, key=len)
        for start in range(0, len(order), 8):
            batch = order[start : start + 8]
            for text, vector in zip(batch, embed(batch), strict=True):
                matrix[missing[text]] = vector
    matrix.flush()
    (index / "pplx-ids.json").write_text(json.dumps([i for i, _ in docs]), encoding="utf-8")
    return True


def _search(index: Path, query: str, k: int, model: Path) -> list[str]:
    import numpy as np

    ids: list[str] = json.loads((index / "pplx-ids.json").read_text(encoding="utf-8"))
    if not ids:
        return []
    matrix = np.load(index / "pplx.npy", allow_pickle=False, mmap_mode="r")
    scores = matrix @ _encoder(model)([query])[0]
    return [ids[i] for i in np.argsort(-scores, kind="stable")[:k]]


if __name__ == "__main__":
    action, directory, model_dir, limit = sys.argv[1:]
    if action == "build":
        _build(Path(directory), json.load(sys.stdin), Path(model_dir))
    elif action == "refresh":
        docs, old, reuse = json.load(sys.stdin)
        print(json.dumps(_build(Path(directory), docs, Path(model_dir), Path(old), reuse)))
    elif action == "search":
        print(
            json.dumps(_search(Path(directory), json.load(sys.stdin), int(limit), Path(model_dir)))
        )
    else:
        raise SystemExit("Expected build, refresh or search")
