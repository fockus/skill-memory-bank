"""File-scoped graph evidence must not merge identically named functions."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def graph_project(tmp_path: Path) -> tuple[Path, Path]:
    project = tmp_path / "repo"
    bank = project / ".memory-bank"
    graph = bank / "codebase" / "graph.json"
    graph.parent.mkdir(parents=True)
    records = [
        {"type": "node", "name": name, "file": file, "kind": "function", "line": 1}
        for file, name in [
            ("hooks/native.py", "patch_files"),
            ("hooks/native.py", "main"),
            ("hooks/other.py", "main"),
        ]
    ]
    records.extend(
        {"type": "edge", "kind": kind, "src": src, "dst": dst}
        for kind, src, dst in [
            ("call", "hooks/native.py:main", "patch_files"),
            ("call", "hooks/other.py:main", "unrelated"),
            ("call", "app/start.py:start", "hooks/native.py:main"),
            ("call", "app/other.py:start", "hooks/other.py:main"),
            ("call", "app/bound.py:start", "hooks.native.main"),
            ("call", "app/bound_other.py:start", "hooks.other.main"),
            ("tests", "tests/test_native.py", "hooks/native.py"),
            ("call", "tests/test_native_main.py:test_entry", "hooks/native.py:main"),
            ("call", "tests/test_patch.py:test_patch", "patch_files"),
            ("call", "tests/test_other.py:test_entry", "hooks/other.py:main"),
            ("call", "tests/test_bound_native.py:test_entry", "hooks.native.main"),
            ("call", "tests/test_bound_other.py:test_entry", "hooks.other.main"),
            ("call", "tests/test_unknown.py:test_entry", "main"),
        ]
    )
    graph.write_text("\n".join(json.dumps(record) for record in records) + "\n")
    return project, graph


def run(script: str, *args: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / script), *args, "--json"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_file_neighbors_keep_exact_callers_without_other_main_functions(graph_project) -> None:
    _, graph = graph_project

    payload = run("mb-graph-query.py", "neighbors", "--graph", str(graph),
                  "--file", "hooks/native.py")

    assert {edge["src"] for edge in payload["outgoing"]} == {"hooks/native.py:main"}
    assert {edge["src"] for edge in payload["incoming"]} == {
        "hooks/native.py:main", "app/start.py:start", "tests/test_native.py",
        "tests/test_native_main.py:test_entry", "tests/test_patch.py:test_patch",
        "app/bound.py:start", "tests/test_bound_native.py:test_entry",
    }


def test_file_tests_include_known_links_and_exclude_ambiguous_main_calls(graph_project) -> None:
    _, graph = graph_project

    payload = run("mb-graph-query.py", "tests", "--graph", str(graph),
                  "--file", "hooks/native.py")

    assert payload["test_files"] == [
        "tests/test_bound_native.py", "tests/test_native.py", "tests/test_native_main.py",
        "tests/test_patch.py",
    ]


def test_file_tests_include_import_of_exact_python_module(graph_project) -> None:
    _, graph = graph_project
    with graph.open("a") as stream:
        for target in ["native", "other"]:
            stream.write(json.dumps({"type": "edge", "kind": "import",
                                    "src": f"tests/test_import_{target}.py",
                                    "dst": f"hooks.{target}"}) + "\n")

    payload = run("mb-graph-query.py", "tests", "--graph", str(graph),
                  "--file", "hooks/native.py")

    assert "tests/test_import_native.py" in payload["test_files"]
    assert "tests/test_import_other.py" not in payload["test_files"]


def test_unqualified_symbol_keeps_all_definitions_and_callers(graph_project) -> None:
    _, graph = graph_project

    payload = run("mb-graph-query.py", "neighbors", "--graph", str(graph),
                  "--symbol", "main", "--direction", "in")

    assert {node["file"] for node in payload["matches"]} == {
        "hooks/native.py", "hooks/other.py",
    }
    assert {edge["src"] for edge in payload["incoming"]} == {
        "app/start.py:start", "app/other.py:start", "tests/test_native_main.py:test_entry",
        "tests/test_other.py:test_entry", "tests/test_unknown.py:test_entry",
        "app/bound.py:start", "app/bound_other.py:start",
        "tests/test_bound_native.py:test_entry", "tests/test_bound_other.py:test_entry",
    }


@pytest.mark.parametrize("selector", ["hooks/native.py:main", "hooks.native.main"])
def test_qualified_symbol_resolves_one_definition_and_its_callers(graph_project, selector) -> None:
    _, graph = graph_project

    payload = run("mb-graph-query.py", "neighbors", "--graph", str(graph),
                  "--symbol", selector, "--direction", "in")

    assert [(node["file"], node["name"]) for node in payload["matches"]] == [
        ("hooks/native.py", "main"),
    ]
    assert {edge["src"] for edge in payload["incoming"]} == {
        "app/start.py:start", "app/bound.py:start", "tests/test_native_main.py:test_entry",
        "tests/test_bound_native.py:test_entry",
    }


def test_code_context_evidence_for_unique_function_excludes_other_main(graph_project) -> None:
    project, _ = graph_project

    payload = run("mb-code-context.py", "--query", "patch_files", "--project-root", str(project),
                  "--mb-path", str(project / ".memory-bank"), "--mode", "graph")

    assert payload["candidate_files"] == ["hooks/native.py"]
    assert all(edge["dst"] != "unrelated" for edge in payload["graph_facts"])
    assert payload["test_files"] == [
        "tests/test_bound_native.py", "tests/test_native.py", "tests/test_native_main.py",
        "tests/test_patch.py",
    ]
