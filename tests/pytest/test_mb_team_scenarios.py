"""Integration scenarios of specs/team-completion (REQ-001..013) through the real mb-team.sh CLI."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
PIPELINE = "team:\n  checkpoint:\n    dir: ../backups-out\n    max_untracked_mb: 1\n"


class Team:
    """A temp git project holding a bank; `run` calls mb-team.sh from the project root."""

    def __init__(self, tmp: Path, scripts: Path = SCRIPTS) -> None:
        self.proj = tmp / "proj"
        self.bank = self.proj / ".memory-bank"
        self.script = scripts / "mb-team.sh"
        self.env = {**os.environ, "MB_LOCK_DIR": str(tmp / "locks")}
        self.bank.mkdir(parents=True)
        for name in ("status", "checklist", "roadmap", "progress"):
            (self.bank / f"{name}.md").write_text(f"# {name}\n", encoding="utf-8")
        (self.bank / "pipeline.yaml").write_text(PIPELINE, encoding="utf-8")
        (self.proj / ".gitignore").write_text(".memory-bank/\nbackups-out/\n", encoding="utf-8")
        (self.proj / "a").mkdir()
        (self.proj / "a" / "x.txt").write_text("base\n", encoding="utf-8")
        self.git("init", "-q", ".")
        self.git("config", "user.email", "t@t")
        self.git("config", "user.name", "t")
        self.git("add", "-A")
        self.git("commit", "-qm", "init")

    def git(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(["git", *args], cwd=self.proj, capture_output=True, text=True, check=False)

    def run(self, *args: str, env: dict | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", str(self.script), "--mb", str(self.bank), *args], cwd=self.proj,
                              capture_output=True, text=True, env=env or self.env, check=False)

    def ok(self, *args: str) -> str:
        r = self.run(*args)
        assert r.returncode == 0, f"{args}: {r.stderr}"
        return r.stdout

    def init(self, *track_specs: tuple[str, ...]) -> None:
        self.ok("init", "demo", "--no-goal", "--tree", str(self.proj))
        for spec in track_specs:
            self.ok("track", "add", *spec)
        brief = self.bank / "reports" / "demo" / "brief.md"
        brief.write_text(re.sub(r"<!--\s*fill:.*?-->", "- filled", brief.read_text(encoding="utf-8")),
                         encoding="utf-8")

    def team_json(self) -> dict:
        return json.loads((self.bank / "reports" / "demo" / "team.json").read_text(encoding="utf-8"))

    def returned(self, tid: str, report: str) -> None:
        (self.bank / "reports" / "demo" / f"{tid}.md").write_text(report, encoding="utf-8")
        self.ok("track", "set", tid, "--status", "dispatched")
        self.ok("track", "set", tid, "--status", "returned")


def _track(tid: str, size: str = "small", *extra: str) -> tuple[str, ...]:
    return (tid, "--task", f"work {tid}", "--dod", f"{tid} done", "--size", size, *extra)


def _skill_copy(tmp: Path) -> Path:
    """A private copy of scripts/, references/ and templates/, so a test can swap one script for a stub."""
    shutil.copytree(REPO_ROOT / "references", tmp / "skill" / "references")
    shutil.copytree(REPO_ROOT / "agents", tmp / "skill" / "agents")
    shutil.copytree(REPO_ROOT / "templates", tmp / "skill" / "templates")
    shutil.copytree(SCRIPTS, tmp / "skill" / "scripts")
    return tmp / "skill" / "scripts"


@pytest.fixture
def team(tmp_path: Path) -> Team:
    return Team(tmp_path)


def test_REQ_001__track_runs_through_the_work_loop(team: Team) -> None:
    team.init(_track("A", "small"), _track("B", "standard"))
    plan = json.loads(team.ok("plan", "--json"))
    assert {t["id"]: t["pipeline"]["mode"] for t in plan["tracks"]} == {"A": "work", "B": "work"}
    assert {t["id"]: t["source"] for t in team.team_json()["tracks"]} == {
        tid: f"reports/demo/tracks/{tid}.prompt.md" for tid in ("A", "B")}
    team.returned("B", "notes\nSTATUS: DONE\n")
    actions = team.ok("next").splitlines()
    assert "collect" in actions
    assert not [a for a in actions if a.split()[0] in ("verify", "review")]


def test_REQ_003__cancelled_dependency_stops_the_team(team: Team) -> None:
    team.init(_track("A"), _track("B", "small", "--deps", "A"), _track("C"))
    team.ok("track", "set", "A", "--status", "cancelled")
    assert team.ok("next").splitlines() == ["stop_human blocked:dep-cancelled:A"]
    row = next(ln for ln in team.ok("status").splitlines() if ln.startswith("B"))
    assert "blocked:dep-cancelled:A" in row


def test_REQ_004__red_flow_after_the_last_collect_stops_the_team(team: Team, tmp_path: Path) -> None:
    shim = _skill_copy(tmp_path)
    calls = tmp_path / "flow-args"
    (shim / "mb-flow-verify.sh").write_text(
        f'#!/bin/sh\necho "$@" >"{calls}"\n'
        'echo \'{"checks":[{"name":"tests","status":"fail"}]}\'\nexit 1\n', encoding="utf-8")
    t = Team(tmp_path / "w", shim)
    t.init(_track("A"))
    t.returned("A", "## Files\n- a\n\nSTATUS: BLOCKED is not what happened\nnotes\nSTATUS: DONE\n")
    t.ok("collect")
    assert t.ok("next").splitlines() == ["stop_human flow-red:tests"]
    assert "--skip acceptance" in calls.read_text(encoding="utf-8")


def test_REQ_007__failed_commit_leaves_the_index_as_it_was(team: Team) -> None:
    team.init(_track("A", "small", "--files", "src/**/*.py"))
    (team.proj / "src").mkdir()
    (team.proj / "src" / "new.py").write_text("x = 1\n", encoding="utf-8")
    (team.proj / "src" / "old.py").write_text("y = 1\n", encoding="utf-8")
    team.git("add", "src/old.py")
    team.git("commit", "-qm", "old")
    (team.proj / "src" / "old.py").write_text("y = 2\n", encoding="utf-8")
    (team.proj / "stray.txt").write_text("s\n", encoding="utf-8")
    team.git("add", "stray.txt")
    team.returned("A", "STATUS: DONE\n")
    team.ok("collect")
    hook = team.proj / ".git" / "hooks" / "pre-commit"
    hook.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    hook.chmod(0o755)
    before = team.git("diff", "--cached", "--name-only").stdout
    r = team.run("commit", "--tracks", "A", "-m", "feat: a", "--yes")
    assert r.returncode == 1, r.stderr
    assert team.git("diff", "--cached", "--name-only").stdout == before
    sys.path.insert(0, str(SCRIPTS))
    from mb_team_review_core import Ctx
    ctx = Ctx.__new__(Ctx)
    ctx.team = {"tree": str(team.proj), "mirror": "", "tracks": team.team_json()["tracks"]}
    assert ctx.owner({"file": "src/sub/y.py"}) == "A"


def test_REQ_009__broken_inputs_are_refused_cleanly(team: Team, tmp_path: Path) -> None:
    shim = _skill_copy(tmp_path)
    (shim / "mb-team-review.sh").write_text("#!/bin/sh\necho not json\nexit 0\n", encoding="utf-8")
    t = Team(tmp_path / "w", shim)
    t.init(_track("A"))
    gate = t.run("review", "gate", "--cycle", "1")
    assert gate.returncode == 2 and "Traceback" not in gate.stderr + gate.stdout
    assert t.team_json()["reviews"] == []

    date = tmp_path / "bin" / "date"
    date.parent.mkdir()
    date.write_text("#!/bin/sh\necho 2026-01-01-000000\n", encoding="utf-8")
    date.chmod(0o755)
    env = {**t.env, "PATH": f"{date.parent}:{os.environ['PATH']}"}
    out = t.proj / "backups-out"
    first = subprocess.run(["bash", str(t.script), "--mb", str(t.bank), "checkpoint", "same"], cwd=t.proj,
                           capture_output=True, text=True, env=env, check=False)
    assert first.returncode == 0, first.stderr
    snap = {p.name: p.read_bytes() for p in out.iterdir()}
    again = subprocess.run(["bash", str(t.script), "--mb", str(t.bank), "checkpoint", "same"], cwd=t.proj,
                           capture_output=True, text=True, env=env, check=False)
    assert again.returncode == 1
    assert {p.name: p.read_bytes() for p in out.iterdir()} == snap
    assert t.run("checkpoint", "../x").returncode == 2

    probe = "import sys; sys.path.insert(0, sys.argv[1]); import mb_team_config as c; print(c.host_lock_root())"
    roots = {subprocess.run([sys.executable, "-c", probe, str(SCRIPTS)], capture_output=True, text=True,
                            env={**{k: v for k, v in os.environ.items() if k != "MB_LOCK_DIR"}, "TMPDIR": d}
                            ).stdout for d in ("/var/tmp/one", "/var/tmp/two")}
    assert len(roots) == 1


def test_REQ_013__track_dispatch_is_described_for_four_hosts() -> None:
    text = (REPO_ROOT / "commands" / "team.md").read_text(encoding="utf-8")
    hosts = text.split("## 9. Hosts", 1)[1].split("\n## ", 1)[0]
    for host in ("Claude Code", "Codex", "OpenCode", "Pi"):
        assert host in hosts
    assert "SKILL.md" in hosts and "Invocation" in hosts
    assert "at the track boundary" in hosts
