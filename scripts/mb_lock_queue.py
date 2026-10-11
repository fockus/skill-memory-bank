#!/usr/bin/env python3
"""Ticket queue, liveness and status for mb-lock.sh named resources (specs/mb-team design §5, C3/C4).

For a resource whose C3 `path` is P: `P.lock/meta.json` is the holder, `P.queue/<seq>` one ticket per
waiter (lowest live seq is next). The lock is taken by renaming a prepared directory onto P.lock (atomic,
meta always present); a ticket is published with link(2), which fails on an existing seq, so neither a
mutex nor flock is needed. A process is alive only while its pid exists with the recorded
`ps -o lstart=` start time, which defeats pid reuse. mb-lock.sh owns signals, the child and the board.
"""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mb_lock_resource import (  # noqa: E402
    check,
    describe,
    die,
    has_cond,
    load_res,
    print_status,
    scan,
)

HOST = socket.gethostname()


def proc_start(pid) -> str | None:
    if not pid:
        return None
    # One fixed format: waiters with another LANG or TZ must read the same start string.
    r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                       env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    return r.stdout.strip() or None


def alive(pid, start) -> bool:
    """Pid exists (EPERM counts) and, when a start time was recorded, started at that time."""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    now = proc_start(pid)
    return now is not None and (start is None or now == start)


def holder_alive(meta: dict) -> bool | None:
    """True alive · False provably dead (or lease expired) · None unknown (unreadable meta)."""
    if not meta:
        return None
    if meta.get("host") != HOST:
        return True  # death on another host cannot be proven from here
    if meta.get("lease_until"):
        return time.time() < meta["lease_until"]
    return alive(meta.get("pid"), meta.get("pid_start")) or alive(
        meta.get("child"), meta.get("child_start"))


def read_meta(lock: Path) -> dict | None:
    """None when the lock is free, {} when it exists but its meta is unreadable."""
    if not lock.is_dir():
        return None
    try:
        return json.loads((lock / "meta.json").read_text())
    except (OSError, ValueError):
        return {}


def side(lock: Path, tag: str) -> Path:
    return lock.with_name(f"{lock.name}.{tag}-{os.getpid()}-{secrets.token_hex(4)}")


def take(lock: Path, info: dict) -> bool:
    tmp = side(lock, "tmp")
    tmp.mkdir(parents=True)
    (tmp / "meta.json").write_text(json.dumps(info))
    try:
        os.rename(tmp, lock)  # fails while P.lock exists with a meta inside
        return True
    except OSError:
        shutil.rmtree(tmp, ignore_errors=True)
        return False


def remove(lock: Path, meta: dict) -> bool:
    """Remove the lock only if it still carries the judged token; put it back otherwise."""
    grave = side(lock, "dead")
    try:
        os.rename(lock, grave)
    except OSError:
        return False
    if (read_meta(grave) or {}).get("token") != meta.get("token"):
        # ponytail: a break racing the queue head can move a fresh lock; we put it back. The restore
        # fails only if a third acquirer slipped in meanwhile — add a generation counter if ever seen.
        try:
            os.rename(grave, lock)
        except OSError:
            print(f"mb-lock: lock changed hands during removal; left at {grave}", file=sys.stderr)
        return False
    shutil.rmtree(grave, ignore_errors=True)
    return True


def tickets(queue: Path, prune: bool = True) -> list[tuple[Path, dict]]:
    out = []
    for f in sorted(queue.glob("[0-9]*")):
        try:
            t = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if t.get("host") == HOST and not alive(t.get("pid"), t.get("pid_start")):
            if prune:
                f.unlink(missing_ok=True)
            continue
        out.append((f, t))
    return out


def enqueue(queue: Path, owner: str, pid: int) -> Path:
    queue.mkdir(parents=True, exist_ok=True)
    tmp = queue / f".tmp-{os.getpid()}-{secrets.token_hex(4)}"
    tmp.write_text(json.dumps({"owner": owner, "pid": pid, "pid_start": proc_start(pid),
                               "host": HOST, "since": time.time()}))
    try:
        while True:
            seq = max((int(p.name) for p in queue.glob("[0-9]*") if p.name.isdigit()), default=0)
            try:
                os.link(tmp, queue / f"{seq + 1:012d}")
                return queue / f"{seq + 1:012d}"
            except FileExistsError:
                continue
    finally:
        tmp.unlink(missing_ok=True)


def op_wait(a, res, lock: Path, queue: Path) -> int:
    me = Path(a.ticket)
    try:
        my_start = json.loads(me.read_text()).get("pid_start")
    except (OSError, ValueError):
        die(f"ticket missing: {me}", 1)
    poll, n = float(res.get("poll_s", 5)), 0
    deadline = time.time() + a.wait if a.wait > 0 else None
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))
    try:
        while alive(a.pid, my_start):  # the wrapper died (even by SIGKILL) → drop the ticket
            live = [f for f, _ in tickets(queue)]
            if me not in live:
                die("ticket vanished from the queue", 1)
            pos, meta = live.index(me), read_meta(lock)
            if pos == 0 and meta is None:
                token, now = secrets.token_hex(8), time.time()
                if take(lock, {"owner": a.owner, "token": token, "pid": a.pid, "pid_start": my_start,
                               "child": None, "child_start": None, "host": HOST, "since": now,
                               "cmd": a.cmd, "lease_until": now + a.lease if a.lease > 0 else None}):
                    print(f"token={token}", flush=True)
                    return 0
                continue
            # AGR-097: the queue head reclaims a provably dead run holder; leases never auto-expire.
            if pos == 0 and meta and not meta.get("lease_until") and holder_alive(meta) is False:
                if remove(lock, meta):
                    print(f"reclaimed={describe(meta)}", flush=True)
                continue
            if n % 12 == 0:
                held = describe(meta) if meta is not None else "nobody"
                print(f"mb-lock: {'queued' if n == 0 else 'waiting'} for {res['name']} as #{pos + 1} "
                      f"({'next' if pos == 0 else f'{pos} ahead'}); held by {held}", file=sys.stderr)
            if deadline and time.time() >= deadline:
                die(f"gave up after {a.wait:g}s waiting for {res['name']}; the command was NOT run", 75)
            n += 1
            time.sleep(poll)
        return 1
    finally:
        me.unlink(missing_ok=True)


