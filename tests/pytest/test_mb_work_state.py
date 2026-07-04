"""Backlog I-093 S1 — `scripts/mb-work-state.sh` durable loop-state + max_cycles enforcement.

The `/mb work` loop currently counts fix-cycles only in the orchestrator's
context (see plan `.memory-bank/plans/2026-07-04_fix_mb-work-resilience.md`
Stage 1). This durable `<bank>/.work-state.json` state makes `max_cycles`
enforcement deterministic (by exit code), surviving compaction/abort.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-state.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _state(mb: Path) -> dict:
    return json.loads((mb / ".work-state.json").read_text(encoding="utf-8"))


def _status_json(mb: Path) -> dict:
    r = _run("status", mb=mb)
    assert r.returncode == 0, r.stderr
    return json.loads(r.stdout)


# ──────────────────────────────────────────────────────────────────────────


def test_init_creates_state_and_prints_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "plans/x.md", "2", mb=mb)
    assert r.returncode == 0, r.stderr

    state_file = mb / ".work-state.json"
    assert state_file.is_file()

    run_id = r.stdout.strip()
    assert run_id

    state = _state(mb)
    assert state["run_id"] == run_id
    assert state["cycle"] == 0
    assert state["phase"] == "in-progress"
    assert state["item_no"] == 2
    assert state.get("max_cycles")


def test_init_accepts_explicit_run_id(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", "plans/x.md", "2", "--run-id", "fixed-id", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "fixed-id"
    assert _state(mb)["run_id"] == "fixed-id"


def test_step_appends_transition(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r1 = _run("step", "implement", mb=mb)
    assert r1.returncode == 0, r1.stderr
    r2 = _run("step", "verify", mb=mb)
    assert r2.returncode == 0, r2.stderr

    status = _status_json(mb)
    assert status["steps"] == ["implement", "verify"]


def test_cycle_increments_and_passes_under_cap(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", "--max-cycles", "2", mb=mb)

    r1 = _run("cycle", mb=mb)
    assert r1.returncode == 0, r1.stderr
    assert _state(mb)["cycle"] == 1

    r2 = _run("cycle", mb=mb)
    assert r2.returncode == 0, r2.stderr
    assert _state(mb)["cycle"] == 2


def test_cycle_exhausted_returns_exit_3(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", "--max-cycles", "2", mb=mb)
    _run("cycle", mb=mb)
    _run("cycle", mb=mb)

    r3 = _run("cycle", mb=mb)
    assert r3.returncode == 3
    assert "cycle budget exhausted" in r3.stderr.lower()


def test_done_sets_phase_done(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r = _run("done", mb=mb)
    assert r.returncode == 0, r.stderr
    assert _status_json(mb)["phase"] == "done"


def test_clear_removes_state(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run("init", "plans/x.md", "2", mb=mb)
    r = _run("clear", mb=mb)
    assert r.returncode == 0, r.stderr
    assert not (mb / ".work-state.json").exists()


def test_status_missing_state_is_fail_safe(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert r.stdout.strip() in ("", "{}")


def test_malformed_state_is_fail_safe(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / ".work-state.json").write_text("{not valid json", encoding="utf-8")
    r = _run("status", mb=mb)
    assert r.returncode == 0
    assert "traceback" not in (r.stdout + r.stderr).lower()


# ── Backlog I-094 S1 — per-run slots + claim + baseline (MB_WORK_PARALLEL) ──


def _run_parallel(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["MB_WORK_PARALLEL"] = "1"
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def _perrun_state(mb: Path, run_id: str) -> dict:
    return json.loads((mb / ".work-state" / f"{run_id}.json").read_text(encoding="utf-8"))


def test_parallel_init_writes_perrun_slot(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", mb=mb)
    assert r.returncode == 0, r.stderr

    assert (mb / ".work-state" / "r1.json").is_file()
    assert not (mb / ".work-state.json").exists()
    assert _perrun_state(mb, "r1")["source"] == "plans/a.md"


def test_two_parallel_runs_have_independent_cycles(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", "--max-cycles", "2", mb=mb)
    _run_parallel("init", "plans/b.md", "1", "--run-id", "r2", "--max-cycles", "2", mb=mb)

    assert _run_parallel("cycle", "--run-id", "r1", mb=mb).returncode == 0
    assert _run_parallel("cycle", "--run-id", "r1", mb=mb).returncode == 0
    assert _run_parallel("cycle", "--run-id", "r2", mb=mb).returncode == 0

    assert _perrun_state(mb, "r1")["cycle"] == 2
    assert _perrun_state(mb, "r2")["cycle"] == 1


def test_init_records_baseline_ref_in_git_repo(tmp_path: Path) -> None:
    repo = tmp_path
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "a@b.c"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "test"], cwd=repo, check=True)
    (repo / "README.md").write_text("hi\n", encoding="utf-8")
    subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, check=True)
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True
    ).stdout.strip()

    mb = _init_mb(tmp_path)
    r = subprocess.run(
        ["bash", str(SCRIPT), "init", "plans/x.md", "2", "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        cwd=repo,
    )
    assert r.returncode == 0, r.stderr
    assert _state(mb)["baseline_ref"] == head


def test_init_baseline_ref_empty_outside_repo(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    env = dict(os.environ)
    env["GIT_CEILING_DIRECTORIES"] = str(tmp_path.parent)
    r = subprocess.run(
        ["bash", str(SCRIPT), "init", "plans/x.md", "2", "--mb", str(mb)],
        capture_output=True,
        text=True,
        check=False,
        cwd=tmp_path,
        env=env,
    )
    assert r.returncode == 0, r.stderr
    assert _state(mb)["baseline_ref"] == ""


def test_init_claim_refused_exit_4(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r1 = _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", mb=mb)
    assert r1.returncode == 0, r1.stderr

    r2 = _run_parallel("init", "plans/a.md", "1", "--run-id", "r2", mb=mb)
    assert r2.returncode == 4
    assert "already claimed by run r1" in r2.stderr.lower()
    assert not (mb / ".work-state" / "r2.json").exists()


def test_init_takeover_overrides_claim(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", mb=mb)

    r2 = _run_parallel("init", "plans/a.md", "1", "--run-id", "r2", "--takeover", mb=mb)
    assert r2.returncode == 0, r2.stderr
    assert (mb / ".work-state" / "r2.json").is_file()

    status = _run_parallel("status", "--all", mb=mb)
    assert status.returncode == 0, status.stderr
    runs = {entry["run_id"] for entry in json.loads(status.stdout)}
    assert "r2" in runs


def test_init_claim_free_after_done(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", mb=mb)
    done = _run_parallel("done", "--run-id", "r1", mb=mb)
    assert done.returncode == 0, done.stderr

    r2 = _run_parallel("init", "plans/a.md", "1", "--run-id", "r2", mb=mb)
    assert r2.returncode == 0, r2.stderr


def test_status_all_lists_every_run(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _run_parallel("init", "plans/a.md", "1", "--run-id", "r1", mb=mb)
    _run_parallel("init", "plans/b.md", "1", "--run-id", "r2", mb=mb)
    # A corrupt slot must not break the listing (fail-safe skip).
    (mb / ".work-state" / "r3.json").write_text("{not valid json", encoding="utf-8")

    r = _run_parallel("status", "--all", mb=mb)
    assert r.returncode == 0, r.stderr
    entries = json.loads(r.stdout)
    run_ids = {e["run_id"] for e in entries}
    assert {"r1", "r2"} <= run_ids
    assert "r3" not in run_ids


def test_new_run_id_prints_unique(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r1 = _run("new-run-id", mb=mb)
    r2 = _run("new-run-id", mb=mb)
    assert r1.returncode == 0, r1.stderr
    assert r2.returncode == 0, r2.stderr
    assert r1.stdout.strip()
    assert r1.stdout.strip() != r2.stdout.strip()
    assert not (mb / ".work-state.json").exists()
    assert not (mb / ".work-state").exists()
