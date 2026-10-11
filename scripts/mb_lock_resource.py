#!/usr/bin/env python3
"""Resource config and conditions for mb-lock.sh (specs/mb-team design §5, contract C3).

Loads the C3 resource JSON (from `--resource-json` or `mb_team_config.py resource`), resolves the lock
path from the scope, evaluates start preconditions and the stop threshold (free disk from `df -Pk`,
optional check command), and renders holders for messages and `status`. Stdlib only.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
_DF_ROW = re.compile(r"(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s")


def die(msg: str, code: int) -> None:
    print(f"mb-lock: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_df(text: str) -> float:
    """Free GiB from `df -Pk` output (macOS and Linux; spaces in filesystem or mount are fine)."""
    m = _DF_ROW.search(text.strip().splitlines()[-1] + " ")
    if not m:
        raise ValueError(f"unparseable df output: {text!r}")
    return int(m.group(3)) / 1048576


def free_gb(path: str) -> float | None:
    r = subprocess.run(["df", "-Pk", path], capture_output=True, text=True)
    try:
        return parse_df(r.stdout) if r.returncode == 0 else None
    except ValueError:
        return None


def lock_root(a, scope: str | None) -> Path:
    if scope == "bank" and a.mb:
        return Path(a.mb) / ".locks" / "res"
    return Path(os.environ.get("MB_LOCK_DIR") or Path(os.environ.get("TMPDIR", "/tmp")) / "mb-locks")


def load_res(a) -> dict:
    if a.resource_json:
        try:
            res = json.loads(Path(a.resource_json).read_text())
        except (OSError, ValueError) as e:
            die(f"cannot read resource JSON {a.resource_json}: {e}", 2)
    else:
        if not a.name:
            die("resource name required", 2)
        cmd = [sys.executable, str(HERE / "mb_team_config.py"), "resource", a.name, "--json"]
        r = subprocess.run(cmd + (["--mb", a.mb] if a.mb else []), capture_output=True, text=True)
        if r.returncode:
            kind = "unknown resource" if r.returncode == 3 else "invalid resource config"
            die(f"{kind} {a.name}: {r.stderr.strip()}", 2)
        res = json.loads(r.stdout)
    if not isinstance(res, dict) or not res.get("name") or res.get("kind", "mutex") != "mutex":
        die("resource JSON needs a name and kind mutex", 2)
    res.setdefault("path", None)
    res["path"] = res["path"] or str(lock_root(a, res.get("scope")) / res["name"])
    if not os.path.isabs(res["path"]):
        die(f"resource path must be absolute: {res['path']}", 2)
    return res


def has_cond(res: dict, phase: str) -> bool:
    """A condition block counts only with a threshold or a check (C3 emits nulls for unset fields)."""
    cond = res.get("preconditions" if phase == "start" else "stop_threshold") or {}
    return cond.get("free_disk_gb") is not None or bool(cond.get("check"))


def check(res: dict, phase: str) -> tuple[bool, float | None, str]:
    """(ok, free GiB, message). For phase stop, ok=False means the stop condition is breached."""
    cond = res.get("preconditions" if phase == "start" else "stop_threshold") or {}
    ok, free, msgs = True, None, []
    if cond.get("free_disk_gb") is not None:
        free = free_gb(cond.get("disk_path") or (res.get("preconditions") or {}).get("disk_path") or ".")
        if free is None:
            ok = phase == "stop"  # unknown disk: fail closed at start, never kill a build on a df hiccup
            msgs.append("free disk unknown (df failed)")
        else:
            ok = free >= cond["free_disk_gb"]
            msgs.append(f"free {free:.1f} GiB" + ("" if ok else f" < {cond['free_disk_gb']}"))
    if cond.get("check"):
        rc = subprocess.run(cond["check"], shell=True, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL).returncode
        if rc:
            ok = False
            msgs.append(f"check failed (exit {rc}): {cond['check']}")
    return ok, free, "; ".join(msgs) or "no conditions"


def describe(m: dict) -> str:
    if not m:
        return "unknown holder (unreadable meta)"
    since = m.get("since") or time.time()
    child = f" child {m['child']}" if m.get("child") else ""
    return (f"{m.get('owner')} pid {m.get('pid')}{child} since "
            f"{time.strftime('%H:%M:%S', time.localtime(since))} "
            f"({int((time.time() - since) // 60)}m): {m.get('cmd') or ''}").rstrip(": ")


def scan(a) -> list[dict]:
    """Resources with a lock or queue on disk (`status` without a name or resource JSON)."""
    found: dict[str, dict] = {}
    for d in [lock_root(a, "host")] + ([lock_root(a, "bank")] if a.mb else []):
        for p in sorted(d.glob("*.lock")) + sorted(d.glob("*.queue")):
            found.setdefault(p.stem, {"name": p.stem, "path": str(p.with_suffix(""))})
    return list(found.values())


def print_status(rows: list[dict], as_json: bool) -> None:
    if as_json:
        print(json.dumps({"resources": rows}))
        return
    for r in rows:
        h = r["holder"]
        state = {True: "alive", False: "DEAD", None: "unknown"}[h["alive"]] if h else ""
        print(f"{r['name']}  held by {describe({**h, 'since': time.time() - h['age_s']})}  {state}"
              if h else f"{r['name']}  free")
        if r["queue"]:
            print("       queue: " + " · ".join(f"{w['owner']} {w['wait_s'] // 60}m" for w in r["queue"]))
        if r["free_disk_gb"] is not None or r["preconditions_ok"] is not None:
            print(f"       free {r['free_disk_gb']} GiB · preconditions {r['preconditions_ok']} · "
                  f"stop breached {r['stop_breached']}")
