"""Tests for opt-in doc/signature node enrichment (`--docs`) in the Python extractor.

Split from test_codegraph.py to keep each file under the project's 400-line gate.
Covers `parse_file(..., include_docs=True)` and the orchestrator's docs-aware cache.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"


def _load_codegraph_module():
    spec = importlib.util.spec_from_file_location("mb_codegraph", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cg_mod():
    if not CODEGRAPH_SCRIPT.exists():
        pytest.skip("scripts/mb-codegraph.py not implemented yet (TDD red)")
    return _load_codegraph_module()


@pytest.fixture
def mb_path(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    return mb


@pytest.fixture
def src_root(tmp_path: Path) -> Path:
    src = tmp_path / "src"
    src.mkdir()
    return src


def write_py(dir_path: Path, name: str, body: str) -> Path:
    import textwrap
    f = dir_path / name
    f.write_text(textwrap.dedent(body).lstrip("\n"))
    return f


def test_function_signature_and_doc_when_include_docs(cg_mod, src_root):
    write_py(src_root, "m.py", '''
        def greet(name, *, loud=False):
            """Say hi to someone."""
            return name
    ''')
    result = cg_mod.parse_file(src_root / "m.py", src_root, include_docs=True)
    fn = next(n for n in result["nodes"] if n.get("name") == "greet")
    assert "name" in fn["signature"] and "loud" in fn["signature"]
    assert fn["doc"] == "Say hi to someone."


def test_class_doc_and_bases_signature_when_include_docs(cg_mod, src_root):
    write_py(src_root, "m.py", '''
        class Service(Base, Mixin):
            """A service."""
    ''')
    result = cg_mod.parse_file(src_root / "m.py", src_root, include_docs=True)
    cls = next(n for n in result["nodes"] if n.get("name") == "Service")
    assert cls["doc"] == "A service."
    assert "Base" in cls["signature"] and "Mixin" in cls["signature"]


def test_module_doc_when_include_docs(cg_mod, src_root):
    write_py(src_root, "m.py", '''
        """Module level docstring."""
        x = 1
    ''')
    result = cg_mod.parse_file(src_root / "m.py", src_root, include_docs=True)
    mod = next(n for n in result["nodes"] if n["kind"] == "module")
    assert mod["doc"] == "Module level docstring."


def test_doc_truncated_and_whitespace_collapsed(cg_mod, src_root):
    long_doc = "word " * 100
    write_py(src_root, "m.py", f'''
        def f():
            """{long_doc}"""
    ''')
    result = cg_mod.parse_file(src_root / "m.py", src_root, include_docs=True)
    fn = next(n for n in result["nodes"] if n.get("name") == "f")
    assert len(fn["doc"]) <= 200 and "  " not in fn["doc"]


def test_default_parse_omits_doc_signature_byte_identity(cg_mod, src_root):
    write_py(src_root, "m.py", '''
        def f():
            """doc."""
    ''')
    result = cg_mod.parse_file(src_root / "m.py", src_root)  # include_docs defaults False
    fn = next(n for n in result["nodes"] if n.get("name") == "f")
    assert "doc" not in fn and "signature" not in fn


def test_function_without_docstring_omits_doc_keeps_signature(cg_mod, src_root):
    write_py(src_root, "m.py", "def f(a, b):\n    return a\n")
    result = cg_mod.parse_file(src_root / "m.py", src_root, include_docs=True)
    fn = next(n for n in result["nodes"] if n.get("name") == "f")
    assert "doc" not in fn and "a" in fn["signature"]


def test_apply_docs_flag_invalidates_stale_cache(cg_mod, mb_path, src_root):
    write_py(src_root, "m.py", '''
        def f():
            """d."""
    ''')
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    assert '"doc"' not in (mb_path / "codebase" / "graph.json").read_text()
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply", docs=True)
    assert '"doc": "d."' in (mb_path / "codebase" / "graph.json").read_text()
