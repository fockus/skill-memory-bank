"""The second way to manufacture a false green: a run that spans a source edit.

Truncation already has a guard — `ok < plan` is detectable after the fact. This
one is not: the run finishes, the plan count matches, every test says `ok`, and
yet different tests ran against different versions of the code. Nothing in the
log records that, because nothing in the log is wrong.

It happened for real: a bats suite was running in the background while a script
under test was edited to trim comments. The run completed 384/384 and would have
been reported green.

The rule this file pins is deliberately blunt, and the third test is the reason:
ANY watched file modified at or after the run start invalidates the run, even if
the edit lands after the last test. From an mtime alone you cannot tell which
tests a change affected, and a guard that guesses is worse than one that refuses.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools" / "check_run_complete.py"

# exit codes: 0 clean · 1 completeness failure · 3 the run spans an edit
EXIT_OK = 0
EXIT_INCOMPLETE = 1
EXIT_STALE = 3


def run_tool(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(TOOL), *args],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
    )


@pytest.fixture()
def complete_log(tmp_path: Path) -> Path:
    """A log that is provably complete, so only staleness can fail it."""
    log = tmp_path / "run.log"
    log.write_text("1..2\nok 1 first\nok 2 second\n")
    return log


@pytest.fixture()
def watched(tmp_path: Path) -> Path:
    src = tmp_path / "script.sh"
    src.write_text("#!/usr/bin/env bash\necho hi\n")
    return src


def _set_mtime(path: Path, when: float) -> None:
    os.utime(path, (when, when))


def test_clean_run_with_no_edits_passes(complete_log: Path, watched: Path) -> None:
    """Baseline: the watched file predates the run, so nothing is stale."""
    start = time.time()
    _set_mtime(watched, start - 60)
    r = run_tool(str(complete_log), "--since", str(start), "--watch", str(watched))
    assert r.returncode == EXIT_OK, r.stdout + r.stderr
    assert "COMPLETE" in r.stdout


def test_file_edited_during_the_run_fails(complete_log: Path, watched: Path) -> None:
    start = time.time() - 100
    _set_mtime(watched, start + 50)  # edited mid-run
    r = run_tool(str(complete_log), "--since", str(start), "--watch", str(watched))
    assert r.returncode == EXIT_STALE, r.stdout + r.stderr
    assert "spans an edit" in r.stdout
    assert watched.name in r.stdout


def test_edit_after_the_last_test_still_fails(complete_log: Path, watched: Path) -> None:
    """The case that forces the blunt rule.

    An edit landing after the final test looks harmless, but mtime carries no
    information about WHICH tests it preceded — and a log written after the edit
    is indistinguishable from one written before it. Refuse rather than guess.
    """
    start = time.time() - 100
    _set_mtime(watched, time.time())  # newest possible: after everything
    r = run_tool(str(complete_log), "--since", str(start), "--watch", str(watched))
    assert r.returncode == EXIT_STALE, r.stdout + r.stderr
    assert "spans an edit" in r.stdout


def test_staleness_message_and_code_differ_from_truncation(tmp_path: Path, watched: Path) -> None:
    """A distinct failure must not borrow truncation's voice or its exit code."""
    truncated = tmp_path / "trunc.log"
    truncated.write_text("1..5\nok 1 a\nok 2 b\n")
    _set_mtime(watched, time.time() - 999)

    trunc = run_tool(str(truncated), "--since", str(time.time()), "--watch", str(watched))
    assert trunc.returncode == EXIT_INCOMPLETE
    assert "TRUNCATED" in trunc.stdout
    assert "spans an edit" not in trunc.stdout

    complete = tmp_path / "ok.log"
    complete.write_text("1..1\nok 1 a\n")
    _set_mtime(watched, time.time())
    stale = run_tool(str(complete), "--since", str(time.time() - 50), "--watch", str(watched))
    assert stale.returncode == EXIT_STALE
    assert "spans an edit" in stale.stdout
    assert "TRUNCATED" not in stale.stdout


def test_both_failures_reported_and_completeness_wins_the_exit_code(
    tmp_path: Path, watched: Path
) -> None:
    """Neither failure may hide the other; a green exit stays reserved for 0."""
    truncated = tmp_path / "both.log"
    truncated.write_text("1..5\nok 1 a\n")
    _set_mtime(watched, time.time())
    r = run_tool(str(truncated), "--since", str(time.time() - 50), "--watch", str(watched))
    assert r.returncode == EXIT_INCOMPLETE
    assert "TRUNCATED" in r.stdout
    assert "spans an edit" in r.stdout


def test_no_watch_paths_says_so_instead_of_implying_a_check(complete_log: Path) -> None:
    """Honesty rule: silence must not read as 'the staleness check passed'."""
    r = run_tool(str(complete_log))
    assert r.returncode == EXIT_OK
    assert "NOT CHECKED" in r.stdout
    assert "--watch" in r.stdout


def test_watch_without_since_is_a_usage_error(complete_log: Path, watched: Path) -> None:
    """--watch with no run start cannot check anything; refuse rather than pass."""
    r = run_tool(str(complete_log), "--watch", str(watched))
    assert r.returncode != EXIT_OK
    assert "--since" in (r.stdout + r.stderr)


def test_since_accepts_a_reference_FILE_not_only_an_epoch(
    tmp_path: Path, complete_log: Path, watched: Path
) -> None:
    """`touch stamp` before the run is the ergonomic form; make it work."""
    stamp = tmp_path / "run.stamp"
    stamp.write_text("")
    _set_mtime(stamp, time.time() - 100)
    _set_mtime(watched, time.time() - 50)  # edited after the stamp = mid-run
    r = run_tool(str(complete_log), "--since", str(stamp), "--watch", str(watched))
    assert r.returncode == EXIT_STALE, r.stdout + r.stderr


def test_a_missing_watched_file_is_a_failure_not_a_pass(complete_log: Path, tmp_path: Path) -> None:
    """A path that vanished during the run is at least as suspicious as an edit."""
    r = run_tool(
        str(complete_log),
        "--since",
        str(time.time()),
        "--watch",
        str(tmp_path / "gone.sh"),
    )
    assert r.returncode != EXIT_OK
    assert "gone.sh" in r.stdout


def test_directories_expand_to_the_files_under_them(tmp_path: Path, complete_log: Path) -> None:
    """`--watch scripts/` must not silently check nothing."""
    d = tmp_path / "scripts"
    d.mkdir()
    (d / "a.sh").write_text("a\n")
    (d / "b.sh").write_text("b\n")
    _set_mtime(d / "a.sh", time.time() - 999)
    _set_mtime(d / "b.sh", time.time())  # one file edited during the run
    r = run_tool(str(complete_log), "--since", str(time.time() - 50), "--watch", str(d))
    assert r.returncode == EXIT_STALE, r.stdout + r.stderr
    assert "b.sh" in r.stdout
