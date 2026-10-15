"""Brief and track prompt rendering (/mb team, REQ-TEAM-030..033).

Goldens in tests/fixtures/team/golden/ follow specs/mb-team/examples.md §3-§4,
rendered from tests/fixtures/team/team.json with the examples §1 team block.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
RENDER = SCRIPTS / "mb_team_render.py"
FIX = REPO_ROOT / "tests" / "fixtures" / "team"
BANK = "/Users/me/proj/.memory-bank"
SKILL = "/Users/me/.claude/skills/memory-bank"


def _render(*args: str, team: Path = FIX / "team.json"):
    return subprocess.run(
        [sys.executable, str(RENDER), *args, "--team", str(team), "--mb", BANK,
         "--pipeline", str(FIX / "pipeline-team.yaml"), "--skill-dir", SKILL],
        capture_output=True, text=True,
    )


def _ok(*args: str) -> str:
    r = _render(*args)
    assert r.returncode == 0, r.stderr
    return r.stdout


def _unfilled(path: Path):
    return subprocess.run([sys.executable, str(RENDER), "unfilled", str(path)], capture_output=True, text=True)


@pytest.mark.parametrize(
    ("args", "golden"),
    [(("brief",), "brief.md"), (("track", "A"), "A.prompt.md"), (("track", "C"), "C.prompt.md")],
    ids=["brief", "track-large-work-review", "track-small-work"],
)
def test_render_matches_golden(args: tuple, golden: str) -> None:
    assert _ok(*args) == (FIX / "golden" / golden).read_text(encoding="utf-8")


def _relative_paths() -> set[str]:
    team = json.loads((FIX / "team.json").read_text(encoding="utf-8"))
    paths = {team["plan"], team["brief"], "goal.md"}
    for t in team["tracks"]:
        paths |= {t["report"], t["prompt"], *t["files"]}
    return paths


@pytest.mark.parametrize("args", [("brief",), ("track", "A"), ("track", "K"), ("track", "C")])
def test_every_path_is_absolute_and_every_mb_command_has_mb(args: tuple) -> None:
    text = _ok(*args)
    for rel in _relative_paths():
        for match in re.finditer(re.escape(rel), text):
            assert text[match.start() - 1] == "/", f"relative path {rel!r} in output"
    for match in re.finditer(r"\S*scripts/mb-[\w-]+\.sh", text):
        assert match.group().lstrip("`").startswith(f"{SKILL}/scripts/"), match.group()
    for line in text.splitlines():
        if re.search(r"scripts/mb-[\w-]+\.sh \w+", line):
            assert f"--mb {BANK}" in line, line


def test_unfilled_finds_scaffold_hints_only_in_brief(tmp_path: Path) -> None:
    brief = tmp_path / "brief.md"
    brief.write_text(_ok("brief"), encoding="utf-8")
    r = _unfilled(brief)
    assert r.returncode == 1
    hints = r.stdout.splitlines()
    assert len(hints) == 6
    assert all(re.match(r"^\d+: ", h) for h in hints)
    filled = re.sub(r"<!-- fill: [^>]*-->", "- done", brief.read_text(encoding="utf-8"))
    brief.write_text(filled, encoding="utf-8")
    assert _unfilled(brief).returncode == 0
    prompt = tmp_path / "A.prompt.md"
    prompt.write_text(_ok("track", "A"), encoding="utf-8")
    r = _unfilled(prompt)
    assert (r.returncode, r.stdout) == (0, "")


def test_pipeline_in_words_for_work_and_lenses(tmp_path: Path) -> None:
    team = json.loads((FIX / "team.json").read_text(encoding="utf-8"))
    track = team["tracks"][1]
    track["source"] = "plans/2026-10-09_feature_admin.md"
    track["pipeline"].update({"verifier": "plan-verifier", "review": "lenses", "lenses": ["logic", "security"]})
    path = tmp_path / "team.json"
    path.write_text(json.dumps(team), encoding="utf-8")
    r = _render("track", "A", team=path)
    assert r.returncode == 0, r.stderr
    assert f"runs through /mb work on {BANK}/plans/2026-10-09_feature_admin.md, driven by the orchestrator" in r.stdout
    assert "You walk the stages" not in r.stdout and "You implement directly" not in r.stdout


def test_track_without_dod_is_refused(tmp_path: Path) -> None:
    team = json.loads((FIX / "team.json").read_text(encoding="utf-8"))
    del team["tracks"][2]["dod"]
    path = tmp_path / "team.json"
    path.write_text(json.dumps(team), encoding="utf-8")
    r = _render("track", "C", team=path)
    assert r.returncode == 2
    assert "C" in r.stderr and "DoD" in r.stderr


def test_unknown_track_exits_2() -> None:
    r = _render("track", "Z")
    assert r.returncode == 2
    assert "Z" in r.stderr


def test_track_prompt_is_a_one_stage_plan_for_mb_work_plan(tmp_path: Path) -> None:
    bank = tmp_path / "proj dir" / ".memory-bank"
    prompt = bank / "reports" / "sso" / "tracks" / "A.prompt.md"
    prompt.parent.mkdir(parents=True)
    r = subprocess.run([sys.executable, str(RENDER), "track", "A", "--team", str(FIX / "team.json"),
                        "--mb", str(bank), "--out", str(prompt)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    r = subprocess.run(["bash", str(SCRIPTS / "mb-work-plan.sh"), "--target", str(prompt), "--dry-run",
                        "--mb", str(bank)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    items = [json.loads(line) for line in r.stdout.splitlines() if line.startswith("{")]
    assert len(items) == 1
    assert (items[0]["role"], items[0]["dod_lines"], items[0]["kind"]) == ("backend", 3, "stage")
