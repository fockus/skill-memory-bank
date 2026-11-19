"""Pi settle-resume gate (master-completion Stage 20).

The real extension (installed shape, Pi's jiti) with the real drive gate script on temp banks;
only Pi's event dispatch is simulated. Resume = hidden custom_message + continue:true.
"""

import json
import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "tests/fixtures/pi_native_graph_host.mjs"
GOAL = "---\nid: G-T\nstatus: active\n---\n\n# Goal\nShip.\n\n## Acceptance criteria\n\n- [{box}] only\n"


def _project(tmp: Path) -> Path:
    proj = tmp / "proj"
    (proj / ".memory-bank" / ".drive").mkdir(parents=True)
    (proj / ".memory-bank" / ".work-state").mkdir()
    (proj / ".memory-bank" / "status.md").write_text("# Status\n")
    return proj


def _drive(proj: Path, box: str, phase: str = "execution") -> None:
    bank = proj / ".memory-bank"
    (bank / "goal.md").write_text(GOAL.format(box=box))
    run = {"run_id": "R1", "bank": str(bank), "goal": str(bank / "goal.md"), "phase": phase}
    (bank / ".drive" / "R1.json").write_text(json.dumps(run))


@pytest.fixture
def world(tmp_path):
    home = tmp_path / "home"
    home.mkdir()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update({"HOME": str(home), "MB_UPDATE_CHECK": "off", "MB_GRAPH_CATCHUP": "off"})
    return {"home": home, "env": env, "proj": _project(tmp_path)}


def _work_run(proj: Path, run_id="W1", phase="in-progress") -> Path:
    run = {"run_id": run_id, "source": "plans/p.md", "item_no": 2, "phase": phase,
           "steps": ["implement", "verify"], "updated": datetime.now(UTC).isoformat()}
    path = proj / ".memory-bank" / ".work-state" / f"{run_id}.json"
    path.write_text(json.dumps(run))
    return path


def settle(world, count=1, outcome="completed"):
    start = {"emit": "session_start", "cwd": str(world["proj"]), "event": {}}
    step = {"emit": "agent_before_settle", "cwd": str(world["proj"]), "event": {"entries": [], "outcome": outcome}}
    steps = [{"emit": "agent_settled", "cwd": str(world["proj"]), "event": {"aborted": False}}] if count < 0 else []
    steps = [start] + steps + [dict(step) for _ in range(abs(count))]
    proc = subprocess.run(
        ["node", str(HOST)], cwd=ROOT, env=world["env"], text=True, capture_output=True, timeout=180,
        input=json.dumps({"home": str(world["home"]), "projectRoot": "", "steps": steps}),
    )
    assert proc.returncode == 0, proc.stderr
    results = json.loads(proc.stdout.strip().splitlines()[-1])
    return results[0], [r["outputs"] for r in results[2:]]


def test_settle_hook_is_registered_with_the_extension(world):
    meta, _ = settle(world)
    assert "agent_before_settle" in meta["events"]
    assert "agent_settled" in meta["events"]


def test_unfinished_drive_run_resumes_with_hidden_message(world):
    _drive(world["proj"], " ")
    _, outs = settle(world)
    (out,) = outs[0]
    assert out["continue"] is True
    msg = out["entries"][-1]
    assert msg["type"] == "custom_message" and msg["display"] is False
    assert "mb-drive.sh next" in msg["content"] and "R1" in msg["content"]


def test_met_goal_settles_without_continue(world):
    _drive(world["proj"], "x")
    _, outs = settle(world)
    assert outs[0] == []


def test_recorded_stop_settles_without_continue(world):
    _drive(world["proj"], " ", phase="stopped")
    _, outs = settle(world)
    assert outs[0] == []


def _run_node(world, steps):
    proc = subprocess.run(["node", str(HOST)], cwd=ROOT, env=world["env"], text=True, capture_output=True,
                          timeout=180, input=json.dumps({"home": str(world["home"]), "projectRoot": "", "steps": steps}))
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def _late_run(world, phase):
    """Session starts, then a run file appears (written by a delayed child), then Pi settles."""
    path = world["proj"] / ".memory-bank" / ".work-state" / "W1.json"
    run = {"run_id": "W1", "source": "plans/p.md", "item_no": 2, "phase": phase,
           "steps": ["implement", "verify"], "updated": datetime.now(UTC).isoformat()}
    writer = subprocess.Popen(["python3", "-c", "import sys,time; time.sleep(2); open(sys.argv[1],'w').write(sys.argv[2])",
                               str(path), json.dumps(run)])
    cwd = str(world["proj"])
    results = _run_node(world, [{"emit": "session_start", "cwd": cwd, "event": {}},
                                {"waitFile": str(path), "timeoutMs": 20000},
                                {"emit": "agent_before_settle", "cwd": cwd, "event": {"entries": [], "outcome": "completed"}}])
    writer.wait()
    return results[-1]["outputs"]


def test_work_run_created_during_session_resumes(world):
    (out,) = _late_run(world, "in-progress")
    assert out["continue"] is True and "W1" in out["entries"][-1]["content"]


def test_preexisting_foreign_work_run_does_not_resume(world):
    _work_run(world["proj"])
    _, outs = settle(world)
    assert outs[0] == []


def test_finished_work_run_settles(world):
    assert _late_run(world, "done") == []


def test_fourth_resume_in_one_cycle_settles(world):
    _drive(world["proj"], " ")
    _, outs = settle(world, count=4)
    assert [bool(o) for o in outs] == [True, True, True, False]


def test_real_settle_resets_the_cycle_cap(world):
    _drive(world["proj"], " ")
    step = {"cwd": str(world["proj"]), "event": {"entries": [], "outcome": "completed"}}
    steps = [{"emit": "session_start", "cwd": str(world["proj"]), "event": {}}]
    steps += [{"emit": "agent_before_settle", **step} for _ in range(4)]
    steps += [{"emit": "agent_settled", "cwd": str(world["proj"]), "event": {"aborted": False}},
              {"emit": "agent_before_settle", **step}]
    proc = subprocess.run(["node", str(HOST)], cwd=ROOT, env=world["env"], text=True, capture_output=True,
                          timeout=180, input=json.dumps({"home": str(world["home"]), "projectRoot": "", "steps": steps}))
    results = json.loads(proc.stdout.strip().splitlines()[-1])
    assert [bool(r["outputs"]) for r in results[2:]] == [True, True, True, False, False, True]


def test_corrupt_state_files_do_not_throw_or_resume(world):
    bank = world["proj"] / ".memory-bank"
    (bank / ".drive" / "R1.json").write_text("{not json")
    (bank / ".work-state" / "W1.json").write_text("\x00garbage")
    _, outs = settle(world)
    assert outs[0] == []


@pytest.mark.parametrize("outcome", ["error", "aborted"])
def test_error_and_aborted_responses_are_left_alone(world, outcome):
    _drive(world["proj"], " ")
    _, outs = settle(world, outcome=outcome)
    assert outs[0] == []
