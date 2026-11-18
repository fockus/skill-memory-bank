"""Whole-spec REQ coverage (mb_spec_coverage.py) and the wave-end `spec_verify` step of /mb team.

A REQ named in a task's `Covers:` whose text the task dropped passed every task-level check; the floor is a
per-REQ table — covering tasks and test files that name the REQ — with `task-only` and `uncovered` as gaps.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import mb_team_spec as team_spec  # noqa: E402
import mb_team_status as status_mod  # noqa: E402
from test_mb_team_state import _bank, _cli, _team, facts, team, track  # noqa: E402

REQUIREMENTS = """# Requirements: access

- **REQ-001** (Ubiquitous): The system shall issue a card to a verified user.
- **REQ-002** (Unwanted): If a user loses access, then the system shall restore access only through an operator.
  Acceptance: a self-service recovery request is refused with 403.
- **REQ-003** (Event): When a card is blocked, the system shall notify the owner.
"""
TASKS = """# Tasks

<!-- mb-task:1 -->
## Task 1: Cards and recovery

**Covers:** REQ-001, REQ-002

**DoD:**
- [ ] issuing works; a recovery flag exists
"""


def _spec(root: Path) -> Path:
    spec = root / ".memory-bank" / "specs" / "access"
    spec.mkdir(parents=True)
    (spec / "requirements.md").write_text(REQUIREMENTS, encoding="utf-8")
    (spec / "tasks.md").write_text(TASKS, encoding="utf-8")
    tests = root / "internal" / "cards"
    tests.mkdir(parents=True)
    (tests / "issue_test.go").write_text(
        "// REQ-001: issue a card\nfunc TestIssue(t *testing.T) {}\n", encoding="utf-8"
    )
    (root / "internal" / "cards" / "recovery.go").write_text(
        "// REQ-002 recovery flag\n", encoding="utf-8"
    )
    return spec


def _coverage(spec: Path, tree: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "mb_spec_coverage.py"),
            str(spec),
            "--tree",
            str(tree),
            "--json",
        ],
        capture_output=True,
        text=True,
    )


def test_req_in_covers_without_a_test_is_task_only_and_fails(tmp_path):
    r = _coverage(_spec(tmp_path), tmp_path)
    assert r.returncode == 1, r.stderr
    rows = {row["req"]: row for row in json.loads(r.stdout)["reqs"]}
    assert rows["REQ-001"]["status"] == "tested" and rows["REQ-001"]["tests"] == [
        "internal/cards/issue_test.go"
    ]
    assert rows["REQ-002"]["status"] == "task-only" and rows["REQ-002"]["tasks"] == [1]
    assert "only through an operator" in rows["REQ-002"]["text"]
    assert "self-service recovery request is refused" in rows["REQ-002"]["text"]
    assert rows["REQ-003"]["status"] == "uncovered"


def test_every_req_tested_passes(tmp_path):
    spec = _spec(tmp_path)
    (tmp_path / "internal" / "cards" / "more_test.go").write_text(
        "func TestRecovery_REQ_002(t *testing.T) {}\n// REQ-003 notify\n", encoding="utf-8"
    )
    r = _coverage(spec, tmp_path)
    assert r.returncode == 0, r.stdout
    assert {row["status"] for row in json.loads(r.stdout)["reqs"]} == {"tested"}


def test_human_output_names_the_gaps(tmp_path):
    r = subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "mb_spec_coverage.py"),
            str(_spec(tmp_path)),
            "--tree",
            str(tmp_path),
        ],
        capture_output=True,
        text=True,
    )
    assert r.returncode == 1
    assert "REQ-002 task-only (task 1)" in r.stdout and "REQ-003 uncovered" in r.stdout


# ── /mb team: spec_verify at wave end ────────────────────────────────────────


def _spec_team(**over):
    t = team(track("A", "done", collected=True))
    t["tracks"][0]["source"] = "specs/access/tasks.md"
    t.update(over)
    return t


def test_team_specs_come_from_plan_and_track_sources():
    t = _spec_team(plan="specs/billing/requirements.md")
    assert team_spec.team_specs(t) == ["specs/access", "specs/billing"]
    assert team_spec.team_specs(team(track("A"))) == []


def test_next_asks_for_spec_verify_after_the_last_collect():
    assert status_mod.decide(_spec_team(), facts()) == ["spec_verify specs/access"]


def test_next_stops_on_recorded_gaps_and_succeeds_on_none():
    t = _spec_team()
    t["spec_checks"] = {
        "specs/access": {"gaps": 2, "report": "r.md", "wave": team_spec.wave_key(t)}
    }
    assert status_mod.decide(t, facts()) == ["stop_human spec-gaps:specs/access"]
    t["spec_checks"]["specs/access"]["gaps"] = 0
    assert status_mod.decide(t, facts()) == ["stop_success"]


def test_a_new_collect_makes_the_spec_check_stale():
    t = _spec_team()
    t["spec_checks"] = {
        "specs/access": {"gaps": 0, "report": "r.md", "wave": team_spec.wave_key(t)}
    }
    t["tracks"][0]["fix_cycle"] = 1
    assert status_mod.decide(t, facts()) == ["spec_verify specs/access"]


def test_spec_check_cli_records_the_result(tmp_path):
    bank = _bank(tmp_path)
    (bank / "specs" / "access").mkdir(parents=True)
    (bank / "specs" / "access" / "tasks.md").write_text("# t\n", encoding="utf-8")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "small",
                "--source", "specs/access/tasks.md").returncode == 0
    r = _cli(bank, "spec-check", "specs/access", "--gaps", "1", "--report", "reports/demo/spec.md")
    assert r.returncode == 0, r.stderr
    rec = _team(bank)["spec_checks"]["specs/access"]
    assert (rec["gaps"], rec["report"], rec["wave"]) == (1, "reports/demo/spec.md", "")
    assert _cli(bank, "spec-check", "specs/access", "--gaps", "-1").returncode == 2


def test_plan_verifier_checks_each_covered_req_against_its_own_text():
    text = (REPO_ROOT / "agents" / "plan-verifier.md").read_text(encoding="utf-8")
    assert "REQ covered by task text only, no code/test evidence" in text
    assert "mb_spec_coverage.py" in text


# ── review fixes (b728474) ───────────────────────────────────────────────────

def test_spec_check_normalizes_the_key_and_refuses_an_unknown_spec(tmp_path):
    bank = _bank(tmp_path)
    (bank / "specs" / "access").mkdir(parents=True)
    (bank / "specs" / "access" / "tasks.md").write_text("# t\n", encoding="utf-8")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(bank.parent)).returncode == 0
    assert _cli(bank, "track", "add", "A", "--task", "t", "--dod", "d", "--size", "small",
                "--source", "specs/access/tasks.md").returncode == 0
    r = _cli(bank, "spec-check", str(bank / "specs" / "access"), "--gaps", "0")
    assert r.returncode == 0, r.stderr
    assert list(_team(bank)["spec_checks"]) == ["specs/access"]
    assert _cli(bank, "spec-check", ".memory-bank/specs/access/", "--gaps", "0").returncode == 0
    assert list(_team(bank)["spec_checks"]) == ["specs/access"]
    bad = _cli(bank, "spec-check", "specs/typo", "--gaps", "0")
    assert bad.returncode == 2 and "specs/access" in bad.stderr


def test_only_bank_relative_spec_paths_count():
    t = team(track("A"))
    t["tracks"][0]["source"] = "/abs/api/specs/v1/openapi.yaml"
    assert team_spec.team_specs(t) == []


def test_requirements_without_parsable_reqs_is_bad_input(tmp_path):
    spec = tmp_path / ".memory-bank" / "specs" / "x"
    spec.mkdir(parents=True)
    (spec / "requirements.md").write_text("### REQ-001\nThe system shall work.\n", encoding="utf-8")
    assert _coverage(spec, tmp_path).returncode == 2


def test_a_blank_line_does_not_cut_the_acceptance_criteria(tmp_path):
    spec = _spec(tmp_path)
    (spec / "requirements.md").write_text(
        "- **REQ-001** (Ubiquitous): The system shall issue a card.\n\n  Acceptance: a card number is returned.\n",
        encoding="utf-8")
    rows = json.loads(_coverage(spec, tmp_path).stdout)["reqs"]
    assert "card number is returned" in rows[0]["text"]


def test_a_req_id_defined_in_two_specs_needs_the_spec_named_in_the_test(tmp_path):
    spec = _spec(tmp_path)
    other = spec.parent / "billing"
    other.mkdir()
    (other / "requirements.md").write_text("- **REQ-001** (Ubiquitous): The system shall bill.\n", encoding="utf-8")
    rows = {r["req"]: r for r in json.loads(_coverage(spec, tmp_path).stdout)["reqs"]}
    assert rows["REQ-001"]["status"] != "tested"  # issue_test.go names REQ-001 but not the access spec
    (tmp_path / "internal" / "cards" / "issue_test.go").write_text("// access:REQ-001 issue a card\n", encoding="utf-8")
    rows = {r["req"]: r for r in json.loads(_coverage(spec, tmp_path).stdout)["reqs"]}
    assert rows["REQ-001"]["status"] == "tested"


def test_collect_survives_a_failing_duplicate_scan_without_double_progress(tmp_path):
    bank = _bank(tmp_path)
    tree = bank.parent
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(tree)).returncode == 0
    for tid in ("A", "B"):
        assert _cli(bank, "track", "add", tid, "--task", "t", "--dod", "d", "--files", f"{tid.lower()}/**",
                    "--size", "small").returncode == 0
        for s in ("dispatched", "returned"):
            assert _cli(bank, "track", "set", tid, "--status", s).returncode == 0
        (bank / "reports" / "demo" / f"{tid}.md").write_text("STATUS: DONE\n", encoding="utf-8")
    t = _team(bank)
    t["baseline"] = "deadbeef" * 5
    (bank / "reports" / "demo" / "team.json").write_text(json.dumps(t), encoding="utf-8")
    collect = [sys.executable, str(SCRIPTS / "mb_team_ops.py"), "collect", "--mb", str(bank)]
    r = subprocess.run(collect, capture_output=True, text=True, cwd=tree)
    assert r.returncode == 0, r.stderr
    assert all(x["collected"] for x in _team(bank)["tracks"])
    before = (bank / "progress.md").read_text(encoding="utf-8")
    subprocess.run(collect, capture_output=True, text=True, cwd=tree)
    assert (bank / "progress.md").read_text(encoding="utf-8") == before
