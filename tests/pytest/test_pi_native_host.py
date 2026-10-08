"""Session-bound host authority against the real public Pi SDK (no remote calls)."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/pi_native_sdk_host.mjs"


def managed_host(tmp_path, scenario="ready"):
    cwd = tmp_path / "project"
    cwd.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    proc = subprocess.run(
        ["node", str(FIXTURE)],
        input=json.dumps({"home": str(home), "cwd": str(cwd), "scenario": scenario}),
        text=True,
        capture_output=True,
        env={**os.environ, "HOME": str(home)},
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def test_managed_factory_binding_is_ready_before_work(tmp_path):
    result = managed_host(tmp_path)
    assert result["ready"], result
    assert result["binding"]["sessionId"] == result["sessionId"]
    assert result["binding"]["components"]["tintin"]["agentMentions"] == "off"
    assert result["modelCalls"] == result["childCalls"] == 0


@pytest.mark.parametrize(
    "scenario",
    [
        "unknown",
        "forged",
        "session-mismatch",
        "early",
        "disposed",
        "late",
        "settings-changed",
        "settings-rebind",
    ],
)
def test_unknown_or_stale_binding_refuses_dispatch(tmp_path, scenario):
    result = managed_host(tmp_path, scenario)
    assert result["refused"], result
    assert result["modelCalls"] == result["childCalls"] == 0


@pytest.mark.parametrize(
    "scenario", ["factory-failure", "ignored-overlay", "duplicate", "untrusted", "child-context"]
)
def test_unsafe_composition_refuses_startup(tmp_path, scenario):
    result = managed_host(tmp_path, scenario)
    assert result.get("refused", False), result
    assert not result["ready"]
    assert result["modelCalls"] == result["childCalls"] == 0


def test_session_replacement_rebinds_and_invalidates_previous_api(tmp_path):
    result = managed_host(tmp_path, "replacement")
    assert result["ready"], result
    assert result["sessionChanged"] and result["generationChanged"]
    assert result["oldRefused"] and result["lateIgnored"]


def test_runtime_overlay_preserves_foreign_settings_and_cwd(tmp_path):
    result = managed_host(tmp_path, "foreign")
    assert result["ready"], result
    assert result["foreignUnchanged"] and result["cwdUnchanged"]
    assert result["binding"]["components"]["tintin"]["agentMentions"] == "off"
