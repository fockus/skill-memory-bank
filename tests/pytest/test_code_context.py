"""Contract tests for scripts/mb-code-context.py.

code_context is the portable GraphRAG-lite orchestrator: semantic candidates are
optional, graph expansion is deterministic, and evidence packs stay bounded.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-code-context.py"


def _write_graph(path: Path, records: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(record) for record in records) + "\n", encoding="utf-8")


def _fixture_project(tmp_path: Path) -> tuple[Path, Path, Path]:
    project = tmp_path / "repo"
    mb = project / ".memory-bank"
    (project / "app").mkdir(parents=True)
    (project / "tests").mkdir()
    (mb / "codebase").mkdir(parents=True)
    (project / "app" / "service.py").write_text(
        "def handle_order():\n    charge_card()\n", encoding="utf-8"
    )
    (project / "app" / "payments.py").write_text(
        "def charge_card():\n    return True\n", encoding="utf-8"
    )
    (project / "tests" / "test_service.py").write_text(
        "def test_handle_order():\n    handle_order()\n", encoding="utf-8"
    )
    (project / ".env").write_text("SECRET_TOKEN=must-not-leak\n", encoding="utf-8")
    (project / ".env.local").write_text("LOCAL_SECRET=must-not-leak-local\n", encoding="utf-8")
    _write_graph(
        mb / "codebase" / "graph.json",
        [
            {
                "type": "node",
                "kind": "function",
                "name": "handle_order",
                "file": "app/service.py",
                "line": 1,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "charge_card",
                "file": "app/payments.py",
                "line": 1,
            },
            {
                "type": "node",
                "kind": "function",
                "name": "test_handle_order",
                "file": "tests/test_service.py",
                "line": 1,
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
                "src": "tests/test_service.py:test_handle_order",
                "dst": "handle_order",
            },
            {
                "type": "edge",
                "kind": "tests",
                "src": "tests/test_service.py",
                "dst": "app/service.py",
            },
        ],
    )
    semantic = tmp_path / "semantic.json"
    semantic.write_text(
        json.dumps(
            {"candidates": [{"file": "app/service.py", "score": 0.91, "symbol": "handle_order"}]}
        ),
        encoding="utf-8",
    )
    return project, mb, semantic


def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _json(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    return json.loads(result.stdout)


def test_code_context_returns_evidence_pack_with_semantic_graph_and_tests(tmp_path: Path) -> None:
    project, mb, semantic = _fixture_project(tmp_path)

    result = _run(
        [
            "--query",
            "where is order handling logic",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--semantic-candidates",
            str(semantic),
            "--json",
        ]
    )

    assert result.returncode == 0, result.stderr
    payload = _json(result)
    assert payload["ok"] is True
    assert payload["query"] == "where is order handling logic"
    assert "semantic" in payload["channels_used"]
    assert "graph" in payload["channels_used"]
    assert "read" in payload["channels_used"]
    assert "app/service.py" in payload["candidate_files"]
    assert "tests/test_service.py" in payload["test_files"]
    assert any(fact["dst"] == "charge_card" for fact in payload["graph_facts"])
    assert "app/service.py" in payload["recommended_next_reads"]


def test_code_context_semantic_unavailable_warns_and_falls_back_to_graph_text(
    tmp_path: Path,
) -> None:
    project, mb, _semantic = _fixture_project(tmp_path)

    result = _run(
        [
            "--query",
            "handle_order",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--semantic-provider",
            "unavailable",
            "--json",
        ]
    )

    assert result.returncode == 0
    payload = _json(result)
    assert payload["ok"] is True
    assert any("semantic provider unavailable" in warning for warning in payload["warnings"])
    assert "graph" in payload["channels_used"]
    assert "text" in payload["channels_used"]
    assert "app/service.py" in payload["candidate_files"]


def test_code_context_graph_mode_bypasses_semantic_candidates(tmp_path: Path) -> None:
    project, mb, semantic = _fixture_project(tmp_path)

    result = _run(
        [
            "--query",
            "handle_order",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--mode",
            "graph",
            "--semantic-candidates",
            str(semantic),
            "--json",
        ]
    )

    assert result.returncode == 0
    payload = _json(result)
    assert "semantic" not in payload["channels_used"]
    assert "graph" in payload["channels_used"]


def test_code_context_missing_graph_fails_open_with_warning(tmp_path: Path) -> None:
    project = tmp_path / "repo"
    mb = project / ".memory-bank"
    (project / "app").mkdir(parents=True)
    (mb / "codebase").mkdir(parents=True)
    (project / "app" / "service.py").write_text("def handle_order():\n    pass\n", encoding="utf-8")

    result = _run(
        [
            "--query",
            "handle_order",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--json",
        ]
    )

    assert result.returncode == 0
    payload = _json(result)
    assert payload["ok"] is True
    assert any("missing graph" in warning for warning in payload["warnings"])
    assert "text" in payload["channels_used"]
    assert payload["graph_facts"] == []


def test_code_context_evidence_pack_is_bounded_and_excludes_env_contents(tmp_path: Path) -> None:
    project, mb, semantic = _fixture_project(tmp_path)
    candidates = [{"file": f"app/file_{index}.py", "score": 0.5} for index in range(30)]
    candidates.insert(0, {"file": "app/service.py", "score": 0.99, "symbol": "handle_order"})
    candidates.insert(1, {"file": ".env.local", "score": 0.98})
    semantic.write_text(json.dumps({"candidates": candidates}), encoding="utf-8")

    result = _run(
        [
            "--query",
            "SECRET_TOKEN LOCAL_SECRET handle_order",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--semantic-candidates",
            str(semantic),
            "--json",
        ]
    )

    assert result.returncode == 0
    payload = _json(result)
    encoded = json.dumps(payload)
    assert len(payload["candidate_files"]) <= 10
    assert len(payload["graph_facts"]) <= 20
    assert "must-not-leak" not in encoded
    assert "must-not-leak-local" not in encoded
    assert ".env" not in payload["candidate_files"]
    assert ".env.local" not in payload["candidate_files"]
    assert ".env" not in payload["recommended_next_reads"]
    assert ".env.local" not in payload["recommended_next_reads"]


def test_code_context_accepts_semantic_only_alias(tmp_path: Path) -> None:
    project, mb, semantic = _fixture_project(tmp_path)

    result = _run(
        [
            "--query",
            "where is order handling logic",
            "--project-root",
            str(project),
            "--mb-path",
            str(mb),
            "--semantic-candidates",
            str(semantic),
            "--semantic-only",
            "--json",
        ]
    )

    assert result.returncode == 0, result.stderr
    payload = _json(result)
    assert payload["mode"] == "semantic"
    assert payload["channels_used"] == ["semantic", "read"]
    assert payload["graph_facts"] == []
