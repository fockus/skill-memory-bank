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


# ── review fixes (b728474): attribution, unreachable baseline, deleted files ──

def _two_tracks(tmp_path: Path, gate: str | None, setup=None) -> tuple[Path, Path]:
    bank = _bank(tmp_path)
    tree = bank.parent
    if gate is not None:
        (bank / "pipeline.yaml").write_text(
            DEFAULT.replace("\nteam:\n", f"\nteam:\n  rules_gate: {json.dumps(gate)}\n"), encoding="utf-8")
    if setup:
        setup(tree)
    _git(tree, "add", "-A")
    _git(tree, "commit", "-q", "-m", "base")
    assert _cli(bank, "init", "demo", "--no-goal", "--tree", str(tree)).returncode == 0
    for tid in ("A", "B"):
        assert _cli(bank, "track", "add", tid, "--task", "t", "--dod", "d", "--files", f"{tid.lower()}/**",
                    "--size", "small").returncode == 0
        for s in ("dispatched", "returned", "done"):
            assert _cli(bank, "track", "set", tid, "--status", s).returncode == 0
    for d in ("a", "b"):
        (tree / d).mkdir(exist_ok=True)
        (tree / d / "new.txt").write_text("x\n", encoding="utf-8")
    return bank, tree


def _commit_ids(bank: Path, tree: Path, ids: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / "mb_team_ops.py"), "commit", "--tracks", ids, "-m", "x",
                           "--yes", "--mb", str(bank)], capture_output=True, text=True, cwd=tree)


def _statuses(bank: Path) -> dict:
    return {t["id"]: t["status"] for t in _team(bank)["tracks"]}


def test_gate_output_blames_only_the_tracks_whose_files_it_names(tmp_path):
    bank, tree = _two_tracks(tmp_path, "echo 'a/new.txt:1: too long'; exit 1")
    r = _commit_ids(bank, tree, "A,B")
    assert r.returncode == 1
    assert _statuses(bank) == {"A": "fixing", "B": "done"}


def test_gate_output_naming_no_selected_file_refuses_without_sending_tracks_back(tmp_path):
    bank, tree = _two_tracks(tmp_path, "echo 'zz/other.go:3: unused'; exit 1")
    r = _commit_ids(bank, tree, "A,B")
    assert r.returncode == 1 and "names no file of the selected tracks" in r.stderr
    assert _statuses(bank) == {"A": "done", "B": "done"}


def test_path_match_respects_boundaries(tmp_path):
    bank, tree = _two_tracks(tmp_path, "echo 'xa/new.txt:1: lint'; exit 1")
    r = _commit_ids(bank, tree, "A")
    assert r.returncode == 1
    assert _statuses(bank)["A"] == "done"


def test_unreachable_baseline_does_not_fake_an_srp_breach(tmp_path):
    def big(tree: Path) -> None:
        (tree / "a").mkdir()
        (tree / "a" / "big.txt").write_text("line\n" * 400, encoding="utf-8")
    bank, tree = _two_tracks(tmp_path, None, big)
    team = _team(bank)
    team["baseline"] = "deadbeef" * 5
    (bank / "reports" / "demo" / "team.json").write_text(json.dumps(team), encoding="utf-8")
    (tree / "a" / "big.txt").write_text("line\n" * 401, encoding="utf-8")
    r = _commit_ids(bank, tree, "A")
    assert r.returncode == 0, r.stderr
    assert "baseline" in r.stderr  # a warning says the threshold check ran without --base


def test_a_deleted_owned_file_is_not_a_tdd_breach(tmp_path):
    def gone(tree: Path) -> None:
        (tree / "a" / "internal").mkdir(parents=True)
        (tree / "a" / "internal" / "gone.go").write_text("package x\n", encoding="utf-8")
    bank, tree = _two_tracks(tmp_path, None, gone)
    (tree / "a" / "internal" / "gone.go").unlink()
    r = _commit_ids(bank, tree, "A")
    assert r.returncode == 0, r.stderr


def test_go_package_level_tests_do_not_block_the_commit(tmp_path):
    bank, tree = _two_tracks(tmp_path, None)
    pkg = tree / "a" / "internal" / "orders"
    pkg.mkdir(parents=True)
    (pkg / "routes.go").write_text("package orders\n\nfunc Routes() {}\n", encoding="utf-8")
    (pkg / "handler_test.go").write_text("package orders\n\nfunc TestRoutes(t *testing.T) {}\n", encoding="utf-8")
    r = _commit_ids(bank, tree, "A")
    assert r.returncode == 0, r.stderr
    assert "tdd/delta" in r.stderr  # reported for the verifier, not a send-back


def test_generated_files_are_not_checked_for_size(tmp_path):
    bank, tree = _two_tracks(tmp_path, None)
    (tree / "a" / "orders.pb.go").write_text("// Code generated by protoc-gen-go. DO NOT EDIT.\n" + "x\n" * 400,
                                             encoding="utf-8")
    r = _commit_ids(bank, tree, "A")
    assert r.returncode == 0, r.stderr


def test_a_preview_without_yes_changes_nothing_even_when_the_gate_fails(tmp_path):
    bank, tree = _two_tracks(tmp_path, "echo 'a/new.txt:1: lint'; exit 1")
    r = subprocess.run([sys.executable, str(SCRIPTS / "mb_team_ops.py"), "commit", "--tracks", "A", "-m", "x",
                        "--mb", str(bank)], capture_output=True, text=True, cwd=tree, stdin=subprocess.DEVNULL)
    assert r.returncode == 1 and "nothing was staged" in r.stderr
    assert _statuses(bank)["A"] == "done"
