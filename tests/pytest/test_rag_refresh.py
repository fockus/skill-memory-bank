"""Detached refresh contracts, with local runtime and short timers in a copied bundle."""

from __future__ import annotations

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path

import pytest
from test_rag_status import ROOT, cli, snapshot, status
from test_rag_status import git_project_fixture as git_project_fixture
from test_rag_status import offline_pplx_fixture as offline_pplx_fixture
from test_rag_status import offline_qmd_fixture as offline_qmd_fixture


def eventually(check: Callable[[], bool], timeout: int = 20) -> None:
    until = time.monotonic() + timeout
    while time.monotonic() < until:
        if check():
            return
        time.sleep(0.05)
    raise AssertionError("Timed out waiting for background RAG work")


@pytest.fixture
def scheduler(tmp_path: Path, offline_qmd: Path, project: Path, request: pytest.FixtureRequest) -> Path:
    for name in ("mb-code-context.py", "mb_code_context_core.py", "mb_graph_query_core.py"):
        shutil.copy(ROOT / "scripts" / name, offline_qmd)
    module = offline_qmd / "mb_rag_refresh.py"
    source = module.read_text()
    budget = 4 if "deadline" in request.node.name else 15
    for name, val in {"QUIET": 1.0, "COOLDOWN": 4.0, "BUDGET": budget}.items():
        source = source.replace(f"\n{name} = ", f"\n{name} = {val} # ")
    module.write_text(source)
    lifecycle = offline_qmd / "mb_project_rag.py"
    with lifecycle.open("a") as out:
        out.write(
            "\nimport time\n_real_update = update\n"
            "def update(root, bank, *, max_new_chunks=None):\n"
            f"    with open({str(tmp_path / 'attempts')!r}, 'a') as log:\n"
            "        print(time.monotonic(), max_new_chunks, file=log)\n"
            "    return _real_update(root, bank, max_new_chunks=max_new_chunks)\n"
        )
    cli(project, "init", "--model", "qwen3")
    return offline_qmd


def lookup(project: Path, scripts: Path, text: str) -> dict:
    proc = subprocess.run(
        [sys.executable, scripts / "mb-code-context.py", "--query", text, "--json"],
        cwd=project, capture_output=True, text=True, check=True, timeout=10,
        env={**os.environ, "PYTHONPATH": os.pathsep.join(map(str, (ROOT, ROOT / "scripts")))},
    )
    return json.loads(proc.stdout)


@pytest.mark.parametrize("damage_when", ["before_lookup", "while_scheduled"])
def test_source_change_never_auto_repairs_broken_publication(
    tmp_path: Path, project: Path, scheduler: Path, damage_when: str
):
    (pointer,) = tmp_path.rglob("current.json")
    (rows,) = tmp_path.rglob("rows.json")
    initial = pointer.read_bytes()
    lease = pointer.parent / "refresh"
    (project / "src/orders.py").write_text("new_discount = 3\n")
    if damage_when == "while_scheduled":
        assert status(project, "--auto-refresh")["refresh"] == "scheduled"
    rows.unlink()
    assert status(project, "--auto-refresh")["status"] == "broken"
    if damage_when == "before_lookup":
        pack = lookup(project, scheduler, "new_discount")
        assert "text" in pack["channels_used"]
        assert not lease.exists() and not any("scheduled" in w for w in pack["warnings"])
        assert any("memory-bank rag update" in w for w in pack["warnings"])
    else:
        def timer_finished() -> bool:
            fd = os.open(lease, os.O_DIRECTORY | os.O_RDONLY)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return True
            except BlockingIOError:
                return False
            finally:
                os.close(fd)

        eventually(timer_finished)
    assert not (tmp_path / "attempts").exists()
    assert not rows.exists() and pointer.read_bytes() == initial
    assert status(project)["status"] == "broken"


@pytest.mark.parametrize("entry", ["startup", "lookup"])
def test_refresh_coalesces_unannounced_edit_then_obeys_cross_session_cooldown(
    tmp_path: Path, project: Path, scheduler: Path, entry: str
):
    source = project / "src/orders.py"
    source.write_text("price = 12\n")
    before = snapshot(tmp_path)
    assert status(project)["status"] == "stale"
    assert snapshot(tmp_path) == before
    if entry == "startup":
        assert status(project, "--auto-refresh")["refresh"] == "scheduled"
    else:
        pack = lookup(project, scheduler, "price")
        assert pack["candidate_files"] == ["src/orders.py"]
        assert any("scheduled" in warning for warning in pack["warnings"])
    attempts = tmp_path / "attempts"
    assert not attempts.exists()
    # A second session asks for the same refresh. The next edit has NO trigger.
    contender = subprocess.Popen(
        [sys.executable, scheduler / "mb-rag.py", "status", "--auto-refresh", "--json"],
        cwd=project, stdout=subprocess.PIPE, text=True,
    )
    time.sleep(0.15)
    source.write_text("later_price = 15\n")
    changed = time.monotonic()
    assert json.loads(contender.communicate(timeout=10)[0])["refresh"] == "scheduled"
    eventually(lambda: status(project)["status"] == "ready")
    start, cap = attempts.read_text().split()
    assert float(start) >= changed + 1 and cap == "32"
    assert "semantic" in lookup(project, scheduler, "later_price")["channels_used"]
    (started,) = (tmp_path / "state").rglob("started")
    first_started = started.stat().st_mtime

    source.write_text("last_price = 16\n")
    assert status(project, "--auto-refresh")["refresh"] == "scheduled"
    eventually(lambda: status(project)["status"] == "ready")
    second, cap = attempts.read_text().splitlines()[1].split()
    assert float(second) > float(start) and cap == "32"
    assert started.stat().st_mtime >= first_started + 4
    assert len(attempts.read_text().splitlines()) == 2


