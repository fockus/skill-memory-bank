"""Real installed extension cleanup, without model requests or forced process exit."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INSPECT = (
    Path(os.environ.get("PI_INSPECT_ROOT") or Path.home() / ".pi/agent/npm/node_modules/pi-inspect")
    / "extensions/inspect.ts"
)


@pytest.mark.parametrize("scenario", ["shutdown", "reload", "request-shutdown"])
def test_inspect_lifecycle_releases_request_watcher(tmp_path, scenario):
    if not INSPECT.is_file():
        pytest.skip("Installed pi-inspect is required for this integration check")
    home = tmp_path / "home"
    cwd = tmp_path / "project"
    home.mkdir()
    cwd.mkdir()
    try:
        result = subprocess.run(
            ["node", str(ROOT / "tests/fixtures/pi_native_lifecycle_host.mjs")],
            input=json.dumps(
                {
                    "home": str(home),
                    "cwd": str(cwd),
                    "extension": str(INSPECT),
                    "scenario": scenario,
                }
            ),
            text=True,
            capture_output=True,
            timeout=12,
            env={**os.environ, "HOME": str(home)},
        )
    except subprocess.TimeoutExpired as error:
        pytest.fail(f"SDK shutdown retained a referenced resource: {error.stdout!r}")
    assert result.returncode == 0, result.stderr
    resources = json.loads(result.stdout.strip().splitlines()[-1])
    assert resources["started"] == resources["before"] + 1, resources
    if scenario == "reload":
        assert resources["reloaded"] == resources["started"], resources
    assert resources["after"] == resources["before"], resources
    assert resources["timersAfter"] == resources["timersBefore"], resources


def test_installed_mb_file_loader_registers_native_tool_after_reload(tmp_path):
    agent_dir = Path.home() / ".pi/agent"
    extension = agent_dir / "extensions/memory-bank-subagent.ts"
    tintin = agent_dir / "npm/node_modules/@tintinweb/pi-subagents"
    if not extension.is_file() or not tintin.is_dir():
        pytest.skip("Installed MB extension and pinned Tintin required")
    home = tmp_path / "home"
    cwd = tmp_path / "project"
    home.mkdir()
    cwd.mkdir()
    result = subprocess.run(
        ["node", str(ROOT / "tests/fixtures/pi_native_lifecycle_host.mjs")],
        input=json.dumps(
            {
                "home": str(home),
                "cwd": str(cwd),
                "extension": str(extension),
                "tintinRoot": str(tintin),
                "scenario": "mb-file-reload",
            }
        ),
        text=True,
        capture_output=True,
        timeout=20,
        env={**os.environ, "HOME": str(home)},
    )
    assert result.returncode == 0, result.stderr
    observed = json.loads(result.stdout.strip().splitlines()[-1])
    assert not observed["reloadErrors"] and not observed["handlerErrors"], observed
    assert len(observed["states"]) == 2, observed
    for state in observed["states"]:
        assert "mb_dispatch_subagent" in state["tools"], state
        assert "mb_dispatch_subagent" in state["active"], state
        assert state["nativeMB"], state
    assert observed["modelCalls"] == 0, observed
