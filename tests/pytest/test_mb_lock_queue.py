"""mb_lock_queue.py / mb_lock_resource.py — liveness, df parsing and the C4 status schema (specs/mb-team design §5)."""

from __future__ import annotations

import importlib.util
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LOCK_SH = REPO / "scripts" / "mb-lock.sh"
sys.path.insert(0, str(REPO / "scripts"))


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


q = _load("mb_lock_queue")
res_mod = _load("mb_lock_resource")

DF_MACOS = """Filesystem     1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s5    971350180 870217516  64529036    94%    /System/Volumes/Data
"""
DF_LINUX = """Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/nvme0n1p2   490617784 98201116 367420636      22% /
"""
DF_SPACES = """Filesystem 1024-blocks Used Available Capacity Mounted on
map auto_home          0        0  1048576   100% /System/Volumes/Data/home dir
"""


def test_parse_df_macos_reads_available_column():
    assert res_mod.parse_df(DF_MACOS) == pytest.approx(64529036 / 1048576)


def test_parse_df_linux_reads_available_column():
    assert res_mod.parse_df(DF_LINUX) == pytest.approx(367420636 / 1048576)


def test_parse_df_filesystem_and_mount_with_spaces():
    assert res_mod.parse_df(DF_SPACES) == pytest.approx(1.0)


def test_alive_own_process_with_matching_start_is_alive():
    assert q.alive(os.getpid(), q.proc_start(os.getpid()))


def test_alive_start_time_mismatch_is_dead():
    assert not q.alive(os.getpid(), "Mon Jan  1 00:00:00 2001")


def test_alive_gone_pid_is_dead():
    p = subprocess.Popen(["true"])
    p.wait()
    assert not q.alive(p.pid, None)


def test_alive_foreign_user_process_counts_as_alive():
    # pid 1 belongs to root: kill(0) raises EPERM, which proves existence.
    assert q.alive(1, q.proc_start(1))


def test_holder_on_another_host_is_never_provably_dead():
    meta = {"host": "elsewhere.invalid", "pid": 999999, "pid_start": "x", "lease_until": None}
    assert q.holder_alive(meta) is True


def test_holder_with_dead_wrapper_and_live_child_is_alive():
    meta = {"host": socket.gethostname(), "pid": 999999, "pid_start": "x",
            "child": os.getpid(), "child_start": q.proc_start(os.getpid()), "lease_until": None}
    assert q.holder_alive(meta) is True


def test_lease_holder_liveness_follows_the_lease():
    meta = {"host": socket.gethostname(), "pid": 999999, "pid_start": "x"}
    assert q.holder_alive({**meta, "lease_until": time.time() + 60}) is True
    assert q.holder_alive({**meta, "lease_until": time.time() - 1}) is False


def _wait(cond, timeout=10.0):
    end = time.time() + timeout
    while not cond():
        assert time.time() < end, "condition not reached"
        time.sleep(0.05)


def test_status_json_matches_c4_with_holder_and_queued_waiter(tmp_path):
    res = {"name": "build", "kind": "mutex", "scope": "host", "path": str(tmp_path / "locks" / "build"),
           "preconditions": {"free_disk_gb": 0, "disk_path": "/"}, "stop_threshold": {"free_disk_gb": 0},
           "poll_s": 0.1, "watch_interval_s": 1}
    rj = tmp_path / "build.json"
    rj.write_text(json.dumps(res))
    common = ["--resource-json", str(rj), "--mb", str(tmp_path)]
    token = subprocess.run(["bash", str(LOCK_SH), "acquire", "build", "--owner", "H", "--lease", "60", *common],
                           check=True, capture_output=True, text=True).stdout.strip()
    waiter = subprocess.Popen(["bash", str(LOCK_SH), "run", "build", "--owner", "W1", *common, "--", "true"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        _wait(lambda: any((tmp_path / "locks" / "build.queue").glob("[0-9]*")))
        out = subprocess.run(["bash", str(LOCK_SH), "status", "build", "--json", *common],
                             check=True, capture_output=True, text=True).stdout
        doc = json.loads(out)
        (r,) = doc["resources"]
        assert set(r) >= {"name", "held", "holder", "queue", "free_disk_gb", "preconditions_ok", "stop_breached"}
        assert r["name"] == "build" and r["held"] is True
        assert set(r["holder"]) >= {"owner", "pid", "child", "host", "since", "age_s", "cmd", "alive", "lease_until"}
        assert r["holder"]["owner"] == "H" and r["holder"]["alive"] is True
        assert isinstance(r["holder"]["age_s"], int)
        (w,) = r["queue"]
        assert set(w) >= {"owner", "pid", "since", "wait_s", "position"}
        assert w["owner"] == "W1" and w["position"] == 1 and w["pid"] == waiter.pid
        assert isinstance(r["free_disk_gb"], float)
        assert r["preconditions_ok"] is True and r["stop_breached"] is False
    finally:
        subprocess.run(["bash", str(LOCK_SH), "release", "build", "--token", token, *common], check=False)
        waiter.wait(timeout=10)


def test_status_json_of_a_free_resource(tmp_path):
    rj = tmp_path / "r.json"
    rj.write_text(json.dumps({"name": "full-tests", "path": str(tmp_path / "full-tests")}))
    out = subprocess.run([sys.executable, str(REPO / "scripts" / "mb_lock_queue.py"), "status",
                          "--resource-json", str(rj), "--json"], check=True, capture_output=True, text=True).stdout
    (r,) = json.loads(out)["resources"]
    assert r["held"] is False and r["holder"] is None and r["queue"] == []
    assert r["preconditions_ok"] is None and r["stop_breached"] is None


def test_alive_does_not_depend_on_the_callers_time_zone_or_locale(monkeypatch):
    monkeypatch.setenv("TZ", "UTC")
    monkeypatch.setenv("LC_ALL", "ru_RU.UTF-8")
    recorded = q.proc_start(os.getpid())
    monkeypatch.setenv("TZ", "Asia/Tokyo")
    monkeypatch.setenv("LC_ALL", "C")
    assert q.alive(os.getpid(), recorded)
