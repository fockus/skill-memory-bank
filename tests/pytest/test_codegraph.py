"""Tests for scripts/mb-codegraph.py — Python ast-based code graph builder.

Contract:
    mb-codegraph.py [--dry-run|--apply] [mb_path] [src_root]

    Parses *.py files in src_root, extracts:
      - Nodes: module, function, class with (file, line, qualname)
      - Edges: import | call | inherit

    Output (--apply):
      - <mb>/codebase/graph.json — JSON Lines (one node/edge per line)
      - <mb>/codebase/god-nodes.md — top-20 by degree (in+out)
      - <mb>/codebase/.cache/<hash>.json — per-file AST cache

    Incremental: if file SHA256 unchanged vs cache → skip re-parse.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import textwrap
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
    f = dir_path / name
    f.write_text(textwrap.dedent(body).lstrip("\n"))
    return f


def _run_cli(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CODEGRAPH_SCRIPT), *args],
        capture_output=True, text=True, check=False,
    )


# ═══════════════════════════════════════════════════════════════
# AST parsing — nodes
# ═══════════════════════════════════════════════════════════════


def test_parse_single_function(cg_mod, src_root):
    """One function → 1 node of kind function."""
    write_py(src_root, "m.py", """
        def hello():
            pass
    """)
    result = cg_mod.parse_file(src_root / "m.py", src_root)
    funcs = [n for n in result["nodes"] if n["kind"] == "function"]
    assert any(n["name"] == "hello" for n in funcs)


def test_parse_class_with_methods(cg_mod, src_root):
    """Class with methods → class node + method nodes."""
    write_py(src_root, "m.py", """
        class Foo:
            def bar(self):
                pass
            def baz(self):
                pass
    """)
    result = cg_mod.parse_file(src_root / "m.py", src_root)
    classes = [n for n in result["nodes"] if n["kind"] == "class"]
    funcs = [n for n in result["nodes"] if n["kind"] == "function"]
    assert any(n["name"] == "Foo" for n in classes)
    assert any(n["name"] in ("bar", "Foo.bar") for n in funcs)


def test_parse_imports(cg_mod, src_root):
    """import X / from X import Y → edges of kind import."""
    write_py(src_root, "m.py", """
        import os
        from pathlib import Path
        from .sibling import helper
    """)
    result = cg_mod.parse_file(src_root / "m.py", src_root)
    imports = [e for e in result["edges"] if e["kind"] == "import"]
    targets = {e["dst"] for e in imports}
    assert "os" in targets
    assert any("Path" in t or "pathlib" in t for t in targets)


def test_parse_function_calls(cg_mod, src_root):
    """Function call → edge of kind call."""
    write_py(src_root, "m.py", """
        def worker():
            helper()
            other.method()
    """)
    result = cg_mod.parse_file(src_root / "m.py", src_root)
    calls = [e for e in result["edges"] if e["kind"] == "call"]
    targets = {e["dst"] for e in calls}
    assert "helper" in targets or any("helper" in t for t in targets)


def test_parse_class_inheritance(cg_mod, src_root):
    """class Child(Parent) → edge inherit."""
    write_py(src_root, "m.py", """
        class Parent:
            pass

        class Child(Parent):
            pass
    """)
    result = cg_mod.parse_file(src_root / "m.py", src_root)
    inherits = [e for e in result["edges"] if e["kind"] == "inherit"]
    assert any(e["dst"] == "Parent" for e in inherits)


# ═══════════════════════════════════════════════════════════════
# Multi-file + cross-file
# ═══════════════════════════════════════════════════════════════


def test_multi_file_each_parsed(cg_mod, src_root):
    """Two .py files → both are in the graph."""
    write_py(src_root, "a.py", "def alpha(): pass\n")
    write_py(src_root, "b.py", "def beta(): pass\n")
    graph = cg_mod.build_graph(src_root)
    files = {n["file"] for n in graph["nodes"] if "file" in n}
    assert "a.py" in files
    assert "b.py" in files


# ═══════════════════════════════════════════════════════════════
# Error handling
# ═══════════════════════════════════════════════════════════════


def test_broken_syntax_skipped_with_warning(cg_mod, src_root, capsys):
    """File with syntax error → skip + warning, batch continues."""
    write_py(src_root, "good.py", "def ok(): pass\n")
    write_py(src_root, "bad.py", "def broken( :\n")  # syntax error
    graph = cg_mod.build_graph(src_root)
    files = {n["file"] for n in graph["nodes"] if "file" in n}
    assert "good.py" in files
    captured = capsys.readouterr()
    assert "bad.py" in captured.err or "bad.py" in captured.out


def test_empty_src_root_returns_empty_graph(cg_mod, src_root):
    """Empty directory → nodes=[], edges=[]."""
    graph = cg_mod.build_graph(src_root)
    assert graph["nodes"] == []
    assert graph["edges"] == []


def test_non_python_files_ignored(cg_mod, src_root):
    """*.md, *.json, *.sh are not parsed."""
    (src_root / "README.md").write_text("# Hi\n")
    (src_root / "config.json").write_text("{}")
    write_py(src_root, "m.py", "def f(): pass\n")
    graph = cg_mod.build_graph(src_root)
    files = {n["file"] for n in graph["nodes"] if "file" in n}
    assert files == {"m.py"}


# ═══════════════════════════════════════════════════════════════
# Write / output
# ═══════════════════════════════════════════════════════════════


def test_apply_writes_graph_json_lines(cg_mod, mb_path, src_root):
    """--apply writes graph.json in JSON Lines format."""
    write_py(src_root, "m.py", "def f(): pass\nclass C: pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    graph_file = mb_path / "codebase" / "graph.json"
    assert graph_file.exists()
    lines = [line for line in graph_file.read_text().splitlines() if line.strip()]
    assert len(lines) >= 2
    # Each line is valid JSON
    for line in lines:
        json.loads(line)


def test_apply_writes_god_nodes_md(cg_mod, mb_path, src_root):
    """god-nodes.md is created and contains the top nodes by degree."""
    # Create a "star" node: hub is called from several places
    write_py(src_root, "hub.py", "def hub(): pass\n")
    write_py(src_root, "a.py", "from hub import hub\ndef a(): hub()\n")
    write_py(src_root, "b.py", "from hub import hub\ndef b(): hub()\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    god_file = mb_path / "codebase" / "god-nodes.md"
    assert god_file.exists()
    content = god_file.read_text()
    assert "hub" in content


def test_dry_run_no_file_writes(cg_mod, mb_path, src_root):
    """--dry-run → 0 file changes in codebase/."""
    write_py(src_root, "m.py", "def f(): pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="dry-run")
    assert not (mb_path / "codebase" / "graph.json").exists()
    assert not (mb_path / "codebase" / "god-nodes.md").exists()


# ═══════════════════════════════════════════════════════════════
# Incremental cache
# ═══════════════════════════════════════════════════════════════


def test_cache_stored_in_codebase_cache(cg_mod, mb_path, src_root):
    """After --apply, .cache/ appears with per-file hash JSON."""
    write_py(src_root, "m.py", "def f(): pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    cache_dir = mb_path / "codebase" / ".cache"
    assert cache_dir.exists()
    # There must be at least 1 JSON file in cache
    caches = list(cache_dir.glob("*.json"))
    assert len(caches) >= 1


def test_incremental_unchanged_file_not_reparsed(cg_mod, mb_path, src_root):
    """Unchanged file → reparsed_count=0 on the second run."""
    write_py(src_root, "m.py", "def f(): pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    # Second run without changes
    summary = cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    assert summary.get("reparsed", 0) == 0
    assert summary.get("cached", 0) >= 1


def test_incremental_changed_file_reparsed(cg_mod, mb_path, src_root):
    """Changing a file → reparsed_count ≥1."""
    write_py(src_root, "m.py", "def f(): pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    write_py(src_root, "m.py", "def f(): pass\ndef g(): pass\n")
    summary = cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    assert summary.get("reparsed", 0) >= 1


# ═══════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════


def test_cli_dry_run_default(cg_mod, mb_path, src_root):
    """CLI without --apply = dry-run, 0 file writes."""
    write_py(src_root, "m.py", "def f(): pass\n")
    result = _run_cli([str(mb_path), str(src_root)])
    assert result.returncode == 0
    assert not (mb_path / "codebase" / "graph.json").exists()


def test_cli_apply_writes_files(cg_mod, mb_path, src_root):
    """CLI --apply → graph.json + god-nodes.md are created."""
    write_py(src_root, "m.py", "def f(): pass\n")
    result = _run_cli(["--apply", str(mb_path), str(src_root)])
    assert result.returncode == 0
    assert (mb_path / "codebase" / "graph.json").exists()


def test_cli_missing_src_root_error(cg_mod, mb_path):
    """Nonexistent src_root → exit 1."""
    result = _run_cli(["--apply", str(mb_path), "/nonexistent/fake"])
    assert result.returncode != 0


# ═══════════════════════════════════════════════════════════════
# Graph shape
# ═══════════════════════════════════════════════════════════════


def test_node_has_required_fields(cg_mod, src_root):
    """Each node has: kind, name, file, line."""
    write_py(src_root, "m.py", "def f(): pass\n")
    graph = cg_mod.build_graph(src_root)
    for n in graph["nodes"]:
        assert "kind" in n
        assert "name" in n
        if n["kind"] != "module":
            assert "file" in n
            assert "line" in n


def test_edge_has_required_fields(cg_mod, src_root):
    """Each edge has: src, dst, kind."""
    write_py(src_root, "m.py", "import os\n")
    graph = cg_mod.build_graph(src_root)
    for e in graph["edges"]:
        assert "src" in e
        assert "dst" in e
        assert "kind" in e


def test_god_nodes_sorted_by_degree_desc(cg_mod, mb_path, src_root):
    """god-nodes.md — top by degree, sorted descending."""
    write_py(src_root, "popular.py", "def popular(): pass\n")
    # 3 files call popular
    for name in ("a.py", "b.py", "c.py"):
        write_py(src_root, name, f"from popular import popular\ndef {name[:-3]}(): popular()\n")
    write_py(src_root, "orphan.py", "def lonely(): pass\n")
    cg_mod.run(mb_path=str(mb_path), src_root=str(src_root), mode="apply")
    content = (mb_path / "codebase" / "god-nodes.md").read_text()
    # popular must rank above orphan/lonely
    pop_idx = content.find("popular")
    lonely_idx = content.find("lonely")
    if lonely_idx > 0:
        assert pop_idx < lonely_idx
