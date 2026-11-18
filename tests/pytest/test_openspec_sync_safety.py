"""OpenSpec bank-write safety (Stage 9 fix cycle 1, AGR-105 Q1/Q5).

A re-``import`` is a three-way merge of the topic's own change (never a silent
``take=openspec``, never a re-link to another change); a checkbox with no
reliable baseline is a conflict when the sides differ; a batch ``sync`` writes
nothing when any topic conflicts or errors; an errored topic exits non-zero.
"""

from __future__ import annotations

import fcntl
import importlib.util
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-openspec.py"

_SPEC = (
    "## ADDED Requirements\n\n"
    "### Requirement: Widget Cache\n"
    "The system SHALL cache widget definitions in memory.\n\n"
    "#### Scenario: Cache hit\n"
    "- **WHEN** a widget is requested twice\n"
    "- **THEN** the second lookup is served from memory\n"
)
_TASKS = "## 1. Build\n\n- [ ] 1.1 Implement in-memory cache\n- [ ] 1.2 Add cache invalidation\n"


def _write_change(change_dir: Path, *, spec: str = _SPEC, tasks: str = _TASKS) -> Path:
    (change_dir / "specs" / "widgets").mkdir(parents=True, exist_ok=True)
    (change_dir / "proposal.md").write_text(
        "## Why\n\nWidgets are slow.\n\n## What Changes\n\n- Cache them.\n", encoding="utf-8"
    )
    (change_dir / "specs" / "widgets" / "spec.md").write_text(spec, encoding="utf-8")
    (change_dir / "tasks.md").write_text(tasks, encoding="utf-8")
    return change_dir


def _cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], capture_output=True, text=True, check=False
    )


def _snapshot(root: Path) -> dict[str, tuple[bytes, int]]:
    return {
        p.relative_to(root).as_posix(): (p.read_bytes(), p.stat().st_mtime_ns)
        for p in root.rglob("*")
        if p.is_file()
    }


