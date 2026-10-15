"""`team next` stops (team-completion REQ-003..005): cancelled dependency, red goal, red flow, last STATUS line."""

from __future__ import annotations

import stat
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import mb_team_status as status_mod  # noqa: E402
from test_mb_team_state import facts, team, track  # noqa: E402


def _done_team():
    return team(track("A", "done", collected=True))


def test_next_cancelled_dependency_stops_for_the_human_without_dispatching_others():
    t = team(track("A", "cancelled"), track("B", deps=["A"]), track("C"))
    assert status_mod.decide(t, facts()) == ["stop_human blocked:dep-cancelled:A"]


def test_next_cancelled_dependency_is_listed_once_per_dependency():
    t = team(track("A", "cancelled"), track("B", deps=["A"]), track("C", deps=["A"]))
    assert status_mod.decide(t, facts()) == ["stop_human blocked:dep-cancelled:A"]


def test_next_stop_is_returned_alone_even_with_collectable_tracks():
    t = team(track("A", "blocked"), track("B", "done"))
    assert status_mod.decide(t, facts()) == ["stop_human blocked:A"]


def test_next_goal_red_after_all_collected_stops_without_running_flow():
    def boom():
        raise AssertionError("flow must not run when the goal is red")
    assert status_mod.decide(_done_team(), facts(goal_ok=lambda: False, flow_red=boom)) == ["stop_human goal-red"]


def test_next_flow_red_names_the_failing_checks():
    assert status_mod.decide(_done_team(), facts(flow_red=lambda: ["tests", "lint"])) == [
        "stop_human flow-red:tests,lint"]


def test_next_all_green_is_stop_success():
    assert status_mod.decide(_done_team(), facts()) == ["stop_success"]


@pytest.mark.parametrize("body,want", [
    ("STATUS: BLOCKED\nnotes\nSTATUS: DONE\n", "DONE"),
    ("STATUS: DONE\nnotes\n**STATUS:** BLOCKED\n", "BLOCKED"),
    ("intro\nSTATUS: DONE_WITH_CONCERNS\n", "DONE_WITH_CONCERNS"),
    ("no status here\n", None),
])
def test_report_status_reads_the_last_status_line(tmp_path, body, want):
    (tmp_path / "r.md").write_text(body, encoding="utf-8")
    assert status_mod.report_status(str(tmp_path), {"report": "r.md"}) == want


@pytest.fixture
def stub_flow(tmp_path, monkeypatch):
    def make(stdout: str, code: int):
        d = tmp_path / "scripts"
        d.mkdir(exist_ok=True)
        f = d / "mb-flow-verify.sh"
        f.write_text(f"#!/bin/bash\ncat <<'EOF'\n{stdout}\nEOF\nexit {code}\n")
        f.chmod(f.stat().st_mode | stat.S_IEXEC)
        monkeypatch.setattr(status_mod, "script", lambda name: str(d / name))
        return str(tmp_path)
    return make


def test_flow_red_names_fail_and_broke_checks_from_the_summary(stub_flow):
    summary = ('{"checks":[{"name":"tests","status":"fail"},{"name":"lint","status":"skip"},'
               '{"name":"qa","status":"broke"}],"verdict":"fail"}')
    tree = stub_flow("[mb-flow-verify] FAIL\n" + summary, 1)
    assert status_mod.flow_red(tree, tree) == ["tests", "qa"]


def test_flow_red_is_empty_when_flow_passes(stub_flow):
    tree = stub_flow("{}", 0)
    assert status_mod.flow_red(tree, tree) == []


def test_flow_red_reports_broke_when_the_summary_is_unparsable(stub_flow):
    tree = stub_flow("garbage", 2)
    assert status_mod.flow_red(tree, tree) == ["broke"]


def test_status_shows_dependents_of_a_cancelled_track_as_blocked():
    tracks = [track("A", "cancelled"), track("B", deps=["A"]), track("C")]
    assert [status_mod.dep_status(t, tracks) for t in tracks] == ["cancelled", "blocked:dep-cancelled:A", "planned"]
