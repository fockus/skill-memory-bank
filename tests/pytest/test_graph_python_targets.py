"""Public graph queries follow Python imports, not matching dotted suffixes."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[2] / "scripts"
ENV = {**os.environ, "MB_CODEGRAPH_REEXEC": "1", "MB_GRAPH_AUTOUPDATE": "off",
       "SOURCE_DATE_EPOCH": "1700000000", "MB_SEMANTIC_PY": "/nonexistent/semantic-python"}


def build(root: Path) -> None:
    subprocess.run([sys.executable, SCRIPTS / "mb-codegraph.py", "--apply",
                    root / ".memory-bank", root], env=ENV, check=True, capture_output=True)


@pytest.fixture(scope="module")
def project(tmp_path_factory) -> Path:
    root = tmp_path_factory.mktemp("import-targets")
    files = {
        "tools/__init__.py": "",
        "tools/core.py": "def evidence(): pass\n",
        "tools/runner.py": "from core import evidence\ndef main(): evidence()\n",
        "pkg/__init__.py": "",
        "pkg/core.py": "def evidence(): pass\n",
        "pkg/outsider.py": "import core\ndef unrelated(): core.evidence()\n",
        "pkg/search.py": "def search():\n    from pkg import core\n    core.evidence()\n",
        "tests/test_alias.py": (
            "from pkg import core as fresh\n"
            "def test_good(): fresh.evidence()\n"
            "def test_param(fresh): fresh.evidence()\n"
            "def test_local(obj):\n    fresh = obj\n    fresh.evidence()\n"
            "def test_method(obj): obj.evidence()\n"
            "def test_factory(make): make().evidence()\n"
            "def test_item(items): items[0].evidence()\n"
        ),
        "tests/test_script.py": (
            "import sys\nfrom pathlib import Path\n"
            "sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))\n"
            "import runner as r\n"
        ),
        "tests/test_unknown.py": "import core\ndef test_external(): core.evidence()\n",
        "tests/test_path_like.py": (
            "import sys\nfrom pathlib import Path\nsys = fake_sys()\n"
            "sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))\n"
            "import runner\n"
        ),
        "tests/test_other.py": "from other import runner as r\n",
        "instance.py": (
            "class Store:\n    def reload(self): pass\n"
            "def manual(obj): Store.reload(obj)\n"
        ),
        "dup.py": "def handle(): pass\n",
        "tools/dup.py": "def handle(): pass\n",
        "tools/conflict.py": "import dup\ndef attempt(): dup.handle()\n",
    }
    for name, body in files.items():
        path = root / name
        path.parent.mkdir(exist_ok=True)
        path.write_text(body)
    (root / ".memory-bank/codebase").mkdir(parents=True)
    build(root)
    return root


def query(root: Path, cmd: str, selector: str, value: str) -> dict:
    graph = root / ".memory-bank/codebase/graph.json"
    args = ["--direction", "in"] if cmd == "neighbors" else []
    p = subprocess.run([sys.executable, SCRIPTS / "mb-graph-query.py", cmd, "--graph", graph,
                        selector, value, *args, "--json"], env=ENV, check=True,
                       text=True, capture_output=True)
    return json.loads(p.stdout)


@pytest.mark.parametrize(("selector", "callers"), [
    ("tools.core.evidence", {"tools/runner.py:main"}),
    ("pkg.core.evidence", {"pkg/search.py:search", "tests/test_alias.py:test_good"}),
    ("evidence", {"tools/runner.py:main", "pkg/search.py:search", "tests/test_alias.py:test_good"}),
])
def test_imported_callers_exclude_other_modules_and_shadowed_receivers(project, selector, callers):
    incoming = query(project, "neighbors", "--symbol", selector)["incoming"]
    assert {e["src"] for e in incoming if e["kind"] == "call"} == callers


def test_raw_alias_query_remains_available(project):
    incoming = query(project, "neighbors", "--symbol", "fresh.evidence")["incoming"]
    assert "tests/test_alias.py:test_good" in {e["src"] for e in incoming}


def test_explicit_class_method_spelling_remains_queryable(project):
    incoming = query(project, "neighbors", "--symbol", "Store.reload")["incoming"]
    assert {e["src"] for e in incoming if e["kind"] == "call"} == {"instance.py:manual"}


def test_tests_follow_import_from_static_script_search_path(project):
    assert query(project, "tests", "--file", "tools/runner.py")["test_files"] == [
        "tests/test_script.py"]


def test_file_impact_includes_sibling_import_and_call_not_other_core(project):
    edges = query(project, "impact", "--file", "tools/core.py")["dependents"]
    assert {(e["kind"], e["src"]) for e in edges} == {
        ("import", "tools/runner.py"), ("call", "tools/runner.py:main")}


def test_graph_front_door_accepts_python_file_as_target(project):
    result = subprocess.run(["bash", SCRIPTS / "mb-graph.sh", "impact", "tools/core.py", "--json"],
                            cwd=project, env={**ENV, "PYTHON": sys.executable,
                                              "MB_PATH": str(project / ".memory-bank")},
                            capture_output=True, text=True, check=True)
    edges = json.loads(result.stdout)["dependents"]
    assert {(e["kind"], e["src"]) for e in edges} == {
        ("import", "tools/runner.py"), ("call", "tools/runner.py:main")}


def test_ambiguous_module_is_not_assigned_to_either_definition(project):
    for file in ("dup.py", "tools/dup.py"):
        edges = query(project, "impact", "--file", file)["dependents"]
        assert not any(e["src"].startswith("tools/conflict.py") for e in edges)


def test_code_context_shares_the_direct_import_test_link(project):
    result = subprocess.run([sys.executable, SCRIPTS / "mb-code-context.py", "--query", "runner",
                             "--project-root", project, "--mb-path", project / ".memory-bank",
                             "--mode", "graph", "--json"], env=ENV, capture_output=True,
                            text=True, check=True)
    assert "tests/test_script.py" in json.loads(result.stdout)["test_files"]


def test_warm_graph_and_read_only_queries_keep_same_import_targets(project):
    graph = project / ".memory-bank/codebase/graph.json"
    before = graph.read_bytes()
    build(project)
    assert graph.read_bytes() == before
    query(project, "tests", "--file", "tools/runner.py")
    assert graph.read_bytes() == before


def test_rebuild_upgrades_pre_binding_cache_without_guessing_on_legacy_graph(project, tmp_path):
    root = tmp_path / "legacy"
    shutil.copytree(project, root)
    graph = root / ".memory-bank/codebase/graph.json"
    rows = [json.loads(line) for line in graph.read_text().splitlines()]
    for row in rows:
        row.pop("target", None)
    graph.write_text("\n".join(map(json.dumps, rows)) + "\n")
    for cache in (graph.parent / ".cache").glob("*.json"):
        record = json.loads(cache.read_text())
        record["cache_version"] = 4
        for edge in record["edges"]:
            edge.pop("_ref", None)
        cache.write_text(json.dumps(record))

    source = "tests/test_alias.py:test_good"
    def callers(symbol):
        return {e["src"] for e in query(root, "neighbors", "--symbol", symbol)["incoming"]}

    assert source in callers("fresh.evidence") and source not in callers("pkg.core.evidence")
    build(root)
    assert source in callers("pkg.core.evidence")
