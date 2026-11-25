"""Project-local QMD vector retrieval. Only prepare() can fetch model weights."""

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import urllib.request
from pathlib import Path

_MODEL = "Qwen3-Embedding-0.6B-Q8_0.gguf"
_MODEL_BYTES = 639_150_592
_SHA256 = "06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439"
_URL = (
    "https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/"
    f"resolve/370f27d7550e0def9b39c1f16d3fbaa13aa67728/{_MODEL}"
)
_INSTALL = "Install Node.js 22+ and run: npm install -g @tobilu/qmd@2.8.3"


def _runtime() -> tuple[Path, Path]:
    node, qmd = shutil.which("node"), shutil.which("qmd")
    if not node or not qmd:
        raise RuntimeError(_INSTALL)
    executable = Path(node).resolve()
    package = Path(qmd).resolve().parent.parent
    cwd = Path.cwd()
    for root in (cwd, *cwd.parents):
        if ((root / ".git").exists() or (root / ".memory-bank").is_dir()) and (
            executable.is_relative_to(root) or package.is_relative_to(root)
        ):
            raise RuntimeError(f"Refusing a project-local QMD runtime. {_INSTALL}")
    try:
        info = json.loads((package / "package.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise RuntimeError(_INSTALL) from exc
    if info.get("name") != "@tobilu/qmd" or info.get("version") != "2.8.3":
        raise RuntimeError(_INSTALL)
    return executable, package


def _verified(path: Path) -> bool:
    if not path.is_file():
        return False
    with path.open("rb") as data:
        return hashlib.file_digest(data, "sha256").hexdigest() == _SHA256


def prepare(cache: Path) -> None:
    _runtime()
    target = cache / _MODEL
    if _verified(target):
        return
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    home_cache = Path.home() / ".cache"
    xdg = Path(os.environ.get("XDG_CACHE_HOME") or home_cache)
    with tempfile.NamedTemporaryFile(dir=cache, delete=False) as temp:
        staging = Path(temp.name)
    try:
        for base in dict.fromkeys((xdg, home_cache)):
            existing = base / "qmd" / "models" / ("hf_Qwen_" + _MODEL)
            if existing.is_file():
                shutil.copyfile(existing, staging)
                if _verified(staging):
                    staging.replace(target)
                    return
        with urllib.request.urlopen(_URL, timeout=60) as src, staging.open("wb") as dest:
            shutil.copyfileobj(src, dest, length=1024 * 1024)
        if not _verified(staging):
            raise RuntimeError(f"SHA-256 mismatch for {_MODEL}; weights not installed")
        staging.replace(target)
    finally:
        staging.unlink(missing_ok=True)


def _run(action: str, index: Path, cache: Path, payload: object) -> str:
    model = cache.resolve() / _MODEL
    if not _verified(model):
        raise RuntimeError(f"Missing or invalid {_MODEL}; run project RAG setup")
    node, package = _runtime()
    bridge = Path(__file__).with_suffix(".mjs")
    result = subprocess.run(
        [node, bridge, package, action, index.resolve() / "code.sqlite", model],
        cwd=cache,
        input=json.dumps(payload, ensure_ascii=False),
        capture_output=True,
        encoding="utf-8",
        env={**os.environ, "GGML_METAL_NO_RESIDENCY": "1", "NODE_OPTIONS": "", "NODE_PATH": ""},
    )
    if result.returncode:
        raise RuntimeError(f"QMD {action} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def build(index: Path, docs: list[tuple[str, str]], cache: Path) -> None:
    _run("build", index, cache, docs)


def refresh(
    index: Path,
    docs: list[tuple[str, str]],
    cache: Path,
    old: Path,
    reuse: list[int | None],
    max_new_chunks: int | None = None,
) -> bool:
    # Published databases use DELETE journaling and never have a live writer.
    try:
        shutil.copyfile(old / "code.sqlite", index / "code.sqlite")
    except FileNotFoundError:
        return False
    missing = len({text for (_, text), src in zip(docs, reuse, strict=True) if src is None})
    payload = {"docs": docs, "missing": missing, "maxNewChunks": max_new_chunks}
    response = json.loads(_run("refresh", index, cache, payload))
    if not isinstance(response, bool):
        raise RuntimeError("Invalid QMD refresh response")
    return response


def search(index: Path, query: str, k: int, cache: Path) -> list[str]:
    if k <= 0 or not query.strip():
        return []
    ids = json.loads(_run("search", index, cache, {"query": query, "k": k}))
    if not isinstance(ids, list) or not all(
        isinstance(i, str) and i.isascii() and i.isdecimal() for i in ids
    ):
        raise RuntimeError("Invalid document IDs returned by QMD")
    return ids
