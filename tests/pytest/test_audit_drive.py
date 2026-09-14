"""Real drive preflight and firewall regression contracts (R05/R10)."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def drive(tmp_path: Path):
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    (bank / "goal.md").write_text(
        "---\nid: G-900\nstatus: active\nmode: static\n"
        "progress_source: checklist\nprogress_target: 100\n---\n"
        "# Goal\n## Description\nProduce a documented result.\n"
        "## Acceptance criteria\n- [ ] Result file delivered\n"
    )
    (bank / "checklist.md").write_text("- ⬜ Result file delivered\n")
    (bank / "status.md").write_text("# Status\n")
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("MB_")}
    env.update(SKILL_DIR=str(ROOT), BANK=str(bank), MB_WORK_RUN_ID="audit-drive", MB_GRAPH_AUTOUPDATE="off")
    return bank, env


def run(drive, script: str, *args: object):
    bank, env = drive
    return subprocess.run(
        ["bash", str(ROOT / "scripts" / script), *map(str, args)],
        cwd=bank.parent, env=env, capture_output=True, text=True, check=False,
    )


def preflight(drive):
    bank, env = drive
    document = (ROOT / "commands/drive.md").read_text()
    snippet = re.search(r"<!-- mb-drive:preflight -->\s*```bash\n(.*?)\n```", document, re.S)
    assert snippet is not None
    return subprocess.run(
        ["bash", "-c", snippet.group(1)], cwd=bank.parent, env=env,
        capture_output=True, text=True, check=False,
    )


def slot(drive, kind: str) -> Path:
    bank, env = drive
    if env.get("MB_WORK_PARALLEL") == "1":
        return bank / f".{kind}" / f"{env['MB_WORK_RUN_ID']}.json"
    return bank / f".{kind}.json"


@pytest.mark.parametrize("parallel", ["0", "1"])
def test_preflight_same_run_preserves_cycle_steps_limits_and_spend(drive, parallel):
    bank, env = drive
    env.update(MB_WORK_PARALLEL=parallel, MAX_CYCLES="3", BUDGET="1000")
    first = preflight(drive)
    assert first.returncode == 0, first.stderr
    for _ in range(2):
        assert run(drive, "mb-work-state.sh", "cycle", "--mb", bank).returncode == 0
    assert run(drive, "mb-work-state.sh", "step", "verify", "--mb", bank).returncode == 0
    assert run(drive, "mb-work-budget.sh", "add", 700, "--run-id", env["MB_WORK_RUN_ID"], "--mb", bank).returncode == 0
    before = {kind: slot(drive, kind).read_bytes() for kind in ("work-state", "work-budget")}
    assert json.loads(before["work-state"])["cycle"] == 2

    resumed = preflight(drive)

    assert resumed.returncode == 0, resumed.stderr
    assert {kind: slot(drive, kind).read_bytes() for kind in before} == before
    assert run(drive, "mb-work-state.sh", "cycle", "--mb", bank).returncode == 0
    exhausted = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])
    assert exhausted.stdout.strip() == "stop_human max-cycle", exhausted.stderr


def test_drive_pending_goal_with_default_firewall_selects_concrete_implement(drive):
    bank, env = drive
    assert preflight(drive).returncode == 0

    result = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "implement auto Result file delivered"


def test_drive_failed_current_work_with_default_firewall_repairs_current_item(drive):
    bank, env = drive
    init = run(drive, "mb-work-state.sh", "init", "drive", 0, "--heading", "Deliver result", "--mb", bank)
    assert init.returncode == 0, init.stderr
    (bank.parent / "unfinished.py").write_text("# TODO: finish result\n")
    subprocess.run(["git", "-C", str(bank.parent), "add", "--intent-to-add", "unfinished.py"], check=True)

    result = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])

    assert result.stdout.strip() == "repair Deliver result", result.stderr


def test_drive_complete_signal_still_runs_full_firewall_acceptance(drive, tmp_path):
    bank, env = drive
    assert preflight(drive).returncode == 0
    acceptance = tmp_path / "accepted.sh"
    acceptance.write_text("#!/bin/sh\nprintf '%s\\n' '{\"ok\":true,\"findings\":[]}'\n")
    acceptance.chmod(0o755)
    env["MB_GOAL_ACCEPTANCE_BIN"] = str(acceptance)

    result = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])

    assert result.stdout.strip() == "repair (current)", result.stderr


def test_drive_complete_goal_with_default_firewall_stops_success(drive):
    bank, env = drive
    assert preflight(drive).returncode == 0
    goal = bank / "goal.md"
    goal.write_text(goal.read_text().replace("- [ ]", "- [x]"))
    (bank / "checklist.md").write_text("- ✅ Result file delivered\n")

    result = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])

    assert result.stdout.strip() == "stop_success", result.stderr


@pytest.mark.parametrize("kind", ["work-state", "work-budget", "drive-state"])
@pytest.mark.parametrize("corruption", ["{invalid", "{}", "null"])
def test_preflight_corrupt_existing_component_refuses_without_reset(drive, kind, corruption):
    _, env = drive
    env.update(MAX_CYCLES="3", BUDGET="1000")
    assert preflight(drive).returncode == 0
    slot(drive, kind).write_text(corruption)
    before = {key: slot(drive, key).read_bytes() for key in ("work-state", "work-budget", "drive-state")}

    result = preflight(drive)

    assert result.returncode != 0
    assert "[drive]" in result.stderr
    assert {key: slot(drive, key).read_bytes() for key in before} == before


@pytest.mark.parametrize("kind", ["work-state", "work-budget", "drive-state"])
def test_preflight_partial_start_only_initializes_missing_component(drive, kind):
    bank, env = drive
    env.update(MAX_CYCLES="3", BUDGET="1000")
    assert preflight(drive).returncode == 0
    assert run(drive, "mb-work-state.sh", "cycle", "--mb", bank).returncode == 0
    assert run(drive, "mb-work-budget.sh", "add", 700, "--mb", bank).returncode == 0
    slot(drive, kind).unlink()
    before = {
        key: slot(drive, key).read_bytes()
        for key in ("work-state", "work-budget", "drive-state") if key != kind
    }

    result = preflight(drive)

    assert result.returncode == 0, result.stderr
    assert slot(drive, kind).is_file()
    assert {key: slot(drive, key).read_bytes() for key in before} == before


@pytest.mark.parametrize("flag", ["BUDGET", "MAX_CYCLES"])
def test_preflight_conflicting_resume_limit_refuses_without_reset(drive, flag):
    _, env = drive
    env.update(MAX_CYCLES="3", BUDGET="1000")
    assert preflight(drive).returncode == 0
    before = {key: slot(drive, key).read_bytes() for key in ("work-state", "work-budget", "drive-state")}
    env[flag] = "4000"

    result = preflight(drive)

    assert result.returncode != 0
    assert "[drive]" in result.stderr
    assert {key: slot(drive, key).read_bytes() for key in before} == before


def test_preflight_resume_without_repeated_flags_keeps_exhausted_budget(drive):
    bank, env = drive
    env.update(MAX_CYCLES="3", BUDGET="1000")
    assert preflight(drive).returncode == 0
    assert run(drive, "mb-work-budget.sh", "add", 1000, "--mb", bank).returncode == 0
    env.pop("BUDGET")
    env.pop("MAX_CYCLES")

    result = preflight(drive)

    assert result.returncode == 0, result.stderr
    assert json.loads(slot(drive, "work-state").read_bytes())["max_cycles"] == 3
    action = run(drive, "mb-drive.sh", "next", "--bank", bank, "--run-id", env["MB_WORK_RUN_ID"])
    assert action.stdout.strip() == "stop_budget", action.stderr
