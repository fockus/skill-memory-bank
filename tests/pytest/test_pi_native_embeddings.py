"""Persistent FastEmbed model cache and honest vector search degradation (Pi-native Stage 3).

Every query runs the real ``scripts/mb-semantic-search.py`` in a fresh process. A stub
``fastembed`` (PYTHONPATH) mimics the real loader's cache contract: it reads the model from
``cache_dir`` (else FASTEMBED_CACHE_PATH, else ``<tmp>/fastembed_cache``), "downloads" only
when online and rejects a corrupt file. The last test runs the real FastEmbed model offline
when one is already cached on this machine (copied, never modified).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SEARCH = REPO_ROOT / "scripts" / "mb-semantic-search.py"
MODEL_DIR = "models--qdrant--all-MiniLM-L6-v2-onnx"

STUB = r"""
import hashlib, json, math, os, tempfile
from pathlib import Path
import numpy as np

def _log(**rec):
    with open(os.environ["STUB_LOG"], "a") as fh:
        fh.write(json.dumps(rec) + "\n")

class TextEmbedding:
    def __init__(self, model_name, cache_dir=None, **kwargs):
        root = Path(cache_dir) if cache_dir else Path(
            os.environ.get("FASTEMBED_CACHE_PATH", os.path.join(tempfile.gettempdir(), "fastembed_cache")))
        _log(event="init", cache_dir=str(root))
        model = root / "models--qdrant--all-MiniLM-L6-v2-onnx" / "model.onnx"
        if not model.is_file():
            if os.environ.get("HF_HUB_OFFLINE") == "1":
                raise ValueError(f"Could not load model {model_name} from any source.")
            model.parent.mkdir(parents=True, exist_ok=True)
            model.write_text("weights")
        if model.read_text() != "weights":
            raise RuntimeError("[ONNXRuntimeError] INVALID_PROTOBUF: Load model failed")

    def embed(self, texts, **kwargs):
        texts = list(texts)
        _log(event="embed", n=len(texts))
        for text in texts:
            v = np.zeros(32, dtype="float32")
            for tok in text.lower().split():
                v[int(hashlib.md5(tok.encode()).hexdigest(), 16) % 32] += 1.0
            yield v / (np.linalg.norm(v) or 1.0)
