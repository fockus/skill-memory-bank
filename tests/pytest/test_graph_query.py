"""Contract tests for scripts/mb-graph-query.py.

The CLI is the portable source of truth for Memory Bank graph access. Native
agent integrations must delegate to this behavior instead of reimplementing it.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-graph-query.py"


def _write_graph(path: Path, records: list[dict[str, Any]]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")
    return path


def _fixture_graph(tmp_path: Path) -> Path:
    return _write_graph(
        tmp_path / "repo with spaces" / ".memory-bank" / "codebase" / "graph.json",
        [
            {
                "type": "node",
                "kind": "module",
                "name": "app/service.py",
                "file": "app/service.py",
                "line": 1,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "handle_order",
                "file": "app/service.py",
                "line": 10,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "charge_card",
                "file": "app/payments.py",
                "line": 7,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "handle_order",
                "file": "app/admin.py",
                "line": 20,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "test_handle_order",
                "file": "tests/test_service.py",
                "line": 5,
            },
            {
                "type": "edge",
                "kind": "call",
                "src": "app/service.py:handle_order",
                "dst": "charge_card",
            },
            {
                "type": "edge",
                "kind": "call",
                "src": "app/admin.py:handle_order",
                "dst": "charge_card",
            },
            {
                "type": "edge",
                "kind": "call",
                "src": "tests/test_service.py:test_handle_order",
                "dst": "handle_order",
            },
            {"type": "edge", "kind": "import", "src": "app/service.py", "dst": "app.payments"},
            {
                "type": "edge",
                "kind": "tests",
                "src": "tests/test_service.py",
                "dst": "app/service.py",
            },
        ],
    )


def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _json(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    return json.loads(result.stdout)


def test_neighbors_by_symbol_returns_incoming_and_outgoing_edges(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["neighbors", "--graph", str(graph), "--symbol", "charge_card", "--json"])

    assert result.returncode == 0, result.stderr
    payload = _json(result)
    assert payload["ok"] is True
    assert {edge["src"] for edge in payload["incoming"]} == {
        "app/service.py:handle_order",
        "app/admin.py:handle_order",
    }
    assert payload["outgoing"] == []


def test_neighbors_by_file_returns_file_edges(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["neighbors", "--graph", str(graph), "--file", "app/service.py", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert any(edge["dst"] == "charge_card" for edge in payload["outgoing"])
    assert any(edge["src"] == "tests/test_service.py" for edge in payload["incoming"])


def test_neighbors_by_file_does_not_duplicate_outgoing_edges_as_incoming(
    tmp_path: Path,
) -> None:
    graph = _write_graph(
        tmp_path / ".memory-bank" / "codebase" / "graph.json",
        [
            {"type": "node", "kind": "module", "name": "src/a.py", "file": "src/a.py", "line": 1},
            {"type": "node", "kind": "function", "name": "a", "file": "src/a.py", "line": 1},
            {"type": "node", "kind": "function", "name": "b", "file": "src/b.py", "line": 1},
            {"type": "edge", "kind": "call", "src": "src/a.py:a", "dst": "b"},
        ],
    )

    result = _run(["neighbors", "--graph", str(graph), "--file", "src/a.py", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    edge = {"type": "edge", "kind": "call", "src": "src/a.py:a", "dst": "b"}
    assert edge in payload["outgoing"]
    assert edge not in payload["incoming"]


def test_neighbors_duplicate_symbol_reports_all_matching_nodes(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["neighbors", "--graph", str(graph), "--symbol", "handle_order", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert len(payload["matches"]) == 2
    assert {node["file"] for node in payload["matches"]} == {"app/service.py", "app/admin.py"}


def test_impact_returns_dependents_and_dependencies(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["impact", "--graph", str(graph), "--symbol", "handle_order", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert "tests/test_service.py" in payload["test_files"]
    assert any(edge["dst"] == "charge_card" for edge in payload["dependencies"])
    assert any(edge["src"].startswith("tests/test_service.py") for edge in payload["dependents"])


def test_tests_by_file_returns_structural_test_links(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["tests", "--graph", str(graph), "--file", "app/service.py", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert payload["test_files"] == ["tests/test_service.py"]


def test_tests_by_symbol_returns_test_files(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["tests", "--graph", str(graph), "--symbol", "handle_order", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert "tests/test_service.py" in payload["test_files"]


def test_tests_detect_common_language_test_file_names(tmp_path: Path) -> None:
    graph = _write_graph(
        tmp_path / ".memory-bank" / "codebase" / "graph.json",
        [
            {
                "type": "node",
                "kind": "function",
                "name": "Run",
                "file": "pkg/service.go",
                "line": 1,
            },
            {"type": "edge", "kind": "call", "src": "pkg/service_test.go:TestRun", "dst": "Run"},
            {"type": "edge", "kind": "call", "src": "src/service.spec.ts:it_runs", "dst": "Run"},
            {"type": "edge", "kind": "call", "src": "src/service.test.js:it_runs", "dst": "Run"},
        ],
    )

    result = _run(["tests", "--graph", str(graph), "--symbol", "Run", "--json"])

    assert result.returncode == 0
    payload = _json(result)
    assert payload["test_files"] == [
        "pkg/service_test.go",
        "src/service.spec.ts",
        "src/service.test.js",
    ]


def test_explain_returns_human_readable_markdown(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["explain", "--graph", str(graph), "--symbol", "charge_card"])

    assert result.returncode == 0
    assert "# Graph explanation" in result.stdout
    assert "charge_card" in result.stdout
    assert "app/service.py:handle_order" in result.stdout


def test_summary_generates_semantic_friendly_markdown_files(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)
    out_dir = tmp_path / ".memory-bank" / "codebase"

    result = _run(["summary", "--graph", str(graph), "--out-dir", str(out_dir), "--json"])

    assert result.returncode == 0, result.stderr
    payload = _json(result)
    written = {Path(path).name for path in payload["written"]}
    assert {"GRAPH_SUMMARY.md", "IMPACT_MAP.md", "TEST_LINKS.md"}.issubset(written)
    assert "charge_card" in (out_dir / "GRAPH_SUMMARY.md").read_text(encoding="utf-8")
    assert "tests/test_service.py" in (out_dir / "TEST_LINKS.md").read_text(encoding="utf-8")


def test_no_match_exits_one_with_json_payload(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["neighbors", "--graph", str(graph), "--symbol", "missing_symbol", "--json"])

    assert result.returncode == 1
    payload = _json(result)
    assert payload["ok"] is False
    assert payload["error"] == "no_match"


def test_missing_graph_exits_three(tmp_path: Path) -> None:
    result = _run(
        ["neighbors", "--graph", str(tmp_path / "missing.json"), "--symbol", "x", "--json"]
    )

    assert result.returncode == 3
    payload = _json(result)
    assert payload["ok"] is False
    assert payload["error"] == "missing_graph"


def test_corrupt_graph_exits_two(tmp_path: Path) -> None:
    graph = tmp_path / ".memory-bank" / "codebase" / "graph.json"
    graph.parent.mkdir(parents=True)
    graph.write_text('{"type":"node"}\nnot json\n', encoding="utf-8")

    result = _run(["neighbors", "--graph", str(graph), "--symbol", "x", "--json"])

    assert result.returncode == 2
    payload = _json(result)
    assert payload["ok"] is False
    assert payload["error"] == "invalid_graph"


def test_missing_selector_exits_two(tmp_path: Path) -> None:
    graph = _fixture_graph(tmp_path)

    result = _run(["neighbors", "--graph", str(graph), "--json"])

    assert result.returncode == 2
    payload = _json(result)
    assert payload["ok"] is False
    assert payload["error"] == "invalid_input"


def _fixture_graph_with_meta(tmp_path: Path) -> Path:
    from datetime import datetime

    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return _write_graph(
        tmp_path / ".memory-bank" / "codebase" / "graph.json",
        [
            {"type": "meta", "generated_at": now, "commit": None, "nodes": 1, "edges": 0},
            {"type": "node", "kind": "module", "name": "a.py", "file": "a.py", "line": 1},
        ],
    )


def test_status_subcommand_json_reports_freshness(tmp_path: Path) -> None:
    graph = _fixture_graph_with_meta(tmp_path)

    result = _run(["status", "--graph", str(graph), "--src-root", str(tmp_path), "--json"])

    assert result.returncode == 0, result.stderr
    payload = _json(result)
    assert payload["exists"] is True
    assert "stale" in payload
    assert "commits_behind" in payload


def test_status_subcommand_missing_graph_exit3(tmp_path: Path) -> None:
    result = _run(
        ["status", "--graph", str(tmp_path / "absent.json"), "--src-root", str(tmp_path), "--json"]
    )

    assert result.returncode == 3
    payload = _json(result)
    assert payload["exists"] is False
