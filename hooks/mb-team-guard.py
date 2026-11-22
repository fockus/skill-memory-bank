#!/usr/bin/env python3
"""MB Team orchestrator guard — Claude Code PreToolUse (Edit|Write|NotebookEdit|Bash) and Stop hook.

A session becomes an orchestrator when one of its Bash commands runs `mb-team.sh` (or the `team`
helper of commands/team.md), or always with MB_ORCHESTRATOR=1. For such a session, main thread only
(a payload with `agent_id` is a subagent and passes):
  - Edit/Write/NotebookEdit of a file inside the project tree but outside the bank is denied:
    the orchestrator delegates code as a track (`team track add <id> --followup …` after close).
  - `git commit` is denied once per distinct command with the board (`mb-coord.sh active`) and a
    pointer to `team commit`; the same command again passes (bank or docs commits stay possible).
  - Stop blocks once per change when orchestrator-console.md is older than the newest team.json or
    the board (with an open team), or is over its line cap.
Opt-out: MB_TEAM_GUARD=off, or `team_guard=off` in <bank>/.mb-config. Any error fails open.
State: $MB_LOCK_DIR (default /tmp/mb-locks-<uid>)/team-guard/<session>.json — host-local, never in git.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
TEAM_CMD = re.compile(
    r"mb-team\.sh|(^|[\n;&|(]\s*)team\s+(init|track|next|status|plan|collect|commit|close|prompt)\b"
)
GIT_COMMIT = re.compile(r"(^|[\n;&|(]\s*)(\S*/)?git((\s+-[Cc]\s+\S+)|(\s+--?[\w-]+(=\S+)?))*\s+commit\b")
EDIT_TOOLS = ("Edit", "Write", "NotebookEdit", "MultiEdit")


def state_dir() -> Path:
    """Private per-user dir; a symlink or a foreign owner raises (and the hook fails open)."""
    sys.path.insert(0, str(SKILL / "scripts"))
    from mb_team_config import host_lock_root  # validates the root the same way for mb-lock.sh

    path = Path(host_lock_root()) / "team-guard"
    if not path.is_symlink():
        path.mkdir(mode=0o700, exist_ok=True)
    info = os.lstat(path)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise OSError(f"{path} is a symlink or not owned by this user")
    return path


def save(path: Path, data: dict) -> None:
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(data))
    os.replace(tmp, path)


def state_file(sid: str) -> Path:
    return state_dir() / (re.sub(r"[^A-Za-z0-9_.-]", "_", sid) + ".json")


def resolve_bank(cwd: str) -> str:
    out = subprocess.run(
        ["bash", "-c", '. "$1"; mb_resolve_path ""', "_", str(SKILL / "scripts" / "_lib.sh")],
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=10,
    )
    bank = os.path.join(cwd, out.stdout.strip())  # the resolver may answer relative to cwd
    return os.path.realpath(bank) if out.returncode == 0 and out.stdout.strip() and os.path.isdir(bank) else ""


def register(sid: str, cwd: str) -> None:
    bank = resolve_bank(cwd)
    if not bank:
        return
    top = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    tree = os.path.realpath(top.stdout.strip() if top.returncode == 0 else os.path.dirname(bank))
    path = state_file(sid)
    old = json.loads(path.read_text()) if path.exists() else {}
    if old.get("bank") != bank or old.get("tree") != tree:
        save(path, {**old, "bank": bank, "tree": tree})


def orchestrator(payload: dict) -> dict | None:
    sid, cwd = str(payload.get("session_id") or ""), str(payload.get("cwd") or os.getcwd())
    path = state_file(sid) if sid else None
    st = json.loads(path.read_text()) if path and path.exists() else None
    if st is None and os.environ.get("MB_ORCHESTRATOR") == "1":
        bank = resolve_bank(cwd)
        st = {"bank": bank, "tree": os.path.dirname(bank)} if bank else None
    if not st:
        return None
    cfg = Path(st["bank"]) / ".mb-config"
    if cfg.is_file() and re.search(
        r"^\s*team_guard\s*=\s*(off|0|false|no)\s*$", cfg.read_text(), re.M | re.I
    ):
        return None
    return st


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }
        )
    )


def once(sid: str, key: str) -> bool:
    """True the first time `key` is seen for this session (and remembers it)."""
    path = state_file(sid)
    st = json.loads(path.read_text()) if path.exists() else {}
    seen = st.setdefault("seen", [])
    if key in seen:
        return False
    st["seen"] = (seen + [key])[-200:]
    save(path, st)
    return True


def inside(path: str, root: str) -> bool:
    return path == root or path.startswith(root.rstrip("/") + "/")


def on_edit(payload: dict, st: dict) -> None:
    ti = payload.get("tool_input") or {}
    target = ti.get("file_path") or ti.get("notebook_path") or ""
    if not target:
        return
    full = os.path.realpath(os.path.join(str(payload.get("cwd") or ""), target))
    if inside(full, st["tree"]) and not inside(full, st["bank"]):
        deny(
            f"MB Team orchestrator: you do not edit code yourself ({target}) — delegate this as a track "
            f"(`team track add <id> --followup --task … --dod … --files …` reopens a closed team; run it through "
            f"the mb-team-track Workflow). Bank files stay editable. Off only on the user's explicit request: "
            f"team_guard=off in {st['bank']}/.mb-config or MB_TEAM_GUARD=off."
        )


def on_bash(payload: dict, sid: str) -> None:
    cmd = str((payload.get("tool_input") or {}).get("command") or "")
    if TEAM_CMD.search(cmd) and sid:
        register(sid, str(payload.get("cwd") or os.getcwd()))
    if not GIT_COMMIT.search(cmd):
        return
    st = orchestrator(payload)
    if not st or not once(sid or "env", "commit:" + hashlib.sha1(cmd.encode()).hexdigest()[:12]):
        return
    board = subprocess.run(
        ["bash", str(SKILL / "scripts" / "mb-coord.sh"), "active", "--mb", st["bank"]],
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout.strip()
    deny(
        "MB Team orchestrator: track work is committed with `team commit --tracks <ids> -m <msg>` (scoped to "
        "the tracks' globs, rules gate, board COMMIT entry; only after the user's yes). Board "
        f"(mb-coord.sh active):\n{board[:3000]}\nIf this commit is not track work (bank, docs the user asked "
        "for) and the board allows it, run the same command again."
    )


def on_stop(payload: dict, sid: str, st: dict) -> None:
    if payload.get("stop_hook_active"):
        return
    bank = Path(st["bank"])
    teams = list((bank / "reports").glob("*/team.json"))
    if not teams:
        return
    changes = [p.stat().st_mtime for p in teams]
    if (
        any(not json.loads(p.read_text()).get("closed") for p in teams)
        and (bank / "COORDINATION.md").exists()
    ):
        changes.append((bank / "COORDINATION.md").stat().st_mtime)
    console = bank / "orchestrator-console.md"
    newest = max(changes)
    why = []
    if not console.exists() or console.stat().st_mtime < newest:
        why.append(
            "orchestrator-console.md is older than the last team.json / board change: update Open "
            "questions, Running, Next and Unrecorded decisions (track lines are written by `track set`)"
        )
    cap = subprocess.run(
        ["bash", str(SKILL / "scripts" / "mb-console.sh"), "check", "--mb", str(bank)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if cap.returncode == 1:
        why.append(cap.stderr.strip())
    if why and once(sid, f"stop:{int(newest)}:{cap.returncode}"):
        print(json.dumps({"decision": "block", "reason": "MB Team console: " + "; ".join(why)}))


def main() -> None:
    if os.environ.get("MB_TEAM_GUARD", "on").lower() in ("off", "0", "false", "no"):
        return
    payload = json.loads(sys.stdin.read() or "{}")
    if not isinstance(payload, dict) or payload.get("agent_id"):
        return
    sid, event = str(payload.get("session_id") or ""), payload.get("hook_event_name")
    tool = payload.get("tool_name")
    if event == "PreToolUse" and tool == "Bash":
        on_bash(payload, sid)
        return
    st = orchestrator(payload)
    if not st:
        return
    if event == "PreToolUse" and tool in EDIT_TOOLS:
        on_edit(payload, st)
    elif event == "Stop" and sid:
        on_stop(payload, sid, st)


if __name__ == "__main__":
    with contextlib.suppress(Exception):  # a guard must never break the host session
        main()
    sys.exit(0)