"""


def _graph(mb: Path, nodes: list[tuple[str, str]]) -> None:
    (mb / "codebase").mkdir(parents=True, exist_ok=True)
    rows = [
        {
            "type": "node",
            "kind": "function",
            "name": n,
            "file": f"src/{n}.py",
            "line": 1,
            "doc": doc,
        }
        for n, doc in nodes
    ]
    (mb / "codebase" / "graph.json").write_text("\n".join(json.dumps(r) for r in rows) + "\n")


NODES = [("authenticate_user", "check user token"), ("render_cart", "draw cart total")]


@pytest.fixture
def env(tmp_path: Path) -> dict:
    home = tmp_path / "home"
    stub = tmp_path / "stub"
    for d in (home, stub, tmp_path / "ostmp"):
        d.mkdir()
    (stub / "fastembed.py").write_text(STUB)
    mb = tmp_path / "proj" / ".memory-bank"
    _graph(mb, NODES)
    clean = {
        k: v for k, v in os.environ.items() if not k.startswith(("FASTEMBED", "HF_", "XDG_", "MB_"))
    }
    return {
        "tmp": tmp_path,
        "mb": mb,
        "log": tmp_path / "stub.log",
        "env": {
            **clean,
            "HOME": str(home),
            "PYTHONPATH": str(stub),
            "STUB_LOG": str(tmp_path / "stub.log"),
            "TMPDIR": str(tmp_path / "ostmp"),
            "HF_HUB_OFFLINE": "1",
        },
    }


def _run(env: dict, code_or_query: str, *, extra: dict | None = None, build: bool = False):
    run_env = {**env["env"], **(extra or {})}
    if build:
        argv = [
            sys.executable,
            "-c",
            "import sys;sys.path.insert(0,sys.argv[1]);"
            "from memory_bank_skill.semantic_index import build_index;print(build_index(sys.argv[2]))",
            str(REPO_ROOT),
            str(env["mb"]),
        ]
    else:
        argv = [
            sys.executable,
            str(SEARCH),
            code_or_query,
            "--backend",
            "embeddings",
            "--json",
            str(env["mb"]),
        ]
    return subprocess.run(
        argv, capture_output=True, text=True, env=run_env, timeout=60, check=False
    )


def _log(env: dict) -> list[dict]:
    path = env["log"]
    return [json.loads(x) for x in path.read_text().splitlines()] if path.exists() else []


def _persistent(env: dict) -> Path:
    return env["tmp"] / "home" / ".cache" / "fastembed"


def _seed_model(root: Path, content: str = "weights") -> Path:
    model = root / MODEL_DIR / "model.onnx"
    model.parent.mkdir(parents=True, exist_ok=True)
    model.write_text(content)
    return model


def _drop_models(env: dict) -> None:
    for root in (_persistent(env), env["tmp"] / "ostmp" / "fastembed_cache"):
        shutil.rmtree(root, ignore_errors=True)


def _warm_matrix(env: dict) -> None:
    """Online build in its own process (simulated download into the default cache)."""
    built = _run(env, "", extra={"HF_HUB_OFFLINE": "0"}, build=True)
    assert built.stdout.strip() == "built", built.stderr
    env["log"].unlink()


def test_offline_query_after_restart_with_new_os_temp_uses_persistent_model_cache(env):
    _warm_matrix(env)
    # Fresh process, offline, and the OS temp dir is a different (purged/sandboxed) one.
    (env["tmp"] / "ostmp2").mkdir()
    proc = _run(env, "authenticate user", extra={"TMPDIR": str(env["tmp"] / "ostmp2")})
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["backend"] == "embeddings"
    assert out["hits"][0]["id"] == "src/authenticate_user.py:authenticate_user"
    inits = [r for r in _log(env) if r["event"] == "init"]
    assert inits and all(r["cache_dir"] == str(_persistent(env)) for r in inits)
    # Only the query was encoded — the persisted corpus matrix was reused.
    assert [r["n"] for r in _log(env) if r["event"] == "embed"] == [1]


def test_model_cache_default_is_outside_os_temp(env):
    _warm_matrix(env)
    assert (_persistent(env) / MODEL_DIR / "model.onnx").is_file()
    assert not (env["tmp"] / "ostmp" / "fastembed_cache").exists()


def test_fastembed_cache_path_override_takes_precedence(env):
    _warm_matrix(env)
    custom = env["tmp"] / "custom-cache"
    _seed_model(custom)
    proc = _run(env, "authenticate user", extra={"FASTEMBED_CACHE_PATH": str(custom)})
    assert json.loads(proc.stdout)["backend"] == "embeddings"
    assert {r["cache_dir"] for r in _log(env) if r["event"] == "init"} == {str(custom)}


def test_model_already_in_legacy_os_temp_cache_is_reused_offline_without_copying(env):
    _warm_matrix(env)
    _drop_models(env)
    legacy = _seed_model(env["tmp"] / "ostmp" / "fastembed_cache")
    proc = _run(env, "authenticate user")
    assert json.loads(proc.stdout)["backend"] == "embeddings"
    assert legacy.read_text() == "weights"
    assert not (_persistent(env) / MODEL_DIR).exists()


def test_warm_matrix_without_model_reports_labeled_bm25_fallback(env):
    _warm_matrix(env)
    _drop_models(env)
    proc = _run(env, "authenticate user")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["backend"] == "bm25"
    warning = " ".join(out["warnings"])
    assert "embedding model unavailable" in warning
    assert str(_persistent(env)) in warning
    assert "answering with bm25" in warning
    assert out["hits"][0]["id"] == "src/authenticate_user.py:authenticate_user"


def test_corrupt_model_is_diagnosed_and_user_cache_is_preserved(env):
    _warm_matrix(env)
    model = _seed_model(_persistent(env), "garbage")
    npy = env["mb"] / ".index" / "codesearch" / "embeddings.npy"
    before = npy.read_bytes()
    proc = _run(env, "authenticate user")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["backend"] == "bm25"
    assert "INVALID_PROTOBUF" in " ".join(out["warnings"])
    assert model.read_text() == "garbage"
    assert npy.read_bytes() == before


def test_cold_corpus_answers_bm25_without_foreground_encoding(env):
    _seed_model(_persistent(env))
    proc = _run(env, "authenticate user")
    out = json.loads(proc.stdout)
    assert out["backend"] == "bm25"
    assert any("answering with bm25" in w for w in out["warnings"])
    assert not [r for r in _log(env) if r["event"] == "embed"]


# ── Real FastEmbed inference (DoD 2) — only when a model is already cached locally ──


def _real_semantic_python() -> str | None:
    for cand in (
        os.environ.get("MB_SEMANTIC_PY"),
        str(Path.home() / ".claude/hooks/.venv/bin/python"),
    ):
        if (
            cand
            and os.access(cand, os.X_OK)
            and subprocess.run(
                [cand, "-c", "import fastembed"], capture_output=True, check=False
            ).returncode
            == 0
        ):
            return cand
    return None


def _cached_real_model() -> Path | None:
    import tempfile

    roots = [
        os.environ.get("FASTEMBED_CACHE_PATH"),
        str(Path.home() / ".cache" / "fastembed"),
        os.path.join(tempfile.gettempdir(), "fastembed_cache"),
    ]
    for root in filter(None, roots):
        if list(Path(root).glob(f"{MODEL_DIR}/snapshots/*/model.onnx")):
            return Path(root)
    return None


SEMANTIC_NODES = [
    ("verify_login", "compare the password hash with the stored digest for this account"),
    ("render_chart", "draw a bar plot of monthly sales figures"),
    ("parse_invoice", "read line items and tax amounts from a pdf document"),
]


def test_real_fastembed_offline_inference_on_semantic_only_fixture(tmp_path: Path):
    python, cached = _real_semantic_python(), _cached_real_model()
    if not python or not cached:
        pytest.skip("no FastEmbed interpreter or no locally cached model (no download allowed)")
    # Copy into the default location under a temp HOME (dereferencing HF blob symlinks):
    # the user's cache is read, never written.
    shutil.copytree(
        cached / MODEL_DIR, tmp_path / ".cache" / "fastembed" / MODEL_DIR, symlinks=False
    )
    mb = tmp_path / "proj" / ".memory-bank"
    _graph(mb, SEMANTIC_NODES)
    clean = {
        k: v for k, v in os.environ.items() if not k.startswith(("FASTEMBED", "HF_", "XDG_", "MB_"))
    }
    (tmp_path / "ostmp").mkdir()
    env = {**clean, "HOME": str(tmp_path), "HF_HUB_OFFLINE": "1", "TMPDIR": str(tmp_path / "ostmp")}
    build = subprocess.run(
        [
            python,
            "-c",
            "import sys;sys.path.insert(0,sys.argv[1]);"
            "from memory_bank_skill.semantic_index import build_index;print(build_index(sys.argv[2]))",
            str(REPO_ROOT),
            str(mb),
        ],
        capture_output=True,
        text=True,
        env=env,
        timeout=300,
        check=False,
    )
    assert build.stdout.strip() == "built", build.stderr[-2000:]
    query = "authenticate user credentials"  # shares no token with any fixture document
    proc = subprocess.run(
        [python, str(SEARCH), query, "--backend", "embeddings", "--json", str(mb)],
        capture_output=True,
        text=True,
        env=env,
        timeout=300,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr[-2000:]
    out = json.loads(proc.stdout)
    assert out["backend"] == "embeddings", out["warnings"]
    assert out["hits"][0]["id"] == "src/verify_login.py:verify_login"
    bm25 = subprocess.run(
        [python, str(SEARCH), query, "--backend", "bm25", "--json", str(mb)],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
        check=False,
    )
    assert json.loads(bm25.stdout)["hits"] == []  # lexical search alone cannot answer it
