"""Tests for the Bash/Bats extractor of the Memory Bank code graph.

Contract (``memory_bank_skill.codegraph_shell``):
    ``.sh``  → module node + function nodes (``name() {`` / ``function name``),
               ``import`` edges for ``source|. <path>`` and for ``bash <path>.sh``
               invocations, ``call`` edges to functions of the same file or of a
               (transitively) sourced file.
    ``.bats``→ module node + a function node per ``@test "…"``, ``import`` edges
               to every ``.sh`` path mentioned and to ``load '<helper>'``.

Always on (stdlib ``re`` only), like the Python ``ast`` extractor: no opt-in
flag, no new dependency. Paths are resolved against the files actually walked,
so ``"$REPO_ROOT/scripts/x.sh"`` becomes the repo-relative ``scripts/x.sh``.
"""

from __future__ import annotations

import importlib.util
import shutil
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
FIXTURE = REPO_ROOT / "tests" / "fixtures" / "codegraph-shell"


def _load_codegraph_module():
    spec = importlib.util.spec_from_file_location("mb_codegraph_shell_it", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def cg_mod():
    return _load_codegraph_module()


@pytest.fixture(scope="module")
def shell_mod():
    from memory_bank_skill import codegraph_shell

    return codegraph_shell


@pytest.fixture
def src(tmp_path: Path) -> Path:
    """Fixture tree copied to tmp so tests may add/remove files freely."""
    target = tmp_path / "src"
    shutil.copytree(FIXTURE, target)
    return target


def _nodes(graph, kind: str, file_rel: str | None = None):
    return [
        n
        for n in graph["nodes"]
        if n.get("kind") == kind and (file_rel is None or n.get("file") == file_rel)
    ]


def _edges(graph, kind: str, src_file: str | None = None):
    return [
        e
        for e in graph["edges"]
        if e.get("kind") == kind
        and (src_file is None or str(e.get("src", "")).split(":", 1)[0] == src_file)
    ]


# ── nodes ────────────────────────────────────────────────────────────────────


def test_bash_functions_become_function_nodes(shell_mod, src: Path):
    result = shell_mod.parse_file(src / "scripts" / "lib.sh", src)

    assert result["file"] == "scripts/lib.sh"
    modules = [n for n in result["nodes"] if n["kind"] == "module"]
    assert modules == [
        {"kind": "module", "name": "scripts/lib.sh", "file": "scripts/lib.sh", "line": 1}
    ]

    funcs = {n["name"]: n for n in result["nodes"] if n["kind"] == "function"}
    assert set(funcs) == {"helper_one", "helper_two", "one_liner"}
    assert funcs["helper_one"]["line"] == 4  # `helper_one() {`
    assert funcs["helper_two"]["line"] == 8  # `function helper_two {`
    assert funcs["one_liner"]["line"] == 12  # single-line body
    assert all(n["file"] == "scripts/lib.sh" for n in funcs.values())


def test_bats_test_becomes_function_node_with_import_edge_to_script(cg_mod, src: Path):
    graph = cg_mod.build_graph(src)

    bats = "tests/bats/test_tool.bats"
    assert {n["name"] for n in _nodes(graph, "module", bats)} == {bats}
    names = {n["name"] for n in _nodes(graph, "function", bats)}
    assert "tool prints one" in names
    assert "tool is executable" in names
    assert "setup" in names  # plain bash function in a .bats file counts too

    # `$REPO_ROOT/scripts/tool.sh` resolves to the repo-relative path.
    assert "scripts/tool.sh" in {e["dst"] for e in _edges(graph, "import", bats)}


# ── edges ────────────────────────────────────────────────────────────────────


def test_source_and_bash_invocation_become_import_edges(cg_mod, src: Path):
    graph = cg_mod.build_graph(src)

    dsts = {e["dst"] for e in _edges(graph, "import", "scripts/tool.sh")}
    assert "scripts/lib.sh" in dsts  # source "$SCRIPT_DIR/lib.sh"
    assert "scripts/other.sh" in dsts  # bash "$SCRIPT_DIR/other.sh"


def test_call_edge_to_function_of_sourced_file(cg_mod, src: Path):
    graph = cg_mod.build_graph(src)

    calls = _edges(graph, "call", "scripts/tool.sh")
    by_dst = {e["dst"]: e["src"] for e in calls}

    assert "helper_one" in by_dst, "call into a sourced file must be an edge"
    assert "helper_two" in by_dst
    assert by_dst["helper_one"] == "scripts/tool.sh:main"  # enclosing function scope
    # `main "$@"` at file level keeps the bare file as src.
    assert "scripts/tool.sh" in {e["src"] for e in calls if e["dst"] == "main"}
    # The other dominant idiom — `source "$(dirname "$0")/lib.sh"` — binds too:
    # the path must survive the space inside the command substitution.
    other = {e["dst"]: e["src"] for e in _edges(graph, "call", "scripts/other.sh")}
    assert other.get("helper_one") == "scripts/other.sh:other_entry"
    # unsourced.sh is never sourced by tool.sh → no guessing across files.
    assert "only_in_unsourced" not in by_dst
    # Heredoc bodies are not shell code.
    assert "not_a_function" not in by_dst
    assert "not_a_function" not in {n["name"] for n in _nodes(graph, "function")}


def test_load_helper_is_import(cg_mod, src: Path):
    graph = cg_mod.build_graph(src)

    dsts = {e["dst"] for e in _edges(graph, "import", "tests/bats/test_tool.bats")}
    assert "tests/bats/lib/assert.bash" in dsts


# ── orchestration ────────────────────────────────────────────────────────────


def test_malformed_file_skipped_with_warning(cg_mod, src: Path, capsys):
    (src / "scripts" / "broken.sh").write_bytes(b"#!/bin/sh\nbroken() {\n\xff\xfe\xfa\n}\n")

    graph = cg_mod.build_graph(src)
    warnings = capsys.readouterr().err

    assert "scripts/broken.sh" in warnings
    # The batch continues: every healthy file is still in the graph.
    assert "scripts/lib.sh" in {n["name"] for n in _nodes(graph, "module")}
    assert "broken" not in {n["name"] for n in _nodes(graph, "function")}


def test_sha_cache_hit_for_shell_files(cg_mod, src: Path, tmp_path: Path):
    cache = tmp_path / "cache"
    cache.mkdir()

    first = cg_mod.build_graph(src, cache)
    assert first["reparsed"] >= 6  # 5 shell files + 1 python module
    assert first["cached"] == 0

    second = cg_mod.build_graph(src, cache)
    assert second["reparsed"] == 0
    assert second["cached"] == first["reparsed"]
    assert second["nodes"] == first["nodes"]
    assert second["edges"] == first["edges"]

    # A touched shell file is re-parsed; the rest stay cached.
    lib = src / "scripts" / "lib.sh"
    lib.write_text(lib.read_text() + "\nhelper_three() {\n  :\n}\n", encoding="utf-8")
    third = cg_mod.build_graph(src, cache)
    assert third["reparsed"] == 1
    assert "helper_three" in {n["name"] for n in third["nodes"] if n.get("kind") == "function"}


def test_python_nodes_and_edges_unchanged_by_shell_files(cg_mod, src: Path, tmp_path: Path):
    """Regression: the python half of the graph is byte-identical with/without shell."""
    py_only = tmp_path / "py_only"
    shutil.copytree(src, py_only)
    for path in list(py_only.rglob("*.sh")) + list(py_only.rglob("*.bats")):
        path.unlink()

    def python_half(graph):
        files = {n["file"] for n in graph["nodes"] if str(n.get("file", "")).endswith(".py")}
        nodes = [n for n in graph["nodes"] if n.get("file") in files]
        edges = [e for e in graph["edges"] if str(e.get("src", "")).split(":", 1)[0] in files]
        return nodes, edges

    assert python_half(cg_mod.build_graph(src)) == python_half(cg_mod.build_graph(py_only))
