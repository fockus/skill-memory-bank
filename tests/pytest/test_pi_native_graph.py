"""Pi-native GraphRAG tools and graph lifecycle (Stage 3).

Real extension (installed shape, Pi's jiti), real scripts, real graphs built by
mb-codegraph.py in two temp projects, temp HOME. Only tool registry/event dispatch is simulated.
"""

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "tests/fixtures/pi_native_graph_host.mjs"
TOOLS = ["code_context", "graph_impact", "graph_neighbors", "graph_tests", "search_code"]


def _project(tmp: Path, name: str, src: str) -> Path:
    proj = tmp / name
    (proj / "src").mkdir(parents=True)
    (proj / "src" / f"{name}.py").write_text(src)
    (proj / ".memory-bank").mkdir()
    return proj


def _build_graph(proj: Path, env: dict) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/mb-codegraph.py"),
            "--apply",
            str(proj / ".memory-bank"),
            str(proj),
        ],
        env=env,
        check=True,
        capture_output=True,
    )


@pytest.fixture
def world(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = {
        k: v for k, v in os.environ.items() if not k.startswith(("MB_", "FASTEMBED", "HF_", "XDG_"))
    }
    env.update({"HOME": str(home), "MB_UPDATE_CHECK": "off"})
    a = _project(
        tmp_path,
        "alpha",
        "def alpha():\n    return 1\n\n\ndef alpha_caller():\n    return alpha()\n",
    )
    b = _project(tmp_path, "beta", "def beta():\n    return 2\n")
    for proj in (a, b):
        _build_graph(proj, env)
    bare = tmp_path / "bare"
    bare.mkdir()
    return {"tmp": tmp_path, "home": home, "env": env, "a": a, "b": b, "bare": bare}


def run(world, steps, env=None, project_root=""):
    proc = subprocess.run(
        ["node", str(HOST)],
        cwd=ROOT,
        env={**world["env"], **(env or {})},
        text=True,
        capture_output=True,
        timeout=180,
        input=json.dumps({"home": str(world["home"]), "projectRoot": project_root, "steps": steps}),
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def call(tool, cwd, **params):
    return {"call": tool, "cwd": str(cwd), "params": params}


def _tree_digest(path: Path) -> str:
    h = hashlib.sha256()
    for f in sorted(p for p in path.rglob("*") if p.is_file()):
        h.update(str(f.relative_to(path)).encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def test_registers_native_tools_and_lifecycle_events(world):
    head = run(world, [])[0]
    assert head["tools"] == TOOLS
    assert {"session_start", "tool_result", "session_compact"} <= set(head["events"])


def test_graph_tools_answer_from_the_bank_of_ctx_cwd(world):
    out = run(
        world,
        [
            call("graph_neighbors", world["a"], symbol="alpha"),
            call("graph_neighbors", world["b"], symbol="beta"),
            # Pi started in a project subfolder walks up to the project's bank.
            call("graph_neighbors", world["a"] / "src", symbol="alpha"),
        ],
    )
    assert out[1]["ok"] and out[1]["details"]["status"] == "ok"
    assert "alpha_caller" in out[1]["text"]
    assert out[2]["ok"] and "beta" in out[2]["text"]
    assert out[3]["ok"] and "alpha_caller" in out[3]["text"], out[3]


def test_model_supplied_bank_path_cannot_redirect_to_another_project(world):
    out = run(
        world,
        [
            call(
                "graph_neighbors",
                world["a"],
                symbol="beta",
                mbPath=str(world["b"] / ".memory-bank"),
                projectRoot=str(world["b"]),
            )
        ],
    )
    assert out[1]["ok"] is False
    assert "graph_neighbors failed" in out[1]["error"]


def test_no_match_is_an_explicit_failure_even_though_stdout_is_json(world):
    out = run(world, [call("graph_impact", world["a"], symbol="does_not_exist")])
    assert out[1]["ok"] is False
    assert "graph_impact failed" in out[1]["error"]


def test_missing_bank_is_an_explicit_failure_without_initialising_one(world):
    out = run(
        world,
        [
            call("graph_tests", world["bare"], symbol="alpha"),
            call("code_context", world["bare"], query="where is alpha"),
        ],
    )
    assert [r["ok"] for r in out[1:]] == [False, False]
    assert all("no Memory Bank" in r["error"] for r in out[1:])
    assert not (world["bare"] / ".memory-bank").exists()


def test_search_code_without_graph_fails(world):
    proj = _project(world["tmp"], "nograph", "x = 1\n")
    out = run(world, [call("search_code", proj, query="alpha")])
    assert out[1]["ok"] is False
    assert "search_code failed" in out[1]["error"]


def test_search_code_labels_bm25_fallback_as_degraded(world):
    out = run(
        world,
        [
            call("search_code", world["a"], query="alpha caller function"),
            call("search_code", world["a"], query="alpha", backend="bm25"),
        ],
    )
    fallback, lexical = out[1], out[2]
    assert fallback["ok"] and fallback["details"]["status"] == "degraded"
    assert fallback["details"]["payload"]["backend"] == "bm25"
    assert "BM25 fallback" in fallback["text"]
    assert lexical["ok"] and lexical["details"]["status"] == "ok"


def test_code_context_returns_evidence_from_current_bank(world):
    out = run(world, [call("code_context", world["a"], query="alpha_caller")])
    assert out[1]["ok"], out[1]
    assert out[1]["details"]["status"] in {"ok", "degraded"}
    assert "src/alpha.py" in out[1]["text"]


def test_tool_cancellation_stops_the_script_promptly(world):
    slow = world["tmp"] / "slow-python"
    slow.write_text("#!/usr/bin/env bash\nsleep 30\n")
    slow.chmod(0o755)
    step = {**call("graph_neighbors", world["a"], symbol="alpha"), "abortAfterMs": 300}
    out = run(world, [step], env={"MB_PYTHON": str(slow)})
    assert out[1]["ok"] is False
    assert "cancelled" in out[1]["error"]
    assert out[1]["ms"] < 5000


def test_session_start_catches_up_dirty_graph_in_background_for_current_bank_only(world):
    dirty = world["a"] / ".memory-bank/codebase/.graph-dirty"
    (world["a"] / "src/alpha.py").write_text(
        "def alpha():\n    return 1\n\n\ndef alpha_two():\n    return alpha()\n"
    )
    dirty.write_text(str(world["a"] / "src/alpha.py") + "\n")
    before_b = _tree_digest(world["b"])
    log = world["a"] / ".memory-bank/codebase/.graph-catchup.log"
    out = run(
        world,
        [
            {"emit": "session_start", "cwd": str(world["a"]), "event": {"reason": "startup"}},
            {"waitFile": str(log)},
        ],
    )
    assert out[1]["ok"] and out[1]["ms"] < 3000  # start is not blocked by the catch-up
    assert out[2]["exists"]
    assert json.loads(log.read_text())["result"] == "refreshed"
    assert not dirty.exists()
    assert "alpha_two" in (world["a"] / ".memory-bank/codebase/graph.json").read_text()
    assert _tree_digest(world["b"]) == before_b


def test_session_start_on_clean_graph_does_not_encode_the_corpus(world):
    record = world["tmp"] / "semantic-calls"
    fake = world["tmp"] / "semantic-python"
    fake.write_text(f'#!/usr/bin/env bash\necho "$@" >> "{record}"\n')
    fake.chmod(0o755)
    log = world["b"] / ".memory-bank/codebase/.graph-catchup.log"
    run(
        world,
        [
            {"emit": "session_start", "cwd": str(world["b"]), "event": {"reason": "startup"}},
            {"waitFile": str(log)},
        ],
        env={"MB_SEMANTIC_PY": str(fake)},
    )
    assert json.loads(log.read_text())["result"] == "clean"
    assert not record.exists()


def test_session_start_catchup_respects_off_switch(world):
    run(
        world,
        [
            {"emit": "session_start", "cwd": str(world["a"]), "event": {}},
            {
                "waitFile": str(world["a"] / ".memory-bank/codebase/.graph-catchup.log"),
                "timeoutMs": 1500,
            },
        ],
        env={"MB_GRAPH_CATCHUP": "off"},
    )
    assert not (world["a"] / ".memory-bank/codebase/.graph-catchup.log").exists()


def _write_event(cwd, path, tool="write"):
    return {
        "emit": "tool_result",
        "cwd": str(cwd),
        "event": {
            "toolName": tool,
            "toolCallId": "t1",
            "input": {"path": str(path)},
            "content": [{"type": "text", "text": "ok"}],
            "isError": False,
        },
    }


def test_code_write_marks_current_graph_dirty_without_cross_project_writes(world):
    before_b = _tree_digest(world["b"])
    run(
        world,
        [
            _write_event(world["a"], "src/new_module.py"),
            _write_event(world["a"], "README.md", tool="edit"),
            _write_event(world["a"], world["b"] / "src/beta.py", tool="edit"),
        ],
    )
    dirty = (world["a"] / ".memory-bank/codebase/.graph-dirty").read_text().splitlines()
    assert dirty == [str(world["a"] / "src/new_module.py")]
    assert _tree_digest(world["b"]) == before_b


def _grep_event(cwd, command):
    return {
        "emit": "tool_result",
        "cwd": str(cwd),
        "sessionId": "nudge-session",
        "event": {
            "toolName": "bash",
            "toolCallId": "t2",
            "input": {"command": command},
            "content": [{"type": "text", "text": "src/alpha.py:1:def alpha"}],
            "isError": False,
        },
    }


def test_structural_grep_result_carries_graph_nudge(world):
    out = run(
        world,
        [_grep_event(world["a"], "grep -rn 'def alpha' src/"), _grep_event(world["a"], "ls -la")],
    )
    content = out[1]["outputs"][0]["content"]
    assert content[0]["text"] == "src/alpha.py:1:def alpha"
    assert "code graph" in content[1]["text"]
    assert out[2]["outputs"] == []
    assert list((world["a"] / ".memory-bank/.index").glob(".graph-nudge.*"))
    assert not (world["b"] / ".memory-bank/.index").exists()


def test_graph_nudge_respects_off_switch(world):
    out = run(
        world, [_grep_event(world["a"], "grep -rn 'def alpha' src/")], env={"MB_GRAPH_NUDGE": "off"}
    )
    assert out[1]["outputs"] == []
