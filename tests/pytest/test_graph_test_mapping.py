"""Tests reach Python scripts through .sh entry points; argparse handlers have callers."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CODEGRAPH = REPO_ROOT / "scripts" / "mb-codegraph.py"
QUERY = REPO_ROOT / "scripts" / "mb-graph-query.py"


@pytest.fixture(scope="module")
def graph(tmp_path_factory) -> Path:
    tmp = tmp_path_factory.mktemp("chain")
    src = tmp / "src"
    (src / "scripts").mkdir(parents=True)
    (src / "tests" / "bats").mkdir(parents=True)
    (src / "scripts" / "tool.sh").write_text(
        '#!/usr/bin/env bash\nSCRIPT_DIR="$(dirname "$0")"\nexec python3 "$SCRIPT_DIR/tool_main.py" "$@"\n')
    (src / "scripts" / "tool_main.py").write_text(
        "import argparse\nimport tool_helper\n\n"
        "def cmd_run(args):\n    return tool_helper.helper()\n\n"
        "def cmd_stop(args):\n    return 0\n\n"
        "def main():\n    p = argparse.ArgumentParser()\n    s = p.add_subparsers()\n"
        "    s.add_parser('run').set_defaults(func=cmd_run)\n"
        "    handler = {'stop': cmd_stop}['stop']\n    return handler(None)\n")
    (src / "scripts" / "tool_helper.py").write_text("def helper():\n    return 1\n")
    (src / "tests" / "bats" / "test_tool.bats").write_text(
        '@test "runs" {\n  run bash "$REPO_ROOT/scripts/tool.sh" run\n}\n')
    (src / "tests" / "bats" / "test_other.bats").write_text(
        '@test "x" {\n  run bash "$REPO_ROOT/scripts/other.sh"\n}\n')
    (src / "scripts" / "other.sh").write_text("#!/usr/bin/env bash\necho hi\n")
    mb = tmp / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    spec = importlib.util.spec_from_file_location("cg_mapping", CODEGRAPH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run(mb_path=str(mb), src_root=str(src), mode="apply")
    return mb / "codebase" / "graph.json"


def _query(graph: Path, *args: str) -> dict:
    out = subprocess.run([sys.executable, str(QUERY), *args, "--graph", str(graph)],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


@pytest.mark.parametrize("target", ["scripts/tool_main.py", "scripts/tool_helper.py"])
def test_tests_for_py_script_include_bats_reaching_it_through_sh(graph, target) -> None:
    assert _query(graph, "tests", "--file", target)["test_files"] == ["tests/bats/test_tool.bats"]


def test_tests_for_unrelated_sh_do_not_leak_into_py_chain(graph) -> None:
    assert _query(graph, "tests", "--file", "scripts/other.sh")["test_files"] == [
        "tests/bats/test_other.bats"]


@pytest.mark.parametrize("handler", ["cmd_run", "cmd_stop"])
def test_who_calls_argparse_dispatched_handler_is_not_empty(graph, handler) -> None:
    payload = _query(graph, "neighbors", "--symbol", handler, "--direction", "in")
    assert any(e["src"] == "scripts/tool_main.py:main" for e in payload["incoming"])
