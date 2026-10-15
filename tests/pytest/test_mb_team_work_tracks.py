"""Every /mb team track runs through /mb work (AGR-103, REQ-001, REQ-002)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
BUNDLED = REPO_ROOT / "references" / "pipeline.default.yaml"
sys.path.insert(0, str(SCRIPTS))

import mb_team_status as status_mod  # noqa: E402

# AGR-097 verifier/review values per size; the mode is the only thing AGR-103 changed.
SIZES = [("trivial", "none", "none"), ("small", "none", "none"), ("standard", "plan-verifier", "none"),
         ("large", "plan-verifier", "lenses"), ("extra", "plan-verifier", "lenses")]


def _resolve(*args: str):
    return subprocess.run([sys.executable, str(SCRIPTS / "mb_team_pipeline.py"), "resolve", "--pipeline",
                           str(BUNDLED), "--json", *args], capture_output=True, text=True)


@pytest.mark.parametrize(("size", "verifier", "review"), SIZES)
def test_bundled_size_resolves_orchestrated_work(size: str, verifier: str, review: str) -> None:
    r = _resolve("--size", size)
    assert r.returncode == 0, r.stderr
    p = json.loads(r.stdout)["pipeline"]
    assert (p["mode"], p["work"], p["verifier"], p["review"]) == ("work", "orchestrated", verifier, review)


@pytest.mark.parametrize("attr", ["mode=direct", "work=light", "mode=work:light"])
def test_retired_modes_are_refused_naming_req_001(attr: str) -> None:
    r = _resolve("--size", "standard", "--attr", attr)
    assert r.returncode == 2
    assert "REQ-001" in r.stderr


def _cli(bank: Path, *args: str):
    return subprocess.run([sys.executable, str(SCRIPTS / "mb_team_tracks.py"), *args, "--mb", str(bank)],
                          capture_output=True, text=True, cwd=bank.parent)


def test_track_added_without_source_runs_on_its_own_prompt(tmp_path: Path) -> None:
    proj = tmp_path / "proj"
    bank = proj / ".memory-bank"
    bank.mkdir(parents=True)
    for name in ("status.md", "progress.md", "checklist.md", "roadmap.md"):
        (bank / name).write_text(f"# {name}\n", encoding="utf-8")
    git = ["git", "-C", str(proj), "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q", str(proj)], check=True)
    subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "init"], check=True)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(proj)).returncode == 0
    r = _cli(bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "large")
    assert r.returncode == 0, r.stderr
    track = json.loads((bank / "reports" / "demo" / "team.json").read_text(encoding="utf-8"))["tracks"][0]
    assert track["source"] == track["prompt"]
    plan = subprocess.run(["bash", str(SCRIPTS / "mb-work-plan.sh"), "--target", str(bank / track["source"]),
                           "--dry-run", "--mb", str(bank)], capture_output=True, text=True)
    assert plan.returncode == 0, plan.stderr
    assert len([ln for ln in plan.stdout.splitlines() if ln.startswith("{")]) == 1


def test_returned_standard_track_is_collected_never_verified_or_reviewed() -> None:
    track = {"id": "A", "status": "returned", "files": ["a/**"], "deps": [], "collected": False,
             "report": "reports/t/A.md", "source": "reports/t/tracks/A.prompt.md",
             "pipeline": {"mode": "work", "work": "orchestrated", "verifier": "plan-verifier", "review": "single"}}
    team = {"topic": "t", "goal": None, "max_parallel": 6, "tracks": [track], "reviews": []}
    facts = {"board": {"tracks": {}, "open_blocked": [], "open_handover": []}, "reports": {"A": "DONE"},
             "brief_unfilled": 0, "budget_stop": False,
             "review": {"enabled": False, "clean_when": {}, "max_cycles": 5},
             "goal_ok": lambda: True, "flow_ok": lambda: True}
    assert status_mod.decide(team, facts) == ["collect"]