def _edit(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    assert old in text, old
    path.write_text(text.replace(old, new), encoding="utf-8")


def _import(change: Path, bank: Path, topic: str) -> subprocess.CompletedProcess[str]:
    return _cli("import", str(change), "--as", topic, "--mb", str(bank))


@pytest.fixture
def env(tmp_path: Path) -> dict[str, Path]:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    change = _write_change(tmp_path / "openspec" / "changes" / "add-widget-cache")
    assert _import(change, bank, "widgets").returncode == 0
    return {"root": tmp_path, "bank": bank, "change": change, "dir": bank / "specs" / "widgets"}


def test_reimport_conflict_on_both_sides_writes_nothing_and_exits_1(env):
    _edit(env["dir"] / "requirements.md", "in memory.", "in memory, per tenant.")
    _edit(env["change"] / "specs" / "widgets" / "spec.md", "in memory.", "in Redis.")
    bank_before = _snapshot(env["bank"])

    proc = _import(env["change"], env["bank"], "widgets")

    assert proc.returncode == 1
    assert "[conflict]" in proc.stderr and "req:Widget Cache" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def test_import_refuses_a_topic_linked_to_another_change(env):
    other = _write_change(env["root"] / "openspec" / "changes" / "other-change")
    bank_before = _snapshot(env["bank"])

    proc = _import(other, env["bank"], "widgets")

    assert proc.returncode == 1
    assert "linked" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def test_import_refuses_an_existing_topic_not_linked_to_openspec(env):
    spec_dir = env["bank"] / "specs" / "authored"
    spec_dir.mkdir()
    (spec_dir / "requirements.md").write_text("# Requirements\n", encoding="utf-8")
    (spec_dir / "tasks.md").write_text("# Tasks\n", encoding="utf-8")
    bank_before = _snapshot(env["bank"])

    proc = _import(env["change"], env["bank"], "authored")

    assert proc.returncode == 1
    assert "not linked" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def test_sync_without_sidecar_reports_a_checkbox_that_differs_as_a_conflict(env):
    (env["dir"] / "openspec-sync.json").unlink()
    _write_change(env["change"], tasks=_TASKS.replace("- [ ] 1.1", "- [x] 1.1"))
    bank_before = _snapshot(env["bank"])

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 1
    assert "task:1.1" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before
    taken = _cli("sync", "widgets", "--take", "openspec", "--mb", str(env["bank"]))
    assert taken.returncode == 0, taken.stderr
    assert "- [x] 1.1" in (env["dir"] / "tasks.md").read_text(encoding="utf-8")


def test_batch_sync_writes_no_topic_when_another_topic_conflicts(env):
    second = _write_change(env["root"] / "openspec" / "changes" / "zz-change")
    assert _import(second, env["bank"], "zz-widgets").returncode == 0
    _edit(env["change"] / "specs" / "widgets" / "spec.md", "in memory.", "in Redis.")
    _edit(env["bank"] / "specs" / "zz-widgets" / "requirements.md", "in memory.", "in RAM.")
    _edit(second / "specs" / "widgets" / "spec.md", "in memory.", "on disk.")
    bank_before = _snapshot(env["bank"])

    proc = _cli("sync", "--mb", str(env["bank"]))

    assert proc.returncode == 1
    assert "zz-widgets: [conflict]" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def test_sync_of_a_topic_whose_source_is_gone_exits_1(env):
    env["change"].rename(env["change"].with_name("moved-away"))
    bank_before = _snapshot(env["bank"])

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 1
    assert "source" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def test_import_refuses_an_incomplete_existing_topic(env):
    spec_dir = env["bank"] / "specs" / "half"
    spec_dir.mkdir()
    (spec_dir / "design.md").write_text("# Design\n\nAuthored by hand.\n", encoding="utf-8")
    bank_before = _snapshot(env["bank"])

    proc = _import(env["change"], env["bank"], "half")

    assert proc.returncode == 1
    assert _snapshot(env["bank"]) == bank_before


def test_sync_reports_a_task_added_on_both_sides_with_different_ticks(env):
    _edit(
        env["dir"] / "tasks.md",
        "- [ ] 1.2 Add cache invalidation",
        "- [ ] 1.2 Add cache invalidation\n- [ ] 1.3 Docs",
    )
    _write_change(env["change"], tasks=_TASKS + "- [x] 1.3 Docs\n")
    bank_before = _snapshot(env["bank"])

    proc = _cli("sync", "widgets", "--mb", str(env["bank"]))

    assert proc.returncode == 1
    assert "task:1.3" in proc.stderr
    assert _snapshot(env["bank"]) == bank_before


def _load_cli():
    spec = importlib.util.spec_from_file_location("mb_openspec_cli_safety", SCRIPT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_batch_sync_write_failure_leaves_every_topic_untouched(env, monkeypatch):
    second = _write_change(env["root"] / "openspec" / "changes" / "zz-change")
    assert _import(second, env["bank"], "zz-widgets").returncode == 0
    _edit(env["change"] / "specs" / "widgets" / "spec.md", "in memory.", "in Redis.")
    _edit(second / "specs" / "widgets" / "spec.md", "in memory.", "on disk.")
    bank_before = {k: v[0] for k, v in _snapshot(env["bank"]).items()}
    mod = _load_cli()
    orig = mod.atomic_write

    def fail_on_second(path, content):
        if "zz-widgets" in str(path):
            raise OSError("simulated disk full")
        orig(path, content)

    monkeypatch.setattr(mod, "atomic_write", fail_on_second)
    with pytest.raises(OSError):
        mod.run_sync(mb_path=env["bank"], topic=None)

    assert {k: v[0] for k, v in _snapshot(env["bank"]).items()} == bank_before


def test_sync_waits_while_another_openspec_operation_holds_the_bank_lock(env):
    _edit(env["change"] / "specs" / "widgets" / "spec.md", "in memory.", "in Redis.")
    req = env["dir"] / "requirements.md"
    fd = os.open(env["bank"] / "specs", os.O_RDONLY)
    fcntl.flock(fd, fcntl.LOCK_EX)
    try:
        proc = subprocess.Popen(
            [sys.executable, str(SCRIPT), "sync", "widgets", "--mb", str(env["bank"])],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        time.sleep(2)
        assert proc.poll() is None  # still waiting for the lock
        assert "in Redis." not in req.read_text(encoding="utf-8")
    finally:
        os.close(fd)
    out, err = proc.communicate(timeout=60)
    assert proc.returncode == 0, err
    assert "in Redis." in req.read_text(encoding="utf-8")


@pytest.mark.parametrize("mode", [0o600, 0o640])
def test_batch_sync_keeps_the_mode_of_a_restricted_bank_file(env, mode):
    req = env["dir"] / "requirements.md"
    req.chmod(mode)
    _edit(env["change"] / "specs" / "widgets" / "spec.md", "in memory.", "in Redis.")
    assert _cli("sync", "--mb", str(env["bank"])).returncode == 0
    assert "Redis" in req.read_text(encoding="utf-8")
    assert req.stat().st_mode & 0o777 == mode


def test_bank_lock_fails_closed_when_the_lock_cannot_be_taken(env, monkeypatch):
    spec = importlib.util.spec_from_file_location("mb_openspec_bank_t", REPO_ROOT / "scripts" / "mb_openspec_bank.py")
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)

    def _no_lock(_d):
        import contextlib

        @contextlib.contextmanager
        def cm():
            yield False

        return cm()

    monkeypatch.setattr(mod, "_dir_lock", _no_lock)
    with pytest.raises(RuntimeError, match="lock"), mod.bank_lock(env["bank"]):
        pytest.fail("body must not run without the lock")
