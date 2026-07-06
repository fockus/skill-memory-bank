"""Contract: ephemeral runtime artifacts must be gitignored.

`.memory-bank/.session-lock` is a transient lock file written/deleted by
`/mb done`; if tracked in git, every session ends with a noisy
`git status` and pollutes the diff. Same for build artifacts (`dist/`)
and dogfood install manifests (`.installed-manifest.json`).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


def _check_ignore(rel_path: str) -> bool:
    """Return True if git treats `rel_path` as ignored (exit 0 from check-ignore)."""
    result = subprocess.run(
        ["git", "check-ignore", rel_path],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def _is_tracked(rel_path: str) -> bool:
    """Return True if file is tracked in git index."""
    result = subprocess.run(
        ["git", "ls-files", "--error-unmatch", rel_path],
        cwd=REPO_ROOT,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


@pytest.mark.parametrize(
    "rel_path",
    [
        ".memory-bank/.session-lock",
        "dist/whatever.whl",
        ".installed-manifest.json",
        ".mb-pi-manifest.json",
    ],
)
def test_runtime_artifact_is_gitignored(rel_path: str) -> None:
    """Each transient artifact must match a `.gitignore` rule."""
    assert _check_ignore(rel_path), (
        f"{rel_path!r} is not gitignored. "
        "Add an appropriate rule to .gitignore — "
        "transient/runtime artifacts must not pollute `git status`."
    )


def test_session_lock_not_tracked_in_index() -> None:
    """`.session-lock` must not be tracked even if a stale entry exists."""
    assert not _is_tracked(".memory-bank/.session-lock"), (
        "`.memory-bank/.session-lock` is tracked in the git index. "
        "Remove with: git rm --cached -f --ignore-unmatch .memory-bank/.session-lock"
    )


def test_installed_manifest_not_tracked_in_index() -> None:
    """`.installed-manifest.json` (dogfood install artifact) must not be tracked.

    Regression guard for L-7: this file used to be committed with local
    pytest paths baked into it (repo-relative install noise). It is already
    gitignored (see `test_runtime_artifact_is_gitignored` above) — this test
    additionally locks in that no stale tracked copy sneaks back into the
    git index.
    """
    assert not _is_tracked(".installed-manifest.json"), (
        "`.installed-manifest.json` is tracked in the git index. "
        "Remove with: git rm --cached -f --ignore-unmatch .installed-manifest.json"
    )
