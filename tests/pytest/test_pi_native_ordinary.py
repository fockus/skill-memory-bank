"""Ordinary Pi composes the actual public Tintin service without a managed root."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "tests/fixtures/pi_native_ordinary_host.mjs"
TINTIN = Path(
    os.environ.get("PI_TINTIN_ROOT")
    or Path.home() / ".pi/agent/npm/node_modules/@tintinweb/pi-subagents"
)


def ordinary_host(tmp_path, scenario="ready"):
    home = tmp_path / "home with space"
    cwd = tmp_path / "project with space"
    home.mkdir()
    cwd.mkdir()
    proc = subprocess.run(
        ["node", str(FIXTURE)],
        input=json.dumps(
            {
                "home": str(home),
                "cwd": str(cwd),
                "scenario": scenario,
                "tintinRoot": str(TINTIN),
            }
        ),
        text=True,
        capture_output=True,
        timeout=60,
        env={**os.environ, "HOME": str(home)},
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def test_ordinary_pi_startup_binds_actual_tintin_without_model_calls(tmp_path):
    result = ordinary_host(tmp_path)
    assert result["ready"], result
    assert not result["errors"], result
    assert result["binding"]["sessionId"] == result["sessionId"]
    assert result["binding"]["components"]["tintin"]["agentMentions"] == "off"
    assert result["registryReady"]
    assert "mb_dispatch_subagent" in result["tools"]
    assert result["modelCalls"] == result["childCalls"] == 0
    assert result["foreignUnchanged"] and result["cwdUnchanged"]


@pytest.mark.parametrize("scenario", ["forged", "session-mismatch", "cwd-mismatch", "shutdown"])
def test_ordinary_pi_invalid_authority_refuses_dispatch(tmp_path, scenario):
    result = ordinary_host(tmp_path, scenario)
    assert result["ready"], result
    assert result["refused"], result
    assert result["modelCalls"] == result["childCalls"] == 0


def test_ordinary_pi_untrusted_project_refuses_before_dispatch(tmp_path):
    result = ordinary_host(tmp_path, "untrusted")
    assert not result["ready"], result
    assert any("trust" in error.lower() for error in result["errors"]), result
    assert result["modelCalls"] == result["childCalls"] == 0


def test_ordinary_pi_settings_change_cannot_be_reauthorized_by_rebind(tmp_path):
    result = ordinary_host(tmp_path, "settings-changed")
    assert result["ready"], result
    assert result["refused"] and result["rebindRefused"], result


def test_ordinary_pi_reload_replaces_service_and_invalidates_old_authority(tmp_path):
    result = ordinary_host(tmp_path, "reload")
    assert result["ready"], result
    assert result["oldRefused"] and result["generationChanged"], result
    assert result["newBinding"]["components"]["tintin"]["agentMentions"] == "off"
    assert result["modelCalls"] == result["childCalls"] == 0


def test_ordinary_pi_duplicate_tintin_refuses_without_launch(tmp_path):
    result = ordinary_host(tmp_path, "duplicate")
    assert not result["ready"], result
    assert any("duplicate" in error.lower() for error in result["errors"]), result
    assert result["modelCalls"] == result["childCalls"] == 0


def test_ordinary_pi_leaf_executes_read_with_inherited_model_and_no_extensions(tmp_path):
    result = ordinary_host(tmp_path, "leaf")
    assert result["ready"] and not result.get("error"), result
    assert result["childSessionId"] != result["sessionId"]
    assert result["childModel"] == result["parentModel"] == "openai/gpt-4.1"
    assert result["childTools"] == ["read"]
    assert result["childExtensions"] == []
    assert len(result["toolResults"]) == 1
    assert result["toolResults"][0]["toolName"] == "read"
    assert "ORDINARY_PI_NATIVE_READ" in json.dumps(result["toolResults"])
    assert "READ_VERIFIED:ORDINARY_PI_NATIVE_READ" in json.dumps(result["answer"])
    assert result["requests"] == 4 and not result.get("transportError")
    assert result["consumed"] and not result["running"]


def test_malformed_managed_settings_refuse_with_scope(tmp_path):
    (tmp_path / "settings.json").write_text("{broken")
    script = """
const { managedSettingsStorage } = await import(process.argv[1]);
try { managedSettingsStorage(process.argv[2], process.argv[2]).withLock('global', () => undefined); }
catch (error) { console.log(error.message); }
"""
    proc = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            script,
            (ROOT / "adapters/pi_native_bootstrap.mjs").as_uri(),
            str(tmp_path),
        ],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr
    assert "Invalid global Pi settings" in proc.stdout


def test_ordinary_pi_child_context_does_not_activate_operator_service(tmp_path):
    result = ordinary_host(tmp_path, "child")
    assert not result["ready"], result
    assert result["modelCalls"] == result["childCalls"] == 0
