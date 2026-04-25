"""I-004 — `scripts/mb-auto-commit.sh` opt-in auto-commit of .memory-bank/ after /mb done.

Contract:
- Triggers only when MB_AUTO_COMMIT=1 OR --force flag.
- Refuses when source files outside .memory-bank/ are dirty.
- Refuses during rebase/merge/cherry-pick.
- Refuses on detached HEAD.
- No-op when bank has no changes.
- Subject: `chore(mb): <last ### heading from progress.md>` truncated to 60 chars.
  Fallback: `chore(mb): session-end YYYY-MM-DD`.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-auto-commit.sh"


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True, text=True, check=check,
    )


def _init_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "test@test.local")
    _git(repo, "config", "user.name", "Test User")
    _git(repo, "config", "commit.gpgsign", "false")
    (repo / "README.md").write_text("# init\n", encoding="utf-8")
    _git(repo, "add", "README.md")
    _git(repo, "commit", "-q", "-m", "init")
    return repo


def _init_bank(repo: Path, *, with_progress: bool = True) -> Path:
    mb = repo / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n\n- ✅ initial item\n", encoding="utf-8")
    if with_progress:
        (mb / "progress.md").write_text(
            "# Progress\n\n## 2026-04-25\n\n### Auto-commit hook landed\nDid the work.\n",
            encoding="utf-8",
        )
    _git(repo, "add", ".memory-bank")
    _git(repo, "commit", "-q", "-m", "bootstrap bank")
    return mb


def _dirty_bank(mb: Path) -> None:
    (mb / "checklist.md").write_text("# Checklist\n\n- ✅ initial\n- ✅ new task\n", encoding="utf-8")


def _run(repo: Path, *args: str, env_extra: dict | None = None) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.pop("MB_AUTO_COMMIT", None)  # always start from clean state
    if env_extra:
        env.update(env_extra)
    return subprocess.run(
        ["bash", str(SCRIPT), *args, "--mb", str(repo / ".memory-bank")],
        capture_output=True, text=True, check=False, env=env, cwd=repo,
    )


def _last_commit_subject(repo: Path) -> str:
    return _git(repo, "log", "-1", "--pretty=%s").stdout.strip()


def _commits_since(repo: Path, ref: str) -> int:
    out = _git(repo, "rev-list", "--count", f"{ref}..HEAD").stdout.strip()
    return int(out) if out else 0


def test_no_op_when_disabled_by_default(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    r = _run(repo)  # MB_AUTO_COMMIT not set
    assert r.returncode == 0, r.stderr
    assert _commits_since(repo, base) == 0


def test_no_op_when_bank_clean(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0, r.stderr
    assert _commits_since(repo, base) == 0


def test_skip_when_source_outside_bank_is_dirty(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    (repo / "src.py").write_text("# new source\n", encoding="utf-8")
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0, r.stderr
    assert _commits_since(repo, base) == 0
    msg = (r.stdout + r.stderr).lower()
    assert "skip" in msg or "outside" in msg or "dirty" in msg


def test_commits_bank_changes_when_clean_outside(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0, r.stderr
    assert _commits_since(repo, base) == 1
    subj = _last_commit_subject(repo)
    assert subj.startswith("chore(mb):")


def test_subject_uses_last_progress_heading(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    _dirty_bank(mb)
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0, r.stderr
    subj = _last_commit_subject(repo)
    assert "Auto-commit hook landed" in subj


def test_subject_fallback_when_no_progress_heading(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo, with_progress=False)
    (mb / "progress.md").write_text("# Progress\n\nno headings here\n", encoding="utf-8")
    _git(repo, "add", ".memory-bank/progress.md")
    _git(repo, "commit", "-q", "-m", "add bare progress")
    _dirty_bank(mb)
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0, r.stderr
    subj = _last_commit_subject(repo)
    assert "session-end" in subj


def test_skip_during_rebase(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    # Simulate in-progress rebase by creating .git/REBASE_HEAD marker.
    (repo / ".git" / "REBASE_HEAD").write_text(base, encoding="utf-8")
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0
    assert _commits_since(repo, base) == 0
    assert "rebase" in (r.stdout + r.stderr).lower() or "merge" in (r.stdout + r.stderr).lower()


def test_skip_on_detached_head(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    _git(repo, "checkout", "-q", "--detach", base)
    r = _run(repo, env_extra={"MB_AUTO_COMMIT": "1"})
    assert r.returncode == 0
    assert _commits_since(repo, base) == 0
    assert "detach" in (r.stdout + r.stderr).lower()


def test_force_flag_overrides_unset_env(tmp_path: Path) -> None:
    repo = _init_repo(tmp_path)
    mb = _init_bank(repo)
    base = _git(repo, "rev-parse", "HEAD").stdout.strip()
    _dirty_bank(mb)
    r = _run(repo, "--force")  # no env, only flag
    assert r.returncode == 0, r.stderr
    assert _commits_since(repo, base) == 1


def test_help_flag(tmp_path: Path) -> None:
    r = subprocess.run(
        ["bash", str(SCRIPT), "--help"],
        capture_output=True, text=True, check=False,
    )
    assert r.returncode == 0
    out = r.stdout + r.stderr
    assert "MB_AUTO_COMMIT" in out
