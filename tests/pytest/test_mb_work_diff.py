"""Backlog I-094 S4 (T3) — `scripts/mb-work-diff.sh` baseline-scoped run diff.

`commands/work.md` hands the verifier/judge the bare working-tree `git diff`
today, which means a co-running `/mb work` run's edits leak into the judged
diff. This script scopes the diff to a run's own `baseline_ref` (recorded by
`mb-work-state.sh init`, I-094 S1) and, optionally, to an explicit set of
files — see plan `.memory-bank/plans/2026-07-04_fix_mb-work-parallel-runs.md`
Stage 4.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DIFF_SCRIPT = REPO_ROOT / "scripts" / "mb-work-diff.sh"
STATE_SCRIPT = REPO_ROOT / "scripts" / "mb-work-state.sh"


def _git(*args: str, repo: Path) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


def _init_repo(tmp_path: Path) -> Path:
    repo = tmp_path
    _git("init", "-q", repo=repo)
    _git("config", "user.email", "a@b.c", repo=repo)
    _git("config", "user.name", "test", repo=repo)
    return repo


def _commit_all(repo: Path, message: str) -> None:
    _git("add", "-A", repo=repo)
    _git("commit", "-q", "-m", message, repo=repo)


def _init_run(repo: Path, mb: Path, run_id: str) -> None:
    r = subprocess.run(
        ["bash", str(STATE_SCRIPT), "init", "plans/x.md", "1", "--run-id", run_id, "--mb", str(mb)],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 0, r.stderr


def _diff(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DIFF_SCRIPT), *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_diff_scopes_to_baseline_and_files(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    (repo / "b.txt").write_text("b1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    # `<baseline>..HEAD` is commit-to-commit, so the run's edits need to land
    # in history (as the run's own step commits would) to show up at all.
    (repo / "a.txt").write_text("a2\n", encoding="utf-8")
    (repo / "b.txt").write_text("b2\n", encoding="utf-8")
    _commit_all(repo, "run r1 edits")

    r = _diff("--run-id", "r1", "--files", "a.txt", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    assert "a.txt" in r.stdout
    assert "b.txt" not in r.stdout


def test_diff_excludes_foreign_run_changes(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    (repo / "c.txt").write_text("c1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    (repo / "a.txt").write_text("a2\n", encoding="utf-8")
    # Simulates another, co-running run's edit landing in shared history.
    (repo / "c.txt").write_text("c2\n", encoding="utf-8")
    _commit_all(repo, "r1 + foreign edits")

    r = _diff("--run-id", "r1", "--files", "a.txt", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    assert "a.txt" in r.stdout
    assert "c.txt" not in r.stdout


def test_diff_name_only_mode(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    (repo / "b.txt").write_text("b1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    (repo / "a.txt").write_text("a2\n", encoding="utf-8")
    (repo / "b.txt").write_text("b2\n", encoding="utf-8")
    _commit_all(repo, "run r1 edits")

    r = _diff("--run-id", "r1", "--name-only", "--files", "a.txt b.txt", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    paths = {line.strip() for line in r.stdout.splitlines() if line.strip()}
    assert paths == {"a.txt", "b.txt"}


def test_diff_empty_baseline_falls_back_scoped(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    (repo / "b.txt").write_text("b1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    # Simulate the "outside a repo at init time" edge case (I-094 S1):
    # baseline_ref recorded empty.
    state = mb / ".work-state.json"
    data = json.loads(state.read_text(encoding="utf-8"))
    data["baseline_ref"] = ""
    state.write_text(json.dumps(data), encoding="utf-8")

    (repo / "a.txt").write_text("a2\n", encoding="utf-8")
    (repo / "b.txt").write_text("b2\n", encoding="utf-8")

    r = _diff("--run-id", "r1", "--files", "a.txt", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    assert "a.txt" in r.stdout
    assert "b.txt" not in r.stdout


def test_diff_includes_uncommitted_changes(tmp_path: Path) -> None:
    # I-094 S4-fix: /mb work only commits a stage at step 5g (done); verify/
    # review (5c/5d) run against a stage that is still uncommitted. A
    # two-dot `<baseline>..HEAD` diff is commit-to-commit and would show an
    # empty diff here, so the review would silently approve nothing. The
    # single-arg form (`git diff <baseline> -- <files>`) must see uncommitted
    # working-tree edits too.
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    # Uncommitted — simulates in-progress stage work before step 5g `done`.
    (repo / "a.txt").write_text("a2\n", encoding="utf-8")

    r = _diff("--run-id", "r1", "--files", "a.txt", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    assert "a.txt" in r.stdout


def test_diff_no_files_uses_full_baseline_range(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    (repo / "a.txt").write_text("a1\n", encoding="utf-8")
    (repo / "b.txt").write_text("b1\n", encoding="utf-8")
    _commit_all(repo, "baseline")

    mb = repo / ".memory-bank"
    mb.mkdir()
    _init_run(repo, mb, "r1")

    (repo / "a.txt").write_text("a2\n", encoding="utf-8")
    (repo / "b.txt").write_text("b2\n", encoding="utf-8")
    _commit_all(repo, "run r1 edits")

    r = _diff("--run-id", "r1", "--mb", str(mb), cwd=repo)
    assert r.returncode == 0, r.stderr
    assert "a.txt" in r.stdout
    assert "b.txt" in r.stdout
