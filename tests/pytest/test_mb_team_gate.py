"""Rules gate before `team commit`: the project's lint-on-new-code command plus mb-rules-check.sh.

Thresholds that live only in prose are never enforced; the gate runs both checks on each selected track's
files, sends a failing track back to `fixing` and refuses the commit with nothing staged.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
DEFAULT = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")
sys.path.insert(0, str(SCRIPTS))

from test_mb_team_state import _bank, _cli, _team  # noqa: E402


def _git(tree: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(tree), "-c", "user.email=t@t", "-c", "user.name=t", *args],
        capture_output=True,
        text=True,
        check=True,
    ).stdout


def _finished_track(tmp_path: Path, gate: str | None, body: str) -> tuple[Path, Path]:
    bank = _bank(tmp_path)
    tree = bank.parent
    if gate is not None:
        (bank / "pipeline.yaml").write_text(
            DEFAULT.replace("\nteam:\n", f"\nteam:\n  rules_gate: {json.dumps(gate)}\n"),
            encoding="utf-8",
        )
    _git(tree, "add", "-A")
    _git(tree, "commit", "-q", "-m", "bank")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(tree)).returncode == 0
    assert (
        _cli(
            bank,
            "track",
            "add",
            "A",
            "--task",
            "t",
            "--dod",
            "d",
            "--files",
            "a/**",
            "--size",
            "small",
        ).returncode
        == 0
    )
    for s in ("dispatched", "returned", "done"):
        assert _cli(bank, "track", "set", "A", "--status", s).returncode == 0
    (tree / "a").mkdir()
    (tree / "a" / "mod.txt").write_text(body, encoding="utf-8")
    return bank, tree


def _commit(bank: Path, tree: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "mb_team_ops.py"),
            "commit",
            "--tracks",
            "A",
            "-m",
            "feat: a",
            "--yes",
            "--mb",
            str(bank),
        ],
        capture_output=True,
        text=True,
        cwd=tree,
    )


def test_failing_rules_gate_returns_the_track_to_fixing_and_commits_nothing(tmp_path):
    bank, tree = _finished_track(
        tmp_path, "echo 'a/mod.txt:1: funlen: too long' >&2; exit 3", "x\n"
    )
    head = _git(tree, "rev-parse", "HEAD")
    r = _commit(bank, tree)
    assert r.returncode == 1
    assert "rules gate" in r.stderr and "funlen" in r.stderr
    assert _team(bank)["tracks"][0]["status"] == "fixing"
    assert _git(tree, "rev-parse", "HEAD") == head
    assert _git(tree, "diff", "--cached", "--name-only") == ""


def test_file_pushed_over_the_srp_threshold_refuses_the_commit(tmp_path):
    bank, tree = _finished_track(tmp_path, None, "line\n" * 320)
    r = _commit(bank, tree)
    assert r.returncode == 1
    assert "solid/srp" in r.stderr and "a/mod.txt" in r.stderr
    assert _team(bank)["tracks"][0]["status"] == "fixing"


def test_passing_gate_commits(tmp_path):
    bank, tree = _finished_track(tmp_path, "true", "small file\n")
    r = _commit(bank, tree)
    assert r.returncode == 0, r.stderr
    assert "a/mod.txt" in _git(tree, "show", "--name-only", "--format=", "HEAD")
    assert _team(bank)["tracks"][0]["status"] == "done"


def test_rules_gate_must_be_a_string(tmp_path):
    path = tmp_path / "pipeline.yaml"
    path.write_text(
        DEFAULT.replace("\nteam:\n", "\nteam:\n  rules_gate: [make, lint]\n"), encoding="utf-8"
    )
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "mb_team_config.py"), "show", "--pipeline", str(path)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 2 and "team.rules_gate" in r.stderr
    path.write_text(
        DEFAULT.replace("\nteam:\n", "\nteam:\n  rules_gate: make lint-new\n"), encoding="utf-8"
    )
    r = subprocess.run(
        [sys.executable, str(SCRIPTS / "mb_team_config.py"), "show", "--pipeline", str(path)],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout)["rules_gate"] == "make lint-new"
