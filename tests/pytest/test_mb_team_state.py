"""/mb team state and the `next` brain (design §3 C1, §9; REQ-TEAM-003, 022..025, 033, 081).

`decide(team, facts)` is the pure decision over team.json plus facts gathered from
the board, the reports, the brief, the budget, the goal and mb-flow-verify; the
CLI tests drive the real writer (lock + atomic replace) through processes.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import mb_team_state as state  # noqa: E402
import mb_team_status as status_mod  # noqa: E402

CLEAN = {"blocker": 0, "major": 0, "medium": 0}


def track(tid, status="planned", files=None, deps=None, verifier="none", review="none",
          mode="work", work="orchestrated", collected=False):
    return {"id": tid, "status": status, "files": files or [f"{tid.lower()}/**"], "deps": deps or [],
            "collected": collected, "report": f"reports/t/{tid}.md", "source": None,
            "pipeline": {"mode": mode, "work": work, "verifier": verifier, "review": review}}


def team(*tracks, max_parallel=6, reviews=None, goal="G-001"):
    return {"topic": "t", "goal": goal, "max_parallel": max_parallel, "tracks": list(tracks),
            "reviews": reviews or []}


def facts(**over):
    base = {"board": {"tracks": {}, "open_blocked": [], "open_handover": []}, "reports": {},
            "brief_unfilled": 0, "budget_stop": False,
            "review": {"enabled": False, "clean_when": CLEAN, "max_cycles": 5},
            "goal_ok": lambda: True, "flow_red": lambda: []}
    base.update(over)
    return base


def test_next_dispatches_only_tracks_whose_deps_are_finished():
    t = team(track("K"), track("A", deps=["K"]), track("C"))
    assert status_mod.decide(t, facts()) == ["dispatch K", "dispatch C"]
    t = team(track("K", "done", collected=True), track("A", deps=["K"]))
    assert status_mod.decide(t, facts()) == ["dispatch A"]


def test_next_glob_overlap_with_running_track_is_not_ready():
    t = team(track("A", "dispatched", files=["src/auth/**"]), track("B", files=["src/auth/login.py"]),
             track("C", files=["src/authz/**"]))
    assert status_mod.decide(t, facts()) == ["dispatch C"]
    t = team(track("A", files=["lib/**"]), track("B", files=["lib/x/**"]))
    assert status_mod.decide(t, facts()) == ["dispatch A"]


def test_next_respects_max_parallel():
    t = team(track("A", "dispatched"), track("B"), track("C"), max_parallel=2)
    assert status_mod.decide(t, facts()) == ["dispatch B"]
    t = team(track("A", "dispatched"), track("B", "reviewing"), track("C"), max_parallel=2)
    assert status_mod.decide(t, facts()) == ["wait"]


def test_next_blocked_track_gives_stop_human():
    t = team(track("A", "blocked"), track("B"))
    assert status_mod.decide(t, facts()) == ["stop_human blocked:A"]
    board = {"tracks": {}, "open_blocked": [{"track": "B", "date": "2026-10-10", "title": "disk"}],
             "open_handover": []}
    t = team(track("A"), track("B", "dispatched"))
    assert status_mod.decide(t, facts(board=board))[0] == "stop_human blocked:B"
    t = team(track("A", "returned"))
    assert status_mod.decide(t, facts(reports={"A": "NEEDS_CONTEXT"})) == ["stop_human needs_context:A"]


def test_next_unfilled_brief_gives_stop_human_and_no_dispatch():
    t = team(track("A"), track("B"))
    assert status_mod.decide(t, facts(brief_unfilled=3)) == ["stop_human brief-unfilled"]


def test_next_budget_stop_blocks_new_dispatch():
    t = team(track("A"), track("B", "done"))
    assert status_mod.decide(t, facts(budget_stop=True)) == ["stop_human budget"]


def test_next_collects_returned_tracks_with_a_done_report_and_never_verifies():
    t = team(track("A", "returned", verifier="plan-verifier"), track("B", "returned", review="single"),
             track("C", "returned"), track("D", "fixing"))
    done = {"A": "DONE", "B": "DONE_WITH_CONCERNS", "C": "DONE"}
    assert status_mod.decide(t, facts(reports=done)) == ["collect"]


def test_next_waits_for_a_track_already_fixing_instead_of_a_second_dispatch():
    t = team(track("A", "fixing", verifier="plan-verifier"), track("B", "dispatched"))
    assert status_mod.decide(t, facts()) == ["wait"]


def test_next_stops_for_the_human_when_a_track_used_up_its_fix_cycles():
    running = track("A", "fixing")
    running["fix_cycle"] = 6
    assert status_mod.decide(team(running), facts()) == ["stop_human fix-cycles:A"]
    assert status_mod.decide(team(track("C", "returned")), facts()) == ["stop_human no-report:C"]


def test_next_team_review_when_enabled_and_all_finished():
    review = {"enabled": True, "clean_when": CLEAN, "max_cycles": 2}
    t = team(track("A", "done", collected=True))
    assert status_mod.decide(t, facts(review=review)) == ["team_review 1"]
    dirty = [{"cycle": 1, "counts": {"blocker": 0, "major": 1, "medium": 0, "minor": 3}}]
    assert status_mod.decide(team(track("A", "done", collected=True), reviews=dirty),
                             facts(review=review)) == ["team_review 2"]
    assert status_mod.decide(team(track("A", "done", collected=True), reviews=dirty * 2),
                             facts(review=review)) == ["stop_human review-cycles"]


def test_next_follows_the_recorded_team_review_gate():
    review = {"enabled": True, "clean_when": CLEAN, "max_cycles": 5}
    gate = {"cycle": 1, "verdict": "fixes_needed", "actions": ["fix A"], "at": "2026-10-10T10:00:00Z"}
    a = track("A", "done", collected=True)
    a["returned_at"] = "2026-10-10T09:00:00Z"
    t = team(a, track("B", "done", collected=True), reviews=[gate])
    assert status_mod.decide(t, facts(review=review)) == ["fix A"]
    a["fix_cycle"] = 1
    assert status_mod.decide(t, facts(review=review)) == ["team_review 2"]
    gate["actions"] = ["stop_human review-unowned"]
    assert status_mod.decide(t, facts(review=review)) == ["stop_human review-unowned"]
    t["reviews"].append({"cycle": 2, "verdict": "clean", "actions": [], "at": "2026-10-10T12:00:00Z"})
    assert status_mod.decide(t, facts(review=review)) == ["stop_success"]


def test_fix_is_pending_until_the_track_goes_through_fixing_even_within_the_gate_second():
    # Timestamps have one-second resolution: a return in the gate's second must not hide the fix,
    # and a fixed return in the same second must not re-open it.
    review = {"enabled": True, "clean_when": CLEAN, "max_cycles": 5}
    gate = {"cycle": 1, "verdict": "fixes_needed", "actions": ["fix A"], "at": "2026-10-10T10:00:00Z",
            "fix_cycles": {"A": 0, "B": 0}}
    a = track("A", "done", collected=True)
    a.update(returned_at="2026-10-10T10:00:00Z", fix_cycle=0)
    t = team(a, track("B", "done", collected=True), reviews=[gate])
    assert status_mod.decide(t, facts(review=review)) == ["fix A"]
    a["fix_cycle"] = 1
    assert status_mod.decide(t, facts(review=review)) == ["team_review 2"]


def _all_good():
    review = {"enabled": True, "clean_when": CLEAN, "max_cycles": 5}
    clean = [{"cycle": 1, "counts": {"blocker": 0, "major": 0, "medium": 0, "minor": 4}}]
    return team(track("A", "done", collected=True), track("B", "cancelled"), reviews=clean), facts(review=review)


def test_next_stop_success_when_all_four_conditions_hold():
    t, f = _all_good()
    assert status_mod.decide(t, f) == ["stop_success"]


@pytest.mark.parametrize("breaks", ["uncollected", "review", "goal", "flow"])
def test_next_no_stop_success_when_one_condition_fails(breaks):
    t, f = _all_good()
    if breaks == "uncollected":
        t["tracks"][0]["collected"] = False
    elif breaks == "review":
        t["reviews"][0]["counts"]["medium"] = 1
    elif breaks == "goal":
        f["goal_ok"] = lambda: False
    else:
        f["flow_red"] = lambda: ["tests"]
    got = status_mod.decide(t, f)
    assert "stop_success" not in got and "wait" not in got


def test_next_no_tracks_is_stop_human():
    assert status_mod.decide(team(), facts()) == ["stop_human no-tracks"]


@pytest.mark.parametrize("glob,path,hit", [
    ("bundle/**", "bundle/a/b.json", True), ("bundle/**", "bundle", False), ("src/*.py", "src/a.py", True),
    ("src/*.py", "src/x/a.py", False), ("docs/readme.md", "docs/readme.md", True), ("a/**/z.go", "a/b/c/z.go", True),
])
def test_glob_match_is_path_aware(glob, path, hit):
    assert state.glob_match(glob, path) is hit


@pytest.mark.parametrize("old,new,ok", [
    ("planned", "dispatched", True), ("dispatched", "returned", True), ("returned", "verifying", True),
    ("verifying", "reviewing", True), ("reviewing", "fixing", True), ("fixing", "returned", True),
    ("returned", "done", True), ("planned", "done", False), ("done", "dispatched", False), ("done", "fixing", True),
    ("reviewing", "blocked", True), ("blocked", "dispatched", True), ("cancelled", "planned", False),
])
def test_status_machine(old, new, ok):
    assert state.can_move(old, new) is ok


# ── writer: lock + atomic replace, through processes ─────────────────────────

def _bank(tmp_path: Path) -> Path:
    proj = tmp_path / "proj with space"
    bank = proj / ".memory-bank"
    bank.mkdir(parents=True)
    for name in ("status.md", "progress.md", "checklist.md", "roadmap.md"):
        (bank / name).write_text(f"# {name}\n", encoding="utf-8")
    git = ["git", "-C", str(proj), "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q", str(proj)], check=True)
    subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "init"], check=True)
    return bank


def _cli(bank: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / "mb_team_tracks.py"), *args, "--mb", str(bank)],
                          capture_output=True, text=True, cwd=bank.parent)


def _team(bank: Path) -> dict:
    return json.loads((bank / "reports" / "demo" / "team.json").read_text(encoding="utf-8"))


def test_concurrent_track_set_never_loses_an_update(tmp_path):
    bank = _bank(tmp_path)
    tree = str(bank.parent)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", tree).returncode == 0
    for tid in ("A", "B"):
        r = _cli(bank, "track", "add", tid, "--task", f"task {tid}", "--dod", "a test proves it",
                 "--files", f"{tid.lower()}/**", "--size", "small")
        assert r.returncode == 0, r.stderr
        assert _cli(bank, "track", "set", tid, "--status", "dispatched").returncode == 0
        assert _cli(bank, "track", "set", tid, "--status", "returned").returncode == 0
    rounds = 8
    loop = ("import subprocess,sys\n"
            "for _ in range(%d):\n"
            "  for s in ('fixing','returned'):\n"
            "    subprocess.run([sys.executable,%r,'track','set',sys.argv[1],'--status',s,'--mb',%r],check=True)\n"
            % (rounds, str(SCRIPTS / "mb_team_tracks.py"), str(bank)))
    procs = [subprocess.Popen([sys.executable, "-c", loop, tid]) for tid in ("A", "B")]
    assert [p.wait(timeout=120) for p in procs] == [0, 0]
    tracks = {t["id"]: t for t in _team(bank)["tracks"]}
    assert tracks["A"]["fix_cycle"] == rounds and tracks["B"]["fix_cycle"] == rounds
    assert not list((bank / "reports" / "demo").glob("*.tmp*"))


def test_track_add_keeps_title_dod_and_resolved_pipeline(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    r = _cli(bank, "track", "add", "A", "--task", "do it", "--title", "short title", "--dod", "one",
             "--dod", "two", "--role", "backend", "--size", "standard", "--review", "single",
             "--model", "executor=opus", "--layer", "prompt")
    assert r.returncode == 0, r.stderr
    a = _team(bank)["tracks"][0]
    assert (a["title"], a["dod"], a["agent"], a["status"]) == ("short title", ["one", "two"], "mb-backend", "planned")
    assert a["pipeline"]["review"] == "single" and a["pipeline"]["models"]["executor"] == "opus"
    assert a["provenance"]["review"] == "prompt" and a["provenance"]["mode"] == "preset:standard"
    prompt = bank / a["prompt"]
    assert "- [ ] two" in prompt.read_text(encoding="utf-8")


def test_track_add_refuses_bad_input(tmp_path):
    bank = _bank(tmp_path)
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "add", "1bad", "--task", "x", "--dod", "y").returncode == 2
    assert _cli(bank, "track", "add", "A", "--task", "x").returncode == 2  # no DoD
    bad = _cli(bank, "track", "add", "A", "--task", "x", "--dod", "y", "--review", "maybe")
    assert bad.returncode == 2 and "review" in bad.stderr
    retired = _cli(bank, "track", "add", "A", "--task", "x", "--dod", "y", "--mode", "direct")
    assert retired.returncode == 2 and "REQ-001" in retired.stderr
    assert _team(bank)["tracks"] == []
    assert _cli(bank, "track", "add", "A", "--task", "x", "--dod", "y").returncode == 0
    assert _cli(bank, "track", "add", "A", "--task", "x", "--dod", "y").returncode == 2  # duplicate
    assert _cli(bank, "track", "set", "A", "--status", "done").returncode == 2  # planned -> done


def test_init_refuses_without_valid_goal_and_twice(tmp_path):
    bank = _bank(tmp_path)
    r = _cli(bank, "init", "demo", "--tree", str(bank.parent))
    assert r.returncode == 2 and "goal" in r.stderr
    assert not (bank / "reports" / "demo" / "team.json").exists()
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 2

