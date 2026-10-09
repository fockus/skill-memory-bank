"""Static Python script invocations establish real file dependencies."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from memory_bank_skill.codegraph_python import parse_file

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def project(tmp_path: Path) -> Path:
    (tmp_path / "hooks").mkdir()
    (tmp_path / "tests" / "pytest").mkdir(parents=True)
    (tmp_path / "hooks" / "native.py").write_text("def main():\n    return 1\n")
    return tmp_path


def write_test(project: Path, body: str) -> Path:
    file = project / "tests" / "pytest" / "test_native.py"
    file.write_text(body)
    return file


@pytest.mark.parametrize("root_expr", [
    "Path(__file__).resolve().parents[2]",
    "Path(__file__).parent.parent.parent",
])
def test_static_subprocess_path_establishes_exact_script_dependency(project, root_expr) -> None:
    file = write_test(project, f"""from pathlib import Path
import subprocess
import sys
ROOT = {root_expr}
RUNNER = ROOT / 'hooks' / 'native.py'
def test_hook():
    subprocess.run([sys.executable, str(RUNNER)], check=True)
""")

    graph = parse_file(file, project)

    assert {"src": "tests/pytest/test_native.py", "dst": "hooks/native.py",
            "kind": "import", "via": "invoke"} in graph["edges"]


def test_dynamic_or_malicious_path_expression_is_never_executed_or_linked(project) -> None:
    marker = project / "must-not-exist"
    file = write_test(project, f"""from pathlib import Path
import subprocess
import os
ROOT = Path(__file__).resolve().parents[2]
DYNAMIC = Path(os.environ['RUNNER'])
EVIL = __import__('pathlib').Path({str(marker)!r}).touch()
def test_hook():
    subprocess.run(['python3', str(DYNAMIC)])
    subprocess.run(['python3', str(EVIL)])
""")

    graph = parse_file(file, project)

    assert not marker.exists()
    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


def test_external_script_path_is_not_linked_to_same_named_project_script(project) -> None:
    external = project.parent / "outside.py"
    external.write_text("raise AssertionError('must not run')\n")
    file = write_test(project, f"""import subprocess
subprocess.run(['python3', {str(external)!r}])
""")

    graph = parse_file(file, project)

    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


@pytest.mark.parametrize("shadowed", ["RUNNER", "subprocess", "str"])
def test_local_shadowed_name_does_not_establish_false_script_dependency(project, shadowed) -> None:
    file = write_test(project, f"""from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'hooks/native.py'
def test_other({shadowed}):
    subprocess.run(['python3', str(RUNNER)])
""")

    graph = parse_file(file, project)

    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


def test_invalid_literal_path_fails_open_without_breaking_graph(project) -> None:
    file = write_test(project, """from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'invalid\\x00.py'
subprocess.run(['python3', str(RUNNER)])
""")

    graph = parse_file(file, project)

    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


def test_reassigned_path_constructor_does_not_establish_false_script_dependency(project) -> None:
    file = write_test(project, """from pathlib import Path
import subprocess
Path = unknown_constructor
ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'hooks/native.py'
subprocess.run(['python3', str(RUNNER)])
""")

    graph = parse_file(file, project)

    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


def test_python_path_printed_as_data_does_not_establish_script_invocation(project) -> None:
    file = write_test(project, """from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'hooks/native.py'
subprocess.run(['echo', str(RUNNER)])
""")

    graph = parse_file(file, project)

    assert not any(edge.get("via") == "invoke" for edge in graph["edges"])


def test_real_builder_and_query_find_invoking_test_without_other_main(project) -> None:
    write_test(project, """from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'hooks/native.py'
def test_hook():
    subprocess.run(['python3', str(RUNNER)])
""")
    (project / "tests" / "pytest" / "test_other.py").write_text(
        "import unittest\nunittest.main()\n"
    )
    bank = project / ".memory-bank"
    bank.mkdir()
    build = subprocess.run(
        [sys.executable, str(ROOT / "scripts/mb-codegraph.py"), "--apply", str(bank), str(project)],
        capture_output=True, text=True, check=False,
    )
    assert build.returncode == 0, build.stderr

    query = subprocess.run(
        [sys.executable, str(ROOT / "scripts/mb-graph-query.py"), "tests", "--graph",
         str(bank / "codebase/graph.json"), "--file", "hooks/native.py", "--json"],
        capture_output=True, text=True, check=False,
    )

    assert query.returncode == 0, query.stderr
    assert json.loads(query.stdout)["test_files"] == ["tests/pytest/test_native.py"]