@pytest.mark.parametrize("cause", ["oversized", "legacy"])
def test_manual_fallback_survives_other_sessions(tmp_path: Path, project: Path, scheduler: Path, cause: str):
    source = project / "src/orders.py"
    if cause == "oversized":
        source.write_text(("new chunks\n" * 250) * 33)
    else:
        (hashes,) = tmp_path.rglob("hashes.json")
        hashes.unlink()
        source.write_text("legacy = True\n")
    status(project, "--auto-refresh")
    eventually(lambda: status(project).get("refresh") == "manual")
    result = status(project, "--auto-refresh")
    assert result["status"] == "stale" and result["action"] == "memory-bank rag update"
    assert "memory-bank rag update" in cli(project, "status")
    time.sleep(4.1)
    assert status(project, "--auto-refresh") == result
    assert len((tmp_path / "attempts").read_text().splitlines()) == 1
    if cause == "oversized":
        source.write_text("small_edit = 1\n")
        assert status(project, "--auto-refresh")["refresh"] == "scheduled"
        eventually(lambda: status(project)["status"] == "ready")
    else:
        cli(project, "update")
        assert status(project)["status"] == "ready"


def test_deleting_last_source_publishes_searchable_empty_index(tmp_path: Path, project: Path, scheduler: Path):
    (project / "src/orders.py").unlink()
    assert status(project, "--auto-refresh")["refresh"] == "scheduled"
    eventually(lambda: status(project)["status"] == "ready")
    assert (tmp_path / "provider-calls").read_text().splitlines() == ["build", "refresh"]
    assert lookup(project, scheduler, "orders")["semantic_candidates"] == []
    (rows,) = tmp_path.rglob("rows.json")
    rows.write_text('[["nonexistent.py",1,1]]')
    assert status(project)["status"] == "broken"


def test_empty_perplexity_generation_requires_empty_ids(
    tmp_path: Path, project: Path, offline_pplx, monkeypatch: pytest.MonkeyPatch
):
    import mb_project_rag as rag
    import mb_rag_pplx as pplx

    def publish_empty(
        index: Path, docs: list, cache: Path, old: Path, reuse: list, max_new_chunks: int | None
    ) -> bool:
        assert docs == reuse == []
        offline_pplx(index, docs, cache)
        return True

    monkeypatch.setattr(pplx, "refresh", publish_empty)
    (project / "src/orders.py").unlink()
    rag.update(project, project / ".memory-bank", max_new_chunks=32)
    assert status(project)["status"] == "ready"
    (ids,) = tmp_path.rglob("pplx-ids.json")
    ids.write_text('["0"]')
    assert status(project)["status"] == "broken"


def test_deadline_kills_hung_provider_tree_and_cleans_generation(tmp_path: Path, project: Path, scheduler: Path):
    import signal

    node = tmp_path / "qmd/bin/node"
    escaped = tmp_path / "survived"
    entered = tmp_path / "child-running"
    pidfile = tmp_path / "worker-pid"
    lifecycle = scheduler / "mb_project_rag.py"
    with lifecycle.open("a") as out:
        out.write(
            "\n_bounded_update = update\n"
            "def update(*args, **kwargs):\n"
            "    import os\n"
            f"    Path({str(pidfile)!r}).write_text(str(os.getpid()))\n"
            "    return _bounded_update(*args, **kwargs)\n"
        )
    grandchild = (
        "import time, signal; from pathlib import Path; "
        f"signal.signal(signal.SIGTERM,signal.SIG_IGN); Path({str(entered)!r}).touch(); "
        f"time.sleep(4.5); Path({str(escaped)!r}).touch()"
    )
    old = node.read_text().splitlines(keepends=True)
    node.write_text(old[0] + (
        "import time, signal, subprocess, sys\n"
        "signal.signal(signal.SIGTERM,signal.SIG_IGN)\n"
        f"subprocess.Popen([sys.executable, '-c', {grandchild!r}]); time.sleep(30)\n"
    ) + "".join(old[1:]))
    (rows,) = tmp_path.rglob("rows.json")
    generations = rows.parent.parent
    before = set(generations.iterdir())
    (project / "src/orders.py").write_text("slow = 2\n")
    assert status(project, "--auto-refresh")["refresh"] == "scheduled"
    # A suspended embedder cannot unwind a SIGTERM handler or run finally.
    eventually(entered.exists)
    os.kill(int(pidfile.read_text()), signal.SIGSTOP)
    eventually(lambda: status(project).get("refresh") == "manual")
    assert set(generations.iterdir()) == before and rows.exists()
    time.sleep(max(0.0, entered.stat().st_mtime + 4.8 - time.time()))
    assert not escaped.exists()
