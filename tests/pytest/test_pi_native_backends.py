"""Common gate facts with explicit engine selection; remote roles are doubles."""

import json

import pytest
from test_pi_native_commands import host
from test_pi_native_work import evidence, project


@pytest.mark.parametrize("backend", ["nico", "tintin"])
@pytest.mark.parametrize("named", [False, True])
def test_selected_engine_runs_common_native_pipeline(tmp_path, backend, named):
    mb, source = project(tmp_path, named=named)
    result = host(tmp_path, tmp_path, args=f"work sample --range 1 --backend {backend}")
    assert not result.get("error"), result
    assert [child["backend"] for child in result["launches"]] == [backend] * 4
    assert evidence(mb)[0]["phase"] == "done"
    identity = json.loads(next((mb / "reports/native-work").glob("*/identity-1.json")).read_text())
    assert identity["backend"] == backend
    assert identity["sessionId"] == "test-session"
    assert identity["roleContracts"]["implement"]["model"] == "openai/gpt-6.1-sol"
    assert source.exists()


@pytest.mark.parametrize("backend", ["nico", "tintin"])
@pytest.mark.parametrize(
    "step,verdict,count",
    [("verify", "FAIL", 2), ("review", "CHANGES_REQUESTED", 3), ("judge", "NO_GO", 4)],
)
def test_both_engines_enforce_negative_gates(tmp_path, backend, step, verdict, count):
    mb, source = project(tmp_path)
    result = host(
        tmp_path,
        tmp_path,
        args=f"work sample --range 1 --backend {backend}",
        negative={"step": step, "verdict": verdict},
    )
    assert result.get("error"), result
    assert len(result["launches"]) == count
    assert all(child["backend"] == backend for child in result["launches"])
    assert evidence(mb)[0]["phase"] != "done"
    assert "- [ ]" in source.read_text()


@pytest.mark.parametrize("backend", ["nico", "tintin"])
def test_cancel_stops_only_selected_owned_child(tmp_path, backend):
    mb, _ = project(tmp_path)
    result = host(
        tmp_path,
        tmp_path,
        args=f"work sample --range 1 --backend {backend}",
        cancelDuringSpawn=True,
    )
    assert result.get("error") and result["cancelled"], result
    assert result["controls"] == [backend]
    assert evidence(mb)[0]["phase"] != "done"


def test_bank_selection_is_overridden_only_by_explicit_flag(tmp_path):
    mb, _ = project(tmp_path)
    (mb / ".mb-config").write_text("pi_subagent_backend=tintin\n")
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert not result.get("error"), result
    assert all(child["backend"] == "tintin" for child in result["launches"])


def test_ordinary_unbound_work_requires_managed_startup(tmp_path):
    project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1", unbound=True)
    assert "mb-pi" in result.get("error", ""), result
    assert not result["launches"]


def test_tintin_external_runner_and_isolation_refuse_before_implementation(tmp_path):
    mb, _ = project(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(pipeline.read_text().replace("mb-reviewer", "codex-cli"))
    result = host(tmp_path, tmp_path, args="work sample --range 1 --backend tintin")
    assert "external" in result.get("error", "").lower(), result
    assert not result["launches"]


@pytest.mark.parametrize("backend", ["nico", "tintin"])
def test_enabled_or_unknown_tintin_mentions_block_either_engine(tmp_path, backend):
    project(tmp_path)
    result = host(
        tmp_path, tmp_path, args=f"work sample --range 1 --backend {backend}", unsafeMentions=True
    )
    assert "mention" in result.get("error", "").lower(), result
    assert not result["launches"]


def work_result(result):
    return json.loads(
        next(m["content"] for m in result["messages"] if m.get("customType") == "mb-native-work")
    )


def terminals(mb):
    return [
        json.loads(p.read_text()) for p in (mb / "reports/native-work").glob("*/*.terminal.json")
    ]


def test_default_backend_is_tintin_without_flag_or_config(tmp_path):
    mb, _ = project(tmp_path, backend=None)
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert not result.get("error"), result
    assert [child["backend"] for child in result["launches"]] == ["tintin"] * 4
    assert not result["ceilings"]
    assert evidence(mb)[0]["phase"] == "done"


@pytest.mark.parametrize(
    "configured,flag,expected",
    [
        ("nico", "", "nico"),
        ("nico", " --backend tintin", "tintin"),
        ("tintin", " --backend nico", "nico"),
    ],
)
def test_bank_config_and_flag_override_default(tmp_path, configured, flag, expected):
    project(tmp_path, backend=configured)
    result = host(tmp_path, tmp_path, args=f"work sample --range 1{flag}")
    assert not result.get("error"), result
    assert {child["backend"] for child in result["launches"]} == {expected}


def test_nico_launches_only_under_registered_capability_ceiling(tmp_path):
    project(tmp_path)
    result = host(tmp_path, tmp_path, args="work sample --range 1 --backend nico")
    assert not result.get("error"), result
    assert len(result["launches"]) == len(result["ceilings"]) == 4
    for child in result["launches"]:
        assert child["ceiling"] == {
            "sessionId": "test-session",
            "allowedTools": ["bash", "read", "write", "edit", "grep", "find"],
            "allowedAgents": [],
            "denyExtensions": True,
        }
    assert all(entry["disposed"] for entry in result["ceilings"])


@pytest.mark.parametrize("failure", ["ceilingFails", "noCeilingApi"])
def test_nico_refuses_launch_without_capability_ceiling(tmp_path, failure):
    mb, source = project(tmp_path)
    result = host(
        tmp_path, tmp_path, args="work sample --range 1 --backend nico", **{failure: True}
    )
    assert "ceiling" in result.get("error", "").lower(), result
    assert not result["launches"]
    assert all(state["phase"] != "done" for state in evidence(mb))
    assert "- [ ]" in source.read_text()


def test_nico_reports_runtime_inventory_unverified_tintin_does_not(tmp_path):
    nico_root, tintin_root = tmp_path / "nico", tmp_path / "tintin"
    nico_root.mkdir(), tintin_root.mkdir()
    nico_mb, _ = project(nico_root)
    nico = host(nico_root, nico_root, args="work sample --range 1 --backend nico")
    tintin_mb, _ = project(tintin_root)
    tintin = host(tintin_root, tintin_root, args="work sample --range 1 --backend tintin")
    assert not nico.get("error") and not tintin.get("error"), (nico, tintin)
    assert work_result(nico)["runtimeInventory"]["status"] == "UNVERIFIED"
    assert all(t["runtimeInventory"]["status"] == "UNVERIFIED" for t in terminals(nico_mb))
    assert "runtimeInventory" not in work_result(tintin)
    assert all("runtimeInventory" not in t for t in terminals(tintin_mb))
