"""Contract tests for the decomposed codegraph package modules.

After splitting the 660-line ``scripts/mb-codegraph.py`` into orchestrator +
package modules, this locks the new module boundaries: each extractor imports
standalone and exposes its documented public API, and the script still re-exports
the legacy surface other test modules rely on.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))


def test_common_exposes_sha256_and_rel():
    from memory_bank_skill import codegraph_common as common
    assert common.sha256("abc") == common.sha256("abc")
    assert common.sha256("abc") != common.sha256("abd")
    assert common.rel(Path("/root/a/b.py"), Path("/root")) == "a/b.py"
    assert common.rel(Path("/elsewhere/x.py"), Path("/root")) == "/elsewhere/x.py"


def test_python_extractor_parses_standalone(tmp_path: Path):
    from memory_bank_skill import codegraph_python as cgpy
    f = tmp_path / "m.py"
    f.write_text("def foo():\n    return 1\n", encoding="utf-8")
    result = cgpy.parse_file(f, tmp_path)
    kinds = {n["kind"] for n in result["nodes"]}
    assert "module" in kinds and "function" in kinds
    assert "hash" in result and result["file"] == "m.py"


def test_treesitter_module_exposes_flag_and_config():
    from memory_bank_skill import codegraph_treesitter as cgts
    assert isinstance(cgts.HAS_TREE_SITTER, bool)
    assert ".go" in cgts.LANG_CONFIG and ".ts" in cgts.LANG_CONFIG
    # callable regardless of whether tree-sitter is installed (None when absent)
    assert callable(cgts.get_ts_parser)


def test_script_reexports_legacy_surface():
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph", REPO_ROOT / "scripts" / "mb-codegraph.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    # Surface consumed by test_codegraph.py / test_codegraph_ts.py
    assert callable(mod.parse_file)
    assert callable(mod.build_graph)
    assert callable(mod.run)
    assert callable(mod._get_ts_parser)
    assert isinstance(mod.HAS_TREE_SITTER, bool)
