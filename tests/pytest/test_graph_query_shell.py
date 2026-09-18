"""`mb-graph-query.py` answers shell questions once .sh/.bats are in the graph.

No query-side special casing is expected: `tests --file <script>.sh` finds the
`.bats` modules that import it, and `impact --symbol <bash_func>` lists the
shell call sites — both through the generic name/file matching already used for
Python. These tests pin that end-to-end behaviour through the CLI.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
QUERY_SCRIPT = REPO_ROOT / "scripts" / "mb-graph-query.py"
FIXTURE = REPO_ROOT / "tests" / "fixtures" / "codegraph-shell"


@pytest.fixture(scope="module")
def graph_path(tmp_path_factory) -> Path:
    tmp = tmp_path_factory.mktemp("shell_graph")
    src = tmp / "src"
    shutil.copytree(FIXTURE, src)
    mb = tmp / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)

    spec = importlib.util.spec_from_file_location("mb_codegraph_query_it", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run(mb_path=str(mb), src_root=str(src), mode="apply")
    return mb / "codebase" / "graph.json"


def _query(graph_path: Path, *args: str) -> dict:
    proc = subprocess.run(
        [sys.executable, str(QUERY_SCRIPT), *args, "--graph", str(graph_path), "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout)


def test_tests_for_shell_script_returns_bats_modules(graph_path: Path):
    payload = _query(graph_path, "tests", "--file", "scripts/tool.sh")

    assert payload["ok"] is True
    # Exactly the suite that imports it — a `.sh` path destination must not
    # collapse to the bare extension and match every other suite's scripts.
    assert payload["test_files"] == ["tests/bats/test_tool.bats"]


def test_impact_for_bash_function_lists_callers(graph_path: Path):
    payload = _query(graph_path, "impact", "--symbol", "helper_one")

    assert payload["ok"] is True
    callers = {e["src"] for e in payload["dependents"] if e["kind"] == "call"}
    assert "scripts/tool.sh:main" in callers
    assert "scripts/lib.sh:helper_two" in callers
