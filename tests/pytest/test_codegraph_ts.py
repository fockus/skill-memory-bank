"""Tests for tree-sitter adapter in scripts/mb-codegraph.py — Stage 6.5.

Extends Python-only v1 with Go / JavaScript / TypeScript / Rust / Java via
tree-sitter + language bindings (opt-in through pip extras).

Gracefully skipped if tree-sitter not available — users without extras still
get Python-only coverage (v1 behavior preserved).
"""

from __future__ import annotations

import importlib.util
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
TS_LANGS = (
    ("go", "tree_sitter_go"),
    ("javascript", "tree_sitter_javascript"),
    ("typescript", "tree_sitter_typescript"),
    ("rust", "tree_sitter_rust"),
    ("java", "tree_sitter_java"),
)


def _load_codegraph_module():
    spec = importlib.util.spec_from_file_location("mb_codegraph", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cg_mod():
    if not CODEGRAPH_SCRIPT.exists():
        pytest.skip("scripts/mb-codegraph.py not implemented yet")
    mod = _load_codegraph_module()
    if not getattr(mod, "HAS_TREE_SITTER", False):
        pytest.skip("tree-sitter not installed — Stage 6.5 requires extras")
    missing = [
        lang for lang, module_name in TS_LANGS if mod._get_ts_parser(lang, module_name) is None
    ]
    if missing:
        pytest.skip(
            "tree-sitter language bindings unavailable for Stage 6.5: " + ", ".join(missing)
        )
    return mod


@pytest.fixture
def src_root(tmp_path: Path) -> Path:
    src = tmp_path / "src"
    src.mkdir()
    return src


def write_file(dir_path: Path, name: str, body: str) -> Path:
    f = dir_path / name
    f.write_text(textwrap.dedent(body).lstrip("\n"))
    return f


# ═══════════════════════════════════════════════════════════════
# Go
# ═══════════════════════════════════════════════════════════════


def test_go_function_parsed(cg_mod, src_root):
    write_file(src_root, "main.go", """
        package main
        func Hello() { }
    """)
    graph = cg_mod.build_graph(src_root)
    names = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    assert "Hello" in names


def test_go_imports_edges(cg_mod, src_root):
    write_file(src_root, "main.go", """
        package main
        import "fmt"
        import "github.com/example/pkg"
    """)
    graph = cg_mod.build_graph(src_root)
    imports = [e for e in graph["edges"] if e["kind"] == "import"]
    targets = {e["dst"] for e in imports}
    assert "fmt" in targets
    assert any("example/pkg" in t for t in targets)


def test_go_calls_edges(cg_mod, src_root):
    write_file(src_root, "main.go", """
        package main
        import "fmt"
        func main() {
            fmt.Println("hi")
            Helper()
        }
        func Helper() {}
    """)
    graph = cg_mod.build_graph(src_root)
    calls = [e["dst"] for e in graph["edges"] if e["kind"] == "call"]
    assert any("Println" in c or "fmt.Println" in c for c in calls)
    assert "Helper" in calls


def test_go_method_receiver(cg_mod, src_root):
    write_file(src_root, "main.go", """
        package main
        type Foo struct{}
        func (f *Foo) Bar() {}
    """)
    graph = cg_mod.build_graph(src_root)
    names = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    assert any("Bar" in n for n in names)


def test_go_type_declaration(cg_mod, src_root):
    write_file(src_root, "main.go", """
        package main
        type User struct {
            Name string
        }
    """)
    graph = cg_mod.build_graph(src_root)
    classes = {n["name"] for n in graph["nodes"] if n["kind"] == "class"}
    assert "User" in classes


# ═══════════════════════════════════════════════════════════════
# JavaScript
# ═══════════════════════════════════════════════════════════════


def test_js_function_parsed(cg_mod, src_root):
    write_file(src_root, "app.js", """
        function hello() {}
        const world = () => {}
    """)
    graph = cg_mod.build_graph(src_root)
    names = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    assert "hello" in names


def test_js_class_and_inheritance(cg_mod, src_root):
    write_file(src_root, "app.js", """
        class Parent {}
        class Child extends Parent {}
    """)
    graph = cg_mod.build_graph(src_root)
    classes = {n["name"] for n in graph["nodes"] if n["kind"] == "class"}
    assert "Parent" in classes
    assert "Child" in classes
    inherits = [e for e in graph["edges"] if e["kind"] == "inherit"]
    assert any(e["dst"] == "Parent" for e in inherits)


def test_js_imports(cg_mod, src_root):
    write_file(src_root, "app.js", """
        import { foo } from './util'
        import React from 'react'
    """)
    graph = cg_mod.build_graph(src_root)
    imports = {e["dst"] for e in graph["edges"] if e["kind"] == "import"}
    assert any("util" in t for t in imports)
    assert any("react" in t for t in imports)


# ═══════════════════════════════════════════════════════════════
# TypeScript
# ═══════════════════════════════════════════════════════════════


def test_ts_function_and_class(cg_mod, src_root):
    write_file(src_root, "app.ts", """
        interface User { name: string }
        function greet(u: User): string { return u.name }
        class Service { run(): void {} }
    """)
    graph = cg_mod.build_graph(src_root)
    funcs = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    classes = {n["name"] for n in graph["nodes"] if n["kind"] == "class"}
    assert "greet" in funcs
    assert "Service" in classes


# ═══════════════════════════════════════════════════════════════
# Rust
# ═══════════════════════════════════════════════════════════════


def test_rust_fn_and_struct(cg_mod, src_root):
    write_file(src_root, "lib.rs", """
        pub struct Config { name: String }
        pub fn run() {}
    """)
    graph = cg_mod.build_graph(src_root)
    funcs = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    classes = {n["name"] for n in graph["nodes"] if n["kind"] == "class"}
    assert "run" in funcs
    assert "Config" in classes


def test_rust_use_as_import(cg_mod, src_root):
    write_file(src_root, "lib.rs", """
        use std::collections::HashMap;
    """)
    graph = cg_mod.build_graph(src_root)
    imports = [e["dst"] for e in graph["edges"] if e["kind"] == "import"]
    assert any("HashMap" in t or "std::collections" in t for t in imports)


# ═══════════════════════════════════════════════════════════════
# Java
# ═══════════════════════════════════════════════════════════════


def test_java_class_and_method(cg_mod, src_root):
    write_file(src_root, "App.java", """
        class App {
            void greet() {}
        }
    """)
    graph = cg_mod.build_graph(src_root)
    classes = {n["name"] for n in graph["nodes"] if n["kind"] == "class"}
    funcs = {n["name"] for n in graph["nodes"] if n["kind"] == "function"}
    assert "App" in classes
    assert any("greet" in n for n in funcs)


# ═══════════════════════════════════════════════════════════════
# Multi-language project
# ═══════════════════════════════════════════════════════════════


def test_mixed_python_go_js(cg_mod, src_root):
    """Project with .py + .go + .js → all 3 files appear in the graph."""
    write_file(src_root, "a.py", "def alpha(): pass\n")
    write_file(src_root, "b.go", "package main\nfunc Beta() {}\n")
    write_file(src_root, "c.js", "function gamma() {}\n")
    graph = cg_mod.build_graph(src_root)
    files = {n["file"] for n in graph["nodes"] if "file" in n}
    assert "a.py" in files
    assert "b.go" in files
    assert "c.js" in files


# ═══════════════════════════════════════════════════════════════
# Error handling
# ═══════════════════════════════════════════════════════════════


def test_broken_go_syntax_skipped(cg_mod, src_root, capsys):
    write_file(src_root, "good.go", "package main\nfunc Ok() {}\n")
    write_file(src_root, "bad.go", "package main\nfunc ( { broken\n")
    graph = cg_mod.build_graph(src_root)
    # The valid file must be in the graph
    files = {n["file"] for n in graph["nodes"] if "file" in n}
    assert "good.go" in files