def own(lock: Path, token: str, what: str) -> dict:
    meta = read_meta(lock)
    if meta is None:
        die(f"{what} refused: the lock is not held", 1)
    if not token or meta.get("token") != token:
        die(f"{what} refused: the lock is held by {describe(meta)}, not by the caller", 1)
    return meta


def iso(t) -> str | None:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)) if t else None


def status_of(res: dict) -> dict:
    lock, queue = Path(res["path"] + ".lock"), Path(res["path"] + ".queue")
    now, meta, holder = time.time(), read_meta(lock), None
    if meta is not None:
        holder = {k: meta.get(k) for k in ("owner", "pid", "child", "host", "cmd", "lease_until")}
        holder.update(since=iso(meta.get("since")), age_s=int(now - meta.get("since", now)),
                      alive=holder_alive(meta))
    qs = [{"owner": t.get("owner"), "pid": t.get("pid"), "since": iso(t.get("since")),
           "wait_s": int(now - t.get("since", now)), "position": i + 1}
          for i, (_, t) in enumerate(tickets(queue, prune=False))]
    pre = check(res, "start") if has_cond(res, "start") else None
    stop = check(res, "stop") if has_cond(res, "stop") else None
    free = next((c[1] for c in (pre, stop) if c and c[1] is not None), None)
    return {"name": res["name"], "held": meta is not None, "holder": holder, "queue": qs,
            "free_disk_gb": round(free, 1) if free is not None else None,
            "preconditions_ok": pre[0] if pre else None,
            "stop_breached": (not stop[0]) if stop else None}


def op_env(a, res, lock, queue) -> int:
    for k, v in (("R_NAME", res["name"]), ("R_WATCH", res.get("watch_interval_s", 30)),
                 ("R_HAS_PRE", int(has_cond(res, "start"))),
                 ("R_HAS_STOP", int(has_cond(res, "stop"))),
                 ("R_HAS_MAINT", int(bool(res.get("maintenance"))))):
        print(f"{k}={shlex.quote(str(v))}")
    return 0


def op_setchild(a, res, lock, queue) -> int:
    meta = own(lock, a.token, "setchild")
    meta.update(child=a.child, child_start=proc_start(a.child))
    tmp = lock / f".meta-{os.getpid()}"
    tmp.write_text(json.dumps(meta))
    os.replace(tmp, lock / "meta.json")
    return 0


def op_check(a, res, lock, queue) -> int:
    ok, _, msg = check(res, a.phase)
    print(f"mb-lock: {res['name']} {a.phase}: {msg}", file=sys.stderr)
    return 0 if ok else 1


def op_maint(a, res, lock, queue) -> int:
    own(lock, a.token, "maintenance")
    if not res.get("maintenance"):
        return 0
    print(f"mb-lock: maintenance: {res['maintenance']}", file=sys.stderr)
    return subprocess.run(res["maintenance"], shell=True, stdout=sys.stderr).returncode


def op_release(a, res, lock, queue) -> int:
    return 0 if read_meta(lock) is None or remove(lock, own(lock, a.token, "release")) else 1


def op_break(a, res, lock, queue) -> int:
    meta = read_meta(lock)
    if meta is None:
        return 0
    if holder_alive(meta):
        die(f"break refused: holder {describe(meta)} is alive", 1)
    if not remove(lock, meta):
        die("break failed: the lock changed during removal", 1)
    print(describe(meta))
    return 0


OPS = {"env": op_env, "wait": op_wait, "setchild": op_setchild, "check": op_check,
       "maint": op_maint, "release": op_release, "break": op_break,
       "enqueue": lambda a, res, lock, queue: print(enqueue(queue, a.owner, a.pid)) or 0}


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(prog="mb_lock_queue.py")
    p.add_argument("op", choices=[*OPS, "status"])
    p.add_argument("name", nargs="?")
    for flag in ("--resource-json", "--mb", "--owner", "--ticket", "--token", "--cmd"):
        p.add_argument(flag, default="")
    for flag, kind in (("--pid", int), ("--child", int), ("--wait", float), ("--lease", float)):
        p.add_argument(flag, type=kind, default=0)
    p.add_argument("--phase", choices=["start", "stop"], default="start")
    p.add_argument("--json", action="store_true")
    a = p.parse_args(argv)
    if a.op != "status":
        res = load_res(a)
        return OPS[a.op](a, res, Path(res["path"] + ".lock"), Path(res["path"] + ".queue"))
    rows = [status_of(r) for r in scan(a)] if not (a.name or a.resource_json) else [status_of(load_res(a))]
    print_status(rows, a.json)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
