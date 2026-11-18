#!/usr/bin/env python3
"""Process liveness for mb-lock.sh holders and waiters (specs/mb-team design §5).

A process is alive while its pid exists; when both the recorded and the current `ps -o lstart=` start
times are known they must match, which defeats pid reuse. An unknown start time (no `ps`, or a `ps`
without lstart) never proves death: a live holder must not be reclaimed or a live waiter pruned on it.
"""

from __future__ import annotations

import os
import socket
import subprocess
import time

HOST = socket.gethostname()


def proc_start(pid) -> str | None:
    if not pid:
        return None
    try:
        # One fixed format: waiters with another LANG or TZ must read the same start string.
        r = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True, text=True,
                           env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    except OSError:
        return None
    return r.stdout.strip() or None


def alive(pid, start) -> bool:
    """Pid exists (EPERM counts) and, when both start times are known, started at the recorded time."""
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    now = proc_start(pid)
    return now is None or start is None or now == start


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
